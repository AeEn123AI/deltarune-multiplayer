#!/bin/bash
# Usage: run_game.sh <display_num> <game_dir> <chapter> [extra args...]
# Starts an Xvfb display (if not running) and launches a chapter under Wine.
DISP=$1; GAMEDIR=$2; CH=$3; shift 3
# Three CPU cores per game (Wine's software rendering would otherwise use ~4-5 each).
N=$(nproc); C0=$(( (DISP - 91) * 3 % N )); CORES=${MP_CORES:-$C0,$(( (C0 + 1) % N )),$(( (C0 + 2) % N ))}
export WINEDEBUG=-all WINEPREFIX=${WINEPREFIX:-$HOME/.wine-dr} DISPLAY=:$DISP
if ! xdpyinfo -display :$DISP >/dev/null 2>&1; then
  Xvfb :$DISP -screen 0 800x600x24 -nolisten tcp >/dev/null 2>&1 &
  sleep 1
fi
# Every output line gets a wall-clock timestamp prefix ("@<unix time> "), used by
# tools/mpcheck.py to line up what different players saw at the same moment.
cd "$GAMEDIR/chapter${CH}_windows" && nice -n 15 taskset -c $CORES wine ../DELTARUNE.exe -game data.win "$@" 2>&1 | python3 -u -c '
import sys, time
for line in sys.stdin:
    sys.stdout.write("@%.3f %s" % (time.time(), line))
'

