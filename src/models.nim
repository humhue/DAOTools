# models.nim
include mem_wrapper

type
  TlkEntry* = object
    line*: string
    node_path*: string

  Dummy* = ref object
    label*: uint32
    type_id*: uint16
    index*: uint32
    is_list*, is_struct*, is_reference*: bool
    parent*: Dummy

  GffStruct* = ref object
    struct_type*: string
    size*: uint32
    field_count*: uint32
    list*: seq[Dummy]
    should_parse*: bool

  GffFileContext* = ref object
    data_offset*: uint32
    erf_filename*, filename*: string
    base_addr*: int
    struct_array*: seq[GffStruct]
    tlkDict*: TableRef[uint32, TlkEntry] # TableRef is a pointer to a Table

  GffFile* = ref object
    erf_file_path*, file_path*: string
    struct_array*: seq[GffStruct]
    struct_array_data_offset*: uint32
    data_offset*: uint32
    file_type*, file_version*: string
    # mm*: MemFile
    mm*: MemBuffer # Changed from MemFile to MemBuffer
    base_addr*: int
    tlkDict*: TableRef[uint32, TlkEntry] # TableRef is a pointer to a Table