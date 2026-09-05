#!/usr/bin/env python3
"""Build a play-free overlay capture set for Gran Turismo 2 from the disc.

The framework compiles the game's overlay code to native shards from
"captures" the runtime records while you play (overlay_captures.json), which
means a fresh install runs the interpreter until the background compiler has
caught up over the first sessions. This tool produces the same capture file
without playing, so Setup can compile the whole cache up front and the first
launch is already native.

GT2 keeps every overlay in GT2.OVL at the disc root: a table of (offset,
size) u32 pairs - the first u32 is the table size in bytes, 0x30 = six
entries - followed by one gzip stream per entry. Each decompressed entry is
a raw code image that the boot EXE loads at 0x80010000 (verified two ways:
a jal-target vote on every entry, and byte-for-byte agreement with the
runtime's own play captures of entry 0 at 0x80010000 / 0x80030000 /
0x80047000). The framework's generic extractor knows nothing about this
container, so this tool unpacks it and hands each entry to the framework's
own discovery (the recompiler in normal mode, via the extract_generic
helpers) exactly as it would a loose PS-X EXE.

    gt2_extract_overlays.py --game-toml titles/arcade/game.toml \
        --recompiler <psxrecomp-game> --out overlay_captures.json [--tmp DIR]

Then: psxrecomp/tools/compile_overlays.py --captures overlay_captures.json ...
"""
import argparse
import gzip
import io
import os
import struct
import sys
import tempfile

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMEWORK = os.path.join(os.path.dirname(HERE), 'psxrecomp', 'tools')


def _import_helpers():
    """extract_generic.py lives in the framework checkout beside this repo, or
    in overlay_toolchain/ on an installed game folder; try both."""
    candidates = [
        os.path.join(FRAMEWORK, 'aot_overlay_spike'),
        os.path.join(os.environ.get('PSX_OVERLAY_TOOLCHAIN', ''), 'aot_overlay_spike'),
    ]
    for c in candidates:
        if os.path.isfile(os.path.join(c, 'extract_generic.py')):
            sys.path.insert(0, c)
            sys.path.insert(0, os.path.dirname(c))
            import extract_generic  # noqa: E402
            return extract_generic
    raise SystemExit('extract_generic.py not found (psxrecomp/tools/aot_overlay_spike)')


# ---- ISO 9660 / GT2.OVL ------------------------------------------------------
SECTOR_RAW = 2352


class Disc:
    """Raw 2352-byte-sector Mode 2 image reader (same walk rip_gt2_title_art uses)."""

    def __init__(self, path):
        self.f = open(path, 'rb')

    def sector(self, lba):
        self.f.seek(lba * SECTOR_RAW + 24)
        return self.f.read(2048)

    def read(self, lba, byte_off, n):
        out = bytearray()
        lba += byte_off // 2048
        off = byte_off % 2048
        while n > 0:
            s = self.sector(lba)
            chunk = s[off:off + min(n, 2048 - off)]
            out += chunk
            n -= len(chunk)
            off = 0
            lba += 1
        return bytes(out)

    def root_dir(self):
        pvd = self.sector(16)
        if pvd[1:6] != b'CD001':
            raise SystemExit('no ISO 9660 volume descriptor at sector 16')
        root = pvd[156:190]
        ext = struct.unpack('<I', root[2:6])[0]
        size = struct.unpack('<I', root[10:14])[0]
        d = self.read(ext, 0, size)
        files = {}
        i = 0
        while i < len(d):
            l = d[i]
            if l == 0:
                i = (i // 2048 + 1) * 2048
                if i >= len(d):
                    break
                continue
            e = d[i:i + l]
            fext = struct.unpack('<I', e[2:6])[0]
            fsz = struct.unpack('<I', e[10:14])[0]
            nl = e[32]
            name = e[33:33 + nl].split(b';')[0].decode('latin1')
            files[name.upper()] = (fext, fsz)
            i += l
        return files


def gt2_ovl_entries(disc):
    root = disc.root_dir()
    if 'GT2.OVL' not in root:
        raise SystemExit('no GT2.OVL at the disc root - not a Gran Turismo 2 image?')
    ext, size = root['GT2.OVL']
    ovl = disc.read(ext, 0, size)
    table_bytes = struct.unpack('<I', ovl[:4])[0]
    if table_bytes % 8 or table_bytes < 8 or table_bytes > 0x200:
        raise SystemExit(f'GT2.OVL: unexpected table size {table_bytes:#x}')
    n = table_bytes // 8
    out = []
    for i in range(n):
        off, sz = struct.unpack('<II', ovl[8 * i:8 * i + 8])
        if off + sz > len(ovl) or ovl[off:off + 2] != b'\x1f\x8b':
            raise SystemExit(f'GT2.OVL entry {i}: not a gzip stream at {off:#x}')
        data = gzip.GzipFile(fileobj=io.BytesIO(ovl[off:off + sz])).read()
        out.append(data)
    return out


# ---- main --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--game-toml', required=True)
    ap.add_argument('--recompiler', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--tmp', default=None)
    a = ap.parse_args()

    eg = _import_helpers()

    doc = tomllib.loads(open(a.game_toml, encoding='utf-8-sig').read())
    game = doc.get('game', doc)
    root = os.path.dirname(os.path.abspath(a.game_toml))
    load_addr = int(str(game.get('load_address', '0x80010000')), 16)
    text_size = int(str(game.get('text_size', '0x00099000')), 16)
    floor = (load_addr + text_size) & 0x1FFFFFFF
    floor_page = (floor // 0x1000) * 0x1000
    disc_rel = game['disc']
    disc_path = os.path.join(root, disc_rel)
    bin_path, _raw = eg.parse_cue_datatrack(disc_path)
    print(f"game={game.get('id')} disc={os.path.basename(bin_path)} "
          f"overlay base=0x{load_addr:08X} floor=0x{floor_page:08X}")

    entries = gt2_ovl_entries(Disc(bin_path))
    tmp = a.tmp or tempfile.mkdtemp(prefix='gt2ovl-')
    os.makedirs(tmp, exist_ok=True)

    records = []
    total_seeds = 0
    for i, body in enumerate(entries):
        # Every entry links at the overlay base; confirm with the same
        # jal-target vote the framework uses before trusting it.
        vote = eg.recover_raw_base(body, 0x80010000, 0x80200000)
        base = vote[0] if isinstance(vote, tuple) else vote
        if base != load_addr:
            raise SystemExit(f'GT2.OVL entry {i}: base vote 0x{base:08X} != 0x{load_addr:08X}')
        pro = eg.prologue_offsets(body)
        entry_pc = load_addr + (pro[0] if pro else 0)
        wrapped = eg.make_psx_exe(body, load_addr, entry_pc)
        seeds, aliases = eg.full_discovery_seeds(wrapped, a.recompiler, tmp)
        how = 'recompiler discovery'
        if seeds is None or not eg.full_discovery_output_audit_clean(wrapped, tmp):
            seeds = eg.prologues(body, load_addr)
            aliases = []
            how = 'prologue scan (discovery rejected)'
        else:
            seeds = eg.filter_full_discovery_seeds(body, load_addr, seeds, entry_pc)
        # Split at the static text floor, as the framework does for a loose
        # EXE (GT2's entries all sit below it, but keep the rule).
        lo = load_addr & 0x1FFFFFFF
        hi = lo + len(body)
        spans = [(lo, floor_page), (floor_page, hi)] if lo < floor_page < hi else [(lo, hi)]
        for slo, shi in spans:
            seg = body[slo - lo:shi - lo]
            va = 0x80000000 | slo
            sd = [x for x in seeds if slo <= (x & 0x1FFFFFFF) < shi]
            span_hi = va + len(seg)
            al = [al for al in aliases
                  if va <= al[0] < span_hi and va <= al[1] < al[2] <= span_hi
                  and (al[0] != load_addr or al[0] == entry_pc)]
            records.append(eg.rec(va, seg, sd, static_alias_ranges=al))
            total_seeds += len(sd)
        print(f"  GT2.OVL[{i}]: {len(body)} bytes @0x{load_addr:08X}, "
              f"{len(seeds)} entries ({how})")

    import json
    with open(a.out, 'w') as f:
        json.dump(records, f)
    print(f"{len(records)} regions, {total_seeds} entries -> {a.out}")


if __name__ == '__main__':
    main()
