# DAOTools
This is a set of tools for Dragon Age: Origins modding.\
This package can patch language-specific .dlg files, extract and build .erf files, and view the contents of files in GFF and ERF format.\
I made this to fix the text lines of .dlg files, that once edited in the original Dragon Age Toolset, from not being language-specific, got replaced with english text.

# How does it work
I noticed, that the original .dlg files of the game, had both NTRY and RPLY *CONVERSATION_LINE_TEXT* set like this:\
    string_offset = 0\
while the modified QUDAO .dlg files had either:\
    string_offset = 4294967295 (0xFFFFFFFF)
    (I don't know what this is for, but in the toolset this is represented as '{index}:', while 0x00 is '{index}')\
    or:\
    string_offset = an offset pointing to a string

Replacing the string offset with 0 is enough to fix this.\
The program extracts the contents of an .erf file, then, for each .dlg file looks for *CONVERSATION_LINE_TEXT* (actually not only that), edits the string offset to 0 (without deleting the orphaned data, since the size difference is minimal), and after doing that, it builds the .erf file again.

The program is pretty slow at patching .dlg files, because all of them have to be parsed.\
When patching all of the QUDAO files extracted from the .erf file (242 .dlg files), it can need as long as 10 minutes to process them: it depends on the number of cores your CPU has got, feel free to report the execution time in the related issue.

# How to use it
    pip3 install construct
    git clone https://github.com/humhue/DAOTools.git
    python3 DAOTools old.erf patched.erf

# How to fix QUDAO
If you want, you can just download the patched files in the release section and install them, if you don't, follow the next steps.

First, set up this package as explained previously.\
Then, download QUDAO at *https://www.nexusmods.com/dragonage/mods/4689/?tab=files*. \
Extract the .zip file and the .dazip file (like a normal .zip)\
Now browse to *Contents/addins/qwinn_fixpack_3/module/data*, you'll find a file named *qwinn_fixpack_3_module.erf*, that's the one we have to patch.\
Assuming that we have this package installed, we can write in the path we did it the command:

    python3 DAOTools qwinn_fixpack_3_module.erf qwinn_fixpack_3_module_patched.erf

After this, we can delete the original .erf in *Contents/addins/qwinn_fixpack_3/module/data*, replace it with the patched version, and change the name again to *qwinn_fixpack_3_module.erf*.\
You now have to zip the *Contents* directory with the *Manifest.xml* file, and rename it *QUDAO Fixpack v3
_5_patched.dazip* or whatever you feel like.
Now all you have to do is to install the .dazip file as you normally would.
