# 60 FPS performance — what costs what, measured (2026-09-03)

The 0.2.0 notes said 60 FPS "runs sluggish and uneven even with the
overclock". This is what it actually is, from two sources: John's PC
(NVIDIA GPU, 120 Hz panel, 16× supersampling, warm native cache, Arcade
disc, a race at 60 FPS + 325%) via `Benchmark GT2.cmd`, and the lab (a
2-core 2.1 GHz Xeon, software GPU, Arcade disc, same race via a savestate).

## The finding

**It is the emulated CPU, not the GPU, and not the interpreter.** In the
race John's main thread sat at 98% guest work with the pacer idle, the
OpenGL side at 0.0 ms/s even at 16× supersampling, and the interpreter at
~25K instructions/s (his cache is warm: 90%+ of overlay dispatches native).
The frame rate was 37–47 Hz. Menus: a clean 60 with half the frame spare.
So at 60 FPS the *native* emulation work per frame — 60 × 3.25 × 33.8 MHz ≈
110 M guest instructions a second, each with cycle accounting, plus GTE,
device servicing and PGXP — is over budget, and every fixed cost on that
path is worth chasing.

## What was found and fixed (all in the carried patches, k–o)

Measured in the lab with `tools/lab_race_bench.sh`: the same 1500 guest
frames of the same race from a savestate, host time taken, 60 FPS + 325%,
warm cache, PGXP off unless stated. Host Hz = VBlanks the host manages per
second (60 = full speed).

| Change | Host Hz | Why |
|---|---|---|
| baseline (0.2.0 code, warm cache) | 38.4 | |
| **native-cache hole** (patch m) | — | The shard compiler failed on GT2's biggest overlay (0x80018000, 44–94 KB, the menu/race code) with `undefined reference to psx_game_text_native_ok`: the emitter's stale-static guard references a host symbol a DLL cannot link. John's `compile_cache.txt` shows it on both discs; the region fell back to per-function "island" shards plus interpreter. Fixed with an `OverlayCallbacks.text_native_ok` forwarder (ABI v22); the whole region now compiles in one shard (940 functions), 15/15 lab regions, no failures. Existing caches are rebuilt over the first sessions. |
| **range-validation memo** (patch l) | ~+13% cold | `dirty_ram_text_native_ok_ranges_from` re-established "no" per interpreted block by a failing memcmp; now remembered per entry with a page-generation stamp. |
| **debug hooks off** (patch n, `[runtime] debug_hot_hooks = false`) | 43.8 | The debug server's per-store fingerprint hashing / frame recorder / write traces and per-block observer are dev tooling; they already went quiet during FMV because they cost. Silenced from boot; `PSX_DEBUG_HOT_HOOKS=1` or the `hot_hooks` command re-arms them. The store chokepoints test the flag before calling. |
| **SPU deadline query** (patch o) | 46.7 | `psx_spu_sample_event_cycles_to_next` snapshotted the whole SPU global state (two 24-voice scans + memset) to read one SPUCNT bit — on every device-deadline recompute. ~10% of the main thread. Reads the register now. |
| store-path call gate (patch n) | 49.8 | see debug hooks |
| **overclock 200 instead of 325** | 57.5 | Host time scales with the overclock whether the game needs the cycles or not (see idle skip below). 60 FPS used to force 325 through a manifest constraint that also switched 60 FPS *off* when the overclock was lowered; decoupled — the launcher now keeps 60 FPS and the player picks the percent. |

Net in the lab: **38.4 → 49.8 Hz at 325% (+30%), 57.5 at 200%.**

## Things measured and rejected

- **idle_skip** (framework fast-forward of RAM-polling wait loops).
  Skips fire in GT2's DrawSync loop (`0x8007C4B8`) and, when the game is
  ahead, its VSync loop (`0x8007D1D0`, PsyQ VSync polling the VBlank
  counter at 0x801F0444). At 30 fps + 100% it gave +6%. At 60 FPS + 325%
  it made the same interval **15% slower** (41.5 → 35.6 Hz), the same with
  the detector restricted to those two PCs: the skipped cycles are cheap
  loop iterations, and the exception/return traffic around the landed
  device events costs more than they save. Off.
- **PGXP** costs ~12% of the frame at 60 FPS (36.4 vs 41.5 Hz, CPU-side
  dataflow shadowing). It is a visual feature the player chooses; the
  Enhanced preset keeps it on. Someone chasing 60 on a slow CPU can turn it
  off on the Mods page.
- **GPU** is not a factor on a real GPU (John: 0.0 ms/s at 16×). The lab's
  software rasteriser is ~6% of its main thread.

## What is left on the table

From a 150-sample stack profile of the final lab build (60 FPS + 325%):
cycle accounting and device servicing (`psx_advance_cycles`, `psx_cyc_*`,
`psx_check_interrupts`, `psx_devices_service_to_now`, DMA/timer deadline
queries) ≈ 17%; the GPUSTAT read at the top of every VSync call (an MMIO
read catches every device up) is what makes `func_8007D19C` hot even when
the loop does not spin; the per-block `debug_server_cyc_observe` call
survives as a call-and-return (~4%) because generated code declares it
itself — removing it means an emitter change and regenerating every title.
The interpreter's remaining share is whatever the native cache has not
captured yet, which shrinks with play.

## Method

- **On a player's PC:** `Benchmark GT2.cmd` in the game folder starts the
  Arcade build with `PSX_RUNTIME_PERF_DIAG=1` and writes `gt2_benchmark.txt`:
  every 5 s a `runtime cadence` line with guest Hz, `work guest` (host ms
  per second in emulation), `pacer` (idle), the GL renderer's own ms/s,
  interpreted instructions/s and overlay native/interp dispatch counts.
  CPU-bound looks like `work guest≈980, pacer≈0, GL≈0`; GPU-bound looks
  like large GL `cpu/tex/draw` numbers with the pacer non-zero.
- **In the lab:** `tools/lab_race_bench.sh` (above). The debug server's
  `phase_profile` (interp / native shard / static EXE / GPU shares, 1 kHz
  sampling) and `phase_hot` (hot guest functions) commands, and a
  poor-man's `gdb -p PID -batch -ex "bt 4"` sampler for host symbols
  (`perf` is not available in the container). Shards for the lab cache are
  compiled by hand from the build's `overlay_captures.json` with
  `psxrecomp/tools/compile_overlays.py` (see CLAUDE.md).
