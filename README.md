# GT2Recomp

*Gran Turismo 2* running natively on your Windows PC — not an emulator, a
[static recompilation](https://github.com/mstan/psxrecomp) built on your own
machine from your own discs. Both game discs, switchable in seconds, up to 4K
and beyond, widescreen, 60 FPS, save states and rewind, DuckStation-grade
PGXP geometry correction, OpenGL or Vulkan. **No game data lives in this
repository or its downloads.**

## Why

The model for this project is *Metal Gear Solid* in the Master Collection:
the original game, intact, and next to it the same game with the picture
and quality-of-life improvements a modern machine allows - so you can play
either, and see the difference. Here that is one switch, **Original /
Enhanced**, on the launcher's main menu. Original is the 1999 game as the
PlayStation drew it, every enhancement off. Enhanced is the same disc at
your monitor's resolution and aspect, with corrected geometry, a longer
draw distance, full-detail AI cars, faster loading and a CPU overclock -
the setup that plays best. Each of those stays individually switchable
underneath, and nothing about the game itself is changed: it is your disc,
recompiled, not a remake.

## Install

**You need:** a Windows 10/11 PC (64-bit) and your own GT2 disc dumps as
`.bin` files — the **Arcade disc**, the **Simulation disc**, or both (both
recommended; you switch discs in the game). Any file names work.

1. **Put your disc image(s) in a folder** (e.g. `C:\Games\GT2`). That
   folder becomes the game folder.
2. **Download `GT2Recomp-setup.zip`** from the
   [latest release](https://github.com/jpcarstech/GT2Recomp/releases/latest)
   and unzip it anywhere.
3. Double-click **`Setup GT2.cmd`**. If your discs aren't beside it, it asks
   you to pick their folder (and copies itself there for next time), lists
   the discs it found, and asks before starting. Then a black window works
   for 30–60 minutes per disc — click **Yes** if Windows asks to allow
   changes, and leave it alone until it prints **DONE**.

Nothing is uploaded anywhere: the game is converted to a PC program entirely
on your machine, from your own discs. Re-run `Setup GT2.cmd` (now in the
game folder) any time to update, or after dropping another disc image in. No PS1 BIOS
needed — a free one is included (drop in your own `scph1001.bin` if you
prefer the real thing).

## Play

Double-click **`Gran Turismo 2 Recompiled.exe`** (make a desktop shortcut if
you like). It opens a launcher built like a console game's front end: the
GT2 mark from your disc up top, a menu on the left — **Start game**,
**Switch disc**, **Settings**, **Mods**, **Cheats**, **Quit** — and your GT
mode career on the right, read from the memory card every time it opens
(current car and nameplate, credits, days, races and wins, career
completion, licences, arcade tracks cleared; L1/R1 or Q/E flips between
the two cards). It works with a pad, the keyboard or the mouse, fills
whatever size you make the window (F11 for fullscreen; it remembers where
you left it). It opens
the disc you used last; **Switch disc** restarts into the other one, and so
does **F1 → Disc → Switch disc** while playing.
The first start: plug in your controller, pick your resolution under
Settings, then pick **Original** or **Enhanced** under *Graphics* at the
foot of the menu (Enhanced: widescreen, geometry correction, longer draw
distance, full-detail AI cars, faster loading, CPU overclock — the setup
that runs best; Original: everything off, the 1999 game), then **Start
game**. The launcher is built for a gamepad first — ▲▼ move, ◀▶ change a
value, ✕ confirms, ○ backs out — and it is new, so expect it to keep
changing for a few releases. Every enhancement stays individually switchable underneath. Out of the
box everything is off: you get the 1999 game, and each enhancement is yours
to turn on. The **Cheats** page lists the codes verified for the disc you
are on — track and car unlocks on the Arcade disc, money, licences and
race completion on the Simulation disc.

Your garage follows you across discs: memory cards are shared, so Arcade's
"Load Guest Garage" reads your Simulation garage exactly like on the real
console.

Settings is a list of sections — Display, Audio, Controllers, Memory
cards, Disc & BIOS, Hotkeys. Display opens on the few rows most people
want — the two picture presets, window size, fullscreen, supersampling and
texture filtering. The rest of the renderer's controls, *Renderer* among
them, are behind **Show advanced settings** at the bottom of that panel.

In game: **F1** settings + disc switch · **F7** save states · **F8** rewind ·
**Tab** turbo · **Alt+Enter** fullscreen · **Esc Esc** quit.

Good to know: Setup converts the game's code to native PC code up front, so
the first launch already runs at full speed; the small remainder (mainly the
code the enhancement patches rewrite) is converted quietly during your first
session and for a little while after you quit.

Have a [GT2 Combined Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc)
image from the fan project? Drop it in the folder too — it builds as a third
switchable disc with its own extras. It's optional; the two plain discs
cover everything else.

## Known issues (0.5.0)

- **Performance work is in progress, on Windows first.** The remaining
  performance problems (60 FPS is CPU-bound, below) are being worked
  through on Windows; other platforms follow, the **Steam Deck**
  specifically — nothing in 0.5.0 has been tried on a Deck yet, and
  [`docs/STEAM_DECK.md`](docs/STEAM_DECK.md) still describes the 0.4.0
  Proton setup.
- **The launcher is new.** Gamepad-first, keyboard and mouse throughout;
  layout, wording and pages will be tweaked over the next releases. A
  screenshot of anything that looks wrong or cannot be reached with a pad
  is the fastest fix.
- **60 FPS is CPU-heavy.** At 60 the emulated PlayStation does a frame's
  work every VBlank at up to 3.25× its real clock, and on many PCs that is
  more emulation work than one core delivers — the frame rate sags in
  races while menus stay at 60. It is the CPU, not the GPU: supersampling
  makes no difference, so leave that alone. What helps: lower the **CPU
  overclock %** on the Mods page (200 or 250 instead of 325 — since 0.3.0
  this no longer switches 60 FPS off), give the native-code cache a few
  sessions to warm up (let `Play GT2.cmd` finish its compile step on
  exit), and if you must, turn PGXP off (about 12% of a 60 fps frame).
  **Original (30 fps) with the Enhanced preset is a solid 30** on
  everything and remains the recommended setup. `Benchmark GT2.cmd`
  writes the numbers to send with a performance report.
- **Cheats are per disc.** The Arcade and Simulation discs are different
  programs, so every mod and cheat is verified on the disc it is offered
  on. The Arcade disc's Cheats page has the track and car unlocks; the
  Simulation disc's has the money, licence and race-completion cheats; the
  Combined Disc keeps its own set. The Simulation cheats change the save
  the game is holding — save your garage first if you care about it. The
  codes that are *not* offered, and why, are in
  [`docs/CHEAT_VERIFICATION.md`](docs/CHEAT_VERIFICATION.md); if you know
  another code that works on v1.1, open an issue.
- **Savestates made on 0.2.0 do not load** on 0.3.0 (the native-code cache
  format changed; states carry its tag). Memory cards and replays are fine.
- Old 30 FPS replays and Rally ghosts don't play back correctly at 60 FPS.
- **Vulkan has not been tried on a real Steam Deck.** The new renderer was
  verified against OpenGL frame for frame on a Linux lab machine with a
  software Vulkan driver, which is not the same as RADV under Proton. If it
  misbehaves there, switch *Renderer* back to OpenGL (it is under *Show
  advanced settings* in Display); a PC with no Vulkan driver falls back on
  its own. See [`docs/STEAM_DECK.md`](docs/STEAM_DECK.md).
- **Edge blending is softer on OpenGL than on Vulkan.** Vulkan does the
  cut-out half but not the blend half yet. Both presets leave it off.

## Help

Something not working? Check the
[troubleshooting list](docs/BUILDING.md#troubleshooting) or
[open an issue](https://github.com/jpcarstech/GT2Recomp/issues) with a
screenshot of what you saw. If the game refuses to start or a disc build
behaves oddly, run **`Diagnose GT2.cmd`** from the game folder and attach the
`gt2_diag.txt` it writes — it captures what the game itself reports.

Not sure which exe is the current build? `Gran Turismo 2 Recompiled.exe` at
the top of the game folder is the only one to start (it opens the disc you
used last; the per-disc exes under `titles\` are what it starts). If the
folder has picked up leftovers from earlier layouts or a second copy of the
game in a subfolder, **`Tidy GT2 folder.cmd`** moves all of it into `_old\`
(nothing is deleted) and offers a rebuild when the installed build is older
than the source it came with.

## For developers

- [`docs/BUILDING.md`](docs/BUILDING.md) — what the build actually does,
  step-by-step builds (Windows checkout + Linux), troubleshooting.
- [`CHANGELOG.md`](CHANGELOG.md) — the detailed dev changelog: every feature
  and fix, per release.
- [`patches/README.md`](patches/README.md) — every framework change this port
  carries, as ordered patches on pinned
  [psxrecomp](https://github.com/mstan/psxrecomp) /
  [recomp-ui](https://github.com/mstan/recomp-ui) commits, each entry
  explaining the bug. CI re-applies the whole stack on every push.
- [`docs/STEAM_DECK.md`](docs/STEAM_DECK.md) — running the Windows build on a
  Steam Deck under Proton, and which launcher settings to pick there.
- [`docs/PGXP_LESSONS.md`](docs/PGXP_LESSONS.md) — how the geometry-correction
  wobble was hunted down and fixed, written for other recompilation and
  emulator projects. [`docs/BRINGUP.md`](docs/BRINGUP.md) is the bring-up log.

## Credits

[PSXRecomp](https://github.com/mstan/psxrecomp) and
[recomp-ui](https://github.com/mstan/recomp-ui) by Matthew Stan (the
recompiler, runtime and launcher) · [GT2 Combined
Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc) and the [GT2 code
pack](https://github.com/CookiePLMonster/Console-Cheat-Codes) by Silent
(CookiePLMonster), UI by Ash_735, 60 FPS research by asasega ·
[DuckStation](https://github.com/stenzek/duckstation) by stenzek (the PGXP
reference this port is matched against) ·
[OpenBIOS](https://github.com/grumpycoders/pcsx-redux) from PCSX-Redux (the
bundled free BIOS; `bios/OpenBIOS.LICENSE`) · Polyphony Digital made the
game — go buy it.

## License

[PolyForm Noncommercial 1.0.0](LICENSE), same as PSXRecomp. Gran Turismo is a
trademark of Sony Interactive Entertainment. No game code, disc data, BIOS or
recompilation output is distributed here — bring your own legally obtained
discs.
