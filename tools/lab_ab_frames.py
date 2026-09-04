#!/usr/bin/env python3
"""lab_ab_frames.py - frame-matched A/B captures from a deterministic savestate.

    lab_ab_frames.py <slot> <out_dir> <at_frames> <name>=<pgxp json> [<name>=<pgxp json> ...]
    e.g. lab_ab_frames.py 5 /tmp/abd 5,1100,1450 'off={"depth":0}' 'on={"depth":1}'

For every configuration: apply the `pgxp` debug-command fields, load the
savestate, wait until N presented frames after the load, record a short
framerec burst at full internal resolution (div=1). Bursts of different
configurations are then aligned to the FIRST configuration's burst by the
HUD lap-timer digits (a colour mask of the "0:00.000" text, compared by
XOR), which is exact to the frame because the timer changes every frame at
60 FPS. Writes <out_dir>/<name>_<N>.png for each configuration and N (the
matched frame), and prints the per-pair alignment offsets and the number of
pixels that differ from the first configuration.
"""
import sys, os, time, glob, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lab import Lab
from PIL import Image, ImageChops
import numpy as np

slot = int(sys.argv[1]); out = sys.argv[2]; ats = [int(x) for x in sys.argv[3].split(",")]
cfgs = []
for a in sys.argv[4:]:
    name, js = a.split("=", 1); cfgs.append((name, json.loads(js)))
os.makedirs(out, exist_ok=True)
L = Lab()
BURST = 8

def timer_mask(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    h, w = a.shape[:2]; sx = w / 1280.0; sy = h / 960.0
    c = a[int(220*sy):int(262*sy), int(120*sx):int(330*sx)]
    return (c[..., 0] > 170) & (c[..., 1] > 80) & (c[..., 2] < 120)

bursts = {}   # (name, N) -> [png paths]
for name, cfg in cfgs:
    r = L.cmd(cmd="pgxp", **cfg)
    print(f"[{name}] pgxp -> " + " ".join(f"{k}={r.get(k)}" for k in cfg), flush=True)
    for N in ats:
        L.cmd(cmd="savestate", op="load", slot=slot); time.sleep(0.3)
        f0 = L.frame()["frame"]
        while L.frame()["frame"] - f0 < N: time.sleep(0.2)
        d = f"{out}/_burst_{name}_{N}"; os.makedirs(d, exist_ok=True)
        for p in glob.glob(d + "/*.png"): os.remove(p)
        L.cmd(cmd="framerec", dir=d, count=BURST, div=1)
        t0 = time.time()
        while len(glob.glob(d + "/*.png")) < BURST and time.time() - t0 < 60: time.sleep(0.5)
        bursts[(name, N)] = sorted(glob.glob(d + "/*.png"))
        print(f"[{name}] N={N}: {len(bursts[(name, N)])} frames", flush=True)

base = cfgs[0][0]
for N in ats:
    ref = bursts[(base, N)]
    mid = BURST // 2
    ref_mask = timer_mask(ref[mid])
    Image.open(ref[mid]).save(f"{out}/{base}_{N}.png")
    for name, _ in cfgs[1:]:
        cand = bursts[(name, N)]
        best = min(range(len(cand)), key=lambda i: np.logical_xor(ref_mask, timer_mask(cand[i])).mean())
        score = np.logical_xor(ref_mask, timer_mask(cand[best])).mean() * 1000
        a = Image.open(ref[mid]).convert("RGB"); b = Image.open(cand[best]).convert("RGB")
        b.save(f"{out}/{name}_{N}.png")
        diff = np.asarray(ImageChops.difference(a, b)).max(axis=2)
        print(f"N={N}: {name} frame {best} vs {base} frame {mid}  timer-mismatch {score:.1f}  "
              f"pixels differing >16: {int((diff > 16).sum())}  bbox {ImageChops.difference(a, b).getbbox()}")
        Image.fromarray(((diff > 16) * 255).astype("uint8")).save(f"{out}/diff_{name}_{N}.png")
