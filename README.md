# DAOTools

**QUDAO FIXPACK DISCLAIMER**

I am not the author of the QUDAO Fixpack (originally created by Paul Escalona / Qwinn). I initially created this toolset specifically to patch QUDAO and make its text non-language-specific, allowing non-English speakers to enjoy the mod.

**Want an international version of the fixpack?** Out of respect for the original author's permissions, I do not host pre-patched mod files. Instead, simply download this program from the [Release Section](https://github.com/humhue/DAOTools/releases), download the original mod from NexusMods, and run the `.dazip` through the patcher. It is fully automated and takes less than a second!

---

## What is this?
DAOTools is a utility for Dragon Age: Origins modding. 

When you edit most modding files (even for trivial fixes) using the original Bioware DA Toolset, any text inside them is often forced into English. This ruins the experience for international players. This tool automatically patches mod files to remove language-specific string references, making the mods compatible with any language version of the game.

**Features:**
* **Cross-Platform GUI:** A brand new, user-friendly graphical interface—no more command-line Python scripts!
* **Direct DAZIP Patching:** No need to manually extract archives. Select a `.dazip`, and the tool will patch every compatible file inside it automatically.
* **Generic GFF3.2 Support:** Patches `.are, .lst, .utc, .uti, .utm, .utp, .utt`. (This fixes location names and item names resetting to English. *Note: Fixing item names requires starting a new playthrough, as the English names get baked directly into existing save files.*)
* **Generic GFF4.0 Support:** Patches `.cub, .cut, .dlb, .dlg, .plo, .stg` (Fixes dialogue and plot text).
* **ERF Management:** Extract and build `.erf` archives directly from the UI.
* **In-Memory Processing:** Processes data in RAM using streams for maximum efficiency.

## How does it work?
The tool unpacks the target archive and parses the underlying GFF files. Whenever it finds a language-specific string reference, it simply edits the string offset to `0`. It intentionally leaves the orphaned text data in the file to prevent breaking the archive structure, as the size difference is completely negligible. 

## Version 2.0 Changelog (The Nim Rewrite)
DAOTools has been completely rewritten from the ground up in the **Nim** programming language, moving away from the legacy Python codebase. 
* **Native GUI Added:** Full graphical interface built with NiGui.
* **Massive Speed Increase:** The previous Python script took up to **10 minutes** to parse large mods like QUDAO. By utilizing lazy-evaluation, RAM-streams, and C-level compilation, DAOTools v2.0 patches the exact same archive in **~450 milliseconds** (over a 1300x speedup).
* **Expanded Format Support:** Added generic support for GFF 3.2.
* *Note: The legacy read-only GFF parser has been dropped, as better dedicated tools exist for viewing raw data.*

## Installation & Compilation
If you just want to use the tool, download the compiled executable for your OS from the **Releases** tab. 

If you want to compile the tool yourself from the source code, you will need the [Nim Compiler](https://nim-lang.org/):

```bash
# Clone the repository
git clone [https://github.com/humhue/DAOTools.git](https://github.com/humhue/DAOTools.git)
cd DAOTools

# Compile the GUI (MacOS Example)
nim c -d:danger --mm:arc --opt:speed --app:"gui" --passC:"-flto -O3" --passL:"-flto -O3 -Wl,-rpath,/opt/homebrew/lib" gui.nim
```

## How do I patch a mod? (e.g., QUDAO Fixpack)
Patching massive mods is now a one-click process.

1. Download the original mod (e.g., QUDAO from NexusMods). Do not unzip the `.dazip` file.
2. Open **DAOTools**.
3. Click **Select File...** and choose the `.dazip` file.
4. **Important Tip:** Leave **"Keep Audio" unchecked**. This strips the heavy `.fsb` and `.fev` English voiceover files. You actively *want* to do this—unless you want characters randomly speaking English in the middle of your dubbed (French/German/idk) playthrough! (If your audio is in English anyway, it doesn't matter as much, but keeping it unchecked still saves file size).
5. Click **Patch DAZIP / GFF**.
6. **Translation Phase:** If the tool finds custom strings that need manual translation, it will automatically pause and open a `TEMP_full_tlk.json` file in your default text editor. You don't have to, but if you wish you can translate those lines, save the file, and click **OK** in the DAOTools popup to resume patching. (Or just click OK to skip this.)
7. Install the newly generated `<mod>_patched.dazip` file into your game as you normally would!

### A Note on QUDAO Translation
This automated patch handles 99% of the mod. However, a few specific custom lines still require manual (language-specific) translation. You can either translate these on-the-fly when the JSON file pops up during the DAZIP patching process, or edit the generated `.tlk` file later using the official DA Toolset. 

If you choose to do it later, unzip your patched `.dazip` and you will find the `.tlk` file here:
`Contents/packages/core/override/QUDAO_Fixpack_v3_5.tlk`
