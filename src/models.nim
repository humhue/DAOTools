# models.nim
include mem_wrapper

const
  # Stringrefs below this are BioWare's own: the game resolves them from its
  # shipped talk table, so blanking them is the whole point of the tool.
  # At or above it the string is mod-authored and exists nowhere else, so its
  # inline fallback must be preserved or replaced from the translation index.
  CustomStringRefBase* = 610000000'u32

type
  TlkEntry* = object
    line*: string
    node_path*: string

  TranslationIndex* = ref object
    ## User-supplied translations. A file-specific value wins over a global
    ## string-ID value. Tables are refs because this type is passed through all
    ## of the parsers and archive layers.
    byId*: TableRef[uint32, string]
    byFile*: TableRef[string, TableRef[uint32, string]]

  DiscoveryIndex* = TableRef[string, TableRef[uint32, TlkEntry]]
    ## resource key -> string ID -> source text and human-readable trace

  Gff4StringSite* = object
    ref_offset*: uint32
    string_ref*: uint32
    embedded_line*: string

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
    resource_key*: string
    base_addr*: int
    struct_array*: seq[GffStruct]
    discovered*: DiscoveryIndex
    translations*: TranslationIndex
    string_sites*: seq[Gff4StringSite]

  GffFile* = ref object
    erf_file_path*, file_path*: string
    struct_array*: seq[GffStruct]
    struct_array_data_offset*: uint32
    data_offset*: uint32
    file_type*, file_version*: string
    # mm*: MemFile
    mm*: MemBuffer # Changed from MemFile to MemBuffer
    base_addr*: int
    resource_key*: string
    discovered*: DiscoveryIndex
    translations*: TranslationIndex
    string_sites*: seq[Gff4StringSite]
