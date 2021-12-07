import dlg_patcher
import erf_builder
import erf_extractor
import sys
import tempfile
import time

def main():
    # python3 erf_builder.py '/home/x/Documents/DA/QUDAO/extracted_files' 'qwinn_fixpack_3_module_patched.erf'

    try:
        old_file_path = sys.argv[1] # qwinn_fixpack_3_module.erf
    except IndexError:
        print("You did not specify a path to an .erf file")
        sys.exit(1)

    try:
        new_file_path = sys.argv[2] # qwinn_fixpack_3_module_patched.erf
    except IndexError:
        print("You did not specify a path for the .erf file")
        sys.exit(1)

    with tempfile.TemporaryDirectory() as dir_path:
        print("Extracting the files...")
        t1 = time.time()
        erf_extractor.extract_erf(old_file_path, dir_path)
        t2 = time.time() - t1
        print("Finished extracting in " + str(t2) + "s!")

        print("Patching .dlg files...")
        t1 = time.time()
        dlg_patcher.patch_all_dlgs(dir_path)
        t2 = time.time() - t1
        print("Finished patching in " + str(t2) + "s!")

        print("Building the .erf file...")
        t1 = time.time()
        erf_builder.build_erf(dir_path, new_file_path)
        t2 = time.time() - t1
        print("Finished building in " + str(t2) + "s!")

if __name__ == "__main__":
    main()
