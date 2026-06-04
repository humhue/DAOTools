import nigui
import os, browsers
import patch_manager

app.init()

var window = newWindow("DAO Tools")
window.width = 600
window.height = 420

var container = newLayoutContainer(Layout_Vertical)
container.padding = 15
container.widthMode = WidthMode_Fill
window.add(container)

# --- 1. Target Selection Row ---
var selContainer = newLayoutContainer(Layout_Horizontal)
selContainer.widthMode = WidthMode_Fill
container.add(selContainer)

var btnFile = newButton("Select File...")
var btnFolder = newButton("Select Folder...")
var lblTarget = newLabel("No target selected...")
lblTarget.widthMode = WidthMode_Fill

selContainer.add(btnFile)
selContainer.add(btnFolder)
selContainer.add(lblTarget)

var targetPath = ""
var isDir = false

btnFile.onClick = proc(event: ClickEvent) =
  var dialog = newOpenFileDialog()
  dialog.title = "Select DAZIP or ERF"
  dialog.run()
  if dialog.files.len > 0:
    targetPath = dialog.files[0]
    isDir = false
    lblTarget.text = "FILE: " & extractFilename(targetPath)

btnFolder.onClick = proc(event: ClickEvent) =
  var dialog = SelectDirectoryDialog() # Using the GTK directory picker we just fixed!
  dialog.title = "Select ERF Source Folder"
  dialog.run()
  if dialog.selectedDirectory != "":
    targetPath = dialog.selectedDirectory
    isDir = true
    lblTarget.text = "DIR: " & extractFilename(targetPath)

# --- 2. Options ---
var chkKeepAudio = newCheckbox("Keep Audio (.fsb, .fev) [DAZIP only]")
container.add(chkKeepAudio)

# --- 3. Action Buttons Row ---
var actContainer = newLayoutContainer(Layout_Horizontal)
actContainer.widthMode = WidthMode_Fill
container.add(actContainer)

var btnPatch = newButton("Patch DAZIP / GFF")
var btnExtract = newButton("Extract ERF")
var btnBuild = newButton("Build ERF")

btnPatch.heightMode = HeightMode_Static
btnPatch.height = 35
btnExtract.heightMode = HeightMode_Static
btnExtract.height = 35
btnBuild.heightMode = HeightMode_Static
btnBuild.height = 35

actContainer.add(btnPatch)
actContainer.add(btnExtract)
actContainer.add(btnBuild)

# --- 4. Console Output ---
var consoleArea = newTextArea()
consoleArea.text = "Engine Ready. Waiting for target...\n"
consoleArea.fontFamily = "Courier"
container.add(consoleArea)

# --- Action Handlers ---

# ACTION 1: Patching
btnPatch.onClick = proc(event: ClickEvent) =
  if targetPath == "" or isDir:
    window.alert("Please 'Select File...' (DAZIP, ERF, or GFF) to patch.")
    return
  consoleArea.addLine("\n▶ Patching: " & extractFilename(targetPath))
  app.queueMain(proc() = app.processEvents())
  
  let keepAudio = chkKeepAudio.checked
  let output = targetPath.splitFile().dir / (targetPath.splitFile().name & ".patched" & targetPath.splitFile().ext)
  
  # Define the pause-and-edit callback
  let onTlkEdit = proc(mapPath: string) =
    openDefaultBrowser(mapPath) # Cross-platform open in Notepad/TextEdit
    
    # This acts as your yield/pause. The backend stops until they click OK.
    window.alert("The program found TLK strings that require manual (language-specific) translation.\n\nThe TLK dictionary has been opened in your default text editor.\n\nYou may now translate these strings, save the file, and then click OK to resume patching.\n\nTo skip this step, click OK to continue. Please note that these lines will remain in their original language.")

  try:
    # Pass the callback into your patching engine
    patchFile(targetPath, output, keepAudio, onTlkEdit)
    consoleArea.addLine("✔ Complete! -> " & extractFilename(output))
  except Exception as e:
    consoleArea.addLine("❌ Error: " & e.msg)

# ACTION 2: Extracting ERF
btnExtract.onClick = proc(event: ClickEvent) =
  if targetPath == "" or isDir:
    window.alert("Please 'Select File...' (an ERF) to extract.")
    return
  
  let outDir = targetPath & "_extracted"
  consoleArea.addLine("\n▶ Extracting ERF to: " & extractFilename(outDir))
  app.queueMain(proc() = app.processEvents())
  
  try:
    extractErf(targetPath, outDir)
    var fileCount = 0
    for kind, path in walkDir(outDir):
      if kind == pcFile:
        fileCount += 1
    consoleArea.addLine("✔ Extracted " & $fileCount & " files successfully.")
  except Exception as e:
    consoleArea.addLine("❌ Error: " & e.msg)

# ACTION 3: Building ERF
btnBuild.onClick = proc(event: ClickEvent) =
  if targetPath == "" or not isDir:
    window.alert("Please 'Select Folder...' to build into an ERF.")
    return
    
  let outFile = targetPath & ".erf"
  consoleArea.addLine("\n▶ Building ERF from: " & extractFilename(targetPath))
  app.queueMain(proc() = app.processEvents())
  
  try:
    buildErf(targetPath, outFile)
    var fileCount = 0
    for kind, path in walkDir(targetPath):
      if kind == pcFile:
        fileCount += 1
    consoleArea.addLine("✔ Built ERF with " & $fileCount & " files -> " & extractFilename(outFile))
  except Exception as e:
    consoleArea.addLine("❌ Error: " & e.msg)

window.show()
app.run()