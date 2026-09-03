/*
 * gameshark_vm - executes DuckStation-format GameShark patch lists inside a
 * psxrecomp plugin, once per VBlank, with DuckStation's semantics (see
 * docs/duckstation-cheat-format.md). The tables come from
 * tools/cht_to_c.py, verbatim from DuckStation's patch database, so what
 * runs here is Silent's code, not a hand translation of it.
 */
#ifndef GAMESHARK_VM_H
#define GAMESHARK_VM_H
#include <stdint.h>

typedef struct GsCode { uint32_t a; uint32_t v; } GsCode;   /* the two words of one line */

typedef struct GsCheat {
    const char*   name;
    const GsCode* codes;
    uint32_t      count;
} GsCheat;

/* Per-cheat mutable state: D7 hold counters (one per line) and whether the
 * cheat ran last frame (for A7/A8 restore on disable). Zero-initialise. */
#define GS_MAX_LINES 96
typedef struct GsState {
    uint32_t hold[GS_MAX_LINES];
    uint8_t  was_enabled;
    uint8_t  refused;          /* a line the VM does not implement: never runs */
} GsState;

/* Run one frame of `cheat`. `enabled` is the feature's state this frame; a
 * 1 -> 0 transition performs the A7/A8 restore writes. Returns 0 if the
 * cheat was refused (unimplemented opcode), 1 otherwise. */
int gs_run(const GsCheat* cheat, GsState* st, int enabled);

/* The 256 global cheat registers (shared by every cheat, per the spec). */
uint32_t gs_register(uint32_t idx);

#endif
