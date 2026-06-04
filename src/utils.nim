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

proc loadIdsAndNames*() =
  # Read the file AT COMPILE TIME and embed it in the binary
  const gffIdListStr = staticRead("GFFIDList.txt") 
  
  # the DA toolset doesn't load __deprecated__ labels, but we are doing it anyway
  # we are loading X_NO_LONGER_USED_X_GFF_ITEM_ONHIT_EFFECTID and similar as well
  # even //GFF_AREAGRID_AREA_ID
  # 2479 entries
  let pattern = re"[GC]FF(?:STRUCT)?_(\w+)\s*=\s*(\d+)"
  
  # Iterate over the embedded string instead of the file system
  for line in gffIdListStr.splitLines(): 
    var matches: array[2, string]
    if line.match(pattern, matches):
      let name = matches[0]
      let id = matches[1].parseUInt.uint32
      name_by_id[id] = name
      id_by_name[name] = id

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
      if getName(dummy.label) != "INVALIDENTRY": quit("Error: Current dummy can't have a label.")
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