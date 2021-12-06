# DAOTools
This is a set of tools for Dragon Age: Origins modding.\
It can patch the text lines of .dlg files, build an .erf file, and view the contents of files in GFF and ERF format.

I did this to fix the text lines of .dlg files, that once edited in the Dragon Age Toolset, from not being language-specific, got replaced with english ones.

I noticed, that the original .dlg files of the game, had both NTRY and RPLY CONVERSATION_LINE_TEXT set like this:\
    string_offset = 0\
while the modified QUDAO .dlg files had either:\
    string_offset = 4294967295 (0xFFFFFFFF) (I don't know what this is for, but in the toolset this is represented as '{index}:', while 0x00 is '{index}')\
    or:\
    string_offset = an offset pointing to a string

Replacing the string offset with 0 is enough to fix this.\
The program looks for CONVERSATION_LINE_TEXT (actually not only that), and edits the string offset to 0 (without deleting the orphaned data, since the size difference is minimal).\
It does this for every .dlg file inside a directory with extracted .erf files, and builds the .erf file again.

The program is pretty slow at patching a .dlg file, because parsing the whole file is required.\
When patching all of the QUDAO files extracted from the .erf file (242 .dlg files), it can need as long as 10 minutes to process them: it depends on the number of cores your CPU has got, feel free to report the execution time in the related issue. 

# How to use it
    pip3 install construct
    git clone https://github.com/humhue/DAOTools.git
    python3 DAOTools 'directory_path_to_extracted_files' 'new_erf_file_patched.erf'

# How to fix QUDAO
First, set up this library as explained in the previous step.\
Then, download QUDAO at 'https://www.nexusmods.com/dragonage/mods/4689/?tab=files'. \
Extract the .zip file and the .dazip file (as if it was a normal .zip)\
Now browse to Contents/addins/qwinn_fixpack_3/module/data, you'll find the 'qwinn_fixpack_3_module.erf' file.\
That's the file we have to patch.\
You can extract the files inside an .erf by using the Dragon Age Toolset.\
Assumed that we have this library installed, we can write in the path we cloned it the command:\
    python3 DAOTools 'directory_path_to_extracted_files' 'qwinn_fixpack_3_module_patched.erf'\
After this, we can delete the .erf in Contents/addins/qwinn_fixpack_3/module/data, replace it with the patched version, and change the name again to 'qwinn_fixpack_3_module.erf'.\
You now have to zip the 'Contents' dir with the 'Manifest.xml' file, and rename it 'QUDAO Fixpack v3
_5_patched.dazip' or whatever you feel like.
Now all you have to do is to install the .dazip file as you normally would.
