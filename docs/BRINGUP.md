# GT2 bring-up log

Base image: "GT2 Combined" mod (both discs merged; single track MODE2/2352,
985.6 MB). Boot EXE `SCUS_944.88`: entry `0x8005D5C0`, load `0x80010000`,
text `0x99000`, stack `801fff00`. Disc root: GT2.OVL / GT2.VOL / MUSIC.DAT /
STREAM.DAT / SYSTEM.CNF.

## Pipeline notes

- Seeds generated from the bare EXE with `probe_disc.scan_jal_seeds` (666
  seeds); full disc probe not required for single-player bring-up.
- `psxrecomp-game` on this EXE: 9,795 functions, 3,423 dispatch entries,
  ~1.2 GB generated C in ~230 shards. Needs ~6 GB RAM.
- Windows build: MinGW cross via `psxrecomp/cmake/toolchain-mingw-w64.cmake`;
  resulting exe imports only Windows system DLLs.

## Gotchas hit (and fixes)

1. **Silent exit on launch, no window.** Release MinGW builds are `-mwindows`;
   startup errors print to a console that does not exist. Capture with
   `Start-Process -Wait -RedirectStandardError`. Root cause: shipped
   `game.toml` had dropped the `[recompiler]` block — the shared config
   loader requires it even at runtime.
2. **"Bundled BIOS Missing" dialog.** Runtime expects `bios/openbios.bin`
   beside the exe even when a retail BIOS is present; ship it. Retail dump
   also goes to `bios/SCPH1001.BIN`.
3. **Original cue referenced `GT2Combined.bin`** while the file on disk was
   named differently — fixed cue must reference the bin's real filename.
4. **Intro FMV audio crackly/slow, in-game fine.** First-session run report:
   `disp_interp = 349,576,910`, `disp_native = 0` — all GT2.OVL overlay code
   (including the FMV player) ran on the interpreter. Fix: compile
   `overlay_captures.json` → native cache. Cross-compiling from Linux for a
   Windows player needs `compile_overlays.is_windows` forced true (suffix +
   `win-x64` cache tag are host-detected) and `--gcc x86_64-w64-mingw32-gcc`.
   960 shards, 0 failures. Ship `.dll`/`.ranges` (+ locks), not the
   `*_fragment_patched.c` intermediates, and never publish captures or cache
   (they contain game code).

## Base image provenance

The recompiled image is Silent's **GT2 Combined Disc** mod
(https://silentsblog.com/2022/02/26/gran-turismo-2-combined-disc/, by Silent /
cookieplmonster, UI by Ash_735). Facts relevant to the recomp, which match
what we observed from the disc itself:

- The **Simulation Disc is the base** — hence the SCUS_944.88 boot EXE we
  recompiled. The Arcade Disc's contribution is mostly its FMV set, merged in
  as `STREAM.DAT` via MKPSXISO.
- The image is deliberately **oversized** (past ISO9660's 99:59.74 limit) —
  invalid on physical media, fine for emulators, and fine for our runtime,
  which reads the bin directly. Explains the 985.6 MB single-track image.
- **Mode switching is a menu patch**: the main menu gains separate Arcade /
  Simulation buttons instead of prompting a disc swap. So both modes run from
  the one boot EXE we recompiled, and Arcade content exercises additional
  overlay regions — expect fresh interpreter-first visits (and new
  overlay_captures.json coverage to compile) the first time Arcade mode and
  its tracks are played.
- Compatible with GT2 Plus / GT2.1 mods per the article, so swapping the base
  image for one of those later means re-extracting the boot EXE and
  regenerating (the EXE differs), but the pipeline is identical.
