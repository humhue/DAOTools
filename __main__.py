import dlg_patcher
import erf_builder
import os
import sys
import time

def main():
    # python3 erf_builder.py '/home/x/Documents/DA/QUDAO/extracted_files' 'qwinn_fixpack_3_module_patched.erf'

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path with the extracted files")
        sys.exit(1)

    try:
        file_path = sys.argv[2] # qwinn_fixpack_3_module_patched.erf
    except IndexError:
        print("You did not specify a path for the .erf file")
        sys.exit(1)  
    
    print("Patching .dlg files...")
    t1 = time.time()
    dlg_patcher.patch_all_dlgs(dir_path)
    t2 = time.time() - t1
    print("Finished patching in " + str(t2) + "s!")
    
    print("Now building the .erf file...")
    t1 = time.time()
    erf_builder.build_erf(dir_path, file_path)
    t2 = time.time() - t1
    print("Finished building in " + str(t2) + "s!")

if __name__ == "__main__":
    main()
