#!/usr/bin/env python3
"""lab_ab_burst.py - like lab_ab_frames.py, but compares EVERY frame of each
configuration's burst with its timer-matched frame of the first configuration,
so intermittent (per-frame) differences show up, not just one matched frame.

    lab_ab_burst.py <slot> <out_dir> <at_frames> <name>=<pgxp json> [...]
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
BURST = 12

def timer_mask(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    h, w = a.shape[:2]; sx = w / 1280.0; sy = h / 960.0
    c = a[int(220*sy):int(262*sy), int(120*sx):int(330*sx)]
    return (c[..., 0] > 170) & (c[..., 1] > 80) & (c[..., 2] < 120)

bursts = {}
for name, cfg in cfgs:
    L.cmd(cmd="pgxp", **cfg)
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

base = cfgs[0][0]
for N in ats:
    ref = bursts[(base, N)]
    masks = [timer_mask(p) for p in ref]
    for name, _ in cfgs[1:]:
        for j, cp in enumerate(bursts[(name, N)]):
            cm = timer_mask(cp)
            best = min(range(len(ref)), key=lambda i: np.logical_xor(masks[i], cm).mean())
            score = np.logical_xor(masks[best], cm).mean() * 1000
            if score > 0.5: continue          # no exact timer match for this frame
            a = Image.open(ref[best]).convert("RGB"); b = Image.open(cp).convert("RGB")
            diff = np.asarray(ImageChops.difference(a, b)).max(axis=2)
            n = int((diff > 16).sum())
            print(f"N={N} {name} frame {j} ~ {base} frame {best}: differing {n} bbox {ImageChops.difference(a, b).getbbox()}", flush=True)
            if n:
                a.save(f"{out}/{base}_{N}_{j}.png"); b.save(f"{out}/{name}_{N}_{j}.png")
