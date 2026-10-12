// DELTARUNE Multiplayer - shared events: cutscenes and battles pull every player together.
//
// sstate: 0 free roam
//         1 leading   - a cutscene started in my game; others were pulled to me
//         2 following - pulled, and the same cutscene started in my game
//         3 waiting   - pulled, arrived, waiting for the cutscene to trigger here
//         4 watching  - pulled, but the cutscene did not trigger here; frozen until it ends

function mp_sync_init()
{
    global.mp_sstate = 0;
    global.mp_slead = -1;
    global.mp_sseq = 0;
    global.mp_prev_interact = 0;
    global.mp_local_dlg = 0;
    global.mp_lastz = -100;
    global.mp_classify = 0;
    global.mp_idle = 0;
    global.mp_wait = 0;
    global.mp_lead_done = 0;
    global.mp_pull = -1;          // deferred pull: [kind, from, room, x, y, enc, plot, age]
    global.mp_battle_seen = 0;
    global.mp_battle_pulled = 0;
    global.mp_warp_mus = -1;
    global.mp_mus_pending = -1;
    global.mp_mus_until = 0;
    global.mp_mus_sent = "";
    global.mp_pmus = array_create(8, "");
    global.mp_hist_x = array_create(16, 0);
    global.mp_hist_y = array_create(16, 0);
    global.mp_hist_i = 0;
    global.mp_pre_room = -1;
    global.mp_pre_x = 0;
    global.mp_pre_y = 0;
    global.mp_pre_plot = 0;
    global.mp_pre_party = [1, 0, 0];
    global.mp_calm_party = [1, 0, 0];
    global.mp_calm_dz = 0;
    global.mp_room_plot = 0;
    global.mp_gameover = 0;
    global.mp_scenes_killed = 0;
    global.mp_postbattle = 0;
    global.mp_goto_blocked = -99999;
    global.mp_goto_timer = 0;
    global.mp_ch1ev_frame = -99;
    global.mp_ch1ev_value = false;
    global.mp_plot_remote = -1;
    global.mp_pre_master = -1;
    global.mp_pre_actors = 0;
    global.mp_last_cs_room = -1;  // the last cutscene that played in my game: room,
    global.mp_last_cs_plot = -1;  // story progress when it started,
    global.mp_last_cs_end = -100000;  // and when it was last running
    global.mp_pre_vis = 1;
    global.mp_pre_mx = 0;
    global.mp_pre_my = 0;
    global.mp_pre_entry = 0;
    global.mp_pre_dz = 0;
    global.mp_calm_plot = 0;
    global.mp_room_frames = 0;
    global.mp_room_calm = 0;
    global.mp_warp_reenter = 0;
    global.mp_warp_pending = 0;
    global.mp_warp_room = -1;
    global.mp_warp_x = 0;
    global.mp_warp_y = 0;
    global.mp_warp_action = 0;
    global.mp_choice_seq = 0;
    global.mp_choices = ds_map_create();
    global.mp_lead_text = "";     // dialogue the leader last sent
    global.mp_lead_free = 0;      // frames the leader has been out of any cutscene
    global.mp_watch_text = "";    // dialogue shown to frozen spectators
}

function mp_sync_reset()
{
    global.mp_sstate = 0;
    global.mp_slead = -1;
    global.mp_pull = -1;
    global.mp_classify = 0;
    global.mp_battle_pulled = 0;
    ds_map_clear(global.mp_choices);
    if (variable_global_exists("plot"))
        global.mp_calm_plot = global.plot;
}

function mp_sync_release_all()
{
    if (global.mp_sstate == 4 || global.mp_sstate == 3)
        global.interact = 0;
    global.mp_sstate = 0;
}

function mp_in_battle_scene()
{
    return instance_exists(obj_battlecontroller) || instance_exists(obj_encounterbasic);
}

// Called from mp_after_input: spectators must not move.
function mp_sync_input()
{
    if (global.mp_sstate == 4 || global.mp_sstate == 3 || (global.mp_sstate == 2 && instance_exists(obj_choicer_neo)))
    {
        for (var i = 0; i < 10; i++)
        {
            global.input_pressed[i] = 0;
            global.input_held[i] = 0;
        }
    }
}

function mp_send_pull(kind)
{
    mp_send_pull_to(kind, -1);
}

// Sends a pull to one peer (a struct), or to everyone.
function mp_send_pull_to(kind, sock)
{
    var px = 0;
    var py = 0;
    if (instance_exists(obj_mainchara))
    {
        px = obj_mainchara.x;
        py = obj_mainchara.y;
    }
    var rm = room;
    var plot = global.plot;
    var entry = 0;
    var dz = mp_dz();
    if (kind == 2)
    {
        rm = global.mp_pre_room;
        px = global.mp_pre_x;
        py = global.mp_pre_y;
        plot = global.mp_pre_plot;
        entry = global.mp_pre_entry;
        dz = global.mp_pre_dz;
    }
    global.mp_sseq += 1;
    mp_log("send pull kind=" + string(kind) + " room=" + room_get_name(rm) + " " + string(px) + "," + string(py) + " plot=" + string(plot) + " entry=" + string(entry));
    mp_begin(30);
    mp_wu8(kind);
    mp_wu16(rm);
    mp_ws16(px);
    mp_ws16(py);
    mp_ws16(global.encounterno);
    mp_wval(plot);
    mp_wu8(entry);
    var party = [global.char[0], global.char[1], global.char[2]];
    if (kind == 2)
        party = global.mp_pre_party;
    for (var i = 0; i < 3; i++)
        mp_wu8(party[i]);
    mp_wu8(dz);
    if (is_struct(sock))
        mp_send_to(sock);
    else
        mp_send();
}

function mp_send_cend()
{
    var px = 0;
    var py = 0;
    if (instance_exists(obj_mainchara))
    {
        px = obj_mainchara.x;
        py = obj_mainchara.y;
    }
    mp_begin(31);
    mp_wu16(room);
    mp_ws16(px);
    mp_ws16(py);
    mp_wu8(mp_dz());
    mp_send();
}

function mp_sync_recv(type, from, b)
{
    if (type == 35) // who the host's turn barrier waits for
    {
        var nn = buffer_read(b, buffer_string);
        if (nn != global.mp_bwait_names)
            mp_log("barrier waits for: " + nn);
        global.mp_bwait_names = nn;
        global.mp_bwait_names_time = current_time;
        return;
    }
    if (type == 34) // the song the sender is playing
    {
        global.mp_pmus[from] = buffer_read(b, buffer_string);
        return;
    }
    if (type == 30) // PULL
    {
        var kind = buffer_read(b, buffer_u8);
        var rm = buffer_read(b, buffer_u16);
        var px = buffer_read(b, buffer_s16);
        var py = buffer_read(b, buffer_s16);
        var enc = buffer_read(b, buffer_s16);
        var plot = mp_rval(b);
        var entry = buffer_read(b, buffer_u8);
        var party = array_create(3, 0);
        for (var i = 0; i < 3; i++)
            party[i] = buffer_read(b, buffer_u8);
        var pdz = buffer_read(b, buffer_u8);
        if (is_array(global.mp_pull) && global.mp_pull[0] == 1 && kind != 1)
            return; // a pending battle pull wins
        if (!mp_room_ok(rm))
            return;
        global.mp_pull = [kind, from, rm, px, py, enc, plot, 0, entry, party, pdz];
        mp_log("got pull kind=" + string(kind) + " from=" + string(from) + " sst=" + string(global.mp_sstate) + " ia=" + string(global.interact));
        mp_sync_try_pull();
        return;
    }
    if (type == 31) // CUTSCENE END
    {
        var rm2 = buffer_read(b, buffer_u16);
        var ex = buffer_read(b, buffer_s16);
        var ey = buffer_read(b, buffer_s16);
        var edz = buffer_read(b, buffer_u8);
        if (from != global.mp_slead)
            return;
        global.mp_watch_text = "";
        if (global.mp_sstate == 3 || global.mp_sstate == 4)
        {
            global.interact = 0;
            global.mp_sstate = 0;
            global.mp_slead = -1;
            mp_vars_apply_queue();
            with (obj_mainchara)
                visible = 1;
            if (mp_room_ok(rm2) && !mp_credits_running())
            {
                global.mp_warp_mus = from;
                global.mp_warp_reenter = mp_dz_take(edz) || (rm2 == room && global.plot > global.mp_room_plot);
                mp_warp(rm2, ex, ey, 0);
            }
        }
        else if (global.mp_sstate == 2)
        {
            global.mp_lead_done = 1;
        }
        return;
    }
    if (type == 33) // leader's current dialogue, for spectators
    {
        var txt = buffer_read(b, buffer_string);
        if (from == global.mp_slead)
            global.mp_watch_text = txt;
        return;
    }
    if (type == 32) // CHOICE
    {
        var seq = buffer_read(b, buffer_u16);
        var val = buffer_read(b, buffer_s8);
        if (from == global.mp_slead)
            ds_map_set(global.mp_choices, seq, val);
        return;
    }
}

// ---------------------------------------------------------------- music
// Rooms only start their own song when nothing is playing, so a player moved by the mod (join,
// pull, end of a cutscene) would keep the previous room's song. Everyone announces what they
// play; whoever is moved to someone plays the same song.

function mp_cutscene_master_exists()
{
    var o = asset_get_index("obj_cutscene_master");
    return o >= 0 && instance_exists(o);
}

function mp_music_name()
{
    var nm = "";
    if (variable_global_exists("currentsong") && is_array(global.currentsong) && snd_is_playing(global.currentsong[1]))
    {
        global.mp_tmp_mus = "";
        with (obj_astream)
        {
            if (variable_instance_exists(id, "songname") && variable_instance_exists(id, "mystream") && mystream == global.currentsong[0])
                global.mp_tmp_mus = songname;
        }
        nm = global.mp_tmp_mus;
    }
    return nm;
}

function mp_music_tick()
{
    if (global.mp_mus_pending >= 0 && (global.mp_frame mod 5) == 0)
    {
        if (global.mp_frame > global.mp_mus_until)
            global.mp_mus_pending = -1;
        else if (global.mp_pmus[global.mp_mus_pending] != "")
            mp_music_follow(global.mp_mus_pending);
    }
    if ((global.mp_frame mod 15) != 0 || !mp_on())
        return;
    var nm = mp_music_name();
    if (nm != global.mp_mus_sent || (global.mp_frame mod 300) == 0)
    {
        global.mp_mus_sent = nm;
        mp_begin(34);
        mp_wstr(nm);
        mp_send();
    }
}

// Play the same song as player pid (after being moved to them).
function mp_music_follow(pid)
{
    if (pid < 0 || pid >= 8)
        return;
    var want = global.mp_pmus[pid];
    if (want == "")
    {
        // Their announcement hasn't arrived yet (just joined): do it as soon as it does.
        global.mp_mus_pending = pid;
        global.mp_mus_until = global.mp_frame + 900;
        return;
    }
    global.mp_mus_pending = -1;
    if (want == "menu.ogg" || want == mp_music_name())
        return;
    if (!variable_global_exists("currentsong") || !is_array(global.currentsong))
        return;
    if (snd_is_playing(global.currentsong[1]))
        snd_stop(global.currentsong[1]);
    global.currentsong[0] = snd_init(want);
    global.currentsong[1] = mus_loop(global.currentsong[0]);
    mp_log("music follows player " + string(pid) + ": " + want);
}

// Tries to act on a received pull; may be deferred while a local dialogue finishes.
function mp_sync_try_pull()
{
    var p = global.mp_pull;
    if (!is_array(p))
        return;
    var kind = p[0];
    var from = p[1];
    if (mp_in_battle_scene() || global.mp_battle_pulled)
    {
        global.mp_pull = -1;
        return;
    }
    if (kind == 2 && mp_credits_running())
    {
        global.mp_pull = -1;
        return;
    }
    if (kind == 2 && variable_global_exists("plot") && p[6] < global.plot)
    {
        // Their cutscene starts from earlier in the story than we are: we've had it already.
        mp_log("pull dropped: plot " + string(p[6]) + " < " + string(global.plot));
        global.mp_pull = -1;
        return;
    }
    if (kind == 2 && global.interact == 0 && p[2] == global.mp_last_cs_room && p[6] <= global.mp_last_cs_plot && (current_time - global.mp_last_cs_end) < 60000)
    {
        // The same cutscene just played in my own game (e.g. they arrived while it was on).
        mp_log("pull dropped: just had that cutscene here");
        global.mp_pull = -1;
        return;
    }
    if (kind == 2 && global.mp_slead == from && global.mp_sstate != 0)
    {
        global.mp_pull = -1;   // already with them
        return;
    }
    // (A battle pull never waits for my own cutscene: the battle is already running for them, and
    // a cutscene of mine that leads into the same fight would start it again here from turn 0
    // while they are further on. My cutscene is cut short when I join, see mp_kill_scenes.)
    if (kind == 2 && global.mp_sstate != 0)
    {
        // Busy with a cutscene in our own game (or watching another one). If it starts the
        // battle by itself the pull is dropped above (we're in battle); otherwise join
        // afterwards if their event is still going.
        global.mp_pull[7] += 1;
        var going = (global.mp_pstate[from] & 1) != 0;
        if (kind == 2)
            going = (global.mp_pstate[from] & 2) != 0;
        if (global.mp_pull[7] > 3600 || (!going && global.mp_pull[7] > 150))
            global.mp_pull = -1;
        return;
    }
    if (!instance_exists(obj_mainchara))
    {
        // Title screen / file select: cannot be pulled yet.
        global.mp_pull[7] += 1;
        if (p[7] > 300)
            global.mp_pull = -1;
        return;
    }
    // A battle that already finished is not worth joining.
    if (kind == 1 && (global.mp_pstate[from] & 1) == 0 && p[7] > 150)
    {
        global.mp_pull = -1;
        return;
    }
    var busy = global.interact != 0 && global.mp_sstate == 0;
    if (kind == 2 && busy && global.mp_classify > 0 && room == p[2])
    {
        // The same cutscene just started in my game too: play along instead of being moved.
        global.mp_pull = -1;
        global.mp_classify = 0;
        mp_sync_follow(from);
        return;
    }
    if (kind == 2 && busy && mp_cutscene_running())
    {
        // Never cut short a story cutscene playing in my own game; join afterwards if the
        // other player's event is still going.
        global.mp_pull[7] += 1;
        var still = (global.mp_pstate[from] & 2) != 0;
        if (kind == 1)
            still = (global.mp_pstate[from] & 1) != 0;
        if (global.mp_pull[7] > 3600 || (!still && global.mp_pull[7] > 150))
            global.mp_pull = -1;
        return;
    }
    // Let a local conversation or room transition finish (up to ~3 seconds).
    if (busy && p[7] < 90)
    {
        global.mp_pull[7] += 1;
        return;
    }
    if (busy)
        mp_close_local_dialogue();
    global.mp_pull = -1;
    global.mp_slead = from;
    // Catch up on shared state that arrived while busy, then take the leader's party
    // (the battle's, or from just before the cutscene): the event may need its members.
    mp_vars_apply_queue();
    var vc = mp_var_index("char");
    var pp = p[9];
    var dz_changed = mp_dz_take(p[10]);
    var party_changed = false;
    for (var i = 0; i < 3; i++)
    {
        if (global.char[i] != pp[i])
            party_changed = true;
        mp_var_apply(vc, i, pp[i]);
    }
    if (kind == 1)
    {
        with (obj_mainchara)
            visible = 1;
        global.interact = 0;
        global.mp_sstate = 0;
        global.encounterno = p[5];
        global.mp_battle_pulled = 1;
        mp_notify("Joining " + global.mp_pname[from] + "'s battle!");
        global.mp_warp_mus = from;
        global.mp_warp_reenter = dz_changed;
        mp_warp(p[2], p[3], p[4], 1);
    }
    else
    {
        // Their story progress from before the cutscene (never moving ours backwards).
        if (p[6] > global.plot)
            global.plot = p[6];
        global.mp_sstate = 3;
        global.mp_wait = -1;
        global.mp_lead_done = 0;
        global.mp_choice_seq = 0;
        global.mp_watch_text = "";
        ds_map_clear(global.mp_choices);
        mp_notify("Joining " + global.mp_pname[from] + " for a cutscene...");
        // Cutscenes that start on entering a room need us to enter it too (and so does a
        // changed party: followers are only created when entering a room).
        global.mp_warp_reenter = p[8] || party_changed || dz_changed;
        global.mp_warp_mus = from;
        mp_warp(p[2], p[3], p[4], 2);
    }
}

// Something that is (or may become) a story cutscene is playing in my own game.
function mp_cutscene_running()
{
    if (global.mp_classify > 0)
        return true;
    var cm = asset_get_index("obj_cutscene_master");
    if (cm >= 0 && instance_exists(cm))
        return true;
    // Chapter 1 has no cutscene master: its story controllers are obj_*event objects with a
    // `con` state counter that is above 0 while they play.
    if (global.mp_chapter == 1 && global.interact != 0)
        return mp_ch1_event_running();
    return false;
}

function mp_ch1_event_running()
{
    if ((global.mp_frame - global.mp_ch1ev_frame) < 10)
        return global.mp_ch1ev_value;
    global.mp_ch1ev_frame = global.mp_frame;
    var found = false;
    with (all)
    {
        var nm = object_get_name(object_index);
        if (string_pos("obj_", nm) == 1 && string_pos("event", nm) > 0 && variable_instance_exists(id, "con"))
        {
            if (is_real(con) && con > 0 && con < 90)
            {
                found = true;
                break;
            }
        }
    }
    global.mp_ch1ev_value = found;
    return found;
}

// I am now playing the cutscene `from` leads, in my own game.
function mp_sync_follow(from)
{
    global.mp_slead = from;
    global.mp_sstate = 2;
    global.mp_idle = 0;
    global.mp_lead_done = 0;
    global.mp_choice_seq = 0;
    ds_map_clear(global.mp_choices);
}

function mp_close_local_dialogue()
{
    with (obj_writer)
        instance_destroy();
    with (obj_dialoguer)
        instance_destroy();
    with (obj_choicer_neo)
        instance_destroy();
    global.interact = 0;
    global.mp_local_dlg = 0;
}

// Called once we are standing where the leader was when the cutscene started.
// (mp_warp_place already released the warp's interact = 3; a cutscene that started on
// entering the room may have set it to 1 by now, which must be kept.)
function mp_sync_arrived()
{
    global.mp_wait = 0;
}

function mp_sync_tick()
{
    var ia = global.interact;
    var battle = mp_in_battle_scene();
    if (instance_exists(obj_mainchara))
    {
        global.mp_hist_i = (global.mp_hist_i + 1) mod 16;
        global.mp_hist_x[global.mp_hist_i] = obj_mainchara.x;
        global.mp_hist_y[global.mp_hist_i] = obj_mainchara.y;
    }
    if (ia == 0)
        global.mp_room_calm = 1;
    if (is_array(global.mp_pull))
        mp_sync_try_pull();

    if (battle && global.mp_battle_pulled && mp_cutscene_master_exists() && !variable_global_exists("mp_scene_in_battle_logged"))
    {
        global.mp_scene_in_battle_logged = 1;
        mp_log("SCENE-IN-BATTLE: a cutscene is running in a battle I was pulled into");
    }
    // Battle started in my game.
    if (battle && !global.mp_battle_seen)
    {
        global.mp_battle_seen = 1;
        if (!global.mp_battle_pulled && (global.mp_sstate == 0 || global.mp_sstate == 1))
            mp_send_pull(1);
    }
    if (!battle && global.mp_battle_seen && !instance_exists(obj_battlecontroller))
    {
        global.mp_battle_seen = 0;
        global.mp_battle_pulled = 0;
    }

    if (ia != 0 && room == global.mp_last_cs_room)
        global.mp_last_cs_end = current_time;
    if (ia != global.mp_prev_interact)
        mp_log("interact " + string(global.mp_prev_interact) + "->" + string(ia) + " sst=" + string(global.mp_sstate) + " room=" + room_get_name(room) + " rf=" + string(global.mp_room_frames) + " z=" + string(global.mp_frame - global.mp_lastz) + " plot=" + string(global.plot));
    switch (global.mp_sstate)
    {
        case 0:
            if (mp_story_rise(ia, battle))
                global.mp_classify = 1;
            else if (global.mp_prev_interact == 0 && ia != 0)
                global.mp_local_dlg = 1;
            if (ia == 0)
                global.mp_local_dlg = 0;
            if (mp_classify_step(ia, battle) && mp_player_count() > 1)
            {
                global.mp_sstate = 1;
                global.mp_idle = 0;
                global.mp_lead_text = "";
                global.mp_slead = global.mp_myid;
                mp_send_pull(2);
            }
            break;
        case 1:
            // The next cutscene started right after this one (only a moment of walking in
            // between, or straight through a door): pull whoever is walking around again.
            if (mp_story_rise(ia, battle))
                global.mp_classify = 1;
            if (mp_classify_step(ia, battle))
                mp_send_pull(2);
            if ((global.mp_frame mod 6) == 0)
            {
                var lt = mp_dialogue_text();
                if (lt != global.mp_lead_text)
                {
                    global.mp_lead_text = lt;
                    mp_begin(33);
                    mp_wstr(lt);
                    mp_send();
                }
            }
            if (ia == 0 && !battle)
            {
                global.mp_idle += 1;
                if (global.mp_idle > 20)
                {
                    // The story changes from the cutscene go out first: spectators are
                    // moved to where it ended, which may need them (e.g. new party members).
                    mp_vars_send_changes(true);
                    mp_send_cend();
                    global.mp_sstate = 0;
                    global.mp_slead = -1;
                }
            }
            else
            {
                global.mp_idle = 0;
            }
            break;
        case 2:
            if (ia == 0 && !battle)
            {
                global.mp_idle += 1;
                if (global.mp_idle > 20)
                {
                    global.mp_sstate = 0;
                    global.mp_slead = -1;
                }
            }
            else
            {
                global.mp_idle = 0;
            }
            break;
        case 3:
            if (global.mp_wait >= 0 && !global.mp_warp_pending)
            {
                global.mp_wait += 1;
                if (ia == 1 || battle)
                {
                    global.mp_sstate = 2;
                    global.mp_idle = 0;
                }
                else if (global.mp_wait > 90)
                {
                    global.mp_sstate = 4;
                    global.mp_lead_free = 0;
                    mp_log("cutscene did not start here: watching");
                }
            }
            if (!global.mp_pconn[global.mp_slead])
            {
                global.mp_sstate = 0;
                global.interact = 0;
            }
            break;
        case 4:
            global.interact = 1;
            if (!global.mp_pconn[global.mp_slead])
            {
                global.mp_sstate = 0;
                global.interact = 0;
            }
            // Safety valve: the leader has been walking around freely for a while (their
            // "cutscene" was something tiny that only concerned their game).
            if ((global.mp_pstate[global.mp_slead] & 4) == 0)
                global.mp_lead_free += 1;
            else
                global.mp_lead_free = 0;
            if (global.mp_lead_free > 90)
            {
                mp_log("leader is walking around again: released");
                global.mp_sstate = 0;
                global.mp_slead = -1;
                global.mp_watch_text = "";
                global.interact = 0;
            }
            break;
    }
    global.mp_prev_interact = global.interact;
    if (global.interact == 0 && global.mp_sstate <= 1)
    {
        global.mp_calm_plot = global.plot;
        global.mp_calm_party = [global.char[0], global.char[1], global.char[2]];
        global.mp_calm_dz = mp_dz();
    }
}

// True when interact just went up for something that looks like a story cutscene (not the
// player pressing Z on something); records where and when it started for mp_send_pull(2).
function mp_story_rise(ia, battle)
{
    // A door transition (interact 3) handing straight over to a cutscene counts too.
    var rise = ia != 0 && (global.mp_prev_interact == 0 || (global.mp_prev_interact == 3 && ia == 1 && global.mp_room_frames < 30));
    if (!rise)
        return false;
    var talked = (global.mp_frame - global.mp_lastz) <= 3;
    if (ia != 1 || talked || battle || global.mp_warp_pending || mp_battle_starting())
        return false;
    // Events on the Chapter 3 board happen on each player's own board, and the end credits
    // run in each player's own game (their rooms need the credits' own objects).
    if (mp_board_on() || mp_credits_running())
        return false;
    // Where the leader stood when the cutscene triggered: standing there re-triggers
    // position-based cutscenes in the pulled players' games.
    // (A couple of frames back: a cutscene may move the player away on its first frame.)
    var hi = global.mp_hist_i;
    if (global.mp_room_frames >= 4)
        hi = (global.mp_hist_i + 14) mod 16;
    global.mp_pre_room = room;
    global.mp_pre_x = global.mp_hist_x[hi];
    global.mp_pre_y = global.mp_hist_y[hi];
    // Story progress from before the cutscene, so it triggers for them too.
    global.mp_pre_plot = global.mp_calm_plot;
    global.mp_pre_party = global.mp_calm_party;
    global.mp_pre_dz = global.mp_calm_dz;
    // Started on entering the room: pulled players must enter it as well.
    global.mp_pre_entry = global.mp_room_frames < 30 || !global.mp_room_calm;
    // (Cutscene controllers can linger after their cutscene: only a new one counts.)
    global.mp_pre_master = mp_newest_master();
    global.mp_pre_actors = mp_actor_count();
    global.mp_last_cs_room = room;
    global.mp_last_cs_plot = global.mp_pre_plot;
    global.mp_pre_vis = 1;
    global.mp_pre_mx = 0;
    global.mp_pre_my = 0;
    if (instance_exists(obj_mainchara))
    {
        global.mp_pre_vis = obj_mainchara.visible;
        global.mp_pre_mx = obj_mainchara.x;
        global.mp_pre_my = obj_mainchara.y;
    }
    return true;
}

// The chapter's end credits are playing in my game.
function mp_credits_running()
{
    var names = ["obj_credits", "obj_credits_2", "obj_credits_ch3", "obj_credits_ch4", "obj_credits_ch5", "obj_credits_ch5_audio", "obj_credits_ch5_transition"];
    for (var i = 0; i < array_length(names); i++)
    {
        var o = asset_get_index(names[i]);
        if (o >= 0 && instance_exists(o))
            return true;
    }
    return false;
}

// Rooms players may be moved into (never Game Over, title or menu rooms).
function mp_room_ok(rm)
{
    if (!room_exists(rm))
        return false;
    var n = room_get_name(rm);
    return string_pos("room_", n) == 1 && string_pos("gameover", n) == 0;
}

// Instance id of the newest cutscene controller (Chapter 2+), or -1.
function mp_newest_master()
{
    var cm = asset_get_index("obj_cutscene_master");
    var best = -1;
    if (cm >= 0)
    {
        with (cm)
        {
            if (real(id) > best)
                best = real(id);
        }
    }
    return best;
}

// Decides whether what started without the player pressing Z (mp_story_rise) is a story
// cutscene. mp_classify counts the frames it has been going (0: nothing to decide).
// Returns true once, at the moment the others should be pulled in.
function mp_classify_step(ia, battle)
{
    if (global.mp_classify <= 0)
        return false;
    // (A cutscene may move to another room early on: the others still start where it began.)
    if (ia == 0 || battle || mp_battle_starting())
    {
        global.mp_classify = 0;
        return false;
    }
    global.mp_classify += 1;
    if (global.mp_classify < 20)
        return false;
    // A story cutscene does something a text box that pops up by itself ("there's nothing
    // that way") doesn't: starts a cutscene controller (Chapter 2+), moves the story on,
    // creates actors, hides or moves the player, or stops the party following.
    var strong = mp_newest_master() > global.mp_pre_master || global.plot != global.mp_pre_plot || mp_actor_count() > global.mp_pre_actors;
    if (!strong && instance_exists(obj_mainchara))
    {
        if (global.mp_pre_vis && !obj_mainchara.visible)
            strong = true;
        if (point_distance(obj_mainchara.x, obj_mainchara.y, global.mp_pre_mx, global.mp_pre_my) > 6)
            strong = true;
    }
    if (strong)
    {
        global.mp_classify = 0;
        return true;
    }
    return false;
}

// Cutscene actors / markers in the room (and party members told to stop following).
function mp_actor_count()
{
    var n = instance_number(obj_marker);
    var ac = asset_get_index("obj_actor");
    if (ac >= 0)
        n += instance_number(ac);
    with (obj_caterpillarchara)
    {
        if (variable_instance_exists(id, "follow") && follow == 0)
            n += 1;
    }
    return n;
}

// An enemy was touched: the "!" before a battle (interact goes up like in a cutscene, and
// the battle itself only appears a little later).
function mp_battle_starting()
{
    return instance_exists(obj_testoverworldenemy) || global.mp_battle_pulled;
}

// Dialogue choices inside a shared cutscene follow the leader.
// Returns -1 while still waiting, otherwise the choice to use.
function mp_choice_follow(localchoice)
{
    if (!mp_on() || global.mp_sstate != 2)
        return localchoice;
    var seq = global.mp_choice_seq;
    if (ds_map_exists(global.mp_choices, seq))
    {
        global.mp_choice_seq += 1;
        return ds_map_find_value(global.mp_choices, seq);
    }
    return -1;
}

// Leader reports a choice it made.
function mp_choice_made(val)
{
    if (!mp_on() || global.mp_sstate != 1)
        return;
    mp_begin(32);
    mp_wu16(global.mp_choice_seq);
    mp_ws8(val);
    mp_send();
    global.mp_choice_seq += 1;
}

function mp_status_line()
{
    if (!mp_on())
        return "";
    var bs = mp_battle_status();
    if (bs != "")
        return bs;
    if (global.mp_sstate == 4)
        return "Watching " + global.mp_pname[global.mp_slead] + "'s cutscene...";
    if (global.mp_sstate == 3)
        return "Joining " + global.mp_pname[global.mp_slead] + "...";
    if (global.mp_sstate == 2 && instance_exists(obj_choicer_neo))
        return global.mp_pname[global.mp_slead] + " is choosing...";
    return "";
}

// Prepended to obj_choicer_neo's Step: followers take the leader's answer.
function mp_choice_step()
{
    if (!variable_global_exists("mp_inited") || !mp_on() || global.mp_sstate != 2)
        return;
    if (canchoose == 1 && choiced == 0)
    {
        var c = mp_choice_follow(-1);
        if (c >= 0)
        {
            mychoice = c;
            event_user(0);
        }
    }
}

// Plain text of the dialogue box on screen (control codes removed), or "".
function mp_dialogue_text()
{
    if (!instance_exists(obj_writer))
        return "";
    var src = "";
    with (obj_writer)
    {
        if (variable_instance_exists(id, "mystring") && is_string(mystring))
            src = mystring;
    }
    var out = "";
    var n = string_length(src);
    var i = 1;
    while (i <= n)
    {
        var ch = string_char_at(src, i);
        if (ch == "\\")
            i += 3;
        else if (ch == "^")
            i += 2;
        else
        {
            if (ch == "&" || ch == "#")
                out += "\n";
            else if (ch != "/" && ch != "%")
                out += ch;
            i += 1;
        }
    }
    return string_copy(out, 1, 300);
}
