#!/bin/bash
# lab_race_bench.sh <60fps true|false> <overclock %> <label>
#   [EXTRA_ENV="PSX_IDLE_SKIP=0 ..."]
# Headless race benchmark on the Arcade build (docs/PERFORMANCE.md): edits
# the build's mods/state.toml (overclock percent, 60fps on/off), boots
# headless with the perf counters on, loads savestate slot 2 (a race, saved
# with the current build - savestates carry the codegen/ABI tag), then
# times how long the host takes for 1500 guest frames from that point. Same
# guest interval every run, so numbers are comparable across configs on the
# same box. Prints host Hz, the phase-profile shares and idle-skip counts.
FPS=$1; OC=$2; LABEL=$3
cd /root/GT2Recomp/titles/arcade/build
P=$(ps -eo pid,comm | awk '$2 ~ /Gran_Turismo/ {print $1}'); [ -n "$P" ] && kill $P; sleep 2
sed -i "s/^percent = .*/percent = \"$OC\"/" mods/state.toml
python3 - "$FPS" <<'PY'
import sys,re; p='mods/state.toml'; s=open(p).read()
s=re.sub(r'(id = "60fps"\nenabled = )(true|false)', r'\g<1>'+sys.argv[1], s); open(p,'w').write(s)
PY
(env PSX_HEADLESS=1 ${EXTRA_ENV:-} PSX_RUNTIME_PERF_DIAG=1 PSX_RUNTIME_PERF_DIAG_MS=5000 nohup ./Gran_Turismo_2__Arcade__Recompiled_pgxp > /tmp/ladder_$LABEL.log 2>&1 &)
sleep 30
python3 - "$LABEL" <<'PY'
import sys,json,time; sys.path.insert(0,'/root/GT2Recomp/tools')
from lab import Lab; L=Lab(); label=sys.argv[1]
L.cmd(cmd='savestate', op='load', slot=2); time.sleep(3)
f0=L.frame()['frame']; w0=time.time()
target=f0+1500
while True:
    f=L.frame()['frame']
    if f>=target: break
    time.sleep(1)
w1=time.time()
pp=L.cmd(cmd='phase_profile', window=10); idle=L.cmd(cmd='idle_skip')
print(f"{label}: 1500 guest frames in {w1-w0:.1f} s host = {1500/(w1-w0):.1f} Hz; interp {pp['interp_share']:.2f} native {pp['native_share']:.2f} static {pp['static_share']:.2f} gpu {pp['gpu_share']:.2f}; skips {idle['skips']} cyc {idle['cycles_skipped']}")
PY
