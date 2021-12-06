import gff_parser
from gff_struct import gff_struct
import mmap
import multiprocessing
import os
import sys
import time

def patch_dlg(file_path):
    gff = gff_struct.parse_file(file_path)
    data_struct = gff_parser.generate_tree_struct(gff)
    data = data_struct.parse_file(file_path)

    with open(file_path, "r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        for conversation_line in data.CONVERSATION_LINE_LIST.List.reference_data.GenericWrapper:
            tell = int(conversation_line\
                .reference_data.CONVERSATION_LINE_TEXT.TLKString.ECString.tell)
            mm[tell:tell+4] = b"\x00\x00\x00\x00"

            conversation_line_cutscene = conversation_line.reference_data\
                .CONVERSATION_LINE_CUTSCENE.GenericWrapper.reference_data

            cutscene_actors = getattr(conversation_line_cutscene, "CUTSCENE_ACTORS", None)
            if cutscene_actors is not None:
                for cutscene_actor in cutscene_actors.List.reference_data.ACTR:
                    for cutscene_actor_action in cutscene_actor\
                        .CUTSCENE_ACTOR_ACTION_QUEUE.List.reference_data\
                        .GenericWrapper:
                        text = getattr(cutscene_actor_action.reference_data, "TEXT", None)
                        if text is not None:
                            tell = int(text.TLKString.ECString.tell)
                            mm[tell:tell+4] = b"\x00\x00\x00\x00"

def patch_all_dlgs(dir_path):
    dlg_files = [f for f in os.listdir(dir_path) if os.path.isfile(dir_path + "/" + f) and f.endswith(".dlg")]

    with multiprocessing.Pool() as pool:
        pool.map(patch_dlg, [dir_path + "/" + dlg_file for dlg_file in dlg_files])

def main():
    # python3 dlg_patcher.py '/home/x/Documents/DA/QUDAO/extracted_files'
    t1 = time.time()


    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path with the extracted files")
        sys.exit(1)


    patch_all_dlgs(dir_path)


    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
