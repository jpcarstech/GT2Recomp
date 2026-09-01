# GT2Recomp

*Gran Turismo 2* running natively on Windows, statically recompiled from the
**GT2 Combined Disc** with [PSXRecomp](https://github.com/mstan/psxrecomp):
the PlayStation MIPS code is translated to C and compiled for x64, then linked
against a hardware-accurate PS1 runtime (GPU, SPU, GTE, CD-ROM, memory cards)
with a recompiled real PS1 BIOS as the kernel. It is not an emulator.

**This repository contains no game data.** You build the executable yourself
from your own legally dumped Gran Turismo 2 discs — the build script does the
recompiling on your machine in about an hour. Nothing here is playable without
your discs.

## What you get

- Both **Arcade and Simulation** modes from one executable (that is what the
  Combined Disc is), with shared save data.
- **Internal resolution up to 16x** (4K and beyond), OpenGL / Vulkan / software
  renderers, nearest / bilinear / sharp-bilinear display scaling, optional FXAA,
  texture filtering with a separate "filter 2D" switch, and **Crop FMVs** (the
  movies fill the window height, letterbox bands removed, pixel aspect kept).
- **PGXP geometry correction** tuned to match DuckStation frame-for-frame:
  sub-pixel vertices, perspective-correct textures, culling correction, and the
  fixes documented in [`docs/PGXP_Lessons_GT2Recomp.docx`](docs/PGXP_Lessons_GT2Recomp.docx)
  (why walls, guardrails and billboards used to wobble, and what fixed it).
  Every knob is live in the in-game **F1** menu.
- **Silent's enhancements as toggles** (Patches / Cheats tab in the launcher):
  16:9 / 16:10 / 21:9 widescreen (true wider FOV, HUD unstretched), 60 FPS with
  CPU overclock, higher draw distance, 8 MB polygon buffers, full-detail AI
  cars, Arcade unlock-all. Converted from
  [Silent's GameShark code pack](https://github.com/CookiePLMonster/Console-Cheat-Codes)
  into guarded runtime patches.
- **Save states** (F7 menu) and **rewind** (F8), fast boot, turbo (Tab), a
  launcher with controller and keyboard rebinding, memory cards compatible with
  emulator `.mcd` files.
- A background native-code compiler: code the game streams in as it goes
  (GT2 loads its engine from `GT2.OVL`) is captured while you play and
  compiled to native code between sessions, so the game gets faster the more
  you play.

Tested on Windows 11 x64. The Linux build compiles from the same tree (Steam
Deck is planned, not yet packaged).

## Before you start: build the GT2 Combined Disc

This port is built from **Silent's GT2 Combined Disc** — the Arcade and
Simulation discs merged into one image with a menu to switch modes. You make
that image yourself from your two dumps; it takes a few minutes.

1. Dump both of your *Gran Turismo 2* discs (Arcade and Simulation) to
   `.bin`/`.cue`. Any release works except NTSC-J v1.0; this port has been
   verified with the NTSC-U base (Simulation disc SCUS-94488).
2. Follow the instructions in
   [CookiePLMonster/GT2-Combined-Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc)
   (Python 3.8+; run `setup.py`, point it at the two images, wait for the
   repack). Take the **full** output with FMVs, not the "lite" burnable one.
3. Name the result `Gran Turismo 2 Combined.bin` (+ `.cue`). The build script
   offers to rename a single large `.bin` for you and rewrites the `.cue` if
   it points at another file name.

The image this project was built from is 1,033,459,392 bytes,
MD5 `70ecd6e788501eb69a220d2a96e624c4` (NTSC-U 1.1 Simulation base, boot EXE
`SCUS_944.88`). The build checks this and warns if yours differs — a different
base (GT2 Plus, PAL) has a different boot EXE and would need its own function
seeds.

## Building and installing (Windows)

Requirements: Windows 10/11 x64, ~6 GB free RAM during the build, ~15 GB of
disk, Git for Windows (or any `git`), and about an hour the first time. The
script installs MSYS2 and the MinGW-w64 toolchain for you with `winget`.

1. Make a game folder, e.g. `D:\Gran Turismo 2 Recompilation`, and put
   `Gran Turismo 2 Combined.bin` / `.cue` in it. Optionally add your own BIOS
   dump as `scph1001.bin` (the bundled OpenBIOS works without it).
2. Clone this repository **into that folder** as `GT2Recomp-src`:
   ```
   cd "D:\Gran Turismo 2 Recompilation"
   git clone https://github.com/jpcarstech/GT2Recomp.git GT2Recomp-src
   ```
   (No `--recursive` needed; the build fetches the pinned submodules itself.)
3. Right-click `GT2Recomp-src\tools-win\local-build\setup_and_build.ps1` →
   **Run with PowerShell** (or from a terminal:
   `powershell -ExecutionPolicy Bypass -File .\GT2Recomp-src\tools-win\local-build\setup_and_build.ps1`).
   It verifies the disc image, extracts the boot EXE into `extracted\`,
   installs the toolchain, applies the framework patches, recompiles the game
   (the long step) and installs everything into the game folder.
4. Play with **`Play GT2.cmd`** in the game folder. It starts the game and,
   when you quit, compiles whatever new code that session captured so the next
   launch runs more of the game natively. The first launch opens the launcher:
   pick your controller, resolution, renderer and patches there.

To update later: `git pull` inside `GT2Recomp-src` and run
`setup_and_build.ps1` again (incremental; minutes, not an hour).

Your game folder ends up looking like this:

```
Gran Turismo 2 Recompilation\
  Gran Turismo 2 Recompiled.exe     built by you
  Play GT2.cmd                      launcher (game + cache top-up)
  setup_and_build.ps1               rebuild / update
  Gran Turismo 2 Combined.bin/.cue  your disc image
  game.toml                         runtime config (safe to edit)
  settings.toml, input.ini, keybinds.ini   launcher settings
  extracted\SCUS_944.88             boot EXE, extracted from your disc
  bios\                             openbios.bin (bundled) + your scph1001.bin
  patches\                          the enhancement packages + their enable state
  saves\                            memory cards (card1.mcd / card2.mcd)
  cache\, overlay_captures.json     native-code cache built from your play
  overlay_toolchain\                the background compiler
  tools\                            helper scripts
  GT2Recomp-src\                    this repository
```

Details, the Linux command line, and what each step does are in
[`docs/BUILDING.md`](docs/BUILDING.md).

## Playing

| Key | Action |
|---|---|
| F1 | In-game settings menu (graphics, display scaling, Crop FMVs, PGXP tuning — live) |
| F7 | Save-state menu |
| F8 | Rewind (hold) |
| F6 | Swap controller ports |
| Tab | Turbo |
| F | Performance overlay |
| Alt+Enter / Ctrl+F | Fullscreen |
| Esc, Esc | Quit (double press) |
| Numpad + / − | Volume |

Default keyboard pad: arrows = d-pad / left stick, X = Cross, Z = Square,
A = Triangle, S = Circle, Q/W = L1/R1, E/R = L2/R2, Enter = Start,
Right Shift = Select. Xbox-style controllers work out of the box; rebind
everything in the launcher's Controls page.

Recommended settings for a 4K/120 Hz display, matching a well-tuned DuckStation
setup: internal scale 6x–9x, display scaling *Nearest* (falls back to
sharp-bilinear at non-integer ratios) or *Bilinear*, Crop FMVs on, PGXP
geometry + textures + culling on at unlimited tolerance (the defaults), and the
Aspect Ratio patch at 16:9. The `tools\` folder has `run_logged.ps1` to capture
the console output when something goes wrong, and `compile_cache.ps1` to
compile the whole native-code backlog in one go.

## How the repository is organized

| Path | What |
|---|---|
| `game.toml` | Game identity + recompiler config (build variant) |
| `tools-win/local-build/game.runtime.toml` | The `game.toml` installed beside the exe (runtime variant) |
| `seeds/ghidra_funcs.txt` | Function seeds for the boot EXE (entry + JAL scan) |
| `CMakeLists.txt`, `codegen_setup.*` | Game runtime target (`psxrecomp_add_game_runtime`) |
| `mods_gt2_silent.c`, `mods/` | The enhancement package: Silent's codes as runtime patch plugins |
| `psxrecomp/`, `recomp-ui/` | Framework and launcher submodules, **pinned to upstream commits** |
| `patches/` | Everything this port changes in the framework, as patches applied at build time (see [`patches/README.md`](patches/README.md) — each entry explains the bug) |
| `tools-win/` | `setup_and_build.ps1` + `local_build.sh` (the build), player helpers, and `dev/` diagnostics |
| `docs/` | [`BUILDING.md`](docs/BUILDING.md), [`BRINGUP.md`](docs/BRINGUP.md) (bring-up log), the PGXP write-up |

Framework changes are carried as patches, never as submodule forks, so anyone
can see exactly what differs from upstream PSXRecomp and the fixes can go back
upstream one at a time. CI applies the whole stack onto the pinned commits on
every push.

## Known issues

- The first launch after a fresh build boots with almost everything
  interpreted; a few play sessions (or one `tools\compile_cache.ps1` run) bring
  the native cache up and the frame rate with it.
- The boot-time "Loading Save Data" screen is slow (tens of seconds) — a BIOS
  memory-card timing issue under investigation.
- Replays and Rally-mode AI ghosts recorded at 30 FPS are not compatible with
  the 60 FPS patch (upstream caveat of the code).
- Software renderer is for A/B testing only; it is far slower than OpenGL.

Bug reports: please include `diagnostics\psx_last_run_report.json`, your
`settings.toml`, and the output of `tools\run_logged.ps1`.

## Credits

- [PSXRecomp](https://github.com/mstan/psxrecomp) and
  [recomp-ui](https://github.com/mstan/recomp-ui) by Matthew Stan — the
  recompiler, runtime and launcher this port is built on.
- [GT2 Combined Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc) and
  the [GT2 code pack](https://github.com/CookiePLMonster/Console-Cheat-Codes)
  by Silent (CookiePLMonster), UI by Ash_735; 60 FPS research by asasega.
- [DuckStation](https://github.com/stenzek/duckstation) by stenzek — the PGXP
  reference behaviour this port's geometry correction was matched against.
- [OpenBIOS](https://github.com/grumpycoders/pcsx-redux) from PCSX-Redux
  (bundled as the default BIOS; see `bios/OpenBIOS.LICENSE`).
- Polyphony Digital made the game. Go buy it.

## License

GT2Recomp (this repository: configuration, seeds, build tooling, the
enhancement plugins and the carried framework patches) is licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE), the same license as PSXRecomp.
Gran Turismo is a trademark of Sony Interactive Entertainment. No game code,
disc data, BIOS or generated recompilation output is distributed here — bring
your own legally obtained discs.
