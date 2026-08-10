import std/[os, tables, tempfiles, unittest]
import zippy/ziparchives
import ../src/patch_manager

const
  TestId = 700000001'u32
  SourceLine = "Blood Gauntlets"
  ItalianLine = "Guanti del Sangue 👋"

proc readU32(data: string, offset: int): uint32 =
  data[offset].uint32 or
    (data[offset + 1].uint32 shl 8) or
    (data[offset + 2].uint32 shl 16) or
    (data[offset + 3].uint32 shl 24)

proc readU16(data: string, offset: int): uint16 =
  data[offset].uint16 or (data[offset + 1].uint16 shl 8)

proc makeGff3(line: string, id = TestId): string =
  # One root struct, one CExoLocString field, and no index arrays.
  result.add("UTI V3.2")
  result.appendU32(56'u32)  # struct offset
  result.appendU32(1'u32)
  result.appendU32(68'u32)  # field offset
  result.appendU32(1'u32)
  result.appendU32(80'u32)  # label offset
  result.appendU32(1'u32)
  result.appendU32(96'u32)  # field-data offset
  result.appendU32((20 + line.len).uint32)
  result.appendU32((116 + line.len).uint32) # empty field-index array
  result.appendU32(0'u32)
  result.appendU32((116 + line.len).uint32) # empty list-index array
  result.appendU32(0'u32)

  result.appendU32(0'u32) # struct type
  result.appendU32(0'u32) # direct field index
  result.appendU32(1'u32) # field count

  result.appendU32(12'u32) # CExoLocString
  result.appendU32(0'u32)  # label index
  result.appendU32(0'u32)  # offset into FieldData

  result.add("LocalizedName")
  result.add("\0\0\0")

  result.appendU32((16 + line.len).uint32)
  result.appendU32(id)
  result.appendU32(1'u32)
  result.appendU32(0'u32)
  result.appendU32(line.len.uint32)
  result.add(line)

proc makeGff4(line: string, id = TestId): string =
  # One ROOT struct with one inline TLKString at data-block offset zero.
  result.add("GFF V4.0PC  TESTV0.1")
  result.appendU32(1'u32)
  result.appendU32(56'u32)

  result.add("ROOT")
  result.appendU32(1'u32)
  result.appendU32(44'u32)
  result.appendU32(8'u32)

  result.appendU32(19003'u32)
  result.appendU16(17'u16)
  result.appendU16(0'u16)
  result.appendU32(0'u32)

  result.appendU32(id)
  result.appendU32(8'u32)
  result.add(line.encodeEcString())

proc makeTalkTable(entries: openArray[tuple[id: uint32, line: string]]): string =
  # Canonical DAO TLK V0.2: TLK root, STRN entries, and an ECString data tail.
  result.add("GFF V4.0PC  TLK V0.2")
  result.appendU32(2'u32)
  result.appendU32(96'u32)

  result.add("TLK ")
  result.appendU32(1'u32)
  result.appendU32(60'u32)
  result.appendU32(4'u32)
  result.add("STRN")
  result.appendU32(2'u32)
  result.appendU32(72'u32)
  result.appendU32(8'u32)

  result.appendU32(19001'u32)
  result.appendU16(1'u16)
  result.appendU16(0xC000'u16)
  result.appendU32(0'u32)
  result.appendU32(19002'u32)
  result.appendU16(4'u16)
  result.appendU16(0'u16)
  result.appendU32(0'u32)
  result.appendU32(19003'u32)
  result.appendU16(14'u16)
  result.appendU16(0'u16)
  result.appendU32(4'u32)

  result.appendU32(4'u32)
  result.appendU32(entries.len.uint32)
  var strings = newStringOfCap(128)
  let stringsOffset = 8 + (entries.len * 8)
  for entry in entries:
    result.appendU32(entry.id)
    result.appendU32((stringsOffset + strings.len).uint32)
    strings.appendEcString(entry.line)
  result.add(strings)

proc talkTableLine(data: string, id: uint32): string =
  let count = data.readU32(100).int
  for i in 0 ..< count:
    let entryOffset = 104 + (i * 8)
    if data.readU32(entryOffset) != id:
      continue
    let lineReference = data.readU32(entryOffset + 4)
    if lineReference == 0 or lineReference == 0xFFFFFFFF'u32:
      return ""
    let absoluteOffset = 96 + lineReference.int
    let length = data.readU32(absoluteOffset)
    var units: seq[uint16]
    if length > 0:
      units = newSeq[uint16]((length - 1).int)
      for unitIndex in 0 ..< units.len:
        units[unitIndex] = data.readU16(absoluteOffset + 4 + (unitIndex * 2))
    return units.fromUtf16Units()
  raise newException(ValueError, "Missing fixture TLK ID: " & $id)

proc discoveredLine(data: string, extension: string): string =
  let discovered = newDiscoveryIndex()
  if extension == ".uti":
    discoverGff3Stream(data, "standalone", "fixture.uti", discovered)
  else:
    discoverGff4Stream(data, "standalone", "fixture.dlg", discovered)
  discovered["fixture" & extension][TestId].line

suite "inline translation rewriting":
  test "unselected mod-authored strings remain byte-for-byte unchanged":
    let translations = newTranslationIndex()
    let originalGff3 = makeGff3(SourceLine)
    let originalGff4 = makeGff4(SourceLine)

    check rewriteGff3Stream(
      originalGff3, "standalone", "fixture.uti", translations) == originalGff3
    check rewriteGff4Stream(
      originalGff4, "standalone", "fixture.dlg", translations) == originalGff4

  test "GFF3 unchanged translations preserve the complete resource":
    let original = makeGff3(SourceLine)
    let translations = newTranslationIndex()
    translations.byId[TestId] = SourceLine
    check rewriteGff3Stream(original, "standalone", "fixture.uti", translations) == original

  test "GFF3 inserts translated CExoLocStrings inside FieldData":
    let original = makeGff3(SourceLine)
    let translations = newTranslationIndex()
    translations.byId[TestId] = ItalianLine
    let rewritten = rewriteGff3Stream(original, "standalone", "fixture.uti", translations)
    let rawDelta = 20 + ItalianLine.len
    let alignedDelta = ((rawDelta + 3) div 4) * 4

    check rewritten.discoveredLine(".uti") == ItalianLine
    check rewritten.readU32(36) == original.readU32(36) +
      alignedDelta.uint32
    check rewritten.readU32(40) == original.readU32(40) +
      alignedDelta.uint32
    check rewritten.readU32(48) == original.readU32(48) +
      alignedDelta.uint32

  test "GFF4 appends UTF-16 ECStrings and preserves non-BMP text":
    let original = makeGff4(SourceLine)
    let translations = newTranslationIndex()
    translations.byId[TestId] = ItalianLine
    let rewritten = rewriteGff4Stream(original, "standalone", "fixture.dlg", translations)

    check rewritten.len > original.len
    check rewritten.discoveredLine(".dlg") == ItalianLine

  test "TLK discovery inventories only mod-authored entries":
    let original = makeTalkTable([
      (id: TestId, line: SourceLine),
      (id: 123'u32, line: "Core fallback")
    ])
    let discovered = newDiscoveryIndex()
    discoverTlkStream(original, "standalone", "fixture.tlk", discovered)

    check discovered.discoveredLen() == 1
    check discovered["fixture.tlk"][TestId].line == SourceLine

  test "TLK master rewriting supports any ID and preserves unselected files":
    const CoreTranslation = "Основная строка"
    let original = makeTalkTable([
      (id: TestId, line: SourceLine),
      (id: 123'u32, line: "Core fallback")
    ])
    let emptyTranslations = newTranslationIndex()
    check rewriteTlkStream(
      original, "standalone", "fixture.tlk", emptyTranslations) == original

    let translations = newTranslationIndex()
    translations.byId[TestId] = ItalianLine
    translations.byId[123'u32] = CoreTranslation
    let rewritten = rewriteTlkStream(
      original, "standalone", "fixture.tlk", translations)
    check rewritten.talkTableLine(TestId) == ItalianLine
    check rewritten.talkTableLine(123'u32) == CoreTranslation

    var missingReference = makeTalkTable([(id: TestId, line: SourceLine)])
    missingReference.writeU32At(108, 0xFFFFFFFF'u32)
    let repaired = rewriteTlkStream(
      missingReference, "standalone", "fixture.tlk", translations)
    check repaired.talkTableLine(TestId) == ItalianLine

  test "shipped IDs discard inline overrides without changing their IDs":
    let translations = newTranslationIndex()

    let originalGff3 = makeGff3(SourceLine, 123'u32)
    let rewrittenGff3 = rewriteGff3Stream(
      originalGff3, "standalone", "core.uti", translations)
    check rewrittenGff3.readU32(100) == 123'u32
    check rewrittenGff3.readU32(96) == 8'u32
    check rewrittenGff3.readU32(104) == 0'u32

    let originalGff4 = makeGff4(SourceLine, 123'u32)
    let rewrittenGff4 = rewriteGff4Stream(
      originalGff4, "standalone", "core.dlg", translations)
    check rewrittenGff4.readU32(56) == 123'u32
    check rewrittenGff4.readU32(60) == 0'u32

  test "interactive discovery excludes shipped core IDs":
    let discovered = newDiscoveryIndex()
    discoverGff3Stream(
      makeGff3(SourceLine, 123'u32), "standalone", "core.uti", discovered)
    discoverGff4Stream(
      makeGff4(SourceLine, 123'u32), "standalone", "core.dlg", discovered)
    check discovered.discoveredLen() == 0

  test "GFF4 preserves the dialogue-advance reference sentinel":
    var original = makeGff4(SourceLine, 123'u32)
    original.writeU32At(60, 0xFFFFFFFF'u32)
    let translations = newTranslationIndex()
    check rewriteGff4Stream(
      original, "standalone", "core.dlg", translations) == original

  test "GFF3 CExoLocStrings round-trip Cyrillic UTF-8":
    const RussianLine = "Кровавые перчатки"
    let translations = newTranslationIndex()
    translations.byId[TestId] = RussianLine
    let rewritten = rewriteGff3Stream(
      makeGff3(SourceLine), "standalone", "fixture.uti", translations)
    check rewritten.discoveredLine(".uti") == RussianLine

  test "master JSON values repair strings zeroed by the old TLK workflow":
    let translations = newTranslationIndex()
    translations.byId[TestId] = ItalianLine

    var oldGff3 = makeGff3(SourceLine)
    oldGff3.writeU32At(96, 8'u32)
    oldGff3.writeU32At(104, 0'u32)
    let repairedGff3 = rewriteGff3Stream(
      oldGff3, "standalone", "fixture.uti", translations)
    check repairedGff3.discoveredLine(".uti") == ItalianLine

    var oldGff4 = makeGff4(SourceLine)
    oldGff4.writeU32At(60, 0'u32)
    let repairedGff4 = rewriteGff4Stream(
      oldGff4, "standalone", "fixture.dlg", translations)
    check repairedGff4.discoveredLine(".dlg") == ItalianLine

  test "file-specific translations take precedence over global IDs":
    let dir = createTempDir("daotools_test_", "")
    let jsonPath = dir / "master.json"
    writeFile(jsonPath, """{
      "tlkstrings": {"700000001": "global"},
      "files": {"fixture.dlg": {"700000001": "specific"}}
    }""")
    let translations = decodeTranslationJson(jsonPath)
    check translations.findTranslation("container.erf -> fixture.dlg", TestId) ==
      (found: true, line: "specific")
    removeDir(dir)

  test "selected files keep their exact basename inside sentinel output folders":
    let dir = createTempDir("daotools_output_", "")
    let inputPath = dir / "am105it_osen_gloves.uti"
    let jsonPath = dir / "master.json"
    writeFile(inputPath, makeGff3(SourceLine))
    writeFile(jsonPath, "{\"700000001\": \"" & ItalianLine & "\"}")

    let first = patchSelectedFile(inputPath, masterJsonPath = jsonPath)
    check first.outputPath ==
      dir / PatchedDirectoryName / "am105it_osen_gloves.uti"
    check fileExists(dir / PatchedDirectoryName / PatchedSentinelName)
    check first.outputPath.extractFilename() == "am105it_osen_gloves.uti"
    check readFile(first.outputPath).discoveredLine(".uti") == ItalianLine

    let second = patchSelectedFile(inputPath, masterJsonPath = jsonPath)
    check second.outputPath ==
      dir / (PatchedDirectoryName & " (2)") / "am105it_osen_gloves.uti"
    check fileExists(
      dir / (PatchedDirectoryName & " (2)") / PatchedSentinelName)

    removeDir(dir)

  test "TLKs nested in ERFs are translated and retain their filename":
    let dir = createTempDir("daotools_tlk_erf_", "")
    let inputPath = dir / "module.erf"
    let jsonPath = dir / "master.json"
    let files = newTable[string, string]()
    files["mod_en-us.tlk"] = makeTalkTable([
      (id: TestId, line: SourceLine)
    ])
    writeFile(inputPath, buildErfStream(files))
    writeFile(jsonPath, "{\"700000001\": \"" & ItalianLine & "\"}")

    let patched = patchSelectedFile(inputPath, masterJsonPath = jsonPath)
    let rewrittenFiles = extractErfStream(readFile(patched.outputPath))
    check patched.outputPath.extractFilename() == "module.erf"
    check rewrittenFiles.hasKey("mod_en-us.tlk")
    check rewrittenFiles["mod_en-us.tlk"].talkTableLine(TestId) == ItalianLine
    check fileExists(patched.outputPath.parentDir() / PatchedSentinelName)

    removeDir(dir)

  test "TLKs nested in DAZIPs use the dedicated talk-table rewriter":
    let dir = createTempDir("daotools_tlk_dazip_", "")
    let inputPath = dir / "module.dazip"
    let jsonPath = dir / "master.json"
    let writer = openZipStream(inputPath)
    writer.addEntry(
      "Contents/addins/example/module/data/mod_en-us.tlk",
      makeTalkTable([(id: TestId, line: SourceLine)]))
    writer.close()
    writeFile(jsonPath, "{\"700000001\": \"" & ItalianLine & "\"}")

    let patched = patchSelectedFile(inputPath, masterJsonPath = jsonPath)
    let reader = openZipArchive(patched.outputPath)
    let rewritten = reader.extractFile(
      "Contents/addins/example/module/data/mod_en-us.tlk")
    check patched.outputPath.extractFilename() == "module.dazip"
    check rewritten.talkTableLine(TestId) == ItalianLine
    check fileExists(patched.outputPath.parentDir() / PatchedSentinelName)

    removeDir(dir)

  test "folder master mode patches a copied tree without a discovery JSON":
    let dir = createTempDir("daotools_folder_", "")
    writeFile(dir / "item.uti", makeGff3(SourceLine))
    writeFile(dir / "dialog.dlg", makeGff4(SourceLine))
    let jsonPath = dir / "master.json"
    writeFile(jsonPath, "{\"700000001\": \"" & ItalianLine & "\"}")

    let patched = patchFolder(dir, masterJsonPath = jsonPath)
    check patched.patched == 2
    check patched.failed == 0
    check patched.translationPath == ""
    check fileExists(patched.outDir / PatchedSentinelName)
    check readFile(patched.outDir / "item.uti").discoveredLine(".uti") == ItalianLine
    check readFile(patched.outDir / "dialog.dlg").discoveredLine(".dlg") == ItalianLine

    removeDir(patched.outDir)
    removeDir(dir)

  test "folder file selectors distinguish duplicate basenames":
    let dir = createTempDir("daotools_paths_", "")
    createDir(dir / "first")
    createDir(dir / "second")
    writeFile(dir / "first" / "item.uti", makeGff3(SourceLine))
    writeFile(dir / "second" / "item.uti", makeGff3(SourceLine))
    let jsonPath = dir / "master.json"
    writeFile(jsonPath, """{
      "files": {
        "first/item.uti": {"700000001": "Prima traduzione"},
        "second/item.uti": {"700000001": "Seconda traduzione"}
      }
    }""")

    let patched = patchFolder(dir, masterJsonPath = jsonPath)
    check readFile(patched.outDir / "first" / "item.uti").discoveredLine(".uti") ==
      "Prima traduzione"
    check readFile(patched.outDir / "second" / "item.uti").discoveredLine(".uti") ==
      "Seconda traduzione"

    removeDir(patched.outDir)
    removeDir(dir)
