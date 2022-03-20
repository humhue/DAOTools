from . import gff_parser
from .gff_struct import gff_struct
import mmap
import multiprocessing
import os
import sys
import time

def patch_tlk(file_path):
    print(file_path)
    gff = gff_struct.parse_file(file_path)
    data_struct = gff_parser.generate_tree_struct(gff)
    data = data_struct.parse_file(file_path)

    with open(file_path, "r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        # we fix data.TALK_STRING_LIST.List.reference_data.STRN[x]
        for talk_string in data.TALK_STRING_LIST.List.reference_data.STRN:
            offset = int(talk_string.TALK_STRING.ECString.offset)
            if offset != 0xFFFFFFFF and offset != 0x00:
                tell = int(talk_string.TALK_STRING.ECString.tell)
                mm[tell:tell+4] = b"\x00\x00\x00\x00"

def patch_all_tlks(dir_path):
    tlk_filenames = [f for f in os.listdir(dir_path)\
        if os.path.isfile(os.path.join(dir_path, f))\
            and f.endswith(".tlk")\
    ]

    with multiprocessing.Pool() as pool:
        pool.map(
            patch_tlk,
            [
                os.path.join(dir_path, tlk_filename)
                for tlk_filename in tlk_filenames
            ]
        )

def main():
    # python3 tlk_patcher.py '/home/x/Documents/DA/QUDAO/extracted_files'
    t1 = time.time()

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to the extracted files")
        sys.exit(1)

    t1 = time.time()
    patch_all_tlks(dir_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
