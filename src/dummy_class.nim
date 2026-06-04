# dummy_class.nim

# Forward declaration so Dummy can call GffStruct methods
proc findTlkStrings*(self: GffStruct, ctx: GffFileContext, index: uint32, parent: Dummy = nil)

proc readTlkString(ctx: GffFileContext, index: uint32, trace: string) =
  let tlkstring_index = cast[ptr uint32](ctx.base_addr + index.int)[]
  let ref_ptr = cast[ptr uint32](ctx.base_addr + index.int + 4) # Notice we get the pointer, not the value
  let ref_val = ref_ptr[]

  if ref_val == 0 or ref_val == 0xFFFFFFFF'u32: return
  # we make sure the reference is a regular one

  if tlkstring_index >= 610000000'u32:
    let tlkstring_offset = ref_ptr[] + ctx.data_offset
    let length = cast[ptr uint32](ctx.base_addr + tlkstring_offset.int)[]
    
    # Read UTF-16LE string directly from memory
    # length includes the trailing null terminator, so we iterate up to length - 1 (Python's [:-1])
    let char_data_ptr = cast[ptr UncheckedArray[uint16]](ctx.base_addr + tlkstring_offset.int + 4)
    
    # Reserve enough bytes assuming standard text, avoiding the null terminator
    var line = newStringOfCap((length - 1) * 2)
    
    for i in 0 ..< (length - 1):
      line.add($Rune(char_data_ptr[i]))
    
    ctx.tlkDict[tlkstring_index] = TlkEntry(
      line: line,
      node_path: ctx.erf_filename & " -> " & ctx.filename & " -> /" & trace
    )
  
  ref_ptr[] = 0'u32 # Instantly mutate the memory
  # for reference, 0xFFFFFFFF was reported to automatically move the dialogue forward, while 0 doesnt

proc readList(ctx: GffFileContext, index: uint32): tuple[length: uint32, offset: uint32] =
  let ref_val = cast[ptr uint32](ctx.base_addr + index.int)[]
  if ref_val == 0 or ref_val == 0xFFFFFFFF'u32: return (0'u32, 0'u32)
  let list_offset = ref_val + ctx.data_offset
  let length = cast[ptr uint32](ctx.base_addr + list_offset.int)[]
  # list_offset + 4, because we're pointing to the data, not to the length
  return (length, list_offset + 4)

proc readGeneric(ctx: GffFileContext, index: uint32): Dummy =
  let field_type_id = cast[ptr uint16](ctx.base_addr + index.int)[]
  let field_flags = cast[ptr uint16](ctx.base_addr + index.int + 2)[]
  let ref_offset = cast[ptr uint32](ctx.base_addr + index.int + 4)[]

  if field_type_id == 0xFFFF and field_flags == 0xFFFF or ref_offset == 0 or ref_offset == 0xFFFFFFFF'u32:
    return nil

  let is_list = (field_flags shr 15) == 1
  let is_struct = ((field_flags shr 14) and 1) == 1
  let is_reference = ((field_flags shr 13) and 1) == 1

  if (is_struct and ctx.structArray[field_type_id].shouldParse) or 
     (not is_struct and (field_type_id == 17 or field_type_id == 0xFFFF)):
    return Dummy(label: 0, type_id: field_type_id, index: ref_offset, 
                 is_list: is_list, is_struct: is_struct, is_reference: is_reference)
  return nil

proc findTlkStrings*(self: Dummy, ctx: GffFileContext, index: uint32) =
  let real_index = index + self.index

  if self.is_struct:
    let mstruct = ctx.struct_array[self.type_id]
    if self.is_list:
      let (length, offset_val) = readList(ctx, real_index)
      var current_offset = offset_val
      for i in 0 ..< length:
        mstruct.findTlkStrings(ctx, current_offset, self)
        current_offset += mstruct.size
    elif self.is_reference:
      quit("Error: A struct shouldn't be a reference.")
    else:
      mstruct.findTlkStrings(ctx, real_index, self)
  else:
    if self.type_id == 17:
      let trace = getNodePath(self, ctx.struct_array)
      if self.is_list:
        let (length, offset_val) = readList(ctx, real_index)
        var current_offset = offset_val
        for i in 0 ..< length:
          # tlkstrings are pairs of index: u32, offset: u32
          readTlkString(ctx, current_offset, trace)
          current_offset += 8
      elif self.is_reference:
        quit("Error: A tlkstring shouldn't be a reference.")
      else:
        readTlkString(ctx, real_index, trace)
        
    elif self.type_id == 0xFFFF:
      if self.is_list:
        let (length, offset_val) = readList(ctx, real_index)
        var current_offset = offset_val
        for i in 0 ..< length:
          let generic_dummy = readGeneric(ctx, current_offset)
          if generic_dummy != nil:
            generic_dummy.parent = self
            generic_dummy.findTlkStrings(ctx, ctx.data_offset)
          current_offset += 8
      elif self.is_reference:
        let generic_dummy = readGeneric(ctx, real_index)
        if generic_dummy != nil:
          generic_dummy.parent = self
          generic_dummy.findTlkStrings(ctx, ctx.data_offset)
      else:
        quit("Error: A generic must be either a list or a reference.")
    else:
      quit("Error: Wrong type-id encountered.")