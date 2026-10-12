#!/bin/bash
# Usage: mptest.sh <chapter> <seconds> "<host test tokens>" "<client test tokens>" [nclients]
# Builds the patched chapter, launches a host (display :91) and clients (:92, :93...)
# with automated test flags, waits, then screenshots every instance.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CH=$1; SECS=$2; HT=$3; CT=$4; NC=${5:-1}
OUT=${MPTEST_OUT:-$ROOT/work/test}
mkdir -p "$OUT"; rm -f "$OUT"/*.log "$OUT"/*.png
rm -f ~/.wine-dr/drive_c/users/ai/AppData/Local/DELTARUNE/multiplayer.ini
if [ -z "$NOBUILD" ]; then
  "$ROOT/patcher/bin/out/drm-patcher" "$ROOT/DELTARUNE/chapter${CH}_windows/data.win" "$ROOT/build/ch$CH.win" "$ROOT/mod" "$CH" | tail -2
fi
"$ROOT/tools/mkgamedir.sh" "$ROOT/build/game" "$CH" "$ROOT/build/ch$CH.win"
pkill -x DELTARUNE.exe || true; sleep 1
"$ROOT/tools/run_game.sh" 91 "$ROOT/build/game" "$CH" -mphost -mpname Host -mpchar 1 -mptest "$HT" > "$OUT/host.log" 2>&1 &
sleep 4
for i in $(seq 1 $NC); do
  "$ROOT/tools/run_game.sh" $((91+i)) "$ROOT/build/game" "$CH" -mpjoin 127.0.0.1 -mpname P$((i+1)) -mpchar $(echo ${MPCHARS:-2 3 4 1 2 3 4} | cut -d" " -f$i) -mptest "$CT" > "$OUT/client$i.log" 2>&1 &
done
# Optional series of side-by-side screenshots: SHOTS="10 15 20" (seconds after start)
T=0
for t in ${SHOTS:-}; do
  sleep $((t - T)); T=$t
  DISPLAY=:91 scrot -o "$OUT/h_$t.png"
  for i in $(seq 1 $NC); do DISPLAY=:$((91+i)) scrot -o "$OUT/c${i}_$t.png"; done
  python3 -c "
from PIL import Image
import sys
fs=['$OUT/h_$t.png']+['$OUT/c%d_$t.png'%i for i in range(1,$NC+1)]
im=Image.new('RGB',(640*len(fs),480))
for k,f in enumerate(fs): im.paste(Image.open(f).crop((80,60,720,540)),(640*k,0))
im.save('$OUT/all_$t.png')"
done
sleep $((SECS > T ? SECS - T : 0))
DISPLAY=:91 scrot -o "$OUT/host.png"
for i in $(seq 1 $NC); do DISPLAY=:$((91+i)) scrot -o "$OUT/client$i.png"; done
# Don't leave the games running (each one uses several CPU cores); KEEP=1 to keep them.
[ -z "$KEEP" ] && pkill -x DELTARUNE.exe
echo "screens in $OUT"
