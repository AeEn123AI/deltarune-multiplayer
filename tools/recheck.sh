#!/bin/bash
# Re-checks every kept (failed) sweep scenario with the current tools/mpcheck.py and lists
# the ones that still fail.   Usage: recheck.sh [sweep dirs...]  (default: work/sweep/ch*)
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for d in ${@:-$ROOT/work/sweep/ch*/}; do
  for s in "$d"/*/; do
    [ -f "$s/host.log" ] || continue
    [ -f "$s/client1.log" ] || continue
    out=$(python3 "$ROOT/tools/mpcheck.py" "$s" --strict-end 2>&1)
    [ $? -ne 0 ] && echo "$(basename "$(dirname "$s")")/$(basename "$s"): $(echo "$out" | grep -A1 '^FAIL' | head -2 | tr '\n' ' ' | cut -c1-250)"
  done
done
