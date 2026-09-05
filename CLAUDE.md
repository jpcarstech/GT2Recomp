# GT2Recomp — working notes

## Configuration rule (multi-disc installs)

Anything the player sets in the launcher or the in-game F1 menu applies to
EVERY disc. What lives with the disc instead of the player is a short list,
and it is short by evidence rather than by assumption:

| Lives with the PLAYER (install-wide) | Where |
|---|---|
| video, audio, controller device/deadzone, hotkeys, memory cards, BIOS, language | `settings.toml` at the game root, via `[runtime] settings_path` |
| pad button mapping | `input.ini`, anchored to the shared settings file's directory |
| keyboard binds + hotkeys | `keybinds.ini`, same anchor |
| which enhancements are ticked | `mods/state.toml` at the game root — `mods_dir` stays a PLAIN name and is resolved against the shared settings file's directory |

| Lives with the DISC | Where |
|---|---|
| this title's disc image | `titles/<name>/game.toml` `disc`, and `titles/<name>/disc.cfg` |
| native-code cache, captures, dumps, diagnostics | `titles/<name>/` |

Enhancements are shared because they were CHECKED, not assumed. Against
DuckStation's cheat DB (`resources/patches.zip`, `SCUS-94455_*.cht` vs
`SCUS-94488_*.cht`) the 60 FPS, widescreen 16:9/21:9, higher draw distance,
full-detail AI cars and 8 MB polygon-buffer codes are **byte-identical**
across the Arcade and Simulation discs — the race-engine overlay loads at
the same addresses on both. Only the arcade unlocks genuinely differ, and
those carry their own `[[feature.target]]`. Safety comes from per-feature
targeting, not from keeping separate state files: a feature the running
disc does not have is inert there rather than applied.

Before adding a new enhancement that might be disc-specific, check it the
same way rather than guessing, and give it a `[[feature.target]]` if the
codes differ.

**Disc REVISION matters as much as disc.** DuckStation ships two databases:
`patches.zip` (Silent's code patches, hash-specific, files named
`SCUS-94455_<hash>.cht`, header "(Rev 1)" = v1.1 — these are what we ship
and they are correct) and `cheats.zip` (community GameShark codes, files
named `SCUS-94455.cht` with NO hash, header says **v1.0**; the Simulation
one says v1.2). This port targets v1.1. GameShark codes from the cheats DB
are for a different pressing and the addresses do not carry over: the
Arcade "unlock all" codes, asserted every VBlank on v1.1, corrupted the
input path — keyboard and pad both dead, restored the moment they were
switched off (2026-09-02). Rule: a cheat that writes into game memory
ships only after it has been run on the exact disc revision it targets.
The plain Arcade disc currently ships NO unlock cheats for this reason;
the honest route is to reverse-engineer the v1.1 unlock check the way the
Combined Disc ones were.

`mods_dir`, `diagnostics_dir` and `dumps_dir` are validated as plain
directory names — the config loader rejects `/`, `\`, `.` and `..` on
purpose so a config can never point the runtime outside its own folder.
Widening one to `"../../patches"` is not the way to share a folder: it
throws at config load, and because this is a GUI-subsystem build that used
to fail silently, the symptom was "nothing happens when I click the exe".
Share a directory by changing what it is RESOLVED AGAINST in the runtime,
not by putting a path in the name.

## Carried-patch policy

Framework changes travel as ordered patches on pinned upstream commits
(`psxrecomp` `afe9ab29`, `recomp-ui` `4eda6543`) — never as submodule forks
or gitlink moves. Apply order is `LC_ALL=C`: `patches/upstream/*.patch`
first, then `patches/psxrecomp-*.patch`, then `patches/recomp-ui/*.patch`.

**Stack test** — run it after touching any patch:

```sh
git -C psxrecomp worktree add -f --detach /tmp/stacktest afe9ab29
cd /tmp/stacktest && for p in $(LC_ALL=C ls .../patches/upstream/*.patch \
    .../patches/psxrecomp-*.patch); do git apply "$p" || echo "FAIL $p"; done
# `git diff | sort | md5sum` here must equal the same in the psxrecomp tree
# (run `git add -N .` first on both sides: patches q/r ADD files, and an
# untracked file is invisible to `git diff`)
```

Every patch gets a row in `patches/README.md` saying what it does and why.

## Editing local_build.sh

The game folder keeps its own copy of `tools-win/local-build/local_build.sh`
and Setup runs THAT copy; it only refreshes itself from the checkout when
`GT2_LB_VERSION` at the top is higher. Every change to the script must bump
it, or players (and John) keep running the old one — the git-clean fix and
the title-art rip shipped once without the bump and never ran.

## Updating a released config

`tools/merge_runtime_config.py` adds keys a release introduces to a player's
tuned `game.toml` without touching values they set. Two escape hatches:
`--replace SECTION` refreshes a product-owned array-of-tables group
wholesale (presets, featured rows); `--force-key SECTION.KEY` overwrites one
scalar the product owns and has moved (used for `mods_dir`). Without the
right flag, a release that changes layout silently leaves existing installs
behind — they keep working and quietly stop matching the docs.

## Releasing

Public history is the `release` branch (one clean commit per release whose
tree is exactly `main`'s at that moment, made with `git commit-tree
main^{tree} -p release`), pushed by John with `push_update.cmd` from
`D:\Gran Turismo 2 Recompilation\release\` (the versioned copy is
`tools-win/dev/release/`; it reads `..\gt2recomp.bundle`, the game-root bundle
Setup also builds from) — it clones the bundle's `release`,
rebases onto GitHub main, pushes `main` and tags. The dev history on `main`
never goes to GitHub.

**Keep local `release` identical to GitHub main.** push_update.cmd rebases,
so the pushed release commit gets a NEW id; if local `release` is not
already GitHub's history, every release drifts and the tag ends up pointing
at a commit that is not on main ("N commits since this release"). After a
push: `fix_release_tag.cmd <tag>` (re-points the tag at origin/main and writes
`release\github_main.bundle`), then fetch that bundle here and `update-ref
refs/heads/release` to it. Done for 0.3.0; `release` == GitHub main
`51fe002` (the 0.2.0 release commit is `49e7523`). Same for 0.4.0, with no
reconciliation needed: GitHub main was still `51fe002` at push time, so the
rebase was a fast-forward and the release commit kept its id - tag `v0.4.0`
== `6bb16f2`. **Run `git ls-remote <remote>` after any push**: if the tag
and `refs/heads/main` already agree with local `release`, there is nothing
to reconcile and `github_main.bundle` can be ignored. `release` is not
tag-only - an ordinary commit can go on top of it (a docs fix after a
release), and push_update.cmd pushes it to main without creating a tag. `fix_release_tag.cmd`
REQUIRES the tag name: run without one on 0.3.0 day, its old default moved
`v0.2.0` onto the 0.3.0 commit and the tags had to be repaired
(`repair_tags_0.3.0.cmd`). Also: the GitHub release form must only be
published AFTER push_update.cmd, or GitHub creates the tag on the old main.

Release checklist: CHANGELOG dated + Known issues → `gt2_version.h`
(the launcher's footer) → README → `tools/
make_setup_zip.sh` (attach the zip) → release commit on `release` + tag →
`tools/make_bundle.sh` → John: push_update.cmd → GitHub "Draft a new
release" for the tag (John attaches the zip, publishes) → check Actions
"patch stack" is green → walk the fresh-user path from a zip in Downloads.

## Rebuilding a title in the lab

`ninja` with no target in `titles/<t>/build` also builds the non-PGXP
`psx-runtime` (never built there: ~650 generated objects, hours). Build the
executable you run: `ninja Gran_Turismo_2__Simulation__Recompiled_pgxp`
(under a minute after a mod-source change). The build tree carries its own
copy of `mods/packages/` and a `mods/state.toml`: copy the manifest over and
write `[[feature]] package_id/id/enabled` entries there to enable features
for a `PSX_NO_LAUNCHER=1` run. A rebuild also copies `titles/<t>/game.toml`
over `build/game.toml`, which drops runtime-only keys the lab needs
(`fmv_letterbox_rows`, `[widescreen]`, `offer_vulkan`) - re-add them after
each rebuild (the lab keeps a script for it). The Vulkan backend needs
`glslc` + Vulkan headers at configure time (apt: `glslc libvulkan-dev`) and a
driver to run: `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json`
(`mesa-vulkan-drivers`, software) with `renderer = "vulkan"` in
`build/settings.toml`; point `VK_ICD_FILENAMES` at a missing file to test
the no-driver fallback.

## Performance work

Measure before touching anything; `docs/PERFORMANCE.md` has the numbers
and the method. On a player's PC: `Benchmark GT2.cmd` → `gt2_benchmark.txt`
(`runtime cadence` lines: `work guest` vs `pacer` vs GL ms/s says CPU- or
GPU-bound; `dirty insn/s` and `overlay native/interp` say how warm the
native cache is). In the lab: `tools/lab_race_bench.sh` times a fixed 1500
guest frames of the same race from savestate slot 2 (re-save it after any
codegen/ABI change — states carry the tag); the debug server's
`phase_profile` / `phase_hot` give guest-side shares, and
`gdb -p PID -batch -ex "bt 4"` sampled in a loop gives host symbols. The lab
build has `overlay_cache = true`; its shards are compiled by hand:
`python3 psxrecomp/tools/compile_overlays.py --captures
titles/arcade/build/overlay_captures.json --game-toml titles/arcade/game.toml
--recompiler psxrecomp/recompiler/build/psxrecomp-game --runtime-include
psxrecomp/runtime/include --out-dir /tmp/ovcache --compiler gcc --flavor 6
--cps --jobs 2`, then copy `<out>/SCUS-94455` into `titles/arcade/build/cache/`
(rebuild `psxrecomp-game` first whenever a runtime header in the cache tag
changed — the tool refuses a stale recompiler). Changing
`runtime/include/debug_server.h` recompiles every generated file (it is
reached through `psx_runtime.h`); declare new runtime-only symbols in the
.cpp that needs them instead.

## Netplay

Not a GT2Recomp feature and not planned (John, 2026-09-04; possibly some day).
The framework carries netplay and this project inherits only the disc gate -
the `[netplay]` block in each title's `game.toml` (`require_cue`,
`required_tracks`, `required_disc_fp`) - which is a disc-identity check, not
an offered mode. There is no `docs/NETPLAY.md` here despite the comment above
that block pointing at one; it is the framework's doc. So keep netplay out of
player-facing docs and release notes: naming it in a Known issues list
advertises a mode this build does not offer. If it is ever taken up, the one
thing worth knowing from the Vulkan work: the lockstep path needs a CPU-side
VRAM authority that only the software and OpenGL backends provide, so a
netplay session on Vulkan silently falls back to software.

## Performance work, 2026-09-04 (all shipped; see docs/PERFORMANCE.md)

- **Launch disc hash** (patch zb): `mod_runtime_commit()` SHA-256'd the whole
  disc every start for a `disc_sha256` target no GT2 package pins. Now only
  when a package pins one, and cached by size+mtime in
  `mods/disc_sha256.cache`. 4.75 s -> 0.50 s to first guest frame in the lab.
  Found with `gdb -batch -ex "catch syscall read" -ex "ignore 1 400" -ex run
  -ex bt`.
- **Install-time native cache**: `tools/gt2_extract_overlays.py` reads
  `GT2.OVL` (u32 table bytes, then (offset,size) pairs, six gzip streams;
  all load at 0x80010000; entry 0 == play captures minus Silent's 8 patched
  words) and emits captures v2 via extract_generic's helpers; Setup step 9
  compiles them with `compile_overlays.py --flavor 6 --cps`. Lab commands:
  `python3 tools/gt2_extract_overlays.py --game-toml titles/arcade/game.toml
  --recompiler psxrecomp/recompiler/build/psxrecomp-game --out
  /tmp/aot/captures.json`, then the compile line above with that captures
  file (35 min on the lab's 2 cores; run it detached, the tool timeout kills
  it otherwise). Race bench 30fps/100%: cold 36.4 Hz/64% interp; AOT only
  49.5/17%; AOT + one session's play shards 55.0/6%. **Do not feed play
  executed_pcs as hints**: 1599 fragment shards, 872 MB, and SLOWER
  (42.4 Hz/30%) - overlapping variants cost every dispatch a hash.
- **Loading mods scoped to memory-card screens** (patch zc): the
  `memcard_only` boolean on Fast Loading / CD Speed; the gate is
  `memcard_io_sector_count()` changing (6-vblank hold). GT2 card traffic:
  BIOS probe, the boot "Loading Save Data" screen, then nothing through title
  and attract mode - so the gate is exactly that screen (and save/load).
  `[[runtime.mod_option_default]]` in game.toml sets a title default for a
  builtin package's option. Lab: `/tmp/lab_game_toml_extra.sh` re-adds these
  after a rebuild.
- **Skip intro**: `gt2.recomp` package, `mods_gt2_recomp.c`; arms the
  framework's START-injection FMV skip and disarms after 4500 guest vblanks.
  Promoted as the "Intro movie" featured row.
- Launcher window opens in 0.4 s; the loop is `SDL_WaitEventTimeout(16)` so
  it redraws at 60 Hz while idle (a real GPU makes that cheap; low priority).
- **Lab gotchas:** `pkill -f <pattern>` matches the shell running it when the
  same command line also launches the game (the exe name appears in it), so
  the kill and the launch must be separate tool calls; `pkill -x` cannot
  match the exe name (>15 chars). Xvfb started from a tool call gets reaped;
  clear `/tmp/.X79-lock` and restart it with setsid. The debug server's
  `load_transitions` reply is multi-line JSON - read the socket to `]}`.

## Launcher front end (2026-09-04): how it is built

The console-style launcher is three pieces, each generic where it can be:

- **recomp-ui patch 0017** adds `RecompLauncherCGameInfo.console_dashboard`
  + `dashboard_logo_path` / `dashboard_backdrop_path` / `dashboard_accent` /
  `dashboard_footer_text` / `save_summary` and the game-agnostic
  `RecompLauncherCSaveSummary` (hero, stats, bars, badges, tiles, empty
  state). The UI is one block in `launcher_imgui.cpp` above `draw_ui`
  (`draw_console_header/dashboard/settings/footer`, `draw_console_save_panel`,
  `console_menu_item`); `draw_ui` branches at the top so the classic
  dashboard is untouched. Menu rows are `InvisibleButton`s with
  `ImGuiButtonFlags_EnableNav`; the layout containers are `NavFlattened`
  (without that the pad focused the scroll child, not the rows). The model
  reads both cards' summaries in `lm_summarize_save()` next to
  `lm_inspect_memcard()`. Design size 1440x960 (`launcher_ng_capi.c`);
  the platform's fill policy scales the layout to the drawable in both
  directions, so a maximized/fullscreen window grows the UI. Window state
  is `launcher_window.ini` in the exe dir (read in `launcher_platform_open_ex`,
  written in `launcher_platform_close`; `track_restore_rect` keeps the
  windowed rect while maximized/fullscreen). F11 / Alt+Enter toggle
  fullscreen (`model.launcher_fullscreen`, synced to the platform each
  frame). `LNG_FORCE_USABLE_BOUNDS=1280x800` simulates a Deck desktop.
  Never run the patch-regeneration loop without checking `cd` succeeded:
  a failed `cd` once committed recomp-ui's whole working tree as "base"
  (fixed with `git reset --soft 4eda6543 && git reset`).
- **psxrecomp patch zd** is only the hook: `psx_mod_set_launcher_dashboard()`
  (mod_plugins.h) + copy into the GameInfo at both build sites.
- **GT2 side**: `gt2_career.c` (CODEGEN_SETUP_SOURCES, every title) parses
  the card, verifies the CRC and fills the summary; registers the dashboard
  from a constructor. `gcc -DGT2_CAREER_TEST -I recomp-ui/src gt2_career.c`
  builds a checker (`gt2_career <card> <exe dir>`). `gt2_version.h` is the
  footer text - bump it with each release. `tools/rip_gt2_launcher_art.py`
  rips logo/mark/backdrop, `lic_*.png`, `map_<course>.png`, `carlogo/<code>.png`
  and `carinfo.txt` into `assets/img/gt2/` (stdlib only; local_build step
  7, `GT2_LB_VERSION=8`). Arcade course -> crsmap mapping is the
  `ARCADE_COURSES` table there (and `kArcadeTracks` in gt2_career.c); the
  known-uncertain assignments are `test_in2`=Midfield, `parma`=Apricot
  Hill, `new_parmaS`=Red Rock Valley, `sprint2`=High Speed Ring,
  `testline`=Deep Forest, `circuit`=Grand Valley, `highway`=SSR5,
  `shortway`=Clubman - matched by outline shape; fix both tables together
  if a player reports a wrong map.
- **Lab**: `/tmp/launcher_shot.sh <tag> [xdotool keys...]` launches
  `--launcher` under Xvfb :79 and screenshots; `/tmp/rich.mcd` is a
  synthetic save (CRC recomputed) with a car, licences and progress for
  screenshots - swap it into `titles/arcade/saves/card1.mcd` and restore
  the backup after.

## Launcher redesign research (2026-09-04; mockups in D:\...\Claude outputs\launcher-mockup-*.png)

- **Art rippable from the disc** (survey tools + dump in /tmp/gt2art; nothing
  committed): `arcade/arc_topmenu` is a gzip (no suffix) of 12 16-bpp TIMs -
  four 512x120 strips stacking into the 512x480 arcade top-menu screen (GT
  mark, "GRAN TURISMO 2 / THE REAL DRIVING SIMULATOR" wordmark over a night
  race photo, Polyphony credit) - the true-colour logo source. `arcade/
  gt_items.tim` = licence badges S/IA/IB/IC/A/B (4bpp, NO CLUT: tint at
  runtime). `carlogo/<id><v><s>--.tim` = car nameplates, 4bpp+CLUT, <=256x64;
  car id packs 4 chars (alphabet `-0-9a-z`, 6 bits at 24/18/12/6); v n/r/s/t
  = normal/RM/other, s l/m = JP plate large/medium, n/o = export plate
  large/medium (135 cars have export plates). `.carinfoe` (root, "CAR\0",
  u32 count, {u32 id,u16 str_off,u16 flags}) gives names. `crsmap/*.tim.gz`
  96x96 course outlines. `gtmenu/commonpic.dat` = 456 full GT-mode screens
  (GTMP tilemaps; orange #f79400 pills on black is GT2's UI language).
  `gtmenudat.dat` is pre-rendered menu TEXT, not art. GTFS offsets: low 11
  bits = pad bytes in the last sector.
- **Save layout** (offsets from block start, verified on John's card via the
  CRC; GT2SaveEditor by zyzalfors documents them): lang 512; arcade progress
  696 (21 bytes, bits easy1/normal2/hard4); days u32 760; races 768; wins
  772; sum best rankings 776; sum rankings 780; prize u32 788; career
  progress 792 = 124 bytes of nibbles (0 none, 1-6 finish) for 248 events,
  100% = 219; licences at S 5657 / IA 7297 / IB 8937 / IC 10577 / A 12217 /
  B 13857, 10 tests each, stride 164, byte 0 none 1 kid 2 bronze 3 silver
  4 gold; car count u8 15988; cars from 15992, 164 bytes each, u32 car id at
  +0; money u32 32392; current car u8 32396 (255 = none); CRC32 of bytes
  [0,32412) at 32412. Save = one 4-block "GT2 Game File", product code of
  whichever disc saved it (BASCUS-94455GAME / -94488GAME), shared by both
  discs. Cards: saves/card1.mcd, card2.mcd, 128 KB raw.

## Shelved work

- **Trackside Objects Behind Barriers** (2026-09-03): trees/poles/signs hidden
  behind guardrails and chain-link fences by ground-contact rows — framework
  patch p, GT2 mod feature, evidence clip and `docs/RENDERING_QUALITY.md`
  §4d — was built, verified on John's Seattle replay, and then pulled the
  same day (John: more important things to fix first). Everything lives in
  GT2Recomp commit `71d75af` (reverted by the next commit) and psxrecomp dev
  branch `shelved/trackside-behind-barriers` (`e335e572`, on top of the
  `afe9ab29` stack). To bring it back: cherry-pick `71d75af`, restore the
  patch as `psxrecomp-zzzzzzzzzzp-*.patch`, re-verify the stack. Its lab
  tools `tools/lab_ab_frames.py` / `lab_ab_burst.py` (frame-matched A/B
  against a savestate) were kept.
