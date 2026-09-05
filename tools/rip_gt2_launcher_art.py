#!/usr/bin/env python3
"""rip_gt2_launcher_art.py - the launcher's Gran Turismo 2 artwork, from the disc.

    rip_gt2_launcher_art.py <GT2 disc .bin> <assets/img/gt2 dir> [--quiet]

Everything the redesigned launcher draws that looks like Gran Turismo 2 is
read out of the player's own disc image at install time by this script;
none of it is shipped with the project. From GT2.VOL (the GTFS archive the
game keeps all its data in - see rip_gt2_title_art.py for the walk) it pulls:

  logo.png          the GT mark and "GRAN TURISMO 2 / THE REAL DRIVING
                    SIMULATOR" wordmark off the top-menu screen
                    (arcade/arc_topmenu, four 512x120 true-colour strips
                    that stack into the 512x480 screen), with a soft
                    elliptical edge baked into the alpha so it sits on any
                    black header
  mark.png          the GT mark alone (empty-save panel)
  backdrop.png      the upper part of that screen (mark + light streaks, no
                    text) with a wide soft edge, for a faint panel backdrop
  lic_<S|IA|IB|IC|A|B>.png
                    the six licence badges from arcade/gt_items.tim. That
                    TIM has no palette (the game tints it), so these are
                    grey-with-alpha masks; the launcher colours them by the
                    tier the save has earned
  map_<course>.png  the 21 arcade-mode course maps (crsmap/<course>.tim.gz,
                    96x96, white outline on transparent)
  carlogo/<code><v>.png
                    one nameplate per car in the game's car table
                    (.carinfoe): the export-market plate where the disc has
                    one, else the Japanese one; <code> is the four-letter
                    car code, <v> the body variant (n normal, r racing
                    modification, s/t special)
  carinfo.txt       "<car id hex>\\t<code><v>\\t<name>" per car, so the
                    launcher can turn the ids stored in a save into names
                    and nameplates

Only the standard library is used: the install runs this from an embedded
Python. PNGs are written directly (zlib), no image library needed.
"""
import gzip, io, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rip_gt2_title_art import Disc, gtfs_files  # noqa: E402

# Arcade-mode course order as the game keeps it in the save's 21 track
# bytes (Rome first, Test Course last), with the crsmap file each one uses.
ARCADE_COURSES = [
    ('roma',       'Rome Circuit'),
    ('roma_short', 'Rome Short Course'),
    ('roma_night', 'Rome Night'),
    ('seattle',    'Seattle Circuit'),
    ('seatt_s',    'Seattle Short Course'),
    ('s_speed',    'Super Speedway'),
    ('laguna',     'Laguna Seca Raceway'),
    ('test_in2',   'Midfield Raceway'),
    ('parma',      'Apricot Hill Raceway'),
    ('new_parmaS', 'Red Rock Valley Speedway'),
    ('tahiti_t',   'Tahiti Road'),
    ('sprint2',    'High Speed Ring'),
    ('autumn',     'Autumn Ring'),
    ('mountain',   'Trial Mountain Circuit'),
    ('testline',   'Deep Forest Raceway'),
    ('circuit',    'Grand Valley Speedway'),
    ('short',      'Grand Valley East'),
    ('highway',    'Special Stage Route 5'),
    ('shortway',   'Clubman Stage Route 5'),
    ('grindel',    'Grindelwald'),
    ('speed',      'Test Course'),
]

CAR_ALPHABET = '-0123456789abcdefghijklmnopqrstuvwxyz'


# ---- PNG ---------------------------------------------------------------------
def write_png(path, w, h, rgba_rows):
    """rgba_rows: list of h bytes objects, each 4*w bytes."""
    raw = b''.join(b'\0' + r for r in rgba_rows)
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


# ---- TIM ---------------------------------------------------------------------
def c15(v, stp_alpha=255):
    """PS1 15-bit colour -> RGBA. 0000h is the transparent texel; STP=1 texels
    are the ones the game blends, but for launcher art they are drawn solid
    (nameplate edges are anti-aliased with STP, not see-through)."""
    if v == 0:
        return (0, 0, 0, 0)
    r, g, b = v & 31, (v >> 5) & 31, (v >> 10) & 31
    return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2), stp_alpha if (v >> 15) else 255)


def maybe_gunzip(data):
    if data[:2] == b'\x1f\x8b':
        return gzip.GzipFile(fileobj=io.BytesIO(data)).read()
    return data


def tim_images(data):
    """Every TIM in data (concatenated), each as (w, h, rows) with rows a list
    of RGBA-tuple lists. 4/8-bit TIMs use their first palette; a 4-bit TIM
    without a palette (gt_items) becomes a grey ramp with index 0 clear."""
    data = maybe_gunzip(data)
    out = []
    pos = 0
    while pos + 20 <= len(data):
        magic, flags = struct.unpack_from('<II', data, pos)
        if magic != 0x10 or (flags & ~0xF):
            break
        mode = flags & 7
        p = pos + 8
        pal = None
        if flags & 8:
            bnum = struct.unpack_from('<I', data, p)[0]
            n = 16 if mode == 0 else 256
            ent = struct.unpack_from('<%dH' % n, data, p + 12)
            pal = [c15(v) for v in ent]
            p += bnum
        bnum2, x, y, w, h = struct.unpack_from('<IHHHH', data, p)
        px = data[p + 12:p + bnum2]
        stride = w * 2
        rows = []
        if mode == 0:
            W = w * 4
            if pal is None:
                pal = [(0, 0, 0, 0)] + [(i * 17, i * 17, i * 17, 255) for i in range(1, 16)]
            for yy in range(h):
                line = px[yy * stride:yy * stride + stride]
                r = []
                for b in line:
                    r.append(pal[b & 15]); r.append(pal[b >> 4])
                rows.append(r[:W])
        elif mode == 1:
            W = w * 2
            for yy in range(h):
                rows.append([pal[b] for b in px[yy * stride:yy * stride + W]])
        elif mode == 2:
            W = w
            for yy in range(h):
                vals = struct.unpack_from('<%dH' % W, px, yy * stride)
                rows.append([c15(v) for v in vals])
        else:
            break
        out.append((W, h, rows))
        pos = p + bnum2
        while pos + 4 <= len(data) and data[pos:pos + 4] == b'\0\0\0\0':
            pos += 4
    return out


def rows_to_png(path, rows):
    h = len(rows); w = len(rows[0]) if h else 0
    write_png(path, w, h, [bytes(c for px in r for c in px) for r in rows])


def crop(rows, x0, y0, x1, y1):
    return [r[x0:x1] for r in rows[y0:y1]]


def bbox_alpha(rows):
    h = len(rows); w = len(rows[0])
    xs = [x for y in range(h) for x in range(w) if rows[y][x][3]]
    ys = [y for y in range(h) for x in range(w) if rows[y][x][3]]
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1) if xs else (0, 0, w, h)


def soft_ellipse(rows, inner=0.55, rx=0.7, ry=0.8):
    """Multiply alpha by a radial falloff: 1 inside `inner` of the ellipse
    (rx, ry of the half-size), 0 at its edge. Bakes the CSS mask the mockup
    used, so the launcher can blit the PNG as is."""
    h = len(rows); w = len(rows[0])
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    ax, ay = cx * rx, cy * ry
    out = []
    for y in range(h):
        dy = (y - cy) / ay if ay else 0
        line = []
        for x in range(w):
            dx = (x - cx) / ax if ax else 0
            d = (dx * dx + dy * dy) ** 0.5
            k = 1.0 if d <= inner else 0.0 if d >= 1.0 else 1.0 - (d - inner) / (1.0 - inner)
            r, g, b, a = rows[y][x]
            line.append((r, g, b, int(a * k + 0.5)))
        out.append(line)
    return out


def soft_rect(rows, mx, my):
    """Fade alpha to 0 over mx/my pixels from each edge (the photo behind the
    logo runs off into the launcher's black instead of ending in a line)."""
    h = len(rows); w = len(rows[0])
    out = []
    for y in range(h):
        ky = min(1.0, (y + 1) / my, (h - y) / my)
        line = []
        for x in range(w):
            k = min(ky, (x + 1) / mx, (w - x) / mx)
            r, g, b, a = rows[y][x]
            line.append((r, g, b, int(a * k + 0.5)))
        out.append(line)
    return out


# ---- pieces ------------------------------------------------------------------
def rip_topmenu(files, body, out, log):
    name = 'arcade/arc_topmenu' if 'arcade/arc_topmenu' in files else 'arcade/arc_topmenu_usa'
    if name not in files:
        log('no top-menu screen (arcade/arc_topmenu) in GT2.VOL')
        return
    tims = tim_images(body(files[name]))
    strips = [t for t in tims if t[0] == 512 and t[1] == 120]
    if len(strips) < 4:
        log('top-menu screen: expected four 512x120 strips')
        return
    screen = []
    for _, _, rows in strips[:4]:
        screen += rows
    # The mark sits in the upper half, the wordmark under it; the row of
    # menu labels and the Polyphony credit below are not ours to reuse.
    rows_to_png(os.path.join(out, 'logo.png'), soft_rect(crop(screen, 64, 26, 444, 268), 28, 18))
    rows_to_png(os.path.join(out, 'mark.png'), soft_rect(crop(screen, 64, 26, 376, 200), 24, 14))
    rows_to_png(os.path.join(out, 'backdrop.png'), soft_ellipse(crop(screen, 0, 16, 512, 212), 0.3, 0.98, 0.98))
    log('logo, mark and backdrop from %s' % name)


def rip_licence_badges(files, body, out, log):
    if 'arcade/gt_items.tim' not in files:
        log('no licence badges (arcade/gt_items.tim) in GT2.VOL')
        return
    w, h, rows = tim_images(body(files['arcade/gt_items.tim']))[0]
    if w < 252 or h < 103:
        log('licence badge sheet has an unexpected size %dx%d' % (w, h))
        return
    cells = {'S': (0, 0), 'IA': (84, 0), 'IB': (168, 0), 'IC': (0, 51), 'A': (84, 51), 'B': (168, 51)}
    for tag, (cx, cy) in cells.items():
        cell = crop(rows, cx, cy, cx + 84, cy + 52)
        x0, y0, x1, y1 = bbox_alpha(cell)
        rows_to_png(os.path.join(out, 'lic_%s.png' % tag), crop(cell, x0, y0, x1, y1))
    log('six licence badges from arcade/gt_items.tim')


def rip_course_maps(files, body, out, log):
    n = 0
    for course, _title in ARCADE_COURSES:
        key = 'crsmap/%s.tim.gz' % course
        if key not in files:
            continue
        try:
            w, h, rows = tim_images(body(files[key]))[0]
        except Exception:
            continue
        rows_to_png(os.path.join(out, 'map_%s.png' % course), rows)
        n += 1
    log('%d of %d arcade course maps from crsmap/' % (n, len(ARCADE_COURSES)))


def car_code(cid):
    return ''.join(CAR_ALPHABET[(cid >> s) & 63] for s in (24, 18, 12, 6))


def car_variant(cid):
    # Low six bits of the id: 24 normal, 28 racing modification, 29 and 30
    # the special bodies the disc names s and t.
    return {28: 'r', 29: 's', 30: 't'}.get(cid & 63, 'r' if cid & 4 else 'n')


def car_name(raw):
    """The .carinfoe string is binary spec data followed by a length byte and
    the display name (a 7Fh right before the name marks it as a tuned/racing
    variant in some entries)."""
    for L in range(1, len(raw)):
        if raw[-L - 1] != L:
            continue
        name = raw[-L:]
        if name[:1] == b'\x7f':
            name = name[1:]
        # Latin-1 text (Protegé); the length byte itself is never printable,
        # so exactly one L fits a real name.
        if name and all(32 <= c < 127 or c >= 0xA0 for c in name):
            name = name.decode('latin1').strip()
            return '' if name == 'Delete' else name   # unused table slots
    return ''


def rip_cars(files, body, out, region, log):
    if '.carinfoe' not in files:
        log('no car table (.carinfoe) in GT2.VOL')
        return
    d = body(files['.carinfoe'])
    if d[:4] != b'CAR\0':
        log('.carinfoe: bad magic')
        return
    count = struct.unpack_from('<I', d, 4)[0]
    logo_dir = os.path.join(out, 'carlogo')
    os.makedirs(logo_dir, exist_ok=True)
    # Nameplate market: the Japanese disc shows the domestic plate
    # ("ROADSTER"); everyone else gets the export one ("Mazda MX-5 Miata")
    # when the disc has it. l/m are the JP large/medium, n/o export.
    prefer = 'lnmo' if region == '_jp' else 'nlom'
    lines = []
    made = 0
    seen = set()
    for i in range(count):
        cid, so, _fl = struct.unpack_from('<IHH', d, 8 + 8 * i)
        end = d.find(b'\0', so)
        name = car_name(d[so:end]) if end > so else ''
        code = car_code(cid) + car_variant(cid)
        if not name:
            continue
        lines.append('%08x\t%s\t%s' % (cid, code, name))
        if code in seen:
            continue
        seen.add(code)
        # This body's plate first, another body of the same car when the
        # disc has no plate for this one (a few RM entries only ship the
        # normal-body plate).
        done = False
        for v in code[4] + 'nrst'.replace(code[4], ''):
            for s in prefer:
                key = 'carlogo/%s%s%s--.tim' % (code[:4], v, s)
                if key not in files:
                    continue
                try:
                    w, h, rows = tim_images(body(files[key]))[0]
                except Exception:
                    continue
                x0, y0, x1, y1 = bbox_alpha(rows)
                rows_to_png(os.path.join(logo_dir, code + '.png'), crop(rows, x0, y0, x1, y1))
                made += 1
                done = True
                break
            if done:
                break
    with open(os.path.join(out, 'carinfo.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    log('%d car names, %d nameplates from carlogo/' % (len(lines), made))


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    src, out = argv[1], argv[2]
    quiet = '--quiet' in argv
    def log(msg):
        if not quiet:
            print('  ' + msg)
    disc = Disc(src)
    root = disc.root_dir()
    if 'GT2.VOL' not in root:
        raise SystemExit('no GT2.VOL on this disc - not a Gran Turismo 2 image?')
    serial = next((n for n in root if n.startswith(('SCUS', 'SCES', 'SCPS'))), '')
    region = '_us' if serial.startswith('SCUS') else '_jp' if serial.startswith('SCPS') else ''
    files, body = gtfs_files(disc, root['GT2.VOL'][0])
    os.makedirs(out, exist_ok=True)
    rip_topmenu(files, body, out, log)
    rip_licence_badges(files, body, out, log)
    rip_course_maps(files, body, out, log)
    rip_cars(files, body, out, region, log)
    print('%s: launcher art from %s' % (out, os.path.basename(src)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
