// DELTARUNE Multiplayer - core: init, players, config, per-frame entry points, dispatch.

function mp_init()
{
    if (variable_global_exists("mp_inited"))
        return;
    global.mp_inited = 1;
    global.mp_version = 3;
    global.mp_chapter = __CHAPTER__;
    global.mp_frame = 0;
    global.mp_notes = ds_list_create();
    global.mp_note_time = ds_list_create();
    global.mp_pconn = array_create(8, 0);
    global.mp_pname = array_create(8, "");
    global.mp_pchar = array_create(8, 1);
    global.mp_plast = array_create(8, 0);
    global.mp_proom = array_create(8, -1);
    global.mp_px = array_create(8, 0);
    global.mp_py = array_create(8, 0);
    global.mp_pspr = array_create(8, -1);
    global.mp_pimg = array_create(8, 0);
    global.mp_pxs = array_create(8, 1);
    global.mp_pys = array_create(8, 1);
    global.mp_pstate = array_create(8, 0);
    global.mp_pvis = array_create(8, 0);
    global.mp_pghost = array_create(8, -4);
    global.mp_ppostime = array_create(8, 0);
    global.mp_pix = array_create(8, 0);
    global.mp_piy = array_create(8, 0);
    mp_net_init();
    mp_config_load();
    mp_world_init();
    mp_sync_init();
    mp_battle_init();
    mp_ui_init();
    global.mp_resumed = 0;
    global.mp_resume_done = 0;
    mp_parse_cmdline();
    mp_resume_load();
    exception_unhandled_handler(mp_on_crash);
}

// Unhandled error anywhere in the game: log it (tests look for [MPCRASH]), keep a copy in
// multiplayer_crash.txt next to the saves, and show it like GameMaker would.
function mp_on_crash(ex)
{
    var txt = "";
    if (is_struct(ex))
    {
        txt = string(ex.longMessage);
        if (variable_struct_exists(ex, "stacktrace"))
            txt += "\nstack: " + string(ex.stacktrace);
    }
    else
    {
        txt = string(ex);
    }
    var where = "chapter " + string(global.mp_chapter) + ", room " + room_get_name(room);
    if (variable_global_exists("plot"))
        where += ", plot " + string(global.plot);
    if (variable_global_exists("mp_sstate"))
        where += ", sync " + string(global.mp_sstate) + ", interact " + string(global.interact) + ", players " + string(mp_player_count());
    if (variable_global_exists("hp") && variable_global_exists("char") && variable_global_exists("charcantarget"))
        where += ", party " + string(global.char[0]) + string(global.char[1]) + string(global.char[2]) + " hp " + string(global.hp[1]) + "/" + string(global.hp[2]) + "/" + string(global.hp[3]) + " cantarget " + string(global.charcantarget[0]) + string(global.charcantarget[1]) + string(global.charcantarget[2]);
    show_debug_message("[MPCRASH] " + where + " | " + string_replace_all(txt, "\n", " | "));
    var f = file_text_open_write("multiplayer_crash.txt");
    file_text_write_string(f, where + "\n" + txt);
    file_text_close(f);
    if (global.mp_test == "")
        show_message("DELTARUNE crashed (" + where + "). Details were saved to multiplayer_crash.txt.\n\n" + txt);
    return 0;
}

function mp_on()
{
    return global.mp_role != 0 && global.mp_linkstate == 3;
}

function mp_players_clear()
{
    for (var i = 0; i < 8; i++)
    {
        global.mp_pconn[i] = 0;
        global.mp_pname[i] = "";
        global.mp_proom[i] = -1;
        global.mp_pstate[i] = 0;
        global.mp_pvis[i] = 0;
    }
    mp_ghosts_clear();
}

function mp_player_set(pid, conn, name, chr)
{
    global.mp_pconn[pid] = conn;
    global.mp_pname[pid] = name;
    global.mp_pchar[pid] = chr;
    if (!conn)
    {
        global.mp_proom[pid] = -1;
        global.mp_pstate[pid] = 0;
        mp_ghost_remove(pid);
    }
}

function mp_unique_name(nm, pid)
{
    nm = string_copy(nm, 1, 12);
    if (nm == "")
        nm = "Player";
    var base = nm;
    var n = 2;
    var clash = true;
    while (clash)
    {
        clash = false;
        for (var i = 0; i < 8; i++)
        {
            if (i != pid && global.mp_pconn[i] && global.mp_pname[i] == nm)
                clash = true;
        }
        if (clash)
        {
            nm = base + string(n);
            n++;
        }
    }
    return nm;
}

function mp_send_pinfo(pid)
{
    mp_begin(3);
    mp_wu8(pid);
    mp_wu8(global.mp_pconn[pid]);
    mp_wstr(global.mp_pname[pid]);
    mp_wu8(global.mp_pchar[pid]);
    mp_send();
}

function mp_player_count()
{
    var n = 0;
    for (var i = 0; i < 8; i++)
    {
        if (global.mp_pconn[i])
            n++;
    }
    return n;
}

function mp_char_name(c)
{
    switch (c)
    {
        case 1:
            return "Kris";
        case 2:
            return "Susie";
        case 3:
            return "Ralsei";
        case 4:
            return "Noelle";
    }
    return "?";
}

function mp_char_prefix(c)
{
    switch (c)
    {
        case 1:
            return "kris";
        case 2:
            return "susie";
        case 3:
            return "ralsei";
        case 4:
            return "noelle";
    }
    return "kris";
}

function mp_char_color(c)
{
    switch (c)
    {
        case 1:
            return make_color_rgb(0, 162, 232);
        case 2:
            return make_color_rgb(234, 121, 200);
        case 3:
            return make_color_rgb(181, 230, 29);
        case 4:
            return make_color_rgb(255, 238, 112);
    }
    return c_white;
}

// Characters a player can pick in this chapter.
function mp_char_max()
{
    if (global.mp_chapter >= 2)
        return 4;
    return 3;
}

function mp_notify(text)
{
    ds_list_add(global.mp_notes, text);
    ds_list_add(global.mp_note_time, current_time);
    while (ds_list_size(global.mp_notes) > 5)
    {
        ds_list_delete(global.mp_notes, 0);
        ds_list_delete(global.mp_note_time, 0);
    }
    show_debug_message("[MP] " + text);
}

// ---------------------------------------------------------------- config

function mp_config_load()
{
    ini_open("multiplayer.ini");
    global.mp_cfg_name = ini_read_string("player", "name", "Player");
    global.mp_cfg_char = ini_read_real("player", "char", 1);
    global.mp_cfg_ip = ini_read_string("net", "ip", "127.0.0.1");
    global.mp_cfg_port = ini_read_real("net", "port", 26510);
    ini_close();
    global.mp_cfg_char = clamp(global.mp_cfg_char, 1, mp_char_max());
}

function mp_config_save()
{
    ini_open("multiplayer.ini");
    ini_write_string("player", "name", global.mp_cfg_name);
    ini_write_real("player", "char", global.mp_cfg_char);
    ini_write_string("net", "ip", global.mp_cfg_ip);
    ini_write_real("net", "port", global.mp_cfg_port);
    ini_close();
}

// A running session is remembered in the ini so the next chapter (a separate game process)
// can pick it up again: the host hosts again, the others join again (they keep retrying).
function mp_resume_save()
{
    if (!mp_on())
        return;
    ini_open("multiplayer.ini");
    ini_write_real("resume", "role", global.mp_role);
    ini_write_string("resume", "ip", global.mp_role == 2 ? global.mp_join_ip : "");
    ini_write_real("resume", "port", global.mp_role == 2 ? global.mp_join_port : global.mp_cfg_port);
    ini_write_real("resume", "chapter", global.mp_chapter);
    ini_write_string("resume", "time", string_format(date_current_datetime(), 8, 8));
    ini_close();
}

function mp_resume_clear()
{
    ini_open("multiplayer.ini");
    ini_write_real("resume", "role", 0);
    ini_close();
}

// At start-up: a session from another chapter, left a moment ago, is continued.
function mp_resume_load()
{
    if (global.mp_auto != "" || global.mp_test != "")
        return;
    ini_open("multiplayer.ini");
    var role = ini_read_real("resume", "role", 0);
    var ip = ini_read_string("resume", "ip", "");
    var port = ini_read_real("resume", "port", 26510);
    var ch = ini_read_real("resume", "chapter", 0);
    var t = real(ini_read_string("resume", "time", "0"));
    ini_close();
    if (role == 0 || ch == global.mp_chapter || ch == 0)
        return;
    if (abs(date_current_datetime() - t) > (15 / 1440))
        return;
    if (role == 1)
    {
        global.mp_auto = "host";
        global.mp_cfg_port = port;
    }
    else if (ip != "")
    {
        global.mp_auto = "join";
        global.mp_cfg_ip = ip;
        global.mp_cfg_port = port;
    }
    else
        return;
    global.mp_resumed = 1;
}

// Command line: -mpname <n> -mpchar <1-4> -mpport <p> -mphost | -mpjoin <ip[:port]> | -mptest <cmd>
function mp_parse_cmdline()
{
    global.mp_auto = "";
    global.mp_test = "";
    var n = parameter_count();
    for (var i = 0; i < n; i++)
    {
        var p = parameter_string(i);
        var v = "";
        if ((i + 1) < n)
            v = parameter_string(i + 1);
        if (p == "-mpname")
            global.mp_cfg_name = v;
        if (p == "-mpchar")
            global.mp_cfg_char = clamp(real(v), 1, mp_char_max());
        if (p == "-mpport")
            global.mp_cfg_port = real(v);
        if (p == "-mphost")
            global.mp_auto = "host";
        if (p == "-mpjoin")
        {
            global.mp_auto = "join";
            var c = string_pos(":", v);
            if (c > 0)
            {
                global.mp_cfg_ip = string_copy(v, 1, c - 1);
                global.mp_cfg_port = real(string_delete(v, 1, c));
            }
            else
            {
                global.mp_cfg_ip = v;
            }
        }
        if (p == "-mptest")
            global.mp_test = v;
    }
}

// ---------------------------------------------------------------- session lifecycle

function mp_on_session_start()
{
    mp_vars_reset_shadow();
    mp_sync_reset();
    mp_battle_reset();
    mp_battle_clear_buffers();
    global.mp_pos_force = 1;
}

function mp_on_session_end()
{
    mp_ghosts_clear();
    mp_sync_release_all();
    mp_battle_reset();
}

// ---------------------------------------------------------------- dispatch

function mp_handle(type, sender, b, sock, endpos)
{
    if (mp_handle_link(type, sender, b, sock))
        return;
    if (type == 3) // PINFO
    {
        var pid = buffer_read(b, buffer_u8);
        var conn = buffer_read(b, buffer_u8);
        var nm = buffer_read(b, buffer_string);
        var chr = buffer_read(b, buffer_u8);
        if (global.mp_role == 1 && sender != 0)
        {
            // A client may only change its own character.
            if (pid != sender)
                return;
            global.mp_pchar[pid] = chr;
            mp_send_pinfo(pid);
            return;
        }
        var was = global.mp_pconn[pid];
        if (pid == global.mp_myid && global.mp_role == 2)
        {
            global.mp_pname[pid] = nm;
            return;
        }
        mp_player_set(pid, conn, nm, chr);
        // (Players already in the session when we joined arrive right after WELCOME: no pop-up.)
        if (!was && conn && pid != global.mp_myid && global.mp_role == 2 && global.mp_linkstate == 3 && (current_time - global.mp_welcome_time) > 2000)
            mp_notify(nm + " joined!");
        if (was && !conn)
            mp_notify(nm + " left.");
        return;
    }
    if (type == 10)
    {
        mp_recv_pos(sender, b);
        return;
    }
    if (type == 20)
    {
        mp_vars_recv(sender, b);
        return;
    }
    if (type == 21) // a client reloaded and wants the shared state again
    {
        if (global.mp_role == 1)
            mp_vars_send_full(sock);
        return;
    }
    if (type >= 30 && type < 40)
    {
        mp_sync_recv(type, sender, b);
        return;
    }
    if (type >= 40 && type < 60)
    {
        mp_battle_recv(type, sender, b);
        return;
    }
}

// ---------------------------------------------------------------- per-frame entry points

// Prepended to obj_time's Begin Step: undo last frame's input masking so the game's
// "just pressed" detection sees the real key state (otherwise held keys re-fire).
function mp_before_input()
{
    if (!variable_global_exists("mp_real_held"))
        return;
    for (var i = 0; i < 10; i++)
        global.input_held[i] = global.mp_real_held[i];
}

// Appended to obj_time's Begin Step, right after the game samples its input.
function mp_after_input()
{
    if (!variable_global_exists("mp_inited"))
        return;
    if (!variable_global_exists("mp_real_held"))
        global.mp_real_held = array_create(10, 0);
    for (var k = 0; k < 10; k++)
        global.mp_real_held[k] = global.input_held[k];
    global.mp_frame += 1;
    global.mp_room_frames += 1;
    global.mp_fol_last = global.mp_fol_mask;
    global.mp_fol_mask = 0;
    mp_ui_input();
    mp_test_input();
    // (Tests with "party": connect once the test setup has put us in our room.)
    var test_wait = global.mp_test != "" && mp_test_has("party") && (!variable_global_exists("mp_test_state") || global.mp_test_state == 0 || global.mp_test_timer < 30);
    if (global.mp_auto != "" && !(global.mp_auto == "join" && test_wait))
    {
        if (global.mp_resumed)
            mp_notify("Continuing the multiplayer session in this chapter...");
        if (global.mp_auto == "host")
            mp_host_start(global.mp_cfg_port);
        else
        {
            global.mp_join_retries = 20;
            mp_join(global.mp_cfg_ip, global.mp_cfg_port);
        }
        global.mp_auto = "";
    }
    if (global.mp_role == 0 && global.mp_join_retry_at > 0 && current_time >= global.mp_join_retry_at)
    {
        global.mp_join_retry_at = 0;
        mp_join(global.mp_cfg_ip, global.mp_cfg_port);
    }
    if (!mp_on())
        return;
    mp_sync_input();
    mp_battle_input();
}

// obj_mp_controller Step.
function mp_tick()
{
    if (global.mp_test != "")
        mp_test_tick();
    if (global.mp_role == 0)
        return;
    mp_net_tick();
    if (!mp_on())
        return;
    if ((global.mp_frame mod 600) == 5 || !global.mp_resume_done)
    {
        global.mp_resume_done = 1;
        mp_resume_save();
    }
    mp_sync_tick();
    mp_battle_tick();
    mp_world_tick();
}

// obj_mp_controller End Step.
function mp_end_tick()
{
    if (global.mp_role == 0)
        return;
    if (mp_on())
        mp_ghosts_update();
    mp_flush();
}
