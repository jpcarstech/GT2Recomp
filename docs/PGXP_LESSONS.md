<!-- Generated from PGXP_Lessons_GT2Recomp.docx (pandoc); the .docx is the formatted original. -->

# Getting PGXP Right in a PS1 Static Recompilation

What it took to make Gran Turismo 2 Recompiled match DuckStation, fix by fix

*GT2Recomp project write-up · September 2026 · shared to help other recompilation and emulation projects*

## Who this is for

Anyone bolting sub-pixel geometry correction (PGXP-style) onto a PlayStation renderer that is not DuckStation: static recompilations, new emulator cores, libretro forks. We spent weeks chasing "the wobble" — distant scenery, guardrails, billboards and trees jittering at high internal resolution while DuckStation rendered the same frames rock steady. The final causes were not exotic. Most of them were places where a single vertex quietly took a different path than its neighbour. This document lists every fix that mattered, what it looked like, how we proved it, and the mistakes that cost the most time.

Everything here is verified against DuckStation as the oracle: identical replay, identical frame (matched by the in-game timer), rendered by both, compared pixel-for-pixel at the full internal resolution. Where a DuckStation source reference exists it is named so you can check the exact semantics yourself.

## Contents

## 1. The one-page version

If you only read this page: at high internal resolution every polygon must take exactly one path from GTE projection to rasterizer, and every copy of a shared vertex must resolve to the same sub-pixel value. Every visible defect we fixed was a violation of one of those two rules, plus two presentation-layer problems that looked like geometry problems. The table is the whole story; the rest of the document is the evidence.

| **Symptom (as the player sees it)**                                                                                     | **Actual cause**                                                                                                                                                                                                                           | **Fix**                                                                                                                                                                             |
|-------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Cracks along track polygon edges (blue/black hairlines through the road and skybox), worse at higher scale              | A write to GTE SXYP (reg 15) is a FIFO push on hardware; the PGXP shadows for SXY0..2 were not shifted with it, so the next store failed validation and one corner fell back to its integer position while its neighbour kept the fraction | Shift the shadow FIFO exactly like the registers on every push; treat SXY2 writes as a mirror, not a push                                                                           |
| Correction visibly degraded the longer a race ran; toggling it off/on repaired the picture for a few seconds            | The integer-pixel to sub-pixel projection table was never advanced per frame; first-writer-wins entries accumulated across frames and saturated as ambiguous                                                                               | Advance the table generation once per vblank, renderer-independent                                                                                                                  |
| Seams if shadows never expire; whole-scene wobble if they expire every frame                                            | The game builds frame N+1 while frame N draws (double-buffered ordering table); retirement policy either believed stale provenance or stranded the handoff                                                                                 | Keep current and previous generation live; hard-wipe only on savestate restore. Time-based wipe defaulted off — the store hook already resets a shadow the guest overwrites         |
| Hairline of background at every mesh seam, much worse at 16x than 4x                                                    | The GL sample-grid alignment shift is half a hires pixel, but the tie-avoidance backoff was a constant in native pixels, so it out-scaled the shift it corrected                                                                           | Express the backoff in hires units so it shrinks with the scale; bit-identical at 1x                                                                                                |
| Every thin detail (billboard text, fronds, wires, fence) changed shape as it moved; car texture crawl                   | "Supersampling" was decimation: the present point-sampled 1 of every S² rendered pixels into the window                                                                                                                                    | Generate a mip chain when minifying and sample LINEAR_MIPMAP_LINEAR (a box average at integer ratios)                                                                               |
| Sliver polygons and distant billboards blinking on/off every frame                                                      | A continuous (precise) NCLIP cross product flips sign near zero area as the camera drifts sub-pixel; our rounding also culled polygons DuckStation keeps                                                                                   | Exact DuckStation semantics: precise NCLIP only when all three shadows have validated depth; magnitude in (0.1, 1.0) bumped to ±1; truncating conversion; no home-grown arbitration |
| Vertical see-through lines between trackside wall panels; a panel jumping a whole pixel as the camera pans (THE wobble) | A textured quad whose integer corners formed an axis-aligned rectangle was drawn through a 2D rect fast path that bypassed PGXP entirely, so that panel sat on the native grid while its neighbours were sub-pixel placed                  | Route any quad with PGXP provenance on any corner through the normal triangle path; keep the shortcut only for true 2D quads                                                        |
| Edge texel bleeding at polygon borders at high scale                                                                    | Per-triangle UV limits, and no max−1 back-off for perspective (diagonal) mappings                                                                                                                                                          | DuckStation ComputePolygonUVLimits parity: max−1 on every axis, one limit rectangle per quad                                                                                        |
| Distant objects jitter by one output pixel per frame at 4K only                                                         | Not geometry: a 9x frame (2880 px) point-sampled into a 3840 px window doubles every third column; sub-pixel motion hops between doubled and single columns                                                                                | Sharp-bilinear present at non-integer magnification; true nearest only at integer ratios                                                                                            |
| Rendered frames match DuckStation but motion looks uneven                                                               | Not geometry: driver vsync was disabled on 120 Hz panels and frames were wall-clock paced onto the refresh grid                                                                                                                            | Swap interval k when the panel is an integer multiple of the guest rate                                                                                                             |

## 2. Background: what a recompilation has to reconstruct

The PS1 GPU only ever receives integer screen coordinates. PGXP (Precision Geometry Transform Pipeline, from the PCSX-Redux/Beetle lineage, refined in DuckStation) recovers the sub-pixel positions the GTE computed before it truncated them, by shadowing the values as they flow from the GTE through CPU registers and memory into the display list. An interpreter can hang a shadow off every register and every word of RAM. A static recompilation can do the same in principle, but its generated code is the game, so the shadow has to survive being written by many independent code paths: GTE stores (swc2), register moves (mfc2/mtc2), memory copies (lw/sw), and the game's own arithmetic.

Our implementation keeps an address-keyed dataflow shadow that is validated by value: a shadow is only believed for a vertex if the packed integer word it describes equals the word the GPU is actually about to draw. Provenance for a polygon comes from the DMA linked-list walk, which reports the guest address of every packet word, so a vertex in the display list can be traced back to the exact GTE projection that produced it. This is the same idea as DuckStation's memory-mode PGXP; the surface area where it can go wrong is larger because nothing is interpreted.

Two consequences shaped every fix in this document. First, any place where the renderer draws a polygon without consulting the shadow is a place where a 3D polygon can silently land on the integer grid next to a sub-pixel neighbour. Second, any place where the shadow can be stale, unshifted, or keyed to the wrong generation produces two different sub-pixel answers for the same shared vertex. Both read, on screen, as the same thing: seams that open and close, and objects that hop.

## 3. Method: how we finally found the defects

### 3.1 Build a frame-exact oracle

Screenshots of "a similar moment" are useless for sub-pixel bugs. We built a headless DuckStation (the regtest binary, with a few local patches: an input script that presses controller buttons at given frame numbers, a dump-start frame, memory card path options, and a per-polygon trace of native and precise vertex positions written from the PGXP polygon path in gpu.cpp) and drove it through the game's own menus to the Replay Theater. A replay saved to memory card is deterministic input, so the same replay played in both renderers produces the same game state frame for frame. Frames were aligned by reading the HUD lap timer with a small template-matching OCR, which is exact to the game's 1/30 s update and needs no assumptions about emulator frame counters.

### 3.2 Compare at full internal resolution, per primitive

This is the lesson that cost us the most. Our first comparison pipeline halved every frame to keep files small and used block-based displacement metrics. A 4–7 pixel seam at 9x disappears when halved, and a handful of misplaced wall panels averages away inside 64-pixel blocks. For a week the numbers said "parity to 0.1 px" while the user could see the defect with the naked eye. The tools that broke it open were: a present-synchronised burst capture of the window at full size (the frames the player actually sees), a ring buffer of every prepared triangle with its integer and resolved 16.16 corners and their resolution tier, a per-frame dump of the raw GP0 words (so UVs, CLUT and texture page of the offending quads were known), and finally a one-line log in the renderer of exactly what positions each textured triangle was handed. That last log showed wall quads arriving with precise == native and no perspective weight — the bypass.

### 3.3 Let the human compare frame-matched video

We rendered the same five seconds of the replay from both renderers at exactly 30 fps with no presentation layer in between and asked the user which one wobbled. That single test settled, in two minutes, a question our metrics had been answering wrongly for days: the difference was in the frame content, and it was on the guardrails. When you have a reporter who can see the defect, give them a clean A/B and believe them over your aggregate metric.

## 4. The fixes, in the order they were needed

### 4.1 SXYP FIFO push must shift the shadows

**Symptom.** Cracks along polygon edges of the track and skybox, roughly one native pixel wide (16 px at 16x), at a fixed set of places that moved with the camera.

**Cause.** On hardware a write to GTE data register 15 (SXYP) is a FIFO push: SXY0 ← SXY1 ← SXY2 ← new. The GTE emulation shifted the real registers but left the PGXP shadows for registers 12–14 describing the pre-push words. The next store of SXY0/1/2 to the display list failed value validation, had its X/Y flags stripped, and wrote a flagless shadow — so that corner drew at its integer position while the adjacent face, which reached the same vertex through an unbroken path, kept its fraction. GT2's race code re-injects cached projections through lwc2 into gte12..14 and mtc2 into gte15 around every NCLIP, so this happened thousands of times per second.

**Fix.** Register 15 writes notify the shadow layer once and shift the shadow FIFO exactly like the registers; the lwc2/mtc2 hook refines registers 14/15 with the source's precision without shifting again; a write to register 14 (SXY2) is treated as a mirror of the FIFO tail, not a push (treating it as a push had corrupted SXY0/1 on every lwc2 gte14).

**How we verified it.** Same savestate at the Tahiti grid: mixed triangles (1–2 of 3 corners precise) per 3 s went from ~1600 to 0; shared-edge corners that two faces resolved differently from 702 to 0; teal seam pixels from 3513 to ~0.

**DuckStation reference.** gte.cpp Execute_RTPS / PushScreenXYFIFO and cpu_pgxp.cpp CPU_MTC2 case 15 (PushScreenXYFIFO on the PGXP side).

### 4.2 Advance the projection table every frame

**Symptom.** Correction quality degraded the longer a race ran; toggling the feature repaired the picture for a few seconds.

**Cause.** The table that maps an integer screen position to the sub-pixel projection behind it is only meaningful within one frame. Nothing advanced its generation during normal play, so entries accumulated across frames. It is first-writer-wins and latches "ambiguous" on the first differing value at an occupied pixel, which is inevitable once the camera moves; in-race we measured 11,278 ambiguous rejections against 122 hits over two seconds. The correction had silently stopped applying.

**Fix.** Advance the generation once per vblank from the GPU tick, independent of the renderer backend.

**How we verified it.** Hit/ambiguous counters over a fixed race window; seams that reopened after ~30 s of play no longer do.

### 4.3 Shadow lifetime: neither immortal nor per-frame

**Symptom.** Two opposite failure modes, both observed: seams when shadows never expire; whole-scene wobble when they expire every frame.

**Cause.** A stale entry left at a display-list address frames ago is believed the moment a new vertex lands on its integer pixel (wrong fraction on one copy of a shared corner). But the game builds frame N+1's ordering table while frame N draws, so wiping per frame strands that handoff and everything falls back to integers.

**Fix.** Keep exactly the current and previous generation live; hard-wipe only on savestate restore or rollback. Time-based retirement is off by default because the store hook already resets a shadow when the guest overwrites the word untracked — that is the correct, data-driven invalidation. Where vertex data is reused for more than two frames (car wheel models), any time-based wipe causes wobble.

**How we verified it.** Both defects reproduced and cleared on the same savestates; wheel-model wobble under per-frame wipe measured with the triangle ring.

### 4.4 GL sample-grid alignment in hires units

**Symptom.** A hairline of background along every mesh seam, much worse at 16x than at 4x.

**Cause.** GL samples pixel centres; the PS1 DDA latches at the pixel's top-left corner. The renderer shifts the sample grid by half a hires pixel (0.5/S) to make them agree, then backs edges off by 1/64 to keep them off exact sample centres. That backoff was written in native pixels, so it did not shrink with the shift it corrects: 12.5% of the shift at S=4, 50% at S=16, and larger than the shift at S≥32. Two polygons sharing an edge then rasterised it on opposite sides of the sample grid and neither covered the boundary column.

**Fix.** Express the backoff in hires units. Bit-identical output at S=1.

**How we verified it.** Seam pixel counts at 4x/16x on the same frame; hairlines gone at both.

### 4.5 Supersampling must resolve, not decimate

**Symptom.** Every thin detail (billboard text, palm fronds, wires, fence mesh, the car emblem) changed shape as it moved; read as wobble and texture crawl. Never visible in screenshots, because screenshots read the render target and the defect was in the present.

**Cause.** The present sampled the S× render target straight into the window. With nearest that keeps one of every S² rendered pixels; with plain linear, four. "Supersampling" was decimation.

**Fix.** When the present minifies, generate the mip chain down to the minification level and sample LINEAR_MIPMAP_LINEAR — at an integer ratio that is exactly the box average of the supersamples. 1:1 and magnified presents are untouched.

**How we verified it.** Per-frame changed pixels in the billboard region at 16x→1440 px: 5–9k before, 1–4k after; fronds and text steady.

### 4.6 Culling correction: DuckStation semantics, nothing else

**Symptom.** Distant billboards, trees and guardrail slivers blinking on and off frame to frame ("z-fighting" that vanished up close).

**Cause.** The precise NCLIP cross product is continuous; near-zero-area polygons flip sign as the camera drifts sub-pixel, while the console's integer winding is stable. We also rounded the result (llround), which culled polygons DuckStation keeps.

**Fix.** Exactly what DuckStation does and no more: use precise NCLIP only when all three SXY shadows carry validated depth (GTE_HasPreciseVertices); bump a magnitude in (0.1, 1.0) to ±1.0 before a truncating integer conversion; otherwise the integer winding. Our two home-grown additions — falling back to the integer winding for small areas, and a sign-arbitration rule — were both removed after they suppressed the rescue on crest-of-hill road polygons.

**How we verified it.** Far-triangle appear/vanish churn at idle from ~230 to ~110 per frame (cull-off floor ~70); polygon counts per frame identical to DuckStation's trace once the 8MB-buffer difference was accounted for.

**DuckStation reference.** gte.cpp Execute_NCLIP_PGXP; cpu_pgxp.cpp GTE_HasPreciseVertices (VALID_XYZ gate) and GTE_NCLIP (the 0.1–1.0 bump).

### 4.7 No fast path may bypass PGXP for a polygon with provenance (the wall seams)

**Symptom.** Vertical see-through lines between trackside wall panels; individual panels sitting a fraction of a pixel lower than their neighbours; a panel jumping a whole pixel as the camera pans. The most visible defect of all, and the one the reporter meant by "wobble".

**Cause.** The textured-quad executor had a shortcut: if the quad's integer corners form an axis-aligned rectangle with matching UVs, draw it as a 2D rect. That path was designed for HUD and menu art and never consulted the shadow. A 3D wall panel that happens to land on integer-rectangular corners for a frame was therefore rasterised at native positions while the panels either side were sub-pixel placed: a 0.5–1 px gap at the joint, and a whole-pixel jump when the panel flipped between the two paths on the next frame. A second shortcut did the same for semi-transparent flat quads. The triangle ring showed every corner resolving precisely — because the ring was written by the triangle path the shortcut skipped. Only logging what the rasterizer actually received exposed it.

**Fix.** Before taking either shortcut, check whether any of the quad's four packet words has a PGXP shadow; if so, take the normal triangle path. True 2D quads (no projection provenance) keep the fast path, so the HUD is unchanged.

**How we verified it.** Same replay frame at 9x: wall rendered as one continuous strip identical to DuckStation; the user confirmed the wobble gone in play, including three other artefacts he had circled (a sky streak at a wall end, a gap at the wall base, a glitch near a distant car).

**DuckStation reference.** DuckStation has no equivalent shortcut: every polygon goes through GPU_HW::LoadVertices / the PGXP vertex path.

### 4.8 Texture coordinate limits: max−1, per quad

**Symptom.** Texel bleeding at polygon edges at high scale; a one-texel-wide line of the neighbouring atlas cell along some edges.

**Cause.** We clamped UVs to each triangle's own min/max and only backed the exclusive end off by one texel for axis-aligned 2D mappings. At S\>1 the interpolated UV at a polygon's outer fragments does reach the far texel of a perspective-mapped face; and clamping per triangle rather than per quad can cut one texel along the quad's diagonal.

**Fix.** DuckStation's rule: per polygon, limits are min..max−1 on both axes whenever min ≠ max, computed once over all four corners of a quad and shared by both triangles.

**How we verified it.** Pixel comparison against DuckStation at the wall and fence at 9x.

**DuckStation reference.** gpu_hw.cpp ComputePolygonUVLimits; the UV_LIMITS clamp in gpu_hw_shadergen.cpp; ShouldClampUVs (limits are always on when PGXP is on).

### 4.9 Defaults that are off for a reason

**Symptom.** Skybox tile gaps; seam pinholes; car number decals dropping out.

**Cause.** Three features that sound like improvements make things worse by default: the vertex cache (screen-position-keyed fallback) corrects 2D background tiles that share a pixel with cached 3D projections; the depth buffer produces seam pinholes (200 vs 17 on an identical frame) and drops coplanar overlays; and "completion" heuristics that borrow a sub-pixel position from a table entry at the same pixel move CPU-authored corners by fractions unrelated to the polygon.

**Fix.** Ship DuckStation's defaults: vertex cache off, depth buffer off, tolerance unlimited, perspective-correct textures on, culling correction on, colour correction off. Remove or disable every non-DuckStation heuristic (see section 5).

**How we verified it.** Each toggled on an identical frame with pixel counts.

**DuckStation reference.** DuckStation settings defaults; the tooltips in its PGXP tab describe the vertex cache as inaccurate for the same reason.

### 4.10 Two presentation problems that looked like geometry problems

**Symptom.** Distant objects jittering by one output pixel per frame — only at 4K; and motion that felt uneven although every rendered frame matched DuckStation.

**Cause.** A 9x scene (2880 px wide) point-sampled into a 3840 px window is a 1.333:1 nearest magnification: every third source column is doubled, and anything moving by sub-source-pixel amounts hops between doubled and single columns. DuckStation never shows this because its display scaling is bilinear regardless of the texture filter. Separately, on a 120 Hz panel the runtime dropped driver vsync (it only accepted ~60 Hz) and paced 30 fps content onto the refresh grid by wall clock.

**Fix.** At non-integer magnification with nearest selected, use a sharp-bilinear present (flat pixel interiors, blend confined to one output pixel); keep true nearest at integer ratios; expose Nearest / Bilinear / Sharp as a user setting like DuckStation. Let the swap interval own the cadence when the panel is an integer multiple of the guest rate.

**How we verified it.** Frame captures of the window (not the render target) before and after; per-present timestamps.

## 5. What did not help (and cost time)

We list these because other projects will be tempted by the same ideas. Every one of them was a plausible mitigation for a symptom whose real cause was elsewhere, and each one added its own artefacts.

- **Present-time crack fill (gap fill).** Built to paint over the seams that were really the SXYP FIFO bug. Once that was fixed it only had false positives: it rewrote ~8% of pixels at a race frame — fronds, sign faces, posts, wires — and the set changed every frame. That is wobble. Default off, then removed from the user surface.

- **Sub-pixel dilation of precise triangles.** Hides cracks by overlapping neighbours; blurs silhouettes and never addressed why two copies of a vertex disagreed.

- **"Completion" of untracked corners from the projection table.** Borrowing a sub-pixel value recorded at the same integer pixel gives a CPU-authored corner a fraction unrelated to its polygon. No visible improvement in A/B; removed from defaults.

- **Home-grown NCLIP arbitration.** Any rule beyond DuckStation's exact semantics suppressed the culling rescue somewhere (crest-of-hill road polygons dropped out, sea visible through the track).

- **Tolerance tuning.** The geometry tolerance moved no defect we had; the defects were path and provenance bugs, not out-of-range corrections.

- **Frame-pacing and input-jitter hypotheses.** Real issues in their own right, but a 60 Hz test and a frame-content A/B showed they were not the wobble. Fix presentation problems, but prove the frame content first.

- **Half-resolution comparison pipelines and block metrics.** They reported parity while the defect was plainly visible. Compare at full internal resolution and per primitive.

## 6. A checklist for your renderer

1.  Enumerate every code path that emits a polygon to the rasterizer. For each, confirm it consults the PGXP shadow or is provably 2D (no projection provenance). Rect and sprite fast paths for quads are the classic leak.

2.  Model the GTE SXY FIFO exactly: register 15 writes push; register 14 writes mirror; shadows shift with the registers. Validate every shadow against the actual packed word before believing it.

3.  Give the projection table (integer pixel → sub-pixel) a per-frame generation and keep the previous generation alive for double-buffered display lists.

4.  Never retire shadows on a timer if your store hook already resets them when the guest overwrites the word.

5.  Keep every edge-avoidance epsilon in hires units so it scales with the internal resolution.

6.  When the present minifies, resolve the supersamples (mip chain / box average). When it magnifies by a non-integer factor, do not point-sample.

7.  Copy DuckStation's NCLIP semantics literally: VALID_XYZ gate, (0.1, 1.0) bump, truncation. Do not add arbitration.

8.  Copy DuckStation's UV limits literally: max−1 per axis whenever min ≠ max, one rectangle per quad, clamp in the fragment shader before the texture window.

9.  Ship DuckStation's defaults (vertex cache off, depth buffer off, tolerance unlimited) and give users its knob set — not an invented one.

10. Build a frame-exact oracle: headless DuckStation, scripted input, a saved replay, OCR the game's own timer, compare at full internal resolution, log what the rasterizer receives per triangle, and when in doubt hand the reporter two frame-matched videos.

## 7. Appendix: tools we ended up needing

All of these are small; none took more than an afternoon, and each one paid for itself the same day. Names are ours; the ideas are portable.

- **Headless DuckStation regtest** with an input script (frame ranges → controller mask), a dump-start frame, memory-card path options, and a PGXP polygon trace (native x/y, precise x/y, w, valid flag per vertex) written from the polygon command handler.

- **HUD timer OCR** (template matching on the game's own digits) to align frames between emulators without trusting frame counters.

- **framerec** — present-synchronised capture of the next N frames from the back buffer right before the swap, at full window size, optionally box-downsampled.

- **Triangle ring** — every prepared triangle's integer corners, resolved 16.16 corners, resolution tier per corner, projection depth, and whether perspective UVs were armed; dumped to CSV over a debug socket.

- **GP0 frame dump** — the raw command words of every primitive in a frame with their guest source address, so UVs, CLUT and texture page of a suspect polygon are known.

- **Rasterizer-side vertex log** — one line per textured triangle with the positions the GPU backend actually received. The single most decisive tool: it shows bypasses that no upstream ring can see.

- **Live knobs** — every PGXP mechanism flippable over a debug socket and from an in-game menu, so a reporter can A/B one mechanism at a time by eye without rebuilding.

*GT2Recomp is a static recompilation of Gran Turismo 2 (SCUS-94488, Combined disc) on the psxrecomp framework. The fixes described here are carried as individual, documented patches against the framework and are intended for upstreaming. Questions and corrections welcome.*
