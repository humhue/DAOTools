from construct import *
from .utils import load_id_names

name_by_id, id_by_name = load_id_names()

class Label(Adapter):
    def _decode(self, obj, ctx, path):
        return name_by_id[obj]
    def _encode(self, obj, ctx, path):
        return id_by_name[obj]

gff_struct = Struct(
    "header" / Struct(
        # The first five fields are always in big endian and never byteswapped.
        # This keeps those fields human readable on any machine.
        Const(b"GFF "),
        "version" / PaddedString(4, "utf-8"), # version of the format | should be always "V4.0"
        "platform" / PaddedString(4, "utf-8"), # target platform for the file | either "PS3 ", "X360" or "PC  "
        "file_type" / PaddedString(4, "utf-8"), # used to identify the file type | often extension, but it's "CONV" for dlg files
        "file_type_version" / PaddedString(4, "utf-8"), # the version of the file type | should be "Vx.x" or "xx.x" where x is a digit
        "struct_count" / Int32ul, # number of elements in the Struct Array
        "data_offset" / Int32ul, # offset from the beginning of the file to the Raw Data Block.
    ),
    "struct_array" / Array(
        this.header.struct_count,
        Struct(
            "struct_type" / PaddedString(4, "utf-8"), # programmer defined ID, like NTRY, RPLY, ASLN
            "field_count" / Int32ul, # number of fields in struct
            "field_offset" / Int32ul, # offset from the beginning of the file to the first field in the struct
            "struct_size" / Int32ul, # size of the chunk of data representing the struct

            "field_array" / Pointer(
                this.field_offset,
                Array(
                    this.field_count,
                    Struct(
                        "label" / Label(Int32ul), # used to look up the field | GFFID of BinaryGFFIDList.h

                        "field_type" / Struct(
                            "type_id" / Int16ul, # number indicating the type
                            "flags" / BitStruct( # 2-byte bit flags
                                Padding(8),
                                "is_list" / Flag, # if set, the type is a list of type_id
                                "is_struct" / Flag, # if set, the type is struct_array[type_id]
                                "is_reference" / Flag, # if set, the type is a reference to type_id
                                Padding(5),
                            ),
                        ), # describing the type of the field
                        "index" / Int32ul, # starting from the beginning of the struct in the data block
                    ),
                ),
            ),
        ),
    ),
)
