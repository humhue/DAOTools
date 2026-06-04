# mem_wrapper.nim

type
  MemSourceKind* = enum msFile, msString
  
  MemBuffer* = object
    mem*: pointer    # The raw C-pointer your parsers actually use
    size*: int       # The size of the buffer
    case kind*: MemSourceKind
    of msString:
      sData: string  # IMPORTANT: This keeps the RAM alive so the GC doesn't delete it
    of msFile:
      fData: MemFile # The legacy file map (if somebody still needs to load physical files)

# 1. Initialize from a RAM Stream (The new way)
proc openMemStream*(data: sink string): MemBuffer =
  result = MemBuffer(kind: msString, sData: data)
  if result.sData.len > 0:
    result.mem = addr result.sData[0]
    result.size = result.sData.len
  else:
    result.mem = nil
    result.size = 0

# 2. Initialize from a Physical File (The legacy way)
proc openMemFile*(path: string): MemBuffer =
  let mf = memfiles.open(path, fmReadWrite)
  result = MemBuffer(kind: msFile, fData: mf, mem: mf.mem, size: mf.size)

# 3. Retrieve the patched string to zip it back up
proc getStreamData*(mb: MemBuffer): string =
  doAssert mb.kind == msString, "Cannot extract string from a file-backed buffer"
  return mb.sData

# 4. Safe close
proc close*(mb: var MemBuffer) =
  if mb.kind == msFile:
    mb.fData.close()