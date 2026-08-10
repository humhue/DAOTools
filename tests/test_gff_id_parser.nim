import std/[re, strutils, unittest]
import ../src/patch_manager

const GffIdList = staticRead("../src/GFFIDList.txt")

suite "GFF ID parser":
  test "manual parser matches the legacy regex over the complete ID list":
    let legacyPattern = re"[GC]FF(?:STRUCT)?_(\w+)\s*=\s*(\d+)"
    var legacyCount = 0
    var parserCount = 0
    var lineNumber = 0

    for line in GffIdList.splitLines():
      lineNumber += 1
      checkpoint("GFFIDList.txt line " & $lineNumber & ": " & line)

      var captures: array[2, string]
      let legacyMatched = line.match(legacyPattern, captures)
      let parsed = line.parseGffIdLine()

      check parsed.matched == legacyMatched
      if legacyMatched:
        legacyCount += 1
        check parsed.name == captures[0]
        check parsed.id == captures[1].parseUInt().uint32
      if parsed.matched:
        parserCount += 1

    check parserCount == legacyCount
    check parserCount == 2441
