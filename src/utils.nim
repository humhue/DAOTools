# utils.nim

# Global Dictionaries
var name_by_id = initTable[uint32, string]()
var id_by_name = initTable[string, uint32]()

# Equivalent to type_string_by_type_id
proc getTypeName*(type_id: uint16): string =
  case type_id
  of 0: "uint8"
  of 1: "int8"
  of 2: "uint16"
  of 3: "int16"
  of 4: "uint32"
  of 5: "int32"
  of 6: "uint64"
  of 7: "int64"
  of 8: "float32"
  of 9: "float64"
  of 10: "Vector3f"
  of 12: "Vector4f"
  of 13: "Quaternionf"
  of 14: "ECString"
  of 15: "Color4f"
  of 16: "Matrix4x4f"
  of 17: "TLKString"
  of 0xFFFF: "Generic"
  else: "Unknown"

proc isGffIdNameChar(value: char): bool {.inline.} =
  value in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc isRegexWhitespace(value: char): bool {.inline.} =
  value in {' ', '\t', '\r', '\n', '\v', '\f'}

proc parseGffIdLine*(line: string): tuple[matched: bool, name: string, id: uint32] =
  ## Parses the same prefix accepted by the former PCRE expression:
  ## [GC]FF(?:STRUCT)?_(\w+)\s*=\s*(\d+)
  ## The source list is ASCII, and trailing comments or punctuation are allowed.
  if line.len < 4 or
      (line[0] != 'G' and line[0] != 'C') or
      line[1] != 'F' or line[2] != 'F':
    return

  var cursor = 3
  if line.len - cursor >= 6 and
      line[cursor] == 'S' and line[cursor + 1] == 'T' and
      line[cursor + 2] == 'R' and line[cursor + 3] == 'U' and
      line[cursor + 4] == 'C' and line[cursor + 5] == 'T':
    cursor += 6

  if cursor >= line.len or line[cursor] != '_':
    return
  cursor += 1

  let nameStart = cursor
  while cursor < line.len and line[cursor].isGffIdNameChar():
    cursor += 1
  if cursor == nameStart:
    return
  let nameEnd = cursor

  while cursor < line.len and line[cursor].isRegexWhitespace():
    cursor += 1
  if cursor >= line.len or line[cursor] != '=':
    return
  cursor += 1
  while cursor < line.len and line[cursor].isRegexWhitespace():
    cursor += 1

  let idStart = cursor
  while cursor < line.len and line[cursor] in {'0'..'9'}:
    cursor += 1
  if cursor == idStart:
    return

  result = (
    matched: true,
    name: line[nameStart ..< nameEnd],
    id: line[idStart ..< cursor].parseUInt().uint32
  )

proc loadIdsAndNames*() =
  # Read the file AT COMPILE TIME and embed it in the binary
  const gffIdListStr = staticRead("GFFIDList.txt") 
  
  # the DA toolset doesn't load __deprecated__ labels, but we are doing it anyway
  # we are loading X_NO_LONGER_USED_X_GFF_ITEM_ONHIT_EFFECTID and similar as well
  # even //GFF_AREAGRID_AREA_ID
  # 2441 entries

  # Iterate over the embedded string instead of the file system
  for line in gffIdListStr.splitLines():
    let parsed = line.parseGffIdLine()
    if parsed.matched:
      name_by_id[parsed.id] = parsed.name
      id_by_name[parsed.name] = parsed.id

# We call this immediately as soon as the module gets imported
loadIdsAndNames()

proc getName*(label: uint32): string =
  if name_by_id.hasKey(label): return name_by_id[label]
  return $label

proc getNodePath*(dummy: Dummy, struct_array: seq[GffStruct]): string =
  # if the current dummy is a generic
  # we dont write anything
  var val = ""
  
  if dummy.type_id != 0xFFFF:
    # if the parent of the current dummy is a generic
    # we append its label then ":generic"
    # otherwise we just append the label of the current dummy
    if dummy.parent != nil and dummy.parent.type_id == 0xFFFF:
      val = getName(dummy.parent.label) & ":generic"
      if getName(dummy.label) != "INVALIDENTRY":
        raise newException(ValueError, "Current dummy can't have a label.")
    else:
      val = getName(dummy.label)
    
    # if the current dummy is a struct
    # we append its type string
    # otherwise we append its type id string
    if dummy.is_struct:
      val &= ":" & struct_array[dummy.type_id].struct_type.strip()
    else:
      val &= ":" & getTypeName(dummy.type_id)
      
  let parent_path = if dummy.parent != nil: getNodePath(dummy.parent, struct_array) else: ""
  if val == "": return parent_path
  if parent_path == "": return val
  return parent_path & "/" & val

proc toString*(arr: array[4, char]): string =
  result = newString(4)
  for i in 0..3: result[i] = arr[i]

proc writeU32At*(data: var string, offset: int, value: uint32) =
  if offset < 0 or offset + 4 > data.len:
    raise newException(ValueError, "32-bit write is outside the resource buffer")
  data[offset] = char(value and 0xFF'u32)
  data[offset + 1] = char((value shr 8) and 0xFF'u32)
  data[offset + 2] = char((value shr 16) and 0xFF'u32)
  data[offset + 3] = char((value shr 24) and 0xFF'u32)

proc appendU32*(data: var string, value: uint32) =
  data.add(char(value and 0xFF'u32))
  data.add(char((value shr 8) and 0xFF'u32))
  data.add(char((value shr 16) and 0xFF'u32))
  data.add(char((value shr 24) and 0xFF'u32))

proc appendU16*(data: var string, value: uint16) =
  data.add(char(value and 0xFF'u16))
  data.add(char((value shr 8) and 0xFF'u16))

proc toUtf16Units*(s: string): seq[uint16] =
  ## ECStrings count and store UTF-16 code units, not Unicode code points.
  result = newSeqOfCap[uint16](s.len)
  for r in s.runes:
    let cp = r.int.uint32
    if cp <= 0xFFFF'u32:
      result.add(cp.uint16)
    else:
      let value = cp - 0x10000'u32
      result.add((0xD800'u32 + (value shr 10)).uint16)
      result.add((0xDC00'u32 + (value and 0x3FF'u32)).uint16)

proc fromUtf16Units*(units: openArray[uint16]): string =
  var i = 0
  while i < units.len:
    let first = units[i]
    if first >= 0xD800'u16 and first <= 0xDBFF'u16 and i + 1 < units.len:
      let second = units[i + 1]
      if second >= 0xDC00'u16 and second <= 0xDFFF'u16:
        let cp = 0x10000'u32 +
          ((first.uint32 - 0xD800'u32) shl 10) +
          (second.uint32 - 0xDC00'u32)
        result.add($Rune(cp))
        i += 2
        continue
    result.add($Rune(first))
    i += 1

proc utf16UnitCount(s: string): int =
  for r in s.runes:
    if r.int.uint32 <= 0xFFFF'u32: result += 1
    else: result += 2

proc appendEcString*(data: var string, line: string) =
  ## Append directly from the borrowed UTF-8 input. This avoids allocating a
  ## UTF-16 sequence and a second encoded string for every translated site.
  data.appendU32((line.utf16UnitCount() + 1).uint32)
  for r in line.runes:
    let cp = r.int.uint32
    if cp <= 0xFFFF'u32:
      data.appendU16(cp.uint16)
    else:
      let value = cp - 0x10000'u32
      data.appendU16((0xD800'u32 + (value shr 10)).uint16)
      data.appendU16((0xDC00'u32 + (value and 0x3FF'u32)).uint16)
  data.appendU16(0'u16)

proc encodeEcString*(line: string): string =
  result = newStringOfCap(4 + (line.len * 2) + 2)
  result.appendEcString(line)
