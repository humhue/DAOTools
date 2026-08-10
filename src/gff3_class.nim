# gff3_class.nim

type
  Gff3StringSite = object
    field_value_offset: uint32
    loc_offset: uint32
    string_ref: uint32
    string_id: uint32
    embedded_line: string

  Gff3File* = ref object
    filepath: string
    filename: string
    erf_filename: string
    # mm: MemFile
    mm: MemBuffer # Changed from MemFile to MemBuffer
    baseAddr: int
    struct_offset, struct_count: uint32
    field_offset, field_count: uint32
    label_offset, label_count: uint32
    field_data_offset, field_data_count: uint32
    field_indices_offset, field_indices_count: uint32
    list_indices_offset, list_indices_count: uint32
    visited_structs: HashSet[uint32]
    resource_key: string
    discovered: DiscoveryIndex
    translations: TranslationIndex
    string_sites: seq[Gff3StringSite]

template readUint32(self: Gff3File, offset: uint32): uint32 =
  cast[ptr uint32](self.baseAddr + offset.int)[]

template writeUint32(self: Gff3File, offset: uint32, val: uint32) =
  cast[ptr uint32](self.baseAddr + offset.int)[] = val

proc readHeader(self: Gff3File) =
  var fileVer = newString(4)
  copyMem(addr fileVer[0], cast[pointer](self.baseAddr + 4), 4)
  if fileVer != "V3.2":
    raise newException(ValueError, "Unsupported GFF3 version in " & self.filename & ": " & fileVer)

  var offset: uint32 = 8
  self.struct_offset = self.readUint32(offset); offset += 4
  self.struct_count = self.readUint32(offset); offset += 4
  self.field_offset = self.readUint32(offset); offset += 4
  self.field_count = self.readUint32(offset); offset += 4
  self.label_offset = self.readUint32(offset); offset += 4
  self.label_count = self.readUint32(offset); offset += 4
  self.field_data_offset = self.readUint32(offset); offset += 4
  self.field_data_count = self.readUint32(offset); offset += 4
  self.field_indices_offset = self.readUint32(offset); offset += 4
  self.field_indices_count = self.readUint32(offset); offset += 4
  self.list_indices_offset = self.readUint32(offset); offset += 4
  self.list_indices_count = self.readUint32(offset)

proc getLabel(self: Gff3File, labelIndex: uint32): string =
  let offset = self.label_offset + (labelIndex * 16)
  var labelBytes = newString(16)
  copyMem(addr labelBytes[0], cast[pointer](self.baseAddr + offset.int), 16)
  let nullPos = labelBytes.find('\x00')
  if nullPos >= 0: return labelBytes[0 ..< nullPos]
  return labelBytes

# Forward declarations
proc processStruct(self: Gff3File, struct_index: uint32, current_path: var seq[string])
proc processField(self: Gff3File, field_index: uint32, current_path: var seq[string])

proc initGff3File*(erf_filename: string, filepath: string,
                   discovered: DiscoveryIndex = nil,
                   translations: TranslationIndex = nil): Gff3File =
  new(result)
  result.erf_filename = extractFilename(erf_filename)
  result.filepath = filepath
  result.filename = extractFilename(filepath)
  result.mm = openMemFile(file_path)
  result.baseAddr = cast[int](result.mm.mem)
  result.visited_structs = initHashSet[uint32]()
  result.resource_key = makeResourceKey(erf_filename, filepath)
  result.discovered = discovered
  result.translations = translations
  result.readHeader()

proc initGff3FileFromStream*(data: sink string, erf_filename: string, filepath: string,
                             discovered: DiscoveryIndex = nil,
                             translations: TranslationIndex = nil): Gff3File =
  new(result)
  result.erf_filename = extractFilename(erf_filename)
  result.filepath = filepath
  result.filename = extractFilename(filepath)
  result.mm = openMemStream(data)
  result.baseAddr = cast[int](result.mm.mem)
  result.visited_structs = initHashSet[uint32]()
  result.resource_key = makeResourceKey(erf_filename, filepath)
  result.discovered = discovered
  result.translations = translations
  result.readHeader()

proc processStruct(self: Gff3File, struct_index: uint32, current_path: var seq[string]) =
  if self.visited_structs.contains(struct_index): return
  self.visited_structs.incl(struct_index)

  let offset = self.struct_offset + (struct_index * 12)
  let data_or_offset = self.readUint32(offset + 4)
  let field_count = self.readUint32(offset + 8)

  if field_count == 1:
    self.processField(data_or_offset, current_path)
  elif field_count > 1:
    let indices_start = self.field_indices_offset + data_or_offset
    for i in 0'u32 ..< field_count:
      let field_idx = self.readUint32(indices_start + (i * 4))
      self.processField(field_idx, current_path)

proc processField(self: Gff3File, field_index: uint32, current_path: var seq[string]) =
  let offset = self.field_offset + (field_index * 12)
  let field_type = self.readUint32(offset)
  let label_index = self.readUint32(offset + 4)
  let data_or_offset = self.readUint32(offset + 8)

  let label_name = self.getLabel(label_index)
  current_path.add(label_name)

  if field_type == 14: # Struct Type
    self.processStruct(data_or_offset, current_path)

  elif field_type == 15: # List Type
    let list_start = self.list_indices_offset + data_or_offset
    let list_size = self.readUint32(list_start)
    for i in 0'u32 ..< list_size:
      current_path.add("[" & $i & "]")
      let struct_idx = self.readUint32(list_start + 4 + (i * 4))
      self.processStruct(struct_idx, current_path)
      discard current_path.pop()

  elif field_type == 12: # CExoLocString Type
    let loc_start = self.field_data_offset + data_or_offset
    let string_ref = self.readUint32(loc_start + 4)

    if string_ref != 0xFFFFFFFF'u32:
      let translated = self.translations.findTranslation(self.resource_key, string_ref)
      let discovering = self.discovered != nil
      let shouldDiscover = discovering and string_ref >= CustomStringRefBase
      let shouldTranslate = not discovering and translated.found
      let shouldClearCore = not discovering and not translated.found and
        string_ref < CustomStringRefBase

      if shouldDiscover or shouldTranslate or shouldClearCore:
        var extractedStr = ""
        var stringId = 0'u32

        # Core-ID clearing needs only the offsets. Decode and retain source text
        # solely for interactive discovery or a master-selected equality check.
        if shouldDiscover or shouldTranslate:
          let string_count = self.readUint32(loc_start + 8)
          # Preserve the original language/gender slot when an edited line is
          # embedded again. DAO resources normally carry one fallback entry.
          if string_count > 0:
            stringId = self.readUint32(loc_start + 12)
            let str_len = self.readUint32(loc_start + 16)
            if str_len > 0:
              let str_data_ptr = cast[ptr UncheckedArray[char]](
                self.baseAddr + loc_start.int + 20)
              extractedStr = newString(str_len)
              copyMem(addr extractedStr[0], str_data_ptr, str_len)

        if not discovering:
          self.string_sites.add(Gff3StringSite(
            field_value_offset: offset + 8,
            loc_offset: loc_start,
            string_ref: string_ref,
            string_id: stringId,
            embedded_line: extractedStr
          ))

        if shouldDiscover and extractedStr != "":
          let trace = self.erf_filename & " -> " & self.filename & " -> /" &
            current_path.join("/") & ":CExoLocString"
          self.discovered.recordDiscovered(
            self.resource_key, string_ref, extractedStr, trace)

  discard current_path.pop()

proc findTlkStrings*(self: Gff3File) =
  if self.struct_count > 0:
    var path = newSeq[string]()
    self.processStruct(0, path)

proc appendLocString(data: var string, site: Gff3StringSite, line: string) =
  # length excludes its own DWORD: string ref, count, string ID, byte length,
  # then UTF-8 CExoString bytes. This is byte-counted UTF-8, so Cyrillic and
  # other non-ASCII scripts are supported; it is not a UTF-16 ECString.
  data.appendU32((16 + line.len).uint32)
  data.appendU32(site.string_ref)
  data.appendU32(1'u32)
  data.appendU32(site.string_id)
  data.appendU32(line.len.uint32)
  data.add(line)

proc rewriteTranslations*(self: Gff3File, translations: TranslationIndex): string =
  ## Rebuild once after traversal. No pointer into mm survives a string resize.
  if self.mm.kind != msString:
    raise newException(ValueError, "GFF3 rewriting requires an owned stream buffer")

  # Traversal is complete, so take ownership and invalidate the cached pointer
  # before any insertion can reallocate the backing string.
  result = self.mm.takeStreamData()
  let insertAt = (self.field_data_offset + self.field_data_count).int
  if insertAt < 0 or insertAt > result.len or
     (self.field_indices_offset != 0xFFFFFFFF'u32 and self.field_indices_offset.int < insertAt) or
     (self.list_indices_offset != 0xFFFFFFFF'u32 and self.list_indices_offset.int < insertAt):
    raise newException(ValueError, "Invalid GFF3 field-data boundaries in " & self.filename)

  var appended = newStringOfCap(256)
  var pointerPatches: seq[tuple[offset: int, value: uint32]]
  var inlineRemovalPatches: seq[tuple[lengthOffset, countOffset: int]]

  for site in self.string_sites:
    let translated = translations.findTranslation(self.resource_key, site.string_ref)
    if translated.found:
      # Cheap and important: preserve the existing allocation and pointer when
      # the imported/interactive JSON did not actually change this occurrence.
      if translated.line == site.embedded_line:
        continue
      let relativeOffset = self.field_data_count + appended.len.uint32
      pointerPatches.add((site.field_value_offset.int, relativeOffset))
      appended.appendLocString(site, translated.line)
    elif site.string_ref < CustomStringRefBase:
      # Shipped IDs should resolve through the user's localized game table.
      # Removing only the embedded override leaves the official ID untouched.
      inlineRemovalPatches.add((site.loc_offset.int, site.loc_offset.int + 8))

  # FieldIndices and ListIndices are DWORD arrays. Keep their original
  # alignment after shifting them behind the enlarged FieldData section.
  while appended.len mod 4 != 0:
    appended.add('\0')

  result.insert(appended, insertAt)

  for patch in inlineRemovalPatches:
    result.writeU32At(patch.lengthOffset, 8'u32)
    result.writeU32At(patch.countOffset, 0'u32)

  for patch in pointerPatches:
    result.writeU32At(patch.offset, patch.value)

  if appended.len > 0:
    let delta = appended.len.uint32
    result.writeU32At(36, self.field_data_count + delta)
    if self.field_indices_offset != 0xFFFFFFFF'u32:
      result.writeU32At(40, self.field_indices_offset + delta)
    if self.list_indices_offset != 0xFFFFFFFF'u32:
      result.writeU32At(48, self.list_indices_offset + delta)

proc close*(self: Gff3File) =
  self.mm.close()
