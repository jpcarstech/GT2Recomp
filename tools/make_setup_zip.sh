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
GT2Recomp setup - Gran Turismo 2 recompiled for PC
===================================================

1. Build the GT2 Combined Disc from your own Arcade + Simulation disc dumps:
   https://github.com/CookiePLMonster/GT2-Combined-Disc
2. Put these files in the same folder as the image, e.g.
   D:\Gran Turismo 2 Recompilation\
       Gran Turismo 2 Combined.bin   (+ .cue)
       scph1001.bin                  (optional: your own BIOS dump)
       Setup GT2.cmd, setup_and_build.ps1, local_build.sh, extract_gt2_exe.ps1
3. Double-click "Setup GT2.cmd". First run: installs the build tools (MSYS2,
   via winget), fetches the source from GitHub, extracts the boot EXE from
   your image and recompiles the game. 30-60 minutes; ~6 GB RAM, ~15 GB disk.
4. Play with "Play GT2.cmd" (created by the build). The launcher opens on
   first start: pick controller, resolution, renderer and patches.

Re-run "Setup GT2.cmd" any time to update to the latest version (minutes).
Full docs: https://github.com/jpcarstech/GT2Recomp
TXT
rm -f "$out"
out="$(realpath -m "$out")"
( cd "$tmp" && zip -q -X "$out" "Setup GT2.cmd" setup_and_build.ps1 local_build.sh extract_gt2_exe.ps1 README.txt )
rm -rf "$tmp"
echo "wrote $out"; unzip -l "$out"
