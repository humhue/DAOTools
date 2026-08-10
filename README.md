# DAOTools

**QUDAO FIXPACK DISCLAIMER**

I am not the author of the QUDAO Fixpack (originally created by Paul Escalona / Qwinn). I initially created this toolset specifically to patch QUDAO and make its text non-language-specific, allowing non-English speakers to enjoy the mod.

**Want an international version of the fixpack?** Out of respect for the original author's permissions, I do not host pre-patched mod files. Instead, simply download this program from [Nexus Mods](https://www.nexusmods.com/dragonage/mods/6920), download the original mod from NexusMods, and run the `.dazip` through the patcher. It is fully automated and takes less than a second!

---

## What is this?
DAOTools is a utility for Dragon Age: Origins modding. 

When you edit most modding files (even for trivial fixes) using the original Bioware DA Toolset, any text inside them is often forced into English. This ruins the experience for international players. This tool automatically patches mod files to remove language-specific string references, making the mods compatible with any language version of the game.

**Features:**
* **Cross-Platform GUI:** A brand new, user-friendly graphical interface—no more command-line Python scripts!
* **Direct DAZIP Patching:** No need to manually extract archives. Select a `.dazip`, and the tool will patch every compatible file inside it automatically.
* **Generic GFF3.2 Support:** Patches `.are, .lst, .utc, .uti, .utm, .utp, .utt`. (This fixes location names and item names resetting to English. *Note: Fixing item names requires starting a new playthrough, as the English names get baked directly into existing save files.*)
* **Generic GFF4.0 Support:** Patches `.cub, .cut, .dlb, .dlg, .plo, .stg` (Fixes dialogue and plot text).
* **Existing Talk-Table Support:** Discovers and translates entries in valid mod-provided `.tlk` files without synthesizing separate talk tables from harvested GFF strings.
* **ERF Management:** Extract and build `.erf` archives directly from the UI.
* **In-Memory Processing:** Processes data in RAM using streams for maximum efficiency.

## How does it work?
The tool performs a read-only discovery pass over the target and separates shipped BioWare strings from mod-authored strings. Hardcoded overrides of shipped strings are disabled so the game can use its installed language. Mod-authored translations are embedded directly back into each GFF resource. Existing valid mod talk tables are translated directly in the output copy when encountered; DAOTools does not generate a new external `.tlk` as an intermediary.

When a translated line is longer than the original, DAOTools appends a new inline string and updates the resource's relative pointer. Each resource is rebuilt only once after discovery, and an unchanged JSON value preserves the existing payload and pointer byte-for-byte.

## Version 2.0 Changelog (The Nim Rewrite)
DAOTools has been completely rewritten from the ground up in the **Nim** programming language, moving away from the legacy Python codebase. 
* **Native GUI Added:** Full graphical interface built with NiGui.
* **Massive Speed Increase:** The previous Python script took up to **10 minutes** to parse large mods like QUDAO. By utilizing lazy-evaluation, RAM-streams, and C-level compilation, DAOTools v2.0 patches the exact same archive in **~450 milliseconds** (over a 1300x speedup).
* **Expanded Format Support:** Added generic support for GFF 3.2.
* *Note: The legacy read-only GFF parser has been dropped, as better dedicated tools exist for viewing raw data.*

## Installation & Compilation
If you just want to use the tool, download the compiled executable from the [Nexus Mods page](https://www.nexusmods.com/dragonage/mods/6920).

If you want to compile the tool yourself from the source code, you will need the [Nim Compiler](https://nim-lang.org/):

Built with Nim 2.2.8 and Zig 0.14.x — using these versions reproduces the latest release build on Nexus Mods.

1. Install Nim  → https://nim-lang.org/install.html (choosenim recommended)
2. Install Zig  → `winget install -e --id zig.zig` / ziglang.org/download / `brew install zig` (on macOS)
3. `nimble install zigcc`        # zig-cc wrapper used as Nim's C compiler
4. `nimble install nigui`        # deps (or `nimble install --depsOnly` if using the .nimble file)
5. `git clone https://github.com/humhue/DAOTools.git`
6. `cd DAOTools`
7. `nim c -d:zigwin src/gui.nim` # this builds DAOTools.exe

Run the inline-translation regression suite with:

`nim c -r tests/test_inline_translations.nim`

First build takes longer while zig compiles the mingw CRT for the target; it's cached afterwards.

## How do I patch a mod? (e.g., QUDAO Fixpack)
Patching massive mods is now a one-click process.

1. Download the original mod (e.g., QUDAO from NexusMods). Do not unzip the `.dazip` file.
2. Open **DAOTools**.
3. Click **Select File...** and choose the `.dazip` file.
4. **Important Tip:** Leave **"Keep Audio" unchecked**. This strips the heavy `.fsb` and `.fev` English voiceover files. You actively *want* to do this—unless you want characters randomly speaking English in the middle of your dubbed (French/German/idk) playthrough! (If your audio is in English anyway, it doesn't matter as much, but keeping it unchecked still saves file size).
5. Click **Patch DAZIP / ERF / TLK / GFF / Folder**.
6. **Translation Phase:** If no master JSON is selected and the tool finds mod-authored strings, it performs a read-only discovery pass and opens a reusable `<input>.translations.json` file. Edit the `line` values, save the file, and click **OK**. DAOTools then reopens the original input and embeds the edited lines during a fresh patch pass. Leaving a line unchanged leaves its existing pointer and payload unchanged.
7. Open the newly generated **DAOTools Patched** folder and install the output normally. The selected file and every resource inside a patched tree retain their exact original filename. If that output directory already exists, DAOTools creates **DAOTools Patched (2)**, then `(3)`, and so on.

Every output directory contains a `.daotools-patched` sentinel identifying it as generated by DAOTools.

### A Note on QUDAO Translation
This automated patch handles 99% of the mod. A few custom lines still require manual translation. You can translate them interactively when the generated JSON opens, or select a previously translated JSON with **Select Master JSON...** before patching. A global ID map is the simplest accepted form:

```json
{
  "1138510444": "Translated line"
}
```

For an ID that is reused with different text, use the optional file-specific form. File-specific values take precedence over global values:

```json
{
  "tlkstrings": {
    "1138510444": "Default translation"
  },
  "files": {
    "example.uti": {
      "1138510444": "Translation for this resource"
    }
  }
}
```

Resources produced by the older external-TLK workflow can be repaired by patching them again with their saved translation JSON. Without that JSON, patch the original mod again so the discovery pass can still read its embedded source lines.
