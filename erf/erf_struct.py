from construct import *

def utf_16_string(length):
    return Prefixed(
        Computed(length * 2),
        CString("utf-16-le"),
    )

erf_struct = Struct(
    "header" / Struct(
        # all values are little-endian
        Const(b"E\x00R\x00F\x00 \x00V\x002\x00.\x000\x00"), # ERF V2.0
        "file_count" / Int32ul, # number of elements in the file (and Table of Contents)
        "year" / Int32ul, # the year since 1900
        "day" / Int32ul, # the day since January 1st
        "padding" / Int32ul, # always 0xFFFFFFFF? Probably it's just a padding
    ),
    "table_of_contents" / Array(
        this.header.file_count,
        Struct(
            "name" / utf_16_string(32), # name of the entry
            "offset" / Int32ul, # offset to entry file data, from start of ERF file
            "size" / Int32ul, # length of file data
        ),
    ),
)

def main():
    filename = '/home/x/Documents/DA/QUDAO/Contents/addins/qwinn_fixpack_3/module/data/qwinn_fixpack_3_module.erf'

    erf = erf_struct.parse_file(filename)
    print(erf)

if __name__ == "__main__":
    main()
