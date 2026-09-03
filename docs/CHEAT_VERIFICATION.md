# Verifying community cheats on the v1.1 discs — method, results, evidence

DuckStation's `cheats.zip` entries for GT2 are generic (no disc hash) and their
headers say **v1.0** (SCUS-94455) and **v1.2** (SCUS-94488). This port runs
**v1.1**. Most codes are identical between the two files and only one
("Hit/Tap Any AI Driver") is listed per revision — the community never
re-derived them per pressing. Applied to v1.1 the Arcade unlock codes killed
controller input (0.2.0 notes). Rule: a cheat that writes into game memory
ships only after it has been run on the exact disc revision it targets, with
a screenshot of the result.

## The lab (tools/lab.py, labkeys.sh, labshot.py, ramdis.py)

The runtime's debug server (127.0.0.1:4370) gives `read_ram`, `write_ram`
(byte), `screenshot_file`, `frame`, `record_frame`. With the game under Xvfb
(`DISPLAY=:77`, `--renderer software`, `PSX_NO_LAUNCHER=1`) and `xdotool`
for keys (keybinds.ini defaults: Return = Start, x = Cross, s = Circle,
a = Triangle, arrows), the menu flows can be driven and photographed from a
script. Notes: the title needs **Cross**; the arcade disc drops into an
attract replay after ~10 s idle (Start returns to the title); in GT mode
**Circle also confirms** and **Triangle backs out**; give the menus ~1 s
between key presses or they drop inputs. Static work: dump RAM with
`read_ram` and disassemble with `tools/ramdis.py <dump> <start> <end>`.

## The one fact that explains everything: v1.1 = v1.0 + 0x370

Both discs' boot executables keep the save/game state in one structure. On
v1.0 it sits at **0x801C9340**; on v1.1 (and the Combined Disc, which is
v1.1-based) at **0x801C96B0** — 0x370 bytes higher (the v1.1 EXE's init
routine at 0x80010650 hard-codes `lui 0x801D / addiu -0x6950`). Every
community data code for the save therefore lands 0x370 short on v1.1:
credits at 0x801D0FC8 is dead memory (reads 0), the 0x801C93F8 "completion
record" is unrelated memory, and so on. Code-patch codes are a separate
question: the GT-mode overlay (GT2.OVL, streamed over the boot EXE text)
happens to keep the same instruction addresses for the purchase and
race-entry code, while the race overlay does not (the tap-AI site moved
0x54 bytes between v1.0 and v1.2 and is at yet another place on v1.1).

## Arcade disc v1.1 (SCUS-94455) — SHIPPED: Unlock All Tracks / All Cars

The v1.0 "Unlock All ... Tracks" codes write per-mode course COUNTS at
0x800F364E..365A. On v1.1 those counts live at **0x800F36FE / 3700 / 3702 /
3704 / 3706 / 3708 / 370A** (+0xB0), one per (mode, table): 1P road normal /
reverse, time trial ×2, rally, 2P road, 2P rally. They are recomputed on
every Arcade-mode entry by **0x8001D210**, which walks each course table
(entries of 32 bytes: name, display name, hash, requirement class, index,
availability byte at +0x1C) through **0x8001D120** and counts the entries
whose requirement passes **0x8002357C(class)**: class < 0 → always;
otherwise all 10 ranking records of that class (state + 0x1418 +
class·0x668, stride 0xA4, presence byte at +1) must be populated. Reverse
tables also need bit 2 of the per-track beaten-flag array at state + 0xB8
(0x801C9768). The tables are sorted by requirement, so a count is enough.
The list builder **0x800228BC** reads the count on COURSE SELECTION entry
and hands it to the generic list widget at 0x800F3680 (index +0x0A, count
+0x0C).

Those three code sites — 0x8002357C `move a2,a0 / bgez`, 0x8001D1C0
`andi v0,v0,1`, and the 0x801C9768 array — are **byte-identical to the
Combined Disc's arcade mode**, which the existing `gt2.arcadetracks` /
`gt2.arcadecars` plugins already patch (write-if-match, so the match is the
overlay guard). Both features now also target SCUS-94455.

Verified on the v1.1 Arcade disc, fresh save, features on:
counts 3/0/3/0/1/3/1 → **21/21/23/23/9/21/6** (every table full); the
course widget count 3 → 21 and the list runs to "21. Rome-Night"
(`docs/evidence/arcade-v1.1-all-tracks-21-rome-night.jpg`); Class-S car
list 8 cars (baseline, `arcade-v1.1-baseline-class-s.jpg`) → 10 cars
(Aston Martin V8 Vantage, Lister Storm appear). Keyboard input worked
throughout the flow with both features on (the v1.0 codes had killed it).

## Simulation disc v1.1 (SCUS-94488) — SHIPPED: eleven re-derived cheats

Data in `mods/db/gt2recomp/SCUS-94488_v1.1.cht`, executed by gameshark_vm,
each guarded (`A4017A3C 00741823`, a GT-mode menu-overlay word no cheat
touches) so nothing is written while the race overlay — or arcade mode on
the Combined Disc — occupies that memory.

| Cheat | v1.0 code | v1.1 | Verified |
|---|---|---|---|
| A Ton Of Cash | `901D0FC8 05F5E0FF` | `901D1338` (profile 0 = state+0x3C74, credits +0x4014; profile 1 at +0x4028) | HOME shows Cr 99,999,999 (`sim-v1.1-credits-99999999.jpg`) |
| Have All Gold Licenses | 60 × `0400` from 0x801CA758 stride 0xA4 | from **0x801CAAC8** (state+0x1418) | GAME STATUS: 60 gold cups, S badge (`sim-v1.1-game-status-60-gold-complete.jpg`); B list all gold (`sim-v1.1-b-license-all-gold.jpg`) |
| Gold per class (6) | blocks of 10 records, 0x668 apart | Super 0x801CAAC8, I-A 0x801CB130, I-B 0x801CB798, I-C 0x801CBE00, A 0x801CC468, B 0x801CCAD0 | block 5 alone → B list all gold, A list none (class order as the community labels it; the v1.0 I-B/I-C split of 11 + 9 records is corrected to 10 + 10) |
| All Races Completed | 68 × `1111` from 0x801C9458 | from **0x801C97C8** (state+0x118) | GAME STATUS: COMPLETE 111.21% (over 100%, as the code always did) |
| Money Never Decreases | halfword `2400` at 0x80017A42, 0x80017D4A | same sites: `sw v1,0x4014(s1)` / `sw v1,0x4014(s2)` in the GT-mode overlay — the credits store, at the credits offset | through the shipped mod pipeline: credits set to 20,000, Demio (Cr 14,660) bought, balance still 20,000 with the car in the garage (`sim-v1.1-money-never-decreases-demio-bought-20000-left.jpg`). Also proves gameshark_vm's halfword writes take effect on code in overlay-covered text pages |
| Any Car Can Play Any Circuit | `D00148E0 000C / 800148E2 1000` | same site: `1043000C beq v0,v1,+0xC` | instruction match (the same transformation as the purchase patch above, which is play-verified); shipped as A7 |

Not shipped, and why: **Start With $99,000,000+** patches the boot EXE's
new-game init (0x800107A0 `addiu v0,zero,0x2710`), which the GT-mode overlay
overwrites at runtime — redundant with A Ton Of Cash anyway; **Max Cash After
One Race** NOPs `addu v0,s0,v0` at 0x8005E6D8 so the next load reads
0x0000BFBC — a kernel-RAM accident whose v1.0 struct offset cannot be
checked; **Start With All Gold Licenses (Alternate)** turns 0x8005DDB8
`sltiu v0,v0,1` into `sb s0,1(s3)` with unknown registers; **Stop Race
Timer** writes zero halfwords at 0x8002F810 / 0x80046E84, both already zero
in the v1.1 race overlay (the timer code is elsewhere); **Hit/Tap Any AI
Driver**: the v1.1 site is 0x800375DC (`lw v0,0x660(s4)`, v1.0 0x80037590,
v1.2 0x800375E4) but the effect was not play-tested; the **"Both Discs"**
race codes (Quick Win, Nitrous, Auto-Pilot, 2P view, Solid Ghost) key off
0x800A9228 as the pad word and 0x800A99xx as the car struct — on v1.1 that
region reads zero in a race (the raw pad word is 0x801C957A); Silent's
Moon Jump / Nitrous / Low-Rider (in the v1.2 cheats file) carry A7 guards
that do not match the v1.1 race overlay (0x800443D0 = `27AD0018`, guard
expects `06309E70`).

## Where things are

- Arcade menu working block: 0x800F3680 widget, mode at 0x800F36FC, counts
  0x800F36FE..370A. Course tables 0x8005098C (1P road), 0x80050C4C (1P road
  reverse), 0x80050F0C / 0x8005120C (time trial), 0x8005150C (rally),
  0x8005164C (2P road), 0x8005190C (2P rally).
- Raw pad word (active-low, Start = 0xFFF7): 0x801C957A (both discs).
- Car-selection widget: 0x800F0560 (index +0x0A, count +0x0C).
- RAM dumps used for the static work: `/tmp/ram_cs2.bin` (arcade, COURSE
  SELECTION); regenerate with the lab, not committed.
