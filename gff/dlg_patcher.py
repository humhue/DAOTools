from . import gff_parser
from .gff_struct import gff_struct
import mmap
import multiprocessing
import os
import sys
import time

def patch_dlg(file_path):
    print(file_path)
    gff = gff_struct.parse_file(file_path)
    data_struct = gff_parser.generate_tree_struct(gff)
    data = data_struct.parse_file(file_path)

    with open(file_path, "r+b") as f, mmap.mmap(f.fileno(), 0) as mm:
        for conversation_line in data.CONVERSATION_LINE_LIST.List.reference_data.GenericWrapper:
            # if the reference pointer isnt 0xFFFFFFFF or 0x00
            # fix CONVERSATION_LINE_TEXT string
            offset = int(conversation_line\
                .reference_data.CONVERSATION_LINE_TEXT.TLKString.ECString.offset)
            if offset != 0xFFFFFFFF and offset != 0x00:
                tell = int(conversation_line\
                    .reference_data.CONVERSATION_LINE_TEXT.TLKString.ECString.tell)
                mm[tell:tell+4] = b"\x00\x00\x00\x00"

            conversation_line_cutscene = conversation_line.reference_data\
                .CONVERSATION_LINE_CUTSCENE.GenericWrapper.reference_data

            # then we fix CONVERSATION_LINE_CUTSCENE.CUTSCENE_ACTORS[X].CUTSCENE_ACTOR_ACTION_QUEUE[x].TEXT
            cutscene_actors = getattr(
                conversation_line_cutscene,
                "CUTSCENE_ACTORS",
                None,
            )
            if cutscene_actors is not None:
                for cutscene_actor in cutscene_actors.List.reference_data.ACTR:
                    for cutscene_actor_action in cutscene_actor\
                        .CUTSCENE_ACTOR_ACTION_QUEUE.List.reference_data\
                        .GenericWrapper:
                        text = getattr(cutscene_actor_action.reference_data, "TEXT", None)
                        if text is not None:
                            offset = int(text.TLKString.ECString.offset)
                            if offset != 0xFFFFFFFF and offset != 0x00:
                                tell = int(text.TLKString.ECString.tell)
                                mm[tell:tell+4] = b"\x00\x00\x00\x00"

            # finally, we fix CONVERSATION_LINE_CUTSCENE.CUTSCENE_HENCHMAN_ACTIONS[X].TEXT
            cutscene_henchman_actions = getattr(conversation_line_cutscene, "CUTSCENE_HENCHMAN_ACTIONS", None)
            if cutscene_henchman_actions is not None:
                if cutscene_henchman_actions.List.reference_data != None:
                    for cutscene_henchman_action in cutscene_henchman_actions.List.reference_data.GenericWrapper:
                        text = getattr(cutscene_henchman_action.reference_data, "TEXT", None)
                        if text is not None:
                            offset = int(text.TLKString.ECString.offset)
                            if offset != 0xFFFFFFFF and offset != 0x00:
                                tell = int(text.TLKString.ECString.tell)
                                mm[tell:tell+4] = b"\x00\x00\x00\x00"

def patch_all_dlgs(dir_path):
    dlg_filenames = [f for f in os.listdir(dir_path)\
        if os.path.isfile(os.path.join(dir_path, f))\
            and f.endswith(".dlg")\
    ]

    with multiprocessing.Pool() as pool:
        pool.map(
            patch_dlg,
            [
                os.path.join(dir_path, dlg_filename)
                for dlg_filename in dlg_filenames
            ]
        )

def main():
    # python3 dlg_patcher.py '/home/x/Documents/DA/QUDAO/extracted_files'
    t1 = time.time()

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to the extracted files")
        sys.exit(1)

    t1 = time.time()
    patch_all_dlgs(dir_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
