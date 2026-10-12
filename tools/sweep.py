#!/usr/bin/env python3
"""Story-scene sweep: for each (room, plot) scenario from tools/sweepgen.py, a host starts in
that room at that point of the story and a client joins from another room (so it is moved
there by the mod, the way a joining player is). Both play with bots (mash, wander) for a
while; the result is checked with tools/mpcheck.py. One pair at a time.

Results: work/sweep/ch<N>/results.txt, one line per scenario:
  <room> <plot> PASS|FAIL|CRASH <details>
Failing scenarios keep their logs and final screenshots in work/sweep/ch<N>/<room>_<plot>/.

Usage: sweep.py <chapter> [--secs 45] [--from N] [--limit N] [--only room[:plot]] [--solo]
  --solo: host only, not hosting (is a crash the game's own / the test setup's?)
"""
import argparse, os, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BATTLE_ROOM = {1: ("room_field1", 100), 2: ("room_dw_cyber_maze_virokun", 100), 3: ("room_dw_couch_overworld_02", 100),
               4: ("room_dw_church_worshiproom", 100), 5: ("room_dw_garden_intro", 100)}
START = {1: "room_field1", 2: "room_dw_cyber_maze_virokun", 3: "room_dw_couch_overworld_02",
         4: "room_dw_church_worshiproom", 5: "room_dw_garden_intro"}


def run(cmd, **kw):
    return subprocess.run(cmd, **kw)


BUILD = os.environ.get("SWEEP_BUILD", "build")  # "buildv" = the vanilla test variant (tools/buildv.sh)
PREFIX = os.path.expanduser("~/.wine-dr")


def game(disp, ch, args, log):
    return subprocess.Popen([os.path.join(ROOT, "tools/run_game.sh"), str(disp), os.path.join(ROOT, BUILD, "game"), str(ch)] + args,
                            stdout=open(log, "w"), stderr=subprocess.STDOUT, env=dict(os.environ, WINEPREFIX=PREFIX))


def crashed(paths):
    for p in paths:
        try:
            if "[MPCRASH]" in open(p, errors="ignore").read():
                return True
        except FileNotFoundError:
            pass
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("chapter", type=int)
    ap.add_argument("--secs", type=int, default=45)
    ap.add_argument("--from", dest="start", type=int, default=0)
    ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--only", default="")
    ap.add_argument("--solo", action="store_true")
    ap.add_argument("--scenfile", default="", help="scenario list (default work/sweep/scen_chN.txt)")
    ap.add_argument("--clients", type=int, default=1, help="number of clients (each pair uses clients+1 displays)")
    ap.add_argument("--keep", action="store_true", help="keep logs of passing scenarios too")
    ap.add_argument("--battles", action="store_true", help="scenarios are 'enc <N>': fight encounter N")
    ap.add_argument("--tag", default="")
    ap.add_argument("--pair", type=int, default=0, help="run several sweeps at once: 0, 1, ... (own displays/port)")
    a = ap.parse_args()
    ch = a.chapter
    sf = a.scenfile or os.path.join(ROOT, f"work/sweep/scen_ch{ch}.txt")
    scen = [l.split()[:2] for l in open(sf) if l.strip()]
    if a.only:
        r, _, p = a.only.partition(":")
        scen = [s for s in scen if s[0] == r and (not p or s[1] == p)] or [[r, p or "0"]]
    scen = scen[a.start:a.start + a.limit]
    base = os.path.join(ROOT, f"work/sweep/ch{ch}{a.tag}")
    os.makedirs(base, exist_ok=True)
    run([os.path.join(ROOT, "tools/mkgamedir.sh"), os.path.join(ROOT, BUILD, "game"), str(ch), os.path.join(ROOT, BUILD, f"ch{ch}.win")], check=True)
    results = open(os.path.join(base, "results.txt"), "a")
    global PREFIX
    # Each pair has its own Wine prefix (and so its own wineserver), restarted between
    # scenarios: killed games leak sockets and handles into the wineserver, which slows
    # every later game down. (~/.wine-dr-pN: `cp -al ~/.wine-dr`, with its own save folder.)
    if a.pair:
        PREFIX = os.path.expanduser(f"~/.wine-dr-p{a.pair}")
    d0 = 91 + (a.clients + 1) * a.pair
    port = str(27000 + a.pair * 1000)

    def kill_mine():
        # Only this pair's games (their command lines name a port in this pair's range).
        pat = f"DELTARUNE.exe .*-mp(port|join) [^ ]*:?{27 + a.pair}[0-9][0-9][0-9]( |$)"
        run(["pkill", "-f", pat])
        run(["wineserver", "-k"], env=dict(os.environ, WINEPREFIX=PREFIX))
        # Wait until they're really gone (and the UDP port is free again).
        for _ in range(40):
            if run(["pgrep", "-f", pat], capture_output=True).returncode != 0:
                break
            time.sleep(0.5)
        else:
            run(["pkill", "-9", "-f", pat])
            time.sleep(2)

    for i, (rm, plot) in enumerate(scen):
        # A fresh port per scenario: Wine can keep a killed game's socket open for a while.
        port = str(27000 + a.pair * 1000 + (i + a.start) % 1000)
        out = os.path.join(base, f"{rm}_{plot}")
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        kill_mine()
        time.sleep(1)
        host_t = f"party,room:{rm},plot:{plot},check,mash,wander,log"
        # Light World rooms start in the Light World (Kris and Susie), like the real game.
        lw_ch1 = ("room_krisroom", "room_alphysclass", "room_insidecloset", "room_schooldoor", "room_torhouse")
        lw_other = ("room_lw_", "room_town", "room_krisroom", "room_torhouse", "room_schooldoor", "room_library", "room_alphysclass", "room_diner", "room_torbathroom", "room_kris")
        if rm.startswith(lw_ch1 if ch == 1 else lw_other):
            host_t += ",lightworld"
        client_t = f"party,room:{START[ch]},plot:{plot},check,mash,wander,log"
        if a.battles:
            # Both in the same room; the host starts the encounter, bots fight (tough enemies).
            room0, p0 = BATTLE_ROOM[ch]
            host_t = f"party,room:{room0},plot:{p0},battle:{plot},bot,botrand,log,tough,check"
            client_t = f"party,room:{room0},plot:{p0},bot,botrand,log,tough,check" + os.environ.get("SWEEP_CLIENT_EXTRA", "")
        logs = [os.path.join(out, "host.log")]
        if a.solo:
            game(d0, ch, ["-mpport", port, "-mptest", host_t], logs[0])
        else:
            game(d0, ch, ["-mpport", port, "-mphost", "-mpname", "Host", "-mpchar", "1", "-mptest", host_t], logs[0])
            time.sleep(3)
            for k in range(1, a.clients + 1):
                logs.append(os.path.join(out, f"client{k}.log"))
                game(d0 + k, ch, ["-mpjoin", "127.0.0.1:" + port, "-mpname", f"P{k + 1}", "-mpchar", str(k + 1), "-mptest",
                                  client_t], logs[k])
                time.sleep(1)
        end = time.time() + a.secs + 12
        while time.time() < end and not crashed(logs):
            time.sleep(1)
        if crashed(logs):
            time.sleep(2)
        for k, l in enumerate(logs):
            run(["scrot", "-o", os.path.join(out, f"end_{k}.png")], env=dict(os.environ, DISPLAY=f":{d0 + k}"))
        kill_mine()
        time.sleep(1)
        if a.solo:
            status = "CRASH" if crashed(logs) else "PASS"
            detail = ""
            if crashed(logs):
                for line in open(logs[0], errors="ignore"):
                    if "[MPCRASH]" in line:
                        detail = line.split("[MPCRASH]", 1)[1].strip()[:300]
        else:
            r = run([sys.executable, os.path.join(ROOT, "tools/mpcheck.py"), out, "--strict-end"], capture_output=True, text=True)
            lines = r.stdout.splitlines()
            bad = [l.strip() for l in lines if l.startswith("FAIL")]
            status = "CRASH" if any("crash" in l for l in bad) else ("FAIL" if r.returncode else "PASS")
            # first problem line under each failing check
            detail = " ; ".join(bad)
            for j, l in enumerate(lines):
                if l.startswith("FAIL") and j + 1 < len(lines) and lines[j + 1].startswith("       "):
                    detail += " || " + lines[j + 1].strip()[:250]
            open(os.path.join(out, "check.txt"), "w").write(r.stdout)
        line = f"{rm} {plot} {status} {detail}"
        print(f"[{i + 1}/{len(scen)}] {line}", flush=True)
        results.write(line + "\n")
        results.flush()
        if status == "PASS" and not a.keep:
            shutil.rmtree(out, ignore_errors=True)
    kill_mine()


if __name__ == "__main__":
    main()
