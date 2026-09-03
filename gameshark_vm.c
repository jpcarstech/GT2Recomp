/* gameshark_vm.c - see gameshark_vm.h and docs/duckstation-cheat-format.md. */
#include "gameshark_vm.h"
#include "mod_plugins.h"
#include <stdio.h>
#include <string.h>

static uint32_t g_regs[256];
uint32_t gs_register(uint32_t idx) { return g_regs[idx & 0xFF]; }

#define ADDR(a) (0x80000000u | ((a) & 0x00FFFFFFu))

static uint32_t rd(uint32_t addr, int width) {
    switch (width) {
        case 1:  return psx_mod_read_byte(addr);
        case 2:  return psx_mod_read_half(addr);
        default: return psx_mod_read_word(addr);
    }
}
static void wr(uint32_t addr, int width, uint32_t v) {
    switch (width) {
        case 1:  psx_mod_write_byte(addr, (uint8_t)v);  break;
        case 2:  psx_mod_write_half(addr, (uint16_t)v); break;
        default: psx_mod_write_word(addr, v);           break;
    }
}
static uint32_t mask(int width) { return width == 1 ? 0xFFu : width == 2 ? 0xFFFFu : 0xFFFFFFFFu; }

/* DuckStation's button bit order for D4/D7 (NOT the PS1 SIO order). */
static uint32_t ds_buttons(void) {
    const uint32_t p = psx_mod_controller_buttons(0);   /* player 1, active-high, PS1 order */
    uint32_t b = 0;
    if (p & (1u << 8))  b |= 0x000001;  /* L2       */
    if (p & (1u << 9))  b |= 0x000002;  /* R2       */
    if (p & (1u << 10)) b |= 0x000004;  /* L1       */
    if (p & (1u << 11)) b |= 0x000008;  /* R1       */
    if (p & (1u << 12)) b |= 0x000010;  /* Triangle */
    if (p & (1u << 13)) b |= 0x000020;  /* Circle   */
    if (p & (1u << 14)) b |= 0x000040;  /* Cross    */
    if (p & (1u << 15)) b |= 0x000080;  /* Square   */
    if (p & (1u << 0))  b |= 0x000100;  /* Select   */
    if (p & (1u << 1))  b |= 0x000200;  /* L3       */
    if (p & (1u << 2))  b |= 0x000400;  /* R3       */
    if (p & (1u << 3))  b |= 0x000800;  /* Start    */
    if (p & (1u << 4))  b |= 0x001000;  /* Up       */
    if (p & (1u << 5))  b |= 0x002000;  /* Right    */
    if (p & (1u << 6))  b |= 0x004000;  /* Down     */
    if (p & (1u << 7))  b |= 0x008000;  /* Left     */
    return b;
}

/* "activate next code" family: a run of these is an AND gating ONE code. */
static int is_next_code_conditional(uint32_t op) {
    return (op >= 0xD0 && op <= 0xD3) || (op >= 0xE0 && op <= 0xE3) ||
           (op >= 0xA0 && op <= 0xA3) || op == 0xD4;
}
/* Block conditionals: gate everything to the matching 00000000 FFFF. */
static int is_block_conditional(uint32_t op) {
    return op == 0xC0 || (op >= 0xC3 && op <= 0xC6) || op == 0xA4 ||
           op == 0xD7 || op == 0x52;
}
static int is_terminator(const GsCode* c) { return c->a == 0 && (c->v & 0xFFFFu) == 0xFFFFu; }

/* DuckStation's GetNextNonConditionalInstruction: index one PAST the first
 * non-conditional line after `i`. */
static uint32_t next_non_conditional(const GsCheat* ch, uint32_t i) {
    for (i = i + 1; i < ch->count; ++i)
        if (!is_next_code_conditional(ch->codes[i].a >> 24)) return i + 1;
    return ch->count;
}
/* Index one past the terminator that closes the block opened at `i`,
 * counting nested blocks; end of cheat if none. */
static uint32_t block_end(const GsCheat* ch, uint32_t i) {
    int depth = 1;
    for (i = i + 1; i < ch->count; ++i) {
        const uint32_t op = ch->codes[i].a >> 24;
        if (is_terminator(&ch->codes[i])) { if (--depth == 0) return i + 1; }
        else if (is_block_conditional(op)) depth++;
    }
    return ch->count;
}

static int cmp(uint32_t x, uint32_t y, int test) {
    switch (test) {   /* the 52-series test nibble; also used for C/D/E/A families */
        case 0:  return x == y;
        case 1:  return x != y;
        case 2:  return x >  y;
        case 3:  return x >= y;
        case 4:  return x <  y;
        case 5:  return x <= y;
        case 6:  return (x & y) == y;
        case 7:  return (x & y) != y;
        case 10: return (x & y) == x;
        case 11: return (x & y) != x;
        default: return 0;
    }
}

static int reg52(const GsCode* c) {
    const uint32_t hi = (c->a >> 20) & 0xF, test = (c->a >> 16) & 0xF;
    const uint32_t yy = (c->a >> 8) & 0xFF, xx = c->a & 0xFF;
    const int width = (hi < 4) ? 1 : (hi < 8) ? 2 : 4;
    const uint32_t m = mask(width);
    const uint32_t kind = hi & 3;     /* 0 reg/reg, 1 reg/const, 2 indirect, 3 reg/address */
    uint32_t x, y;
    if (test == 8 || test == 9) {     /* ranges: reg XX vs (hi=T, lo=Z) halves of v */
        const uint32_t z = width == 1 ? (c->v & 0xFF) : (c->v & 0xFFFF);
        const uint32_t t = width == 1 ? ((c->v >> 16) & 0xFF) : ((c->v >> 16) & 0xFFFF);
        x = (kind == 2) ? rd(g_regs[xx], width) : (g_regs[xx] & m);
        return test == 8 ? (x > z && x < t) : (x >= z && x <= t);
    }
    switch (kind) {
        case 0:  x = g_regs[yy] & m; y = g_regs[xx] & m; break;              /* "If RegYY op RegXX" */
        case 1:  x = g_regs[xx] & m; y = c->v & m; break;
        case 2:  if (test <= 5) { x = rd(g_regs[yy], width); y = rd(g_regs[xx], width); }
                 else           { x = rd(g_regs[xx], width); y = c->v & m; }
                 break;
        default: x = g_regs[xx] & m; y = rd(ADDR(c->v), width); break;
    }
    return cmp(x, y, (int)test);
}

static void reg51(const GsCode* c) {
    const uint32_t op = (c->a >> 16) & 0xFF;
    const uint32_t yy = (c->a >> 8) & 0xFF, xx = c->a & 0xFF;
    if (op >= 0xC0 && op <= 0xCA) {
        const uint32_t rr = c->v & 0xFF; uint32_t r = 0;
        const uint32_t X = g_regs[xx], Y = g_regs[yy];
        switch (op) {
            case 0xC0: r = Y + X; break;   case 0xC1: r = Y - X; break;
            case 0xC2: r = Y * X; break;   case 0xC3: r = X ? Y / X : 0; break;
            case 0xC4: r = X ? Y % X : Y; break;
            case 0xC5: r = Y & X; break;   case 0xC6: r = Y | X; break;
            case 0xC7: r = Y ^ X; break;   case 0xC8: r = ~X; break;
            case 0xC9: r = X << yy; break; case 0xCA: r = X >> yy; break;
        }
        g_regs[rr] = r; return;
    }
    if (op >= 0xD0 && op <= 0xD2) {
        const uint32_t Y = g_regs[yy];
        g_regs[xx] = op == 0xD0 ? (Y & c->v) : op == 0xD1 ? (Y | c->v) : (Y ^ c->v);
        return;
    }
    const int width = (op < 0x40) ? 1 : (op < 0x80) ? 2 : 4;
    const uint32_t m = mask(width);
    switch (op & 0x0F) {
        case 0: wr(ADDR(c->v), width, g_regs[xx] & m); break;              /* mem[V] = reg XX */
        case 1: g_regs[xx] = rd(ADDR(c->v), width); break;                  /* reg XX = mem[V] */
        case 2: wr(g_regs[xx], width, c->v & m); break;                     /* mem[reg XX] = V */
        case 3: g_regs[xx] = (g_regs[yy] + c->v) & m; break;                /* reg XX = reg YY + V */
        case 4: wr(g_regs[xx], width, (g_regs[yy] + c->v) & m); break;      /* mem[reg XX] = reg YY + V */
        case 5: g_regs[xx] = c->v & m; break;                               /* reg XX = V */
        case 6: g_regs[xx] = rd(g_regs[yy] + c->v, width); break;           /* reg XX = mem[reg YY + V] */
        default: break;                                                     /* 7: refused at build */
    }
}

int gs_run(const GsCheat* ch, GsState* st, int enabled) {
    if (st->refused) return 0;
    if (ch->count > GS_MAX_LINES) {
        fprintf(stderr, "gameshark_vm: [%s] has %u lines (max %d) - refused\n",
                ch->name, ch->count, GS_MAX_LINES);
        st->refused = 1; return 0;
    }
    if (!enabled) {
        if (st->was_enabled) {
            /* A7/A8 restore: put the original halfword/byte back where the
             * patched value is still present. */
            for (uint32_t i = 0; i < ch->count; ++i) {
                const GsCode* c = &ch->codes[i];
                const uint32_t op = c->a >> 24;
                if (op == 0xA7) {
                    const uint32_t a = ADDR(c->a), old = c->v >> 16, nw = c->v & 0xFFFF;
                    if (psx_mod_read_half(a) == nw) psx_mod_write_half(a, (uint16_t)old);
                } else if (op == 0xA8) {
                    const uint32_t a = ADDR(c->a), old = (c->v >> 8) & 0xFF, nw = c->v & 0xFF;
                    if (psx_mod_read_byte(a) == nw) psx_mod_write_byte(a, (uint8_t)old);
                }
            }
            memset(st->hold, 0, sizeof(st->hold));
            st->was_enabled = 0;
        }
        return 1;
    }
    st->was_enabled = 1;

    const uint32_t buttons = ds_buttons();
    uint32_t i = 0;
    while (i < ch->count) {
        const GsCode* c = &ch->codes[i];
        const uint32_t op = c->a >> 24, a = ADDR(c->a), v = c->v;
        switch (op) {
        case 0x00: i++; break;                                   /* nop / terminator */
        case 0x30: psx_mod_write_byte(a, (uint8_t)v); i++; break;
        case 0x31: psx_mod_write_byte(a, (uint8_t)(psx_mod_read_byte(a) | v)); i++; break;
        case 0x32: psx_mod_write_byte(a, (uint8_t)(psx_mod_read_byte(a) & ~v)); i++; break;
        case 0x80: psx_mod_write_half(a, (uint16_t)v); i++; break;
        case 0x81: psx_mod_write_half(a, (uint16_t)(psx_mod_read_half(a) | v)); i++; break;
        case 0x82: psx_mod_write_half(a, (uint16_t)(psx_mod_read_half(a) & ~v)); i++; break;
        case 0x90: psx_mod_write_word(a, v); i++; break;
        case 0x91: psx_mod_write_word(a, psx_mod_read_word(a) | v); i++; break;
        case 0x92: psx_mod_write_word(a, psx_mod_read_word(a) & ~v); i++; break;
        case 0x10: psx_mod_write_half(a, (uint16_t)(psx_mod_read_half(a) + v)); i++; break;
        case 0x11: psx_mod_write_half(a, (uint16_t)(psx_mod_read_half(a) - v)); i++; break;
        case 0x20: psx_mod_write_byte(a, (uint8_t)(psx_mod_read_byte(a) + v)); i++; break;
        case 0x21: psx_mod_write_byte(a, (uint8_t)(psx_mod_read_byte(a) - v)); i++; break;
        case 0x60: psx_mod_write_word(a, psx_mod_read_word(a) + v); i++; break;
        case 0x61: psx_mod_write_word(a, psx_mod_read_word(a) - v); i++; break;
        case 0x1F: psx_mod_write_half(0x1F800000u | (c->a & 0x3FFu), (uint16_t)v); i++; break;
        case 0xA5: psx_mod_write_word(0x1F800000u | (c->a & 0x3FFu), v); i++; break;
        case 0xA6: case 0xA7: {
            const uint32_t old = v >> 16, nw = v & 0xFFFF;
            if (psx_mod_read_half(a) == old) psx_mod_write_half(a, (uint16_t)nw);
            i++; break;
        }
        case 0xA8: {
            const uint32_t old = (v >> 8) & 0xFF, nw = v & 0xFF;
            if (psx_mod_read_byte(a) == old) psx_mod_write_byte(a, (uint8_t)nw);
            i++; break;
        }
        case 0xF5: {
            const uint32_t y = v >> 16, z = v & 0xFFFF, cur = psx_mod_read_half(a);
            if (cur == y) psx_mod_write_half(a, (uint16_t)z);
            else if (cur == z) psx_mod_write_half(a, (uint16_t)y);
            i++; break;
        }
        /* 5000CCSS IIII - slide: repeat the NEXT code (80 halfword or 30
         * byte write) CC times, address += SS and value += IIII each step.
         * DuckStation's Slide handler; the pair is consumed together. */
        case 0x50: {
            const uint32_t count = (c->a >> 8) & 0xFF, step = c->a & 0xFF;
            const uint32_t inc = v & 0xFFFF;
            if (i + 1 >= ch->count) { i++; break; }
            const GsCode* w = &ch->codes[i + 1];
            const uint32_t wop = w->a >> 24;
            uint32_t wa = ADDR(w->a), wv = w->v;
            for (uint32_t k = 0; k < count; ++k) {
                if (wop == 0x80)      psx_mod_write_half(wa, (uint16_t)wv);
                else if (wop == 0x30) psx_mod_write_byte(wa, (uint8_t)wv);
                else break;
                wa += step; wv += inc;
            }
            i += 2; break;
        }
        /* ---- activate-next-code conditionals ---- */
        case 0xD0: case 0xD1: case 0xD2: case 0xD3:
        case 0xE0: case 0xE1: case 0xE2: case 0xE3:
        case 0xA0: case 0xA1: case 0xA2: case 0xA3: {
            const int width = (op & 0xF0) == 0xD0 ? 2 : (op & 0xF0) == 0xE0 ? 1 : 4;
            static const int tests[4] = { 0, 1, 4, 2 };   /* ==, !=, <, > */
            const int ok = cmp(rd(a, width), v & mask(width), tests[op & 3]);
            i = ok ? i + 1 : next_non_conditional(ch, i);
            break;
        }
        /* ---- block conditionals ---- */
        case 0xC0: i = (psx_mod_read_half(a) == (v & 0xFFFF)) ? i + 1 : block_end(ch, i); break;
        case 0xC3: i = (psx_mod_read_byte(a) <  (v & 0xFF))   ? i + 1 : block_end(ch, i); break;
        case 0xC4: i = (psx_mod_read_byte(a) >  (v & 0xFF))   ? i + 1 : block_end(ch, i); break;
        case 0xC5: i = (psx_mod_read_half(a) <  (v & 0xFFFF)) ? i + 1 : block_end(ch, i); break;
        case 0xC6: i = (psx_mod_read_half(a) >  (v & 0xFFFF)) ? i + 1 : block_end(ch, i); break;
        case 0xA4: i = (psx_mod_read_word(a) == v)            ? i + 1 : block_end(ch, i); break;
        case 0xD7: {
            /* D7PQRRRR TTYYYYYY - see docs/duckstation-cheat-format.md */
            const uint32_t P = (c->a >> 20) & 0xF, Q = (c->a >> 16) & 0xF;
            const uint32_t frames = c->a & 0xFFFF;
            const uint32_t tt = v >> 24, bits = v & 0xFFFFFF;
            const int pressed = P == 0 ? ((buttons & bits) == bits) : ((buttons & bits) == 0);
            uint32_t* hold = &st->hold[i];
            *hold = pressed ? *hold + 1 : 0;
            if (tt) g_regs[tt] = *hold;
            int ok = pressed;
            if (ok) switch (Q) {
                case 0: break;
                case 1: ok = (*hold == frames); break;
                case 2: ok = (*hold <  frames); break;   /* derived from Silent's BGM code */
                case 3: ok = (*hold >= frames); break;
                case 4: ok = (*hold != frames); break;
                default: ok = 0; break;
            }
            i = ok ? i + 1 : block_end(ch, i);
            break;
        }
        case 0x52: i = reg52(c) ? i + 1 : block_end(ch, i); break;
        case 0x51: reg51(c); i++; break;
        default:
            fprintf(stderr, "gameshark_vm: [%s] line %u: opcode %02X not implemented - cheat refused\n",
                    ch->name, i, op);
            st->refused = 1; return 0;
        }
    }
    return 1;
}
