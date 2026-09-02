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
to turn on.

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

## Known issues (0.2.0)

- **60 FPS is not right yet.** On current builds it runs sluggish and uneven
  even with the CPU overclock it switches on — the doubled simulation rate
  plus a 325% emulated CPU is more than the native-code cache can carry
  until it has warmed up over several sessions, and on many PCs more than
  it can carry at all. Treat it as experimental: **Original (30 fps) with
  the Enhanced preset is the recommended setup**, and it is a solid 30. If
  you try 60, give it a few sessions (let `Play GT2.cmd` finish its compile
  step on exit) before judging it, and turn supersampling down first if it
  is still heavy.
- **Mods and cheats are per disc, and each disc needs its own testing.** The
  Arcade and Simulation discs are different programs; an enhancement or a
  cheat that works on one has to be verified on the other before it is
  offered there. Every mod in this release was checked on both plain discs
  (they turned out to share the same code for all of them). **Cheats have
  not been:** the published unlock codes for the Arcade disc are for the
  v1.0 pressing and corrupt the v1.1 disc this port runs — they were what
  broke controller input in testing — so the plain discs currently ship
  **no cheats**, and the Cheats page says so. The Combined Disc keeps its
  own. Expect more mods and cheats in later releases as each is verified
  per disc; if you know a code that works on v1.1, open an issue.
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
