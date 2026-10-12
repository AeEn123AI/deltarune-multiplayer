#!/usr/bin/env python3
"""Generates story-scene sweep scenarios for tools/sweep.py.

For every room of a chapter, looks at the objects placed in it (work/sweep/roomobj_chN.txt,
from `drm-patcher --room-objects`) and their decompiled code (work/chN/CodeEntries). Objects
that start events (set global.interact, make a cutscene, start a battle or change room) are
story objects; the global.plot values their code compares against give the story moments at
which that room does something. Each (room, plot) becomes a scenario.

Usage: sweepgen.py <chapter> [--max-per-room N]  -> prints "room plot" lines
"""
import glob, os, re, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = re.compile(r"test|debug|old|_example|tester|placeholder|_copy|unused|gms2|GMS|sandbox|empty$|blank|PLACE_|ROOM_|bullettest|battletest|gameover")
EVENT = re.compile(r"global\.interact = 1|scr_cutscene_make|room_goto|encounterno|scr_battle\(")
PLOT = re.compile(r"global\.plot\s*(==|<=|>=|<|>|!=)\s*(\d+)")


def main():
    ch = int(sys.argv[1])
    maxper = int(sys.argv[sys.argv.index("--max-per-room") + 1]) if "--max-per-room" in sys.argv else 3
    code_dir = os.path.join(ROOT, f"work/ch{ch}/CodeEntries")
    rooms = defaultdict(set)
    for line in open(os.path.join(ROOT, f"work/sweep/roomobj_ch{ch}.txt")):
        r, o, _ = line.split()
        rooms[r].add(o)
    cache = {}
    # Objects placed in many rooms (doors, save points, NPC templates) are not story events.
    count = defaultdict(int)
    for r in rooms:
        for o in rooms[r]:
            count[o] += 1

    def obj_code(o):
        if o not in cache:
            txt = ""
            for f in glob.glob(os.path.join(code_dir, f"gml_Object_{o}_*.gml")):
                txt += open(f, errors="ignore").read()
            cache[o] = txt
        return cache[o]

    for r in sorted(rooms):
        if not r.startswith("room_") or SKIP.search(r):
            continue
        vals = set()
        for o in rooms[r]:
            if count[o] > 3:
                continue
            t = obj_code(o)
            if not EVENT.search(t):
                continue
            for op, n in PLOT.findall(t):
                n = int(n)
                vals.add({"==": n, "<=": n, ">=": n, "<": n - 1, ">": n + 1, "!=": n}[op])
        vals = sorted(v for v in vals if 0 <= v < 2000)
        if not vals:
            continue
        # Spread the picks over the room's story range.
        if len(vals) > maxper:
            step = (len(vals) - 1) / (maxper - 1)
            vals = sorted({vals[round(i * step)] for i in range(maxper)})
        for v in vals:
            print(r, v)


if __name__ == "__main__":
    main()
