# DuckStation patch database entries for GT2 (provenance)

Verbatim copies of the two files this port's enhancements are built from,
taken from DuckStation's `resources/patches.zip` (John's copy of the
DuckStation GitHub build, 2026-09-02; sha256 of the zip:
`5774a2fb691c6727ae0023e1d460f412479db7df92e247193c13f077734c6e2d`).

- `SCUS-94455_B421447B10306C8B.cht` — Gran Turismo 2 (USA) (Arcade Mode) (Rev 1) = v1.1
- `SCUS-94488_6C4C043E1B0B34C6.cht` — Gran Turismo 2 (USA) (Simulation Mode) (Rev 1) = v1.1

These are HASH-SPECIFIC (the suffix is DuckStation's disc hash) and say
"Rev 1" in their header, so they match the v1.1 discs this port targets.
Author: Silent (CookiePLMonster), 60 FPS with asasega.

`tools/cht_to_c.py` turns selected sections of these files into the C tables
in `mods_gt2_silent_codes.h`, executed by `gameshark_vm.c` every VBlank.
The semantics of every opcode come from DuckStation's own specification,
`docs/duckstation-cheat-format.md`.

NOT copied here on purpose: DuckStation's `cheats.zip` entries for these
serials. Those are generic (no hash) and their headers say v1.0 (Arcade) and
v1.2 (Simulation) — the wrong pressings. See CLAUDE.md.
