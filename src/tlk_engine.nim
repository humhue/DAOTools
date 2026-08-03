# tlk_engine.nim

# =====================================================================
# JSON UTILITIES
# =====================================================================

proc encodeTlkstringsJson*(tlkstrings: TableRef[uint32, TlkEntry], mapfilePath: string) =
  # Recreates: outer_dict = {"tlkstrings": tlkstrings}
  var outerObj = newJObject()
  var tlkObj = newJObject()
  
  for k, v in tlkstrings.pairs:
    var entryObj = newJObject()
    entryObj["line"] = newJString(v.line)
    entryObj["node_path"] = newJString(v.node_path)
    tlkObj[$k] = entryObj
    
  outerObj["tlkstrings"] = tlkObj
  writeFile(mapfilePath, outerObj.pretty())

proc decodeTlkstringsJson*(mapfilePath: string): TableRef[uint32, TlkEntry] =
  # Recreates: {k: v["line"] for k, v in outer_dict["tlkstrings"].items()}
  result = newTable[uint32, TlkEntry]()
  let root = parseFile(mapfilePath)
  let tlkObj = root["tlkstrings"]
  
  for k, v in tlkObj.pairs:
    let line = v["line"].getStr()
    # Handle missing node_path safely just in case the JSON was hand-edited
    let nodePath = if v.hasKey("node_path"): v["node_path"].getStr() else: ""
    result[k.parseUInt.uint32] = TlkEntry(line: line, node_path: nodePath)

proc genMapfile*(mapfilePath: string, extractedTlkstrings: TableRef[uint32, TlkEntry]): bool =
  # Recreates NEW_TLKSTRINGS.update(old_tlkstrings)
  if extractedTlkstrings.len == 0:
    return false

  encodeTlkstringsJson(extractedTlkstrings, mapfilePath)
  return true

# =====================================================================
# TLK BINARY GENERATOR
# =====================================================================

# Binary writers. These MUST be procs, not templates: a template splices the
# argument expression into its body and re-types it in the caller's context, so
# an untyped literal keeps its default `int` type and Stream.write[T] emits
# sizeof(int) == 8 bytes instead of 4 or 2. A proc parameter converts at the
# call boundary, which is what the GFF4 layout requires.
proc writeU32(strm: Stream, val: uint32) = strm.write(val)
proc writeU16(strm: Stream, val: uint16) = strm.write(val)
proc writeChars(strm: Stream, val: string) = strm.write(val)

# ECStrings are counted and stored in UTF-16 code units, not code points, so
# anything outside the BMP has to become a surrogate pair here. Doing the
# conversion once also guarantees the offset pass and the payload pass agree.
proc toUtf16Units(s: string): seq[uint16] =
  result = newSeqOfCap[uint16](s.len)
  for r in s.runes:
    let cp = r.int.uint32
    if cp <= 0xFFFF'u32:
      result.add(cp.uint16)
    else:
      let v = cp - 0x10000'u32
      result.add((0xD800'u32 + (v shr 10)).uint16)
      result.add((0xDC00'u32 + (v and 0x3FF'u32)).uint16)

proc genTlkFile*(mapfilePath: string, tlkfilePath: string): bool =
  let entries = decodeTlkstringsJson(mapfilePath)
  let n_entries = entries.len.uint32
  
  if n_entries == 0:
    return false

  var strm = newFileStream(tlkfilePath, fmWrite)
  if strm == nil: quit("Error: Could not open output file.")

  # --- CALCULATE OFFSETS ---
  let headerSize = 28'u32
  let bufStructArraySize = 32'u32 # TLK (16 bytes) + STRN (16 bytes)
  let bufFieldArraySize = 36'u32  # 3 fields * 12 bytes each
  let dataOffset = headerSize + bufStructArraySize + bufFieldArraySize # 96 (\x60)

  # --- 1. WRITE HEADER ---
  strm.writeChars("GFF V4.0PC  TLK V0.2")
  strm.writeU32(2'u32)       # struct_count
  strm.writeU32(dataOffset)  # offset to data block

  # --- 2. WRITE STRUCT ARRAY ---
  # A struct entry is type[4], field_count, field_offset, struct_size — in that order.
  strm.writeChars("TLK ")
  strm.writeU32(1'u32)     # number of fields
  strm.writeU32(60'u32)    # offset to the first field (60 = 28 + 32), \x3C
  strm.writeU32(4'u32)     # size
  strm.writeChars("STRN")
  strm.writeU32(2'u32)     # number of fields
  strm.writeU32(72'u32)    # offset to the first field (60 + 12), \x48
  strm.writeU32(8'u32)     # size

  # --- 3. WRITE FIELD ARRAY ---
  # TLK
  strm.writeU32(19001'u32) # label, TALK_STRING_LIST
  strm.writeU16(1'u16)     # type_id, list of STRN
  strm.writeU16(49152'u16) # flags, is_list and is_struct
  strm.writeU32(0'u32)     # index
  # STRN
  strm.writeU32(19002'u32) # label, TALK_STRING_ID
  strm.writeU16(4'u16)     # type_id, uint32
  strm.writeU16(0'u16)     # flags
  strm.writeU32(0'u32)     # index
  strm.writeU32(19003'u32) # label, TALK_STRING
  strm.writeU16(14'u16)    # type_id, ECString
  strm.writeU16(0'u16)     # flags
  strm.writeU32(4'u32)     # index

  # --- 4. WRITE DATA BLOCK ---
  # a list is a reference, but its entries aren't
  # we create the reference to the list at 4 + data_offset (96)
  strm.writeU32(4'u32)
  strm.writeU32(n_entries) # which is here

  # --- 5. WRITE STRN INDICES ---
  let entrySize = 8'u32 # uint32 (stringRef ID) and reference to ECString

  # diff = current_length + length_of_data_generated_by_the_next_for_loop
  let diff = 8'u32 + (entrySize * n_entries)
  var acc = 0'u32

  # we convert the table to a sequence to guarantee iteration order matches python
  # the UTF-16 payload is built here so the offset pass below measures the exact
  # bytes the string pass writes
  var seqEntries: seq[tuple[id: uint32, units: seq[uint16]]]
  for k, v in entries.pairs:
    seqEntries.add((k, v.line.toUtf16Units()))

  # Explicitly sort the entries by ID ascending (Crucial for BioWare engine lookups)
  seqEntries.sort(proc (x, y: auto): int = cmp(x.id, y.id))

  # create STRNs (uint32, ref to string)
  for i, entry in seqEntries:
    strm.writeU32(entry.id)

    # + 4 * i accounts for the 4-byte length DWORD preceding every string
    strm.writeU32(diff + (4'u32 * i.uint32) + acc)

    # acc += utf16 string size in bytes, zero-terminated
    let utf16CharCount = entry.units.len + 1
    acc += (utf16CharCount.uint32 * 2'u32)

  # --- 6. WRITE ACTUAL STRINGS ---
  for entry in seqEntries:
    # First DWORD is length in wchar (including the null terminator)
    strm.writeU32((entry.units.len + 1).uint32)

    # Write UTF-16LE code units
    for u in entry.units:
      strm.writeU16(u)

    # Write Null Terminator \x00\x00
    strm.writeU16(0'u16)

  strm.close()
  return true