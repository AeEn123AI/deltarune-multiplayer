#!/bin/bash
# Builds the VANILLA test variant into buildv/: the game with only the test harness wired in
# (teleport, key mashing, crash logging) and none of the multiplayer gameplay hooks.
# Used with SWEEP_BUILD=buildv tools/sweep.py <chapter> --solo ... to check whether a crash is the game's own.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/buildv"
rm -rf "$ROOT/work/vanillamod"; cp -r "$ROOT/mod" "$ROOT/work/vanillamod"
python3 - "$ROOT" <<'PY'
import sys
r=sys.argv[1]+"/work/vanillamod/hooks/core.hook"
s=open(r).read()
open(r,"w").write(s[:s.index(";; Player character sprite swap.")])
PY
for c in ${@:-1 2 3 4 5}; do
  "$ROOT/patcher/bin/out/drm-patcher" "$ROOT/DELTARUNE/chapter${c}_windows/data.win" "$ROOT/buildv/ch$c.win" "$ROOT/work/vanillamod" $c > "$ROOT/buildv/ch$c.log" 2>&1 && echo "chapter $c: ok" || { echo "chapter $c: FAILED"; tail -5 "$ROOT/buildv/ch$c.log"; }
done
