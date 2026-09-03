#!/usr/bin/env bash
# labkeys.sh <key> [hold_s] [settle_s]  - press a key in the lab game window.
# Keys per keybinds.ini: Return=Start, x=Cross, s=Circle, z=Square, a=Triangle,
# Up/Down/Left/Right, q=L1, w=R1, e=L2, r=R2, "Right Shift"=Select.
export DISPLAY=:77
WID=$(xdotool search --name "Gran Turismo" | head -1)
xdotool keydown --window "$WID" "$1"; sleep "${2:-0.25}"; xdotool keyup --window "$WID" "$1"; sleep "${3:-1.5}"
