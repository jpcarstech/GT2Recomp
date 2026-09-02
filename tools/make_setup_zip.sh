#!/usr/bin/env bash
# Build GT2Recomp-setup.zip - the files a player drops into the folder
# holding their GT2 disc dump(s). Attach it to the GitHub Release.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-GT2Recomp-setup.zip}"
tmp=$(mktemp -d)
cp "tools-win/local-build/Setup GT2.cmd" tools-win/local-build/setup_and_build.ps1 \
   tools-win/local-build/local_build.sh "tools-win/local-build/Diagnose GT2.cmd" "$tmp/"
cat > "$tmp/README.txt" <<'TXT'
GRAN TURISMO 2 ON YOUR PC - SETUP
==================================

What you need: a Windows 10/11 PC, ~15 GB free space, internet, and your own
GT2 disc dumps saved as .bin files - the Arcade disc, the Simulation disc,
or both (both recommended; you can switch discs in the game).

STEP 1 - Put your disc image(s) in a folder
  Any folder (e.g. C:\Games\GT2). File names don't matter - setup works
  out which disc is which. That folder becomes the game folder.

STEP 2 - Double-click "Setup GT2.cmd"  (30-60 minutes PER DISC, automatic)
  - It can run from anywhere - the folder you unzipped to is fine. If your
    discs aren't beside it, a window asks you to pick their folder, and the
    setup files copy themselves there for next time.
  - It lists the discs it found and asks before starting the long step.
  - If Windows asks to allow changes, click Yes (build tools installing).
  - Leave the black window alone until it prints DONE.

PLAY: double-click "Gran Turismo 2 Recompiled.exe" (make a desktop shortcut
if you like). The first start opens a settings window - plug in your
controller, pick your resolution, then open Mods and press "Enhanced"
(widescreen, geometry correction, draw distance, full-detail AI, CPU
overclock - the setup that runs best) or "Authentic 1999" (everything
off), and hit Play. It always opens the disc you used last; change discs
with the "Disc" row in that settings window, or in the game:
F1 -> Disc -> Switch disc.
In game: F1 = settings + disc switch, F7 = save states, F8 = rewind.

KNOWN ISSUES: 60 FPS is experimental and runs sluggish on current builds -
stay on Original (30 fps) for now. Mods and cheats are per disc and each
needs its own testing; the plain Arcade/Simulation discs ship no cheats
yet (the published codes are for the wrong disc revision). More of both
will come as they are verified. Full list: the README on GitHub.

Good to know:
  - Your garage follows you: memory cards are shared between the discs, so
    Arcade's "Load Guest Garage" sees your Simulation garage, like on the
    real console.
  - The game gets FASTER over your first few sessions (it quietly converts
    more of itself to PC code while you play and briefly after you quit).
  - Re-run "Setup GT2.cmd" (now in the game folder) any time to update, or
    after adding another disc image (only the new disc takes the full time).
  - Nothing is uploaded anywhere; everything is built from your own discs.
  - Optional: put your own PS1 BIOS dump (scph1001.bin) in the folder before
    setup. Not required - a free BIOS is included.
  - Have a GT2 Combined Disc image from the fan project? Drop it in too -
    it builds as a third switchable disc with its own extras.

Problems? Run "Diagnose GT2.cmd" and attach the gt2_diag.txt it writes to an
issue at github.com/jpcarstech/GT2Recomp - full guide there too.
TXT
rm -f "$out"
out="$(realpath -m "$out")"
( cd "$tmp" && zip -q -X "$out" "Setup GT2.cmd" setup_and_build.ps1 local_build.sh "Diagnose GT2.cmd" README.txt )
rm -rf "$tmp"
echo "wrote $out"; unzip -l "$out"
