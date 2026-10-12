#!/usr/bin/env python3
"""Real-game-flow multiplayer test driver.

Starts N instances of a chapter WITHOUT the -mptest shortcuts that skip the menus, drives
them with real key presses (xdotool) through the file select / name entry / F9 multiplayer
menu like a player would, and records [MPCHK] self-check lines (see scr_mp_test.gml) and
screenshots. Check the result with tools/mpcheck.py.

Usage: flow.py <scenario> [options]   (see SCENARIOS below / --help)
"""
import argparse, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAVEDIR = os.path.expanduser("~/.wine-dr/drive_c/users/ai/AppData/Local/DELTARUNE")


class Game:
    def __init__(self, idx, out, chapter, args):
        self.idx = idx
        self.disp = 91 + idx
        self.name = "host" if idx == 0 else f"client{idx}"
        self.log = os.path.join(out, self.name + ".log")
        self.out = out
        cmd = [os.path.join(ROOT, "tools/run_game.sh"), str(self.disp), os.path.join(ROOT, "build/game"), str(chapter)] + args
        self.proc = subprocess.Popen(cmd, stdout=open(self.log, "w"), stderr=subprocess.STDOUT)

    def keys(self, *seq):
        subprocess.run([os.path.join(ROOT, "tools/keys.sh"), str(self.disp)] + list(seq), check=True)

    def shot(self, tag):
        path = os.path.join(self.out, f"{tag}_{self.name}.png")
        subprocess.run(["scrot", "-o", path], env=dict(os.environ, DISPLAY=f":{self.disp}"))
        return path

    def last(self):
        """Latest self-check line as a dict."""
        try:
            lines = [l.split(" ", 1)[1] if l.startswith("@") else l for l in open(self.log, errors="ignore")]
            lines = [l for l in lines if l.startswith("[MPCHK] t=")]
        except FileNotFoundError:
            return {}
        if not lines:
            return {}
        return dict(re.findall(r"(\w+)=(\S*)", lines[-1]))

    def wait(self, pred, timeout, what):
        end = time.time() + timeout
        while time.time() < end:
            d = self.last()
            if d and pred(d):
                return d
            time.sleep(0.5)
        raise TimeoutError(f"{self.name}: timed out waiting for {what}; last={self.last()}")


def log(msg):
    print(f"[flow {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def menu_retry(g, what, seq):
    """Runs a key sequence at the file select until the game leaves PLACE_MENU."""
    g.wait(lambda d: d.get("room") == "PLACE_MENU", 180, "file select")
    for attempt in range(4):
        time.sleep(4)
        seq()
        try:
            g.wait(lambda d: d.get("room") != "PLACE_MENU", 20, what)
            return
        except TimeoutError:
            log(f"{g.name}: {what} did not start, retrying")
            g.keys("x", "x", "x", "x:1")
    raise TimeoutError(f"{g.name}: could not {what}")


def new_game(g):
    """From launch to a new file in slot 1, the way a player does it."""
    menu_retry(g, "new game", lambda: g.keys("z:1.5", "z:3", "z", "Down", "Down", *["Right"] * 7, "z:2", "Right", "z:2"))


def load_game(g, slot):
    menu_retry(g, "load game", lambda: g.keys(*(["Down"] * slot), "z:1.5", "z:2"))


def f9_host(g):
    g.keys("F9:0.6", "Down", "Down", "z:1")


def f9_join(g, char, nchars):
    # rows when offline: name, char, host, ip, join, close. "Play as" cycles with Right.
    want = int(g.last().get("want", "1"))
    g.keys("F9:0.6", "Down", *(["Right"] * ((char - want) % nchars)), "Down", "Down", "Down", "z:1")


def free_roam(d):
    return d.get("room", "").startswith("room_") and d.get("ia") == "0" and d.get("sst") == "0" and d.get("bat") == "0" and d.get("x") != "-1"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("chapter", type=int)
    ap.add_argument("--clients", type=int, default=1)
    ap.add_argument("--chars", default="2,3,4,1,2,3,4", help="characters picked by the clients in the F9 menu")
    ap.add_argument("--start", default="new", help="new | load:<slot>")
    ap.add_argument("--makesave", default="", help="<room>:<plot>: first create save slot 0 there (in-game save)")
    ap.add_argument("--test", default="check,mash", help="-mptest tokens for every instance (no shortcuts)")
    ap.add_argument("--hosttest", default="", help="extra tokens for the host")
    ap.add_argument("--clienttest", default="", help="extra tokens for the clients")
    ap.add_argument("--connect", default="ingame", help="ingame | menu (connect at the file select)")
    ap.add_argument("--secs", type=int, default=120, help="how long to keep playing after everyone is connected")
    ap.add_argument("--shots", type=int, default=15, help="screenshot every N seconds")
    ap.add_argument("--out", default=os.path.join(ROOT, "work/flow"))
    ap.add_argument("--keep", action="store_true", help="leave the games running")
    ap.add_argument("--nobuild", action="store_true")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    for f in os.listdir(a.out):
        if f.endswith((".log", ".png")):
            os.remove(os.path.join(a.out, f))
    if not a.nobuild:
        subprocess.run([os.path.join(ROOT, "patcher/bin/out/drm-patcher"), os.path.join(ROOT, f"DELTARUNE/chapter{a.chapter}_windows/data.win"),
                        os.path.join(ROOT, f"build/ch{a.chapter}.win"), os.path.join(ROOT, "mod"), str(a.chapter)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([os.path.join(ROOT, "tools/mkgamedir.sh"), os.path.join(ROOT, "build/game"), str(a.chapter), os.path.join(ROOT, f"build/ch{a.chapter}.win")], check=True)
    subprocess.run(["pkill", "-x", "DELTARUNE.exe"])
    time.sleep(1)
    # Fresh multiplayer settings, as on a new install (every instance shares this file).
    try:
        os.remove(os.path.join(SAVEDIR, "multiplayer.ini"))
    except FileNotFoundError:
        pass

    if a.makesave:
        rm, pl = a.makesave.split(":")
        log(f"creating a save in {rm} (plot {pl})")
        g = Game(0, a.out, a.chapter, ["-mptest", f"party,room:{rm},plot:{pl},save,check"])
        end = time.time() + 120
        while time.time() < end and "[MPCHK] saved" not in open(g.log, errors="ignore").read():
            time.sleep(1)
        time.sleep(2)
        subprocess.run(["pkill", "-x", "DELTARUNE.exe"])
        time.sleep(2)
        os.rename(g.log, os.path.join(a.out, "makesave.txt"))

    chars = [int(c) for c in a.chars.split(",")]
    games = []
    for i in range(a.clients + 1):
        extra = a.hosttest if i == 0 else a.clienttest
        tokens = ",".join(t for t in [a.test, extra] if t)
        games.append(Game(i, a.out, a.chapter, ["-mpname", "Host" if i == 0 else f"P{i + 1}", "-mptest", tokens]))
        time.sleep(2)
    try:
        def connect():
            for attempt in range(4):
                log("host: F9 -> Host a game")
                f9_host(games[0])
                try:
                    games[0].wait(lambda d: d.get("on") == "1", 10, "hosting")
                    break
                except TimeoutError:
                    games[0].keys("Escape", "F9:0.5")  # close the menu if it is open
                    if "[MP] Hosting" in open(games[0].log, errors="ignore").read():
                        break
            for g in games[1:]:
                for attempt in range(4):
                    log(f"{g.name}: F9 -> Play as {chars[g.idx - 1]} -> Join")
                    f9_join(g, chars[g.idx - 1], 3 if a.chapter == 1 else 4)
                    try:
                        g.wait(lambda d: d.get("on") == "1", 20, "connection")
                        break
                    except TimeoutError:
                        if attempt == 3:
                            raise
                        g.keys("x:0.5")
        if a.connect == "menu":
            for g in games:
                g.wait(lambda d: d.get("room") == "PLACE_MENU", 120, "file select")
            time.sleep(3)
            connect()
        for g in games:
            if a.start == "new":
                log(f"{g.name}: new game")
                new_game(g)
            else:
                log(f"{g.name}: load slot {a.start.split(':')[1]}")
                load_game(g, int(a.start.split(":")[1]))
        if a.connect == "ingame":
            for g in games:
                g.wait(free_roam, 600, "free roam after the opening")
                log(f"{g.name}: in free roam: {g.last().get('room')}")
                g.shot("ready")
            connect()
        t0 = time.time()
        n = 0
        while time.time() - t0 < a.secs:
            time.sleep(min(a.shots, max(0, a.secs - (time.time() - t0))))
            n += 1
            for g in games:
                g.shot(f"s{n:02d}")
            log("  ".join(f"{g.name}:{g.last().get('room')}@{g.last().get('x')},{g.last().get('y')} sst={g.last().get('sst')} ia={g.last().get('ia')}" for g in games))
    finally:
        if not a.keep:
            subprocess.run(["pkill", "-x", "DELTARUNE.exe"])
    log("done; check with tools/mpcheck.py " + a.out)


if __name__ == "__main__":
    main()
