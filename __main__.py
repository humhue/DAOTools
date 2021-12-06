import dlg_patcher
import erf_builder
import os
import sys

def main():
    # python3 erf_builder.py '/home/x/Documents/DA/QUDAO/extracted_files' 'qwinn_fixpack_3_module_patched.erf'

    try:
        dir_path = sys.argv[1]
    except IndexError:
        print("You did not specify a path with the extracted files")
        sys.exit(1)

    try:
        filename = sys.argv[2] # qwinn_fixpack_3_module_patched.erf
    except IndexError:
        print("You did not specify a path for the .erf file")
        sys.exit(1)

    file_path = os.getcwd() + "/" + filename

    print("Patching .dlg files...")
    dlg_patcher.patch_all_dlgs(dir_path)
    print("Finished patching!")
    print("Now building the .erf file...")
    erf_builder.build_erf(dir_path, file_path)
    print("Finished building!")

if __name__ == "__main__":
    main()
