/*
 * gt2_career.c - the launcher's career panel, read from the player's own
 * memory card.
 *
 * Gran Turismo 2 keeps GT mode in one 4-block "GT2 Game File" (product code
 * BASCUS-94455GAME / -94488GAME in North America, BESCES-02380 / -12380 in
 * Europe, BISCPS-10116 / -10117 in Japan; the Arcade and Simulation discs
 * share it). This reads that block off a raw 128 KB card image, checks the
 * game's own CRC32 over it, and turns the few dozen bytes the dashboard
 * cares about into the launcher's generic save summary (recomp-ui's
 * RecompLauncherCSaveSummary): the car you are driving with its nameplate,
 * credits, prize money, days, races and wins, the career-completion bar,
 * the six licence badges, and the arcade tracks cleared per difficulty.
 *
 * Offsets are relative to the start of the save block (block 1 of the
 * card's data area), verified against real cards:
 *
 *   696   21 x u8   arcade progress per track (bit0 easy, bit1 normal, bit2 hard)
 *   760   u32       days
 *   768   u32       races entered
 *   772   u32       races won
 *   780   u32       sum of finishing positions (races - average finish)
 *   788   u32       prize money won
 *   792   124 bytes career progress, one nibble per event: 0 not entered,
 *                   1..6 best finish (219 events count towards 100%)
 *   5657 / 7297 / 8937 / 10577 / 12217 / 13857
 *                   licence S / IA / IB / IC / A / B: 10 tests, 164 bytes
 *                   apart, byte 0 = 0 none, 1 kid, 2 bronze, 3 silver, 4 gold
 *   15988 u8        cars in the garage
 *   15992 164 x n   garage entries, u32 car id first
 *   32392 u32       credits
 *   32396 u8        garage index of the current car (255 = none)
 *   32412 u32       CRC32 (zlib polynomial) of bytes [0, 32412)
 *
 * Car ids are the game's own 32-bit codes; the install rips the car table
 * (.carinfoe) to assets/img/gt2/carinfo.txt ("<id hex>\t<code>\t<name>")
 * and one nameplate PNG per code, so this file only has to look them up.
 * Nothing of the disc is compiled in.
 *
 * Built into every GT2 exe (CODEGEN_SETUP_SOURCES); registers itself with
 * the runtime's launcher hook at load. GT2_CAREER_TEST builds a standalone
 * checker: gt2_career <card.mcd> [<exe dir>].
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(GT2_CAREER_TEST) || __has_include("recomp_launcher.h")
#define GT2_CAREER_HAVE_LAUNCHER 1
#include "recomp_launcher.h"
#endif
#if !defined(GT2_CAREER_TEST)
#include "mod_plugins.h"
#include "gt2_version.h"
#endif

/* ---- card image ----------------------------------------------------------- */
#define MC_SIZE      (128 * 1024)
#define MC_FRAME     128
#define MC_BLOCK     8192
#define GT2_SAVE_LEN 32768

static const char* const kGt2Serials[] = {
    "SCUS-94455", "SCUS-94488",   /* NTSC-U Arcade / Simulation */
    "SCES-02380", "SCES-12380",   /* PAL */
    "SCPS-10116", "SCPS-10117",   /* NTSC-J */
    NULL
};

static uint32_t rd32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint16_t rd16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }

static uint32_t crc32_zlib(const uint8_t* d, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; ++i) {
        c ^= d[i];
        for (int k = 0; k < 8; ++k) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
    }
    return c ^ 0xFFFFFFFFu;
}

/* Find the GT2 game file on a raw card and copy its 32 KB into `out`.
 * Returns 1 when found and its CRC checks out, 0 for no save, -1 when the
 * file is not a card at all, -2 when the save is there but corrupt. */
static int gt2_card_load(const uint8_t* card, size_t len, uint8_t* out) {
    if (len < MC_SIZE || card[0] != 'M' || card[1] != 'C') return -1;
    for (int i = 1; i < 16; ++i) {
        const uint8_t* f = card + MC_FRAME * i;
        if (f[0] != 0x51) continue;                 /* first block of a file */
        if (rd32(f + 4) != GT2_SAVE_LEN) continue;
        char name[21];
        memcpy(name, f + 10, 20); name[20] = 0;
        int ok = 0;
        for (int k = 0; kGt2Serials[k]; ++k)
            if (strlen(name) >= 12 && strncmp(name + 2, kGt2Serials[k], 10) == 0) { ok = 1; break; }
        if (!ok) continue;
        /* follow the block chain (the game writes them contiguously, but the
         * directory says where they are) */
        int blk = i, got = 0;
        while (blk >= 1 && blk <= 15 && got < 4) {
            memcpy(out + got * MC_BLOCK, card + MC_BLOCK * blk, MC_BLOCK);
            ++got;
            uint16_t next = rd16(card + MC_FRAME * blk + 8);
            if (next == 0xFFFF) break;
            blk = (int)next + 1;
        }
        if (got < 4) return -2;
        if (crc32_zlib(out, 32412) != rd32(out + 32412)) return -2;
        return 1;
    }
    return 0;
}

/* ---- car table --------------------------------------------------------------- */
typedef struct { uint32_t id; char code[8]; char name[64]; } CarRec;

static int car_table_load(const char* exe_dir, CarRec** out) {
    char path[1200];
    snprintf(path, sizeof(path), "%s%sassets/img/gt2/carinfo.txt",
             exe_dir ? exe_dir : "", (exe_dir && exe_dir[0] && exe_dir[strlen(exe_dir) - 1] != '/' &&
                                       exe_dir[strlen(exe_dir) - 1] != '\\') ? "/" : "");
    FILE* f = fopen(path, "rb");
    if (!f) return 0;
    int cap = 1200, n = 0;
    CarRec* recs = (CarRec*)calloc((size_t)cap, sizeof(CarRec));
    char line[256];
    while (recs && fgets(line, sizeof(line), f)) {
        char* a = strchr(line, '\t'); if (!a) continue; *a++ = 0;
        char* b = strchr(a, '\t');    if (!b) continue; *b++ = 0;
        char* e = b + strlen(b);
        while (e > b && (e[-1] == '\n' || e[-1] == '\r')) *--e = 0;
        if (n == cap) {
            cap *= 2;
            CarRec* r2 = (CarRec*)realloc(recs, (size_t)cap * sizeof(CarRec));
            if (!r2) break;
            recs = r2;
        }
        recs[n].id = (uint32_t)strtoul(line, NULL, 16);
        snprintf(recs[n].code, sizeof(recs[n].code), "%s", a);
        snprintf(recs[n].name, sizeof(recs[n].name), "%s", b);
        ++n;
    }
    fclose(f);
    *out = recs;
    return n;
}

static const char kCarAlphabet[] = "-0123456789abcdefghijklmnopqrstuvwxyz";
static void car_code_of(uint32_t id, char out[8]) {
    out[0] = kCarAlphabet[(id >> 24) & 63];
    out[1] = kCarAlphabet[(id >> 18) & 63];
    out[2] = kCarAlphabet[(id >> 12) & 63];
    out[3] = kCarAlphabet[(id >> 6) & 63];
    unsigned low = id & 63;
    out[4] = low == 28 ? 'r' : low == 29 ? 's' : low == 30 ? 't' : (low & 4) ? 'r' : 'n';
    out[5] = 0;
}

/* Name + nameplate code for a car id: exact id first, then any entry of the
 * same car (another body), else the bare code so something still shows. */
static void car_lookup(const CarRec* recs, int n, uint32_t id, char* name, size_t name_cap,
                       char* code, size_t code_cap) {
    char want[8]; car_code_of(id, want);
    snprintf(code, code_cap, "%s", want);
    name[0] = 0;
    for (int i = 0; i < n; ++i)
        if (recs[i].id == id) { snprintf(name, name_cap, "%s", recs[i].name); snprintf(code, code_cap, "%s", recs[i].code); return; }
    for (int i = 0; i < n; ++i)
        if (strncmp(recs[i].code, want, 4) == 0) { snprintf(name, name_cap, "%s", recs[i].name); return; }
    snprintf(name, name_cap, "Car %.4s", want);
}

/* ---- formatting ------------------------------------------------------------- */
static void fmt_thousands(char* out, size_t cap, uint32_t v) {
    char raw[16]; snprintf(raw, sizeof(raw), "%u", v);
    size_t n = strlen(raw), o = 0;
    for (size_t i = 0; i < n && o + 1 < cap; ++i) {
        if (i && (n - i) % 3 == 0 && o + 1 < cap) out[o++] = ',';
        out[o++] = raw[i];
    }
    out[o] = 0;
}

/* ---- the summary ------------------------------------------------------------ */
#if defined(GT2_CAREER_HAVE_LAUNCHER)

static const struct { const char* file; const char* name; } kArcadeTracks[21] = {
    { "roma",       "Rome Circuit" },
    { "roma_short", "Rome Short Course" },
    { "roma_night", "Rome Night" },
    { "seattle",    "Seattle Circuit" },
    { "seatt_s",    "Seattle Short Course" },
    { "s_speed",    "Super Speedway" },
    { "laguna",     "Laguna Seca Raceway" },
    { "test_in2",   "Midfield Raceway" },
    { "parma",      "Apricot Hill Raceway" },
    { "new_parmaS", "Red Rock Valley Speedway" },
    { "tahiti_t",   "Tahiti Road" },
    { "sprint2",    "High Speed Ring" },
    { "autumn",     "Autumn Ring" },
    { "mountain",   "Trial Mountain Circuit" },
    { "testline",   "Deep Forest Raceway" },
    { "circuit",    "Grand Valley Speedway" },
    { "short",      "Grand Valley East" },
    { "highway",    "Special Stage Route 5" },
    { "shortway",   "Clubman Stage Route 5" },
    { "grindel",    "Grindelwald" },
    { "speed",      "Test Course" },
};

static const struct { const char* tag; const char* name; int off; } kLicences[6] = {
    { "S",  "S licence",   5657 },
    { "IA", "I-A licence", 7297 },
    { "IB", "I-B licence", 8937 },
    { "IC", "I-C licence", 10577 },
    { "A",  "A licence",   12217 },
    { "B",  "B licence",   13857 },
};

static RecompLauncherCSaveStat* add_stat(RecompLauncherCSaveSummary* o, const char* group,
                                        const char* label, const char* value, const char* sub, int accent) {
    if (o->num_stats >= RECOMP_LAUNCHER_SAVE_STATS) return NULL;
    RecompLauncherCSaveStat* s = &o->stats[o->num_stats++];
    snprintf(s->group, sizeof(s->group), "%s", group);
    snprintf(s->label, sizeof(s->label), "%s", label);
    snprintf(s->value, sizeof(s->value), "%s", value);
    snprintf(s->sub, sizeof(s->sub), "%s", sub ? sub : "");
    s->accent = accent;
    return s;
}

static void gt2_fill_empty(RecompLauncherCSaveSummary* o, const char* why) {
    o->present = 0;
    snprintf(o->title, sizeof(o->title), "GT MODE CAREER");
    snprintf(o->empty_title, sizeof(o->empty_title), "%s", why);
    snprintf(o->empty_text, sizeof(o->empty_text),
             "Start GT mode and save at the memory card screen; your career shows up here.");
    snprintf(o->empty_image, sizeof(o->empty_image), "img/gt2/mark.png");
    snprintf(o->badges_label, sizeof(o->badges_label), "LICENSES");
    o->num_badges = 6;
    for (int i = 0; i < 6; ++i) {
        snprintf(o->badges[i].label, sizeof(o->badges[i].label), "%s", kLicences[i].tag);
        snprintf(o->badges[i].image, sizeof(o->badges[i].image), "img/gt2/lic_%s.png", kLicences[i].tag);
        o->badges[i].tier = 0;
    }
}

int gt2_career_summary(const char* card_path, const char* exe_dir, RecompLauncherCSaveSummary* o) {
    if (!card_path || !card_path[0] || !o) return 0;
    memset(o, 0, sizeof(*o));
    FILE* f = fopen(card_path, "rb");
    if (!f) return 0;
    uint8_t* card = (uint8_t*)malloc(MC_SIZE);
    if (!card) { fclose(f); return 0; }
    size_t got = fread(card, 1, MC_SIZE, f);
    fclose(f);
    uint8_t* sv = (uint8_t*)malloc(GT2_SAVE_LEN);
    if (!sv) { free(card); return 0; }
    int rc = gt2_card_load(card, got, sv);
    free(card);
    if (rc < 0) {
        free(sv);
        if (rc == -1) return 0;                    /* not a card: the launcher says "no memory card" */
        gt2_fill_empty(o, "SAVE DATA COULD NOT BE READ");
        return 1;
    }
    if (rc == 0) { free(sv); gt2_fill_empty(o, "NO SAVE DATA ON THIS CARD"); return 1; }

    o->present = 1;
    snprintf(o->title, sizeof(o->title), "GT MODE CAREER");

    /* the car */
    const unsigned ncars = sv[15988];
    const unsigned cur = sv[32396];
    const uint32_t days = rd32(sv + 760);
    CarRec* cars = NULL;
    const int ncar_recs = car_table_load(exe_dir, &cars);
    snprintf(o->hero_label, sizeof(o->hero_label), "CURRENT CAR");
    if (cur != 255 && cur < ncars && 15992 + 164 * (cur + 1) <= GT2_SAVE_LEN) {
        const uint32_t id = rd32(sv + 15992 + 164 * cur);
        char name[64], code[8];
        car_lookup(cars, ncar_recs, id, name, sizeof(name), code, sizeof(code));
        snprintf(o->hero_text, sizeof(o->hero_text), "%s", name);
        snprintf(o->hero_image, sizeof(o->hero_image), "img/gt2/carlogo/%s.png", code);
    } else {
        snprintf(o->hero_text, sizeof(o->hero_text), "No car yet");
    }
    free(cars);
    snprintf(o->hero_sub, sizeof(o->hero_sub), "Garage %u car%s  \xC2\xB7  Day %u",
             ncars, ncars == 1 ? "" : "s", days);

    /* finances / racing */
    char v[24], sub[32], v2[32];
    fmt_thousands(v, sizeof(v), rd32(sv + 32392));
    snprintf(v2, sizeof(v2), "Cr. %s", v);
    add_stat(o, "FINANCES", "Credits", v2, NULL, 1);
    fmt_thousands(v, sizeof(v), rd32(sv + 788));
    snprintf(v2, sizeof(v2), "Cr. %s", v);
    add_stat(o, "FINANCES", "Prize money won", v2, NULL, 0);
    fmt_thousands(v, sizeof(v), days);
    add_stat(o, "FINANCES", "Days", v, NULL, 0);

    const uint32_t races = rd32(sv + 768), wins = rd32(sv + 772), sum_pos = rd32(sv + 780);
    fmt_thousands(v, sizeof(v), races);
    add_stat(o, "RACING", "Races", v, NULL, 0);
    fmt_thousands(v, sizeof(v), wins);
    if (races) snprintf(sub, sizeof(sub), "%u%%", (unsigned)((wins * 100 + races / 2) / races));
    else       sub[0] = 0;
    add_stat(o, "RACING", "Wins", v, sub, 0);
    if (races && sum_pos) snprintf(v, sizeof(v), "%.1f", (double)sum_pos / (double)races);
    else                  snprintf(v, sizeof(v), "-");
    add_stat(o, "RACING", "Average finish", v, NULL, 0);

    /* career progress: 219 events count; each finish adds 1/position */
    {
        double score = 0.0;
        unsigned won = 0, entered = 0;
        for (int i = 0; i < 248; ++i) {
            const unsigned nib = (i & 1) ? (sv[792 + i / 2] >> 4) : (sv[792 + i / 2] & 15);
            if (nib == 0 || nib > 6) continue;
            ++entered;
            if (nib == 1) ++won;
            score += 1.0 / (double)nib;
        }
        double pct = score * 100.0 / 219.0;
        if (pct > 100.0) pct = 100.0;
        RecompLauncherCSaveBar* b = &o->bars[o->num_bars++];
        snprintf(b->label, sizeof(b->label), "CAREER PROGRESS");
        b->fraction = (float)(pct / 100.0);
        snprintf(b->value, sizeof(b->value), "%.1f%%", pct);
        snprintf(b->sub, sizeof(b->sub), "%u of 219 events won", won);
        snprintf(b->sub_right, sizeof(b->sub_right), "%u entered", entered);
    }

    /* licences */
    snprintf(o->badges_label, sizeof(o->badges_label), "LICENSES");
    for (int i = 0; i < 6; ++i) {
        RecompLauncherCSaveBadge* bd = &o->badges[o->num_badges++];
        snprintf(bd->label, sizeof(bd->label), "%s", kLicences[i].name);
        snprintf(bd->image, sizeof(bd->image), "img/gt2/lic_%s.png", kLicences[i].tag);
        int lowest = 4, golds = 0;
        for (int t = 0; t < 10; ++t) {
            const int r = sv[kLicences[i].off + 164 * t];
            if (r < lowest) lowest = r;
            if (r == 4) ++golds;
        }
        /* the licence is held once every test is at least bronze; the badge
         * shows the weakest result, the caption the metal - or, while it is
         * still being earned, how many of the ten tests are passed */
        int passed = 0;
        for (int t = 0; t < 10; ++t) if (sv[kLicences[i].off + 164 * t] >= 2) ++passed;
        bd->tier = lowest >= 4 ? 3 : lowest == 3 ? 2 : lowest == 2 ? 1 : 0;
        if (bd->tier == 3)       snprintf(bd->sub, sizeof(bd->sub), "GOLD");
        else if (bd->tier == 2)  snprintf(bd->sub, sizeof(bd->sub), "SILVER");
        else if (bd->tier == 1)  snprintf(bd->sub, sizeof(bd->sub), "BRONZE");
        else if (passed > 0)     snprintf(bd->sub, sizeof(bd->sub), "%d / 10", passed);
        else                     snprintf(bd->sub, sizeof(bd->sub), "\xE2\x80\x93");
        if (bd->tier) snprintf(bd->label, sizeof(bd->label), "%s: %d gold", kLicences[i].name, golds);
        else          snprintf(bd->label, sizeof(bd->label), "%s: %d of 10 tests passed", kLicences[i].name, passed);
    }

    /* arcade mode: per track, the difficulties won (each win is what unlocks
     * the next track and difficulty in the game) */
    {
        unsigned easy = 0, normal = 0, hard = 0;
        snprintf(o->tiles_label, sizeof(o->tiles_label), "ARCADE MODE");
        for (int i = 0; i < 21; ++i) {
            RecompLauncherCSaveTile* t = &o->tiles[o->num_tiles++];
            const unsigned bits = sv[696 + i] & 7;
            snprintf(t->label, sizeof(t->label), "%s", kArcadeTracks[i].name);
            snprintf(t->image, sizeof(t->image), "img/gt2/map_%s.png", kArcadeTracks[i].file);
            t->pips = (int)((bits & 1) + ((bits >> 1) & 1) + ((bits >> 2) & 1));
            t->pips_max = 3;
            if (bits & 1) ++easy;
            if (bits & 2) ++normal;
            if (bits & 4) ++hard;
            if (bits == 7)      snprintf(t->detail, sizeof(t->detail), "Won on Easy, Normal and Hard");
            else if (bits == 0) snprintf(t->detail, sizeof(t->detail), "No win yet");
            else snprintf(t->detail, sizeof(t->detail), "Won on%s%s%s",
                          (bits & 1) ? " Easy" : "", (bits & 2) ? ((bits & 1) ? ", Normal" : " Normal") : "",
                          (bits & 4) ? ((bits & 3) ? ", Hard" : " Hard") : "");
        }
        unsigned cleared = 0;
        for (int i = 0; i < 21; ++i) if ((sv[696 + i] & 7) == 7) ++cleared;
        snprintf(o->tiles_sub, sizeof(o->tiles_sub), "Tracks cleared\n%u / 21", cleared);
        snprintf(o->tiles_hint, sizeof(o->tiles_hint),
                 "Wins per track: Easy %u, Normal %u, Hard %u", easy, normal, hard);
    }
    free(sv);
    return 1;
}

#if !defined(GT2_CAREER_TEST)
static const PsxLauncherDashboard kGt2Dashboard = {
    /* console_dashboard */ 1,
    /* logo_path         */ "img/gt2/logo.png",
    /* backdrop_path     */ "img/gt2/backdrop.png",
    /* accent            */ "#f79400",
    /* footer_text       */ "GT2Recomp " GT2RECOMP_VERSION,
    /* save_summary      */ gt2_career_summary,
};

PSX_MOD_CONSTRUCTOR(gt2_register_launcher_dashboard) {
    (void)psx_mod_set_launcher_dashboard(&kGt2Dashboard);
}
#endif

#if defined(GT2_CAREER_TEST)
int main(int argc, char** argv) {
    if (argc < 2) { fprintf(stderr, "usage: gt2_career <card.mcd> [<exe dir>]\n"); return 2; }
    RecompLauncherCSaveSummary s;
    int rc = gt2_career_summary(argv[1], argc > 2 ? argv[2] : "", &s);
    printf("rc=%d present=%d title=\"%s\"\n", rc, s.present, s.title);
    if (!rc) return 1;
    if (!s.present) { printf("empty: %s / %s / %s\n", s.empty_title, s.empty_text, s.empty_image); }
    printf("hero: [%s] %s | %s | %s\n", s.hero_label, s.hero_text, s.hero_sub, s.hero_image);
    for (int i = 0; i < s.num_stats; ++i)
        printf("stat %-9s %-16s %-14s %s%s\n", s.stats[i].group, s.stats[i].label, s.stats[i].value,
               s.stats[i].sub, s.stats[i].accent ? "  (accent)" : "");
    for (int i = 0; i < s.num_bars; ++i)
        printf("bar  %s %.3f %s | %s\n", s.bars[i].label, s.bars[i].fraction, s.bars[i].value, s.bars[i].sub);
    for (int i = 0; i < s.num_badges; ++i)
        printf("badge %-12s tier=%d %-8s %s\n", s.badges[i].label, s.badges[i].tier, s.badges[i].sub, s.badges[i].image);
    printf("tiles %s (%s)\n", s.tiles_label, s.tiles_sub);
    for (int i = 0; i < s.num_tiles; ++i)
        printf("  %2d/%d %-26s %s\n", s.tiles[i].pips, s.tiles[i].pips_max, s.tiles[i].label, s.tiles[i].image);
    return 0;
}
#endif
#endif /* GT2_CAREER_HAVE_LAUNCHER */
