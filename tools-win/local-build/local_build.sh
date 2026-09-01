#!/usr/bin/env bash
# GT2Recomp local build - runs inside the MSYS2 MinGW64 shell.
# Normally launched by setup_and_build.ps1; direct use:
#   bash local_build.sh <game folder, unix form> [<source checkout>]
#   e.g. bash local_build.sh "/d/Gran Turismo 2 Recompilation"
#
# Inputs it expects in the game folder:
#   Gran Turismo 2 Combined.bin / .cue   your GT2 Combined Disc image
#   extracted/SCUS_944.88                boot EXE (setup_and_build.ps1 extracts it)
#   scph1001.bin                         optional retail BIOS dump
# Outputs: "Gran Turismo 2 Recompiled.exe" + everything it needs, in place.
set -euo pipefail
GAME_DIR="${1:?usage: local_build.sh <game folder> [source checkout]}"
GITHUB_URL="${GT2RECOMP_GIT_URL:-https://github.com/jpcarstech/GT2Recomp.git}"

# ---- where the source lives -------------------------------------------------
# Preferred: this script runs from inside a checkout (<src>/tools-win/local-build),
# so that checkout is the source. Otherwise <game>/GT2Recomp-src, cloned from
# GitHub on first run (or from a gt2recomp.bundle beside it, the developer flow).
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${2:-}" ]; then
    SRC="$2"
elif [ -e "$_here/../../.git" ]; then
    SRC="$(cd "$_here/../.." && pwd)"
else
    SRC="$GAME_DIR/GT2Recomp-src"
fi

echo "== 1/7 source =="
if [ ! -e "$SRC/.git" ]; then
    if [ -f "$GAME_DIR/gt2recomp.bundle" ]; then
        git clone "$GAME_DIR/gt2recomp.bundle" "$SRC"
    else
        echo "cloning $GITHUB_URL -> $SRC"
        git clone "$GITHUB_URL" "$SRC"
    fi
fi
cd "$SRC"
if [ -f "$GAME_DIR/gt2recomp.bundle" ] && [ -z "${GT2_NO_SYNC:-}" ]; then
    # Developer flow: a bundle beside the game folder is the source of truth.
    git fetch "$GAME_DIR/gt2recomp.bundle" 'refs/heads/*:refs/remotes/bundle/*' 2>/dev/null || true
    TARGET=$(git rev-parse -q --verify bundle/main || git rev-parse -q --verify bundle/master)
    git checkout -qf -B main "$TARGET"
elif [ -z "${GT2_NO_SYNC:-}" ] && git remote get-url origin >/dev/null 2>&1 && \
     [ -z "$(git status --porcelain --untracked-files=no)" ]; then
    # Clean checkout with a remote: pick up the latest release commit.
    git pull -q --ff-only || echo "  (git pull skipped - offline or diverged; building the checkout as is)"
fi
echo "  source: $SRC @ $(git rev-parse --short HEAD)"
# Submodule working trees carry last build's applied patches; a pin move
# cannot check out over dirty files, and the checkout carries no hand edits
# by design - discard before syncing.
for _sm in psxrecomp recomp-ui; do
    if [ -e "$SRC/$_sm/.git" ]; then
        git -C "$SRC/$_sm" checkout -q -- . 2>/dev/null || true
    fi
done
git submodule update --init --recursive --force --depth 1 || git submodule update --init --recursive --force

# Self-sync: a game-folder copy of this script is only a bootstrap and can go
# stale behind the checkout. If it differs, refresh it and re-exec ONCE.
CANON="$SRC/tools-win/local-build/local_build.sh"
SELF="$GAME_DIR/local_build.sh"
if [ "${GT2_LB_SYNCED:-}" != "1" ] && [ -f "$CANON" ] && [ -f "$SELF" ] && [ "$CANON" != "$SELF" ]; then
    canon_sum=$(md5sum < "$CANON" 2>/dev/null | cut -d' ' -f1) || canon_sum=""
    self_sum=$(md5sum < "$SELF" 2>/dev/null | cut -d' ' -f1) || self_sum=""
    if [ -n "$canon_sum" ] && [ "$canon_sum" != "$self_sum" ]; then
        cp -f "$CANON" "$SELF"
        echo "== local_build.sh was stale; updated from the checkout - restarting build (once) =="
        GT2_LB_SYNCED=1 exec bash "$SELF" "$GAME_DIR" "$SRC"
    fi
fi

# ---- inputs -----------------------------------------------------------------
if [ ! -f "$GAME_DIR/extracted/SCUS_944.88" ]; then
    echo "*** $GAME_DIR/extracted/SCUS_944.88 is missing." >&2
    echo "*** Run setup_and_build.ps1 (it extracts the boot EXE from the disc image)," >&2
    echo "*** or run tools-win/extract_gt2_exe.ps1 in the game folder." >&2
    exit 1
fi

echo "== 2/7 framework patches =="
cd "$SRC/psxrecomp"
git checkout -q . 2>/dev/null || true
# ORDER MATTERS: upstream/ first, then the carried psxrecomp-* set in byte
# (LC_ALL=C) order - the order the stack is generated and tested in. A failed
# apply is fatal: a build silently missing a patch is indistinguishable from
# "the change did not help". Paths carry spaces, so lists travel on newlines.
_patch_fail=0
_patch_count=0
_apply_sorted() {
    local p b
    while IFS= read -r p; do
        [ -f "$p" ] || continue
        b=$(basename "$p")
        _patch_count=$((_patch_count + 1))
        if git apply --check "$p" 2>/dev/null; then
            git apply "$p"; echo "  applied $b"
        elif git apply --reverse --check "$p" 2>/dev/null; then
            echo "  already applied $b"
        else
            echo "  *** FAILED TO APPLY: $b" >&2
            _patch_fail=1
        fi
    done < <(LC_ALL=C printf '%s\n' "$@" | LC_ALL=C sort)
}
_apply_sorted "$SRC"/patches/upstream/*.patch
_apply_sorted "$SRC"/patches/psxrecomp-*.patch
if [ "$_patch_count" = "0" ]; then
    echo "*** No framework patches were found under $SRC/patches/. Stopping." >&2
    exit 1
fi
if [ "$_patch_fail" != "0" ]; then
    echo "*** One or more framework patches did NOT apply (see above); stopping." >&2
    exit 1
fi
cd "$SRC/recomp-ui"
git checkout -q . 2>/dev/null || true
_apply_sorted "$SRC"/patches/recomp-ui/*.patch
if [ "$_patch_fail" != "0" ]; then
    echo "*** The launcher patch did NOT apply; stopping." >&2
    exit 1
fi
cd "$SRC"

echo "== 3/7 recompiler tool =="
cmake -S psxrecomp/recompiler -B psxrecomp/recompiler/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build psxrecomp/recompiler/build --target psxrecomp-game -j

echo "== 4/7 game inputs + BIOS backends =="
mkdir -p disc
cp -f "$GAME_DIR/extracted/SCUS_944.88" disc/SCUS_944.88
for _b in "$GAME_DIR/scph1001.bin" "$GAME_DIR/bios/SCPH1001.BIN" "$GAME_DIR/bios/scph1001.bin"; do
    if [ -f "$_b" ]; then cp -f "$_b" psxrecomp/bios/SCPH1001.BIN; break; fi
done
( cd psxrecomp && bash tools/regen_bios.sh --config bios/OpenBIOS.toml )
( cd psxrecomp && [ -f bios/SCPH1001.BIN ] && bash tools/regen_bios.sh --config bios/SCPH1001.toml || true )

echo "== 5/7 generate + build (the long step; needs ~6 GB RAM) =="
psxrecomp/recompiler/build/psxrecomp-game --config game.toml
# PSX_EXPANDED_RAM: dev-console 8 MiB memory map (DuckStation "8MB RAM"
# parity), required by the 8MB Polygon Buffers / Full Detail AI Cars mods.
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DPSXRECOMP_ROOT="$SRC/psxrecomp" -DPSX_RECOMP_UI=ON -DRECOMP_UI_ROOT="$SRC/recomp-ui" \
      -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=ON
# The PGXP hook variant is THE exe: the builtin "PGXP Precision" mod toggles the
# correction at runtime; with it off every compiled-in hook early-outs.
cmake --build build --target psx-runtime-pgxp -j

echo "== 6/7 install into game folder =="
cp -f  build/Gran_Turismo_2_Recompiled_pgxp.exe "$GAME_DIR/Gran Turismo 2 Recompiled.exe"
cp -rf build/assets "$GAME_DIR/"
# Runtime config (the repo root game.toml is the BUILD variant). Never
# overwrite a player's tuned copy; leave the fresh one beside it instead.
if [ ! -f "$GAME_DIR/game.toml" ]; then
    cp -f "$SRC/tools-win/local-build/game.runtime.toml" "$GAME_DIR/game.toml"
elif [ "$(md5sum < "$SRC/tools-win/local-build/game.runtime.toml")" != "$(md5sum < "$GAME_DIR/game.toml")" ]; then
    cp -f "$SRC/tools-win/local-build/game.runtime.toml" "$GAME_DIR/game.toml.new"
    echo "  game.toml kept; the current default is beside it as game.toml.new"
fi
mkdir -p "$GAME_DIR/seeds" "$GAME_DIR/bios"
cp -f "$SRC/seeds/ghidra_funcs.txt" "$GAME_DIR/seeds/ghidra_funcs.txt"
# BIOS: the bundled OpenBIOS is always required beside the exe; a retail dump
# is optional and selectable in the launcher.
cp -f psxrecomp/bios/openbios.bin psxrecomp/bios/OpenBIOS.LICENSE "$GAME_DIR/bios/"
[ -f psxrecomp/bios/SCPH1001.BIN ] && cp -f psxrecomp/bios/SCPH1001.BIN "$GAME_DIR/bios/SCPH1001.BIN" || true
cp -f psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$GAME_DIR/bios/"
# Mod packages install as patches/ (game.toml [runtime] mods_dir = "patches").
if [ -d "$GAME_DIR/mods" ] && [ ! -d "$GAME_DIR/patches" ]; then
    mv "$GAME_DIR/mods" "$GAME_DIR/patches"
    echo "  migrated mods/ -> patches/ (enable state preserved)"
fi
mkdir -p "$GAME_DIR/patches"
cp -rf build/mods/. "$GAME_DIR/patches/"
# Player-facing scripts: launchers at the game root, helpers in tools/.
mkdir -p "$GAME_DIR/tools"
for s in setup_and_build.ps1 "Setup GT2.cmd" "Play GT2.cmd"; do
    cp -f "$SRC/tools-win/local-build/$s" "$GAME_DIR/$s"
done
for s in play_gt2.ps1 compile_cache.ps1 run_logged.ps1 organize_game_folder.ps1 \
         play_software.ps1 capture_screen.ps1; do
    cp -f "$SRC/tools-win/local-build/$s" "$GAME_DIR/tools/$s"
    rm -f "$GAME_DIR/$s"   # sweep pre-tools/ root-level copies
done
cp -f "$SRC/tools-win/extract_gt2_exe.ps1" "$GAME_DIR/tools/extract_gt2_exe.ps1"
# Developer diagnostics (tools-win/dev) install into tools/ only when asked
# (GT2_DEV_TOOLS=1); they locate the game folder one level up from tools/.
if [ "${GT2_DEV_TOOLS:-}" = "1" ] && [ -d "$SRC/tools-win/dev" ]; then
    cp -f "$SRC"/tools-win/dev/*.ps1 "$GAME_DIR/tools/"
fi

echo "== 7/7 overlay_toolchain (background native-code compiler; MUST match this build) =="
# The runtime include headers define the overlay cache namespace, so the
# toolchain is regenerated from THIS tree every build. The embedded Python and
# TinyCC payloads are downloaded once (python.org / tinycc) and reused.
TK="$GAME_DIR/overlay_toolchain"
mkdir -p "$TK" "$TK/bios"
cp -f  psxrecomp/recompiler/build/psxrecomp-game.exe "$TK/psxrecomp-game.exe"
cp -f  psxrecomp/tools/compile_overlays.py "$TK/compile_overlays.py"
rm -rf "$TK/include"
cp -r  psxrecomp/runtime/include "$TK/include"
cp -f psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$TK/bios/"
PY_VER="${GT2_EMBED_PY_VER:-3.12.10}"
if [ ! -f "$TK/python/python.exe" ]; then
    echo "  fetching embeddable Python $PY_VER (~11 MB, one-time)..."
    _pyzip="$TK/python-embed.zip"
    if curl -fsSL -o "$_pyzip" "https://www.python.org/ftp/python/$PY_VER/python-$PY_VER-embed-amd64.zip"; then
        mkdir -p "$TK/python"
        ( cd "$TK/python" && unzip -qo "$_pyzip" )
        rm -f "$_pyzip"
    else
        echo "  *** could not download Python; the game will still run, but new code stays" >&2
        echo "  *** interpreted until overlay_toolchain/python/python.exe exists (see README)." >&2
    fi
fi
if [ ! -f "$TK/tcc/tcc.exe" ]; then
    echo "  fetching TinyCC 0.9.27 (fallback compiler, ~1 MB, one-time)..."
    _tcczip="$TK/tcc.zip"
    if curl -fsSL -o "$_tcczip" "https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win64-bin.zip"; then
        ( cd "$TK" && unzip -qo "$_tcczip" ) && rm -f "$_tcczip"
    else
        echo "  (TinyCC download failed - gcc from MSYS2 is used when it is on PATH; play_gt2.ps1 adds it)"
    fi
fi
echo
echo "DONE. 'Gran Turismo 2 Recompiled.exe' is installed in: $GAME_DIR"
echo "Start it with 'Play GT2.cmd' (launches the game, then compiles newly seen code)."

# ---- optional: retail-geometry TEST exe (developer A/B) ----------------------
# GT2_RETAIL_TEST=1 builds the SAME tree with -DPSX_EXPANDED_RAM=OFF into a
# self-contained retail-test/ subfolder (own plugins, copied saves/settings).
if [ "${GT2_RETAIL_TEST:-}" = "1" ]; then
    echo "== retail-geometry TEST build (PSX_EXPANDED_RAM=OFF) =="
    cmake -S . -B build-retail -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DPSXRECOMP_ROOT="$SRC/psxrecomp" -DPSX_RECOMP_UI=ON -DRECOMP_UI_ROOT="$SRC/recomp-ui" \
          -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=OFF
    cmake --build build-retail --target psx-runtime-pgxp -j
    RT="$GAME_DIR/retail-test"
    mkdir -p "$RT" "$RT/bios" "$RT/patches" "$RT/extracted" "$RT/seeds"
    cp -f  build-retail/Gran_Turismo_2_Recompiled_pgxp.exe "$RT/GT2 Retail Test.exe"
    rm -rf "$RT/assets" "$RT/mods"
    cp -rf build-retail/assets "$RT/"
    cp -rf build-retail/mods/. "$RT/patches/"
    cp -f  psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$RT/bios/"
    cp -f  "$GAME_DIR/bios/"*.bin "$GAME_DIR/bios/"*.BIN "$RT/bios/" 2>/dev/null || true
    for f in "Gran Turismo 2 Combined.bin" "Gran Turismo 2 Combined.cue"; do
        [ -f "$GAME_DIR/$f" ] && { ln -f "$GAME_DIR/$f" "$RT/$f" 2>/dev/null || cp -f "$GAME_DIR/$f" "$RT/$f"; }
    done
    for f in game.toml bios.cfg disc.cfg overlay_captures.json settings.toml config.ini; do
        [ -f "$GAME_DIR/$f" ] && cp -f "$GAME_DIR/$f" "$RT/$f" || true
    done
    cp -f "$GAME_DIR/extracted/SCUS_944.88" "$RT/extracted/"
    cp -f "$GAME_DIR/seeds/ghidra_funcs.txt" "$RT/seeds/"
    [ -d "$GAME_DIR/saves" ] && rm -rf "$RT/saves" && cp -rf "$GAME_DIR/saves" "$RT/saves" || true
    echo "RETAIL TEST installed: retail-test/GT2 Retail Test.exe"
fi
