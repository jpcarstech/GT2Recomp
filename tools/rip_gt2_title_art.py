#!/usr/bin/env python3
"""rip_gt2_title_art.py - the launcher's box art, straight off the player's disc.

    rip_gt2_title_art.py <GT2 disc .bin> <out.tga> [--crop-logo] [--png <preview.png>]

Reads the raw 2352-byte-sector disc image, walks ISO 9660 to GT2.VOL, walks
the GTFS archive inside it (magic "GTFS", u16 file count, u16 entry count,
u32 sector offsets, 32-byte entries: u32 timestamp, u16 offset index, u8
flags [bit0 dir, bit7 last], 25-byte name) to the `arcade` folder and pulls
the title screen the game itself shows - title_arcade_*.tim.gz on the
Arcade disc, title_gtmode_*.tim.gz on the Simulation disc (the Combined
disc carries both; GT Mode's is used). The region suffix follows the disc
serial (SCUS -> _us, SCPS -> _jp, SCES -> none). The TIM (8-bit CLUT,
352x480) is decoded with the PS1's own rules - a 0000h texel is fully
transparent, an STP=1 texel is half transparent (the game blends it 50%
over what is behind) - and written as a 32-bit top-left-origin TGA, which
is what the launcher's box-art loader takes (assets/img/boxart.tga).
--crop-logo keeps only the "GT2 GRAN TURISMO" mark instead of the whole
title card. Nothing here comes from anywhere but the disc.
"""
import gzip, io, struct, sys

SECTOR = 2352
DATA_OFF = 24  # MODE2/2352: sync(12) + header(4) + subheader(8)

class Disc:
    def __init__(self, path):
        self.f = open(path, 'rb')
    def sector(self, lba):
        self.f.seek(lba * SECTOR + DATA_OFF)
        return self.f.read(2048)
    def read(self, lba, byte_off, n):
        out = b''
        while n > 0:
            s = self.sector(lba + byte_off // 2048)[byte_off % 2048:]
            chunk = s[:n]
            out += chunk; n -= len(chunk); byte_off += len(chunk)
        return out
    def root_dir(self):
        pvd = self.sector(16)
        if pvd[1:6] != b'CD001':
            raise SystemExit('not an ISO 9660 disc image (no PVD at sector 16)')
        rec = pvd[156:190]
        extent = struct.unpack('<I', rec[2:6])[0]; size = struct.unpack('<I', rec[10:14])[0]
        data = b''.join(self.sector(extent + i) for i in range((size + 2047) // 2048))
        files = {}
        i = 0
        while i < len(data):
            l = data[i]
            if l == 0:
                i = (i // 2048 + 1) * 2048; continue
            ext = struct.unpack('<I', data[i + 2:i + 6])[0]
            sz = struct.unpack('<I', data[i + 10:i + 14])[0]
            nl = data[i + 32]; name = data[i + 33:i + 33 + nl].decode('latin1').split(';')[0]
            files[name.upper()] = (ext, sz)
            i += l
        return files

def gtfs_files(disc, vol_lba):
    hdr = disc.read(vol_lba, 0, 16)
    if hdr[:4] != b'GTFS':
        raise SystemExit('GT2.VOL is not a GTFS archive')
    nfiles, nent = struct.unpack('<HH', hdr[8:12])
    offs = struct.unpack('<%dI' % nfiles, disc.read(vol_lba, 16, 4 * nfiles))
    tbl = disc.read(vol_lba, offs[1] & 0xFFFFF800, 32 * nent)
    ents = []
    for i in range(nent):
        e = tbl[i * 32:(i + 1) * 32]
        ts, idx, fl = struct.unpack('<IHB', e[:7])
        ents.append((idx, fl, e[7:32].split(b'\0')[0].decode('latin1')))
    # directory entries: idx = first entry of that directory's listing.
    def walk(start, prefix, out):
        i = start
        while i < len(ents):
            idx, fl, name = ents[i]
            if name != '..':
                if fl & 1: walk(idx, prefix + name + '/', out)
                else: out[prefix + name] = idx
            if fl & 0x80: break
            i += 1
    out = {}
    walk(0, '', out)
    def body(idx):
        start = offs[idx] & 0xFFFFF800; end = offs[idx + 1] & 0xFFFFF800
        return disc.read(vol_lba, start, end - start)
    return out, body

def decode_tim8(data):
    """8-bit CLUT TIM -> (w, h, rows of (r,g,b,a))."""
    magic, flags = struct.unpack('<II', data[:8])
    if magic != 0x10 or (flags & 7) != 1 or not (flags & 8):
        raise SystemExit('expected an 8-bit CLUT TIM')
    bnum = struct.unpack('<I', data[8:12])[0]
    clut = data[20:8 + bnum]; pos = 8 + bnum
    bnum2, x, y, w, h = struct.unpack('<IHHHH', data[pos:pos + 12])
    px = data[pos + 12:pos + bnum2]
    pal = struct.unpack('<%dH' % (len(clut) // 2), clut)
    def c15(v):
        if v == 0: return (0, 0, 0, 0)                       # PS1: 0000h is the cutout
        r, g, b = v & 31, (v >> 5) & 31, (v >> 10) & 31
        a = 128 if (v >> 15) else 255                         # STP: blended 50% by the game
        return ((r << 3) | (r >> 2), (g << 3) | (g >> 2), (b << 3) | (b >> 2), a)
    lut = [c15(v) for v in pal]
    W = w * 2
    rows = [[lut[px[yy * W + xx]] for xx in range(W)] for yy in range(h)]
    return W, h, rows

def write_tga(path, w, h, rows):
    hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    body = bytearray()
    for row in rows:
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    open(path, 'wb').write(hdr + bytes(body))

def bbox_opaque(rows, w, h, thresh=200):
    xs = [x for y in range(h) for x in range(w) if rows[y][x][3] >= thresh]
    ys = [y for y in range(h) for x in range(w) if rows[y][x][3] >= thresh]
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1) if xs else (0, 0, w, h)

def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr); return 2
    src, dst = argv[1], argv[2]
    crop = '--crop-logo' in argv
    png = argv[argv.index('--png') + 1] if '--png' in argv else None
    disc = Disc(src)
    root = disc.root_dir()
    if 'GT2.VOL' not in root:
        raise SystemExit('no GT2.VOL on this disc - not a Gran Turismo 2 image?')
    serial = next((n for n in root if n.startswith('SCUS') or n.startswith('SCES') or n.startswith('SCPS')), '')
    region = '_us' if serial.startswith('SCUS') else '_jp' if serial.startswith('SCPS') else ''
    files, body = gtfs_files(disc, root['GT2.VOL'][0])
    order = ['arcade/title_gtmode', 'arcade/title_arcade'] if 'arcade/title_gtmode' + region + '.tim.gz' in files \
        else ['arcade/title_arcade', 'arcade/title_gtmode']
    # The Arcade disc's own card first when it has no GT Mode one; both discs
    # ship both files, so prefer the one matching what the disc boots into.
    if serial.endswith('455') or 'ARCADE' in src.upper():
        order = ['arcade/title_arcade', 'arcade/title_gtmode']
    chosen = None
    for base in order:
        for suffix in (region, '', '_us', '_jp'):
            if base + suffix + '.tim.gz' in files:
                chosen = base + suffix + '.tim.gz'; break
        if chosen: break
    if not chosen:
        raise SystemExit('no title art in GT2.VOL/arcade')
    raw = body(files[chosen])
    tim = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
    w, h, rows = decode_tim8(tim)
    if crop:
        # The mark sits in the upper half; keep the fully opaque region of
        # that band (the logo glyphs), with a small margin.
        x0, y0, x1, y1 = bbox_opaque([r for r in rows[:h * 55 // 100]], w, h * 55 // 100)
        m = 8
        x0, y0, x1, y1 = max(0, x0 - m), max(0, y0 - m), min(w, x1 + m), min(h, y1 + m)
        rows = [r[x0:x1] for r in rows[y0:y1]]; w, h = x1 - x0, y1 - y0
    write_tga(dst, w, h, rows)
    if png:
        try:
            from PIL import Image
            im = Image.new('RGBA', (w, h)); im.putdata([p for r in rows for p in r]); im.save(png)
        except ImportError:
            pass
    print(f'{dst}: {chosen} ({w}x{h}) from {src}')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
