# Steam Deck

GT2Recomp runs on the Deck as the Windows build under Proton. There is no
native SteamOS build and none is planned for now: Proton runs the exe as-is,
and the Vulkan renderer gives it the Deck's GPU driver (RADV) directly, so a
Linux build would gain little. This page is the intended setup; it has not
yet been verified on Deck hardware - the notes below say what was checked
and where.

## Building

Setup (`Setup GT2.cmd`) needs MSYS2 and the game discs, so the build is
done on a Windows PC and the finished game folder is copied to the Deck
(SD card, or over the network into `/home/deck/Games/`). Everything the
game needs is inside that folder: the disc exes, `game.toml`, the BIOS,
the box art, memory cards and saves. Copy the whole folder.

## Adding the game to Steam

In Desktop Mode, open Steam, *Games > Add a Non-Steam Game to My Library*,
browse to the folder and pick `Gran Turismo 2 Recompiled.exe` (the small
starter that opens whichever disc you built; the per-disc exes work too).
Then in the game's *Properties > Compatibility*, tick *Force the use of a
specific Steam Play compatibility tool* and choose **Proton Hotfix**. The
first launch takes a few seconds longer while Proton sets up its prefix.

## Launcher settings for the Deck

The launcher opens as usual under Proton. Display settings open on a short
list (presets, window, supersampling, texture filtering); three of the four
rows below live under **Show advanced settings**, the checkbox at the bottom
of that list, so tick it first.

| Row | Where | Set to | Why |
|---|---|---|---|
| Renderer | advanced | **Vulkan** | Talks to RADV directly. OpenGL also works (Proton passes it to Mesa) but Vulkan is the path the driver and Proton are tuned for. |
| Fullscreen | simple | **Borderless** | The Deck's screen is 1280x800; the 1280x960 default window is taller than the panel. Borderless letterboxes the 4:3 image at native size. |
| Supersampling | simple | 2x-4x | 4x is 1280x960 internal, the most the 800-row panel can show; drop to 2x if a race dips (the 60 FPS mod is CPU work, see `PERFORMANCE.md`). |
| Hide cursor in fullscreen | advanced | on | Gaming Mode has no visible pointer, but the Windows cursor would otherwise sit in the middle of the picture. |

The advanced toggle is a view state, not a setting: it is not written to
`settings.toml`, so the launcher opens on the short list again next run. The
values you set while it was open are saved normally.

A machine without a usable Vulkan driver falls back to OpenGL with a line
in the log, so a wrong Renderer choice never leaves the game unable to
start.

## Controls

Steam Input presents the Deck's controls as a controller, which the game
picks up as Player 1 like any pad (the launcher's Player 1 box shows it as
connected). The default Steam Input template is fine; the trackpad drives
the launcher as a mouse. Hotkeys mapped to controller buttons in
`config.ini` (`[hotkeys] switch_disc_pad` and friends) work the same as on
Windows.

## What is not there yet on Vulkan

Vulkan now does everything OpenGL does bar one thing. It rasterises with the
same 1x-4x supersampling, PGXP and widescreen; it has all eleven texture
filters, *Filter 2D elements*, the display aspect, *Display scaling*
(including sharp-bilinear), post-processing (FXAA), *Crop FMVs*, *FMV
filtering* (including bicubic) and *FMV chroma smoothing*. The exception is
the second half of edge blending: the coverage cutout is there, but blending
the surviving fragments by coverage needs a dual-source blend the Vulkan
pipelines do not set up yet, so *Edge blending* is softer on OpenGL. Vulkan
also builds its filter shaders at compile time instead of on first use, so
picking a heavy filter (the MMPX family) does not stall the first frame the
way it can on OpenGL.

The launcher itself is fine on the Deck's panel: its UI scales to whatever
the window or screen gives it, so the whole page fits at 1280x800 both
windowed in Desktop Mode and full-screen in Gaming Mode.

## What was checked

On a Linux lab machine with Mesa's software Vulkan driver: the Vulkan
backend initialises, boots the Arcade disc, runs races and loads save states;
the intro movie presents with the crop and chroma smoothing applied and the
crop is frame-stable across it; all eleven texture filter modes were compared
against OpenGL frame for frame from a fixed save state; FXAA measurably
softens the presented frame;
the menu font atlas matches OpenGL texel for texel after the intro movie (the
garbled-menu-text bug); a full boot plus the menus under the Khronos
validation layers reports no errors;
the launcher lists Software, OpenGL and Vulkan and launches the game on
Vulkan; a Vulkan request with no Vulkan driver present falls back to OpenGL
and the game starts normally. The launcher was checked on simulated
1280x800 (windowed and full-screen), 1366x768, 1920x1080 and 3840x2160
displays - the layout fits and its buttons hit-test correctly at each. Nothing has been run under Proton on a Deck yet. When
you do, the game's console output says which renderer came up
(`psxrecomp: renderer backend requested: vulkan`, then `vulkan: device =`
with the GPU name); to see it on the Deck, set the game's launch options to
`PROTON_LOG=1 %command%` and read `~/steam-<appid>.log` after a run.
