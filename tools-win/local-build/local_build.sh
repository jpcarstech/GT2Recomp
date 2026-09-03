#!/usr/bin/env bash
# GT2Recomp local build - runs inside the MSYS2 MinGW64 shell.
# Normally launched by setup_and_build.ps1; direct use:
#   bash local_build.sh <game folder, unix form> [<source checkout>]
#   e.g. bash local_build.sh "/d/Gran Turismo 2 Recompilation"
#
# Inputs it expects in the game folder: your own disc dump(s), any file
# names - Arcade disc, Simulation disc, or the optional GT2 Combined Disc
# image (.bin, with or without .cue) - plus optionally scph1001.bin (retail
# BIOS dump). Every disc found gets its own build under titles\<name>\ and
# the root "Gran Turismo 2 Recompiled.exe" starts whichever disc you used
# last (switchable in the launcher and the in-game F1 menu).
set -euo pipefail
# Bump when this script changes shape. The self-sync below replaces a game-
# folder copy with the checkout's ONLY when the checkout's is newer by this
# number - never the other way. Without it, a setup zip that is ahead of the
# GitHub checkout (a release being prepared, a stale clone) downgraded itself
# to the older script on the first run and then failed in that script's terms,
# with no exe and no hint that the newer script had ever been there.
GT2_LB_VERSION=4
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

echo "== 1/8 source =="
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
# stale behind the checkout. If the checkout's is NEWER (GT2_LB_VERSION),
# refresh it and re-exec ONCE. An older checkout never wins: it is told so,
# and the build carries on with this script (which knows how to use it).
CANON="$SRC/tools-win/local-build/local_build.sh"
SELF="$GAME_DIR/local_build.sh"
if [ "${GT2_LB_SYNCED:-}" != "1" ] && [ -f "$CANON" ] && [ -f "$SELF" ] && [ "$CANON" != "$SELF" ]; then
    canon_ver=$(sed -n 's/^GT2_LB_VERSION=\([0-9][0-9]*\)$/\1/p' "$CANON" | head -1)
    if [ -z "$canon_ver" ]; then canon_ver=0; fi
    if [ "$canon_ver" -gt "$GT2_LB_VERSION" ]; then
        cp -f "$CANON" "$SELF"
        echo "== local_build.sh was stale (v$GT2_LB_VERSION -> v$canon_ver); updated from the checkout - restarting build (once) =="
        GT2_LB_SYNCED=1 exec bash "$SELF" "$GAME_DIR" "$SRC"
    elif [ "$canon_ver" -lt "$GT2_LB_VERSION" ]; then
        echo "  (the source checkout carries an OLDER build script, v$canon_ver < v$GT2_LB_VERSION;"
        echo "   keeping this one. If the checkout is behind, that is GitHub not being"
        echo "   updated yet - or a bundle beside the game folder is the source of truth.)"
    fi
fi

# A checkout this script cannot build from (pre-0.2: no titles/) stops HERE
# with the reason, rather than 400 lines later with a missing-file error.
if [ ! -d "$SRC/titles" ]; then
    echo "*** The source checkout at $SRC is older than this setup (it has no titles/" >&2
    echo "*** folder, so it is pre-0.2). Either GitHub has not been updated for this" >&2
    echo "*** release yet, or GT2Recomp-src is a stale clone. Delete GT2Recomp-src and" >&2
    echo "*** re-run once the release is published (or put gt2recomp.bundle beside" >&2
    echo "*** the game folder to build from it directly)." >&2
    exit 1
fi

echo "== 2/8 framework patches =="
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

echo "== 3/8 recompiler tool =="
cmake -S psxrecomp/recompiler -B psxrecomp/recompiler/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build psxrecomp/recompiler/build --target psxrecomp-game -j
RECOMPILER="$SRC/psxrecomp/recompiler/build/psxrecomp-game"
[ -x "$RECOMPILER" ] || RECOMPILER="$RECOMPILER.exe"

echo "== 4/8 discs =="
# Find every disc image in the game folder and work out which GT2 disc each
# one is, from its CONTENT (boot serial + data-track size) - file names do
# not matter. Every disc found becomes its own build under titles\<name>\.
PY="$(command -v python3 || command -v python)"
PROBE="$SRC/psxrecomp/tools/new_project_layout/probe_disc.py"
declare -A DISC_CUE DISC_BIN
_cue_for_bin() {
    # Ensure a .cue exists for this .bin and references its real file name.
    local bin="$1" cue="${1%.bin}.cue" bname
    bname=$(basename "$bin")
    if [ ! -f "$cue" ]; then
        printf 'FILE "%s" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n' "$bname" > "$cue"
        echo "  wrote $(basename "$cue")" >&2
    elif ! grep -qF "$bname" "$cue"; then
        cp -f "$cue" "$cue.bak"
        printf 'FILE "%s" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n' "$bname" > "$cue"
        echo "  fixed $(basename "$cue") to reference $bname (old copy: $(basename "$cue").bak)" >&2
    fi
    printf '%s' "$cue"
}
while IFS= read -r -d '' _bin; do
    _size=$(stat -c '%s' "$_bin" 2>/dev/null || stat -f '%z' "$_bin")
    [ "$_size" -gt 400000000 ] || continue
    _cue=$(_cue_for_bin "$_bin")
    _json="$SRC/.probe_tmp.json"
    if ! "$PY" "$PROBE" --identity-only --json-out "$_json" "$_cue" >/dev/null 2>&1; then
        echo "  (skipping $(basename "$_bin") - not a readable PS1 disc image)"
        continue
    fi
    # The path MUST travel as an argv entry: MSYS2 rewrites /d/... to D:\... for
    # a native Windows program's ARGUMENTS, but not inside a -c script string,
    # so an embedded path reaches Python untranslated and cannot be opened.
    _serial=$("$PY" -c 'import json,sys
try:
    print(json.load(open(sys.argv[1]))["serial"] or "")
except Exception:
    pass' "$_json" 2>/dev/null)
    if [ -z "$_serial" ]; then
        echo "  (skipping $(basename "$_bin") - could not read its disc identity)"
        continue
    fi
    _title=""
    case "$_serial" in
        SCUS-94455) _title="arcade" ;;
        SCUS-94488) if [ "$_size" -ge 1000000000 ]; then _title="combined"; else _title="simulation"; fi ;;
        *) echo "  (skipping $(basename "$_bin") - serial '$_serial' is not GT2 NTSC-U)" ;;
    esac
    [ -n "$_title" ] || continue
    if [ -n "${DISC_CUE[$_title]:-}" ]; then
        echo "  (two $_title discs found; using $(basename "${DISC_BIN[$_title]}"))"
        continue
    fi
    DISC_CUE[$_title]="$_cue"
    DISC_BIN[$_title]="$_bin"
    echo "  $(basename "$_bin") -> $_title ($_serial)"
done < <(find "$GAME_DIR" -maxdepth 1 -name '*.bin' -type f -print0)
rm -f "$SRC/.probe_tmp.json"
TITLES=()
for _t in arcade simulation combined; do
    [ -n "${DISC_CUE[$_t]:-}" ] && TITLES+=("$_t")
done
if [ "${#TITLES[@]}" = "0" ]; then
    echo "*** No GT2 disc image found in $GAME_DIR." >&2
    echo "*** Put your Arcade and/or Simulation disc dumps (.bin) there - any" >&2
    echo "*** file names - and run setup again. (NTSC-U v1.1 dumps are the" >&2
    echo "*** tested ones; the optional GT2 Combined Disc also works.)" >&2
    exit 1
fi
echo "  building: ${TITLES[*]}"

echo "== 5/8 BIOS backends =="
for _b in "$GAME_DIR/scph1001.bin" "$GAME_DIR/bios/SCPH1001.BIN" "$GAME_DIR/bios/scph1001.bin"; do
    if [ -f "$_b" ]; then cp -f "$_b" psxrecomp/bios/SCPH1001.BIN; break; fi
done
( cd psxrecomp && bash tools/regen_bios.sh --config bios/OpenBIOS.toml )
( cd psxrecomp && [ -f bios/SCPH1001.BIN ] && bash tools/regen_bios.sh --config bios/SCPH1001.toml || true )

# ---- progress reporting -----------------------------------------------------
# Setup is 30-60 minutes per disc, and a silent black window is the most likely
# moment for someone to decide it has hung and kill it. These keep one live
# line going with a real estimate, and push the thousands of recompiler
# warnings into a log instead of the screen.
_hms() {
    local s=$1
    if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $((s/3600)) $(((s%3600)/60))
    elif [ "$s" -ge 60 ]; then printf '%dm %02ds' $((s/60)) $((s%60))
    else printf '%ds' "$s"; fi
}

# Run a long, noisy command with a ticking elapsed-time line. Full output goes
# to $1 so a failure can still be diagnosed.
_run_with_spinner() {
    local log="$1" what="$2"; shift 2
    local start=$SECONDS pid rc
    "$@" > "$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r   %s ... %s   ' "$what" "$(_hms $((SECONDS - start)))"
        sleep 2
    done
    if wait "$pid"; then rc=0; else rc=$?; fi
    if [ "$rc" = 0 ]; then
        printf '\r   %s ... done in %s        \n' "$what" "$(_hms $((SECONDS - start)))"
    else
        printf '\r   %s ... FAILED after %s   \n' "$what" "$(_hms $((SECONDS - start)))"
        echo "   last lines of $log:" >&2
        tail -n 15 "$log" >&2
    fi
    return $rc
}

# Filter ninja's output down to one live line with a percentage and an ETA.
# Reads stdin; everything is still written to $1 verbatim.
_build_progress() {
    local log="$1" label="$2" start=$SECONDS line n t el eta
    : > "$log"
    while IFS= read -r line; do
        printf '%s\n' "$line" >> "$log"
        if [[ "$line" =~ ^\[([0-9]+)/([0-9]+)\] ]]; then
            n=${BASH_REMATCH[1]}; t=${BASH_REMATCH[2]}
            el=$((SECONDS - start))
            if [ "$n" -gt 20 ] && [ "$el" -gt 10 ] && [ "$t" -gt 0 ]; then
                eta=$(( el * (t - n) / n ))
                printf '\r   %s: compiling %d of %d  ·  %d%%  ·  about %s left      ' \
                       "$label" "$n" "$t" $((100 * n / t)) "$(_hms $eta)"
            else
                printf '\r   %s: compiling %d of %d      ' "$label" "$n" "$t"
            fi
        else
            case "$line" in
                *[Ee]rror*|FAILED:*|*"error:"*) printf '\n%s\n' "$line" ;;
            esac
        fi
    done
    printf '\r   %s: compiled in %s                              \n' \
           "$label" "$(_hms $((SECONDS - start)))"
}

echo "== 6/8 building your discs - the long step (30-60 min each) =="
_disc_no=0
for _t in "${TITLES[@]}"; do
    TDIR="$SRC/titles/$_t"
    _disc_no=$((_disc_no + 1))
    case "$_t" in
        arcade)     _disc_label="Arcade" ;;
        simulation) _disc_label="Simulation" ;;
        combined)   _disc_label="Combined" ;;
        *)          _disc_label="$_t" ;;
    esac
    _step="Disc $_disc_no of ${#TITLES[@]} ($_disc_label)"
    echo "-- $_step --"
    mkdir -p "$TDIR/disc"
    # The build config references the disc by its canonical name; link the
    # player's image (hard link when possible - no copy of a 700 MB file).
    _canon_bin=$(grep -m1 '^bin_name' "$TDIR/game.toml" | sed 's/.*= *"\(.*\)"/\1/')
    _canon_cue=$(grep -m1 '^cue_name' "$TDIR/game.toml" | sed 's/.*= *"\(.*\)"/\1/')
    ln -f "${DISC_BIN[$_t]}" "$TDIR/disc/$_canon_bin" 2>/dev/null || cp -f "${DISC_BIN[$_t]}" "$TDIR/disc/$_canon_bin"
    printf 'FILE "%s" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n' "$_canon_bin" > "$TDIR/disc/$_canon_cue"
    # BIOS profiles: the recompiler wants them findable from the title root.
    mkdir -p "$TDIR/bios"
    cp -f psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$TDIR/bios/"
    # Boot EXE, extracted from the player's own disc.
    "$PY" "$PROBE" --identity-only --write-boot-exe "$TDIR/disc" "${DISC_CUE[$_t]}" >/dev/null
    _exe_rel=$(grep -m1 '^exe' "$TDIR/game.toml" | sed 's/.*= *"\(.*\)"/\1/')
    if [ ! -f "$TDIR/$_exe_rel" ]; then
        echo "*** $_t: boot EXE extraction did not produce $_exe_rel" >&2
        exit 1
    fi
    # The generate is the long step (~10 min/disc). It is a pure function of
    # the boot EXE, the seeds and the recompiler build, so skip it when the
    # emitted dispatch table is newer than all three — that is what makes
    # re-running setup (to pick up a new release) minutes instead of an hour.
    _exe_name=$(basename "$_exe_rel")
    _dispatch="$TDIR/generated/${_exe_name}_dispatch.c"
    if [ -f "$_dispatch" ] && [ "$_dispatch" -nt "$TDIR/$_exe_rel" ] && \
       [ "$_dispatch" -nt "$TDIR/seeds/ghidra_funcs.txt" ] && \
       [ "$_dispatch" -nt "$RECOMPILER" ]; then
        echo "   converting game code ... already up to date"
    else
        ( cd "$TDIR" && _run_with_spinner "$TDIR/generate.log" \
              "converting game code to C" "$RECOMPILER" --config game.toml )
    fi
    # PSX_EXPANDED_RAM: dev-console 8 MiB memory map (DuckStation "8MB RAM"
    # parity), required by the 8MB Polygon Buffers / Full Detail AI Cars mods.
    _run_with_spinner "$TDIR/configure.log" "preparing the build" \
        cmake -S "$TDIR" -B "$TDIR/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DPSXRECOMP_ROOT="$SRC/psxrecomp" -DPSX_RECOMP_UI=ON -DRECOMP_UI_ROOT="$SRC/recomp-ui" \
          -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=ON
    # The PGXP hook variant is THE exe: the builtin "PGXP Precision" mod
    # toggles the correction at runtime; off = every compiled-in hook early-outs.
    cmake --build "$TDIR/build" --target psx-runtime-pgxp -j 2>&1 \
        | _build_progress "$TDIR/build.log" "$_step"
done

echo "== 7/8 install into game folder =="
# The enhancement tree is mods\ - upstream's name for it. Earlier GT2Recomp
# releases called the same folder patches\; carry it across whole (packages
# AND state.toml, i.e. what the player has ticked) before anything below
# creates a fresh mods\ beside it.
if [ -d "$GAME_DIR/patches" ] && [ ! -d "$GAME_DIR/mods" ]; then
    echo "  renaming patches/ -> mods/ (upstream's name for the enhancement tree)"
    mv -f "$GAME_DIR/patches" "$GAME_DIR/mods"
elif [ -d "$GAME_DIR/patches" ] && [ -d "$GAME_DIR/mods" ]; then
    # Both present (a hand-made mods/ next to an old patches/): the player's
    # enable state is the one thing that must not be lost.
    [ -f "$GAME_DIR/mods/state.toml" ] || cp -f "$GAME_DIR/patches/state.toml" "$GAME_DIR/mods/state.toml" 2>/dev/null || true
    rm -rf "$GAME_DIR/patches.pre-mods"
    mv -f "$GAME_DIR/patches" "$GAME_DIR/patches.pre-mods"
fi
mkdir -p "$GAME_DIR/saves" "$GAME_DIR/titles" "$GAME_DIR/mods"
for _t in "${TITLES[@]}"; do
    TDIR="$SRC/titles/$_t"
    D="$GAME_DIR/titles/$_t"
    case "$_t" in
        arcade)     _label="Arcade" ;;
        simulation) _label="Simulation" ;;
        combined)   _label="Combined" ;;
    esac
    mkdir -p "$D/bios" "$D/extracted" "$D/seeds"
    # One exe per title folder (the root stub and the Disc rows find it by
    # being the only .exe there).
    # Never use $(ls ... | head -1) here: an unmatched glob makes ls fail and
    # `set -e` + pipefail would abort the install with no message (it did).
    _built=""
    for _cand in "$TDIR/build/"*_pgxp.exe "$TDIR/build/"*_pgxp; do
        [ -f "$_cand" ] && { _built="$_cand"; break; }
    done
    if [ -z "$_built" ]; then
        echo "*** $_t: no built exe under $TDIR/build" >&2
        exit 1
    fi
    cp -f "$_built" "$D/GT2 $_label.exe"
    rm -rf "$D/assets"
    cp -rf "$TDIR/build/assets" "$D/"
    # Runtime config. Never overwrite a player's tuned copy; leave the fresh
    # one beside it instead. __DISC_CUE__ becomes the player's own cue name.
    _cue_base=$(basename "${DISC_CUE[$_t]}")
    sed "s|__DISC_CUE__|$_cue_base|" "$TDIR/game.runtime.toml" > "$D/game.toml.fresh"
    if [ ! -f "$D/game.toml" ]; then
        mv -f "$D/game.toml.fresh" "$D/game.toml"
    elif [ "$(md5sum < "$D/game.toml.fresh")" != "$(md5sum < "$D/game.toml")" ]; then
        # Keep every value the player has tuned, but add the keys this release
        # introduced - otherwise an update that adds a launcher feature (the
        # frame-rate row, the presets: both live in game.toml) does nothing at
        # all for anyone who already has a config, and they never find out.
        # The presets and promoted rows are OUR definitions, not the
        # player's settings, so those groups are refreshed from the template;
        # every other value they have tuned is kept exactly as it is.
        if "$PY" "$SRC/tools/merge_runtime_config.py" \
                --replace runtime.feature_preset \
                --replace runtime.featured_feature_row \
                --force-key runtime.mods_dir \
                --force-key runtime.cheats_page_note \
                "$D/game.toml.fresh" "$D/game.toml"; then
            rm -f "$D/game.toml.fresh" "$D/game.toml.new"
        else
            mv -f "$D/game.toml.fresh" "$D/game.toml.new"
            echo "  $_t: game.toml kept as is; the current default is beside it as game.toml.new"
        fi
    else
        rm -f "$D/game.toml.fresh"
    fi
    cp -f "$TDIR/seeds/ghidra_funcs.txt" "$D/seeds/ghidra_funcs.txt"
    cp -f "$TDIR/disc/"SCUS_944.* "$D/extracted/" 2>/dev/null || true
    # BIOS: the bundled OpenBIOS is always required beside the exe; a retail
    # dump is optional and selectable in the launcher.
    cp -f psxrecomp/bios/openbios.bin psxrecomp/bios/OpenBIOS.LICENSE "$D/bios/"
    [ -f psxrecomp/bios/SCPH1001.BIN ] && cp -f psxrecomp/bios/SCPH1001.BIN "$D/bios/SCPH1001.BIN" || true
    cp -f psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$D/bios/"
    # Enhancements are shared by the whole install (game.toml mods_dir =
    # "mods", resolved beside the shared settings.toml), so they are
    # installed ONCE at the game root rather than once per title. Every
    # title builds the same mods/ tree, so which title does the copy makes
    # no difference; state.toml (what the player has ticked) is never
    # touched by it.
    cp -rf "$TDIR/build/mods/." "$GAME_DIR/mods/"
done
# v0.1.x migration: the old single-build layout kept the Combined build's
# state at the game root. Move it under titles/combined/ so nothing is lost.
if [ -n "${DISC_CUE[combined]:-}" ] && [ -f "$GAME_DIR/overlay_captures.json" ] && [ ! -f "$GAME_DIR/titles/combined/overlay_captures.json" ]; then
    echo "  migrating pre-0.2 root install state -> titles/combined/"
    mv -f "$GAME_DIR/overlay_captures.json" "$GAME_DIR/titles/combined/"
    [ -d "$GAME_DIR/cache" ] && mv -f "$GAME_DIR/cache" "$GAME_DIR/titles/combined/cache" || true
    # The enhancement tree deliberately stays at the game root (renamed
    # patches/ -> mods/ above): 0.2 shares one tree across every disc, which
    # is where a pre-0.2 install already kept it - so a player who upgrades
    # finds exactly the enhancements they had ticked, still ticked, on every
    # disc that has them.
    [ -f "$GAME_DIR/game.toml" ] && mv -f "$GAME_DIR/game.toml" "$GAME_DIR/game.toml.pre-0.2.bak" || true
fi
# 0.2-beta migration: the first 0.2 builds kept one patches/ tree per title.
# Promote the first one that has a state.toml so nobody loses what they ticked,
# then retire the rest (renamed, never deleted - they are the only record).
if [ ! -f "$GAME_DIR/mods/state.toml" ]; then
    for _t in "${TITLES[@]}"; do
        if [ -f "$GAME_DIR/titles/$_t/patches/state.toml" ]; then
            echo "  migrating enhancements from titles/$_t/ to the shared mods/"
            cp -f "$GAME_DIR/titles/$_t/patches/state.toml" "$GAME_DIR/mods/state.toml"
            break
        fi
    done
fi
for _t in "${TITLES[@]}"; do
    if [ -d "$GAME_DIR/titles/$_t/patches" ]; then
        rm -rf "$GAME_DIR/titles/$_t/patches.pre-shared"
        mv -f "$GAME_DIR/titles/$_t/patches" "$GAME_DIR/titles/$_t/patches.pre-shared"
    fi
done

# The front door: a tiny stub that starts whichever disc you used last.
# (MSYS2's gcc targets Windows; on a Linux dev box the mingw cross gcc does.)
echo "  building the root exe (disc chooser stub)"
_stubcc=gcc
command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 && _stubcc=x86_64-w64-mingw32-gcc
"$_stubcc" -O2 -mwindows -o "$GAME_DIR/Gran Turismo 2 Recompiled.exe" "$SRC/tools-win/local-build/gt2_stub.c"
# Player-facing scripts: launchers at the game root, helpers in tools/.
mkdir -p "$GAME_DIR/tools"
for s in setup_and_build.ps1 "Setup GT2.cmd" "Play GT2.cmd" "Diagnose GT2.cmd" "Benchmark GT2.cmd" "Tidy GT2 folder.cmd"; do
    cp -f "$SRC/tools-win/local-build/$s" "$GAME_DIR/$s"
done
for s in play_gt2.ps1 compile_cache.ps1 run_logged.ps1 organize_game_folder.ps1 \
         play_software.ps1 capture_screen.ps1 tidy_game_folder.ps1; do
    cp -f "$SRC/tools-win/local-build/$s" "$GAME_DIR/tools/$s"
    rm -f "$GAME_DIR/$s"   # sweep pre-tools/ root-level copies
done
cp -f "$SRC/tools-win/extract_gt2_exe.ps1" "$GAME_DIR/tools/extract_gt2_exe.ps1" 2>/dev/null || true
# Developer diagnostics (tools-win/dev) install into tools/ only when asked
# (GT2_DEV_TOOLS=1); they locate the game folder one level up from tools/.
if [ "${GT2_DEV_TOOLS:-}" = "1" ] && [ -d "$SRC/tools-win/dev" ]; then
    cp -f "$SRC"/tools-win/dev/*.ps1 "$GAME_DIR/tools/"
fi

echo "== 8/8 overlay_toolchain (background native-code compiler; MUST match this build) =="
# The runtime include headers define the overlay cache namespace, so the
# toolchain is regenerated from THIS tree every build. The embedded Python and
# TinyCC payloads are downloaded once (python.org / tinycc) and reused. One
# toolchain at the install root serves every title.
TK="$GAME_DIR/overlay_toolchain"
mkdir -p "$TK" "$TK/bios"
cp -f  psxrecomp/recompiler/build/psxrecomp-game.exe "$TK/psxrecomp-game.exe" 2>/dev/null || \
cp -f  psxrecomp/recompiler/build/psxrecomp-game "$TK/psxrecomp-game"
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
echo "DONE. Installed discs: ${TITLES[*]}"
echo "Double-click 'Gran Turismo 2 Recompiled.exe' to play - it opens the disc"
echo "you used last; change discs in the launcher's Disc row or in-game (F1)."

# ---- optional: retail-geometry TEST exe (developer A/B) ----------------------
# GT2_RETAIL_TEST=1 builds the Combined title with -DPSX_EXPANDED_RAM=OFF into
# a self-contained retail-test/ subfolder (own plugins, copied saves/settings).
if [ "${GT2_RETAIL_TEST:-}" = "1" ] && [ -n "${DISC_CUE[combined]:-}" ]; then
    echo "== retail-geometry TEST build (PSX_EXPANDED_RAM=OFF) =="
    TDIR="$SRC/titles/combined"
    cmake -S "$TDIR" -B "$TDIR/build-retail" -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DPSXRECOMP_ROOT="$SRC/psxrecomp" -DPSX_RECOMP_UI=ON -DRECOMP_UI_ROOT="$SRC/recomp-ui" \
          -DPSX_PGXP_VARIANT=ON -DPSX_DEBUG_TOOLS=ON -DPSX_EXPANDED_RAM=OFF
    cmake --build "$TDIR/build-retail" --target psx-runtime-pgxp -j
    RT="$GAME_DIR/retail-test"
    mkdir -p "$RT" "$RT/bios" "$RT/mods" "$RT/extracted" "$RT/seeds"
    cp -f  "$TDIR/build-retail/"*_pgxp.exe "$RT/GT2 Retail Test.exe"
    rm -rf "$RT/assets" "$RT/mods"
    cp -rf "$TDIR/build-retail/assets" "$RT/"
    cp -rf "$TDIR/build-retail/mods/." "$RT/mods/"
    cp -f  psxrecomp/bios/SCPH1001.toml psxrecomp/bios/OpenBIOS.toml "$RT/bios/"
    cp -f  "$GAME_DIR/titles/combined/bios/"*.bin "$GAME_DIR/titles/combined/bios/"*.BIN "$RT/bios/" 2>/dev/null || true
    ln -f "${DISC_BIN[combined]}" "$RT/$(basename "${DISC_BIN[combined]}")" 2>/dev/null || cp -f "${DISC_BIN[combined]}" "$RT/"
    cp -f "${DISC_CUE[combined]}" "$RT/"
    for f in game.toml overlay_captures.json settings.toml config.ini; do
        [ -f "$GAME_DIR/titles/combined/$f" ] && cp -f "$GAME_DIR/titles/combined/$f" "$RT/$f" || true
    done
    # retail-test/ is a self-contained A/B folder one level below the game
    # root, so the title's "../../" shared paths (settings, saves, patches,
    # disc) would point a level ABOVE the game folder. Re-root them here.
    [ -f "$RT/game.toml" ] && "$PY" - "$RT/game.toml" <<'PYEOF' || true
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = re.sub(r'(?m)^(\s*(?:memcard_dir|settings_path|mods_dir|disc)\s*=\s*")\.\./\.\./',
           r'\1', s)
open(p, 'w', encoding='utf-8').write(s)
PYEOF
    [ -f "$GAME_DIR/settings.toml" ] && cp -f "$GAME_DIR/settings.toml" "$RT/settings.toml" || true
    cp -f "$GAME_DIR/titles/combined/extracted/SCUS_944.88" "$RT/extracted/" 2>/dev/null || true
    cp -f "$TDIR/seeds/ghidra_funcs.txt" "$RT/seeds/"
    [ -d "$GAME_DIR/saves" ] && rm -rf "$RT/saves" && cp -rf "$GAME_DIR/saves" "$RT/saves" || true
    echo "RETAIL TEST installed: retail-test/GT2 Retail Test.exe"
fi
