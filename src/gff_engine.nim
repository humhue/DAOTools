# gff_engine.nim

import os, tables, memfiles, strutils, unicode, sets, json

# Include the architecture
include models
include utils
include translation_engine
include dummy_class
include gff3_class
include gff4_class

when isMainModule:
  loadIdsAndNames()

  if paramCount() < 1:
    quit("Usage: ./gff_engine <path_to_gff_file>")
  
  let file_path = paramStr(1)
  if not fileExists(file_path): quit("Error: File not found.")

  for _ in 0 ..< 1000:

    let discovered = newDiscoveryIndex()
    let ext = file_path.splitFile().ext.toLowerAscii()
    
    if ext in [".are", ".lst", ".utc", ".uti", ".utm", ".utp", ".utt"]:
      let f = initGff3File("standalone", file_path, discovered)
      f.findTlkStrings()
      f.close()
    else:
      let f = initGff4File("standalone", file_path, discovered)
      f.findTlkStrings()
      f.close()

  # # Recreates: outer_dict = {"tlkstrings": tlkstrings}
  # var outerObj = newJObject()
  # var tlkObj = newJObject()
  
  # for k, v in tlkDict.pairs:
  #   var entryObj = newJObject()
  #   entryObj["line"] = newJString(v.line)
  #   entryObj["node_path"] = newJString(v.node_path)
  #   tlkObj[$k] = entryObj
    
  # outerObj["tlkstrings"] = tlkObj
  # echo $outerObj.pretty()
    
  # echo "Extracted ", tlkDict.len, " strings."
