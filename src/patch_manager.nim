# patch_manager.nim

import os, tables, memfiles, strutils, unicode, sets, json, streams, algorithm, times
import zippy/ziparchives

include models
include utils
include erf_engine
include translation_engine
include dummy_class
include gff3_class
include gff4_class
include talktable_class

const
  ExtGff3 = [".are", ".lst", ".utc", ".uti", ".utm", ".utp", ".utt"]
  ExtGff4 = [".cub", ".cut", ".dlb", ".dlg", ".plo", ".stg"]
  ExtTlk = ".tlk"
  AudioExts = [".fsb", ".fev"]
  PatchableExts = @ExtGff3 & @ExtGff4 & @[ExtTlk, ".erf", ".dazip"]
  PatchedDirectoryName* = "DAOTools Patched"
  PatchedSentinelName* = ".daotools-patched"
  PatchedSentinelContents =
    "DAOTools patched output. Game resource filenames are intentionally preserved.\n"

# =====================================================================
# RESOURCE DISCOVERY AND REWRITING
# =====================================================================

proc discoverGff3Stream*(data: sink string, containerPath, filename: string,
                         discovered: DiscoveryIndex) =
  let f = initGff3FileFromStream(move(data), containerPath, filename, discovered)
  f.findTlkStrings()
  f.close()

proc rewriteGff3Stream*(data: sink string, containerPath, filename: string,
                        translations: TranslationIndex): string =
  let f = initGff3FileFromStream(
    move(data), containerPath, filename, translations = translations)
  f.findTlkStrings()
  result = f.rewriteTranslations(translations)
  f.close()

proc discoverGff4Stream*(data: sink string, containerPath, filename: string,
                         discovered: DiscoveryIndex) =
  let f = initGff4FileFromStream(move(data), containerPath, filename, discovered)
  f.findTlkStrings()
  f.close()

proc rewriteGff4Stream*(data: sink string, containerPath, filename: string,
                        translations: TranslationIndex): string =
  let f = initGff4FileFromStream(
    move(data), containerPath, filename, translations = translations)
  f.findTlkStrings()
  result = f.rewriteTranslations(translations)
  f.close()

proc discoverTlkStream*(data: sink string, containerPath, filename: string,
                        discovered: DiscoveryIndex) =
  let f = initTalkTableFileFromStream(
    move(data), containerPath, filename, discovered = discovered)
  f.findTalkTableStrings()
  f.close()

proc rewriteTlkStream*(data: sink string, containerPath, filename: string,
                       translations: TranslationIndex): string =
  let f = initTalkTableFileFromStream(
    move(data), containerPath, filename, translations = translations)
  f.findTalkTableStrings()
  result = f.rewriteTalkTable(translations)
  f.close()

proc discoverErfStream(erfPath: string, erfData: sink string,
                       discovered: DiscoveryIndex) =
  let files = extractErfStream(erfData)
  # extractErfStream owns separate entry strings now; release the potentially
  # huge source ERF before walking those entries.
  var consumedErf = move(erfData)
  reset(consumedErf)
  for filename, data in files.mpairs:
    let ext = filename.splitFile().ext.toLowerAscii()
    if ext in ExtGff3:
      discoverGff3Stream(move(data), erfPath, filename, discovered)
    elif ext == ExtTlk:
      discoverTlkStream(move(data), erfPath, filename, discovered)
    elif ext in ExtGff4:
      discoverGff4Stream(move(data), erfPath, filename, discovered)

proc rewriteErfStream(erfPath: string, erfData: sink string,
                      translations: TranslationIndex): string =
  let files = extractErfStream(erfData)
  var consumedErf = move(erfData)
  reset(consumedErf)
  for filename, data in files.mpairs:
    let ext = filename.splitFile().ext.toLowerAscii()
    if ext in ExtGff3:
      data = rewriteGff3Stream(move(data), erfPath, filename, translations)
    elif ext == ExtTlk:
      data = rewriteTlkStream(move(data), erfPath, filename, translations)
    elif ext in ExtGff4:
      data = rewriteGff4Stream(move(data), erfPath, filename, translations)
  buildErfStream(files)

proc discoverDazip(zipPath: string, discovered: DiscoveryIndex,
                   scopeLabel: string) =
  let reader = openZipArchive(zipPath)
  for path, record in reader.records:
    if record.kind != FileRecord: continue
    let ext = path.splitFile().ext.toLowerAscii()
    if ext == ".erf":
      discoverErfStream(scopeLabel & " -> " & path, reader.extractFile(path), discovered)
    elif ext in ExtGff3:
      discoverGff3Stream(reader.extractFile(path), scopeLabel, path, discovered)
    elif ext == ExtTlk:
      discoverTlkStream(reader.extractFile(path), scopeLabel, path, discovered)
    elif ext in ExtGff4:
      discoverGff4Stream(reader.extractFile(path), scopeLabel, path, discovered)

proc rewriteDazip(zipPath, outputPath: string, keepAudio: bool,
                  translations: TranslationIndex, scopeLabel: string) =
  let reader = openZipArchive(zipPath)
  let writer = openZipStream(outputPath)

  for path, record in reader.records:
    if record.kind != FileRecord: continue
    let ext = path.splitFile().ext.toLowerAscii()
    if not keepAudio and ext in AudioExts: continue

    var data = reader.extractFile(path)
    if ext == ".erf":
      writer.addEntry(path, rewriteErfStream(
        scopeLabel & " -> " & path, move(data), translations))
    elif ext in ExtGff3:
      writer.addEntry(path, rewriteGff3Stream(
        move(data), scopeLabel, path, translations))
    elif ext == ExtTlk:
      writer.addEntry(path, rewriteTlkStream(
        move(data), scopeLabel, path, translations))
    elif ext in ExtGff4:
      writer.addEntry(path, rewriteGff4Stream(
        move(data), scopeLabel, path, translations))
    else:
      writer.addEntry(path, data)

  writer.close()

proc discoverPath(inputPath: string, discovered: DiscoveryIndex,
                  resourceLabel = "") =
  let ext = inputPath.splitFile().ext.toLowerAscii()
  let label = if resourceLabel == "": extractFilename(inputPath) else: resourceLabel
  if ext in ExtGff3:
    discoverGff3Stream(readFile(inputPath), "standalone", label, discovered)
  elif ext == ExtTlk:
    discoverTlkStream(readFile(inputPath), "standalone", label, discovered)
  elif ext in ExtGff4:
    discoverGff4Stream(readFile(inputPath), "standalone", label, discovered)
  elif ext == ".erf":
    discoverErfStream(label, readFile(inputPath), discovered)
  elif ext == ".dazip":
    discoverDazip(inputPath, discovered, label)
  else:
    raise newException(ValueError, "Unknown game file extension: " & ext)

proc rewritePath(inputPath, outputPath: string, keepAudio: bool,
                 translations: TranslationIndex, resourceLabel = "") =
  let ext = inputPath.splitFile().ext.toLowerAscii()
  let label = if resourceLabel == "": extractFilename(inputPath) else: resourceLabel
  if ext in ExtGff3:
    writeFile(outputPath, rewriteGff3Stream(
      readFile(inputPath), "standalone", label, translations))
  elif ext == ExtTlk:
    writeFile(outputPath, rewriteTlkStream(
      readFile(inputPath), "standalone", label, translations))
  elif ext in ExtGff4:
    writeFile(outputPath, rewriteGff4Stream(
      readFile(inputPath), "standalone", label, translations))
  elif ext == ".erf":
    writeFile(outputPath, rewriteErfStream(
      label, readFile(inputPath), translations))
  elif ext == ".dazip":
    rewriteDazip(inputPath, outputPath, keepAudio, translations, label)
  else:
    raise newException(ValueError, "Unknown game file extension: " & ext)

# =====================================================================
# TRANSLATION WORKFLOW
# =====================================================================

proc nextTranslationPath(inputPath: string, isFolder = false): string =
  let baseDir = if isFolder: inputPath.parentDir() else: inputPath.splitFile().dir
  let baseName = if isFolder: inputPath.lastPathPart() else: inputPath.extractFilename()
  let stem = baseDir / (baseName & ".translations")
  result = stem & ".json"
  var suffix = 2
  while fileExists(result) or dirExists(result):
    result = stem & " (" & $suffix & ").json"
    suffix += 1

proc editDiscoveredTranslations(discovered: DiscoveryIndex, jsonPath: string,
                                onTranslationEdit: proc(mapPath: string) = nil): TranslationIndex =
  result = newTranslationIndex()
  if discovered.discoveredLen() == 0:
    return

  discovered.encodeDiscoveryJson(jsonPath)
  if onTranslationEdit != nil:
    onTranslationEdit(jsonPath)
  result = decodeTranslationJson(jsonPath)

proc loadMasterTranslations(masterJsonPath: string): TranslationIndex =
  if masterJsonPath == "":
    return nil
  if not fileExists(masterJsonPath):
    raise newException(IOError, "Translation JSON not found: " & masterJsonPath)
  decodeTranslationJson(masterJsonPath)

proc patchFile*(inputPath, outputPath: string, keepAudio = false,
                onTranslationEdit: proc(mapPath: string) = nil,
                masterJsonPath = ""): string =
  ## Returns the generated interactive JSON path, or "" when a master JSON was
  ## supplied or no mod-authored strings needed editing.
  var translations = loadMasterTranslations(masterJsonPath)
  if translations == nil:
    let discovered = newDiscoveryIndex()
    discoverPath(inputPath, discovered)
    if discovered.discoveredLen() > 0:
      result = nextTranslationPath(inputPath)
    translations = editDiscoveredTranslations(discovered, result, onTranslationEdit)

  rewritePath(inputPath, outputPath, keepAudio, translations)

proc nextPatchedOutputDir*(inputPath: string): string =
  ## Return a new sibling output directory. Never merge with or overwrite an
  ## older run, and keep installable resource filenames completely unchanged.
  let parent = if dirExists(inputPath): inputPath.parentDir()
               else: inputPath.splitFile().dir
  result = parent / PatchedDirectoryName
  var suffix = 2
  while dirExists(result) or fileExists(result):
    result = parent / (PatchedDirectoryName & " (" & $suffix & ")")
    suffix += 1

proc writePatchedSentinel(dirPath: string) =
  writeFile(dirPath / PatchedSentinelName, PatchedSentinelContents)

proc patchSelectedFile*(inputPath: string, keepAudio = false,
                        onTranslationEdit: proc(mapPath: string) = nil,
                        masterJsonPath = ""):
                        tuple[outputPath, translationPath: string] =
  ## Patch one directly selected file transactionally into DAOTools Patched,
  ## retaining its exact basename so loose resources remain game-loadable.
  let outputDir = nextPatchedOutputDir(inputPath)
  createDir(outputDir)
  result.outputPath = outputDir / inputPath.extractFilename()
  let temporaryPath = result.outputPath & ".daotmp"
  try:
    result.translationPath = patchFile(
      inputPath, temporaryPath, keepAudio, onTranslationEdit, masterJsonPath)
    moveFile(temporaryPath, result.outputPath)
    writePatchedSentinel(outputDir)
  except:
    try:
      if fileExists(temporaryPath): removeFile(temporaryPath)
      removeDir(outputDir)
    except CatchableError:
      discard
    raise

proc patchFolder*(dirPath: string, keepAudio = false,
                  onTranslationEdit: proc(mapPath: string) = nil,
                  onFile: proc(path: string, err: string) = nil,
                  masterJsonPath = ""):
                  tuple[outDir, translationPath: string, patched, failed, skipped: int] =
  ## Discovery reads only the source tree. The destination copy is not created
  ## until translations are ready, making the interactive first pass fully
  ## transactional.
  var sourceTargets: seq[string]
  for path in walkDirRec(dirPath):
    if path.splitFile().ext.toLowerAscii() in PatchableExts:
      sourceTargets.add(path)
    else:
      result.skipped += 1
  sourceTargets.sort()

  var translations = loadMasterTranslations(masterJsonPath)
  if translations == nil:
    let discovered = newDiscoveryIndex()
    for path in sourceTargets:
      let relative = relativePath(path, dirPath).replace('\\', '/')
      try:
        discoverPath(path, discovered, relative)
      except Exception:
        # Discovery failures are reported again during the patch pass, where
        # the untouched copied file can be preserved.
        discard
    if discovered.discoveredLen() > 0:
      result.translationPath = nextTranslationPath(dirPath, true)
    translations = editDiscoveredTranslations(
      discovered, result.translationPath, onTranslationEdit)

  let dest = nextPatchedOutputDir(dirPath)
  copyDir(dirPath, dest)
  writePatchedSentinel(dest)
  result.outDir = dest

  for sourcePath in sourceTargets:
    let relative = relativePath(sourcePath, dirPath)
    let destPath = dest / relative
    let tmp = destPath & ".daotmp"
    try:
      rewritePath(destPath, tmp, keepAudio, translations, relative.replace('\\', '/'))
      removeFile(destPath)
      moveFile(tmp, destPath)
      result.patched += 1
      if onFile != nil: onFile(destPath, "")
    except Exception as e:
      if fileExists(tmp): removeFile(tmp)
      result.failed += 1
      if onFile != nil: onFile(destPath, e.msg.replace(".daotmp", ""))

when isMainModule:
  if paramCount() < 1:
    quit("Usage: ./patch_manager <path_to_game_file> [translations.json]")

  let filePath = paramStr(1)
  if not fileExists(filePath): quit("Error: File not found.")
  let masterJson = if paramCount() >= 2: paramStr(2) else: ""

  try:
    discard patchSelectedFile(filePath, masterJsonPath = masterJson)
  except CatchableError as e:
    quit("Error: " & e.msg)
