# erf_engine.nim
# import os, streams, times, strutils, unicode, algorithm

# Helpers for UTF-16LE binary I/O
proc readUtf16*(strm: Stream, numBytes: int): string =
  var runes = newSeq[Rune]()
  for i in 0 ..< (numBytes div 2):
    let u = strm.readUint16()
    if u != 0:
      runes.add(Rune(u))
  return $runes

proc writeUtf16*(strm: Stream, s: string, numBytes: int) =
  var written = 0
  for r in s.toRunes():
    if written + 2 <= numBytes:
      strm.write(r.uint16)
      written += 2
  while written < numBytes:
    strm.write(0'u8) # Pad remaining with zeroes
    written += 1

proc extractErf*(filePath, dirPath: string) =
  if dirExists(dirPath):
    removeDir(dirPath)
  createDir(dirPath)

  var strm = newFileStream(filePath, fmRead)
  if strm == nil: quit("Could not open ERF for reading: " & filePath)

  discard strm.readStr(16) # Skip "ERF V2.0" magic
  let fileCount = strm.readUint32()
  discard strm.readUint32() # skip delta years
  discard strm.readUint32() # skip delta days
  discard strm.readUint32() # skip padding

  for i in 0 ..< fileCount:
    strm.setPosition(32 + i.int * 72) # Jump strictly to TOC entry
    let entryName = strm.readUtf16(64)
    let entryOffset = strm.readUint32()
    let entrySize = strm.readUint32()

    # Seek directly to the aligned file data and extract
    strm.setPosition(entryOffset.int)
    let data = strm.readStr(entrySize.int)

    var outStrm = newFileStream(joinPath(dirPath, entryName), fmWrite)
    outStrm.write(data)
    outStrm.close()

  strm.close()

proc buildErf*(dirPath, filePath: string) =
  var embeddedFilenames = newSeq[string]()
  for kind, path in walkDir(dirPath):
    if kind == pcFile:
      embeddedFilenames.add(extractFilename(path))
  embeddedFilenames.sort()

  let fileCount = embeddedFilenames.len.uint32
  let nowTime = now()
  let deltaYears = (nowTime.year - 1900).uint32
  let janFirst = dateTime(nowTime.year, mJan, 1, 0, 0, 0, 0, local())
  let deltaDays = (nowTime - janFirst).inDays().uint32

  var strm = newFileStream(filePath, fmWrite)
  if strm == nil: quit("Could not create ERF: " & filePath)

  strm.writeUtf16("ERF V2.0", 16)
  strm.write(fileCount)
  strm.write(deltaYears)
  strm.write(deltaDays)
  strm.write(0xFFFFFFFF'u32)

  # ALIGNMENT HELPER: Rounds any offset up to the nearest multiple of 16 bytes
  template align16(val: uint32): uint32 =
    let rem = val mod 16
    if rem == 0: val else: val + (16 - rem)

  # Pre-calculate TOC to find padded offsets
  var currentOffset = align16(32 + fileCount * 72)
  var tocEntries = newSeq[tuple[name: string, offset: uint32, size: uint32]]()

  for name in embeddedFilenames:
    let size = getFileSize(joinPath(dirPath, name)).uint32
    tocEntries.add((name, currentOffset, size))
    currentOffset = align16(currentOffset + size) # Apply alignment for the NEXT file

  # Write TOC
  for entry in tocEntries:
    strm.writeUtf16(entry.name, 64)
    strm.write(entry.offset)
    strm.write(entry.size)

  # Write File Data
  for entry in tocEntries:
    # Safely pad the binary with zeroes up to our aligned offset
    while strm.getPosition() < entry.offset.int:
      strm.write(0'u8)

    # Write actual file content
    var inStrm = newFileStream(joinPath(dirPath, entry.name), fmRead)
    strm.write(inStrm.readAll())
    inStrm.close()

  strm.close()

proc extractErfStream*(erfData: string): TableRef[string, string] =
  result = newTable[string, string]()
  var strm = newStringStream(erfData)
  
  discard strm.readStr(16) # Skip "ERF V2.0"
  let fileCount = strm.readUint32()
  discard strm.readUint32() # delta years
  discard strm.readUint32() # delta days
  discard strm.readUint32() # padding

  for i in 0 ..< fileCount:
    strm.setPosition(32 + i.int * 72)
    let entryName = strm.readUtf16(64)
    let entryOffset = strm.readUint32()
    let entrySize = strm.readUint32()

    strm.setPosition(entryOffset.int)
    result[entryName] = strm.readStr(entrySize.int)
    
  strm.close()

proc buildErfStream*(files: TableRef[string, string]): string =
  var embeddedFilenames = newSeq[string]()
  for name in files.keys:
    embeddedFilenames.add(name)
  embeddedFilenames.sort()

  let fileCount = embeddedFilenames.len.uint32
  let nowTime = now()
  let deltaYears = (nowTime.year - 1900).uint32
  let janFirst = dateTime(nowTime.year, mJan, 1, 0, 0, 0, 0, local())
  let deltaDays = (nowTime - janFirst).inDays().uint32

  template align16(val: uint32): uint32 =
    let rem = val mod 16
    if rem == 0: val else: val + (16 - rem)

  var currentOffset = align16(32 + fileCount * 72)
  var tocEntries = newSeq[tuple[name: string, offset: uint32, size: uint32]]()

  for name in embeddedFilenames:
    let size = files[name].len.uint32
    tocEntries.add((name, currentOffset, size))
    currentOffset = align16(currentOffset + size)

  # THE FIX 1: currentOffset is the exact final byte size of the ERF.
  # Pre-allocate exactly that much memory to stop geometric doubling.
  var buffer = newStringOfCap(currentOffset.int)
  var strm = newStringStream(buffer)

  strm.writeUtf16("ERF V2.0", 16)
  strm.write(fileCount)
  strm.write(deltaYears)
  strm.write(deltaDays)
  strm.write(0xFFFFFFFF'u32)

  for entry in tocEntries:
    strm.writeUtf16(entry.name, 64)
    strm.write(entry.offset)
    strm.write(entry.size)

  for entry in tocEntries:
    while strm.getPosition() < entry.offset.int:
      strm.write(0'u8)
    strm.write(files[entry.name])

  # THE FIX 2: Do NOT use readAll(). It creates a massive redundant copy.
  # We extract the underlying string pointer directly.
  result = strm.data
  strm.close()