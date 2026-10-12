#!/usr/bin/env python3
"""Checks the [MPCHK] self-check lines (scr_mp_test.gml, token "check") of every player in a
test output directory and reports, per check, PASS or FAIL with examples:

  char      in free roam every player is drawn as the character they picked
  follower  no party member played by a connected player also follows anyone as an NPC
  ghost     every other player in the same room is shown, where they really are
  state     shared story state (plot, gold, party, flags, items, HP) matches
  sync      nobody is left frozen: cutscene/battle sync states always return to free roam
  moved     players moved independently (not glued together)

Usage: mpcheck.py <dir> [--strict-end]   exit code 1 when a check fails
"""
import glob, os, re, sys
from collections import defaultdict

FREE = lambda s: s["sst"] == "0" and s["ia"] == "0" and s["bat"] == "0"


_last_bad = {}


def twice(nm, opid, wc):
    """A ghost problem counts when the sample just before (<= 1.6 s) was bad too: the logs are
    sampled twice a second, so a single odd sample can be a step or a door in between."""
    k = (nm, opid)
    prev = _last_bad.get(k)
    _last_bad[k] = wc
    return prev is not None and 0 < wc - prev <= 1.6


def parse(path):
    out = []
    for line in open(path, errors="ignore"):
        ts = None
        if line.startswith("@"):
            ts, _, line = line.partition(" ")
            ts = float(ts[1:])
        if not line.startswith("[MPCHK] t="):
            continue
        d = dict(re.findall(r"(\w+)=(\S*)", line))
        d["ts"] = ts
        try:
            d["wc"] = float(d["wc"])
            for k in ("x", "y", "dx", "dy", "fol", "want", "drawn", "id"):
                d[k] = int(float(d[k]))
        except (KeyError, ValueError):
            continue
        peers = {}
        for p in d.get("peers", "").split(";"):
            if not p:
                continue
            f = p.split(":")
            e = {"char": int(f[1]), "room": int(f[2]), "px": float(f[3]), "py": float(f[4])}
            if len(f) >= 7 and f[5].startswith("G"):
                e["gx"] = float(f[5][1:])
                e["gy"] = float(f[6])
            peers[int(f[0])] = e
        d["peers"] = peers
        out.append(d)
    # wc: wall clock in seconds, frame-precise (taken when the game saw the second tick over).
    # The first second after start may be partial, so align every line to the latest offset.
    if out and all(d["ts"] is not None for d in out):
        # Timestamped when written (run_game.sh); smooth out output batching with the
        # game's own millisecond timer.
        off = min(d["ts"] - int(d["t"]) / 1000 for d in out)
        for d in out:
            d["wc"] = int(d["t"]) / 1000 + off
    elif out:
        offs = sorted(d["wc"] - int(d["t"]) / 1000 for d in out)
        off = offs[len(offs) // 2]
        for d in out:
            d["wc"] = int(d["t"]) / 1000 + off
    return out


def seg_dist(px, py, ax, ay, bx, by):
    """Distance from a point to the path walked between two samples: straight, or an L
    shape along either axis first (players walk with the arrow keys)."""
    import math

    def to_seg(x1, y1, x2, y2):
        dx, dy = x2 - x1, y2 - y1
        L = dx * dx + dy * dy
        t = 0 if L == 0 else max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L))
        return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

    straight = to_seg(ax, ay, bx, by)
    x_first = min(to_seg(ax, ay, bx, ay), to_seg(bx, ay, bx, by))
    y_first = min(to_seg(ax, ay, ax, by), to_seg(ax, by, bx, by))
    return min(straight, x_first, y_first)


def nearest(samples, wc):
    best = None
    for s in samples:
        if best is None or abs(s["wc"] - wc) < abs(best["wc"] - wc):
            best = s
    return best


def window(samples, wc, w):
    return [s for s in samples if abs(s["wc"] - wc) <= w]


def main():
    d = sys.argv[1]
    strict_end = "--strict-end" in sys.argv
    logs = sorted(glob.glob(os.path.join(d, "host.log"))) + sorted(glob.glob(os.path.join(d, "client*.log")))
    players = {}
    crashes = []
    for l in logs:
        for line in open(l, errors="ignore"):
            if "[MPCRASH]" in line:
                crashes.append(os.path.basename(l)[:-4] + ": " + line.split("[MPCRASH]", 1)[1].strip()[:400])
    for l in logs:
        ss = parse(l)
        on = [s for s in ss if s.get("on") == "1"]
        if not on:
            print(f"{os.path.basename(l)}: never connected ({len(ss)} samples)")
            continue
        players[on[-1]["id"]] = {"name": os.path.basename(l)[:-4], "s": on}
    if crashes:
        print(f"FAIL crash    ({len(crashes)} crashes)")
        for c in crashes:
            print("       " + c)
    if len(players) < 2:
        print("FAIL: fewer than two connected players")
        sys.exit(1)
    fails = defaultdict(list)
    warns = []
    counts = defaultdict(int)
    for pid, P in players.items():
        nm = P["name"]
        for s in P["s"]:
            free = FREE(s) and (s["x"] != -1 or s.get("plat") == "1")
            # char
            if free and s["vis"] == "1" and s.get("plat") != "1":
                counts["char"] += 1
                if s["drawn"] != s["want"]:
                    fails["char"].append(f"{nm} t={s['wc']:.1f} {s['room']}: wants {s['want']} but drawn as {s['drawn']} ({s['spr']})")
            # follower
            if free:
                counts["follower"] += 1
                for opid, e in s["peers"].items():
                    if s["fol"] & (1 << e["char"]):
                        fails["follower"].append(f"{nm} t={s['wc']:.1f} {s['room']}: NPC follower of char {e['char']} shown, but player {opid} plays it")
            # ghost
            for opid, e in s["peers"].items():
                if opid not in players or not free or s["vis"] != "1":
                    continue
                o = nearest(players[opid]["s"], s["wc"])
                if o is None or abs(o["wc"] - s["wc"]) > 0.6:
                    continue
                # Only judge moments where the other player was settled in the same room.
                near = window(players[opid]["s"], s["wc"], 1.2)
                if not all(n["room"] == s["room"] and FREE(n) and n["vis"] == "1" for n in near):
                    continue
                # Standing in a doorway outside the room (x or y below 0): the door transition is
                # about to move them and what is drawn there is not meaningful.
                if any(n["dx"] < 0 or n["dy"] < 0 for n in window(players[opid]["s"], s["wc"], 3.0)):
                    continue
                # A room that was just (re)built, e.g. by a room refresh (same room name, so no room change shows).
                if any(int(n.get("rf", "9999")) < 150 for n in window(players[opid]["s"], s["wc"], 1.2)) or int(s.get("rf", "9999")) < 150:
                    continue
                # Door crossings: the other player's room change reaches me with a delay.
                if not all(n["room"] == s["room"] for n in window(players[opid]["s"], s["wc"], 3.0)):
                    continue
                # The mod hides ghosts while a text box is up, and a game-driven text box can flicker
                # `interact` to 0 for a couple of frames: don't judge samples with a dialogue open.
                if s.get("dlg") == "1" or any(n.get("dlg") == "1" for n in near):
                    continue
                if "bvx" in s:
                    # Chapter 3 board: only pieces on the board screen I'm looking at are shown.
                    bvx, bvy = int(float(s["bvx"])), int(float(s["bvy"]))
                    if not all(bvx + 8 <= n["dx"] <= bvx + 384 - 24 and bvy + 8 <= n["dy"] <= bvy + 256 - 24 for n in near):
                        continue
                before = [n for n in players[opid]["s"] if n["wc"] <= s["wc"] - 0.5]
                if not before or before[-1]["room"] != s["room"] or not FREE(before[-1]):
                    continue  # they only just arrived (or came back from a battle/cutscene)
                mine = [n for n in P["s"] if n["wc"] <= s["wc"] - 0.5]
                if not mine or mine[-1]["room"] != s["room"]:
                    continue  # I only just arrived
                counts["ghost"] += 1
                plat = s.get("plat") == "1"
                if "gx" not in e:
                    if plat:
                        continue  # the platformer figure blinks (hurt) and is hidden for a moment
                    if not twice(nm, opid, s["wc"]):
                        continue
                    fails["ghost"].append(f"{nm} t={s['wc']:.1f} {s['room']}: {players[opid]['name']} is in this room but not shown")
                    continue
                if not any(n["wc"] >= s["wc"] for n in near):
                    continue  # their log ends before this moment
                if len({(n["dx"], n["dy"]) for n in near}) == 1 and len({n["spr"] for n in near}) > 1:
                    continue  # walked off and came back between samples: can't tell
                still = len(near) >= 2 and len({(n["dx"], n["dy"], n["spr"]) for n in near}) == 1 and not plat
                # Moving: the shown position must be one they really had within the last ~1.5 s
                # (network delay plus the 1 s sampling of these logs).
                recent = [n for n in players[opid]["s"] if -1.6 <= n["wc"] - s["wc"] <= 0.6 and n["room"] == s["room"]]
                # distance to the path walked between consecutive samples
                dist = min(seg_dist(e["gx"], e["gy"], p1["dx"], p1["dy"], p2["dx"], p2["dy"])
                           for p1, p2 in zip(recent, recent[1:] or recent))
                tol = 6 if "bvx" in s else 3  # board pieces bob while walking
                if "bvx" in s:
                    still = False  # the board scrolls under the pieces: judge by the path only
                if ((still and dist > tol) or dist > (120 if plat else 60)) and twice(nm, opid, s["wc"]):
                    fails["ghost"].append(f"{nm} t={s['wc']:.1f} {s['room']}: sees {players[opid]['name']} at {e['gx']:.0f},{e['gy']:.0f} but they are at {o['dx']},{o['dy']} ({'standing' if still else 'moving'})")
        # sync: frozen / stuck states
        # Watching a cutscene that didn't start in your own game is the designed fallback for
        # cutscenes that depend on earlier steps; only being stuck like that is a failure.
        run = 0
        for s in P["s"]:
            if s["sst"] == "4":
                run += 1
                if run == 1:
                    warns.append(f"{nm} t={s['wc']:.1f} {s['room']}: watched a cutscene (it did not start in this game)")
                if run == 60 and not any(not FREE(n) for q, Q in players.items() if q != pid for n in window(Q["s"], s["wc"], 5)):
                    fails["sync"].append(f"{nm} t={s['wc']:.1f} {s['room']}: watching for over a minute")
            else:
                run = 0
        counts["sync"] += len(P["s"])
        last = P["s"][-1]
        tail = 0
        for x in reversed(P["s"]):
            if x["sst"] not in ("3", "4"):
                break
            tail += 1
        others_busy = any(not FREE(x) for q, Q in players.items() if q != pid for x in Q["s"][-10:])
        if strict_end and tail >= 30 and not others_busy:
            fails["sync"].append(f"{nm}: ended stuck waiting for / watching a cutscene (sst={last['sst']} room={last['room']})")
        long_ia = 0
        for s in P["s"]:
            long_ia = long_ia + 1 if (s["sst"] in ("3", "4")) else 0
            if long_ia == 60:  # 30 s
                fails["sync"].append(f"{nm} t={s['wc']:.1f}: stuck in sync state {s['sst']} for 30 s")
        # moved
        P["pos"] = {(s["room"], s["dx"], s["dy"]) for s in P["s"]}
        P["free"] = sum(1 for s in P["s"] if FREE(s) and (s["x"] != -1 or s.get("plat") == "1"))
    # moved: somebody walked, and players were not glued to each other
    counts["moved"] += 1
    in_battle = sum(1 for P in players.values() for x in P["s"] if x["bat"] == "1") >= 3
    if not in_battle and all(len(P["pos"]) < 3 for P in players.values()) and any(P["free"] >= 10 for P in players.values()):
        fails["moved"].append("nobody moved")
    ids0 = list(players)
    for a in ids0:
        for b in ids0:
            if b <= a:
                continue
            same = tot = 0
            for s in players[a]["s"]:
                o = nearest(players[b]["s"], s["wc"])
                if o and abs(o["wc"] - s["wc"]) < 0.6 and FREE(s) and FREE(o) and s["room"] == o["room"] and (s["x"] != -1 or s.get("plat") == "1"):
                    tot += 1
                    same += (s["dx"], s["dy"]) == (o["dx"], o["dy"])
            if tot >= 10 and same > tot * 0.5:
                fails["moved"].append(f"{players[a]['name']} and {players[b]['name']} stood on the same spot {same}/{tot} times")
    # music: players in the same room, both free (or both watching the same cutscene), must hear the same song.
    for a in ids0:
        for b in ids0:
            if b <= a:
                continue
            run = 0
            for s in players[a]["s"]:
                o = nearest(players[b]["s"], s["wc"])
                ok = (o and abs(o["wc"] - s["wc"]) < 0.6 and s["room"] == o["room"] and s.get("mus") and o.get("mus")
                      and s["bat"] == o["bat"] == "0" and s["mus"] not in ("none", "menu.ogg") and o["mus"] not in ("none", "menu.ogg"))
                if not ok:
                    run = 0
                    continue
                counts["music"] += 1
                run = run + 1 if s["mus"] != o["mus"] else 0
                if run == 24:  # 12 s of different songs
                    fails["music"].append(f"t={s['wc']:.1f} {s['room']}: {players[a]['name']} plays {s['mus']}, {players[b]['name']} plays {o['mus']}")
    # world: players free in the same room must be in the same world (Light / Dark) for the whole 6 s.
    for a in ids0:
        for b in ids0:
            if b <= a:
                continue
            run = 0
            for s in players[a]["s"]:
                o = nearest(players[b]["s"], s["wc"])
                ok = (o and abs(o["wc"] - s["wc"]) < 0.6 and s["room"] == o["room"] and FREE(s) and FREE(o)
                      and "dz" in s and "dz" in o)
                if not ok:
                    run = 0
                    continue
                counts["world"] += 1
                run = run + 1 if s["dz"] != o["dz"] else 0
                if run == 12:
                    fails["world"].append(f"t={s['wc']:.1f} {s['room']}: {players[a]['name']} is in world {s['dz']}, {players[b]['name']} in world {o['dz']}")
    # A game that stops logging long before the others crashed (error box) or froze.
    end = max(P["s"][-1]["wc"] for P in players.values())
    for P in players.values():
        if end - P["s"][-1]["wc"] > 10:
            fails["sync"].append(f"{P['name']}: stopped responding {end - P['s'][-1]['wc']:.0f} s before the end (crash or freeze)")
    # state: compare each sample with every other player's samples around the same time
    ids = list(players)
    keys = ("plot", "gold", "party", "hfl", "hit", "hhp")
    for i in ids:
        for j in ids:
            if j <= i:
                continue
            for s in players[i]["s"]:
                if not FREE(s):
                    continue
                w = window(players[j]["s"], s["wc"], 2.0)
                w2 = window(players[i]["s"], s["wc"], 2.0)
                if len(w) < 3 or len(w2) < 2 or not all(FREE(x) for x in w + w2):
                    continue
                if any(len({x[k] for x in w2}) > 1 for k in keys):
                    continue  # changing right now
                counts["state"] += 1
                if not any(all(x[k] == s[k] for k in keys) for x in w):
                    o = nearest(w, s["wc"])
                    diff = [f"{k}: {s[k]} vs {o[k]}" for k in keys if s[k] != o[k]]
                    fails["state"].append(f"t={s['wc']:.1f} {players[i]['name']} vs {players[j]['name']}: " + ", ".join(diff))
    # battle: per-turn battle state ([MPLOG] lines, -mptest log) must match between players
    turns = {}
    for l in logs:
        d = {}
        for line in open(l, errors="ignore"):
            if "[MPLOG] turn=" in line:
                body = line.split("[MPLOG] ", 1)[1].strip()
                d[body.split()[0]] = body
        turns[os.path.basename(l)[:-4]] = d
    if any(turns.values()):
        names = list(turns)
        common = set(turns[names[0]]).intersection(*[set(turns[n]) for n in names[1:]])
        counts["battle"] = len(common)
        for k in sorted(common, key=lambda x: int(x.split("=")[1])):
            vals = {turns[n][k] for n in names}
            if len(vals) > 1:
                fails["battle"].append(f"{k} differs: " + " | ".join(f"{n}: {turns[n][k]}" for n in names))
        lens = [len(turns[n]) for n in names]
        if max(lens) - min(lens) > 1:
            fails["battle"].append(f"players reached different turns: " + ", ".join(f"{n} {len(turns[n])}" for n in names))
    if fails["state"]:
        # Which flags differ (from the [MPFLAGS] dumps closest to the end)
        dumps = {}
        for l in logs:
            last = None
            for line in open(l, errors="ignore"):
                if "[MPFLAGS]" in line:
                    last = line.split("[MPFLAGS]", 1)[1].split()
            if last and len(last) >= 3:
                dumps[os.path.basename(l)[:-4]] = dict(kv.split("=", 1) for kv in last[2].split(",") if "=" in kv)
        names = list(dumps)
        for i in range(1, len(names)):
            a0, b0 = dumps[names[0]], dumps[names[i]]
            diff = [f"{k}: {a0.get(k, '0')} vs {b0.get(k, '0')}" for k in sorted(set(a0) | set(b0), key=int) if a0.get(k) != b0.get(k)]
            fails["state"].insert(0, f"last flag dumps {names[0]} vs {names[i]}: " + (", ".join(diff[:20]) or "same"))
    # A cutscene must never run in a game that was pulled into a battle.
    counts["scene"] = 1
    for l in logs:
        nm = os.path.basename(l)[:-4]
        bat, until = "0", 0.0
        for line in open(l, errors="ignore"):
            m = re.match(r"@([\d.]+) (.*)", line)
            if not m:
                continue
            ts, body = float(m.group(1)), m.group(2)
            if body.startswith("[MPCHK]"):
                b = re.search(r" bat=(\d)", body)
                bat = b.group(1) if b else bat
            elif "got pull kind=1" in body:
                until = ts + 4
            elif "SCENE-IN-BATTLE" in body:
                fails["scene"].append(f"{nm} t={ts:.1f}: {body.split('SCENE-IN-BATTLE: ')[1].strip()}")
    bad = False
    if not crashes:
        print("PASS crash     (no crashes)")
    for c in ("char", "follower", "ghost", "state", "sync", "moved") + (("battle",) if "battle" in counts else ()) + (("scene",) if counts["scene"] or fails["scene"] else ()) + (("music",) if counts["music"] else ()) + (("world",) if counts["world"] else ()):
        f = fails[c]
        status = "PASS" if not f else "FAIL"
        bad |= bool(f)
        print(f"{status:4} {c:8} ({counts[c]} checks, {len(f)} problems)")
        for e in f[:6]:
            print("       " + e)
        if len(f) > 6:
            print(f"       ... {len(f) - 6} more")
    for w in warns[:4]:
        print("WARN " + w)
    for pid, P in players.items():
        rooms = []
        for s in P["s"]:
            if not rooms or rooms[-1] != s["room"]:
                rooms.append(s["room"])
        print(f"  {P['name']}: id {pid}, char {P['s'][-1]['want']}, {len(P['s'])} samples, rooms: {' > '.join(rooms[-8:])}")
    sys.exit(1 if bad or crashes else 0)


if __name__ == "__main__":
    main()
