Title: Mod-selected display aspect is clobbered by the post-activation settings settle

On PSX, display-view controls are mod-owned (`gi->aspect_mask = 0`) and a
game mod selects the aspect via `psx_mod_set_fixed_display_aspect()` from an
activation callback. However, the settings settle that runs after
`mod_runtime_activate_plugins()` re-applies `switch (ls.aspect_index)` from
the launcher snapshot, which was taken before activation and (with the PSX
profile's hidden aspect row) always reads index 0 — resetting the mod's
choice to 4:3 every launch.

The comment immediately above that switch already documents this clobber
class for `turbo_loads` / `auto_skip_fmv` ("Applying them here would clobber
whatever the ... plugins decided with a stale pre-activation value") and
guards both. The display aspect needs the same treatment.

Repro: any game package with an activation plugin calling
psx_mod_set_fixed_display_aspect(16, 9); observe the window/present stays 4:3.
Suggested fix: track mod ownership (set on psx_mod_set_fixed/adaptive_
display_aspect) and skip the aspect settle switch when owned — patch attached.
