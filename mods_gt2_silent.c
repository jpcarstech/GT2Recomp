/*
 * Silent's Enhancements for Gran Turismo 2 — trusted plugin implementations.
 *
 * Patch data by Silent (CookiePLMonster) and asasega, from
 * https://github.com/CookiePLMonster/Console-Cheat-Codes
 * (PS1/Gran Turismo 2), converted from GameShark form to guarded
 * per-VBlank writes. Verified against the GT2 Combined Disc build of
 * NTSC-U 1.1 (overlay gt2_01 of GT2.OVL, load base 0x80010000).
 *
 * VERIFICATION POLICY (learned the hard way on the arcade cheats): the
 * Combined Disc rebuilds parts of the game, so no external cheat database
 * is trusted - every site below was confirmed against a live RAM capture
 * of THIS disc with the target overlay resident (write-if-match makes a
 * wrong site harmless: it silently does nothing rather than corrupting).
 * Data pokes into save-derived state lose the reload race on mode entry;
 * anything an in-game screen derives at build time is patched at the
 * CHECK (code site), not the data.
 *
 * GT2 streams its mode code from GT2.OVL over the boot EXE image, so these
 * sites only exist while the Simulation-mode overlay (gt2_01) is resident.
 * Every write is double-gated:
 *   1. an overlay fingerprint — two instruction words unique to gt2_01 that
 *      no enhancement touches — must match, and
 *   2. the exact original instruction/value must be present at the site
 *      (write-if-match, mirroring Silent's A7 GameShark semantics).
 * On any other overlay, game revision, or already-patched state, a VBlank
 * tick does nothing.
 */

#include "mod_plugins.h"

struct CPUState;
extern void fntrace_mark_game_started(struct CPUState* cpu);

/* gt2_01 residency fingerprint. Silent's own A4 overlay-identity guard
 * words, verified unique to gt2_01 across every overlay in GT2.OVL and
 * untouched by every enhancement in the pack. (The previous fingerprint
 * pair at 0x80016A6C/0x80016A78 is REWRITTEN by the 8MB polygon-buffer
 * patch below, so it can no longer identify the overlay.) */
#define GT2_FP_ADDR_A   0x8001F888u
#define GT2_FP_WORD_A   0xAEB40008u
#define GT2_FP_ADDR_B   0x8003EC6Cu
#define GT2_FP_WORD_B   0x02602021u

static int gt2_sim_overlay_resident(void) {
    return psx_mod_read_word(GT2_FP_ADDR_A) == GT2_FP_WORD_A &&
           psx_mod_read_word(GT2_FP_ADDR_B) == GT2_FP_WORD_B;
}

/* FMV gate (user requirement): NO enhancement touches FMV playback — the
 * intro and all in-game movies run authentic. Uses the runtime's strict
 * FMV classifier (gpu.c) rather than raw MDEC activity: GT2's course
 * select embeds an MDEC track-preview movie inside a live 3D scene, and a
 * raw MDEC gate kept the overclock disengaged there (sluggish menu). The
 * classifier calls that a game frame; the intro and fullscreen movies
 * (24-bit, no shaded prims) still classify as FMV. */
extern int gpu_ws_fmv_frame(void);

static int gt2_fmv_active(void) {
    return gpu_ws_fmv_frame();
}

/* ---- 60 FPS (NTSC-U 1.1 sites) ------------------------------------------
 * - frame divider byte: 2 (30 fps) -> 1 (60 fps); game data, re-checked
 *   every VBlank because mode changes rewrite it.
 * - three `slti v0,v0,2` -> `slti v0,v0,0` immediates that would otherwise
 *   halve the tire-smoke / mirror-sky / rear-mirror update rate at 60 fps.
 *   (Silent's A0/A4 lines for this revision write values the 1.1 overlay
 *   already contains — cross-revision normalizers — so they are omitted.)
 */
#define GT2_60FPS_DIVIDER   0x801D5634u

static const uint32_t k60fps_slti_sites[] = {
    0x800168C8u,   /* tire smoke cadence   */
    0x80019644u,   /* rear-mirror sky      */
    0x80029548u,   /* rear-mirror redraw   */
};
#define GT2_SLTI_ORIG  0x28420002u   /* slti v0,v0,2 */
#define GT2_SLTI_PATCH 0x28420000u   /* slti v0,v0,0 */

/* VBlank-side game-start latch. The entry-function hook (below) covers the
 * native path, but GT2's boot-loaded EXE code executes on the dirty-RAM
 * interpreter (BIOS load marks the pages runtime-written), so the generated
 * entry body — and with it the framework's game-start latch — never runs.
 * Once the Simulation overlay is resident the game is unambiguously past
 * boot: trip the latch with the runtime's bound CPU state. Idempotent. */
extern int psx_mod_game_started(void);
extern struct CPUState* debug_cpu_ptr;

static void gt2_latch_game_started(void) {
    if (psx_mod_game_started()) return;
    if (!gt2_sim_overlay_resident()) return;
    if (debug_cpu_ptr) fntrace_mark_game_started(debug_cpu_ptr);
}

/* ---- CPU Overclock (its own feature) ------------------------------------
 * Runs the emulated CPU at the chosen percentage everywhere past boot except
 * FMV (user policy): menus included — GT2's UI is sluggish at stock speed.
 * The BIOS boot (Sony/PS logos) stays stock: the latch is not set yet.
 * The 60 FPS feature depends on this one to actually reach 60. */
extern void psx_set_cpu_overclock(uint32_t percent);   /* psx_cycles.h */
static unsigned g_gt2_oc_pct = 200;     /* read from option at activation */
static int      g_gt2_oc_applied = 0;

static void gt2_overclock_vblank(void) {
    gt2_latch_game_started();

    if (gt2_fmv_active()) {
        if (g_gt2_oc_applied) { psx_set_cpu_overclock(100u); g_gt2_oc_applied = 0; }
        return;
    }
    if (psx_mod_game_started() && !g_gt2_oc_applied) {
        psx_set_cpu_overclock(g_gt2_oc_pct);
        g_gt2_oc_applied = 1;
    }
}

static void gt2_60fps_vblank(void) {
    gt2_latch_game_started();

    /* FMV: keep everything authentic — no patches. */
    if (gt2_fmv_active())
        return;

    /* The 60 fps code patches exist only in the Simulation overlay (gt2_01);
     * on any other overlay the sites can't match and there is nothing to do. */
    if (!gt2_sim_overlay_resident())
        return;
    if (psx_mod_read_byte(GT2_60FPS_DIVIDER) == 2u)
        psx_mod_write_byte(GT2_60FPS_DIVIDER, 1u);
    for (unsigned i = 0; i < sizeof(k60fps_slti_sites) / sizeof(uint32_t); ++i) {
        const uint32_t addr = k60fps_slti_sites[i];
        if (psx_mod_read_word(addr) == GT2_SLTI_ORIG)
            psx_mod_write_code_word(addr, GT2_SLTI_PATCH);
    }
}

/* ---- Display aspect (mod-owned, per the framework's intended design) ----
 * Reads the feature's "ratio" choice and requests a fixed display aspect
 * before renderer/window init. Feature disabled -> activation never runs ->
 * stock 4:3. Unknown/missing value -> no call (stock presentation).
 */
#include <string.h>

static int g_gt2_ws_num = 0, g_gt2_ws_den = 1;   /* chosen aspect; 0 = off */

static void gt2_display_aspect_activate(void) {
    char v[16] = "";
    if (!psx_mod_option_value("gt2.silent-enhancements", "aspect", "ratio",
                              v, sizeof v))
        return;
    if      (strcmp(v, "16:9")  == 0) { g_gt2_ws_num = 16; g_gt2_ws_den = 9;
        (void)psx_mod_set_fixed_display_aspect(16, 9); }
    else if (strcmp(v, "16:10") == 0) { g_gt2_ws_num = 16; g_gt2_ws_den = 10;
        (void)psx_mod_set_fixed_display_aspect(16, 10); }
    else if (strcmp(v, "21:9")  == 0) { g_gt2_ws_num = 21; g_gt2_ws_den = 9;
        (void)psx_mod_set_fixed_display_aspect(21, 9); }
}

/* ---- Native 16:9 widescreen (Silent's "16:9 Widescreen" patch) ----------
 * GT2's widescreen is done GAME-SIDE, exactly as the user runs it in
 * DuckStation (cheat on, emulator widescreen hack off): Silent's patch makes
 * the race renderer project, window and cull a true 16:9 field of view
 * anamorphically into the 4:3 frame, and the runtime presents a plain
 * stretch ([widescreen] gte_squash = false keeps the framework's GTE
 * X-squash at identity so the widening is never applied twice).
 *
 * The sites below are Silent's A7 write-if-match halfwords, verbatim,
 * limited to the blocks whose guards exist in the Simulation-mode overlay
 * set of the Combined Disc (gt2_01 / gt2_03) — every site was verified
 * present in the shipped overlay images. Menus and FMV run other overlays,
 * where none of these addresses match: they stay stock and present 4:3.
 * Native values are tuned for 16:9; the 16:10 / 21:9 choices keep the
 * framework presentation without the game-side patch for now. */
typedef struct {
    uint32_t guard_addr;   /* Silent's A4 overlay-identity word for the block */
    uint32_t guard_word;
    uint32_t addr;         /* halfword site */
    uint16_t orig, patched;
} Gt2WsSite;

static const Gt2WsSite k_gt2_ws_sites[] = {
    /* -- guard A401F888 AEB40008 (race draw window / projection setup) -- */
    { 0x8001F888u, 0xAEB40008u, 0x800100D0u, 0xFF60u, 0xFF2Bu },
    { 0x8001F888u, 0xAEB40008u, 0x800100D4u, 0x00A0u, 0x00D5u },
    /* -- guard A403EC6C 02602021 (rear-view mirror window) -- */
    { 0x8003EC6Cu, 0x02602021u, 0x800295E4u, 0xFFC4u, 0xFFB0u },
    { 0x8003EC6Cu, 0x02602021u, 0x800295E8u, 0x003Cu, 0x0050u },
    /* -- guard A4057010 260201C0 (race render paths) -- */
    { 0x80057010u, 0x260201C0u, 0x80049736u, 0xA485u, 0xA489u },
    { 0x80057010u, 0x260201C0u, 0x80049EB4u, 0x00C8u, 0x010Au },
    { 0x80057010u, 0x260201C0u, 0x80049EBCu, 0x3021u, 0x00C8u },
    { 0x80057010u, 0x260201C0u, 0x80049EBEu, 0x00A0u, 0x3406u },
    { 0x80057010u, 0x260201C0u, 0x8004C100u, 0x00C8u, 0x010Au },
    { 0x80057010u, 0x260201C0u, 0x8004C108u, 0x3021u, 0x00C8u },
    { 0x80057010u, 0x260201C0u, 0x8004C10Au, 0x00A0u, 0x3406u },
    { 0x80057010u, 0x260201C0u, 0x8004DFE8u, 0x0000u, 0x0160u },
    { 0x80057010u, 0x260201C0u, 0x8004DFEAu, 0x0000u, 0x2405u },
    { 0x80057010u, 0x260201C0u, 0x8004DFF4u, 0x0220u, 0x00C4u },
    { 0x80057010u, 0x260201C0u, 0x8004DFF6u, 0x8FB2u, 0xA485u },
    { 0x80057010u, 0x260201C0u, 0x8004DFD0u, 0x0160u, 0x01D5u },
    { 0x80057010u, 0x260201C0u, 0x80050B80u, 0xFF50u, 0xFF16u },
    { 0x80057010u, 0x260201C0u, 0x80050B88u, 0x00B0u, 0x00EAu },
    /* -- guard A405D598 8005A5B4 (race render paths, second bank) -- */
    { 0x8005D598u, 0x8005A5B4u, 0x8005802Cu, 0x00C8u, 0x010Au },
    { 0x8005D598u, 0x8005A5B4u, 0x80058034u, 0x3021u, 0x00C8u },
    { 0x8005D598u, 0x8005A5B4u, 0x80058036u, 0x00A0u, 0x3406u },
    { 0x8005D598u, 0x8005A5B4u, 0x800588E0u, 0x00C8u, 0x010Au },
    { 0x8005D598u, 0x8005A5B4u, 0x800588E8u, 0x3021u, 0x00C8u },
    { 0x8005D598u, 0x8005A5B4u, 0x800588EAu, 0x00A0u, 0x3406u },
    { 0x8005D598u, 0x8005A5B4u, 0x800599C4u, 0x0160u, 0x01D5u },
    /* -- guard A4020A74 3084007F (gt2_03 overlay: bounds bank) -- */
    { 0x80020A74u, 0x3084007Fu, 0x8001E55Cu, 0xFF80u, 0xFF56u },
    { 0x80020A74u, 0x3084007Fu, 0x8001E564u, 0x0080u, 0x00AAu },
    { 0x80020A74u, 0x3084007Fu, 0x800201A8u, 0xFF97u, 0xFF74u },
    { 0x80020A74u, 0x3084007Fu, 0x800201B0u, 0x0069u, 0x008Cu },
    { 0x80020A74u, 0x3084007Fu, 0x80015350u, 0x0140u, 0x01AAu },
};

static void gt2_ws_native_vblank(void) {
    /* Native patch is 16:9-tuned; other ratios keep the plain framework
     * presentation for now. */
    if (g_gt2_ws_num != 16 || g_gt2_ws_den != 9) return;
    if (gt2_fmv_active()) return;

    uint32_t cached_guard_addr = 0;
    int      guard_ok = 0;
    for (unsigned i = 0;
         i < sizeof(k_gt2_ws_sites) / sizeof(k_gt2_ws_sites[0]); ++i) {
        const Gt2WsSite* s = &k_gt2_ws_sites[i];
        if (s->guard_addr != cached_guard_addr) {
            cached_guard_addr = s->guard_addr;
            guard_ok = psx_mod_read_word(s->guard_addr) == s->guard_word;
        }
        if (!guard_ok) continue;

        const uint32_t wa = s->addr & ~3u;
        const int      sh = (s->addr & 2u) ? 16 : 0;
        uint32_t w = psx_mod_read_word(wa);
        if ((uint16_t)(w >> sh) != s->orig) continue;   /* patched or foreign */
        w = (w & ~(0xFFFFu << sh)) | ((uint32_t)s->patched << sh);
        psx_mod_write_code_word(wa, w);
    }
}

static void gt2_aspect_vblank(void) {
    gt2_latch_game_started();
    gt2_ws_native_vblank();
}

/* ---- Slightly higher draw distance --------------------------------------
 * Silent's "Slightly higher draw distance" (NTSC-U 1.1): the race renderer
 * has a conditional that keeps the REPLAY draw distance out of normal
 * races; flip its bnez into an unconditional j to the same target so races
 * always use the replay distance. (The game's draw distance is bounded by
 * track data itself, hence "slightly".) One word in gt2_01:
 *   0x80020420: 0x14400004 (bnez v0,+4 -> 0x80020434)
 *            -> 0x0800810D (j 0x80020434)
 * A4 guard is the gt2_01 fingerprint word at 0x8003EC6C (checked in
 * gt2_sim_overlay_resident); site is write-if-match like every port here. */
#define GT2_DRAWDIST_ADDR  0x80020420u
#define GT2_DRAWDIST_ORIG  0x14400004u
#define GT2_DRAWDIST_PATCH 0x0800810Du

static void gt2_drawdist_vblank(void) {
    gt2_latch_game_started();
    if (gt2_fmv_active()) return;
    if (!gt2_sim_overlay_resident()) return;
    if (psx_mod_read_word(GT2_DRAWDIST_ADDR) == GT2_DRAWDIST_ORIG)
        psx_mod_write_code_word(GT2_DRAWDIST_ADDR, GT2_DRAWDIST_PATCH);
}

/* ---- Use 8MB RAM for polygon buffers ------------------------------------
 * Silent's dev-RAM cheat: gt2_01's polygon/OT buffer setup at 0x80016A6C
 * builds base 0x000E5700 (s1-relative) and size 0x38000; rewrite it to the
 * absolute expanded-RAM base 0x80200000 with size 0x70000 (doubled):
 *   lui a1,0x000E / ori a1,0x5700 -> lui a1,0x8020 / ori a1,0
 *   addu a1,s1,a1                 -> nop
 *   lui a2,0x0003 / ori a2,0x8000 -> lui a2,0x0007 / ori a2,0
 * Silent's D1 lines detect real 8MB by probing a 2MB mirror; this build
 * knows its geometry at compile time (psx_memory.h), so the whole feature
 * compiles out of retail-RAM builds. Takes effect when a race (re)loads —
 * the setup code runs at overlay init, same as the DuckStation cheat. */
#include "psx_memory.h"

typedef struct { uint32_t addr, orig, patched; } Gt2WordSite;

#if PSX_MAIN_RAM_BYTES == PSX_MAIN_RAM_EXPANDED_BYTES

static const Gt2WordSite k_gt2_ram8_sites[] = {
    { 0x80016A6Cu, 0x3C05000Eu, 0x3C058020u },   /* lui a1,0x8020    */
    { 0x80016A70u, 0x34A55700u, 0x34A50000u },   /* ori a1,a1,0      */
    { 0x80016A78u, 0x02252821u, 0x00000000u },   /* addu -> nop      */
    { 0x80016A7Cu, 0x3C060003u, 0x3C060007u },   /* lui a2,0x0007    */
    { 0x80016A88u, 0x34C68000u, 0x34C60000u },   /* ori a2,a2,0      */
};

static int gt2_ram8_patched(void) {
    return psx_mod_read_word(k_gt2_ram8_sites[0].addr)
        == k_gt2_ram8_sites[0].patched;
}

static void gt2_ram8_vblank(void) {
    gt2_latch_game_started();
    if (gt2_fmv_active()) return;
    if (!gt2_sim_overlay_resident()) return;
    for (unsigned i = 0;
         i < sizeof(k_gt2_ram8_sites) / sizeof(k_gt2_ram8_sites[0]); ++i) {
        const Gt2WordSite* s = &k_gt2_ram8_sites[i];
        if (psx_mod_read_word(s->addr) == s->orig)
            psx_mod_write_code_word(s->addr, s->patched);
    }
}

/* ---- Full detail (LOD) AI cars ------------------------------------------
 * Forces every car to the highest LOD model. Needs the doubled polygon
 * buffers above — six full-detail cars overflow the stock 0x38000 buffer —
 * so this handler arms only after the 8MB patch is observed applied in RAM
 * (which also sequences it behind that feature being enabled). Sites:
 *   0x80014344: 0x16A00040 (bnez s5,+0x40) -> 0x08005112 (j 0x80014448)
 *   0x80014348: 0x24120003 (li s2,3)       -> 0x24120001 (li s2,1)      */
static const Gt2WordSite k_gt2_lod_sites[] = {
    { 0x80014344u, 0x16A00040u, 0x08005112u },
    { 0x80014348u, 0x24120003u, 0x24120001u },
};

static void gt2_fulllod_vblank(void) {
    gt2_latch_game_started();
    if (gt2_fmv_active()) return;
    if (!gt2_sim_overlay_resident()) return;
    if (!gt2_ram8_patched()) return;   /* hard dependency: 8MB buffers */
    for (unsigned i = 0;
         i < sizeof(k_gt2_lod_sites) / sizeof(k_gt2_lod_sites[0]); ++i) {
        const Gt2WordSite* s = &k_gt2_lod_sites[i];
        if (psx_mod_read_word(s->addr) == s->orig)
            psx_mod_write_code_word(s->addr, s->patched);
    }
}
#endif /* expanded RAM */

/* Activation records the chosen percentage; the VBlank handler arms and
 * disarms it around FMV playback (user requirement: movies stay authentic). */
#include <stdlib.h>

static void gt2_overclock_activate(void) {
    char v[16] = "";
    if (psx_mod_option_value("gt2.silent-enhancements", "overclock", "percent",
                             v, sizeof v)) {
        const unsigned parsed = (unsigned)atoi(v);
        if (parsed >= 100u && parsed <= 400u) g_gt2_oc_pct = parsed;
    }
}

/* Game-start latch. GT2 defeats both framework detectors (see game.toml
 * [recompiler] mod_function_entry_funcs): the HLE BIOS handoff enters the
 * EXE without an entry dispatch, and GT2.OVL overwrites game text so the
 * clean-text latch can never match. The generated hook at the PS-EXE entry
 * lands here; fntrace_mark_game_started is idempotent and performs the
 * standard handoff (dirty baseline, CD speed switch, widescreen engage). */
static void gt2_game_start_hook(struct CPUState* cpu, uint32_t address) {
    (void)address;
    fntrace_mark_game_started(cpu);
}

/* ---- Arcade unlocks (Combined-disc code patches) ------------------------
 * The classic GameShark data cheats for the retail Arcade disc do NOT work
 * on the Combined disc: its rebuilt arcade mode relocates that data, and
 * the old addresses (0x800F364E track masks, 0x801C93F8 completion array)
 * are dead memory here - verified empirically (values stick, game never
 * reads them; same non-result on DuckStation with the Combined disc).
 *
 * Reverse-engineered from the Combined disc's arcade overlay instead:
 * course/car menu items are filtered at menu registration by two checks -
 *   1. 0x8002357C(group): a track group is unlocked when all 10 ranking
 *      entries of its block (arcade state struct 0x801C96B0 + 0x1418 +
 *      group*0x668, entry stride 0xA4, presence byte +1) are populated;
 *   2. an unlock-bit array at struct+0xB8, tested via (byte>>2)&1 inside
 *      the item walker 0x8001D120 (and (byte>>1)|(byte>>2) in the car-
 *      completeness scan at 0x800235F4).
 * The menu list is rebuilt from these checks on every Arcade-mode entry,
 * right after the save image reloads, so one-shot data writes lose the
 * race. Patch the CHECKS instead (write-if-match, Silent A7 semantics -
 * the original words exist only while the arcade overlay is resident, so
 * the match doubles as the overlay guard):
 *   0x8002357C: move a2,a0   -> jr ra        \ predicate returns 1
 *   0x80023580: bgez a2,+xx  -> li v0,1      / (delay slot)
 *   0x8001D1C0: andi v0,v0,1 -> ori v0,zero,1  unlock-bit gate always set
 * Effect shows from the next Arcade-mode entry (menus registered then). */
static const Gt2WordSite k_gt2_arcade_tracks_sites[] = {
    { 0x8002357Cu, 0x00803021u, 0x03E00008u },   /* move a2,a0 -> jr ra  */
    { 0x80023580u, 0x04C10003u, 0x24020001u },   /* bgez       -> li v0,1 */
};

static const Gt2WordSite k_gt2_arcade_cars_sites[] = {
    { 0x8001D1C0u, 0x30420001u, 0x34020001u },   /* andi v0,v0,1 -> ori v0,zero,1 */
};

static void gt2_arcade_apply(const Gt2WordSite* sites, unsigned n) {
    gt2_latch_game_started();
    if (gt2_fmv_active()) return;
    for (unsigned i = 0; i < n; ++i) {
        if (psx_mod_read_word(sites[i].addr) == sites[i].orig)
            psx_mod_write_code_word(sites[i].addr, sites[i].patched);
    }
}

static void gt2_arcade_tracks_vblank(void) {
    gt2_arcade_apply(k_gt2_arcade_tracks_sites,
                     sizeof(k_gt2_arcade_tracks_sites) /
                     sizeof(k_gt2_arcade_tracks_sites[0]));
}

/* Extra cars / classes derive from the per-track "beaten" flag array at
 * arcade state struct+0xB8 (0x801C9768; one byte per track index 0..20,
 * difficulty bits 0..2 - fresh saves are all zero, and the array reloads
 * from the save image on every Arcade-mode entry). Asserting the bits per
 * VBlank simulates "every road track beaten on all difficulties", the same
 * semantics the classic cars cheat had on the retail disc. The class/car
 * screens read the flags when opened, so per-frame assertion always wins
 * the reload race. Guarded by the tracks-site fingerprint words (arcade
 * overlay resident), original or patched. */
#define GT2_ARCADE_BEATEN_ARRAY  0x801C9768u
#define GT2_ARCADE_TRACK_COUNT   21u

static int gt2_arcade_overlay_resident(void) {
    uint32_t w = psx_mod_read_word(k_gt2_arcade_tracks_sites[0].addr);
    return w == k_gt2_arcade_tracks_sites[0].orig ||
           w == k_gt2_arcade_tracks_sites[0].patched;
}

static void gt2_arcade_cars_vblank(void) {
    gt2_arcade_apply(k_gt2_arcade_cars_sites,
                     sizeof(k_gt2_arcade_cars_sites) /
                     sizeof(k_gt2_arcade_cars_sites[0]));
    if (!gt2_arcade_overlay_resident()) return;
    for (uint32_t i = 0; i < GT2_ARCADE_TRACK_COUNT; ++i) {
        uint32_t a = GT2_ARCADE_BEATEN_ARRAY + i;
        uint8_t b = psx_mod_read_byte(a);
        if ((b & 0x07u) != 0x07u)
            psx_mod_write_byte(a, (uint8_t)(b | 0x07u));
    }
}

/* ---- plain Arcade disc (SCUS-94455) -------------------------------------
 * The published GameShark unlock codes for this serial (0x800F364E.. track
 * counts, 0x801C93F8.. completion record) are for the v1.0 pressing; on
 * v1.1 every save-struct address sits 0x370 higher, and asserted every
 * VBlank the v1.0 writes corrupted the input path (2026-09-02). They were
 * removed, and the v1.1 arcade overlay reverse-engineered instead: its
 * unlock predicate (0x8002357C), item walker (0x8001D120) and beaten-flag
 * array (0x801C9768) are byte-for-byte the code the Combined Disc features
 * above patch - the Combined Disc's arcade mode IS the v1.1 arcade code -
 * so those two features now target SCUS-94455 as well. Lab-verified on the
 * v1.1 Arcade disc: course counts 3/0/3/0/1/3/1 -> 21/21/23/23/9/21/6, the
 * course list runs to "21. Rome-Night", Class-S grows from 8 to 10 cars
 * (docs/CHEAT_VERIFICATION.md, docs/evidence/). */

/* ---- Silent's remaining patches, verbatim from DuckStation's database ----
 * Executed by gameshark_vm.c with DuckStation's own code semantics (see
 * docs/duckstation-cheat-format.md). The tables are generated from the
 * "Rev 1" (v1.1) files in mods/db/duckstation/ by tools/cht_to_c.py and
 * carry Silent's overlay-identity guards, so each does nothing until its
 * overlay is resident. Each runs only while its feature is enabled (the
 * runtime invokes a VBlank plugin only when its feature is in the plan). */
#include "gameshark_vm.h"
#include "mods_gt2_silent_codes.h"
#include "mods_gt2_silent_codes_sim.h"
/* Community Simulation-disc cheats re-derived for v1.1 (mods/db/gt2recomp/
 * SCUS-94488_v1.1.cht): the v1.0/v1.2 codes shifted to the v1.1 save layout
 * (+0x370), code sites checked against the v1.1 GT-mode overlay, every one
 * run in the lab - docs/CHEAT_VERIFICATION.md. Each is A4-guarded on a
 * GT-mode menu overlay word, so nothing is written while the race overlay
 * (or arcade mode on the Combined Disc) occupies that memory. */
#include "mods_gt2_v11_codes_sim.h"

#define GT2_GS_PLUGIN(fn, cheat)                                   \
    static void fn(void) {                                         \
        static GsState st;                                         \
        if (!psx_mod_game_started() || gt2_fmv_active()) return;   \
        (void)gs_run(&cheat, &st, 1);                              \
    }
GT2_GS_PLUGIN(gt2_gs_metric_vblank,     gs_metric_units)
GT2_GS_PLUGIN(gt2_gs_hudmirror_vblank,  gs_hud_mirror)
GT2_GS_PLUGIN(gt2_gs_replaycams_vblank, gs_replay_cams)
GT2_GS_PLUGIN(gt2_gs_bgm_vblank,        gs_bgm_switch)
GT2_GS_PLUGIN(gt2_gs_endurance_vblank,  gs_true_endurance)
GT2_GS_PLUGIN(gt2_gs_eventgen_vblank,   gs_fixed_event_gen)
GT2_GS_PLUGIN(gt2_gs_cash_vblank,       gs_v11_cash)
GT2_GS_PLUGIN(gt2_gs_moneykeep_vblank,  gs_v11_money_never_dec)
GT2_GS_PLUGIN(gt2_gs_anycar_vblank,     gs_v11_any_car)
GT2_GS_PLUGIN(gt2_gs_goldall_vblank,    gs_v11_gold_all)
GT2_GS_PLUGIN(gt2_gs_golds_vblank,      gs_v11_gold_s)
GT2_GS_PLUGIN(gt2_gs_goldia_vblank,     gs_v11_gold_ia)
GT2_GS_PLUGIN(gt2_gs_goldib_vblank,     gs_v11_gold_ib)
GT2_GS_PLUGIN(gt2_gs_goldic_vblank,     gs_v11_gold_ic)
GT2_GS_PLUGIN(gt2_gs_golda_vblank,      gs_v11_gold_a)
GT2_GS_PLUGIN(gt2_gs_goldb_vblank,      gs_v11_gold_b)
GT2_GS_PLUGIN(gt2_gs_racesdone_vblank,  gs_v11_races_done)

PSX_MOD_CONSTRUCTOR(gt2_register_silent_enhancements) {
    (void)psx_mod_register_vblank_plugin("gt2.gs-metric",     gt2_gs_metric_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-hudmirror",  gt2_gs_hudmirror_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-replaycams", gt2_gs_replaycams_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-bgm",        gt2_gs_bgm_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-endurance",  gt2_gs_endurance_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-eventgen",   gt2_gs_eventgen_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-cash",       gt2_gs_cash_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-moneykeep",  gt2_gs_moneykeep_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-anycar",     gt2_gs_anycar_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-goldall",    gt2_gs_goldall_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-golds",      gt2_gs_golds_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-goldia",     gt2_gs_goldia_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-goldib",     gt2_gs_goldib_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-goldic",     gt2_gs_goldic_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-golda",      gt2_gs_golda_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-goldb",      gt2_gs_goldb_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.gs-racesdone",  gt2_gs_racesdone_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.display-aspect",
                                         gt2_aspect_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.drawdistance",
                                         gt2_drawdist_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.arcadetracks",
                                         gt2_arcade_tracks_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.arcadecars",
                                         gt2_arcade_cars_vblank);
#if PSX_MAIN_RAM_BYTES == PSX_MAIN_RAM_EXPANDED_BYTES
    (void)psx_mod_register_vblank_plugin("gt2.ram8buffers",
                                         gt2_ram8_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.fulllod",
                                         gt2_fulllod_vblank);
#endif
    (void)psx_mod_register_function_entry_plugin("gt2.gamestart", 0x8005D5C0u,
                                                 gt2_game_start_hook);
    (void)psx_mod_register_vblank_plugin("gt2.silent60fps", gt2_60fps_vblank);
    (void)psx_mod_register_vblank_plugin("gt2.overclock", gt2_overclock_vblank);
    (void)psx_mod_register_activation_plugin("gt2.overclock",
                                             gt2_overclock_activate);
    (void)psx_mod_register_activation_plugin("gt2.display-aspect",
                                             gt2_display_aspect_activate);
}
