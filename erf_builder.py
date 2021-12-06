import datetime
import os
import shutil
import struct
import sys
import time

def int32(n):
    return struct.pack("<I", n)

def utf16(s):
    return s.encode("utf-16-le")

def build_erf(dir_path, file_path):
    embedded_files = [f for f in os.listdir(dir_path) if os.path.isfile(dir_path + "/" + f)]
    file_count = len(embedded_files)

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

        data_block_offset = 32 + file_count * 72 # header_length + file_count * table_of_contents_length
        acc = data_block_offset
        for embedded_file in embedded_files:
            bytes_.extend(utf16(embedded_file)) # name
            bytes_.extend(bytes(64 - len(embedded_file) * 2)) # so that the name is 64 byte long
            bytes_.extend(int32(acc)) # offset
            size = os.path.getsize(dir_path + "/" + embedded_file) # get the size of the file in bytes
            bytes_.extend(int32(size)) # size of the file in bytes
            acc += size

        erf_file.write(bytes_)

        # erf_file.tell() is now data_block_offset
        for embedded_file in embedded_files:
            with open((dir_path + "/" + embedded_file), "rb") as embedded_f:
                # copy the data of the embedded_file to the erf_file
                shutil.copyfileobj(embedded_f, erf_file)

def main():
    # python3 erf_builder.py '/home/x/Documents/DA/QUDAO/extracted_files' 'qwinn_fixpack_3_module_patched.erf'
    t1 = time.time()


    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path with the extracted files")
        sys.exit(1)

    try:
        file_path = sys.argv[2]
    except IndexError:
        print("You did not specify a path for the .erf file")
        sys.exit(1)

    build_erf(dir_path, file_path)


    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
