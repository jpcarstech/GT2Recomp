# Changelog

## 0.4.0 — Vulkan renderer, a launcher that fits any screen, a calmer F1 menu (2026-09-04)

### Graphics
- **Crop FMVs no longer pops.** The letterbox-band crop switched on only
  after the first bright movie frame and switched off again through every
  fade to black, so the intro jumped between the uncropped 4:3 frame and the
  cropped picture — for over two seconds on the Polyphony logo and again
  between the logo and the intro. GT2's movies are letterboxed with 24 black
  rows top and bottom; the title config now says so (`[video]
  fmv_letterbox_rows = 24`, framework patch p) and the crop is static from
  the first frame. A detected band can still only make the crop smaller,
  never larger, so nothing is cut that was not black.
- **JINC2 texture filtering** — the filter GT2 players pick on DuckStation
  for car bodies and wheel arches — is a fourth Texture filtering choice in
  the launcher (Nearest → Bilinear → 3-Point (N64) → JINC2) and in the F1
  menu. It is Hyllian's windowed-jinc 2-lobe kernel with anti-ringing,
  ported from DuckStation's shader with its constants, on the same
  cutout/semi-transparency rules as the other modes. 16 taps per pixel:
  measurably heavier on the GPU than bilinear at 9× supersampling.
- **3-Point (N64) is mupen64plus's**: the exact formulation GLideN64 renders
  (the ArthurCarvalho / twinaphex shader from mupen64plus-libretro), with its
  colour-bleeding handling for cut-outs. Side by side
  at 4×: `docs/evidence/render-4x-texture-filters-car.png` and `-wall.png`
  (nearest / bilinear / 3-point / JINC2 on the same frame of John's Seattle
  replay).
- The F1 menu's Texture filtering row no longer collapses 3-Point or JINC2
  to Bilinear when touched.
- **F1 → Advanced PGXP rows now stick across launches** (settings.toml
  `[pgxp]`, applied over the PGXP mod's shipped defaults). **Reset PGXP to
  GT2 defaults** sits at the bottom of the section: it restores the shipped
  values and forgets your edits, so the mod's defaults rule again.
- **Every DuckStation texture filter is now here**: xBR, Scale2x (EPX),
  Scale3x, MMPX, MMPX Enhanced and MMPX Advanced join the list, as
  DuckStation's own shaders (lifted verbatim, three one-line fixes). The
  pixel-art scalers (Scale2x/3x, MMPX) are made for hard-edged 2D art —
  tick **Filter 2D elements** to see what they do to the HUD and fonts;
  on GT2's photographic textures they read close to Nearest. MMPX Advanced
  is a very large shader: expect a pause of a second or two the first time
  it is selected.
- **Edge blending** (Graphics page, under Filter 2D elements): DuckStation's
  edge blending for the filtered modes — cut-out textures (trees, fences,
  crowds) get a soft edge instead of a hard texel outline; off by default
  so nothing changes until you ask. Side by side:
  `docs/evidence/render-4x-texture-edge-blending.png`.
- **FMV chroma smoothing** (Graphics page, under FMV filtering):
  DuckStation's 24-bit chroma smoothing — the video codec stores colour at
  half resolution, so movies show 2×2 colour blocks at any upscale; this
  reconstructs the colour bilinearly and leaves the detail alone. Off by
  default.

- **Vulkan renderer.** The launcher's Renderer row now offers Software,
  OpenGL and Vulkan (`[video] offer_vulkan = true` in every title config;
  an existing game.toml picks the key up on the next Setup). The framework's
  Vulkan backend rasterises on the GPU with the same 1x-4x supersampling,
  PGXP and widescreen as OpenGL. Its present path is a plain blit for now:
  texture filtering beyond bilinear, edge blending, FXAA, the display
  scaling filters, the FMV crop and chroma smoothing are OpenGL-only until
  the next release ports them. Vulkan is loaded at run time, and a machine
  without a Vulkan driver or device falls back to OpenGL with a line in the
  log instead of exiting at start (framework patch w). Pick Vulkan on Steam
  Deck; see `docs/STEAM_DECK.md`.
- **Garbled menu text on Vulkan is fixed** (framework patch za). The options
  and load-game menus drew from stale VRAM because the Vulkan backend threw
  away queued texture uploads whenever the display entered or left 24-bit
  mode - and GT2 uploads its menu font atlas near the end of the intro movie,
  so the atlas never reached the GPU. The OpenGL backend had the identical
  bug and was fixed long ago; Vulkan now flushes those uploads instead of
  dropping them. Measured at the font-atlas page against OpenGL on the same
  boot: 1022 of 1024 texels differed before the fix, none after.
- **Four Vulkan spec violations fixed** (framework patch za). The validation
  layers flagged 21 errors across three rules - a depth/stencil image cleared
  and transitioned without the usage flag that requires, barriers naming only
  the stencil half of a combined depth/stencil format, and a staging buffer
  used for readbacks without the matching usage flag. All are undefined
  behaviour on a stricter driver than the one the lab runs, which is exactly
  what a Steam Deck's driver is. Now zero.
- **Vulkan does the whole texture-filter set** (framework patch y). All
  eleven modes — nearest, bilinear, 3-point, trilinear, JINC2, xBR, Scale2x,
  Scale3x and the three MMPX variants — plus *Filter 2D elements* and edge
  blending's coverage cutout. They are the same shader text the OpenGL
  backend compiles, from the same generated DuckStation blocks, so the two
  renderers cannot drift apart; verified mode by mode from a fixed save
  state, with five of the eleven pixel-identical between backends and the
  rest differing by a handful of pixels of floating-point rounding. Vulkan
  compiles these at build time rather than on first use, so switching to a
  heavy filter does not stall the way it can on OpenGL.
- **Sharp-bilinear, FXAA and bicubic FMV filtering on Vulkan** (framework
  patch y). The present is a plain blit for nearest and bilinear and a
  shader pass for the rest; if that pass cannot be built the renderer keeps
  the blit, so a driver that cannot run it still runs the game. Edge
  blending's second half (blending survivors by coverage through a
  dual-source factor) is the one texture-filter feature still OpenGL-only.
- **The Vulkan present follows the Display settings** (framework patch x).
  Its final blit was pinned to 4:3, so a widescreen or 16:10 aspect came out
  letterboxed wrongly; it now uses the same aspect OpenGL does. *Display
  scaling* picks the filter, and movies get *Crop FMVs*, *FMV filtering* and
  *FMV chroma smoothing* — the crop uses the same static band the OpenGL
  path does, verified frame-stable across a whole intro movie. Still
  OpenGL-only: texture filtering beyond bilinear, edge blending,
  post-processing (FXAA) and sharp-bilinear scaling, which need shader
  passes rather than a blit.

### Launcher
- **Display settings open on six rows, not eighteen** (launcher patch 0016).
  This is a remaster, not an emulator front end: the panel now shows
  *Presets*, *Window size*, *Fullscreen*, *Supersampling* and *Texture
  filtering*, and everything else sits behind a **Show advanced settings**
  checkbox at the bottom. Expanded, the remaining rows are grouped under
  *Picture*, *Movies*, *Window & presentation* and *Rewind* so they read as
  four short lists rather than one wall. *Renderer* is one of the advanced
  rows: the Original and Enhanced presets already set a sensible one and a
  wrong pick falls back to OpenGL by itself, so it is a tuning choice rather
  than a first-run decision — Steam Deck players who want Vulkan tick the
  box first (`docs/STEAM_DECK.md` says so). Nothing was removed and no
  default changed; the toggle is a view state, not a setting, so it is not
  written to `settings.toml` and the launcher always opens on the short
  list.
- **The F1 menu is reorganised** (framework patch z, launcher patch 0014).
  *Resume game* is the top entry and acts on the spot; *Disc* sits under it;
  *Settings* holds Display, Graphics, Audio and Input; the PGXP rows are
  now four levels down at *Settings > Graphics > Advanced > PGXP*, where a
  player who does not know what PGXP is will not meet them by accident (the
  *Advanced* and *System* sections are gone); and *Quit* and *Quit to
  launcher* are the last two rows. The menu shows the trail in its header so
  you can see where you are, and Back walks out one level at a time. The
  header also names the disc you are on ("Arcade disc", "Simulation disc"),
  at every level of the menu, so a pause never leaves you guessing which one
  is running. Quit
  flushes memory cards through the same path as closing the window, and
  quit to launcher restarts the disc you are playing back into the launcher.
- **The launcher's hotkeys table is back to one binding per hotkey**
  (launcher patch 0015) — the *Secondary* column added in 0010 is gone
  along with the column headers. `config.ini`'s `[KeyMap]` still accepts a
  comma-separated list for anyone who wants two keys on one action.

- **The launcher fits every screen now.** Its layout is authored at a fixed
  size and the window was only ever allowed to scale *up* (for high-DPI and
  high-resolution desktops); on anything smaller than that design size the
  window shrank instead and the panels were simply cut off — a Steam Deck's
  1280x800 panel lost most of Player 2 and the memory cards, 1366x768
  laptops the same, and dragging the window small did it on any PC. The UI
  scale is now one continuous number that can go below 1, so the whole
  layout shrinks to fit and nothing is ever clipped; on a 1080p, 1440p or 4K
  desktop the size is exactly what it was. Text is also sharper everywhere
  the scale is not 1: the font is rasterised at the scale it will be drawn
  at instead of being resampled from a fixed atlas (measurably crisper on a
  4K desktop, which is most of what you would notice on the Neo G9).

- **The disc's own title art** on the game card instead of the placeholder
  cartridge: Setup rips the title screen (`GT2.VOL`, `arcade/title_*.tim`)
  from your disc dump with `tools/rip_gt2_title_art.py` — the PS1's own
  transparency rules, written as the launcher's `assets/img/boxart.tga`.
  Nothing is downloaded and nothing ships with the project; no disc, no art.
- **Hotkeys have a second binding.** The Hotkeys panel is a Primary /
  Secondary table; either key triggers the action. Backspace while capturing
  clears a slot. **Switch disc** is a hotkey on multi-disc installs
  (unbound by default) — it does what the Disc row's button does.
- **Hide cursor in fullscreen** (Display, under Fullscreen; on by default):
  the pointer disappears in borderless and exclusive fullscreen and comes
  back for the F1 menu and in a window.
- The launcher sizes itself to the desktop: 1080p is 1×, 1440p 1.33×, 4K
  2× (OS display scaling above 100 % is honoured as before).
- **Presets** at the top of Settings → Display: **Original** (how the
  PlayStation drew it — native resolution, no texture filtering, raw pixels,
  movies as decoded) and **Enhanced** (4× supersampling, bilinear texture
  filtering, FXAA, bilinear scaling, cropped, bicubic, chroma-smoothed
  movies). Picture settings only — the Mods page keeps its own presets.
- The **Screen model** row is gone from Settings (it changed nothing
  visible on GT2).
- **Hotkeys now work on multi-disc installs.** The launcher saved them to
  the shared config.ini but the game read the per-disc copy first, so edits
  never took effect — which is why a Switch disc key did nothing.
- **Filter 2D elements** now defaults off — the HUD, fonts and menu art stay
  pixel-exact unless you tick it.
- Controller hotkeys (Rewind Select+R3, Save states Select+R1, and now
  Switch disc, F1 menu, Fullscreen, Fast-forward, FPS readout) are read
  from `settings.toml [hotkeys]`; the controller page no longer has a
  block for them.
- The **Authentic 1999** preset on the Mods page is now called **Original**,
  and the presets no longer appear on the Cheats page (applying one there
  would have cleared the cheats and switched on enhancements).
- On a multi-disc install the **Disc** row is a button, not a drop-down: it
  names the disc you are running and offers *Switch to <the other disc>*
  (with all three installed it walks through them); discs you do not have
  installed are listed under it.

### Setup
- Setup installs the Vulkan headers and shader compiler
  (`mingw-w64-x86_64-vulkan-headers`, `mingw-w64-x86_64-shaderc`) with the
  rest of the toolchain; without them the Vulkan backend was silently built
  as an inert stub and every Vulkan request fell back to OpenGL.
- Re-running Setup after an update failed with `FAILED TO APPLY` on the
  texture-filter patch: patches that add files left them behind from the
  previous run and `git apply` refused to overwrite them. Setup now clears
  untracked files in the framework checkouts before applying the stack
  (build directories are gitignored and untouched).

### Known issues
- **Vulkan has not run on a real Steam Deck yet.** Everything in this
  release was measured on a Linux lab machine using Mesa's software Vulkan
  driver, which proves the code is correct but says nothing about how RADV
  and Proton behave. If Vulkan misbehaves on a Deck, the Renderer row (under
  *Show advanced settings*) puts you back on OpenGL, and a machine with no
  usable Vulkan driver falls back on its own.
- **Edge blending is still softer on OpenGL.** Vulkan does the coverage
  cutout but not the second half - blending the surviving fragments by
  coverage - which needs a dual-source blend the Vulkan pipelines do not set
  up yet. Both presets leave *Edge blending* off, so this only shows if you
  turn it on yourself.
- **Netplay runs on the software renderer under Vulkan.** The lockstep path
  needs a CPU-side VRAM authority that only the software and OpenGL backends
  provide; a netplay session started on Vulkan quietly uses software.


## 0.3.0 — every Silent patch, cheats on both discs, 60 FPS measured (2026-09-03)

### Enhancements
- **All of Silent's GT2 patches now ship, run VERBATIM from DuckStation's
  patch database.** New on both discs: **Metric Units**, **HUD & Mirror Toggle
  (L3)** — tap to cycle the rear-view mirror, hold to hide the HUD — **Replay
  Cameras in Race (R1)**, and **BGM Switch (R3)** — tap for the next track,
  hold to mute. New on the Simulation disc: **True Endurance** (the Rome 2
  Hours event ends after two real hours, as in the PS2 games) and **Fixed
  Event Generator**. The previously shipped five (60 FPS, widescreen, draw
  distance, full-detail AI, 8 MB buffers) are unchanged and are the same
  versions as the database's current entries — nothing is duplicated.
- How: a small interpreter for DuckStation's GameShark code format
  (`gameshark_vm.c`, semantics from DuckStation's own specification in
  `docs/duckstation-cheat-format.md`) executes the database entries as data.
  `tools/cht_to_c.py` turns the two hash-specific "Rev 1" (= v1.1) files in
  `mods/db/duckstation/` into C tables, refusing at build time any opcode the
  interpreter does not implement. Every one of the four shared patches is
  byte-identical between the Arcade and Simulation database files. The
  interpreter is unit-tested against Silent's real code — `tests/run.sh`
  proves the BGM state machine (tap/hold/wrap/mute), the L3 tap-vs-hold
  detection, the R1 hold and replay restore chain, and that a patch writes
  nothing while its overlay is not resident.
- One framework addition to make the button-driven patches possible:
  `psx_mod_controller_buttons()` — the button word the game itself sees this
  frame, after mapping, keybinds and the analog/digital policy.

### 60 FPS performance — measured, three fixes, one decoupling
- **Measured first** (`docs/PERFORMANCE.md`): on a real PC a 60 FPS race is
  CPU-bound in *native* emulation code — the GPU costs nothing even at 16×
  supersampling, the interpreter is negligible once the native cache is
  warm. So the fixed costs on the emulation path were profiled and cut:
- **The native cache had a hole.** The background shard compiler failed on
  GT2's biggest overlay (the menu/race code at 0x80018000) with an
  unresolved symbol on both discs, leaving that code to per-function
  island shards and the interpreter. Fixed (shard ABI v22 — existing
  caches are rebuilt over the first few sessions, so expect those to be a
  little slower than the last one you played).
- **Dev instrumentation off at play time:** the debug server's per-store
  fingerprinting, frame recorder and per-block observer are silenced from
  boot (`debug_hot_hooks = false`; `PSX_DEBUG_HOT_HOOKS=1` re-arms them),
  and the SPU's per-deadline query no longer snapshots the whole SPU state
  to read one bit. Together with a memo on the static-code validity check:
  **+30% on the lab's 60 FPS race at 325%.**
- **60 FPS no longer forces the 325% overclock.** Choosing 60 FPS still
  switches the CPU overclock on, but the percent is yours — lowering it no
  longer switches 60 FPS off (it did, through a manifest constraint). Host
  time scales with the overclock whether the game needs the cycles or not,
  so if 60 stutters, try 200 or 250 on the Mods page before giving up on
  it; 325 (Silent's figure) remains the safe upper value.
- Measured and rejected: the framework's idle-loop skipping (15% slower at
  60 FPS in GT2's DrawSync/VSync loops, off), PGXP costs ~12% at 60 FPS
  (a visual choice, still in the Enhanced preset).
- `Benchmark GT2.cmd` in the game folder writes a `gt2_benchmark.txt` with
  the runtime's own counters (guest Hz, host time split, interpreter and
  native-cache activity) for a race — the file to send with a performance
  report.
- Savestates from earlier builds do not load on this one (the state carries
  the codegen/ABI tag that changed with the shard fix).
- `Tidy GT2 folder.cmd` (`tools\tidy_game_folder.ps1`): moves the pre-0.2
  single-build leftovers at the game root, any second complete install in a
  subfolder, lab disc chunks and freeze dumps into `_old\`, and the release
  tooling into `release\`, so the root holds one exe to start; says which
  build is installed and offers `Setup GT2.cmd` when `gt2recomp.bundle` is
  newer than it. Never deletes; idempotent.

### F1 menu
- PGXP tuning now lives under an **Advanced** section at the bottom of the
  F1 menu, each row stating the GT2 default, with a **Reset PGXP to GT2
  defaults** row. The shipped configuration is the lab-verified one from the
  PGXP work (geometry, perspective-correct textures, culling correction and
  preserve-projection on; tolerance unlimited; colour correction,
  disable-on-2D, vertex cache, CPU mode and depth buffer off) and is applied
  automatically whenever the PGXP mod is on — nobody has to tune anything.
  The stale `pgxp_tolerance = 0.1` in the runtime config (ignored while the
  mod owns the setting) is gone, with an accurate note in its place.
- **Change disc...** (the hot mount still offered in single-disc installs)
  refuses an image whose serial is not this build's: the Simulation disc
  cannot be mounted into the Arcade build or vice versa. A build is a static
  recompilation of one executable, and cheats activated for one disc would
  keep writing their addresses into the other disc's memory. Multi-disc
  installs never had the row; their disc switch restarts into the other
  build, so no cheat state can cross over.

### Cheats — the plain discs get theirs, verified on v1.1
- **Why the community codes never worked here:** both discs keep the save
  state in one structure that sits at 0x801C9340 on v1.0 and **0x801C96B0
  on v1.1** — 0x370 bytes higher. Every published data code for GT2 was
  written against v1.0, so on v1.1 it lands short: the credits code writes
  dead memory, the Arcade unlock codes hit the input path. Each cheat below
  was re-derived for v1.1 and run in the lab with a screenshot of the result
  (`docs/CHEAT_VERIFICATION.md`, `docs/evidence/`).
- **Arcade disc: Unlock All Tracks / Unlock All Cars.** The v1.1 arcade
  code turned out to be byte-identical to the Combined Disc's arcade mode,
  whose unlock-check patches already shipped; those two features now
  target the Arcade disc too. Every course table fills (the 1P list runs to
  "21. Rome-Night") and the extra class cars appear.
- **Simulation disc, eleven cheats:** A Ton Of Cash, Money Never
  Decreases, Any Car Can Enter Any Race, All Gold Licences and one per
  licence class (Super, I-A, I-B, I-C, A, B), All Races Completed. All
  pure data (`mods/db/gt2recomp/SCUS-94488_v1.1.cht`) for the GameShark
  interpreter, which gained the `50` slide opcode; every one is guarded on a
  GT-mode menu-overlay word so nothing is written mid-race, or in arcade
  mode on the Combined Disc.
- Not shipped, with the reason documented: Start With $99,000,000+, Max
  Cash After One Race, the "alternate" gold code, Stop Race Timer, Hit/Tap
  AI, and the "Both Discs" race codes (their pad-word address is not the
  pad word on v1.1).

### Known issues
- **60 FPS is CPU-heavy.** A 60 FPS race is emulation work on one core at up
  to 3.25× the PlayStation's clock; on many PCs that sags in races while
  menus stay at 60. The GPU is not involved (supersampling makes no
  difference). What helps: a lower **CPU overclock %** on the Mods page
  (200–250 — this no longer switches 60 FPS off), a few sessions for the
  native-code cache to warm (let `Play GT2.cmd` finish its compile step),
  and PGXP off if you must (~12% of a 60 fps frame). Original (30 fps) with
  the Enhanced preset is a solid 30 everywhere. `Benchmark GT2.cmd` writes
  the numbers to send with a performance report.
- **Old 30 fps replays and Rally ghosts** do not play back correctly at
  60 FPS (a property of Silent's patch, as on DuckStation).
- **Cheats are per disc.** The Arcade unlocks are on the Arcade disc's
  Cheats page, the money/licence/race cheats on the Simulation disc's; the
  Combined Disc keeps its own set. The Simulation cheats change the save
  file the game is holding — on a garage you care about, save first. Not
  shipped and why: `docs/CHEAT_VERIFICATION.md`.
- **Savestates from 0.2.0 do not load** on this build (the native-code
  cache ABI changed with the shard fix; the state carries that tag). Memory
  cards and replays are unaffected.
- The first sessions after a build run slower (the native-code cache is
  rebuilt for the new ABI), and the boot "Loading Save Data" screen takes a
  while.
- Upgrading from 0.1.x: the enhancement folder is renamed `patches\` →
  `mods\` on the first setup run; `Tidy GT2 folder.cmd` moves the rest of
  the old layout into `_old\`.

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
