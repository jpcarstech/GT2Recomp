# Building GT2Recomp

The player version is in the [README](../README.md#install):
unzip `GT2Recomp-setup.zip` next to your GT2 Combined Disc image and
double-click `Setup GT2.cmd`. This page is the long version — what each step
does, how to run it by hand, and how to build on Linux.

## Inputs you provide

| File | Where | Notes |
|---|---|---|
| `Gran Turismo 2 Combined.bin` + `.cue` | game folder | Built from your own Arcade + Simulation dumps with [GT2-Combined-Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc). Expected: 1,033,459,392 bytes, MD5 `70ecd6e788501eb69a220d2a96e624c4`. The `.cue` must reference the `.bin` by its real file name (`setup_and_build.ps1` rewrites it if not). |
| `scph1001.bin` | game folder (optional) | A retail SCPH-1001 BIOS dump. Without it the bundled OpenBIOS is used; with it you can pick either in the launcher. Some titles behave differently on OpenBIOS; GT2 runs on both. |

Everything else is derived: the boot EXE is extracted from the image, the
generated C comes out of the recompiler, and the framework is fetched at its
pinned commit.

## What `setup_and_build.ps1` does

1. **Finds the game folder** — the folder containing `Gran Turismo 2 Combined.bin`,
   looked up from the script's own location (three levels up from
   `GT2Recomp-src\tools-win\local-build\`) or passed with `-GameDir`. If the
   only large `.bin` there has another name it offers to rename it.
2. **Checks the image** (size + MD5) and warns on a mismatch. A different base
   image means a different boot EXE, and the function seeds in
   `seeds/ghidra_funcs.txt` are for `SCUS_944.88` from this image.
3. **Extracts the boot EXE**: `tools-win/extract_gt2_exe.ps1` parses the
   ISO9660 filesystem inside the raw MODE2/2352 image, reads `SYSTEM.CNF`, and
   writes `extracted\SCUS_944.88` (plus `disc_listing.txt` / `disc_md5.txt`).
4. **Installs the toolchain** — MSYS2 via `winget`, then
   `mingw-w64-x86_64-{toolchain,cmake,ninja,ccache}`, `git`, `python`,
   `unzip`, `curl` via `pacman`. One-time; re-runs are no-ops.
5. **Runs `local_build.sh`** in the MSYS2 MinGW64 shell, which does the actual
   work (below).

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
4. **Inputs + BIOS** — copies `extracted/SCUS_944.88` to `disc/`, your
   `scph1001.bin` (if any) to `psxrecomp/bios/SCPH1001.BIN`, and regenerates
   the recompiled BIOS backends (`tools/regen_bios.sh` for OpenBIOS and, if
   present, the retail one).
5. **Generate + build** — `psxrecomp-game --config game.toml` emits the game as
   C (~9,800 functions, ~1.2 GB of C in ~230 shards; this needs ~6 GB RAM and
   is the long step), then CMake configures the game runtime with
   `-DPSX_RECOMP_UI=ON -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=ON`
   and builds the `psx-runtime-pgxp` target. `PSX_EXPANDED_RAM` is the 8 MB
   dev-console memory map (DuckStation "8MB RAM") required by the 8 MB polygon
   buffers / full-detail AI patches; the PGXP variant is the shipped exe and
   its hooks early-out when the PGXP patch is off.
6. **Install into the game folder** — the exe as `Gran Turismo 2 Recompiled.exe`,
   `assets\`, the runtime `game.toml` (only if absent; otherwise a fresh copy is
   left as `game.toml.new`), `seeds\`, `bios\` (OpenBIOS + license + your dump
   + the BIOS profiles), the enhancement packages into `patches\` (their
   enable state in `patches\state.toml` is preserved), `Play GT2.cmd`,
   `setup_and_build.ps1`, and the player helpers into `tools\`.
   `GT2_DEV_TOOLS=1` also installs the diagnostics from `tools-win/dev/`.
7. **`overlay_toolchain\`** — the background native-code compiler used by the
   game: `psxrecomp-game.exe`, `compile_overlays.py`, the runtime headers
   (they define the cache namespace, so this is refreshed on every build),
   BIOS profiles, plus an embedded Python (downloaded from python.org once)
   and TinyCC 0.9.27 (fallback compiler when no gcc is on the game's PATH;
   `Play GT2.cmd` puts the MSYS2 gcc on it, which produces faster code).

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
Crop FMVs, texture filtering, controller setup, BIOS choice, and the
Patches / Cheats tab (Silent's enhancements). Everything lands in
`settings.toml` / `input.ini` / `keybinds.ini` / `patches\state.toml` next to
the exe; `game.toml` is the port's runtime config and safe to hand-edit
(comments explain each key). F1 opens the in-game menu with the live graphics
and PGXP settings.

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

- **"Could not find 'Gran Turismo 2 Combined.bin'"** — the script is not in
  (or under) the game folder; pass `-GameDir`.
- **Extraction produced no `SCUS_944.88`** — the image is not the Combined
  Disc (its boot EXE is the Simulation disc's `SCUS_944.88`); check
  `extracted\disc_listing.txt` and `SYSTEM.CNF`.
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
  cache is empty. Play a few sessions or run `tools\compile_cache.ps1` once
  with the game closed; the runtime reports interpreted vs native dispatch
  shares in `diagnostics\psx_last_run_report.json`.
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
| `game.toml` | Game identity + recompiler config (build variant) |
| `tools-win/local-build/game.runtime.toml` | The `game.toml` installed beside the exe (runtime variant) |
| `seeds/ghidra_funcs.txt` | Function seeds for the boot EXE (entry + JAL scan) |
| `CMakeLists.txt`, `codegen_setup.*` | Game runtime target (`psxrecomp_add_game_runtime`) |
| `mods_gt2_silent.c`, `mods/` | The enhancement package: Silent's codes as runtime patch plugins |
| `psxrecomp/`, `recomp-ui/` | Framework and launcher submodules, pinned to upstream commits |
| `patches/` | Everything this port changes in the framework, applied at build time ([`patches/README.md`](../patches/README.md)) |
| `tools-win/` | The build scripts, player helpers, and `dev/` diagnostics |
| `docs/` | This file, [`BRINGUP.md`](BRINGUP.md), the PGXP write-up |

Framework changes are carried as patches, never as submodule forks, so anyone
can see exactly what differs from upstream PSXRecomp and the fixes can go
back upstream one at a time.

Bug reports are most useful with `diagnostics\psx_last_run_report.json`, the
player's `settings.toml`, and the output of `tools\run_logged.ps1`.
