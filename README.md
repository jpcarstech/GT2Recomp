# GT2Recomp

*Gran Turismo 2* running natively on your Windows PC — not an emulator, a
[static recompilation](https://github.com/mstan/psxrecomp) built on your own
machine from your own discs. Both game discs, switchable in seconds, up to 4K
and beyond, widescreen, 60 FPS, save states and rewind, DuckStation-grade
PGXP geometry correction. **No game data lives in this repository or its
downloads.**

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
you like). It opens the disc you used last; the settings window's **Disc**
row switches discs, and so does **F1 → Disc → Switch disc** while playing.
The first start opens the settings window — plug in your controller, pick
your resolution, then open **Mods** and press **Enhanced** (widescreen,
geometry correction, longer draw distance, full-detail AI cars, CPU overclock
— the setup that runs best) or **Authentic 1999** (everything off), then hit
Play. Every enhancement stays individually switchable underneath. Out of the
box everything is off: you get the 1999 game, and each enhancement is yours
to turn on. The **Cheats** page lists the codes verified for the disc you
are on — track and car unlocks on the Arcade disc, money, licences and
race completion on the Simulation disc.

Your garage follows you across discs: memory cards are shared, so Arcade's
"Load Guest Garage" reads your Simulation garage exactly like on the real
console.

In game: **F1** settings + disc switch · **F7** save states · **F8** rewind ·
**Tab** turbo · **Alt+Enter** fullscreen · **Esc Esc** quit.

Good to know: the game gets *faster* over your first few sessions — it
quietly converts more of itself to native PC code while you play and for a
little while after you quit.

Have a [GT2 Combined Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc)
image from the fan project? Drop it in the folder too — it builds as a third
switchable disc with its own extras. It's optional; the two plain discs
cover everything else.

## Known issues (0.3.0)

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
- The first sessions after a build run slower (the game is still converting
  itself to native code), and the boot "Loading Save Data" screen takes a
  while.
- Old 30 FPS replays and Rally ghosts don't play back correctly at 60 FPS.

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
