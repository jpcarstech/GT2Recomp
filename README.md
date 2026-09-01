# GT2Recomp

*Gran Turismo 2* running natively on your Windows PC — not an emulator, a
[static recompilation](https://github.com/mstan/psxrecomp) built on your own
machine from your own discs. Both game discs in one, up to 4K and beyond,
widescreen, 60 FPS, save states and rewind, DuckStation-grade PGXP geometry
correction. **No game data lives in this repository or its downloads.**

## Install

**You need:** a Windows 10/11 PC (64-bit), ~15 GB free space, internet, and
the **GT2 Combined Disc** — the fan-made image that merges your own Arcade and
Simulation disc dumps into one game. Make it first by following the
instructions at
[CookiePLMonster/GT2-Combined-Disc](https://github.com/CookiePLMonster/GT2-Combined-Disc)
(you end up with a ~1 GB `.bin` + a small `.cue`).

1. **Make a game folder** (e.g. `C:\Games\GT2`) and put the combined image
   (`.bin` + `.cue`) in it.
2. **Download `GT2Recomp-setup.zip`** from the
   [latest release](https://github.com/jpcarstech/GT2Recomp/releases/latest)
   and drag its five files into the same folder.
3. Double-click **`Setup GT2.cmd`**. A black window works for 30–60 minutes —
   click **Yes** if Windows asks to allow changes, press **Enter** if it
   offers to rename your image, leave it alone until it prints **DONE**.

Nothing is uploaded anywhere: the game is converted to a PC program entirely
on your machine, from your own discs. Re-run `Setup GT2.cmd` any time to
update (minutes, not an hour). No PS1 BIOS needed — a free one is included
(drop in your own `scph1001.bin` if you prefer the real thing).

## Play

Double-click **`Gran Turismo 2 Recompiled.exe`** (make a desktop shortcut if
you like). The first start opens a settings window — plug in your controller,
pick your resolution and patches (widescreen, 60 FPS, draw distance...), hit
Play.

In game: **F1** graphics menu · **F7** save states · **F8** rewind ·
**Tab** turbo · **Alt+Enter** fullscreen · **Esc Esc** quit.

Good to know: the game gets *faster* over your first few sessions — it
quietly converts more of itself to native PC code while you play and for a
little while after you quit.

## Help

Something not working? Check the
[troubleshooting list](docs/BUILDING.md#troubleshooting) or
[open an issue](https://github.com/jpcarstech/GT2Recomp/issues) with a
screenshot of what you saw. Known quirks: the first sessions after a build
run slower (see above), the boot "Loading Save Data" screen takes a while,
and old 30 FPS replays don't work with the 60 FPS patch.

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
