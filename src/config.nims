# config.nims

# shared
switch("path", "../vendor/zippy/src")

# --- Windows x64 cross-build via zig:  nim c -d:zigwin src/gui.nim ---
when defined(zigwin):
  switch("os", "windows")
  switch("cpu", "amd64")
  switch("cc", "clang")
  switch("clang.exe", "zigcc")
  switch("clang.linkerexe", "zigcc")
  switch("clang.options.linker", "")
  switch("define", "danger")
  switch("mm", "arc")
  switch("opt", "speed")
  # no switch("app","gui") — on a mac host it triggers .app bundling even for Windows targets
  switch("passC", "-target x86_64-windows-gnu -O3")
  switch("passL", "-target x86_64-windows-gnu -O3 -Wl,-s -mwindows")
  switch("out", "DAOTools.exe")

# --- macOS native release:  nim c -d:macgui src/gui.nim ---
when defined(macgui):
  switch("define", "danger")
  switch("mm", "arc")
  switch("opt", "speed")
  switch("app", "gui")
  switch("passC", "-flto -O3")
  switch("passL", "-flto -O3 -Wl,-rpath,/opt/homebrew/lib")
  switch("out", "DAOTools")

# Usage becomes just:
# nim c -d:zigwin src/gui.nim    # → DAOTools.exe (Windows)
# nim c -d:macgui src/gui.nim    # → DAOTools (macOS)