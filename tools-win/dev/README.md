# Developer diagnostics

Scripts used while bringing GT2 up and tuning PGXP. They talk to the game's
debug TCP port (127.0.0.1:4370, one running instance) and write their captures
into the game folder's `diagnostics\` / `dumps\`. Not installed by default;
`GT2_DEV_TOOLS=1` at build time copies them into the game folder's `tools\`
(they expect to sit one level below the exe).

| Script | Purpose |
|---|---|
| `pgxp_tune.ps1`, `pgxp_knob.ps1` | Flip PGXP settings live (`pgxp` debug command); the F1 menu does the same in-game |
| `pgxp_trace.ps1`, `pgxp_framerec.ps1`, `pgxp_burst.ps1`, `pgxp_wobble.ps1`, `pgxp_why.ps1`, `pgxp_hunt.ps1`, `pgxp_ab.ps1` | Per-triangle ring, presented-frame bursts, provenance census - how the wall/guardrail wobble was found |
| `pace_trace.ps1`, `pad_trace.ps1` | Present cadence / controller input as the game sees it |
| `dump_gp0.ps1`, `dump_scene.ps1`, `dump_ab.ps1`, `dump_vram.ps1`, `dump_ram.ps1` | GP0 command stream, scene captures, VRAM / RAM dumps |
| `diag_*.ps1` | Bring-up era captures (boot stalls, CD delivery, garbled text, arcade unlocks, perf) |
| `check_build.ps1`, `build_pgxp.ps1`, `retail_test_build.ps1`, `toggle_native.ps1` | Build provenance check, hook-variant rebuild, retail-RAM A/B exe, native-code kill switch |
| `show_video.ps1`, `win_burst.ps1`, `scan_xbank.ps1`, `export_disc_chunks.ps1` | Misc capture/transfer helpers |

See `docs/PGXP_Lessons_GT2Recomp.docx` for how these were used.

`release/` holds John's GitHub push scripts (`push_update.cmd`,
`fix_release_tag.cmd`); they live in the game folder's `release\` subfolder,
not in `tools\` — see CLAUDE.md "Releasing".
