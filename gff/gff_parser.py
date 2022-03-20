from construct import *

def Reference(struct, data_offset):
    return Struct(
        "tell" / Tell,
        "offset" / Int32ul,
        "reference_data" / If(
            (this.offset != 0xFFFFFFFF) & (this.offset != 0x00),
            Pointer(this.offset+data_offset, struct),
        ),
    )

def ReferenceWithOffset(struct, offset, data_offset):
    return Struct(
        "reference_data" / If(
            (offset != 0xFFFFFFFF) & (offset != 0x00),
            Pointer(offset+data_offset, struct),
        ),
    )

def List(struct, data_offset):
    return "List" / Reference(
        Struct(
            "length" / Int32ul,
            struct.name / Array(this.length, struct),
        ),
        data_offset,
    )

def ECString(data_offset):
    return "ECString" / Reference(
        Struct(
            "length" / Int32ul,
            "string_data" / Prefixed(
                Computed(this.length * 2),
                CString("utf-16-le"),
            ),
        ), data_offset,
    )

def TLKString(data_offset):
    return "TLKString" / Struct(
        "index" / Int32ul, # index of the string in the TLK string table
        ECString(data_offset),
    )

Generic = "Generic" / Struct(
    #"tell" / Tell,
    "field_type" / Struct(
        "type_id" / Int16ul,
        "flags" / BitStruct(
            Padding(8),
            "is_list" / Flag,
            "is_struct" / Flag,
            "is_reference" / Flag,
            Padding(5),
        ),
    ),
    "reference_offset" / Int32ul,
)

struct_by_type_id = {        # as in the Dragon Age Toolset
    0: "UINT8" / Int8ul,     # BYTE
    1: "INT8" / Int8sl,      # CHAR
    2: "UINT16" / Int16ul,   # WORD
    3: "INT16" / Int16sl,    # SHORT
    4: "UINT32" / Int32ul,   # DWORD
    5: "INT32" / Int32sl,    # INT
    6: "UINT64" / Int64ul,   # DWORD64
    7: "INT64" / Int64sl,    # INT64
    8: "FLOAT32" / Float32l, # FLOAT
    9: "FLOAT64" / Float64l, # DOUBLE
    10: "Vector3f" / Padded(
        # theoretically, this should be just 'Array(3, Float32l)' (12 bits),
        # but, a structure/type seems to need to be a multiple of 8, that's
        # why we are wrapping the array into a 16 bit struct
        16,
        Array(3, Float32l), # this is a 12 bit-length array
        b"\x00", # the byte that has to be repeated to lengthen up to 16 bit
    ),
    12: "Vector4f" / Array(4, Float32l),
    13: "Quaternionf" / Array(4, Float32l),
    14: ECString,
    15: "Color4f" / Array(4, Float32l),
    16: "Matrix4x4f" / Array(16, Float32l),
    17: TLKString,
    0xFFFF: Generic,
}

class GenericWrapper(Subconstruct):
    def __init__(
        self,
        struct_array,
        data_offset,
        struct_by_type_id,
        label,
        structs, # the list of all the structs already parsed
        subcon,
    ):
        super().__init__(subcon)
        self.struct_array = struct_array
        self.data_offset = data_offset
        self.struct_by_type_id = struct_by_type_id
        self.label = label
        self.structs = structs

    def _parse(self, stream, ctx, path):
        obj = self.subcon._parse(stream, ctx, path)

        if obj.field_type.flags.is_struct:
            if (
                obj.field_type.type_id == 65535
                and obj.field_type.flags.is_list
                and obj.field_type.flags.is_reference
            ):
                # this occurs when a generic struct field is empty,
                # like a CUT in NTRY's CONVERSATION_LINE_CUTSCENE
                # it would be better to check for 0xFFFF, but this works too
                new_type = Pass
            else:
                if self.structs is None:
                    new_type = generate_struct_(
                        struct=self.struct_array[obj.field_type.type_id],
                        struct_array=self.struct_array,
                        data_offset=self.data_offset,
                        struct_by_type_id=self.struct_by_type_id,
                        new_structs=self.structs,
                    )
                else:
                    struct_type = self.struct_array[obj.field_type.type_id]\
                        .struct_type
                    new_type = self.structs[struct_type]
        else:
            if (
                field.field_type.type_id == 14
                or field.field_type.type_id == 17
            ):
                new_type = self.struct_by_type_id[obj.field_type.type_id]
            else:
                new_type = self.struct_by_type_id[obj.field_type.type_id]

        if obj.field_type.flags.is_list and new_type != Pass:
            new_type = List(new_type, self.data_offset)

        new_type = ReferenceWithOffset(
            new_type,
            obj.reference_offset,
            self.data_offset,
        )

        return new_type._parse(stream, ctx, path)

def convert_to_struct(key, values, struct_size):
    return key / Padded(
        struct_size,
        Struct(
            *values,
        ),
        b"\xFF",
    )

def generate_struct_(
    struct,
    struct_array,
    data_offset,
    struct_by_type_id,
    new_structs=None,
):
    if (
        new_structs is not None
        and new_structs.get(struct.struct_type) is not None
    ):
        return new_structs[struct.struct_type]

    # else

    type_ids = {}
    # should be something like {6: Int8, 0: String, ...}, unordered

    for field in struct.field_array:
        if field.field_type.flags.is_struct:
            # if it's a struct, we have to break it down
            new_type = generate_struct_(
                struct=struct_array[field.field_type.type_id],
                struct_array=struct_array,
                data_offset=data_offset,
                struct_by_type_id=struct_by_type_id,
                new_structs=new_structs,
            )
        else:
            # if it's a field, we can process it as such
            if (
                field.field_type.type_id == 14
                or field.field_type.type_id == 17
            ):
                new_type = struct_by_type_id[field.field_type.type_id](data_offset)
            else:
                new_type = struct_by_type_id[field.field_type.type_id]

            if field.field_type.type_id == 0xFFFF:
                # if it's a generic, we need to wrap it lmao i hate this
                new_type = "GenericWrapper" / GenericWrapper(
                    struct_array,
                    data_offset,
                    struct_by_type_id,
                    field.label,
                    new_structs,
                    new_type,
                )

        if field.field_type.flags.is_list:
            new_type = List(new_type, data_offset)

        new_type = field.label / Struct(new_type)
        type_ids[field.index] = new_type

    # type_ids should be something like {6: Int8, 0: String, ...}
    ordered_type_ids = [t[1] for t in sorted(type_ids.items())]
    # ordered_type_ids should be something like [String, Int8, ...]
    # this' needed because fields and structs in GFF aren't ordered by index


    new_struct_ = convert_to_struct(
        struct.struct_type, # name of the struct
        ordered_type_ids,
        struct.struct_size,
    ) # we get a named struct from ordered_type_ids

    if new_structs is not None:
        new_structs[struct.struct_type] = new_struct_

    return new_struct_

# struct_by_type_id

def generate_all_structs(gff):
    structs = {}
    for struct in gff.struct_array:
        generate_struct_(
            struct,
            gff.struct_array,
            gff.header.data_offset,
            struct_by_type_id,
            structs,
        )
    return structs

def generate_tree_struct(gff):
    # it creates every struct, the root one (gff.struct_array[0]) too
    all_structs = generate_all_structs(gff)
    struct = generate_struct_(
        gff.struct_array[0],
        gff.struct_array,
        gff.header.data_offset,
        struct_by_type_id,
        all_structs,
    )
    return Pointer(gff.header.data_offset, struct)
