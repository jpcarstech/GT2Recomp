# DuckStation GameShark code format — the subset this port executes

Source: `cheat-format.txt` in the `duckstation/chtdb` repository (the
official specification for DuckStation's cheat/patch files), condensed to
what `gameshark_vm.c` implements. Every line is `AAAAAAAA VVVV[VVVV]`: the top
byte of the first word is the opcode, the low 24 bits are the address (RAM,
`0x80000000 | addr`), the second word is a 16- or 32-bit value depending on
the opcode.

## Plain writes
| Code | Meaning |
|---|---|
| `30XXXXXX 00YY` | write byte |
| `31` / `32` | byte OR / AND-NOT |
| `80XXXXXX YYYY` | write halfword |
| `81` / `82` | halfword OR / AND-NOT |
| `90XXXXXX YYYYYYYY` | write word |
| `91` / `92` | word OR / AND-NOT |
| `10`/`11`, `20`/`21`, `60`/`61` | halfword/byte/word increment / decrement by value |
| `A5000XXX YYYYYYYY`, `1F000XXX YYYY` | scratchpad word / halfword write |
| `A6XXXXXX YYYYZZZZ` | if halfword == YYYY write ZZZZ |
| `A7XXXXXX YYYYZZZZ` | same, and on DISABLE: if == ZZZZ write YYYY back (restore) |
| `A8XXXXXX YYZZ` | byte version of A7 |
| `F5XXXXXX YYYYZZZZ` | toggle: if == YYYY write ZZZZ; else if == ZZZZ write YYYY |
| `5000CCSS IIII` | slide: repeat the NEXT code (`80` or `30`) CC times, address += SS, value += IIII |

## "Activate next code" conditionals (gate ONE following code)
`D0`..`D3` halfword ==, !=, <, > · `E0`..`E3` byte · `A0`..`A3` word.
On failure DuckStation skips forward past every CONSECUTIVE conditional of
this family and past the first non-conditional after them
(`GetNextNonConditionalInstruction`): a run of these lines is an AND gating
one code. On success, just fall through to the next line.

## Block conditionals ("master codes": gate everything to the terminator)
`C0XXXXXX YYYY` halfword == · `C3`/`C4` byte <, > · `C5`/`C6` halfword <, > ·
`A4XXXXXX YYYYYYYY` word == · `D7` (buttons, below) · `52..` (registers, below).
If the condition fails, execution skips to the matching `00000000 FFFF`
line (or the end of the cheat). `00000000 FFFF` is otherwise a no-op. This
port's VM counts nesting when skipping (an inner block opened inside the
skipped region is skipped whole); Silent's GT2 code is written so both a
nesting and a flat reading behave the same.

## `D7PQRRRR TTYYYYYY` — button block conditional
- `YYYYYY` button mask, DuckStation's bit order (NOT the PS1 SIO order):
  `000001` L2, `000002` R2, `000004` L1, `000008` R1, `000010` △, `000020` ○,
  `000040` ✕, `000080` □, `000100` Select, `000200` L3, `000400` R3,
  `000800` Start, `001000`/`002000`/`004000`/`008000` D-pad up/right/down/left,
  `01`..`08 0000` right-stick as buttons, `10`..`80 0000` left-stick.
- `P`: 0 = all masked buttons pressed, 1 = all released.
- `RRRR` frame count, `Q` how to compare the number of consecutive frames
  the condition has held: 0 = no frame test, 1 = exactly RRRR, **2 = fewer
  than RRRR**, 3/4 per the spec text (unused here).
- `TT`: if non-zero, cheat register TT receives the current hold count every
  frame (0 once released), whether or not the block executes.

**About Q=2.** The chtdb text lists Q=2 as "at least RRRR" and Q=3 as "less
than". Silent's BGM Switch code (`D702003C 02000400`, "tap R3 to switch,
hold to mute") only works if Q=2 means FEWER than 60 frames — with "at least"
a tap does nothing and a hold both mutes and switches. Silent tested his code
in DuckStation, so the implementation, not the prose, is what this VM
follows. Q=1 as "exactly" is confirmed by the HUD toggle code the same way.

## `51` — cheat registers (256 global 32-bit registers, shared by all cheats)
`51 OP YY XX  VVVVVVVV`; width from OP's high nibble (0 = byte, 4 = half,
8 = word), operation from its low nibble:
| low nibble | operation |
|---|---|
| 0 | write register XX to address V |
| 1 | read address V into register XX |
| 2 | write V to the address held in register XX (indirect) |
| 3 | register XX = register YY + V |
| 4 | indirect: mem[register XX] = register YY + V |
| 5 | register XX = V |
| 6 | register XX = mem[register YY + V] (indirect read) |
| 7 | array-of-arrays write (unused here, unimplemented) |
`51C0`..`51CA` register arithmetic/bitwise into register RR, `51D0`..`51D2`
AND/OR/XOR register YY with constant into XX.

## `52` — register block conditionals
`52 OP YY XX  VVVVVVVV`; OP's high nibble picks width and operand kind
(0/4/8 = byte/half/word register vs register; 1/5/9 = register vs constant;
2/6/A = indirect vs indirect or constant; 3/7/B = register vs address value),
low nibble the test: 0 ==, 1 !=, 2 >, 3 >=, 4 <, 5 <=, 6 `& V == V`,
7 `& V != V`, 8 exclusive range, 9 inclusive range, A `& V == reg`,
B `& V != reg`. Block semantics as above.

## What the GT2 patches actually use
`00 30 80 90 A0 A4 A7 C4 D0 D1 D7 E0 F5 51(03,04,05,06,81,83) 52(10,12,13,15,90,91)`.
Anything outside the implemented set makes the VM refuse the whole cheat at
load time with a message naming the opcode, rather than guess.
