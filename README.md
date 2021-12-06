# DAOTools
This is a set of tools for Dragon Age: Origins modding.
It can patch .dlg files text lines, build an .erf file and view the contents of files in GFF and ERF format.

I did this to fix the text lines of .dlg files, that once edited in the Dragon Age Toolset, from not being language-specific, got replaced with english ones.

I noticed, that the original .dlg files of the game, had both NTRY and RPLY CONVERSATION_LINE_TEXT set like this:

    string_offset = 0
while the modified QUDAO .dlg files had either:
  
    string_offset = 4294967295 (0xFFFFFFFF) (I don't know what this is for, but in the toolset this is represented as '{index}:', while 0x00 is '{index}')
    
    or:
  
    string_offset = an offset pointing to a string

Replacing the string offset with 0 is enough to fix this
The program looks for CONVERSATION_LINE_TEXT (actually not only that), and edits the string offset to 0 (without deleting the orphaned data, since the size difference is minimal)
It does this for every .dlg file inside a directory with extracted .erf files, and builds the .erf file again

The program is pretty slow at patching .dlg files because parsing the whole file is involved in the process
When patching the whole QUDAO files extracted from the .erf file, it can need as long as 10 minutes to process, it depends on the number of cores you CPU can employ at the same time: feel free to report the execution time  

# How to use it
    pip3 install construct
    git clone https://github.com/humhue/DAOTools.git
    python3 DAOTools 'directory_path_to_extracted_files' 'erf_file_name_patched.erf'
