# DELTARUNE Multiplayer — known issues and planned fixes

Sorted by priority. Effort: S = small, M = medium, L = large.
Port forwarding (UDP 26510) stays the way to play online; no relay server.

* F7 / "Stop all music and sounds" (F9 menu): `audio_stop_all()`, for when the music desyncs; rooms start their song again on the next room entry (2026-10-11).

## User test report 6 (Chapter 1 battle loop with Rudinn), 2026-10-14

> I'm in a constant battle loop with Rudinn, the enemy isn't despawning after the battle. And I'd need to actively run away from the enemy which isn't like the gameplay that deltarune normally has.

Cause: every player has their own copy of each overworld enemy, and the game removes the touched one only in the toucher's game. The pulled player's copy (rebuilt fresh by the pull, right where they arrive) chased them after the battle, touched them and pulled everyone into the same battle again. Reproduced in room_field1 (`work/enemy.sh` with `noenemysync`): one Rudinn gave 4 battles bouncing between the two players.

**Fixed.** The touch handler (`obj_chaseenemy` user event 0 in Chapter 1, `obj_overworldenemy_parent` in Chapters 2-5) sends the enemy's object and starting point (message 36); every game removes that enemy now and whenever the room is built again (pull, rebuild), until the player leaves the room for another one (then it comes back, as in the game). Tested: Chapter 1 room_field1 and Chapter 2 cyber maze, one battle, enemy gone in both games.

## User test report 5 (Chapter 1 with 3-4 players), 2026-10-14

> Is there a reason you changed it so characters are reserved? [...] it essentially locks the character chooser if there's 3 players or more. [...] Also the health bar UI is still broken [...] some of the time even when I'm playing as a player not in the battle, it still makes me dodge the attacks for a different player. I managed to softlock the story and save file. After the Lancer battle, progressing to the room with Ralsei's training dummy is impossible due to Susie blocking it [...] Reloading the save doesn't help. I suggest looking out for anything which can cause a softlock like this, and adding a noclip feature.

| # | Problem | Cause | Fix / status |
|---|---|---|---|
| 1 | Character lock blocks the F9 picker with 3+ players. | A UX choice (TODO "same character twice"), not a bug fix: duplicates were already safe (the battle slot goes to the lowest-numbered player with that character). | **Removed.** Picker cycles freely, no auto-switch; the row says "(also P2: you watch battles)". Tested: 4 players all Kris, nobody switched. |
| 2 | HP bar drawn nearly empty while the numbers are right. | Numbers read from network buffers are int32; the game divides HP by max HP and int32 / int32 is an integer division (71 / 90 = 0). Logged: `int32/int32 ratio=0`. | **Fixed.** `mp_num()` turns every received number into a real (`mp_rval`, battle HP/QTE reads). Tested: Chapter 1 battle, bars match the numbers on both screens (screenshot). |
| 3 | Players whose character isn't in the battle still dodge. | A watcher got a normal SOUL (hits did nothing, but it flashed). | **Fixed.** A watcher's SOUL is dimmed and labelled WATCHING, no hit flash/sound, status line "Watching: Ralsei is not in this battle. No need to dodge." Tested with 3 players, party Kris+Susie. |
| 4 | Story softlock after the Lancer battle (Susie blocks the way, survives reloading). | `obj_darkcastle_event` (room_castle_front) runs in each player's game: plot 20/21, Lancer battle (22), Ralsei's story, plot 30. The lagging player's copy wrote plot 21 after 22; the host took it, its room was rebuilt during the story (con 100: the old `con < 90` cut-off missed it), the event deleted itself (it does when plot >= 20) and plot stayed 21. Reproduced with `staleplot:22:21` + `nomono`: plot ends at 21. | **Fixed.** (a) Ordinary updates can't move plot backwards (refused; the higher value is sent back); full snapshots still can. (b) A room is not rebuilt (plot refresh, post-battle rebuild) while a Chapter 1 event's `con` changed in the last 10 s. Same test with the fix: both games end at plot 30, party Kris+Ralsei (as in vanilla). (c) `scr_getchar` never adds a party member twice in multiplayer. |
| 5 | Way out of softlocks. | | **Added** (F9): noclip (F6, own game only), "replay this room's story" (host: room-entry checkpoint of the shared state, room re-entered for everyone), "story progress < N >" (host: set plot, re-enter). README has the recipe for this save (castle front door, 19). |

Tests after these changes: story tool on a stuck save (plot 21, Kris+Susie, real F9 key presses, set 19): the castle scene and Lancer battle replay, Susie not added twice, both games end at plot 30 with Kris+Ralsei; rewind (gold/flag/plot back to room entry on both games); noclip (real F6: through Susie's blocker into room_castle_tutorial; without it stuck at x=408). Regressions: `regress.sh` all 5 chapters identical, `cutscenes.sh` 9/9 pass, Chapter 1 story sweep 75/79 (the same 4 test artifacts as before).

## Open — user test report 4 (Chapter 1 Ralsei cutscene into the Lancer battle: softlock), 2026-10-11

Reported by the user after playing it themselves (two screenshots; the window title is "The Beginning", i.e. Chapter 1, the Lancer-on-a-bike fight in the castle prison hall):

> I softlocked it. I skipped ahead on the ralsei story cutscene on one, then not on the other, then the battle only started for one, then the battle started for the other, the HP desynced, I finished the battle and now one of them is softlocked, pressing F8 shows "Can't go there right now"
>
> And the health bar broke for susie
>
> Plus both players had to dodge despite only one player being involved in the battle

What the screenshots show: (1) the two battle screens at the same moment: top says "ALFIE2 IS CHOOSING FOR KRIS..." with Kris 76/90, Susie 96/110 and the ACT text "Lancer is thinking about chips."; bottom says "YOUR TURN: CHOOSE KRIS'S ACTION!" with Kris **90/90** (HP differs between the players) and Susie's text reading 96/110 while her **HP bar is almost empty** (bar and number disagree). (2) afterwards: one player stands in the empty castle room with only Ralsei on screen, the other sees the same room with nobody visible and, after pressing F8 several times, five lines of "CAN'T GO THERE RIGHT NOW." (the softlocked one).

| # | Issue | Status |
|---|---|---|
| 1 | Skipping the cutscene on one player and not the other: the battle starts for one player first and for the other later. | **Cause found, fixed (not reproduced with the exact Chapter 1 scene).** A battle pull used to wait for the receiver's own cutscene ("never cut short a story cutscene"). If that cutscene then led into the same fight, the receiver started it itself from turn 0 while the other player was further on: two different battles for one encounter. A battle pull no longer waits (`mp_sync_try_pull`): the receiver joins at once and its own cutscene is cut short (`mp_kill_scenes`). Checked with the Chapter 2 Queen scene with one fast and one slow player, in both orders: identical battle logs on both sides. |
| 2 | HP of the same hero differs between the two players during the battle (Kris 76/90 vs 90/90). | Probably the same cause (the second player's own battle starting from its own, full HP). Not verified separately. |
| 3 | Susie's HP bar is drawn nearly empty while her HP reads 96/110. | Open: not reproduced; likely a consequence of two battles being set up for one player (the bar is drawn from the second battle's values). Re-check after a play-through. |
| 4 | Both players had to dodge although only one of them was in the battle. | Probably the same cause: the second player's own battle gave them a SOUL and bullets. Not verified separately. |
| 5 | After the battle one player is softlocked (hidden character, only Ralsei marker on screen, F8 says "Can't go there right now"). | **Fixed in two ways.** (a) After a battle in which my own scene was cut short (`mp_scenes_killed`), the room is rebuilt 2 seconds later at the same spot, the character made visible and interact released (`mp_postbattle_tick`, log "rebuilding the room after a battle that cut my scene short"): a scene cut off in the middle left the character hidden, the party replaced by markers and interact stuck. (b) F8 pressed twice within 5 seconds frees any stuck sync state (`mp_unstick`) and goes to the host; the first press says "press F8 again to force". Tested with the `stuck:<n>` token (faked stuck state): second F8 logs "Released a stuck state." and "Going to Host." |

## Open — user test report 3 (Chapter 2 and Chapter 5 platforming), 2026-10-09

Reported by the user after playing it themselves (with screenshots: a Ralsei "Joining Alfie2 for a cutscene..." room with a pile of cards, a Kris in Hometown with a pile of cars and a "Joining Alfie..." banner, a Chapter 2 battle with garbled text, and a Chapter 2 battle where the party's HP bars look wrong):

> I tried in the aqua platforming room you suggested earlier, the sidescrolling parts are basically nonfunctional, just acts exactly like it does singleplayer. Then I decided to play chapter 2, when a player goes ahead of the other and triggers a cutscene, it can result things to break a lot, this was me grabbing the cards from the other room on one client, then on the other client it looked like this when jumping into the dark world, then the music desynced on both clients (one playing castle town, other playing empty town), and lancer was there on one while he wasn't on another. Other than that things were still fine. Also had the same thing when jumping into the library dark world. Then the cutscene introducing Queen broke everything, when i went ahead and left the other client behind, it seemed fine at first, until the battle started, and started playing the cutscene on the other client, even though it already played, while in battle. I saw the dialog appear over the battle and now it started another battle within the battle, leaving the game softlocked. I haven't managed to outright crash the game, but I managed to softlock it, which I feel like is an improvement. Also the health bars are seem broken.

| # | Issue | Status / cause |
|---|---|---|
| 1 | Chapter 5 platforming sections (e.g. `room_dw_garden_aquaplatforming`): players don't see each other, it behaves exactly like single-player. | **Mostly done.** The platformer is the game's own engine (`obj_plat_player`, always Kris's platformer sprites). New `gml/ch5/scr_mp_plat`: your platformer figure is sent (draw position, sprite, frame, direction; state bit 32) and the other players are shown as ghosts in the same room, hidden unless both are in a platforming section. Joiners only change room. Test bots now jump (`wander`), and `mpcheck.py` knows the platformer (looser ghost tolerance: jumps are fast). All 7 platforming rooms pass. **Not done:** each player is still drawn as Kris there (the platformer has no per-character figure), the figures' hits/enemies/pickups are not shared (everyone plays their own copy), and a real human has not tried it. |
| 2 | Chapter 2: a player runs ahead and triggers a cutscene (grabbing the cards, jumping into the dark world / library dark world): the other player sees a broken screen (piles of cars/cards), the music differs (castle town vs empty town) and Lancer is present for one only. | **Fixed (user's exact steps: exit the Dark World on one client, collect the things at the school, go back in; the castle town is built from them).** Three causes: (1) *music*: rooms only start a song when none plays; everyone now announces their song (type 34) and moved players follow it (earlier fix). (2) *Large sprites / piles*: the Light/Dark World state (`global.darkzone`) was never carried: a player in the Dark World pulled into a Light World room kept Dark World followers and sprites (drawn big) and the room's actors copied them. It is now sent with pulls (state from before the cutscene), cutscene ends, joins and the new "go to" action (state bit 64 in position messages, protocol v3); a change re-enters the room so followers/sprites are built for the right world. New `mpcheck.py` check "world" (same room = same world). (3) *Lancer / castle town not matching*: room objects are built from the story progress when the room is entered; when another player moves the story on while you stand in a room, yours was out of date. After the changes settle (90 frames, free roam only) the room is now entered again at the same spot (`mp_room_refresh_tick`, log `room refresh`), also at the end of a cutscene in the same room. Checked with `lightworld` / `setplot:` test tokens and the castle town scenario (`work/cut_town`). |
| 3 | Chapter 2, Queen introduction: one player left the other behind; when the battle started, the other client played the cutscene again over the battle, then started a second battle inside the battle: softlock. | **Fixed.** Reproduced with `tools/cutscenes.sh ch2_queen` (host walks into the scene while the client is in another room). The pulled client arrived at the battle's room and the room's own scene (`obj_ch2_scene9`, triggered by the player's x) started there as well; its dialogue drew over the battle and it started encounter 53 again. This is not specific to Queen: any story cutscene that leads into a battle (the user's point) can do it. So the fix is generic: `mp_kill_scenes()` removes, when joining a battle and every frame until the battle exists, every object that holds a cutscene master (`cutscene_master` variable: that is how every Chapter 2-5 cutscene object works, whatever it is called), the masters themselves, and objects named `obj_*scene*` / `obj_*event*` (Chapter 1 has no cutscene master: its story controllers are `obj_*event` objects). Verified in Chapters 2-5 with a made-up cutscene object (`fakescene` test token, started while being pulled into a battle): the new check fails without the fix (`nokill` token) and passes with it. Chapter 1 is covered by name only (not verified with a test). New check "scene": fails if a cutscene runs in a game that was pulled into a battle (`SCENE-IN-BATTLE` in the log). With the fix both players finish the fight, the story moves on (plot 51) for both, nobody is stuck. (`weak` test token: enemies have 1 HP so a battle ends quickly.) |
| 4 | Chapter 2 battle: party HP bars look broken, battle text garbled/overlapping. | **Fixed (same cause as 3).** With the scene removed the bars and text are normal; with the fix disabled (`nokill` token) the scene's dialogue is drawn over the battle. |

## Sweep status after the report-3 fixes, 2026-10-10 (`work/sweep/ch3_s1`, `ch4_s2`, `ch5_s1`)

Chapter 5 passes (only the credits-room crash, the game's own). Chapters 3-4 still list:
* The game's own crashes (see below), plus **new, unexplained**: Chapter 4 `room_lw_church_main` plot 289 (`obj_ch4_DCB03` Step, "Variable obj_ch4_DCB03.su... not set", 2 players, interact 1). Not looked at yet.
* "nobody moved" in `alphysclass` and Light World rooms (Noelle's house, church, torhouse): probably the bots cannot walk there (test setup), not confirmed.
* Ghost mismatches around doors at the top of a town room: `room_library` plot 3/12 (Ch 3 and 4), `room_diner` 45/49/50, `room_town_church` 100, `room_town_noellehouse` 89, `room_board_dungeon_3` 179. The host stands at y of about -7 (past the top edge, on a door) and the other client sees a stale position (820,180) or no ghost for 2-4 s. Could be a real stale-ghost bug when a player is moved by the mod to a door trigger; not investigated.
* `tools/mpcheck.py` ghost check now ignores samples with a text box open (a game-driven text box flickers `interact` to 0 for 2 frames and the mod hides ghosts during dialogue; this was `room_town_school` 300) and moments within 3 s of the other player changing room.

## Chapter 1 music, fixed 2026-10-11

There was no music sync in Chapter 1: the mod identifies the playing song by the `songname` that Chapter 2+'s `snd_init` records on its `obj_astream`, and Chapter 1's `snd_init` does not, so every song read as "none" and nobody followed anybody. A Chapter 1 hook now sets `songname`. Checked with the new `song:<file>` test token (host plays `field_of_hopes.ogg`, a joining client logs `music follows player 0: field_of_hopes.ogg`). The sweeps could not show this before because the title screen's drone song is still "playing" in test warps. Known small difference: a following player plays the song at full volume (Chapter 1 rooms start some songs at 0.7).

## Chapter 1 two-player crashes, fixed 2026-10-11

`room_castle_town` 30, `room_field_boxpuzzle` 49 and `room_forest_chase2` 150 crashed with two players but not solo (vanilla or mod). Causes, all in the mod: (1) the mod's warp keeps `interact` at 3 for a few frames, so `obj_mainchara` never set `runmove` (it only does so while interact is 0) and Chapter 1's Ralsei run event crashed reading it: `runmove` now gets a default at room start. (2) Chapter 1 has no cutscene master, so the mod did not see its `obj_*event` cutscenes as running and a pull restarted the room in the middle of one (box puzzle): such events (`con` between 1 and 89, interact not 0) now count as a running cutscene and the pull waits. (3) HP is shared: another player's hit could leave a hero at 0 HP here without the game's Game Over having run; the next overworld hit then looked for another hero whose instance does not exist (`charinstance` has one entry in the chase). `scr_damage` outside battles now runs the Game Over when a party hero is at 0 HP (`mp_overworld_all_down`). The crash log line now also shows party, HP and `charcantarget`. Full Chapter 1 sweep: 75 of 79 pass; the rest are test artifacts (bed rooms, prison cell, class scene party).

## Vanilla check and feature tests, 2026-10-11

* **Vanilla comparison** (`tools/buildv.sh` builds `buildv/`: only the test harness, none of the multiplayer gameplay hooks; `SWEEP_BUILD=buildv tools/sweep.py <ch> --solo ...`). These crash on vanilla too, so they are the game's own: Ch3 `snow_zone_battle` 290, enc 141; Ch4 `church_claw` 150/169/170, `churchb_library_alternate` 236/238, enc 93/174/179/180; Ch5 credits rooms (`castle_rooms_susie`, `ralsei_castle_front`) 390, `room_gameover` 279, `room_krisroom` 4, `room_town_school` 100, enc 777. Not reproduced on vanilla: Ch1 `castle_town` 30, `field_boxpuzzle` 49, `forest_chase2` 150 (they crashed in two-player runs, not solo: **still to look at**, could be the mod); Ch4 `lw_noellehouse_dess` 66 (was the test starting the Light World room in the Dark World state, gone with `lightworld`); Ch5 enc 235 (debug enemy `obj_enemy_example`, only crashes with two players: it sets `myattackpriority` only in the "enemytalk" phase, which the two-player battle flow can skip; not reachable in the story).
* **New features, tested for real:** Game Over then Continue (two players, `nododge`): both reach Game Over, the client then logs "Going to Host."; downed SOUL dimmed with a DOWN label (screenshot); barrier names on clients (a third player frozen with SIGSTOP: both others show "WAITING FOR P3..."); F8 with a real key press (xdotool) goes to the host; chapter resume (host and client, via the ini): the Chapter 2 client connected to the Chapter 2 host with no flags; duplicate character resolved (client asked for Kris, became Susie); `gotohost` token.

## Sweep result after the playability batch, 2026-10-11 (`work/sweep/ch*_f`, flow.py, regress.sh)

All five chapters swept again with the new build. Everything passes except: the game's own crashes (Ch1 `room_castle_town` 30 / `room_field_boxpuzzle` 49 / `room_forest_chase2` 150, Ch3 `snow_zone_battle`, Ch4 `church_claw` and `churchb_library_alternate`, Ch5 credits rooms, `room_gameover`, `room_krisroom` 4, `room_town_school` 100; the Ch5 ones were confirmed solo), and test artifacts: `room_krisroom` (both players start in bed, bots cannot move), `room_dw_rhythm` 132, Ch1 `room_alphysclass` 1 (the class scene sets its own party, the test's differs). Flaky ones (`town_shelter` 349, `bellhall_bookroom` 242, `town_mid` 94) pass alone. Real key-press flow (file select, new game, F9, three players, Chapter 4) passes; battle sync (`regress.sh`, 2 and 3 players) passes.

## Done — playability batch, 2026-10-11

* F8 / "Go to <player>" (F9 menu) takes you to the host (host: first other player), with a fade; fixes anyone stuck in a puzzle or a room that is out of step. Warps in general fade in now.
* (Removed 2026-10-14, see report 5) Two players couldn't play the same character.
* After Game Over + Continue, clients are taken to the host once they have reloaded.
* The turn barrier names who it is waiting for on every client (host sends type 35).
* Downed players' SOUL is dimmed and labelled DOWN.
* Chapter change: the session is remembered in `multiplayer.ini` (`[resume]`); the next chapter's start within 15 minutes hosts / joins again by itself (join retries for a few minutes). "Stop hosting" / "Leave" forgets it.
* ACTs: the RNG is re-seeded at the start of each hero's action (all players), not only at phase starts.
* Test tooling: `lightworld`, `setplot:<n>`, `gotohost:<n>` tokens; sweeps start Light World rooms in the Light World; `mpcheck.py` ignores text-box flicker, doorways outside the room, door-crossing delays and freshly built rooms in the ghost check.
* Crash `obj_ch4_DCB03` (Chapter 4 Light World church) was the same world-state bug and is gone.

Not done (decided): gold as deltas (battle rewards are applied by every player locally, so adding deltas would double them; two players buying at the same instant can still overwrite each other), "skip their text" at the barrier (the barrier is what keeps the battles identical), saving for the host, host migration (clients don't know each other's addresses: needs a handover message and a forwarded port on the new host).

## Done — user test report (Chapter 4), 2026-10-08

Reported by the user after playing it themselves:

> I just tested it out myself, it's very buggy, i think more dynamic testing should be done, i started it on chapter 4, and when i got out the cutscene, i saw an NPC kris following me, despite it being kris and susie, and i had one of the clients set to susie, yet it's still controlling kris, then on the synced cutscene thing, none of it actually played. You should ensure your dynamic testing covers all this, ensure that all players are the characters they chose, and they can move independently, and there's no desync.

| Issue | Cause found | Fix |
|---|---|---|
| A client set to Susie still walked as Kris (Chapter 4). | Chapter 4 draws Kris with its own `draw_sprite_ext(..., x + tower_shake_xoffset, ...)` instead of `draw_self()`, so the sprite-swap hook never ran. That also meant your position was never sent as "visible", so nobody saw you and nothing got hidden. | Chapter 4 hook for that call (`mp_draw_mainchara(xoff)`). Swaps now also stay on while talking to people, reading signs, going through doors and during anything that only happens in your own game. Before, you briefly turned back into Kris then. |
| An NPC Kris followed the player. | The follower standing in for your own character is drawn as Kris. It was only hidden while the Kris player was visible in the same room (and with the bug above, never). | A party member any connected player plays is never drawn as an NPC follower, wherever that player is. |
| The shared cutscene didn't play. | Several separate problems: (1) the leader's first story-flag/plot changes were broadcast before the pull arrived, so the cutscene no longer triggered for the others; (2) a player still in their own cutscene dropped the pull; (3) a leader who walked from one cutscene straight into the next never sent a pull for the second; (4) cutscenes that start on entering a room didn't re-trigger for someone already in that room; (5) the pull set `plot` (possibly already advanced). | Shared-state changes are held while a possible cutscene is being classified. The pull carries the plot from before the cutscene and whether it started on room entry (re-enter the room, or `room_restart`). Pulls received during your own cutscene wait until it ends if the other cutscene is still going. Pulls from earlier in the story than you are are ignored. A leader starting another cutscene pulls again. A door handing straight over to a cutscene is detected. A cutscene that changes room early still pulls. |
| (found while testing) Spectators could get stuck, and "you can't go that way" messages pulled everyone. | Any unprompted text box counted as a cutscene. A tiny event repeated by the leader kept spectators frozen. | Pull only if a new cutscene controller appears or the plot changes within 20 frames, or if it lasts more than 4 s. Spectators are released after the leader has been walking around for 3 s. Spectators now see the leader's dialogue text. |
| (found while testing) A battle's "!" intro was taken for a cutscene, and its pull overwrote the pending battle pull. A Game Over then warped the spectator into `room_gameover` (crash). | `interact` rises before the battle objects exist. | Touching an enemy (`obj_testoverworldenemy`) is never a cutscene. A pending battle pull wins over a cutscene pull. Nobody is ever moved into Game Over or menu rooms. |
| (found while testing) Battle menu desync: one player's game ignored a press that the others' replay accepted, so the game deadlocked at the turn barrier. | The battle menu ignores presses for a few frames after the previous one. The replay can only be later, so an ignored "too early" press could be accepted remotely. | The menu owner's presses are kept at least 5 frames apart (an early press is held back, not dropped). |
| (found while testing) Battle party mismatch (Chapter 5): a pulled player fought with a different party. | Each game used its own `global.char`. | The battle pull carries the starting player's party. |
| (found while testing) Special walking sprites (`spr_kris_walk_left_church`, `spr_kris_walkd_hold`, ...) showed Kris for other characters. | The direction wasn't recognised from those names. | Direction detection understands `_walk_left`, `_walkd`, etc. for every character. |

## Testing — what now exists

* `tools/flow.py`: real game flow. N instances, real key presses (xdotool) through the file
  select, new game (name entry) or loading a save, and the F9 menu (pick a character, host,
  join), either at the file select or after starting. The bot (`mash`, `wander`) then plays.
* `tools/mpcheck.py`: checks every player's twice-a-second self-check lines (`-mptest check`).
  Each player is drawn as the character they chose in free roam. No party member played by
  someone is drawn as a follower. Every other player in the room is shown where they really
  are. The shared state hash (plot, gold, party, flags, items, HP) matches. Nobody is left
  frozen/waiting, and nobody crashed or froze. Players moved independently.
* `tools/cutscenes.sh`: scripted real story cutscenes in Chapters 2–5 (on entering a room,
  and by walking into a trigger) with the other players in a different room; checks they are
  pulled in and the cutscene plays in their game.
* `tools/regress.sh`: battle sync in every chapter (unchanged).
* Log lines are wall-clock timestamped (`run_game.sh`) so players' views can be compared.

* `tools/sweepgen.py` + `tools/sweep.py`: about 560 story scenarios (every room with story
  objects at the story points they check) and every battle encounter in Chapters 1-5, with a
  host and a joining client (`--clients 2` for three players, `--solo` to find the game's own
  crashes). All pass except the game's own crashes (listed under the crash reports).
* `tools/aiplay.py` + `tools/llm.py`: AI-driven playthrough. Each player is a vision model
  agent (model and provider from the opencode config; default `commandcode-goat`
  `deepseek/deepseek-v4.1-flash`) that looks at its screen and presses real keys; the result
  is checked by `mpcheck.py`. Includes a notes logbook, stuck/room hints and random
  unsticking. A first Chapter 4 run (new game, 2 players, 45 min) reached the church with no
  crashes or desync, but progress is slow (about 7-25 s per decision). `work/aiall.sh` plays
  every chapter in turn (not started yet). Long runs use API quota: ask before running.

* `tools/cutscenes.sh` custom scenarios (`ch2_queen`, `ch2_library`, ...) use the test tokens
  `away:<room>:<n>[:<x>:<y>]` (walk through to another room n frames after the party setup, like a player
  running ahead or being somewhere else) and `weak` (1-HP enemies). `mpcheck.py` also checks
  that players in the same room hear the same song ("music") and that no cutscene runs in a pulled battle ("scene").

Still not covered automatically: Chapter 1 new game (the vessel creation; Chapter 1 is
tested by loading a save), joining mid-cutscene, cutscenes started with Z (user report 3),
platforming sections (only "stand in the room" is tested), real play-through of whole chapters.

## Other things worth checking (my own list)

- Changing character mid-session through F9 (picking it before joining, at the file select or
  in game, is now covered by `tools/flow.py`).
- Joining while the host is in a cutscene or battle. (Joining from the file select is covered.)
- Rooms where the game hides or repositions followers. (Light World followers in Chapter 4 are covered.)
- Chapter 5 `_weird_mode` draws Kris with `draw_sprite` (not hooked: shows Kris in that mode).
- Light World Ralsei/Noelle have no Light World walk sprites; they fall back to Dark World ones.
- More `interact` cases in later chapters (save points, shops, the C menu are Z-triggered and
  local; unprompted text boxes now only pull after 4 s).

## Done — user crash reports and the Chapter 3 board, 2026-10-08

| Issue | Cause | Fix |
|---|---|---|
| Crash: `obj_mainchara` Create, "Unable to find any instance for object obj_markerC" (Chapter 1). | The mod moves players between rooms with `interact = 3` (like a door) but kept the last door's entrance number, so the game looked for that door's entry marker in a room that doesn't have it. | `mp_warp` clears `global.entrance`; the mod places the player itself. |
| Crash: `obj_ch3_gameshow` Step, "Unable to find any instance for object index 0" (Chapter 3 board). | A player who only watched a cutscene was moved to where it ended (the board) before receiving the story changes from it (Susie/Ralsei joining the party), so their followers didn't exist. | The leader sends all its story changes before "cutscene ended"; spectators apply them before being moved. |
| Chapter 3 board game didn't work in multiplayer. | The board is drawn at a fixed place while the board scrolls underneath (the `BOARD_Tiles` layer moves); the mod only knew about walking characters, and treated the couch party as walking characters. | Board mode (`gml/ch3/scr_mp_board`): everyone plays their own copy of the board, like walking around. Your piece (Kris's) is drawn as your character, pieces other players play are hidden and shown as their name-tagged ghost when on the same board screen (positions sent relative to the whole board). The couch shows the real party. Board events never pull anyone; real battles still do. Joining someone on the board only changes room. |
| Crashes were hard to report. | | Unhandled errors are written to `multiplayer_crash.txt` (next to the saves, with chapter, room, plot, sync state and stack) and the log (`[MPCRASH]`, which the tests check). |
| (sweep) Crash: `obj_floorshadow` Draw, "non-existing sprite" (Chapter 4 ripple puzzle). | A pulled player was put on the cutscene's trigger spot right at Room Start; the cutscene began on frame one, before the new party followers had sprites, and copied empty sprites into its actors. | After moving to another room the mod waits 4 frames (like a door arrival) before stepping onto the spot; Chapter 4 shadows also skip a missing sprite. |
| (sweep) Crash: `obj_ch5_DW10` (Ralsei missing), Chapter 5. | A player busy in their own cutscene joined the other's afterwards without first applying the shared state that arrived meanwhile (party members). | Pulls apply queued shared state first, and carry the leader's party from just before the cutscene; a changed party re-enters the room so followers exist. |
| (sweep) Crash: end credits rooms (Chapter 5). | Each credits room counted as a new cutscene; others were pulled into credits rooms that need the credits' own objects. | No pulls or cutscene-end moves while the credits play. |
| (sweep) Story state could end up swapped between two players (plot, party). | Two players finishing cutscenes at the same time each applied the other's in-flight change. | The host's copy is the shared one: it echoes every change it applies from a client (including ones it queued while busy) to everyone. |
| (sweep) Text boxes that pop up by themselves ("you can't go that way") pulled everyone and could keep them frozen. | Any unprompted `interact` lasting 4 s counted as a cutscene. | A cutscene must do something cutscene-like (new cutscene controller, story progress, new actors, player hidden or moved by the game, party stops following). Spectators are released when the leader is walking around again. |
| (sweep) A pulled player sometimes re-watched a cutscene they had just played, or was put off-screen. | Arrived while the other's copy was still running / position taken on the frame the cutscene moved the player away. | Pulls for a room+story point you just played are ignored; the start position is taken from two frames earlier. |

| (sweep) 3rd player joining during a battle got no turns. | Only the first two players got the battle pull. | The host sends a battle pull to anyone joining while a battle runs. |
| (sweep) Joiner stood outside the doorway; no battle started. | Warp used the draw position +4. | Players send their real position; joiners are warped there. |
| (sweep) Battle menu deadlock / HP desync (Ch 4 enc 151, Ch 5 enc 222). | Presses too close together, input at the turn barrier, stray enemy-owned hits. | 5-frame press spacing, input blocked at the barrier, HP reports tracked (`mp_rhp_known`). |
| Game's own battle crashes (also solo): Ch 3 enc 141, Ch 4 enc 93/174/179/180, Ch 5 enc 235/777. | Missing enemy variables / debug encounters. | None needed. |

### Automated story sweep (tools/sweepgen.py, tools/sweep.py)

Every room with story objects is visited at each story point (`plot`) those objects check:
the host starts there, a client joins from elsewhere and is moved in by the mod, bots play,
`mpcheck.py` checks everything (crashes, characters, followers, ghosts, shared state, sync).
`--battles` does the same for every encounter (3+ turns, battle state compared per turn).
Crashes that also happen single-player (`--solo`) are the game's own / from teleporting
into unreachable rooms, not multiplayer:

* Chapter 3 `room_dw_snow_zone_battle` (plot 290), Chapter 4 `room_dw_church_claw` (its door
  leads to a room that doesn't exist), `room_dw_churchb_library_alternate`, Noelle's house
  "home alone" sequence entered mid-way, Chapter 5 credits rooms entered directly, and the
  Chapter 5 opening in Kris's room with a 3-person test party.

Known, harmless: per-player statistics stored as story flags (Chapter 5 "slashes" count)
keep the last writer's value instead of adding up.

## Priority 1 — quick wins that make things feel right

| Issue | Fix | Effort |
|---|---|---|
| Waiting on slow readers: a player can sit at the turn barrier for a while, and only the host can see who they're waiting on. | Show exactly who everyone is waiting on, for clients too. After ~20 s, offer "Skip their text" to the waiting player. | S |
| Downed players' SOUL still appears and dodges, but nothing happens when hit — feels broken. | Draw it greyed out with a "DOWN" label, or make it a ghost SOUL that can still graze for TP. | S |
| Teleport after watching a cutscene: players who only watched get dropped at the leader's final position abruptly. | Fade out/in around the warp, like a door transition. | S |
| Moving to the next chapter disconnects everyone; the session has to be re-hosted. | Save session details (host address, character) when a chapter ends; the next chapter auto-reconnects on start. | S |
| Game Over: after Continue, each player reloads their own save and can end up in different rooms. | After Continue, pull everyone to the host's position once the host has reloaded. | S |
| Same character twice: the second player silently becomes a battle spectator. | Block picking a character someone else already has in the F9 menu (sharing by alternating turns could come later, M). | S |
| Puzzles and set pieces (Queen's mansion acid, chase sequences, timed puzzles) run separately per player; one player solving it can change the room under another and leave them stuck. | "Teleport to host" hotkey: warps you to the host's room and position (with a fade). Fixes stuck players anywhere, not just in puzzles. | S |
| Random ACT outcomes can briefly differ (some ACTs use randomness after locally-timed text). | Re-seed the RNG right before each ACT resolves, not just at phase starts. | S |

## Priority 2 — protect progress

| Issue | Fix | Effort |
|---|---|---|
| Shop money: gold syncs as "last total wins", so simultaneous purchases can overwrite each other. | Sync gold as changes ("−50") instead of totals; have the host assign item slots so two players can't fill the same one. | M |
| Save points: each player saves their own file, so a client's save goes stale. | Make the host's save the shared one: when a client saves, the host saves too. Joining clients already take the host's state. | S |
| Host leaving ends the session (no relay server, by choice). | Offer the next player "Become host?". If they accept, they start hosting and everyone reconnects to them automatically. If their port isn't forwarded, show a clear message ("P2 can't be reached — they need to forward UDP 26510"). | M |

## Priority 3 — special content

| Issue | Fix | Effort |
|---|---|---|
| Special battle styles (Spamton NEO, Berdly/Queen, Chapter 4/5 gimmick fights) likely only partly sync. | Detect special battles and fall back to "one player drives the battle, everyone else spectates and dodges". Later, hand-sync individual fights people care about. | S–M (fallback); L per fight |

## Priority 4 — cosmetic

| Issue | Fix | Effort |
|---|---|---|
| Party menu (C) always shows the real party (Kris first), not your chosen character. | Keep the menu accurate; add a small "You: Susie" label so it doesn't look wrong. | S |
| Light World: characters without Light World walk sprites (e.g. Ralsei) fall back to showing as Kris. | Better fallback, e.g. a Light World variant if one exists, otherwise the Dark World sprite. | S |

## Untested / low priority

| Issue | Notes |
|---|---|
| Snowgrave route (Chapter 2) | Untested. Branching routes are low priority. Relies on Noelle-specific battle flow and flags, so expect oddities if players disagree. Possible later fix: route choices follow whoever plays Noelle (or the host). |

## Out of scope for now

- Relay server (would remove the need for port forwarding, but needs something hosted 24/7).
