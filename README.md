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

## How to install (no technical knowledge needed)

**What you need:** a Windows 10 or 11 PC (64-bit), about 15 GB of free space,
an internet connection, and your own *Gran Turismo 2* discs — both of them,
Arcade and Simulation — saved on your PC as `.bin` + `.cue` files. Setup takes
about an hour, almost all of it waiting.

### Step 1 — Combine your two discs into one game image (~15 min)

GT2 shipped on two discs. This port uses the fan-made **Combined Disc**, which
merges them into one game with both modes on the menu. You make it yourself
from your two disc images by following the instructions at
[CookiePLMonster/GT2-Combined-Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc).
You end up with a new game image of about **1 GB** (plus a small `.cue`
file) — that's the one this port uses.

### Step 2 — Make a game folder

Create a new folder anywhere you like, for example `C:\Games\GT2`, and put the
combined game image from Step 1 in it (the big `.bin` and its `.cue`).

### Step 3 — Run the installer (30–60 min, all automatic)

1. Download **`GT2Recomp-setup.zip`** from the
   [latest release](https://github.com/jpcarstech/GT2Recomp/releases/latest).
2. Open the zip and drag its five files into your game folder from Step 2.
3. Double-click **`Setup GT2.cmd`**. A black window opens and starts working.
   - If Windows asks *"Do you want to allow this app to make changes?"*, click
     **Yes** — that's the free build tools installing.
   - If it offers to rename your game image, press **Enter** to accept.
   - Leave the window alone until it prints **DONE**, then close it.

### Play

Double-click **`Gran Turismo 2 Recompiled.exe`** in your game folder (make a
desktop shortcut if you like). The first start opens a settings window — plug
in your controller, pick your resolution and any patches (widescreen,
60 FPS...), and hit Play. In the game, **F1** opens the graphics menu, **F7**
save states, **F8** rewinds.

Two good things to know: the game keeps getting *faster* over your first few
play sessions (it quietly converts more of the game to native PC code while
you play and for a little while after you quit), and you can re-run
`Setup GT2.cmd` any time to update to the newest version (that takes minutes,
not an hour).

Nothing about your discs or game is ever uploaded anywhere: the conversion
happens entirely on your PC, from your own discs. That is also why there is no
plain download of the finished game — it legally can't be handed out, but your
PC can build it from what you own.

<details>
<summary><b>If something goes wrong</b></summary>

- **The black window closes instantly or shows red text** — run
  `Setup GT2.cmd` again; if it repeats, take a photo/screenshot of the text
  and [open an issue](https://github.com/jpcarstech/GT2Recomp/issues).
- **"Could not find 'Gran Turismo 2 Combined.bin'"** — the five zip files and
  your game image are not in the same folder.
- **A warning about the image's size or MD5** — your combined image was made
  from a different disc version (e.g. PAL or GT2 Plus). Only the regular
  NTSC-U discs are supported right now.
- **The game starts but runs poorly at first** — expected; see above. It
  speeds up over the first few sessions (or run `tools\compile_cache.ps1`
  once with the game closed to convert everything in one go).
- More details: [docs/BUILDING.md](docs/BUILDING.md#troubleshooting).

</details>

## For developers

<details>
<summary><b>Disc image details, building from a checkout, Linux</b></summary>

The base image is Silent's **GT2 Combined Disc** (any GT2 release except
NTSC-J v1.0 can build it; this port is verified against the NTSC-U base,
Simulation disc SCUS-94488). The image this project was built from is
1,033,459,392 bytes, MD5 `70ecd6e788501eb69a220d2a96e624c4` (boot EXE
`SCUS_944.88`). `setup_and_build.ps1` checks size and MD5 and warns on a
mismatch — a different base image has a different boot EXE and would need its
own function seeds.

To build from a checkout instead of the setup zip: clone this repository into
the game folder as `GT2Recomp-src` (no `--recursive`; the build fetches the
pinned submodules itself) and double-click
`GT2Recomp-src\tools-win\local-build\Setup GT2.cmd`. Update later with
`git pull` + the same script (incremental, minutes). The build verifies the
disc image, extracts the boot EXE into `extracted\`, installs the MSYS2
toolchain, applies the framework patches, recompiles the game and installs
everything into the game folder.

Your game folder ends up looking like this:

```
GT2\
  Gran Turismo 2 Recompiled.exe     built by you - this is the game, launch it
  Play GT2.cmd                      optional wrapper (game + full cache top-up on exit)
  Setup GT2.cmd, setup_and_build.ps1, local_build.sh   rebuild / update
  Gran Turismo 2 Combined.bin/.cue  your disc image
  game.toml                         runtime config (safe to edit)
  settings.toml, input.ini, keybinds.ini   launcher settings
  extracted\SCUS_944.88             boot EXE, extracted from your disc
  bios\                             openbios.bin (bundled free BIOS) + optionally your scph1001.bin
  patches\                          the enhancement packages + their enable state
  saves\                            memory cards (card1.mcd / card2.mcd)
  cache\, overlay_captures.json     native-code cache built from your play
  overlay_toolchain\                the background compiler
  tools\                            helper scripts
  GT2Recomp-src\                    this repository (checkout flow)
```

A retail BIOS is never required or distributed: the bundled
[OpenBIOS](https://github.com/grumpycoders/pcsx-redux) (free, clean-room)
is the default; a personal `scph1001.bin` dump placed in the game folder
becomes selectable in the launcher.

The full walk-through of every build step, the Linux build, and
troubleshooting live in [`docs/BUILDING.md`](docs/BUILDING.md).

</details>

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
