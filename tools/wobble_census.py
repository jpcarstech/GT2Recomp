#!/usr/bin/env python3
"""wobble_census.py - how much do vertices jitter frame to frame, native vs precise?

Input: a merged pgxp_tris CSV (consecutive guest frames of the triangle ring,
deduplicated by seq). For every textured 3D triangle we find the same triangle
in the previous and the next frame (same command word, nearest centroid, same
shape), which gives each corner a three-frame screen path. A corner moving
smoothly has a small second difference  d2 = (p[n+1]-p[n]) - (p[n]-p[n-1]);
a corner that snaps to the pixel grid has |d2| up to ~1 px regardless of how
smoothly the camera moves. We report that for the integer coordinates the PS1
GPU received (what the console shows) and for the PGXP-resolved coordinates
(what we and DuckStation draw), so the residual jitter of the precise path is
measured, not guessed. Units: native pixels (320x240 space).

    wobble_census.py all.csv [--min-frames 3] [--sizes]
"""
import sys, csv, collections, math, argparse

ap = argparse.ArgumentParser()
ap.add_argument("csv")
ap.add_argument("--max-move", type=float, default=16.0, help="max centroid move per frame to accept a match (px)")
ap.add_argument("--shape-tol", type=float, default=3.0, help="max per-edge-vector change to accept a match (px)")
ap.add_argument("--frames", type=str, default=None, help="frame range a:b (inclusive) to analyse")
ap.add_argument("--worst", type=int, default=0, help="print the N corners with the largest precise local residual")
ap.add_argument("--per-frame", action="store_true", help="print the precise local-residual p90 per frame")
ap.add_argument("--min-tris", type=int, default=2500, help="frames with fewer textured triangles are partial ring dumps; skip them")
args = ap.parse_args()

TEXTURED = {0x24, 0x25, 0x26, 0x27, 0x2C, 0x2D, 0x2E, 0x2F, 0x34, 0x35, 0x36, 0x37, 0x3C, 0x3D, 0x3E, 0x3F}

by_frame = collections.defaultdict(list)
rows = 0
frange = tuple(map(int, args.frames.split(":"))) if args.frames else None
for r in csv.DictReader(open(args.csv)):
    rows += 1
    f = int(r["frame"])
    if frange and not (frange[0] <= f <= frange[1]): continue
    cmd = int(r["cmd0"], 16) >> 24
    if cmd not in TEXTURED: continue
    nat = [(int(r[f"ix{k}"]), int(r[f"iy{k}"])) for k in range(3)]
    pre = [(int(r[f"fx{k}"]) / 65536.0, int(r[f"fy{k}"]) / 65536.0) for k in range(3)]
    tiers = [int(r[f"t{k}"]) for k in range(3)]
    # degenerate / off-screen slivers are not what anyone looks at
    if len(set(nat)) < 3: continue
    by_frame[f].append({"cmd": r["cmd0"], "nat": nat, "pre": pre, "t": tiers, "seq": int(r["seq"])})

# GT2 double-buffers by drawing alternate frames 240 px lower in VRAM (the
# vertex coordinates carry the buffer offset). Bring every frame to buffer 0.
for f, tris in by_frame.items():
    ys = sorted(sum(p[1] for p in t["nat"]) / 3.0 for t in tris)
    if ys[len(ys)//2] >= 240:
        for t in tris:
            t["nat"] = [(x, y - 240) for x, y in t["nat"]]
            t["pre"] = [(x, y - 240.0) for x, y in t["pre"]]
frames = sorted(f for f in by_frame if len(by_frame[f]) >= args.min_tris)
print(f"complete frames: {len(frames)} of {len(by_frame)} captured")
if args.frames:
    a, b = map(int, args.frames.split(":"))
    frames = [f for f in frames if a <= f <= b]
print(f"rows {rows}; textured 3D triangles {sum(len(by_frame[f]) for f in frames)} over {len(frames)} frames "
      f"({frames[0]}..{frames[-1]})" if frames else "no frames")
gaps = [(frames[i], frames[i+1]) for i in range(len(frames)-1) if frames[i+1] != frames[i]+1]
if gaps: print(f"WARNING: {len(gaps)} gaps in the frame sequence, e.g. {gaps[:3]}")

def centroid(v): return (sum(p[0] for p in v)/3.0, sum(p[1] for p in v)/3.0)
def edges(v): return [(v[(k+1)%3][0]-v[k][0], v[(k+1)%3][1]-v[k][1]) for k in range(3)]

def match(prev, cur):
    """cur triangle -> index of the same triangle in prev, by cmd word, centroid distance, shape."""
    G = 16
    idx = collections.defaultdict(list)
    for i, t in enumerate(prev):
        pc = centroid(t["nat"]); idx[(t["cmd"], int(pc[0]//G), int(pc[1]//G))].append(i)
    out = {}
    used = set()
    for j, t in enumerate(cur):
        c = centroid(t["nat"]); e = edges(t["nat"])
        best = None
        cx, cy = int(c[0]//G), int(c[1]//G)
        cands = [i for dx in (-1, 0, 1) for dy in (-1, 0, 1) for i in idx.get((t["cmd"], cx+dx, cy+dy), ())]
        for i in cands:
            if i in used: continue
            p = prev[i]
            pc = centroid(p["nat"])
            d = math.hypot(c[0]-pc[0], c[1]-pc[1])
            if d > args.max_move: continue
            pe = edges(p["nat"])
            sh = max(math.hypot(e[k][0]-pe[k][0], e[k][1]-pe[k][1]) for k in range(3))
            if sh > args.shape_tol: continue
            score = d + sh
            if best is None or score < best[0]: best = (score, i)
        if best is not None:
            out[j] = best[1]; used.add(best[1])
    return out

# three-frame chains: n-1 -> n -> n+1
d2_nat, d2_pre, d2_pre_prec = [], [], []
res_nat, res_pre = [], []
worst = []
dropped = [0]   # d2 minus the local (24 px cell) median d2: camera motion removed, jitter left
size_bins = collections.defaultdict(lambda: [[], []])  # by triangle size class: (nat, pre)
matched_tris = 0
for fi in range(1, len(frames)-1):
    f0, f1, f2 = frames[fi-1], frames[fi], frames[fi+1]
    if f1 != f0+1 or f2 != f1+1: continue
    A, B, C = by_frame[f0], by_frame[f1], by_frame[f2]
    mBA = match(A, B)   # B index -> A index
    mCB = match(B, C)   # C index -> B index
    cell_nat, cell_pre = collections.defaultdict(list), collections.defaultdict(list)
    per_corner = []
    for jc, jb in mCB.items():
        if jb not in mBA: continue
        ja = mBA[jb]
        ta, tb, tc = A[ja], B[jb], C[jc]
        matched_tris += 1
        for k in range(3):
            ext_k = max(max(p[0] for p in tb["nat"]) - min(p[0] for p in tb["nat"]),
                        max(p[1] for p in tb["nat"]) - min(p[1] for p in tb["nat"]))
            if ext_k < 16: continue
            pb = tb["nat"][k]; cell = (int(pb[0] // 24), int(pb[1] // 24))
            vecs = []
            for key in ("nat", "pre"):
                a, b, c = ta[key][k], tb[key][k], tc[key][k]
                vecs.append(((c[0]-b[0]) - (b[0]-a[0]), (c[1]-b[1]) - (b[1]-a[1])))
            cell_nat[cell].append(vecs[0]); cell_pre[cell].append(vecs[1])
            per_corner.append((cell, vecs[0], vecs[1], tb["cmd"], [ta[kk][k] for kk in ("nat","pre")], [tb[kk][k] for kk in ("nat","pre")], [tc[kk][k] for kk in ("nat","pre")], ext_k))
    def med(v):
        xs = sorted(x for x, _ in v); ys = sorted(y for _, y in v)
        return (xs[len(xs)//2], ys[len(ys)//2])
    mn = {c: med(v) for c, v in cell_nat.items() if len(v) >= 6}
    mp = {c: med(v) for c, v in cell_pre.items() if len(v) >= 6}
    fr_res = []
    for cell, vn, vp, cmd, pa, pb, pc, ext_k in per_corner:
        if cell in mn:
            rn = math.hypot(vn[0]-mn[cell][0], vn[1]-mn[cell][1]); rp = math.hypot(vp[0]-mp[cell][0], vp[1]-mp[cell][1])
            # a corner whose integer path accelerates by >3 px in one frame is a
            # tracking error (a repeating fence post / tile matched to its
            # neighbour), not motion; drop it from both distributions
            if rn > 3.0: dropped[0] += 1; continue
            res_nat.append(rn); res_pre.append(rp); fr_res.append(rp)
            worst.append((rp, f1, cmd, ext_k, rn, pa, pb, pc, mp[cell]))
    if args.per_frame and fr_res:
        fr_res.sort(); print(f"  frame {f1}: n={len(fr_res)} precise residual p50 {fr_res[len(fr_res)//2]:.3f} p90 {fr_res[int(0.9*len(fr_res))]:.3f}")
    for jc, jb in mCB.items():
        if jb not in mBA: continue
        ja = mBA[jb]
        ta, tb, tc = A[ja], B[jb], C[jc]
        ext = max(max(p[0] for p in tb["nat"]) - min(p[0] for p in tb["nat"]),
                  max(p[1] for p in tb["nat"]) - min(p[1] for p in tb["nat"]))
        sb = "<4px" if ext < 4 else "<16px" if ext < 16 else "<64px" if ext < 64 else ">=64px"
        for k in range(3):
            for name, key, lst in (("nat", "nat", d2_nat), ("pre", "pre", d2_pre)):
                a, b, c = ta[key][k], tb[key][k], tc[key][k]
                d2 = math.hypot((c[0]-b[0]) - (b[0]-a[0]), (c[1]-b[1]) - (b[1]-a[1]))
                lst.append(d2)
                size_bins[sb][0 if name == "nat" else 1].append(d2)
            if min(ta["t"][k], tb["t"][k], tc["t"][k]) > 0:
                a, b, c = ta["pre"][k], tb["pre"][k], tc["pre"][k]
                d2_pre_prec.append(math.hypot((c[0]-b[0]) - (b[0]-a[0]), (c[1]-b[1]) - (b[1]-a[1])))

def stats(l):
    if not l: return "n=0"
    l = sorted(l); n = len(l)
    q = lambda p: l[min(n-1, int(p*n))]
    return f"n={n:7d}  median {q(0.5):.3f}  p90 {q(0.9):.3f}  p99 {q(0.99):.3f}  mean {sum(l)/n:.3f}  >0.5px {100*sum(1 for x in l if x>0.5)/n:5.1f}%"

print(f"\ntriangles tracked across 3 consecutive frames: {matched_tris}")
print("second difference of corner position |d2| (px, native 320x240 units):")
print(f"  integer coords (console / PGXP off) : {stats(d2_nat)}")
print(f"  PGXP-resolved coords (what we draw) : {stats(d2_pre)}")
print(f"    ...corners precise on all 3 frames : {stats(d2_pre_prec)}")
print("\nlocal residual (corners of >=16 px triangles; the cell-median d2 = real camera acceleration removed):")
print(f"  ({dropped[0]} corners dropped as tracking errors: integer path jumped >3 px)")
print(f"  integer coords : {stats(res_nat)}")
print(f"  PGXP-resolved  : {stats(res_pre)}")
print("\nby triangle screen extent:")
for sb in ("<4px", "<16px", "<64px", ">=64px"):
    if sb in size_bins:
        print(f"  {sb:7s} nat {stats(size_bins[sb][0])}")
        print(f"  {'':7s} pre {stats(size_bins[sb][1])}")

if args.worst:
    worst.sort(reverse=True)
    print(f"\nworst {args.worst} precise local residuals (px; frame cmd extent | native d2-residual | native path | precise path | cell median d2):")
    for rp, f1, cmd, ext_k, rn, pa, pb, pc, cm in worst[:args.worst]:
        fmt = lambda p: f"({p[0]:.2f},{p[1]:.2f})"
        print(f"  {rp:5.2f} f{f1} {cmd} {ext_k:4d}px | nat-res {rn:4.2f} | {pa[0]} {pb[0]} {pc[0]} | {fmt(pa[1])} {fmt(pb[1])} {fmt(pc[1])} | ({cm[0]:.2f},{cm[1]:.2f})")
