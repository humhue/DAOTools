# gff4_class.nim

proc findTlkStrings*(self: GffStruct, ctx: GffFileContext, index: uint32, parent: Dummy = nil) =
  for dummy in self.list:
    dummy.parent = parent
    dummy.findTlkStrings(ctx, index)

proc genGffStruct*(self: GffFile, index: uint32): GffStruct =
  if self.struct_array[index] != nil: return self.struct_array[index]

  let struct_data_offset = self.struct_array_data_offset + (index * 16)
  
  var struct_type_bytes: array[4, char]
  copyMem(addr struct_type_bytes, cast[pointer](self.base_addr + struct_data_offset.int), 4)
  let struct_type = toString(struct_type_bytes)
  
  let field_count = cast[ptr uint32](self.base_addr + struct_data_offset.int + 4)[]
  let field_offset = cast[ptr uint32](self.base_addr + struct_data_offset.int + 8)[]
  let struct_size = cast[ptr uint32](self.base_addr + struct_data_offset.int + 12)[]

  var gffstruct = GffStruct(struct_type: struct_type, size: struct_size, field_count: field_count, list: newSeqOfCap[Dummy](field_count), should_parse: false)
  var counter = 0

  for i in 0 ..< field_count:
    let field_addr = self.base_addr + field_offset.int + (i * 12).int
    let field_label = cast[ptr uint32](field_addr)[]
    let field_type_id = cast[ptr uint16](field_addr + 4)[]
    let field_flags = cast[ptr uint16](field_addr + 6)[]
    let field_index = cast[ptr uint32](field_addr + 8)[]

    let is_list = (field_flags shr 15) == 1
    let is_struct = ((field_flags shr 14) and 1) == 1
    let is_reference = ((field_flags shr 13) and 1) == 1

    if (is_struct and self.genGffStruct(field_type_id).should_parse) or
       (not is_struct and (field_type_id == 17 or field_type_id == 0xFFFF)):
      let dummy = Dummy(label: field_label, type_id: field_type_id, index: field_index, is_list: is_list, is_struct: is_struct, is_reference: is_reference)
      gffstruct.list.add(dummy)
      # set should_parse to true also avoiding unnecessary write ops
      if counter == 0: gffstruct.should_parse = true
      counter += 1
  
  # Truncate the sequence to exactly the number of valid dummies found (useless micropt)
  gffstruct.list.setLen(counter)
  self.struct_array[index] = gffstruct
  return gffstruct

proc initGff4File*(erf_file_path: string, file_path: string,
                   discovered: DiscoveryIndex = nil,
                   translations: TranslationIndex = nil): GffFile =
  new(result)
  result.erf_file_path = erf_file_path
  result.file_path = file_path
  result.resource_key = makeResourceKey(erf_file_path, file_path)
  result.discovered = discovered
  result.translations = translations
  result.mm = openMemFile(file_path)
  result.baseAddr = cast[int](result.mm.mem)

  let gff_magic = cast[ptr array[4, char]](result.baseAddr)[]
  let gff_version = cast[ptr array[4, char]](result.baseAddr + 4)[]
  let platform = cast[ptr array[4, char]](result.baseAddr + 8)[]
  
  if toString(gff_magic) != "GFF " or toString(gff_version) != "V4.0" or toString(platform) != "PC  ":
    raise newException(ValueError, "Invalid GFF4 header signature in " & extractFilename(file_path))

  let struct_array_count = cast[ptr uint32](result.baseAddr + 20)[]
  result.data_offset = cast[ptr uint32](result.baseAddr + 24)[]
  result.struct_array_data_offset = 28

  result.struct_array = newSeq[GffStruct](struct_array_count)
  for index in 0'u32 ..< struct_array_count:
    discard result.genGffStruct(index)

proc initGff4FileFromStream*(data: sink string, erf_file_path: string, file_path: string,
                             discovered: DiscoveryIndex = nil,
                             translations: TranslationIndex = nil): GffFile =
  new(result)
  result.erf_file_path = erf_file_path
  result.file_path = file_path
  result.resource_key = makeResourceKey(erf_file_path, file_path)
  result.discovered = discovered
  result.translations = translations
  result.mm = openMemStream(data)
  result.baseAddr = cast[int](result.mm.mem)

  let gff_magic = cast[ptr array[4, char]](result.baseAddr)[]
  let gff_version = cast[ptr array[4, char]](result.baseAddr + 4)[]
  let platform = cast[ptr array[4, char]](result.baseAddr + 8)[]
  
  if toString(gff_magic) != "GFF " or toString(gff_version) != "V4.0" or toString(platform) != "PC  ":
    raise newException(ValueError, "Invalid GFF4 header signature in " & extractFilename(file_path))

  let struct_array_count = cast[ptr uint32](result.baseAddr + 20)[]
  result.data_offset = cast[ptr uint32](result.baseAddr + 24)[]
  result.struct_array_data_offset = 28

  result.struct_array = newSeq[GffStruct](struct_array_count)
  for index in 0'u32 ..< struct_array_count:
    discard result.genGffStruct(index)

proc findTlkStrings*(self: GffFile) =
  let n_root_elements = self.struct_array[0].list.len
  if n_root_elements > 0:
    let ctx = GffFileContext(
      data_offset: self.data_offset, 
      erf_filename: extractFilename(self.erf_file_path), # Used Python's os.path.basename equivalent
      filename: extractFilename(self.file_path), 
      resource_key: self.resource_key,
      base_addr: self.base_addr, 
      struct_array: self.struct_array,
      discovered: self.discovered,
      translations: self.translations
    )
    self.struct_array[0].findTlkStrings(ctx, ctx.data_offset, nil)
    self.string_sites = ctx.string_sites

proc rewriteTranslations*(self: GffFile, translations: TranslationIndex): string =
  ## GFF4 references are relative to the raw data block and the format has no
  ## data-size field, so new ECStrings can be appended at EOF. Build the output
  ## only after traversal so MemBuffer.mem/base_addr never become stale.
  if self.mm.kind != msString:
    raise newException(ValueError, "GFF4 rewriting requires an owned stream buffer")

  # Take the original allocation instead of keeping it alive while constructing
  # another full-size copy. Appends may now reallocate safely: traversal is over
  # and no mmap/baseAddr pointer is read again.
  result = self.mm.takeStreamData()

  for site in self.string_sites:
    let translated = translations.findTranslation(self.resource_key, site.string_ref)
    if translated.found:
      if translated.line == site.embedded_line:
        continue
      let absoluteOffset = result.len
      if absoluteOffset < self.data_offset.int:
        raise newException(ValueError, "Invalid GFF4 data offset in " & extractFilename(self.file_path))
      # translated.line stays owned by the reusable TranslationIndex. The
      # encoder borrows it and writes straight into the resource buffer.
      result.appendEcString(translated.line)
      result.writeU32At(
        site.ref_offset.int,
        (absoluteOffset - self.data_offset.int).uint32)
    elif site.string_ref < CustomStringRefBase:
      # Core IDs resolve through the installed language's shipped talk table.
      result.writeU32At(site.ref_offset.int, 0'u32)

proc close*(self: GffFile) =
  self.mm.close()
