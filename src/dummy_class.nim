# dummy_class.nim

# Forward declaration so Dummy can call GffStruct methods
proc findTlkStrings*(self: GffStruct, ctx: GffFileContext, index: uint32, parent: Dummy = nil)

proc readTlkString(ctx: GffFileContext, index: uint32, trace: string) =
  let tlkstring_index = cast[ptr uint32](ctx.base_addr + index.int)[]
  let ref_val = cast[ptr uint32](ctx.base_addr + index.int + 4)[]
  let translated = ctx.translations.findTranslation(ctx.resource_key, tlkstring_index)
  let discovering = ctx.discovered != nil

  # Keep this format observation: a reference value of 0xFFFFFFFF has been
  # reported to advance dialogue automatically, whereas 0 means no embedded
  # line. Never turn the sentinel into zero merely because it is a core ID.
  if ref_val == 0 or ref_val == 0xFFFFFFFF'u32:
    # An explicit master value can repair a reference zeroed by an older run.
    # Discovery cannot recover text which is no longer reachable.
    if not discovering and translated.found:
      ctx.string_sites.add(Gff4StringSite(
        ref_offset: index + 4,
        string_ref: tlkstring_index,
        embedded_line: ""
      ))
    return

  let shouldDiscover = discovering and tlkstring_index >= CustomStringRefBase
  let shouldTranslate = not discovering and translated.found
  let shouldClearCore = not discovering and not translated.found and
    tlkstring_index < CustomStringRefBase

  # Do not decode or retain the thousands of unrelated TLK strings. Discovery
  # needs mod-authored source text; rewriting needs only selected master IDs or
  # a core-ID reference which must be cleared.
  if not shouldDiscover and not shouldTranslate and not shouldClearCore:
    return

  if shouldClearCore:
    ctx.string_sites.add(Gff4StringSite(
      ref_offset: index + 4,
      string_ref: tlkstring_index,
      embedded_line: ""
    ))
    return

  let tlkstring_offset = ref_val + ctx.data_offset
  let length = cast[ptr uint32](ctx.base_addr + tlkstring_offset.int)[]
  let char_data_ptr = cast[ptr UncheckedArray[uint16]](ctx.base_addr + tlkstring_offset.int + 4)
  var units: seq[uint16]
  if length > 0:
    units = newSeq[uint16]((length - 1).int)
    for i in 0 ..< units.len:
      units[i] = char_data_ptr[i]
  let line = units.fromUtf16Units()

  if shouldTranslate:
    ctx.string_sites.add(Gff4StringSite(
      ref_offset: index + 4,
      string_ref: tlkstring_index,
      embedded_line: line
    ))

  if shouldDiscover and line != "":
    ctx.discovered.recordDiscovered(
      ctx.resource_key,
      tlkstring_index,
      line,
      ctx.erf_filename & " -> " & ctx.filename & " -> /" & trace
    )

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
      raise newException(ValueError, "A struct shouldn't be a reference.")
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
        raise newException(ValueError, "A tlkstring shouldn't be a reference.")
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
        raise newException(ValueError, "A generic must be either a list or a reference.")
    else:
      raise newException(ValueError, "Wrong type-id encountered: " & $self.type_id)
