# Changelog

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
- Starvation watchdog no longer kills the boot-time BIOS memory-card load.

### Framework
- All PSXRecomp / recomp-ui changes carried as ordered patches on pinned
  upstream commits (`patches/README.md` explains each); CI applies the stack.

### Known issues
- First launch after a build is mostly interpreted until the native cache
  fills; the boot "Loading Save Data" screen is slow (BIOS memory-card
  timing, under investigation); 30 FPS replays / rally ghosts are not
  compatible with the 60 FPS patch; the software renderer is for A/B only.
