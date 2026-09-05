# Building GT2Recomp

The player version is in the [README](../README.md#install):
unzip `GT2Recomp-setup.zip` next to your GT2 disc dump(s) and double-click
`Setup GT2.cmd`. This page is the long version — what each step does, how to
run it by hand, and how to build on Linux.

## Inputs you provide

| File | Where | Notes |
|---|---|---|
| Your disc dump(s), `.bin` (+ `.cue` if you have it) | game folder | The **Arcade disc** (SCUS-94455, 729,606,864 bytes, MD5 `79befcdb7e725daff04bce3c4aafb321`), the **Simulation disc** (SCUS-94488, 680,856,960 bytes, MD5 `36d8008a99299b236a32a6bf4702aac6`), or both — NTSC-U v1.1 are the tested dumps. Any file names: each image is identified by content (boot serial + track size). A missing/wrong `.cue` is written/fixed automatically. Optional third disc: a [GT2 Combined Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc) image (1,033,459,392 bytes, MD5 `70ecd6e788501eb69a220d2a96e624c4`) builds as its own switchable title. |
| `scph1001.bin` | game folder (optional) | A retail SCPH-1001 BIOS dump. Without it the bundled OpenBIOS is used; with it you can pick either in the launcher. Some titles behave differently on OpenBIOS; GT2 runs on both. |

Everything else is derived: the boot EXE is extracted from the image, the
generated C comes out of the recompiler, and the framework is fetched at its
pinned commit.

## What `setup_and_build.ps1` does

1. **Finds the game folder** — the folder containing at least one large
   `.bin`, looked up from the script's own location (three levels up from
   `GT2Recomp-src\tools-win\local-build\`) or passed with `-GameDir`.
2. **Installs the toolchain** — MSYS2 via `winget`, then
   `mingw-w64-x86_64-{toolchain,cmake,ninja,ccache}`, `git`, `python`,
   `unzip`, `curl` via `pacman`. One-time; re-runs are no-ops.
3. **Runs `local_build.sh`** in the MSYS2 MinGW64 shell, which does the actual
   work (below), including working out which GT2 disc each image is.

## What `local_build.sh` does

Runs inside MSYS2 MinGW64; `bash local_build.sh "<game folder>" [<source dir>]`.

1. **Source** — uses the checkout it lives in. If invoked from a bare game
   folder copy, clones `https://github.com/jpcarstech/GT2Recomp.git` into
   `<game>/GT2Recomp-src` (or, developer flow, from a `gt2recomp.bundle` beside
   it). A clean checkout with a remote is fast-forwarded (`GT2_NO_SYNC=1`
   skips that). Submodules are then checked out at their **pinned upstream
   commits** (`--depth 1`).
2. **Framework patches** — `patches/upstream/*.patch` then
   `patches/psxrecomp-*.patch`, in byte (`LC_ALL=C`) order, onto `psxrecomp/`;
   `patches/recomp-ui/*.patch` onto `recomp-ui/`. Any patch that fails to
   apply stops the build: a build silently missing a patch would be
   indistinguishable from "the fix did not help". [`patches/README.md`](../patches/README.md)
   describes each patch.
3. **Recompiler tool** — `cmake -S psxrecomp/recompiler -B psxrecomp/recompiler/build`
   and builds `psxrecomp-game`.
4. **Discs** — every `.bin` over 400 MB in the game folder is probed
   (`psxrecomp/tools/new_project_layout/probe_disc.py`): the boot serial and
   data-track size say which GT2 disc it is (arcade / simulation / combined);
   a missing or wrong `.cue` is written/fixed first. Non-GT2 images are
   skipped with a note. Also regenerates the recompiled BIOS backends
   (`tools/regen_bios.sh` for OpenBIOS and, with your `scph1001.bin`, the
   retail one).
5. **Generate + build, per disc** — for each disc found, in `titles/<name>/`
   of the checkout: the player's image is hard-linked in under its canonical
   name, the boot EXE extracted from it, then `psxrecomp-game --config
   game.toml` emits that disc's game as C (~1.2 GB of C; needs ~6 GB RAM —
   the long step) and CMake builds the `psx-runtime-pgxp` target with
   `-DPSX_RECOMP_UI=ON -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=ON`.
   `PSX_EXPANDED_RAM` is the 8 MB dev-console memory map (DuckStation
   "8MB RAM") required by the 8 MB polygon buffers / full-detail AI patches;
   the PGXP variant is the shipped exe and its hooks early-out when the PGXP
   patch is off.
6. **Install into the game folder** — per disc, into `titles\<name>\`: the
   exe (`GT2 Arcade.exe` / `GT2 Simulation.exe` / `GT2 Combined.exe`),
   `assets\` — including the launcher's artwork ripped from your disc at
   this point: the box art (`tools/rip_gt2_title_art.py`) and, under
   `assets\img\gt2\`, the GT mark and wordmark, licence badges, course
   maps, one nameplate per car and the car-name table
   (`tools/rip_gt2_launcher_art.py`; pure standard-library Python, run by
   the embedded interpreter) — the runtime `game.toml` (only if absent; otherwise a fresh
   copy is left as `game.toml.new` — the disc line points at your own cue),
   `seeds\`, `bios\`, the enhancement packages into `patches\`. Shared, at
   the game root: `saves\` (memory cards — all discs read the same garage),
   `settings.toml`, and the compiled `gt2_stub.c` as
   `Gran Turismo 2 Recompiled.exe` — the front door that starts the disc you
   used last. A pre-0.2 root install's captures/cache/patch-state migrate
   under `titles\combined\`. `GT2_DEV_TOOLS=1` also installs the
   diagnostics from `tools-win/dev/`.
7. **`overlay_toolchain\`** — the background native-code compiler used by the
   game: `psxrecomp-game.exe`, `compile_overlays.py`, the runtime headers
   (they define the cache namespace, so this is refreshed on every build),
   BIOS profiles, plus an embedded Python (downloaded from python.org once)
   and TinyCC 0.9.27 (fallback compiler when no gcc is on the game's PATH;
   `Play GT2.cmd` puts the MSYS2 gcc on it, which produces faster code).
8. **Native-code cache, built up front** — GT2 keeps its menu and race code
   in overlays (`GT2.OVL`) that the static recompile of the boot EXE does
   not cover; the runtime compiles them to native shards from "captures" it
   records while you play. Setup now produces those captures without
   playing: `tools/gt2_extract_overlays.py` reads `GT2.OVL` straight from
   your disc (a table of six gzip streams, every one loaded at
   `0x80010000`), hands each to the recompiler's own function discovery,
   and `compile_overlays.py` builds every shard into `titles\<name>\cache\`
   - the same cache the game keeps adding to. A first launch therefore runs
   native from the start instead of after a few sessions. This step is
   about ten minutes per disc with gcc and is skipped for shards already
   built; logs are `titles\<name>\aot_extract.txt` and `compile_cache.txt`.
   Three of the six overlays always fail their whole-image audit (discovery
   walks into data) and are built from per-function fragments instead, so
   `PSX_SHARD_RESULT ... failed=3` is the normal outcome.

Rebuilds are incremental: ccache and Ninja skip what did not change, so a
`git pull` + `setup_and_build.ps1` is minutes.

Optional: `GT2_RETAIL_TEST=1` additionally builds a retail-memory-map exe into
`retail-test\` for A/B tests against the expanded-RAM build.

## Running the game

Launch `Gran Turismo 2 Recompiled.exe` directly — that's the player flow.
The runtime finds the MSYS2 gcc itself (appended to its own PATH when nothing
else resolves), compiles newly captured code in the background while you play,
and on exit hands the remaining backlog to a detached low-priority finisher
(log: `compile_cache.txt`; disable with `PSX_OVERLAY_EXIT_COMPILE=0`).
`Play GT2.cmd` remains as an optional wrapper that runs the full-backlog
`tools\compile_cache.ps1` in the foreground after you quit; TinyCC is the
fallback compiler when no gcc exists at all.

First launch opens the launcher: renderer, internal scale, display scaling,
Crop FMVs, texture filtering, controller setup, BIOS choice, the **Disc**
row (switch between installed discs; relaunches into the picked one), and
the Patches / Cheats tab (Silent's enhancements — shown only on discs they
target). Settings land in the shared `settings.toml` at the game root;
`input.ini` / `keybinds.ini` / `patches\state.toml` sit next to each disc's
exe; each `titles\<name>\game.toml` is that disc's runtime config and safe
to hand-edit (comments explain each key). F1 opens the in-game menu with the
live graphics and PGXP settings plus **Disc → Switch disc** — a clean quit
straight into the other disc, no launcher stop-over.

## Linux (build and run from the same tree)

The tree builds natively on Linux (this is how the port is developed and
compared against DuckStation). Debian/Ubuntu packages: `build-essential cmake
ninja-build git python3` plus the X11/GL dev headers SDL needs
(`libgl-dev libx11-dev libxext-dev`); SDL3 itself is fetched at a pinned
release by the framework's CMake when no system SDL3 is found (see
`psxrecomp/docs/BUILDING.md`). The Vulkan renderer builds only when the Vulkan
SDK's `glslc` is present; OpenGL is the default either way.

```sh
git clone https://github.com/jpcarstech/GT2Recomp.git && cd GT2Recomp
git submodule update --init --recursive --depth 1
# framework patches, same order as local_build.sh
( cd psxrecomp && LC_ALL=C printf '%s\n' ../patches/upstream/*.patch ../patches/psxrecomp-*.patch | LC_ALL=C sort | while read -r p; do git apply "$p"; done )
( cd recomp-ui && git apply ../patches/recomp-ui/*.patch )
# recompiler tool
cmake -S psxrecomp/recompiler -B psxrecomp/recompiler/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build psxrecomp/recompiler/build --target psxrecomp-game
# inputs: boot EXE (extract with any ISO tool, e.g. 7z x on the .bin's ISO track) + optional BIOS
mkdir -p disc && cp /path/to/SCUS_944.88 disc/
cp /path/to/scph1001.bin psxrecomp/bios/SCPH1001.BIN   # optional
( cd psxrecomp && bash tools/regen_bios.sh --config bios/OpenBIOS.toml )
# generate + build
psxrecomp/recompiler/build/psxrecomp-game --config game.toml
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DPSXRECOMP_ROOT=$PWD/psxrecomp -DPSX_RECOMP_UI=ON -DRECOMP_UI_ROOT=$PWD/recomp-ui \
      -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=ON
cmake --build build --target psx-runtime-pgxp
```

Run folder (any directory): `build/Gran_Turismo_2_Recompiled_pgxp`,
`tools-win/local-build/game.runtime.toml` copied as `game.toml`, your
`Gran Turismo 2 Combined.bin`/`.cue`, `extracted/SCUS_944.88`, `seeds/`,
`bios/openbios.bin` (from `psxrecomp/bios/`), `build/assets/`, and
`build/mods/` copied as `patches/`. The Windows-only parts are the
`overlay_toolchain` payload (on Linux the runtime shells out to the system
`python3`/`gcc` — see `psxrecomp/docs/COMPILING_OVERLAYS.md`) and the
PowerShell helpers.

Cross-compiling a Windows exe from Linux works with
`-DCMAKE_TOOLCHAIN_FILE=psxrecomp/cmake/toolchain-mingw-w64.cmake`; the
resulting exe imports only Windows system DLLs.

## Troubleshooting

- **"No disc image found"** — the script is not in (or under) the game
  folder, or the folder has no `.bin` over 400 MB; pass `-GameDir`.
- **"skipping <file> - serial ... is not GT2 NTSC-U"** — the image is a
  different region/game; only SCUS-94455 / SCUS-94488 dumps build (the
  seeds and patches are for the NTSC-U v1.1 EXEs).
- **A patch "FAILED TO APPLY"** — the submodule is not at its pin (a manual
  `git submodule update` without `--force` over a dirty tree, or a checkout of
  a newer upstream). `git -C psxrecomp checkout -- . && git submodule update --force`
  and re-run.
- **Silent exit on launch, no window** — run `tools\run_logged.ps1`; startup
  errors of the `-mwindows` build only show there. Usual causes: missing
  `game.toml` beside the exe, missing `bios\openbios.bin`, `.cue` pointing at
  the wrong file name.
- **"Bundled BIOS missing"** — `bios\openbios.bin` must exist even when a retail
  BIOS is selected; re-run the build's install step (or copy it from
  `GT2Recomp-src\psxrecomp\bios\`).
- **Game runs slowly / stutters in races after a fresh build** — the native
  cache should have been built by Setup's step 8; check
  `titles\<name>\compile_cache.txt` ends with a `PSX_SHARD_RESULT` line and
  `titles\<name>\cache\` is populated. If step 8 failed (its message names
  the log), run `tools\compile_cache.ps1` once with the game closed, or
  just play: the runtime still captures and compiles in the background. It
  reports interpreted vs native dispatch shares in
  `diagnostics\psx_last_run_report.json`.
- **`compile_cache.ps1`: "Bundled python not found"** — the embedded Python
  download in step 7 failed (offline?). Re-run `setup_and_build.ps1`, or unzip
  `python-3.12.x-embed-amd64.zip` from python.org into
  `overlay_toolchain\python\`.
- **The game exits by itself after ~4 s on a screen with no movement** — the
  starvation watchdog. Report it with `starvation_dump.jsonl` from the game folder;
  `PSX_STARVATION_TIMEOUT_US=0` in the environment disables it meanwhile.

## Repository layout

| Path | What |
|---|---|
| `titles/<name>/` | Per-disc build config: `game.toml` (build variant + probe digests), `seeds/`, CMake project, `codegen_setup.*`, `mods_gt2_silent.c`, and `game.runtime.toml` (installed beside that disc's exe) |
| `tools-win/local-build/gt2_stub.c` | The root `Gran Turismo 2 Recompiled.exe`: starts the disc you used last |
| `tools-win/local-build/*.cmd`, `*.ps1` | Installed into the game folder: `Setup`/`Play`/`Diagnose`/`Benchmark`/`Tidy GT2 folder.cmd` at the root, helpers in `tools\` |
| `game.toml`, `seeds/`, `CMakeLists.txt`, `codegen_setup.*`, `mods_gt2_silent.c` | The Combined title at the repo root (CI + pre-0.2 flow; `titles/combined/` is the installed variant) |
| `psxrecomp/`, `recomp-ui/` | Framework and launcher submodules, pinned to upstream commits |
| `patches/` | Everything this port changes in the framework, applied at build time ([`patches/README.md`](../patches/README.md)) |
| `tools-win/` | The build scripts, player helpers, and `dev/` diagnostics |
| `docs/` | This file, [`BRINGUP.md`](BRINGUP.md), the PGXP write-up |

Framework changes are carried as patches, never as submodule forks, so anyone
can see exactly what differs from upstream PSXRecomp and the fixes can go
back upstream one at a time.

Bug reports are most useful with `diagnostics\psx_last_run_report.json`, the
player's `settings.toml`, and the output of `tools\run_logged.ps1`.
