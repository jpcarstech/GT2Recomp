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
```

Every patch gets a row in `patches/README.md` saying what it does and why.

## Updating a released config

`tools/merge_runtime_config.py` adds keys a release introduces to a player's
tuned `game.toml` without touching values they set. Two escape hatches:
`--replace SECTION` refreshes a product-owned array-of-tables group
wholesale (presets, featured rows); `--force-key SECTION.KEY` overwrites one
scalar the product owns and has moved (used for `mods_dir`). Without the
right flag, a release that changes layout silently leaves existing installs
behind — they keep working and quietly stop matching the docs.
