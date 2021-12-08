import datetime
import os
import struct
import sys
import time

def int32(n):
    return struct.pack("<I", n)

def utf16(s):
    return s.encode("utf-16-le")

def build_erf(dir_path, file_path):
    embedded_filenames = sorted([f for f in os.listdir(dir_path)\
        if os.path.isfile(os.path.join(dir_path, f))\
    ])
    file_count = len(embedded_filenames)

    today = datetime.date.today()
    this_year = int(today.strftime("%Y"))
    january_first = datetime.date(this_year, 1, 1)
    delta_years = this_year - 1900
    delta_days = (today - january_first).days

    with open(file_path, "wb") as erf_file:
        bytes_ = bytearray(utf16("ERF V2.0"))
        bytes_.extend(int32(file_count))
        bytes_.extend(int32(delta_years))
        bytes_.extend(int32(delta_days))
        bytes_.extend(b"\xFF\xFF\xFF\xFF")

        data_block_offset = 32 + file_count * 72 # header_length + file_count * table_of_content_length
        acc = data_block_offset
        for embedded_filename in embedded_filenames:
            bytes_.extend(utf16(embedded_filename)) # name
            bytes_.extend(bytes(64 - len(embedded_filename) * 2)) # so that the name is 64 byte long
            bytes_.extend(int32(acc)) # offset
            size = os.path.getsize(os.path.join(dir_path, embedded_filename)) # get the size of the file in bytes
            bytes_.extend(int32(size)) # size of the file in bytes
            acc += size

        # flush bytes_
        erf_file.write(bytes_)

        # erf_file.tell() is now data_block_offset

        for embedded_filename in embedded_filenames:
            with open(os.path.join(dir_path, embedded_filename), "rb") as embedded_file:
                # read the data from embedded_file and write it to erf_file
                data = embedded_file.read()
                erf_file.write(data)

def main():
    # python3 erf_builder.py '/home/x/Documents/DA/QUDAO/extracted_files' 'qwinn_fixpack_3_module_patched.erf'

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to the extracted files")
        sys.exit(1)

    try:
        file_path = sys.argv[2]
    except IndexError:
        print("You did not specify a path for the .erf file")
        sys.exit(1)

    t1 = time.time()
    build_erf(dir_path, file_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
