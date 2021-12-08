import os
import re

label_file_path = os.path.join(
    os.path.dirname(__file__),
    "GFFIDList.txt",
)

def load_id_names():
    name_by_id = {}
    id_by_name = {}
    # the DA toolset doesn't load __deprecated__ labels, but we are doing it anyway
    pattern = re.compile(r"(?:__deprecated__)?[GC]FF(?:STRUCT)?_(\w*)\s*=\s*(\d+)")
    with open(label_file_path) as f:
        for line in f:
            m = pattern.match(line)
            if m:
                name, id = m.groups()
                name_by_id[int(id)] = name
                id_by_name[name] = int(id)
    return name_by_id, id_by_name
