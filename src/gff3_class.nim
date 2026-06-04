# gff3_class.nim

type
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
    tlkDict*: TableRef[uint32, TlkEntry]

template readUint32(self: Gff3File, offset: uint32): uint32 =
  cast[ptr uint32](self.baseAddr + offset.int)[]

template writeUint32(self: Gff3File, offset: uint32, val: uint32) =
  cast[ptr uint32](self.baseAddr + offset.int)[] = val

proc readHeader(self: Gff3File) =
  var fileVer = newString(4)
  copyMem(addr fileVer[0], cast[pointer](self.baseAddr + 4), 4)
  doAssert fileVer == "V3.2", "Unsupported Version: " & fileVer

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

proc initGff3File*(erf_filename: string, filepath: string, tlkDict: TableRef[uint32, TlkEntry]): Gff3File =
  new(result)
  result.erf_filename = extractFilename(erf_filename)
  result.filepath = filepath
  result.filename = extractFilename(filepath)
  result.mm = openMemFile(file_path)
  result.baseAddr = cast[int](result.mm.mem)
  result.visited_structs = initHashSet[uint32]()
  result.tlkDict = tlkDict
  result.readHeader()

proc initGff3FileFromStream*(data: sink string, erf_filename: string, filepath: string, tlkDict: TableRef[uint32, TlkEntry]): Gff3File =
  new(result)
  result.erf_filename = extractFilename(erf_filename)
  result.filepath = filepath
  result.filename = extractFilename(filepath)
  result.mm = openMemStream(data)
  result.baseAddr = cast[int](result.mm.mem)
  result.visited_structs = initHashSet[uint32]()
  result.tlkDict = tlkDict
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
    
    if string_ref >= 610000000'u32 and string_ref != 0xFFFFFFFF'u32:
      let string_count = self.readUint32(loc_start + 8)
      var extractedStr = ""
      
      # Extract the first CExoString if it exists
      if string_count > 0:
        let str_len = self.readUint32(loc_start + 16)
        if str_len > 0:
          let str_data_ptr = cast[ptr UncheckedArray[char]](self.baseAddr + loc_start.int + 20)
          extractedStr = newString(str_len)
          copyMem(addr extractedStr[0], str_data_ptr, str_len)
          
      # Patch logic from old_gff_patcher.py: length = 8, string_count = 0
      self.writeUint32(loc_start, 8)
      self.writeUint32(loc_start + 8, 0)
      
      if extractedStr != "":
        let trace = self.erf_filename & " -> " & self.filename & " -> /" & current_path.join("/") & ":CExoLocString"
        self.tlkDict[string_ref] = TlkEntry(line: extractedStr, node_path: trace)

  discard current_path.pop()

proc findTlkStrings*(self: Gff3File) =
  if self.struct_count > 0:
    var path = newSeq[string]()
    self.processStruct(0, path)

proc close*(self: Gff3File) =
  self.mm.close()