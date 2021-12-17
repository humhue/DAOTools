from . import gff_parser
from .gff_struct import gff_struct
import mmap
import multiprocessing
import os
import sys
import time

def patch_cut(file_path):
    print(file_path)
    gff = gff_struct.parse_file(file_path)
    data_struct = gff_parser.generate_tree_struct(gff)
    data = data_struct.parse_file(file_path)

    with open(file_path, "r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        # first we fix data.CUTSCENE_ACTORS[X].CUTSCENE_ACTOR_ACTION_QUEUE[x].TEXT
        cutscene_actors = getattr(data, "CUTSCENE_ACTORS", None)
        if cutscene_actors is not None:
            for cutscene_actor in cutscene_actors.List.reference_data.ACTR:
                for cutscene_actor_action in cutscene_actor\
                    .CUTSCENE_ACTOR_ACTION_QUEUE.List.reference_data\
                    .GenericWrapper:
                    text = getattr(cutscene_actor_action.reference_data, "TEXT", None)
                    if text is not None:
                        tell = int(text.TLKString.ECString.tell)
                        mm[tell:tell+4] = b"\x00\x00\x00\x00"

        # then, we fix data.CUTSCENE_HENCHMAN_ACTIONS[X].TEXT
        cutscene_henchman_actions = getattr(data, "CUTSCENE_HENCHMAN_ACTIONS", None)
        if cutscene_henchman_actions is not None:
            if cutscene_henchman_actions.List.reference_data != None:
                for cutscene_henchman_action in cutscene_henchman_actions.List.reference_data.GenericWrapper:
                    text = getattr(cutscene_henchman_action.reference_data, "TEXT", None)
                    if text is not None:
                        tell = int(text.TLKString.ECString.tell)
                        mm[tell:tell+4] = b"\x00\x00\x00\x00"


def patch_all_cuts(dir_path):
    cut_filenames = [f for f in os.listdir(dir_path)\
        if os.path.isfile(os.path.join(dir_path, f))\
            and f.endswith(".cut")\
    ]

    with multiprocessing.Pool() as pool:
        pool.map(patch_cut, [os.path.join(dir_path, cut_filename) for cut_filename in cut_filenames])

def main():
    # python3 cut_patcher.py '/home/x/Documents/DA/QUDAO/extracted_files'
    t1 = time.time()

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to the extracted files")
        sys.exit(1)

    t1 = time.time()
    patch_all_cuts(dir_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
