from . import gff_parser
from .gff_struct import gff_struct
import mmap
import multiprocessing
import os
import sys
import time

def patch_plo(file_path):
    print(file_path)
    gff = gff_struct.parse_file(file_path)
    data_struct = gff_parser.generate_tree_struct(gff)
    data = data_struct.parse_file(file_path)

    with open(file_path, "r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        for plot in data.PLOT_PLOTS.List.reference_data.PLOT:
            # we fix first data.PLOT_PLOTS.List.reference_data.PLOT[x].PLOT_NAME
            tell = plot.PLOT_NAME.TLKString.ECString.tell
            mm[tell:tell+4] = b"\x00\x00\x00\x00"

            for flag in plot.PLOT_FLAGS.List.reference_data.FLAG:
                # and then data.PLOT_PLOTS.List.reference_data.PLOT[x].PLOT_FLAGS.List.reference_data.FLAG[x].PLOT_FLAG_JOURNAL
                tell = flag.PLOT_FLAG_JOURNAL.TLKString.ECString.tell
                mm[tell:tell+4] = b"\x00\x00\x00\x00"

def patch_all_plos(dir_path):
    plo_filenames = [f for f in os.listdir(dir_path)\
        if os.path.isfile(os.path.join(dir_path, f))\
            and f.endswith(".plo")\
    ]

    with multiprocessing.Pool() as pool:
        pool.map(patch_plo, [os.path.join(dir_path, plo_filename) for plo_filename in plo_filenames])

def main():
    # python3 plo_patcher.py '/home/x/Documents/DA/QUDAO/extracted_files'
    t1 = time.time()

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to the extracted files")
        sys.exit(1)

    t1 = time.time()
    patch_all_plos(dir_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
