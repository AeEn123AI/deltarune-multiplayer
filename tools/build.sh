#!/bin/bash
# Usage: build.sh [chapters...]   Patches the chapters into build/chN.win. Each file is
# replaced atomically, so tests that are running pick the new build up at their next launch.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for c in ${@:-1 2 3 4 5}; do
  "$ROOT/patcher/bin/out/drm-patcher" "$ROOT/DELTARUNE/chapter${c}_windows/data.win" "$ROOT/build/ch$c.win.tmp" "$ROOT/mod" $c > "$ROOT/build/ch$c.log" 2>&1 \
    && mv -f "$ROOT/build/ch$c.win.tmp" "$ROOT/build/ch$c.win" && echo "chapter $c: ok" || { echo "chapter $c: FAILED"; tail -5 "$ROOT/build/ch$c.log"; }
done
