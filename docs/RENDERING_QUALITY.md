# Rendering quality beyond PGXP — what the PS1 does, what is fixed, what is left, what to do next (2026-09-03)

Question asked: how PS1 3D rendering, PGXP and perspective-correct
texturing work, what still makes geometry and textures wobble or swim in
GT2Recomp, and the best course of action that is not "render at 16×".

Short answer: **GT2's geometry is already at the ceiling of what PGXP can
do** — in a race 97.3% of triangles resolve fully sub-pixel with depth, 0%
are mixed, and the 2.7% that don't are HUD/2D quads (measured below; CPU
mode does not move it). What remains, and what the eye reads as "wobble"
and "swimming", is **texture presentation**: per-polygon bilinear clamping
that draws a tile grid on the road, minification aliasing on grandstands
and far scenery because PS1 textures have no mip chain, and the smear of a
16-texel-wide asphalt texture magnified across a 4K screen. Those are the
targets. Ranked plan at the end.

## 1. How the PlayStation renders 3D

Facts from the hardware documentation ([psx-spx GTE](https://psx-spx.consoledev.net/geometrytransformationenginegte/)):

- **Fixed point everywhere.** The GTE rotates a 16-bit integer vertex by a
  1.3.12 fixed-point matrix (12 fraction bits, ±8 range) into 32-bit
  accumulators, then clamps to 16-bit IR registers. There is no FPU.
- **Projection truncates.** `SX = (H*0x20000/SZ3 + 1)/2 * IR1 + OFX`, then
  `SX2 = MAC0 / 0x10000` — the sub-pixel fraction is thrown away; screen
  coordinates are integers saturated to −1024..1023. The 1/SZ term comes
  from an unsigned Newton-Raphson approximation with a 257-entry table,
  not an exact division.
- **The GPU only sees integers.** Every polygon reaches the rasteriser with
  integer corners and integer 8-bit texture coordinates; the DDA fills
  from the top-left corner. A vertex that moves less than a pixel between
  frames does not move at all, then jumps a whole pixel — that is the
  wobble.
- **Affine texture mapping.** UVs interpolate linearly in screen space
  with no 1/W term, so a receding quad's texture bends toward its
  diagonal — the warping. Games subdivide big polygons (GT2 tiles its
  road) to hide it.
- **No Z-buffer.** Polygons go into an ordering table by one depth value
  per primitive and are drawn back to front; nothing prevents two
  polygons at similar depth from swapping order frame to frame.
- **15-bit colour, dithered.** Gouraud shading interpolates at 5 bits per
  channel; the dither pattern hides the banding at 320×240.

## 2. What PGXP does, and where its reach ends

PGXP (Precision Geometry Transform Pipeline, iCatButler; refined in Beetle
and DuckStation — [Libretro's introduction](https://www.libretro.com/index.php/mednafenbeetle-psx-pgxp-arrives/), [DuckStation's option texts](https://github.com/stenzek/duckstation/blob/master/src/duckstation-qt/graphicssettingswidget.cpp), [DuckStation's engine](https://raw.githubusercontent.com/stenzek/duckstation/master/src/core/cpu_pgxp.cpp))
shadows every GTE register, CPU register and word of RAM with the
pre-truncation float position `{x, y, z}` plus validity flags, follows it
through the instructions games use to move a vertex into a display list
(swc2/mfc2, lw/sw, lh/sh, and in **CPU mode** the ALU: add/sub, and/or,
shifts, mult/div), and validates a shadow against the exact integer word
it claims to describe before believing it. Then:

- **Geometry correction**: the rasteriser gets the float position instead
  of the integer — the wobble is gone for every vertex the shadow reached.
- **Perspective-correct textures / colours**: the shadow carries the
  projected depth, so UVs (and optionally colours) interpolate with 1/W.
- **Culling correction**: NCLIP recomputed from the precise positions, with
  the (0.1, 1.0) → ±1 bump so a sliver is not culled by rounding.
- **Depth buffer** (off by default): tests pixels against PGXP depth to
  reduce ordering-table Z-fighting — and drops coplanar overlays.
- **Vertex cache** (off): a screen-position-keyed fallback, "inaccurate"
  per DuckStation's own text because position is not provenance.
- **Preserve projection precision** (on): keeps precision in
  post-projection values.

What it cannot fix: a vertex the shadow never reaches (built by the CPU
from integers with no projection provenance), and — fundamentally —
everything upstream of RTPS. The game's world is 16-bit integer vertices
rotated by 4096-step matrices; PGXP restores the fraction that the
projection threw away but cannot invent precision the game never had.
How much does that matter? A matrix element tick is 1/4096; at the
PS1's typical focal length (H ≈ 300 px) a full-rotation error of one
tick moves a point at any distance by about H/4096 ≈ **0.07 px**. The
integer world is at millimetre-ish scale. So upstream quantisation is
below one output pixel even at 4K: once PGXP resolves a vertex, its motion
is as smooth as the game's own logic. A recompilation *could* carry float
precision through the game's matrix pipeline (the emitter already hooks
every ALU op), but the measurement says there is nothing there to win.

## 3. Where GT2Recomp stands — measured

`docs/PGXP_LESSONS.md` is the record of reaching DuckStation parity (ten
fixes, each verified pixel-for-pixel against a frame-exact DuckStation
oracle). Today's census, from the runtime's triangle ring during a race
on the Arcade disc while driving (`pgxp_tris`, 8192 consecutive
triangles):

| | CPU mode off (shipped) | CPU mode on |
|---|---|---|
| triangles with all 3 corners precise + depth | **97.3%** | 95.4% |
| mixed (1–2 precise corners — the seam-maker) | **0.0%** | 0.0% |
| no precise corner | 2.7% | 4.6% |
| what the unresolved ones are | 0x2A semi-transparent flat quads, 0x38/0x28 flat quads: the HUD, the map, the shadow blobs — CPU-authored 2D | + 80 value mismatches CPU mode introduces |
| perspective-correct UVs armed | every textured triangle (0x2C/0x3C/0x24/0x34) | same |

So: CPU mode is not a lever for GT2 (it is for games that repack vertices
with ALU ops; GT2's race renderer stores GTE output straight into the
display list). Nothing is mixed. Geometry is done.

## 4. What is actually left — with pictures

Frames from the lab's GL renderer at 4× internal resolution, PGXP on
(`docs/evidence/render-4x-*.jpg`, captured with the runtime's
present-synchronised `framerec`):

1. **The road is a patchwork under bilinear filtering**
   (`render-4x-road-bilinear-tile-seams.jpg`). Every road quad shows a
   brightness step at its border — a tile grid. Cause: texture filtering
   is clamped to each polygon's own UV rectangle (DuckStation's max−1
   rule, adopted for parity, section 4.8 of the lessons) so the bilinear
   footprint cannot cross a polygon edge; at the border the last texel is
   duplicated and the neighbour tile starts from its own first texel. On
   the console there is no filtering, so no seam; with `nearest`
   (`render-4x-road-nearest.jpg`) the seam disappears — and the road
   becomes a field of wide, flat texel blocks, because GT2's asphalt is a
   coarse, strongly anisotropic texture (texels far wider than tall on
   screen). This is what "the road swims" is: a grid that moves with the
   tiles, on top of a 16-texel-wide texture magnified across a 4K frame.
2. **Grandstands and far scenery alias** (`render-4x-wall-grandstand.jpg`).
   The crowd checker in the distance is sampled below its texel rate. PS1
   textures are CLUT-indexed regions of VRAM with no mip chain; the
   runtime's `trilinear` mode approximates one level with a 2-texel tent,
   and 16× supersampling with the mip resolve at present hides the rest by
   brute force. In motion, without that, it shimmers — the other half of
   what a player calls wobble.
3. **Polygon edges** are anti-aliased only by supersampling. DuckStation's
   MSAA option exists precisely because it gives edge quality "with lower
   performance requirement" than SSAA. Not a CPU concern on John's PC
   (the GL side costs 0 ms/s there), but it is the honest replacement for
   16× on smaller GPUs.
4. **What is fine already:** the hires FBO is RGBA8, Gouraud interpolates at
   8 bits and nothing dithers — that is DuckStation's "True Color" already;
   walls and billboards are seam-free and perspective-correct; UV limits
   stop atlas bleeding; the present resolves supersamples properly.
5. **Ordering-table flicker** (cars vs. guardrails, shadows): not measured
   in this pass. The PGXP depth buffer is the tool and the lessons record
   why it is off (pinholes 200 vs 17 on one frame, decals dropped).

## 4b. The chase-camera / Seattle / cornering case — measured

John's pointer: the wobble is more pronounced in the 3rd-person camera,
easiest to see on city tracks (Seattle) and around corners. Reproduced in
the lab on Seattle Circuit in the chase view, driving from the grid into
the first corner with the camera swinging (GL renderer at 4×, PGXP on,
151 frames of the triangle ring, 377,284 triangles; frames in
`docs/evidence/`… the `frec5` burst):

| | Seattle, chase cam, cornering |
|---|---|
| triangles with all 3 corners precise + depth | **96.9%** |
| mixed | **0.0%** |
| none | 3.1% — again only 0x2A/0x28/0x38 flat quads (shadows, HUD) and 0x2E semi-transparent textured quads (11 per frame: HUD/mirror art) |
| large near polygons subdivided? | No: the nearest textured triangles are 94–412 px wide at native resolution — GT2 does not re-tessellate near geometry, so there is no split-point UV rounding to jump |
| car body UVs frame to frame (straight, chase view) | constant: 638 of 639 matched corners unchanged — no per-frame reflection UV recomputation on the body |

So the chase view does not put any vertex on a worse path than the
bumper view, and the car's own texture coordinates do not move. What *is*
different in the chase view, from the frames: the composition. A large
near object (the car) sits still on screen while everything behind it
streams past, and Seattle's roadside is one big magnified textured quad
after another (elevated highway, walls, buildings) — the surfaces where
the bilinear tile seams (item 1) and texel-scale magnification are most
visible, sweeping across the screen as the camera yaws through a corner.
Two other things are worth separating before touching the renderer:

- **Frame delivery.** John's benchmark showed 37–47 Hz in a 60 FPS race:
  frames arriving unevenly against a moving background is judder, and the
  chase composition is the most judder-sensitive there is. Retest after
  the performance bundle, and compare 30 fps vs 60 in the same corner.
- **Game-side camera motion.** The chase camera is the game's own
  fixed-point filter; anything it does, DuckStation shows too. The
  frame-exact oracle from the lessons (a saved replay of this corner,
  both renderers, frames matched by the lap timer, compared at full
  internal resolution) is the way to know whether anything remains that
  DuckStation does not have.

Not a bug: the beige strip across the bottom of the chase view on the
grid is the painted grid box under the car.

## 4c. John's own replay — is any vertex jitter left with PGXP on? (measured)

John saved a savestate on his PC: Seattle Circuit, race replay, chase
camera, RUF CTR 2, starting 3 s into lap 1. It loads in the lab unchanged
(same codegen/ABI tag), and a replay is deterministic input, so the same
guest frames can be captured as often as needed. `tools/wobble_census.py`
turns the runtime's triangle ring into a jitter measurement:

- every textured 3D triangle is tracked across three consecutive guest
  frames (same command word, nearest centroid, same shape; GT2's alternate
  frames sit 240 px lower in VRAM and are normalised);
- for each corner the second difference of its screen path,
  `d2 = (p[n+1]−p[n]) − (p[n]−p[n−1])`, is taken twice: on the integer
  coordinates the GPU received (what the console / PGXP-off draws) and on
  the PGXP-resolved coordinates (what we and DuckStation draw);
- the real camera motion is removed by subtracting the median `d2` of the
  corner's 24-px screen cell, so what is left is per-vertex jitter;
- corners whose *integer* path accelerates by more than 3 px in one frame
  are tracker mismatches (a fence post matched to its neighbour) and are
  dropped from both sides alike.

Two windows, 60 FPS, 4× GL, PGXP on: the opening straight (245 frames) and
the first corner with the camera swinging (218 frames). Corners of triangles
at least 16 px across — the geometry anyone looks at:

| local jitter residual, native px | straight: integer | straight: PGXP | corner: integer | corner: PGXP |
|---|---|---|---|---|
| median | 0.00 | **0.008** | 1.00 | **0.021** |
| 90th percentile | 1.00 | **0.08** | 1.41 | **0.22** |
| 99th percentile | 2.00 | 0.33 | 2.24 | 0.74 |
| corners moving > 0.5 px off their smooth path | 44% | **0.3%** | 52% | **2.5%** |

So: on the console (and with PGXP off) half of all visible vertices hop by
a pixel or more every frame — the wobble. With PGXP on, on John's own
replay, in the chase camera, through the corner, the residual is a fiftieth
of a pixel typically and a fifth of a pixel at the 90th percentile — and
the worst remaining cases are real motion (an AI car decelerating past the
camera), not snapping. The camera also moves *every* frame at 60 FPS
(median vertex velocity 1.5–2.9 px/frame with no alternate-frame stalls),
so the 60 FPS patch is not stepping the chase camera at 30 Hz.

That closes the geometry question for this scene: whatever John sees
wobbling in the chase view is not vertex position jitter in our renderer.
The candidates that remain are the ones in section 4 (texture-side
sampling: tile seams, magnified texels crawling under nearest filtering at
16×, minification aliasing) and frame delivery on his display (section 4b).
`docs/evidence/seattle-chase-ab/` holds a frame-matched PGXP on/off clip
(`seattle-chase-pgxp-ab-halfspeed.mp4`, 77 guest frames at 4×, the
approach to the underpass corner, aligned by the HUD timer) and a still,
for anyone who wants to look rather than read.

**The utility poles over the left guardrail at the replay's start** (John's
second pointer) are not a draw-order fault of ours. From the triangle ring
on that frame: the pole quad (`0x2C434347`, 39×57 px, GTE depth 7588) is
*nearer* than the fence/guardrail polygons it overlaps (depth 8600 at the
pole's column, 10200–16266 along the segment), so the console's ordering
table draws it last too. Switching the PGXP depth buffer on — a true
per-pixel depth test — leaves the pole exactly where it is
(`left-poles-depthbuffer-off-on.jpg`); only the "Loaded slot" OSD and a
few far pixels change. The pole model stands on the shoulder in front of
the rail in the track data; DuckStation and the PlayStation draw it there
as well. A DuckStation side-by-side of the same spot would be the
confirmation.

## 5. The course of action — ranked, no brute force

| # | Action | What it fixes | Cost | Risk | Verdict |
|---|---|---|---|---|---|
| 1 | **Seam-aware UV limits.** Widen a polygon's clamp rectangle by one texel on a side when the texel beyond it lies inside the same texture page/window *and* is not the edge of the texture window (i.e. it is the adjacent road tile's first texel in a continuous strip, not another atlas cell). Keep DuckStation's rule for everything else. | The road tile grid (item 1) under bilinear, i.e. the most visible remaining artefact. | Small: one function in the GL renderer's UV-limit computation, a debug knob, an A/B on the road frames above with a seam-pixel count at tile borders (the lessons' method). | Atlas bleed where two unrelated textures abut with no padding — measurable, and the knob stays per-frame testable. | **Do first.** |
| 2 | **Mipmapped, anisotropic texture sampling.** Decode (texture page, CLUT, window) into an RGBA texture-cache entry with a mip chain and sample it trilinear + anisotropic for 3D polygons; keep the raw-VRAM shader path for 2D. The framework already has the decode/hash/VRAM-write-tracking machinery in `hd_texture_pack.cpp`. | Far shimmer (item 2) without SSAA; anisotropic sampling also sharpens the road at grazing angles, which is exactly where the asphalt smears. Lets supersampling drop to 2–4× with equal or better stability. | Medium: a cache keyed like the HD-pack entries, invalidation on VRAM writes (already tracked), a second sampling path in the fragment shader. | CLUT changes and VRAM-rendered textures (the mirror, the HUD) must invalidate correctly — the tracking exists; verify with the lessons' frame-diff tools. | **Second.** The real replacement for 16×. |
| 3 | **HD texture pack for GT2.** Dump the race textures through the pack machinery, upscale (a clean 4× of the asphalt, walls, crowds, car liveries), ship as an optional download. | The magnified smear (item 1's other half) — nothing else can put detail into a 16-texel road. Also buries the tile seams at 4× texel density. | Content-heavy (hundreds of textures, curation), infrastructure mostly present. | Wrong hash matches and pop-in; a per-track pack can be validated visually. | Third — the biggest visual step, but it is content, not code. Start with the road and walls of one track as a pilot. |
| 4 | **MSAA option** (4×) as the edge anti-aliasing for the internal scale, with SSAA kept for those who want it. | Item 3; makes 2–4× internal + MSAA a first-class setting. | Medium (multisampled FBO, resolve before pack/readback). | Mask-bit/semi-transparency passes need care with samples. | After 1–2; matters for weaker GPUs. |
| 5 | **JINC2 / sharp-bilinear-3D texture filter** in the fragment shader. GT2 players on DuckStation prefer JINC2 for the car wheel arches ([Project Cerbera](https://projectcerbera.com/gt/2/duckstation/)). | Magnification quality on curved textures; not the road. | Small–medium (a 12-tap windowed sinc; DuckStation's shader is the reference for behaviour). | Cost per fragment; cheap on a real GPU. | Nice-to-have after 1–3. |
| 6 | **PGXP depth buffer, DuckStation-exact** (opaque only, clear-threshold, transparent-depth rules) | Ordering flicker (item 5) — *if* GT2 shows it; measure first with the ring (same-depth polygons swapping order across frames). | Medium; the lessons show the naïve version hurts. | Pinholes, decal loss — the known failure modes. | Only with evidence. |
| — | PGXP CPU mode, vertex cache, tolerance, gap fill, dilation, "completion", home-grown NCLIP rules, float matrices | — | — | — | **Don't.** Measured (CPU mode: 97.3 → 95.4%, +mismatches) or already rejected in the lessons; the upstream-precision argument in §2 says float matrices win ~0.07 px. |

Method for every step, from the lessons: the same frame, full internal
resolution, per-primitive counts (seam pixels at tile borders, changed
pixels per frame in a region), and a frame-matched A/B for the reporter —
never an aggregate metric on a downscaled frame.

## 6. Answering the original question directly

- *Why do PS1 games wobble?* Integer screen coordinates from a fixed-point
  projection, affine textures, no Z-buffer.
- *What does PGXP fix?* All of the above at the projection stage, for every
  vertex whose path it can follow; in GT2 that is 97.3% of race triangles
  with none mixed — parity with DuckStation was reached and verified.
- *What still moves?* Textures, not geometry: bilinear seams on the road
  tiles and on Seattle's big wall/highway quads, aliasing where textures
  minify, the smear where they magnify — plus, until the 60 FPS work is
  retested, judder from uneven frame delivery, which the chase view shows
  more than any other.
- *Best course without brute force:* seam-aware UV limits (days), a
  mipmapped/anisotropic texture cache (a week or two) — together they let
  supersampling drop from 16× to 2–4× with a steadier picture — then an HD
  texture pilot for one track, then MSAA and JINC2 as options. Leave PGXP's
  knobs at DuckStation's defaults; they are done.

Sources: [psx-spx GTE](https://psx-spx.consoledev.net/geometrytransformationenginegte/) · [DuckStation graphics option texts](https://github.com/stenzek/duckstation/blob/master/src/duckstation-qt/graphicssettingswidget.cpp) · [DuckStation cpu_pgxp.cpp](https://raw.githubusercontent.com/stenzek/duckstation/master/src/core/cpu_pgxp.cpp) · [Libretro: Beetle PSX PGXP arrives](https://www.libretro.com/index.php/mednafenbeetle-psx-pgxp-arrives/) · [Beetle PGXP README](https://github.com/libretro/beetle-psx-libretro/blob/master/pgxp/README.md) · [DuckStation texture replacement wiki](https://github.com/stenzek/duckstation/wiki/Texture-Replacement) · [Project Cerbera: DuckStation settings for GT2](https://projectcerbera.com/gt/2/duckstation/) · `docs/PGXP_LESSONS.md` · lab census and frames in this repository.
