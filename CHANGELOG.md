# Changelog

## 0.2.0 — multi-disc: build from your own Arcade + Simulation dumps (2026-09-02)

**The GT2 Combined Disc is no longer required.** Setup now builds directly
from the disc dumps people actually own — the Arcade disc, the Simulation
disc, or both — and disc switching is built in. A Combined Disc image still
builds if you drop one in (as a third switchable disc, with its
Combined-only extras), but nothing depends on it anymore.

### Known issues
- **60 FPS is experimental and not right yet.** It runs sluggish and uneven
  on current builds even with the overclock it switches on: the doubled
  simulation rate plus a 325% emulated CPU is more than the native-code cache
  carries until it has warmed up over several sessions, and on many PCs more
  than it carries at all. Original (30 fps) with the Enhanced preset is the
  recommended setup and is a solid 30.
- **Mods and cheats are per disc and each disc needs its own testing.** The
  Arcade and Simulation discs are different programs. Every mod in this
  release was verified on both plain discs (they share the same code for all
  of them). No cheat has been: the published Arcade unlock codes are for the
  v1.0 pressing and corrupt v1.1, so the plain discs ship none, and the
  Cheats page says so. Expect more mods and cheats in later releases as each
  is verified per disc.
- Upgrading from 0.1.x: the enhancement folder is renamed `patches\` →
  `mods\` on the first setup run, with everything in it. Per-title
  `patches\` folders from 0.2 test builds are kept as `patches.pre-shared`
  and can be deleted.

### Multi-disc install
- Every disc image found in the game folder (any file names — discs are
  identified by content: boot serial + track size) is recompiled into its
  own build under `titles\<name>\` (arcade / simulation / combined).
- `Gran Turismo 2 Recompiled.exe` is now a tiny front door that opens the
  disc you used last (`[launcher] active_title` in the shared
  `settings.toml`); pre-0.2 single-build installs migrate automatically
  (captures and cache move under `titles\combined\`; the enhancement tree
  stays at the root, which is now where every disc reads it).
- **Launcher "Disc" row**: pick Arcade / Simulation / Combined; switching
  relaunches straight into that disc's launcher. Titles that aren't built
  show as "(not installed)".
- **In-game disc switch**: F1 → Disc (listed first) → cycle through your
  installed discs, "Switch disc (restarts game)" — quits cleanly (saves
  flushed) and boots the other disc directly, no launcher stop-over, like
  swapping discs on the console. On a multi-disc install that section is
  exactly those two rows; the framework's "mount any image file" and tray
  cycle are not offered, since each build is made from one specific disc.
- **One player configuration for the whole install.** Everything you set in
  the launcher or the F1 menu applies to every disc: `settings.toml`
  (video, audio, controller, hotkeys, BIOS, language), `input.ini` (pad
  mapping), `keybinds.ini` (keyboard), and the enabled-mods list itself —
  tick 60 FPS or widescreen on one disc and it is already on when you switch.
  Safe because each feature carries its own disc target; anything the running
  disc does not have is inert there rather than applied. **Memory cards are
  shared** (`saves\` at the install root) — Arcade's "Load Guest Garage"
  reads your Simulation garage, matching real hardware. Save states, captures
  and the native-code cache are per-disc.
- Verified: the plain Simulation EXE is one instruction away from the
  Combined Disc's (Silent's menu-mode selector); the Arcade EXE shares the
  entry hook and widescreen gate byte-for-byte — the whole enhancement
  stack carries over unchanged.

### Enhancements on every disc
- The enhancement package now targets **both** discs. Verified code-by-code
  against DuckStation's bundled patch database: Silent's 60 FPS, Widescreen
  16:9/21:9, Full detail AI cars, Higher draw distance and 8 MB polygon
  buffers are byte-identical on the Arcade and Simulation discs (the race
  engine overlay loads at the same addresses on both), and our 60 FPS
  addresses match the database's NTSC-U v1.1 variant exactly. Before this, an
  Arcade-disc build had no enhancements at all.
- **Per-disc features** (`[[feature.target]]`): one package can now carry codes
  for several discs of the same game and each disc's menu shows only what is
  real for it. The Combined Disc's arcade unlock cheats are the case in point:
  that disc rebuilds arcade mode and needs its own unlock check patched, and it
  reports the Simulation serial, so they are pinned to its boot-EXE hash.
- **No unlock cheats for the plain Arcade disc — deliberately.** The published
  GameShark codes for it (DuckStation's cheat database) are for the **v1.0**
  pressing; this port runs v1.1, and on v1.1 those addresses hold something
  else. Applied every frame, they corrupted the game's input path — keyboard
  and pad both dead — which is how the mismatch was found. They were removed
  rather than shipped as a guess; the Cheats page stays in place and says so.
  Rule from here on: a cheat that writes into game memory ships only after it
  has been run on the exact disc revision it targets. (Silent's patches — 60
  FPS, widescreen and the rest — come from a different, hash-specific database
  and are the right revision.)
- **CPU Overclock stands on its own, default 200%.** With full-detail AI cars
  and the longer draw distance on, the emulated CPU has real extra work even at
  30 fps — GT2 already dipped with six cars in view on the console — so the
  overclock is part of a good 30 fps setup, not just a 60 FPS accessory.
  Choosing 60 FPS switches it on and raises it to 325 (the figure Silent ships
  with the 60 FPS patch); choosing Original (30 fps) leaves it as it is;
  unticking the overclock cascades 60 FPS off.
- **One-click presets** on the Mods page: **Authentic 1999** turns everything
  off for the game exactly as it shipped; **Enhanced** is the best-running
  setup — geometry correction, widescreen, longer draw distance, full-detail AI
  cars and the 200% overclock at the original 30 fps. 60 FPS and Fast Loading
  are one click away but not part of the preset: 60 costs more of your PC than
  it gives on most hardware, and faster loading is a feel choice a player
  should make for themselves. Every feature stays individually toggleable
  underneath.
- **Frame rate** is a first-class row in the launcher's Display settings and in
  the in-game F1 menu — "Original (30 fps)" or "60 FPS".
- The launcher's mod pages are called **Mods** and **Cheats**, and the folder
  is `mods\`, as upstream names them; an existing `patches\` is renamed on
  update with everything in it, including what you had ticked.

### Setup and saves
- **Setup tells you what it is doing.** The long build step now keeps one live
  line — `Disc 1 of 2 (Arcade): compiling 812 of 1,762 · 46% · about 14 min
  left` — instead of a silent window and thousands of recompiler warnings.
  Full output still goes to `generate.log` / `build.log` per disc.
- **Memory cards are backed up before every session** into `saves/backups`
  (ten deep, `.1` newest). A career is tens of hours and the card is rewritten
  in place on every save; a session that changed nothing is skipped.

### Framework fixes surfaced by the multi-disc work
- **A disc build mounts its own disc.** With settings shared across titles,
  the remembered `[disc] path` was whichever disc ran last, and a relative
  disc path in `game.toml` could fail the launcher's existence check when
  started from a shortcut — either way the launcher substituted the *other*
  disc's image. The Arcade build booting the Simulation disc, the launcher
  opening its first-run setup page instead of Play (which reads as "no input
  works"), and "Disc verification failed" were all this. Each title now
  resolves its declared disc to an absolute path at config load and re-pins
  to it before mounting; only an explicit `--disc` overrides it.
- The F1 disc switch releases the controller (SDL's joystick subsystem, not
  just our handles) before starting the other disc's exe — Windows would not
  hand the same pad to the child, so it came up with no controller.
- `[launcher] active_title` survives the launcher's own settings saves (it
  saved a rebuilt object and dropped every key it did not know about, so the
  root exe fell back to the first installed disc).
- A `game.toml` the loader rejects, and a disc the launcher discards, now say
  so in a message box / on stderr instead of the exe silently vanishing.
- An installed cheat/patch package that doesn't target the running disc is
  now **inert and hidden** (it used to block launch outright via its hidden
  always-on features). Combined-only cheats stay invisible on the plain
  discs; the mod menus only list packages that can target the running
  title.
- POSIX quit hang: `close()` doesn't unblock a Linux thread stuck in
  `accept()`/`recv()`, so every quit hung joining the debug-server thread —
  the sockets are now `shutdown()` first. (The Windows counterpart of this
  bug was fixed in 0.1.1.)
- The F1 menu's disc switch defers its shutdown until the menu's pause loop
  unwinds — running it inside deadlocked against the VBlank-frozen guest
  threads.
- The F1 frame-rate Apply now persists the change before restarting; it was
  flipping the features in memory only, so the game came back at 30 fps.

### Setup / tooling
- **Setup runs from anywhere.** Unzip to Downloads and double-click: if the
  disc images aren't beside the script, a folder picker asks for them, the
  setup files copy themselves into that folder (so updates run from the game
  folder from then on), and setup lists the discs it found and asks before
  starting the long step. Previously it stopped with "No disc image found"
  unless the zip had been extracted into the disc folder itself.
- `setup_and_build.ps1` no longer requires specific disc file names or a
  rename step; `local_build.sh` classifies and builds every disc it finds
  in one run and compiles the new root stub from `gt2_stub.c`.
- `compile_cache.ps1` compiles each installed disc's capture backlog;
  `play_gt2.ps1` understands the chooser-stub layout.
- Per-title build configs live in `titles/<name>/` in the repo (game.toml
  with probe digests + entry hook, seeds, CMake project, runtime config
  template), over one shared mod package tree and one plugin source.
- Re-running setup is incremental again: the long recompile step is skipped
  when its output is already newer than the boot EXE, the seeds and the
  recompiler, so picking up a new release takes minutes rather than another
  full hour per disc.
- Fixed: the install step could abort silently part-way on Linux (an unmatched
  shell glob under `set -e`), leaving a game folder with configs but no exe.
- **Updating no longer leaves new features behind.** The installer still never
  overwrites a `game.toml` you have tuned, but it now merges in the keys a
  release adds instead of dropping a `game.toml.new` beside it that nobody
  reads — so an update that adds a launcher feature actually reaches people
  who already have a config. Your own values are kept untouched; only the
  preset and promoted-row definitions, which are ours rather than settings,
  are refreshed.

## 0.1.1 — quit-hang fix (2026-09-01)

- **Fixed: the game hung on quit (Esc Esc).** The background finisher that
  converts remaining game code after you exit was spawned inheriting every
  inheritable handle — including the debug server's listening socket (Windows
  sockets are inheritable by default) — so shutdown's `closesocket` never took
  effect, its `accept()` never unblocked, and the quit joined forever. The
  finisher now inherits nothing (cmd's own `>>` redirection writes its log)
  and is spawned as the very last step of shutdown, after all sockets are
  closed.
- Docs: front-page README rewritten to a brief install/play/help sheet; the
  GT2 Combined Disc steps are a link to that project instead of a restated
  copy; this file is the detailed dev changelog.

## 0.1.0 — first public release (2026-09-01)

Source release: build it yourself with `setup_and_build.ps1` from your own
GT2 Combined Disc (see the README). No game code is distributed.

### The port
- Gran Turismo 2 (GT2 Combined Disc, NTSC-U base, boot EXE `SCUS_944.88`)
  statically recompiled with PSXRecomp; Arcade and Simulation modes, saves,
  replays, FMVs, both BIOS backends (bundled OpenBIOS or your SCPH-1001 dump).
- Overlay code (`GT2.OVL`) runs through PSXRecomp's capture-and-compile tier:
  captured while you play, compiled to native shards between sessions
  (`Play GT2.cmd` does the top-up; `tools\compile_cache.ps1` does the whole
  backlog at once).
- 8 MB expanded-RAM memory map build (DuckStation "8MB RAM" parity) so the
  polygon-buffer and full-LOD patches work.

### Graphics
- Internal resolution up to 16x; OpenGL (default), Vulkan (experimental) and
  software renderers.
- Display scaling: nearest / bilinear / sharp-bilinear (DuckStation Nearest /
  Bilinear Smooth / Bilinear Sharp); nearest falls back to sharp-bilinear at
  non-integer magnification so distant detail does not shimmer at 4K.
- Crop FMVs: letterbox bands inside the movie frame detected and removed,
  overscan trimmed, pixel aspect preserved — movies fill the window height.
- Texture filtering (nearest / bilinear / 3-point / trilinear) with a
  separate "filter 2D elements" switch; optional FXAA.
- Supersampling resolves through a mip chain instead of point-decimating.
- Present cadence: driver vsync at swap interval k on 120/240 Hz panels.

### PGXP (geometry correction) — matched to DuckStation frame-for-frame
- Sub-pixel vertices, perspective-correct textures, culling correction
  (exact `GTE_NCLIP` semantics), preserved projection precision; the
  DuckStation knob set live in the in-game F1 menu.
- Fixed: SXYP FIFO shadow shift, per-frame projection-table generation,
  shadow lifetime across the double-buffered ordering table, hires-unit
  sample-grid alignment, the textured/mono quad rect fast path bypassing PGXP
  (the trackside wall seams and guardrail wobble), per-quad UV limits with
  DuckStation's max−1 rule.
- Write-up for other projects: `docs/PGXP_LESSONS.md` / `.docx`.

### Enhancements (Patches / Cheats tab; Silent's GT2 code pack as runtime plugins)
- Aspect ratio 16:9 / 16:10 / 21:9 (true wider FOV, HUD unstretched), 60 FPS,
  CPU overclock (disengages during FMVs), higher draw distance, 8 MB polygon
  buffers, full-detail AI cars, Arcade unlock all tracks / cars.

### Runtime / launcher
- Save states (F7), rewind (F8), turbo (Tab), fast boot, performance overlay,
  controller/keyboard rebinding, memory cards as `.mcd`.
- Launching the exe directly is the whole player flow: the runtime finds the
  MSYS2 gcc itself and finishes the native-code backlog in a detached
  background process after you quit (no wrapper script needed).
- Starvation watchdog no longer kills the boot-time BIOS memory-card load.

### Framework
- All PSXRecomp / recomp-ui changes carried as ordered patches on pinned
  upstream commits (`patches/README.md` explains each); CI applies the stack.

### Known issues
- First launch after a build is mostly interpreted until the native cache
  fills; the boot "Loading Save Data" screen is slow (BIOS memory-card
  timing, under investigation); 30 FPS replays / rally ghosts are not
  compatible with the 60 FPS patch; the software renderer is for A/B only.
