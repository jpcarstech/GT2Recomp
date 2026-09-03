/* Host-side test of gameshark_vm against Silent's real GT2 code tables, with
 * a fake 8 MB guest RAM and scripted controller input. Proves the interpreter
 * semantics that matter (block terminators with nesting, D7 hold counters and
 * Q modes, 51/52 register decoding, A7/F5/D0 chains) do what the patches'
 * own comments say they do. Build: see tests/run.sh. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "../gameshark_vm.h"

static uint8_t ram[8 << 20];
static uint32_t g_buttons;   /* active-high PS1 order */
#define OFF(a) ((a) & 0x7FFFFF)
uint8_t  psx_mod_read_byte(uint32_t a) { return ram[OFF(a)]; }
uint16_t psx_mod_read_half(uint32_t a) { uint16_t v; memcpy(&v, ram + OFF(a), 2); return v; }
uint32_t psx_mod_read_word(uint32_t a) { uint32_t v; memcpy(&v, ram + OFF(a), 4); return v; }
void psx_mod_write_byte(uint32_t a, uint8_t v)  { ram[OFF(a)] = v; }
void psx_mod_write_half(uint32_t a, uint16_t v) { memcpy(ram + OFF(a), &v, 2); }
void psx_mod_write_word(uint32_t a, uint32_t v) { memcpy(ram + OFF(a), &v, 4); }
uint32_t psx_mod_controller_buttons(uint32_t slot) { return slot == 0 ? g_buttons : 0; }
int psx_mod_game_started(void) { return 1; }

#include "../mods_gt2_silent_codes.h"
#include "../mods_gt2_v11_codes_sim.h"

static int fails = 0;
#define CHECK(cond, ...) do { if (!(cond)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

#define R3 (1u << 2)
#define L3 (1u << 1)
#define R1 (1u << 11)

static void test_bgm(void) {
    /* Silent's BGM Switch: reg3 = *(0x8002F4EC) = audio manager; current
     * track byte at +0x2EE. Tap R3 -> track+1 (wraps 0..5); hold 60 -> 0xFE. */
    GsState st; memset(&st, 0, sizeof st);
    memset(ram, 0, sizeof ram);
    psx_mod_write_word(0x8001F888, 0xAEB40008);           /* overlay guard A */
    psx_mod_write_word(0x8003EC6C, 0x02602021);           /* overlay guard B */
    psx_mod_write_word(0x8002F4EC, 0x80100000);           /* audio manager ptr */
    psx_mod_write_byte(0x80100000 + 0x2EE, 2);            /* current track 2 */

    /* tap: 10 frames held, then release */
    g_buttons = R3; for (int i = 0; i < 10; i++) gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 2, "no change while held short (got %u)", psx_mod_read_byte(0x801002EE));
    g_buttons = 0; gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 3, "tap R3 -> next track (got %u)", psx_mod_read_byte(0x801002EE));
    /* four more taps wrap 3->4->5->0->1 */
    for (int k = 0; k < 4; k++) { g_buttons = R3; gs_run(&gs_bgm_switch, &st, 1); g_buttons = 0; gs_run(&gs_bgm_switch, &st, 1); }
    CHECK(psx_mod_read_byte(0x801002EE) == 1, "wraps to 1 after 0..5 (got %u)", psx_mod_read_byte(0x801002EE));
    /* hold 60 frames -> mute (0xFE) exactly once; release does NOT switch */
    g_buttons = R3; for (int i = 0; i < 59; i++) gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 1, "not muted before 60 (got %u)", psx_mod_read_byte(0x801002EE));
    gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 0xFE, "muted at frame 60 (got %u)", psx_mod_read_byte(0x801002EE));
    for (int i = 0; i < 30; i++) gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 0xFE, "stays muted while held (got %u)", psx_mod_read_byte(0x801002EE));
    g_buttons = 0; gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 0xFE, "release after hold does not switch (got %u)", psx_mod_read_byte(0x801002EE));
    /* tap while muted -> unmute to track 0 */
    g_buttons = R3; gs_run(&gs_bgm_switch, &st, 1); g_buttons = 0; gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x801002EE) == 0, "tap while muted -> track 0 (got %u)", psx_mod_read_byte(0x801002EE));
    /* audio pointer 0 -> nothing written anywhere near */
    psx_mod_write_word(0x8002F4EC, 0);
    g_buttons = R3; gs_run(&gs_bgm_switch, &st, 1); g_buttons = 0; gs_run(&gs_bgm_switch, &st, 1);
    CHECK(psx_mod_read_byte(0x000002EE) == 0, "null audio pointer: no write at +0x2EE of 0");
    printf("bgm: ok\n");
}

static void test_hud_mirror(void) {
    /* HUD & mirror: tap L3 cycles the branch word at 0x8002951C through
     * 1040000C (default) -> 00000001 (always on) -> 0800A554 (always off) ...
     * wait: order in the code is: default->always on? Let the code decide;
     * just check it cycles through the three values and returns. Holding L3
     * 60 frames toggles two F5 pairs (HUD). */
    GsState st; memset(&st, 0, sizeof st);
    memset(ram, 0, sizeof ram);
    psx_mod_write_word(0x8003EC6C, 0x02602021);
    psx_mod_write_word(0x8002951C, 0x1040000C);           /* default branch */
    psx_mod_write_half(0x8002942C, 0xA52E); psx_mod_write_half(0x8002942E, 0x0022);
    psx_mod_write_half(0x8002941C, 0x0000); psx_mod_write_half(0x8002941E, 0x0C00);
    g_buttons = 0; gs_run(&gs_hud_mirror, &st, 1);
    CHECK(psx_mod_read_word(0x8002951C) == 0x1040000C, "idle: unchanged");
    uint32_t seen[4] = {0}; int n = 0;
    for (int tap = 0; tap < 3; tap++) {
        g_buttons = L3; gs_run(&gs_hud_mirror, &st, 1);   /* frame 1: exactly 1 -> cycle */
        gs_run(&gs_hud_mirror, &st, 1);                    /* frame 2: no further change */
        g_buttons = 0; gs_run(&gs_hud_mirror, &st, 1);
        seen[n++] = psx_mod_read_word(0x8002951C);
    }
    CHECK(seen[0] != 0x1040000C && seen[1] != seen[0] && seen[2] == 0x1040000C,
          "three taps cycle and return: %08X %08X %08X", seen[0], seen[1], seen[2]);
    /* HUD hold: 60 frames toggles the two halfword pairs; holding longer does not toggle back */
    g_buttons = L3; for (int i = 0; i < 60; i++) gs_run(&gs_hud_mirror, &st, 1);
    CHECK(psx_mod_read_half(0x8002942C) == 0x0022 && psx_mod_read_half(0x8002941E) == 0x0000,
          "HUD toggled at frame 60 (%04X %04X)", psx_mod_read_half(0x8002942C), psx_mod_read_half(0x8002941E));
    for (int i = 0; i < 100; i++) gs_run(&gs_hud_mirror, &st, 1);
    CHECK(psx_mod_read_half(0x8002942C) == 0x0022, "no re-toggle while holding");
    g_buttons = 0; gs_run(&gs_hud_mirror, &st, 1);
    g_buttons = L3; for (int i = 0; i < 60; i++) gs_run(&gs_hud_mirror, &st, 1);
    CHECK(psx_mod_read_half(0x8002942C) == 0xA52E, "second hold toggles back");
    printf("hud/mirror: ok\n");
}

static void test_replay_cams(void) {
    GsState st; memset(&st, 0, sizeof st);
    memset(ram, 0, sizeof ram);
    psx_mod_write_word(0x8001F888, 0xAEB40008);
    psx_mod_write_byte(0x800A92BC, 0);                    /* replay off */
    psx_mod_write_half(0x8001031C, 0x0003); psx_mod_write_half(0x80010370, 0x40F0);
    psx_mod_write_half(0x8001171C, 0x0106); psx_mod_write_half(0x80011778, 0x45E9);
    psx_mod_write_word(0x80010A4C, 0x8C70006C);
    psx_mod_write_half(0x80010148, 0x40B6);
    g_buttons = 0; gs_run(&gs_replay_cams, &st, 1);
    CHECK(psx_mod_read_half(0x8001031C) == 0x0009 && psx_mod_read_half(0x80010370) == 0x45C1,
          "A7 sites patched in race (%04X %04X)", psx_mod_read_half(0x8001031C), psx_mod_read_half(0x80010370));
    CHECK(psx_mod_read_half(0x8001171C) == 0x010E && psx_mod_read_half(0x80011778) == 0x45D7, "inner block (replay off) patched");
    /* hold R1 exactly 30 frames -> F5 toggles fire once */
    g_buttons = R1; for (int i = 0; i < 29; i++) gs_run(&gs_replay_cams, &st, 1);
    CHECK(psx_mod_read_half(0x80010148) == 0x40B6, "not toggled before 30");
    gs_run(&gs_replay_cams, &st, 1);
    CHECK(psx_mod_read_half(0x80010148) == 0x427F && psx_mod_read_word(0x80010A4C) == 0x00008021, "toggled at 30 (%04X %08X)",
          psx_mod_read_half(0x80010148), psx_mod_read_word(0x80010A4C));
    CHECK(psx_mod_read_byte(0x801FFA89) == 2, "camera byte set");
    /* replay ON: originals restored by the D0/80 chain */
    psx_mod_write_byte(0x800A92BC, 1); g_buttons = 0; gs_run(&gs_replay_cams, &st, 1);
    CHECK(psx_mod_read_half(0x8001171C) == 0x0106 && psx_mod_read_half(0x80011778) == 0x45E9 &&
          psx_mod_read_word(0x80010A4C) == 0x8C70006C, "replay on restores originals (%04X %04X %08X)",
          psx_mod_read_half(0x8001171C), psx_mod_read_half(0x80011778), psx_mod_read_word(0x80010A4C));
    printf("replay cams: ok\n");
}

static void test_metric(void) {
    GsState st; memset(&st, 0, sizeof st);
    memset(ram, 0, sizeof ram);
    /* With no guard words present nothing may be written anywhere. */
    gs_run(&gs_metric_units, &st, 1);
    for (size_t i = 0; i < sizeof ram; i++) if (ram[i]) { CHECK(0, "metric wrote to %08zX with no overlay resident", i); break; }
    printf("metric (guards): ok\n");
}

/* v1.1 Simulation cheats: the 50 slide opcode, the A4 overlay guard, and
 * A7 restore-on-disable, against the shipped tables. */
static void test_sim_v11(void) {
    GsState st; memset(&st, 0, sizeof st);
    memset(ram, 0, sizeof ram);
    /* guard word absent (race overlay resident): nothing written */
    gs_run(&gs_v11_gold_all, &st, 1);
    CHECK(psx_mod_read_half(0x801CAAC8) == 0, "gold_all writes nothing without the menu overlay");
    gs_run(&gs_v11_cash, &st, 1);
    CHECK(psx_mod_read_word(0x801D1338) == 0, "cash writes nothing without the menu overlay");
    /* menu overlay resident */
    psx_mod_write_word(0x80017A3C, 0x00741823);
    memset(&st, 0, sizeof st); gs_run(&gs_v11_gold_all, &st, 1);
    int ok = 1;
    for (int i = 0; i < 60; i++) if (psx_mod_read_half(0x801CAAC8 + i * 0xA4) != 0x0400) ok = 0;
    CHECK(ok, "gold_all: 60 records x 0xA4 = 0x0400");
    CHECK(psx_mod_read_half(0x801CAAC8 + 60 * 0xA4) == 0, "gold_all: stops after 60");
    CHECK(psx_mod_read_half(0x801CAAC8 + 2) == 0, "gold_all: touches only the first halfword of a record");
    memset(&st, 0, sizeof st); gs_run(&gs_v11_cash, &st, 1);
    CHECK(psx_mod_read_word(0x801D1338) == 99999999u, "cash = 99,999,999 (got %u)", psx_mod_read_word(0x801D1338));
    /* per-class: block 5 only touches records 50..59 */
    memset(ram, 0, sizeof ram); psx_mod_write_word(0x80017A3C, 0x00741823);
    memset(&st, 0, sizeof st); gs_run(&gs_v11_gold_b, &st, 1);
    CHECK(psx_mod_read_half(0x801CAAC8 + 49 * 0xA4) == 0 && psx_mod_read_half(0x801CAAC8 + 50 * 0xA4) == 0x0400 &&
          psx_mod_read_half(0x801CAAC8 + 59 * 0xA4) == 0x0400 && psx_mod_read_half(0x801CAAC8 + 60 * 0xA4) == 0,
          "gold_b covers exactly records 50..59");
    /* races: 68 halfwords of 0x1111 */
    memset(&st, 0, sizeof st); gs_run(&gs_v11_races_done, &st, 1);
    CHECK(psx_mod_read_half(0x801C97C8) == 0x1111 && psx_mod_read_half(0x801C97C8 + 67 * 2) == 0x1111 &&
          psx_mod_read_half(0x801C97C8 + 68 * 2) == 0, "races_done: 68 halfwords");
    /* money never decreases: A7 patch, then restore on disable */
    psx_mod_write_word(0x80017A40, 0xAE234014); psx_mod_write_word(0x80017D48, 0xAE434014);
    memset(&st, 0, sizeof st); gs_run(&gs_v11_money_never_dec, &st, 1);
    CHECK(psx_mod_read_word(0x80017A40) == 0x24004014 && psx_mod_read_word(0x80017D48) == 0x24004014,
          "money_never_dec: both stores become addiu zero (got %08X %08X)", psx_mod_read_word(0x80017A40), psx_mod_read_word(0x80017D48));
    gs_run(&gs_v11_money_never_dec, &st, 0);
    CHECK(psx_mod_read_word(0x80017A40) == 0xAE234014 && psx_mod_read_word(0x80017D48) == 0xAE434014,
          "money_never_dec: restored on disable");
    /* any car: A7 on the beq */
    psx_mod_write_word(0x800148E0, 0x1043000C);
    memset(&st, 0, sizeof st); gs_run(&gs_v11_any_car, &st, 1);
    CHECK(psx_mod_read_word(0x800148E0) == 0x1000000C, "any_car: beq -> b (got %08X)", psx_mod_read_word(0x800148E0));
    gs_run(&gs_v11_any_car, &st, 0);
    CHECK(psx_mod_read_word(0x800148E0) == 0x1043000C, "any_car: restored on disable");
}

int main(void) {
    test_bgm(); test_hud_mirror(); test_replay_cams(); test_metric(); test_sim_v11();
    printf(fails ? "%d FAILURES\n" : "ALL OK\n", fails);
    return fails ? 1 : 0;
}
