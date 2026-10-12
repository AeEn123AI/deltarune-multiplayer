#!/usr/bin/env python3
"""LLM-driven playthrough: every player is a vision-model agent that looks at its game's screen
(plus the self-check state line) and presses real keys, like a person playing co-op.
Crashes ([MPCRASH]) and desync are then checked with tools/mpcheck.py.

Usage: aiplay.py <chapter> [--clients 1] [--secs 900] [--start new|load:N] [--model ...] [--out DIR]
Models: any OpenAI-compatible chat model from the opencode config (see tools/llm.py).
"""
import argparse, json, os, re, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow, llm

ROOT = flow.ROOT
SYSTEM = """You are a person playing DELTARUNE co-op (a multiplayer mod) and you want to PROGRESS THROUGH THE STORY as far as possible. You control ONE player from screenshots; other humans play at the same time.
Controls: arrow keys move (hold to walk); Z = confirm/talk/interact/advance text; X = cancel/run; C = open the menu (avoid it; if a menu is open press X). In battles: Z on FIGHT, Z to confirm target, press Z again at the attack timing; ACT/MERCY also fine; dodge bullets with arrows.
How to play well:
- Advance every dialogue box with Z. Talk to people (face them and press Z), examine objects, walk through doors and room exits, follow the story marker/NPC hints, pick up items, save when offered.
- Do NOT stay in one room for long. Once you have talked to the people/objects here, LEAVE through an exit, preferring exits you have not used. Prefer new rooms over rooms in your visited list.
- Pay attention to your NOTES (what you did so far, the current objective) and the HARNESS HINTS in the state line, and follow them.
- Stay roughly together with the other players when it makes sense, but do not wait for them.
Reply with ONLY one JSON object: {"see": "<short description of the screen>", "plan": "<what you do next and why, short>", "keys": ["Up*1.2", "z", ...]}
Key format: key name (up,down,left,right,z,x,c,Return) optionally *seconds to HOLD (walking: *0.4 to *2.5). Plain 'z' is a tap. At most 12 keys per reply."""
NOTES_PROMPT = """You keep the logbook of a DELTARUNE player. Given the old notes and the latest turns, write the NEW notes in under 150 words: 1) story progress so far (places, events, people met), 2) CURRENT OBJECTIVE and where to go next (a concrete guess, e.g. which exit to try), 3) things that did NOT work (so they are not repeated). Plain text only."""
KEYMAP = {"up": "Up", "down": "Down", "left": "Left", "right": "Right", "z": "z", "x": "x", "c": "c", "return": "Return", "enter": "Return"}


class Agent(threading.Thread):
    def __init__(self, g, others, a, stop, pause):
        super().__init__(daemon=True)
        self.g, self.others, self.a, self.stop, self.pause = g, others, a, stop, pause
        self.hist = []
        self.n = 0
        self.errors = 0
        self.notes = "Just started playing."
        self.visits = {}            # room -> number of turns spent there
        self.room_turns = 0
        self.cur_room = None
        self.plot = None
        self.plot_turn = 0
        self.lastkey, self.same = None, 0
        self.recent = []
        self.last_z = False
        self.tr = open(os.path.join(a.out, f"agent_{g.name}.jsonl"), "w")

    def state(self):
        d = self.g.last()
        room = d.get("room")
        s = f"you: room={room} x={d.get('x')} y={d.get('y')} battle={d.get('bat')} sync={d.get('sst')} {'DIALOGUE/CUTSCENE OPEN (Z advances)' if d.get('ia') == '1' else 'free to walk (Z only interacts with what you face)'} story={d.get('plot')}"
        for o in self.others:
            od = o.last()
            s += f"; {o.name}: room={od.get('room')} x={od.get('x')} y={od.get('y')}"
        return s

    def hints(self):
        """Harness observations the model can't make from one screenshot (bookkeeping per turn)."""
        d = self.g.last()
        room, h = d.get("room"), []
        if room != self.cur_room:
            self.cur_room, self.room_turns = room, 0
        self.room_turns += 1
        self.visits[room] = self.visits.get(room, 0) + 1
        if d.get("plot") != self.plot:
            self.plot, self.plot_turn = d.get("plot"), self.n
        key = (room, d.get("x"), d.get("y"), d.get("ia"))
        self.same = self.same + 1 if key == self.lastkey else 0
        self.lastkey = key
        h.append("rooms visited so far (turns spent): " + ", ".join(f"{r}({n})" for r, n in list(self.visits.items())[-12:]))
        if self.same >= 3 and d.get("ia") == "0" and d.get("bat") == "0":
            h.append("you have NOT MOVED for several turns: you are blocked - walk a different direction")
        if self.room_turns >= 12 and d.get("ia") == "0":
            h.append(f"you have spent {self.room_turns} turns in this room: LEAVE it through an exit you haven't used")
        if self.n - self.plot_turn >= 40:
            h.append(f"the story has not advanced for {self.n - self.plot_turn} turns: go somewhere new, talk to every person, interact with things")
        for o in self.others:
            od = o.last()
            if od.get("room") and od.get("room") != room and room and room.startswith("room_"):
                h.append(f"{o.name} is in another room ({od.get('room')})")
        return "HARNESS HINTS: " + " | ".join(h)

    def focus(self):
        env = dict(os.environ, DISPLAY=f":{self.g.disp}")
        w = ""
        for c in subprocess.run(["xdotool", "search", "--onlyvisible", "--class", "deltarune"], env=env, capture_output=True, text=True).stdout.split():
            g = subprocess.run(["xdotool", "getwindowgeometry", c], env=env, capture_output=True, text=True).stdout
            m = re.search(r"Geometry: (\d+)x", g)
            if m and int(m.group(1)) >= 320:
                w = c
        if w:
            subprocess.run(["xdotool", "mousemove", "--window", w, "320", "240", "click", "1"], env=env)

    def press(self, spec):
        m = re.match(r"^\s*(\w+)(?:\*([\d.]+))?\s*$", str(spec))
        if not m or m.group(1).lower() not in KEYMAP:
            return
        k, hold = KEYMAP[m.group(1).lower()], min(float(m.group(2) or 0.12), 3.0)
        env = dict(os.environ, DISPLAY=f":{self.g.disp}")
        subprocess.run(["xdotool", "keydown", k], env=env)
        time.sleep(hold)
        subprocess.run(["xdotool", "keyup", k], env=env)
        time.sleep(0.2)

    def update_notes(self):
        try:
            txt = "OLD NOTES:\n" + self.notes + "\n\nLATEST TURNS:\n" + "\n".join(self.recent[-14:])
            self.notes = llm.chat(self.a.provider, self.a.model, [{"role": "system", "content": NOTES_PROMPT}, {"role": "user", "content": txt}],
                                  max_tokens=self.a.max_tokens)[:1200]
        except Exception as e:
            self.tr.write(json.dumps({"n": self.n, "notes_error": str(e)[:150]}) + "\n")

    def unstick(self):
        """The model is looping: a few random walks (like a player mashing around)."""
        import random
        for _ in range(5):
            self.press(f"{random.choice(['up', 'down', 'left', 'right'])}*{random.uniform(0.6, 2.0):.1f}")
            if random.random() < 0.4:
                self.press("z")

    def run(self):
        while not self.stop.is_set():
            if self.pause.is_set():
                time.sleep(0.5)
                continue
            self.n += 1
            shot = self.g.shot("ai")
            state, hints = self.state(), self.hints()
            msgs = [{"role": "system", "content": SYSTEM}]
            msgs += self.hist[-4:]
            msgs.append({"role": "user", "content": [{"type": "text", "text": f"NOTES: {self.notes}\n{state}\n{hints}"}, llm.image_part(shot)]})
            try:
                out = llm.chat(self.a.provider, self.a.model, msgs, max_tokens=self.a.max_tokens)
                j = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
                keys = list(j.get("keys", []))[:12]
                self.errors = 0
            except Exception as e:
                self.errors += 1
                self.tr.write(json.dumps({"n": self.n, "error": str(e)[:200]}) + "\n")
                if self.errors > 8:
                    return
                keys, j = ["z"], {"see": "?"}
            self.hist.append({"role": "user", "content": state})
            self.hist.append({"role": "assistant", "content": json.dumps({"see": j.get("see", ""), "plan": j.get("plan", ""), "keys": keys})})
            self.recent.append(f"{state} | saw: {j.get('see', '')} | plan: {j.get('plan', '')}")
            self.tr.write(json.dumps({"n": self.n, "t": time.time(), "state": state, "see": j.get("see"), "plan": j.get("plan"), "keys": keys}) + "\n")
            self.tr.flush()
            # The screenshot is several seconds old by now: don't re-open the dialogue we just closed.
            d = self.g.last()
            if d.get("ia") == "0" and d.get("bat") == "0" and self.last_z and self.same >= 1:
                keys = [k for k in keys if str(k).strip().lower() != "z"] or ["left*0.3"]
            self.last_z = any(str(k).strip().lower() == "z" for k in keys)
            self.focus()
            for k in keys:
                if self.stop.is_set() or self.pause.is_set():
                    break
                self.press(k)
            if self.n % 10 == 0:
                self.update_notes()
            if self.same >= 6 or self.room_turns >= 30:
                self.tr.write(json.dumps({"n": self.n, "unstick": True}) + "\n")
                self.unstick()
                self.same, self.room_turns = 0, 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("chapter", type=int)
    ap.add_argument("--clients", type=int, default=1)
    ap.add_argument("--chars", default="2,3,4,1")
    ap.add_argument("--secs", type=int, default=5400)
    ap.add_argument("--start", default="new")
    ap.add_argument("--provider", default="commandcode-goat")
    ap.add_argument("--model", default="deepseek/deepseek-v4.1-flash")
    ap.add_argument("--max-tokens", dest="max_tokens", type=int, default=3500)
    ap.add_argument("--out", default=os.path.join(ROOT, "work/ai"))
    ap.add_argument("--nobuild", action="store_true")
    ap.add_argument("--test", default="check,log")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for f in os.listdir(a.out):
        if f.endswith((".log", ".png", ".jsonl")):
            os.remove(os.path.join(a.out, f))
    if not a.nobuild:
        subprocess.run([os.path.join(ROOT, "patcher/bin/out/drm-patcher"), os.path.join(ROOT, f"DELTARUNE/chapter{a.chapter}_windows/data.win"),
                        os.path.join(ROOT, f"build/ch{a.chapter}.win"), os.path.join(ROOT, "mod"), str(a.chapter)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run([os.path.join(ROOT, "tools/mkgamedir.sh"), os.path.join(ROOT, "build/game"), str(a.chapter), os.path.join(ROOT, f"build/ch{a.chapter}.win")], check=True)
    subprocess.run(["pkill", "-x", "DELTARUNE.exe"])
    time.sleep(1)
    try:
        os.remove(os.path.join(flow.SAVEDIR, "multiplayer.ini"))
    except FileNotFoundError:
        pass
    chars = [int(c) for c in a.chars.split(",")]
    games = []
    for i in range(a.clients + 1):
        games.append(flow.Game(i, a.out, a.chapter, ["-mpname", "Host" if i == 0 else f"P{i + 1}", "-mptest", a.test]))
        time.sleep(2)
    stop = threading.Event()
    try:
        for g in games:
            if a.start == "new":
                flow.new_game(g)
            else:
                flow.load_game(g, int(a.start.split(":")[1]))
        # The opening cutscene needs a player: the agents play it, then everyone connects.
        stop_pause = threading.Event()
        pause = threading.Event()
        agents = [Agent(g, [o for o in games if o is not g], a, stop, pause) for g in games]
        for ag in agents:
            ag.start()
        end = time.time() + 1500
        while not all(flow.free_roam(g.last()) for g in games):
            if time.time() > end:
                raise TimeoutError("opening not finished: " + str([g.last().get("room") for g in games]))
            time.sleep(3)
        pause.set()
        time.sleep(4)
        flow.log("in free roam; connecting")
        for attempt in range(5):
            flow.f9_host(games[0])
            try:
                games[0].wait(lambda d: d.get("on") == "1", 10, "hosting")
                break
            except TimeoutError:
                if attempt == 4:
                    raise
                games[0].keys("Escape", "x:0.5", "x:0.5")
        for g in games[1:]:
            for attempt in range(4):
                flow.f9_join(g, chars[g.idx - 1], 3 if a.chapter == 1 else 4)
                try:
                    g.wait(lambda d: d.get("on") == "1", 20, "connection")
                    break
                except TimeoutError:
                    g.keys("x:0.5")
        pause.clear()
        t0 = time.time()
        while time.time() - t0 < a.secs:
            time.sleep(5)
            if any("[MPCRASH]" in open(g.log, errors="ignore").read() for g in games):
                flow.log("CRASH detected")
                time.sleep(3)
                break
            if not any(ag.is_alive() for ag in agents):
                break
        for g in games:
            g.shot("final")
    finally:
        stop.set()
        time.sleep(1)
        subprocess.run(["pkill", "-x", "DELTARUNE.exe"])
    subprocess.run([sys.executable, os.path.join(ROOT, "tools/mpcheck.py"), a.out])


if __name__ == "__main__":
    main()
