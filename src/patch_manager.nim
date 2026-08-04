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

proc tlkBaseName*(path: string): string =
  ## Full filename including its extension, so foo.dlg and foo.cut don't fight
  ## over one .tlk. Spaces become underscores like the DAZIP path already does.
  path.extractFilename().replace(" ", "_")

proc emitTlk*(tlkDict: TableRef[uint32, TlkEntry], destDir, baseName: string,
              onTlkEdit: proc(mapPath: string) = nil): string =
  ## Writes the harvested strings out as <baseName>.tlk in destDir and returns
  ## its path ("" if there was nothing to write).
  ##
  ## Never skip this when the dict is non-empty. By the time we get here the
  ## parser has already zeroed the string references inside the patched file,
  ## so this .tlk is the only surviving copy of those lines.
  if tlkDict.len == 0: return ""

  let mapPath = destDir / "TEMP_full_tlk.json"
  let tlkPath = destDir / (baseName & ".tlk")

  if not genMapfile(mapPath, tlkDict): return ""

  # Hand control to the GUI: it opens the JSON in the user's editor and then
  # blocks on a modal. The backend FREEZES right here until they click "OK".
  # genTlkFile must not run before this returns, or we compile the untranslated
  # JSON and throw the user's translation away.
  if onTlkEdit != nil:
    onTlkEdit(mapPath)

  let generated = genTlkFile(mapPath, tlkPath)
  if fileExists(mapPath): removeFile(mapPath)
  return if generated: tlkPath else: ""

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
    # Built next to the target DAZIP, then folded into the archive itself
    let workDir = zipPath.splitFile().dir
    let baseName = zipPath.splitFile().name.replace(" ", "_")
    let tlkPath = emitTlk(tlkDict, workDir, baseName, onTlkEdit)

    if tlkPath != "":
      writer.addEntry("Contents/packages/core/override/" & baseName & ".tlk", readFile(tlkPath))
      # The archive owns it now; don't leave a loose copy on the SSD
      removeFile(tlkPath)

  writer.close()

# =====================================================================
# MAIN ROUTER
# =====================================================================

proc patchFile*(inputPath, outputPath: string, keepAudio = false,
                onTlkEdit: proc(mapPath: string) = nil,
                sharedTlkDict: TableRef[uint32, TlkEntry] = nil) =
  ## sharedTlkDict lets a caller (patchFolder) accumulate strings across many
  ## files and emit one .tlk at the end. When it is nil we own the dict, and we
  ## are the ones responsible for writing the .tlk out.
  let ext = inputPath.splitFile().ext.toLowerAscii()
  let ownsDict = sharedTlkDict == nil
  let tlkDict = if ownsDict: newTable[uint32, TlkEntry]() else: sharedTlkDict

  if ext in ExtGff3:
    copyFile(inputPath, outputPath)
    patchGff3("None", outputPath, tlkDict)

  elif ext in ExtGff4:
    copyFile(inputPath, outputPath)
    patchGff4("None", outputPath, tlkDict)

  elif ext == ".erf":
    patchErf(inputPath, outputPath, tlkDict)

  elif ext == ".dazip":
    # A DAZIP is self-contained: it always gets its own dict and embeds its own
    # .tlk, even when it turns up inside a folder run.
    patchDazip(inputPath, outputPath, keepAudio, newTable[uint32, TlkEntry](), onTlkEdit)
    return

  else:
    raise newException(ValueError, "Unknown game file extension: " & ext)

  # Whatever we harvested has just been zeroed inside the patched file. If we
  # own the dict, this is the last chance to write those strings back out.
  if ownsDict:
    discard emitTlk(tlkDict, outputPath.splitFile().dir, tlkBaseName(inputPath), onTlkEdit)

proc patchedPath*(inputPath: string): string =
  ## <name>.patched.<ext>, alongside the original.
  let (dir, name, ext) = inputPath.splitFile()
  return dir / (name & ".patched" & ext)

proc patchFolder*(dirPath: string, keepAudio = false,
                  onTlkEdit: proc(mapPath: string) = nil,
                  onFile: proc(path: string, err: string) = nil):
                  tuple[outDir, tlkPath: string, patched, failed, skipped: int] =
  ## Copies dirPath to a sibling "Patched - <name>" and patches the files inside
  ## that copy in place, keeping their original filenames. The source folder is
  ## never modified. onFile reports progress: err == "" on success.
  let name = dirPath.lastPathPart()          # ignores a trailing separator
  let parent = dirPath.parentDir()

  # Never write into or delete an existing folder: a previous run may hold
  # translations the user typed by hand.
  var dest = parent / ("Patched - " & name)
  var attempt = 2
  while dirExists(dest) or fileExists(dest):
    dest = parent / ("Patched - " & name & " (" & $attempt & ")")
    attempt += 1

  copyDir(dirPath, dest)
  result.outDir = dest

  var targets: seq[string]
  for path in walkDirRec(dest):
    if path.splitFile().ext.toLowerAscii() in PatchableExts:
      targets.add(path)
    else:
      result.skipped += 1

  # Collect first, then patch: we are writing new files into the tree we walked
  targets.sort()

  # One dict for the whole tree, so the folder gets a single combined .tlk
  let tlkDict = newTable[uint32, TlkEntry]()

  for path in targets:
    # patchFile can't read and write the same path, so patch to a sibling temp
    # and swap it in
    let tmp = path & ".daotmp"
    try:
      patchFile(path, tmp, keepAudio, onTlkEdit, tlkDict)
      removeFile(path)
      moveFile(tmp, path)
      result.patched += 1
      if onFile != nil: onFile(path, "")
    except Exception as e:
      # Leave the untouched copy in place so the output folder stays complete
      if fileExists(tmp): removeFile(tmp)
      result.failed += 1
      # Engines report the file they were handed, which is the temp copy
      if onFile != nil: onFile(path, e.msg.replace(".daotmp", ""))

  # Must come after the loop: the dict isn't complete until every file is done
  result.tlkPath = emitTlk(tlkDict, dest, name.replace(" ", "_"), onTlkEdit)

when isMainModule:
  # loadIdsAndNames() # Initialize global ID/Name dictionaries before parsing

  if paramCount() < 1:
    quit("Usage: ./patch_manager <path_to_gff_file>")
  
  let filePath = paramStr(1)
  if not fileExists(filePath): quit("Error: File not found.")

  # The engines raise on malformed input now; keep the CLI's output clean
  try:
    patchFile(filePath, patchedPath(filePath))
  except CatchableError as e:
    quit("Error: " & e.msg)