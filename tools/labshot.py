#!/usr/bin/env python3
"""labshot.py <name> [wait_nonblack_s] - screenshot the lab game to /tmp/<name>.png,
optionally waiting until the frame is not black."""
import sys, time; sys.path.insert(0, '/root/GT2Recomp/tools')
from lab import Lab
from PIL import Image
L = Lab(); name = sys.argv[1]; wait = float(sys.argv[2]) if len(sys.argv) > 2 else 0
t0 = time.time()
while True:
    L.cmd(cmd='screenshot_file', path=f'/tmp/{name}.png')
    im = Image.open(f'/tmp/{name}.png').convert('L')
    mx = max(im.getdata())
    if mx > 40 or time.time() - t0 > wait: break
    time.sleep(2)
print(f"{name}: frame {L.frame()['frame']} size {im.size} maxlum {mx}")
