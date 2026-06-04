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

proc genTlkFile*(mapfilePath: string, tlkfilePath: string): bool =
  let entries = decodeTlkstringsJson(mapfilePath)
  let n_entries = entries.len.uint32
  
  if n_entries == 0:
    return false

  var strm = newFileStream(tlkfilePath, fmWrite)
  if strm == nil: quit("Error: Could not open output file.")

  # Helper templates to cleanly write native binary data without struct.pack
  template writeU32(val: uint32) = strm.write(val)
  template writeU16(val: uint16) = strm.write(val)
  template writeChars(val: string) = strm.write(val)

  # --- CALCULATE OFFSETS ---
  let headerSize = 28'u32
  let bufStructArraySize = 32'u32 # TLK (16 bytes) + STRN (16 bytes)
  let bufFieldArraySize = 36'u32  # 3 fields * 12 bytes each
  let dataOffset = headerSize + bufStructArraySize + bufFieldArraySize # 96 (\x60)

  # --- 1. WRITE HEADER ---
  writeChars("GFF V4.0PC  TLK V0.2")
  writeU32(2)          # struct_count
  writeU32(dataOffset) # offset to data block

  # --- 2. WRITE STRUCT ARRAY ---
  writeChars("TLK ")
  writeU32(60)    # offset to the first field (60 = 28 + 32), \x3C
  writeU32(1)     # number of fields
  writeU32(4)     # size
  writeChars("STRN")
  writeU32(2)     # number of fields
  writeU32(72)    # offset to the first field (60 + 12), \x48
  writeU32(8)     # size

  # --- 3. WRITE FIELD ARRAY ---
  # TLK
  writeU32(19001) # label, TALK_STRING_LIST
  writeU16(1)     # type_id, list of STRN
  writeU16(49152) # flags, is_list and is_struct
  writeU32(0)     # index
  # STRN
  writeU32(19002) # label, TALK_STRING_ID
  writeU16(4)     # type_id, uint32
  writeU16(0)     # flags
  writeU32(0)     # index
  writeU32(19003) # label, TALK_STRING
  writeU16(14)    # type_id, ECString
  writeU16(0)     # flags
  writeU32(4)     # index

  # --- 4. WRITE DATA BLOCK ---
  # a list is a reference, but its entries aren't
  # we create the reference to the list at 4 + data_offset (96)
  writeU32(4)
  writeU32(n_entries) # which is here

  # --- 5. WRITE STRN INDICES ---
  let entrySize = 8'u32 # uint32 (stringRef ID) and reference to ECString
  
  # diff = current_length + length_of_data_generated_by_the_next_for_loop
  let diff = 8'u32 + (entrySize * n_entries)
  var acc = 0'u32

  # we convert the table to a sequence to guarantee iteration order matches python
  # we extract JUST the line string here to keep the binary loop simple
  var seqEntries: seq[tuple[id: uint32, line: string]]
  for k, v in entries.pairs:
    seqEntries.add((k, v.line))
    
  # Explicitly sort the entries by ID ascending (Crucial for BioWare engine lookups)
  seqEntries.sort(proc (x, y: auto): int = cmp(x.id, y.id))

  # create STRNs (uint32, ref to string)
  for i, entry in seqEntries:
    writeU32(entry.id)
    
    # + 4 * i accounts for the 4-byte length DWORD preceding every string
    writeU32(diff + (4'u32 * i.uint32) + acc) 
    
    # acc += utf16 string size in bytes, zero-terminated
    # runes.len perfectly mimics Python's len(line) code unit count for standard BMP text
    let utf16CharCount = entry.line.toRunes().len + 1 
    acc += (utf16CharCount.uint32 * 2'u32) 

  # --- 6. WRITE ACTUAL STRINGS ---
  for entry in seqEntries:
    let runes = entry.line.toRunes()
    
    # First DWORD is length in wchar (including the null terminator)
    writeU32((runes.len + 1).uint32)
    
    # Write UTF-16LE characters (Cast Rune to 16-bit integer)
    for r in runes:
      writeU16(r.int.uint16)
      
    # Write Null Terminator \x00\x00
    writeU16(0)

  strm.close()
  return true