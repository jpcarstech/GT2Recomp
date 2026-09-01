#!/usr/bin/env bash
# Build GT2Recomp-setup.zip - the four files a player drops into the folder
# holding their GT2 Combined Disc image. Attach it to the GitHub Release.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-GT2Recomp-setup.zip}"
tmp=$(mktemp -d)
cp "tools-win/local-build/Setup GT2.cmd" tools-win/local-build/setup_and_build.ps1 \
   tools-win/local-build/local_build.sh tools-win/extract_gt2_exe.ps1 "$tmp/"
cat > "$tmp/README.txt" <<'TXT'
GRAN TURISMO 2 ON YOUR PC - SETUP
==================================

What you need: a Windows 10/11 PC, ~15 GB free space, internet, and your own
GT2 discs (both: Arcade and Simulation) saved as .bin + .cue files.

STEP 1 - Combine your two discs into one game image (~15 minutes)
  a. Install Python from python.org/downloads
     (tick "Add python.exe to PATH" in its installer).
  b. Download Silent's Combined Disc tool:
     github.com/CookiePLMonster/GT2-Combined-Disc/releases/latest
  c. Unzip it, double-click setup.py, pick your two disc images, wait.
  d. You get a new ~1 GB game image (plus a small .cue). Keep those two.

STEP 2 - Make a game folder
  Create a folder anywhere (e.g. C:\Games\GT2) and put the combined image
  (.bin and .cue) from Step 1 in it, together with the five files from this
  zip (you probably already did that).

STEP 3 - Double-click "Setup GT2.cmd"  (30-60 minutes, all automatic)
  - If Windows asks to allow changes, click Yes (build tools installing).
  - If it offers to rename your game image, press Enter.
  - Leave the black window alone until it prints DONE.

PLAY: double-click "Gran Turismo 2 Recompiled.exe" (make a desktop shortcut
if you like). The first start opens a settings window - plug in your
controller, pick resolution and patches (widescreen, 60 FPS...), hit Play.
In game: F1 = graphics menu, F7 = save states, F8 = rewind.

Good to know:
  - The game gets FASTER over your first few sessions (it quietly converts
    more of itself to PC code while you play and briefly after you quit).
  - Re-run "Setup GT2.cmd" any time to update (minutes, not an hour).
  - Nothing is uploaded anywhere; everything is built from your own discs.
  - Optional: put your own PS1 BIOS dump (scph1001.bin) in the folder before
    setup. Not required - a free BIOS is included.

Problems? github.com/jpcarstech/GT2Recomp - full guide + report an issue.
TXT
rm -f "$out"
out="$(realpath -m "$out")"
( cd "$tmp" && zip -q -X "$out" "Setup GT2.cmd" setup_and_build.ps1 local_build.sh extract_gt2_exe.ps1 README.txt )
rm -rf "$tmp"
echo "wrote $out"; unzip -l "$out"
