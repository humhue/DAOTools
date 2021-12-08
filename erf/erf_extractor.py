import os
import shutil
import struct
import sys
import time

def unpack_int32(buf):
    return struct.unpack("<I", buf)[0]

def unpack_utf16(buf):
    return struct.unpack("<"+str(len(buf))+"s", buf)[0]\
        .decode("utf-16-le")\
        .encode("utf-8")\
        .rstrip(b"\x00")\
        .decode("utf-8")

def extract_erf(file_path, dir_path):
    try:
        os.mkdir(dir_path)
    except FileExistsError:
        shutil.rmtree(dir_path)
        os.mkdir(dir_path)

    with open(file_path, "rb") as erf_file:
        header = erf_file.read(32)
        # magic = unpack_utf16(header[:16])
        file_count = unpack_int32(header[16:20])
        # delta_years = unpack_int32(header[20:24])
        # delta_days = unpack_int32(header[24:28])
        # padding = unpack_int32(header[28:32])

        toc_length = file_count * 72 # file_count * table_of_contents_length
        toc = erf_file.read(toc_length) # table_of_contents
        counter = 0
        for _ in range(file_count):
            entry_name = unpack_utf16(toc[counter:counter+64])
            entry_offset = unpack_int32(toc[counter+64:counter+68])
            entry_size = unpack_int32(toc[counter+68:counter+72])
            counter += 72

            # we have to seek here, because the original DA Toolset or whatever
            # some people (namely Qwinn) used to build .erf files, can add a
            # certain number of 0 bytes before a file content, so that
            # (toc[i].entry_offset + toc[i].entry_size) == toc[i+1].entry_offset
            # is not always true
            erf_file.seek(entry_offset)
            with open(os.path.join(dir_path, entry_name), "wb") as embedded_file:
                # read the data from erf_file and write it to embedded_file
                data = erf_file.read(entry_size)
                embedded_file.write(data)

def main():
    # python3 erf_extractor.py 'qwinn_fixpack_3_module.erf' '/home/x/Documents/DA/QUDAO/extracted_files'

    try:
        file_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path to an .erf file")
        sys.exit(1)

    try:
        dir_path = sys.argv[2]
    except IndexError:
        print("You did not specify a path for the extracted files")
        sys.exit(1)

    t1 = time.time()
    extract_erf(file_path, dir_path)
    t2 = time.time() - t1
    print(str(t2)+"s")

if __name__ == "__main__":
    main()
