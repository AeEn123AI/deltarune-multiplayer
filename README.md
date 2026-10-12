# DELTARUNE Multiplayer

> **Note: this project was written almost entirely by AI** (Claude, via Claude Code), directed and
> tested by a human. Expect rough edges and bugs, and please don't treat the code as hand-audited.
> It contains no DELTARUNE game files: the patcher modifies *your own* copy of the game.

Online (network) co-op multiplayer for DELTARUNE Chapters 1–5, each player on their own PC, in the style of Block Tales' multiplayer:

* **Pick a party member.** Each player plays as Kris, Susie, Ralsei or (Chapter 2+) Noelle.
  Your character is what you walk around as, and in battle you choose that character's
  actions (FIGHT / ACT / MAGIC / ITEM / SPARE / DEFEND) and press for their attacks.
* **Everyone dodges.** In the bullet phase every player controls their own SOUL. A hit only
  hurts the character *you* play. If all of your characters are down, hits do nothing.
  Your grazes add to the shared TP bar.
* **Explore independently.** Walk and talk to NPCs on your own, even in different rooms.
  Other players appear as name-tagged characters when you're in the same room. A party
  member someone is playing never also follows you as an NPC, wherever that player is.
* **Battles and story cutscenes bring everyone together.** When someone touches an enemy
  or triggers a story cutscene, everyone else is pulled into that room. Cutscenes play in
  each player's own game, and dialogue choices follow whoever triggered the cutscene.
* **Shared progress.** Story flags, items, gold, equipment and HP are kept in sync. The host's
  world is the shared one.
* **Built for bad connections.** It uses UDP with its own reliability layer: position updates
  are latest-only, and game events are acknowledged, retransmitted and delivered in order.
  Measured traffic is roughly 0.2–0.5 KB/s per player while walking and up to ~2 KB/s on
  the host during a 3-player battle. Tested at ~500 ms round-trip, 5% packet loss and
  64 kbit/s.

Up to 8 players can connect. Each party member is controlled by one player. Extra players,
or players whose character isn't in the party, watch (and dodge, harmlessly) in battle.
The host controls any party member nobody picked.

## Online multiplayer, not local

This is **network multiplayer**: every player runs their **own copy of the game on their own
computer** and they connect over the internet (or a LAN) with UDP. It is not split-screen,
not shared-keyboard, and not Steam Remote Play. Each player has their own window, their own
keyboard or controller, and can walk to a different room from everyone else.

```
   Player 1 (host)                              Player 2 (client)
 +------------------+     UDP, port 26510     +------------------+
 | DELTARUNE + mod  | <---------------------> | DELTARUNE + mod  |
 | own screen/input |   positions, battle,    | own screen/input |
 +------------------+   story state, music    +------------------+
          ^                                              
          |  UDP     More players (up to 8) connect the same way
```

* One player hosts (forward **UDP 26510** on their router); the others join by typing the
  host's IP address in the F9 menu. There is no relay or central server.
* In the same room you see each other's characters walk around live, with name tags.
* The protocol is reliable-UDP with its own acknowledgements, so it copes with lag and
  packet loss (see "Network protocol" below).

## Installing

You need DELTARUNE (the Steam/itch version with `chapter1_windows` … `chapter5_windows`
folders). Every player needs the mod installed.

**Windows:** unzip `DeltaruneMultiplayer-windows.zip` anywhere and run `Install.bat`. It
finds the default Steam install automatically. Otherwise, drag your DELTARUNE folder onto
`Install.bat`.

**Linux / Steam Deck (Proton):** unzip `DeltaruneMultiplayer-linux.zip` and run
`./install.sh` (or `./install.sh /path/to/DELTARUNE`).

The installer keeps the original as `data.win.vanilla` in each chapter folder. Re-running it
(e.g. to update the mod) always patches from that original. `Uninstall.bat` /
`uninstall.sh` restores the originals.

## Playing

1. Everyone starts DELTARUNE, picks the **same chapter** and loads (or starts) a game.
2. Press **F9** to open the multiplayer menu.
   * **Name** and **Play as**: use left/right to pick your character. You can change it any
     time; it takes effect from the next battle turn.
   * The host chooses **Host a game**. The default port is UDP **26510**.
   * Everyone else sets **Host address** to the host's IP (e.g. `203.0.113.7:26510`) and
     chooses **Join game**.
3. Joining players are moved next to the host and receive the host's progress.

Handy things:
* **F8** (or "Go to ..." in the F9 menu) takes you to where the host is (the host goes to the
  first other player). Use it if you get stuck, a puzzle or room is out of step, or you simply
  want to catch up.
* **F7** (or "Stop all music and sounds" in the F9 menu) stops everything that is playing. Use it if the
  music gets out of step; the game starts a room's music again the next time you enter a room.
* Two players can't play the same character: the one who joined later is switched
  automatically, and the F9 character picker skips characters that are taken.
* When a chapter ends and you start the next one within a few minutes, the session continues
  by itself: the host hosts again and the others join again.
* After a Game Over and Continue, everyone is taken back to the host.
* If another player moves the story on while you are standing in a room, the room is
  rebuilt (same spot) a moment later so it matches theirs.
* Players are in the same world (Light / Dark) as whoever they join or are pulled to.

The player list (top-left) shows each player's character, ping and whether they're in a
battle or cutscene. The yellow line at the top tells you whose turn it is in battle
("Your turn: choose Susie's action!" / "P2 is choosing for Susie...").

**Playing over the internet:** the host must forward **UDP port 26510** on their router.
Alternatively, everyone can join the same virtual LAN (Tailscale, ZeroTier, Radmin VPN…) and
use the host's address on that network. A UDP tunnelling service (e.g. playit.gg) also
works.

Settings are saved in `multiplayer.ini` next to DELTARUNE's save files. For testing, you
can also launch a chapter with `-mphost`, `-mpjoin <ip[:port]>`, `-mpname <name>`,
`-mpchar <1-4>` and `-mpport <port>`.

## How it works

Every player runs the full game; the mod keeps the copies in step instead of streaming
video or state.

| Situation | What is synchronised |
|---|---|
| Walking around | Your room, position and current sprite, ~10×/s and only when they change (unreliable, latest wins). Others draw you as a smoothly interpolated "ghost". |
| Story state | `plot`, flags (≥60), items, key items, equipment, gold, party, HP/stats. Changes are scanned every 2 frames and sent as small deltas. The full state goes out once on join. A player who loads a save re-fetches the host's state, and a host who loads pushes theirs to everyone. |
| Cutscene | If `global.interact` goes non-zero without the player pressing Z on something (or a door hands straight over to it), it may be a story cutscene. It counts once a new cutscene controller appears or the story progresses within 20 frames, or if it lasts over 4 s (so "you can't go that way" messages don't pull anyone). Others are warped to where it triggered, with the story progress from just before it, so the same cutscene starts in their game; for cutscenes that start on entering a room they enter that room too. Story changes are held back while this is decided, so they can't stop the cutscene from triggering for the others. A player busy with their own cutscene joins afterwards if the other one is still going; pulls from earlier in the story than you are are ignored. If it still doesn't trigger, they watch frozen, see the leader's dialogue, and are released when it ends (or when the leader is walking around again). `obj_choicer_neo` answers follow the leader. |
| Battle start | The initiator's encounter number is sent. Others start the same encounter (same music and "!" intro, same party) through an invisible `obj_testoverworldenemy`. Players busy in their own cutscene join after it ends. Late joiners enter at the start of the next turn. |
| Battle menu | The player who owns the character whose turn it is drives the menu. Their button presses, with the original frame spacing (at least 5 frames apart, so a press the menu would ignore as too early is never accepted in someone else's replay), are replayed in everyone's game, so every game's menu state machine (TP, items, ACT partners, going back with X) stays identical. |
| Attack timing | Each player presses only for their own character's bolts. Results are shared, and remote bolts wait for their owner's result. Damage is computed identically from the points. |
| Randomness | `random_set_seed` with the same seed at the start of the attack phase, enemy dialogue phase and bullet phase. |
| Bullet phase | Fully local: your SOUL, your hits (`scr_damage` re-targets to your character). The HP of each character is owned by its player and broadcast when it changes. |
| Turn barrier | Before each new turn, everyone reports "done" plus their TP gain from grazing. The host sends `TURN_GO` with the authoritative TP (base + everyone's grazes), HP, enemy HP, mercy and which enemies remain, plus who controls which character this turn. |
| Game over | A party wipe in any player's game is broadcast, so everyone in that battle goes down together. |

### Network protocol

One UDP socket. Each datagram (≤1200 bytes) carries a cumulative ack plus a 32-bit
selective-ack field and any number of records. Reliable records are retransmitted with an
RTT-based timeout and back-off, at most 4 datagrams per frame. Unreliable records (positions)
replace older queued ones and are dropped if they arrive out of order. The host is the hub and
forwards everything to the other players. Protocol version 2 (older versions can't join). Peers time out after 30 s of silence.

### Source layout

```
mod/gml/      new code: scr_mp_net (transport), scr_mp_core, scr_mp_world (ghosts,
              sprites, shared state), scr_mp_sync (cutscenes/pulls), scr_mp_battle,
              scr_mp_ui (F9 menu/HUD), scr_mp_test (automation), obj_mp_controller,
              obj_mp_ghost
mod/hooks/    small edits to the game's own code (see core.hook)
patcher/      drm-patcher: compiles the mod into a chapter's data.win (UndertaleModLib)
tools/        test harness: run several game instances under Wine + Xvfb
```

Building the patcher needs the .NET 10 SDK and an UndertaleModTool checkout
(`-p:UTMTRoot=...`, default `~/tools/UndertaleModTool`). The patcher's other commands are:

```
drm-patcher <in data.win> <out data.win> <mod dir> <chapter>   # patch one file
drm-patcher install|uninstall [DELTARUNE folder]
drm-patcher --decompile <data.win> <code entry>...             # inspect game code
drm-patcher --find-object <data.win> <object>                  # which rooms contain it
```

The patcher refuses to build if the mod references an object, sprite, sound, script or room
that the target chapter doesn't have.

## Testing that was done

All tests use real game instances under Wine on virtual displays. Each game writes a
self-check line twice a second (`-mptest check`): which character it draws for you, which
followers it draws, where it shows the other players, a hash of the shared story state, and
its sync state. `tools/mpcheck.py` compares these between players and fails if anyone is
drawn as the wrong character, a played character also appears as an NPC follower, another
player is shown somewhere they aren't, the shared state differs, anyone is left frozen, or
a game crashes.

* **Real game flow** (`tools/flow.py`): games are driven with real key presses through the
  file select (new game with name entry, or loading a save) and the F9 menu (pick a
  character, host, join), then a bot plays. Done in Chapter 4 (new game; 2 and 3 players;
  connecting at the file select or after starting; 250 ms / 5% loss), Chapter 2 (new game)
  and Chapter 1 (loading a save). The Chapter 4 opening shares the kitchen and church
  cutscenes between players.
* **Story cutscenes** (`tools/cutscenes.sh`): in Chapters 2–5 the host triggers a real
  cutscene (on entering a room, or by walking into it) while the others are in another room.
  They are pulled in and the cutscene plays in their games too (2 and 3 players).
* **Story and battle sweeps** (`tools/sweepgen.py`, `tools/sweep.py`): every room with story
  objects is visited at each story point it checks (about 560 scenarios in chapters 1-5), and
  every encounter is fought (3+ turns, battle state compared per turn), each with a host and
  a client joining from elsewhere. Crashes that also happen single-player are the game's own
  (rooms/encounters the game can't normally reach) and are listed in TODO.md. Late joiners
  (3 players) are pulled into a running battle.
* **Battles** (`tools/regress.sh`): 3 players in chapters 1–5, battle state identical every
  turn; earlier also ~500 ms RTT, 5% loss, 64 kbit/s.

## Known limitations

* Only cutscenes triggered by walking or entering a room are shared. Cutscenes started by
  pressing Z on something play only for the player who did it (their story changes still
  sync). Cutscenes that depend on a player's exact route may not trigger in the other
  games; those players watch frozen (seeing the leader's dialogue) until it ends and are
  then moved to the leader.
* Boss battles with heavily scripted mechanics haven't been played through in multiplayer.
  Turn-end snapshots fix up HP, TP, mercy and defeated enemies, but other enemy-specific
  state could still drift.
* Remote players' text boxes advance on their own, so players can be a few seconds apart.
  The turn barrier brings everyone back together each turn.
* Everyone must run the same chapter and the same mod version (checked on join).
* Not affiliated with Toby Fox or the DELTARUNE team. The patched game files are generated
  on your machine from your own copy of the game.
