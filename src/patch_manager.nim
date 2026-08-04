# patch_manager.nim

import os, re, tables, memfiles, strutils, unicode, sets, json, streams, algorithm, times, std/tempfiles
import zippy/ziparchives

# Include our core engine components
include models
# include mem_wrapper # included by models already
include utils
include erf_engine
include tlk_engine
include dummy_class
include gff3_class
include gff4_class

const
  ExtGff3 = [".are", ".lst", ".utc", ".uti", ".utm", ".utp", ".utt"]
  ExtGff4 = [".cub", ".cut", ".dlb", ".dlg", ".plo", ".stg", ".tlk"]
  AudioExts = [".fsb", ".fev"]
  # Everything patchFile knows how to route. Used to filter folder scans so we
  # never hand it an extension it would quit on.
  PatchableExts = @ExtGff3 & @ExtGff4 & @[".erf", ".dazip"]

proc patchGff3(erfPath, absPath: string, tlkDict: TableRef[uint32, TlkEntry]) =
  let f = initGff3File(erfPath, absPath, tlkDict)
  f.findTlkStrings()
  f.close()

proc patchGff4(erfPath, absPath: string, tlkDict: TableRef[uint32, TlkEntry]) =
  let f = initGff4File(erfPath, absPath, tlkDict)
  f.findTlkStrings()
  f.close()

proc patchErfContents(dirPath, erfPath: string, tlkDict: TableRef[uint32, TlkEntry]) =
  for kind, path in walkDir(dirPath):
    if kind == pcFile:
      let ext = path.splitFile().ext.toLowerAscii()
      
      if ext in ExtGff3:
        patchGff3(erfPath, path, tlkDict)
      
      elif ext in ExtGff4 and ext != ".tlk": # Skip .tlk files inside ERF
        patchGff4(erfPath, path, tlkDict)

proc patchErf(erfPath, newErfPath: string, tlkDict: TableRef[uint32, TlkEntry]) =
  let tempDir = createTempDir("daotools_", "_erf")
  try:
    extractErf(erfPath, tempDir)
    patchErfContents(tempDir, erfPath, tlkDict)
    buildErf(tempDir, newErfPath)
  finally:
    removeDir(tempDir) # Clean up temp files

proc patchGff3Stream(erfPath, filename: string, data: sink string, tlkDict: TableRef[uint32, TlkEntry]): string =
  let f = initGff3FileFromStream(data, erfPath, filename, tlkDict)
  f.findTlkStrings()
  let patchedData = f.mm.getStreamData() # Grab the mutated string!
  f.close()
  return patchedData

proc patchGff4Stream(erfPath, filename: string, data: sink string, tlkDict: TableRef[uint32, TlkEntry]): string =
  let f = initGff4FileFromStream(data, erfPath, filename, tlkDict)
  f.findTlkStrings()
  let patchedData = f.mm.getStreamData()
  f.close()
  return patchedData

proc patchErfContentsStream(erfPath: string, erfFiles: TableRef[string, string], tlkDict: TableRef[uint32, TlkEntry]) =
  # Iterate using mpairs to mutate the table values in place
  for filename, data in erfFiles.mpairs:
    let ext = filename.splitFile().ext.toLowerAscii()
    if ext in ExtGff3:
      erfFiles[filename] = patchGff3Stream(erfPath, filename, data, tlkDict)
    elif ext in ExtGff4 and ext != ".tlk":
      erfFiles[filename] = patchGff4Stream(erfPath, filename, data, tlkDict)

# proc patchErfStream(erfPath: string, erfData: string, tlkDict: TableRef[uint32, TlkEntry]): string =
#   let erfFiles = extractErfStream(erfData)
#   patchErfContentsStream(erfPath, erfFiles, tlkDict)
#   return buildErfStream(erfFiles)

proc patchErfStream(erfPath: string, erfData: sink string, tlkDict: TableRef[uint32, TlkEntry]): string =
  let erfFiles = extractErfStream(erfData)
  
  # EXECUTOR: We copied the files to the table. The original 250MB string is now dead weight.
  # We forcefully wipe it from RAM right now before we start building the new one.
  var deadData = move(erfData) 
  reset(deadData) 
  
  patchErfContentsStream(erfPath, erfFiles, tlkDict)
  return buildErfStream(erfFiles)

# Add the callback parameter to the definition
proc patchDazip*(zipPath, newZipPath: string, keepAudio: bool, tlkDict: TableRef[uint32, TlkEntry], onTlkEdit: proc(mapPath: string) = nil) =
  let reader = openZipArchive(zipPath)
  let writer = openZipStream(newZipPath) 
  
  for path, record in reader.records:
    if record.kind != FileRecord: continue
    
    let ext = path.splitFile().ext.toLowerAscii()
    if not keepAudio and ext in AudioExts: continue
      
    let fileData = reader.extractFile(path)
    
    if ext == ".erf":
      let patchedErf = patchErfStream(path, fileData, tlkDict)
      writer.addEntry(path, patchedErf) 
    else:
      writer.addEntry(path, fileData)   
      
  if tlkDict.len > 0:
    # Build absolute paths next to the target DAZIP
    let workDir = zipPath.splitFile().dir
    let mapPath = workDir / "TEMP_full_tlk.json"
    let tlkPath = workDir / "TEMP_test.tlk"
    
    # Check if mapfile generated successfully
    if genMapfile(mapPath, tlkDict):
      
      # If the GUI passed us a callback, execute it!
      # This hands control back to the GUI, which pops the window.alert.
      # The backend will FREEZE right here until the user clicks "OK".
      if onTlkEdit != nil:
        onTlkEdit(mapPath)
      
      # The user clicked OK! Resume standard operations:
      discard genTlkFile(mapPath, tlkPath)
      
      let baseName = zipPath.splitFile().name.replace(" ", "_")
      let overridePath = "Contents/packages/core/override/" & baseName & ".tlk"
      
      writer.addEntry(overridePath, readFile(tlkPath))
      
    # Clean up the SSD
    if fileExists(mapPath): removeFile(mapPath)
    if fileExists(tlkPath): removeFile(tlkPath)

  writer.close()

# =====================================================================
# MAIN ROUTER
# =====================================================================

proc patchFile*(inputPath, outputPath: string, keepAudio = false, onTlkEdit: proc(mapPath: string) = nil) =
  let ext = inputPath.splitFile().ext.toLowerAscii()
  let tlkDict = newTable[uint32, TlkEntry]() # Central dict for this patching run
  
  if ext in ExtGff3:
    copyFile(inputPath, outputPath)
    patchGff3("None", outputPath, tlkDict)
    
  elif ext in ExtGff4:
    copyFile(inputPath, outputPath)
    patchGff4("None", outputPath, tlkDict)
    
  elif ext == ".erf":
    patchErf(inputPath, outputPath, tlkDict)
    
  elif ext == ".dazip":
    patchDazip(inputPath, outputPath, keepAudio, tlkDict, onTlkEdit)
    
  else:
    quit("Error: Unknown game file extension: " & ext)

proc patchedPath*(inputPath: string): string =
  ## <name>.patched.<ext>, alongside the original.
  let (dir, name, ext) = inputPath.splitFile()
  return dir / (name & ".patched" & ext)

proc patchFolder*(dirPath: string, keepAudio = false,
                  onTlkEdit: proc(mapPath: string) = nil,
                  onFile: proc(path: string, err: string) = nil):
                  tuple[patched, failed, skipped: int] =
  ## Patches every compatible file under dirPath, recursively, writing each
  ## result next to its original. onFile reports progress: err == "" on success.
  var targets: seq[string]
  for path in walkDirRec(dirPath):
    let (_, name, ext) = path.splitFile()
    # Skip our own output so re-running a folder doesn't patch the patches
    if ext.toLowerAscii() in PatchableExts and not name.toLowerAscii().endsWith(".patched"):
      targets.add(path)
    else:
      result.skipped += 1

  # Collect first, then patch: we are writing new files into the tree we walked
  targets.sort()

  for path in targets:
    try:
      patchFile(path, patchedPath(path), keepAudio, onTlkEdit)
      result.patched += 1
      if onFile != nil: onFile(path, "")
    except Exception as e:
      result.failed += 1
      if onFile != nil: onFile(path, e.msg)

when isMainModule:
  # loadIdsAndNames() # Initialize global ID/Name dictionaries before parsing

  if paramCount() < 1:
    quit("Usage: ./patch_manager <path_to_gff_file>")
  
  let filePath = paramStr(1)
  if not fileExists(filePath): quit("Error: File not found.")
  
  patchFile(filePath, patchedPath(filePath))