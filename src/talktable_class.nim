# talktable_class.nim

type
  TalkTableStructInfo = object
    kind: string
    field_count: uint32
    field_offset: uint32
    size: uint32

  TalkTableFile = ref object
    filename: string
    resource_key: string
    mm: MemBuffer
    base_addr: int
    data_offset: uint32
    list_ref_offset: uint32
    string_struct_size: uint32
    id_offset: uint32
    line_ref_offset: uint32
    discovered: DiscoveryIndex
    translations: TranslationIndex
    string_sites: seq[Gff4StringSite]

proc requireTlkRange(self: TalkTableFile, offset, length: int) =
  if offset < 0 or length < 0 or offset > self.mm.size or
     length > self.mm.size - offset:
    raise newException(
      ValueError,
      "TLK structure is outside the resource buffer in " & self.filename)

proc tlkReadU16(self: TalkTableFile, offset: int): uint16 =
  self.requireTlkRange(offset, 2)
  cast[ptr uint16](self.base_addr + offset)[]

proc tlkReadU32(self: TalkTableFile, offset: int): uint32 =
  self.requireTlkRange(offset, 4)
  cast[ptr uint32](self.base_addr + offset)[]

proc tlkFourCc(self: TalkTableFile, offset: int): string =
  self.requireTlkRange(offset, 4)
  result = newString(4)
  copyMem(addr result[0], cast[pointer](self.base_addr + offset), 4)

proc findTalkTableLayout(self: TalkTableFile) =
  self.requireTlkRange(0, 28)
  if self.tlkFourCc(0) != "GFF " or self.tlkFourCc(4) != "V4.0" or
     self.tlkFourCc(8) != "PC  " or self.tlkFourCc(12) != "TLK ":
    raise newException(ValueError, "Invalid DAO TLK header in " & self.filename)

  let structCount = self.tlkReadU32(20)
  self.data_offset = self.tlkReadU32(24)
  if structCount == 0 or self.data_offset.int > self.mm.size:
    raise newException(ValueError, "Invalid DAO TLK layout in " & self.filename)

  var structs = newSeq[TalkTableStructInfo](structCount.int)
  var rootIndex = -1
  var stringIndex = -1
  for i in 0 ..< structCount.int:
    let offset = 28 + (i * 16)
    self.requireTlkRange(offset, 16)
    structs[i] = TalkTableStructInfo(
      kind: self.tlkFourCc(offset),
      field_count: self.tlkReadU32(offset + 4),
      field_offset: self.tlkReadU32(offset + 8),
      size: self.tlkReadU32(offset + 12)
    )
    if structs[i].kind == "TLK ": rootIndex = i
    elif structs[i].kind == "STRN": stringIndex = i

  if rootIndex != 0 or stringIndex < 0:
    raise newException(ValueError, "DAO TLK is missing TLK/STRN structures in " & self.filename)

  var foundList = false
  let root = structs[rootIndex]
  for i in 0 ..< root.field_count.int:
    let offset = root.field_offset.int + (i * 12)
    self.requireTlkRange(offset, 12)
    let label = self.tlkReadU32(offset)
    let fieldType = self.tlkReadU16(offset + 4)
    let flags = self.tlkReadU16(offset + 6)
    if label == 19001'u32:
      if fieldType.int != stringIndex or (flags and 0xC000'u16) != 0xC000'u16:
        raise newException(ValueError, "Invalid TALK_STRING_LIST field in " & self.filename)
      self.list_ref_offset = self.tlkReadU32(offset + 8)
      foundList = true

  var foundId = false
  var foundLine = false
  let stringStruct = structs[stringIndex]
  self.string_struct_size = stringStruct.size
  for i in 0 ..< stringStruct.field_count.int:
    let offset = stringStruct.field_offset.int + (i * 12)
    self.requireTlkRange(offset, 12)
    let label = self.tlkReadU32(offset)
    let fieldType = self.tlkReadU16(offset + 4)
    if label == 19002'u32:
      if fieldType != 4'u16:
        raise newException(ValueError, "Invalid TALK_STRING_ID field in " & self.filename)
      self.id_offset = self.tlkReadU32(offset + 8)
      foundId = true
    elif label == 19003'u32:
      if fieldType != 14'u16:
        raise newException(ValueError, "Invalid TALK_STRING field in " & self.filename)
      self.line_ref_offset = self.tlkReadU32(offset + 8)
      foundLine = true

  if not foundList or not foundId or not foundLine or
     self.string_struct_size < 8'u32 or
     self.id_offset + 4'u32 > self.string_struct_size or
     self.line_ref_offset + 4'u32 > self.string_struct_size:
    raise newException(ValueError, "Incomplete DAO TLK schema in " & self.filename)

proc initTalkTableFileFromStream(data: sink string, containerPath,
                                 filename: string,
                                 discovered: DiscoveryIndex = nil,
                                 translations: TranslationIndex = nil): TalkTableFile =
  new(result)
  result.filename = extractFilename(filename)
  result.resource_key = makeResourceKey(containerPath, filename)
  result.discovered = discovered
  result.translations = translations
  result.mm = openMemStream(move(data))
  result.base_addr = cast[int](result.mm.mem)
  result.findTalkTableLayout()

proc readTalkTableLine(self: TalkTableFile, relativeOffset: uint32): string =
  let absoluteOffset = self.data_offset.int + relativeOffset.int
  let length = self.tlkReadU32(absoluteOffset)
  if length == 0: return ""
  let availableUnits = (self.mm.size - absoluteOffset - 4) div 2
  if length.int > availableUnits:
    raise newException(ValueError, "Invalid ECString length in " & self.filename)

  var units = newSeq[uint16]((length - 1).int)
  for i in 0 ..< units.len:
    units[i] = self.tlkReadU16(absoluteOffset + 4 + (i * 2))
  units.fromUtf16Units()

proc findTalkTableStrings(self: TalkTableFile) =
  let rootField = self.data_offset.int + self.list_ref_offset.int
  let listReference = self.tlkReadU32(rootField)
  if listReference == 0 or listReference == 0xFFFFFFFF'u32:
    return

  let listOffset = self.data_offset.int + listReference.int
  let count = self.tlkReadU32(listOffset)
  let entriesOffset = listOffset + 4
  let entrySize = self.string_struct_size.int
  if count.int > (self.mm.size - entriesOffset) div entrySize:
    raise newException(ValueError, "TLK entry list is outside the resource buffer in " & self.filename)

  let discovering = self.discovered != nil
  for i in 0 ..< count.int:
    let entryOffset = entriesOffset + (i * entrySize)
    let stringId = self.tlkReadU32(entryOffset + self.id_offset.int)
    let translated = self.translations.findTranslation(self.resource_key, stringId)
    let shouldDiscover = discovering and stringId >= CustomStringRefBase
    let shouldTranslate = not discovering and translated.found
    if not shouldDiscover and not shouldTranslate:
      continue

    let referenceOffset = entryOffset + self.line_ref_offset.int
    let lineReference = self.tlkReadU32(referenceOffset)
    if lineReference == 0 or lineReference == 0xFFFFFFFF'u32:
      if shouldTranslate:
        self.string_sites.add(Gff4StringSite(
          ref_offset: referenceOffset.uint32,
          string_ref: stringId,
          embedded_line: ""
        ))
      continue

    let line = self.readTalkTableLine(lineReference)
    if shouldTranslate:
      self.string_sites.add(Gff4StringSite(
        ref_offset: referenceOffset.uint32,
        string_ref: stringId,
        embedded_line: line
      ))
    if shouldDiscover and line != "":
      self.discovered.recordDiscovered(
        self.resource_key,
        stringId,
        line,
        self.resource_key & " -> /TALK_STRING_LIST[" & $i & "]:TALK_STRING")

proc rewriteTalkTable(self: TalkTableFile,
                      translations: TranslationIndex): string =
  result = self.mm.takeStreamData()
  for site in self.string_sites:
    let translated = translations.findTranslation(self.resource_key, site.string_ref)
    if not translated.found or translated.line == site.embedded_line:
      continue
    let absoluteOffset = result.len
    if absoluteOffset < self.data_offset.int:
      raise newException(ValueError, "Invalid DAO TLK data offset in " & self.filename)
    result.appendEcString(translated.line)
    result.writeU32At(
      site.ref_offset.int,
      (absoluteOffset - self.data_offset.int).uint32)

proc close(self: TalkTableFile) =
  self.mm.close()
