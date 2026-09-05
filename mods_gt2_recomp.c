/*
 * GT2Recomp's own conveniences (mods/packages/gt2.recomp) - trusted plugin
 * implementations. Nothing here patches game code; these drive runtime
 * facilities the framework already owns.
 */

#include "mod_plugins.h"

/* ---- Skip intro movie -----------------------------------------------------
 *
 * The framework's FMV auto-skip is a generic mechanism (hold START while a
 * streaming movie is detected, which is how a player skips GT2's intro) and
 * it is deliberately mod-owned on PSX: a title decides WHEN it applies. GT2
 * has one movie a player wants gone - the opening, between the disclaimer
 * and the memory card screen - and it is the first thing that streams after
 * boot. So the skip is armed at activation and disarmed after a window of
 * guest vblanks long enough to reach and skip the intro on any machine (the
 * window counts guest frames, not wall time, so a slow PC is not short-
 * changed) and far too short to reach anything else the game plays as
 * video: the attract-mode loop of the same movie sits behind a title-screen
 * timeout, and the ending sits behind the whole game. */
#define GT2_SKIP_INTRO_WINDOW_FRAMES 4500u   /* ~75 s at 60 Hz vblank */

static unsigned s_skip_intro_frames;
static int s_skip_intro_armed;

static void gt2_skip_intro_activate(void) {
    s_skip_intro_frames = 0;
    s_skip_intro_armed = 1;
    (void)psx_mod_set_auto_skip_fmv(1);
}

static void gt2_skip_intro_vblank(void) {
    if (!s_skip_intro_armed) return;
    if (!psx_mod_game_started()) return;
    if (++s_skip_intro_frames < GT2_SKIP_INTRO_WINDOW_FRAMES) return;
    s_skip_intro_armed = 0;
    (void)psx_mod_set_auto_skip_fmv(0);
}

PSX_MOD_CONSTRUCTOR(gt2_register_recomp_extras) {
    (void)psx_mod_register_activation_plugin("gt2.skip-intro", gt2_skip_intro_activate);
    (void)psx_mod_register_vblank_plugin("gt2.skip-intro", gt2_skip_intro_vblank);
}
