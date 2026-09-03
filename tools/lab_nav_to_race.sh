#!/bin/bash
# boot -> start a Road Race (Easy / Class-S / first car / AT / Racing / first course)
cd /root/GT2Recomp
sleep 20
bash tools/labkeys.sh Return 0.25 5      # skip intro
bash tools/labkeys.sh x 0.25 8           # title -> ARCADE MODE
bash tools/labkeys.sh x 0.25 3           # Single Player
bash tools/labkeys.sh x 0.25 3           # Road Race
bash tools/labkeys.sh x 0.25 3           # Easy
bash tools/labkeys.sh x 0.25 3           # Class-S
bash tools/labkeys.sh x 0.25 3           # car
bash tools/labkeys.sh x 0.25 6           # AT
bash tools/labkeys.sh x 0.25 6           # Racing
bash tools/labkeys.sh x 0.25 3           # course -> start
