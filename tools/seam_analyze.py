#!/usr/bin/env python3
"""seam_analyze.py - find PGXP seams from the resolved-corner dump (pgxp_tris CSV).

Two triangles that share an EDGE (two integer corners in common) are adjacent
faces of one mesh. If they resolved a shared corner to different sub-pixel
positions, that edge opens - a seam - regardless of whether the second copy
fell back to native (mixed) or got a different fraction (divergent). Sharing a
single pixel is not enough: unrelated objects overlap in screen space all the
time and are not supposed to connect.
"""
import sys, csv, collections
path = sys.argv[1] if len(sys.argv) > 1 else "pgxp_tris.csv"
rows = list(csv.DictReader(open(path)))
print(f"triangles: {len(rows)}")
tris=[]
for r in rows:
    if r["any"] != "1": continue
    c=[]
    for k in range(3):
        c.append(((int(r[f"ix{k}"]),int(r[f"iy{k}"])),(int(r[f"fx{k}"]),int(r[f"fy{k}"])),int(r[f"t{k}"])))
    tris.append((int(r["seq"]),r["cmd0"],c))
print(f"triangles with >=1 precise corner: {len(tris)}")

# edge -> list of (seq, cmd0, {corner:(resolved,tier)})
edges=collections.defaultdict(list)
for seq,cmd0,c in tris:
    m={ic:(fp,t) for ic,fp,t in c}
    ics=sorted(m.keys())          # degenerate tris have <3 distinct corners
    for i in range(len(ics)):
        for j in range(i+1,len(ics)):
            edges[(ics[i],ics[j])].append((seq,cmd0,m))
shared=[(e,l) for e,l in edges.items() if len(l)>=2]
print(f"edges shared by >=2 triangles: {len(shared)}")
agree=mixed=div=0; worst=[]
for (a,b),l in shared:
    for corner in (a,b):
        pos={m[corner][0] for _,_,m in l}
        if len(pos)<2: continue
        nat=any(m[corner][0]==(corner[0]<<16,corner[1]<<16) for _,_,m in l)
        prec=any(m[corner][0]!=(corner[0]<<16,corner[1]<<16) for _,_,m in l)
        kind="mixed" if (nat and prec) else "divergent"
        if kind=="mixed": mixed+=1
        else: div+=1
        xs=[p[0]/65536 for p in pos]; ys=[p[1]/65536 for p in pos]
        mag=max(max(xs)-min(xs),max(ys)-min(ys))
        worst.append((mag,kind,corner,sorted(pos),[m[corner][1] for _,_,m in l],[c for _,c,_ in l][:3],[s for s,_,_ in l][:3]))
    else:
        pass
n_corner_checks=sum(2 for _ in shared)
print(f"shared-edge corner checks: {n_corner_checks}")
print(f"  agree     : {n_corner_checks-mixed-div}")
print(f"  MIXED     : {mixed}   (one adjacent face precise, the other native)")
print(f"  DIVERGENT : {div}   (both precise, different fractions)")
worst.sort(reverse=True)
print("\nworst shared-EDGE disagreements (px kind corner positions tiers cmd0 seqs):")
for mag,kind,corner,pos,tiers,cmds,seqs in worst[:14]:
    print(f"  {mag:5.3f} {kind:9s} {corner}  {pos[:3]}  tiers={tiers}  cmd0={cmds}  seq={seqs}")
