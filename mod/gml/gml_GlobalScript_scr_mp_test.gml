// DELTARUNE Multiplayer - automated test helpers (enabled with -mptest "<tokens>").
// Tokens (comma separated):
//   party           give the save a full dark-world party (Kris/Susie/Ralsei) and go to `room`
//   room:<name>     room to start in (with `party`)
//   plot:<n>        story progress to use (with `party`)
//   battle:<enc>    start encounter <enc> ~4s after arriving (once)
//   bot             press buttons automatically (menus, attacks, dodging)
//   log             log battle state every turn
//   check           log a self-check line twice a second (character drawn, followers drawn,
//                   other players' positions, shared state hash, sync state) for tools/mpcheck.py
//   mash            press Z through title screens, menus and cutscenes (real game start)
//   wander          walk around randomly in free roam
//   partyat:<n>     do `party` after n frames (default 60)
//   walk:<d>:<t>:<n>  hold direction d (l/r/u/d) for n frames, t frames after arriving
//   away:<room>:<n>[:<x>:<y>] once connected, n frames after the party setup, go to <room> (like walking through a door)
//   fakescene       (test of the pulled-battle cleanup) start a cutscene of our own while being pulled into a battle
//   lightworld      with `party`: start in the Light World (Kris and Susie)
//   setplot:<n>     set the story progress to <n> after a while (shared with the others)
//   gotohost:<n>    press the "go to the other player" action n frames after the party setup
//   nododge         bot: don't dodge in the bullet phase (heroes go down)
//   battleat:<n>    with battle: start the encounter n frames after arriving (default 120)
//   song:<file>     play this song after the party setup (music sync tests)
//   mashevery:<n>   mash presses Z every n frames (default 10); mashfrom:<n> only after n frames in the room
//   stuck:<n>       fake a stuck sync state n frames after the party setup (F8 must free it)
//   weak            enemies have 1 HP (battle ends quickly)
//   save            save the game to slot 0 once in free roam (for later load tests)
//   load:<slot>     load save slot <slot> from the title screen
//   solo            with `party`: Kris alone
//   duo             with `party`: Kris and Susie (with `battle`: the battle party)
//   watchplot       log plot, party and the room's story events every 5 s
//   staleplot:<a>:<b>  when the plot reaches a (outside battles), set it back to b once
//   nomono          (test of the stale-plot guard) accept a lower plot from the others

function mp_test_has(tok)
{
    var t = "," + global.mp_test + ",";
    return string_pos("," + tok + ",", t) > 0 || string_pos("," + tok + ":", t) > 0;
}

function mp_test_arg(tok)
{
    var t = "," + global.mp_test + ",";
    var p = string_pos("," + tok + ":", t);
    if (p == 0)
        return "";
    var rest = string_delete(t, 1, p + string_length(tok) + 1);
    return string_copy(rest, 1, string_pos(",", rest) - 1);
}

function mp_test_tick()
{
    if (!variable_global_exists("mp_test_state"))
    {
        global.mp_test_state = 0;
        global.mp_test_timer = 0;
        global.mp_test_battled = 0;
        global.mp_test_lastturn = -1;
    }
    global.mp_test_timer += 1;
    // Wall clock with frame precision for tools/mpcheck.py: the moment the (whole-second)
    // wall clock ticks over.
    var wsec = floor((date_current_datetime() - 45000) * 86400 + 0.5);
    if (!variable_global_exists("mp_test_ws") || wsec != global.mp_test_ws)
    {
        global.mp_test_ws = wsec;
        global.mp_test_wb = current_time;
    }
    var partyat = 60;
    if (mp_test_arg("partyat") != "")
        partyat = real(mp_test_arg("partyat"));
    if (global.mp_test_state == 0 && mp_test_has("party") && global.mp_test_timer > partyat)
    {
        global.mp_test_state = 1;
        global.char[0] = 1;
        global.char[1] = 2;
        global.char[2] = 3;
        global.darkzone = 1;
        var pl = mp_test_arg("plot");
        // (A client that already joined keeps the story progress it got from the host.)
        if (pl != "" && !(mp_on() && global.mp_role == 2))
            global.plot = real(pl);
        mp_ch_test_party();
        // duo: Kris and Susie
        if (mp_test_has("duo"))
            global.char[2] = 0;
        // solo: Kris alone (the very start of the Dark World)
        if (mp_test_has("solo"))
        {
            global.char[1] = 0;
            global.char[2] = 0;
        }
        // lightworld: start as in the Light World (Kris and Susie only)
        if (mp_test_has("lightworld"))
        {
            global.darkzone = 0;
            global.char[2] = 0;
        }
        var rn = mp_test_arg("room");
        if (rn == "")
            rn = "room_field1";
        global.interact = 0;
        room_goto(asset_get_index(rn));
        global.mp_test_timer = 0;
        mp_notify("[test] party ready, going to " + rn);
    }
    if (mp_test_has("pos") && !variable_global_exists("mp_test_posdone") && instance_exists(obj_mainchara) && global.mp_test_timer > 90)
    {
        global.mp_test_posdone = 1;
        var pv = mp_test_arg("pos");
        var c = string_pos(":", pv);
        with (obj_mainchara)
        {
            x = real(string_copy(pv, 1, c - 1));
            y = real(string_delete(pv, 1, c));
        }
        with (obj_caterpillarchara)
        {
            x = obj_mainchara.x;
            y = obj_mainchara.y;
            scr_caterpillar_interpolate();
        }
    }
    // watchplot: log story progress, party and what the room's story events are doing every 5 s
    if (mp_test_has("watchplot") && (global.mp_frame mod 150) == 0 && variable_global_exists("plot"))
    {
        var evs = "";
        with (all)
        {
            var onm = object_get_name(object_index);
            if (string_pos("obj_", onm) == 1 && string_pos("event", onm) > 0 && variable_instance_exists(id, "con"))
                evs += " " + onm + ":" + string(con);
        }
        mp_log("[watch] " + room_get_name(room) + " plot=" + string(global.plot) + " party=" + string(global.char[0]) + string(global.char[1]) + string(global.char[2]) + " interact=" + string(global.interact) + " susieblock=" + string(instance_number(obj_npc_susiedark)) + " battle=" + string(instance_exists(obj_battlecontroller)) + " xy=" + (instance_exists(obj_mainchara) ? string(obj_mainchara.x) + "," + string(obj_mainchara.y) : "-") + " gold=" + string(global.gold) + " flag500=" + string(global.flag[500]) + evs);
    }
    // staleplot:<a>:<b>: once the plot reaches <a> (outside battles), set it back to <b>, as the copy
    // of a cutscene that a lagging player still watches does (Chapter 1 castle softlock)
    if (mp_test_has("staleplot") && !variable_global_exists("mp_test_staledone") && variable_global_exists("plot") && !instance_exists(obj_battlecontroller))
    {
        var sa = mp_test_arg("staleplot");
        var sc = string_pos(":", sa);
        if (global.plot == real(string_copy(sa, 1, sc - 1)))
        {
            global.mp_test_staledone = 1;
            global.plot = real(string_delete(sa, 1, sc));
            mp_log("[test] stale plot written: " + string(global.plot));
        }
    }
    // setplot:<n>: move the story on to <n> after a while (another player doing it while I stand in a room)
    if (mp_test_has("setplot") && global.mp_test_timer == 700 && mp_on() && global.mp_test_state == 1)
    {
        global.plot = real(mp_test_arg("setplot"));
        mp_log("[test] plot set to " + string(global.plot));
    }
    // gotohost:<n>: use the "go to the other player" action n frames after the party setup
    if (mp_test_has("gotohost") && global.mp_test_state == 1 && mp_on() && global.mp_test_timer == real(mp_test_arg("gotohost")))
        mp_go_to_player(mp_goto_target());
    // song:<file>: play this song (instead of whatever plays) 20 frames after the party setup
    if (mp_test_has("song") && global.mp_test_state == 1 && global.mp_test_timer == 20 && variable_global_exists("currentsong"))
    {
        if (snd_is_playing(global.currentsong[1]))
            snd_stop(global.currentsong[1]);
        global.currentsong[0] = snd_init(mp_test_arg("song"));
        global.currentsong[1] = mus_loop(global.currentsong[0]);
        mp_log("[test] playing " + mp_test_arg("song"));
    }
    // stuck:<n>: n frames after the party setup, fake a stuck sync state (as after a cutscene that was cut short):
    // watching a cutscene that never ends, character hidden, interact stuck
    if (mp_test_has("stuck") && global.mp_test_state == 1 && mp_on() && global.mp_test_timer == real(mp_test_arg("stuck")) && instance_exists(obj_mainchara))
    {
        global.mp_sstate = 3;
        global.mp_slead = 0;
        global.interact = 1;
        with (obj_mainchara)
            visible = 0;
        mp_log("[test] faked a stuck state");
    }
    // setvars: change a story flag and gold after a while; logvars: report them.
    if (mp_test_has("setvars") && global.mp_test_timer == 400)
    {
        global.flag[500] = 7;
        global.gold += 123;
        show_debug_message("[MPVARS] set flag500=7 gold=" + string(global.gold));
    }
    if (mp_test_has("logvars") && (global.mp_test_timer == 200 || global.mp_test_timer == 700))
        show_debug_message("[MPVARS] t=" + string(global.mp_test_timer) + " flag500=" + string(global.flag[500]) + " xy=" + (instance_exists(obj_mainchara) ? string(obj_mainchara.x) + "," + string(obj_mainchara.y) : "-") + " gold=" + string(global.gold) + " plot=" + string(global.plot));
    var battle_delay = mp_test_arg("battleat") != "" ? real(mp_test_arg("battleat")) : 120;
    if (mp_test_has("battle") && !global.mp_test_battled && instance_exists(obj_mainchara) && global.mp_test_timer > battle_delay && global.interact == 0 && (mp_on() || global.mp_role == 0))
    {
        var other_ready = true;
        if (global.mp_role == 1)
            other_ready = mp_player_count() > 1 && global.mp_proom[1] == room;
        if (other_ready)
        {
            global.mp_test_battled = 1;
            // Fight with the full test party (a room's own cutscene may have changed it).
            global.char[0] = 1;
            global.char[1] = 2;
            global.char[2] = 3;
            // duo: Kris and Susie only (whoever plays Ralsei watches)
            if (mp_test_has("duo"))
                global.char[2] = 0;
            global.encounterno = real(mp_test_arg("battle"));
            mp_notify("[test] starting encounter " + string(global.encounterno));
            mp_battle_force_start();
        }
    }
    if (mp_test_has("numtest") && global.mp_test_timer == 60)
    {
        var bb = buffer_create(8, buffer_fixed, 1);
        buffer_write(bb, buffer_s32, 71);
        buffer_seek(bb, buffer_seek_start, 0);
        var iv = buffer_read(bb, buffer_s32);
        buffer_delete(bb);
        var a = mp_num(iv);
        var r = real(iv);
        show_debug_message("[NUMTEST] raw " + typeof(iv) + " " + string(iv / 90) + " | mp_num " + typeof(a) + " " + string(a / 90) + " " + string(a) + " | real() " + typeof(r) + " " + string(r / 90));
    }
    if (mp_test_has("crashtest") && global.mp_test_timer == 100)
        show_debug_message(real(global.mp_test));
    if (mp_test_has("check") && (global.mp_frame mod 30) == 0)
        mp_test_check();
    if (mp_test_has("check") && (global.mp_frame mod 300) == 150 && variable_global_exists("flag"))
    {
        var fl = "";
        for (var i = 60; i < array_length(global.flag); i++)
        {
            if (global.flag[i] != 0)
                fl += string(i) + "=" + string(global.flag[i]) + ",";
        }
        show_debug_message("[MPFLAGS] t=" + string(current_time) + " hfl=" + string_copy(md5_string_utf8(fl), 1, 8) + " " + fl);
    }
    if (mp_test_has("save") && !variable_global_exists("mp_test_saved") && instance_exists(obj_mainchara) && global.interact == 0 && global.mp_test_timer > 600)
    {
        global.mp_test_saved = 1;
        scr_saveprocess(0);
        show_debug_message("[MPCHK] saved slot 0 room=" + room_get_name(room) + " plot=" + string(global.plot));
    }
    if (mp_test_has("log") && variable_global_exists("mp_b_active") && mp_battle_on() && global.mp_bturn != global.mp_test_lastturn && !global.mp_bwait)
    {
        global.mp_test_lastturn = global.mp_bturn;
        var s = "[MPLOG] turn=" + string(global.mp_bturn) + " tp=" + string(global.tension);
        for (var i = 0; i < 3; i++)
        {
            if (global.char[i] != 0)
                s += " hp" + string(i) + "=" + string(global.hp[global.char[i]]) + "/own" + string(global.mp_owner[i]);
            if (global.monster[i])
                s += " mon" + string(i) + "=" + string(global.monsterhp[i]) + "/mercy" + string(global.mercymod[i]);
        }
        show_debug_message(s);
    }
}

// Bot RNG independent of GameMaker's (which the battle sync seeds deterministically).
function mp_test_rand(n)
{
    if (!variable_global_exists("mp_test_lcg"))
        global.mp_test_lcg = ((global.mp_myid * 7777) + 12345) mod 65537;
    // Small LCG: GML's mod works on 32-bit integers, so keep every product below 2^31.
    global.mp_test_lcg = ((global.mp_test_lcg * 75) + 74) mod 65537;
    return floor((global.mp_test_lcg / 65537) * n) mod n;
}

// Simple input bot used by automated tests. Runs before the multiplayer input logic.
// "bot" mashes Z; "botrand" also picks random menu commands and sometimes backs out.
function mp_test_input()
{
    if (global.mp_test == "")
        return;
    var f = global.mp_frame;
    // mashevery:<n> presses every n frames instead of 10 (a slow reader), mashfrom:<n> starts n frames into the room.
    var mash_every = mp_test_arg("mashevery") != "" ? real(mp_test_arg("mashevery")) : 10;
    var mash_from = mp_test_arg("mashfrom") != "" ? real(mp_test_arg("mashfrom")) : 15;
    if (mp_test_has("mash") && !global.mp_ui_open && string_pos("PLACE_", room_get_name(room)) != 1 && !instance_exists(obj_battlecontroller) && (f mod mash_every) == 0 && global.mp_room_frames > mash_from && (!instance_exists(obj_mainchara) || global.interact == 1))
    {
        // Dialogue choices need a direction first.
        if (instance_exists(obj_choicer_neo) && (f mod 20) == 0)
        {
            global.input_held[3] = 1;
            global.input_pressed[3] = 1;
        }
        else
            global.input_pressed[4] = 1;
    }
    if (mp_test_has("wander") && !instance_exists(obj_battlecontroller) && (instance_exists(obj_mainchara) || mp_plat_on()) && global.interact == 0 && variable_global_exists("mp_test_timer") && global.mp_test_timer > 200)
    {
        if (!variable_global_exists("mp_test_wdir") || (f mod 45) == 0)
            global.mp_test_wdir = mp_test_rand(6);
        if (global.mp_test_wdir < 4)
            global.input_held[global.mp_test_wdir] = 1;
        // Platforming: jump now and then (X).
        if (mp_plat_on() && (f mod 40) == 0 && mp_test_rand(2) == 0)
        {
            global.input_pressed[5] = 1;
            global.input_held[5] = 1;
        }
    }
    // fakescene: while being pulled into a battle, start a cutscene of our own (an object with a
    // cutscene master, like every story cutscene), once - the thing mp_kill_scenes must stop.
    if (mp_test_has("fakescene") && global.mp_battle_pulled && !mp_in_battle_scene() && !variable_global_exists("mp_fake_done") && asset_get_index("obj_marker") >= 0 && asset_get_index("scr_cutscene_make") >= 0)
    {
        global.mp_fake_done = 1;
        var fo = instance_create(0, 0, asset_get_index("obj_marker"));
        fo.cutscene_master = script_execute(asset_get_index("scr_cutscene_make"));
        with (fo)
            script_execute(asset_get_index("c_wait"), 600);
        global.interact = 1;
        mp_log("fakescene created, master " + string(fo.cutscene_master) + " exists " + string(mp_cutscene_master_exists()));
    }
    if (mp_test_has("away") && variable_global_exists("mp_test_state") && mp_on() && global.mp_test_state == 1 && !variable_global_exists("mp_test_awaydone") && global.interact == 0 && instance_exists(obj_mainchara))
    {
        // away:<room>:<n>[:<x>:<y>]
        var aw = mp_test_arg("away");
        var ap = string_pos(":", aw);
        var ar = string_delete(aw, 1, ap);
        var ap2 = string_pos(":", ar);
        var an = ap2 > 0 ? real(string_copy(ar, 1, ap2 - 1)) : real(ar);
        var ax = 300;
        var ay = 300;
        if (ap2 > 0)
        {
            var axy = string_delete(ar, 1, ap2);
            var ap3 = string_pos(":", axy);
            ax = real(string_copy(axy, 1, ap3 - 1));
            ay = real(string_delete(axy, 1, ap3));
        }
        if (global.mp_test_timer >= an)
        {
            global.mp_test_awaydone = 1;
            mp_warp(asset_get_index(string_copy(aw, 1, ap - 1)), ax, ay, 0);
        }
    }
    if (mp_test_has("walk") && instance_exists(obj_mainchara) && variable_global_exists("mp_test_timer"))
    {
        var wa = mp_test_arg("walk");
        var p1 = string_pos(":", wa);
        var wd = string_copy(wa, 1, p1 - 1);
        var wr = string_delete(wa, 1, p1);
        var p2 = string_pos(":", wr);
        var wt = real(string_copy(wr, 1, p2 - 1));
        var wn = real(string_delete(wr, 1, p2));
        if (global.mp_test_state == 1 && global.mp_test_timer >= wt && global.mp_test_timer < wt + wn && global.interact == 0)
        {
            var di = 0;
            if (wd == "r")
                di = 1;
            if (wd == "u")
                di = 2;
            if (wd == "l")
                di = 3;
            global.input_held[di] = 1;
        }
    }
    if (!mp_test_has("bot"))
        return;
    if (instance_exists(obj_battlecontroller))
    {
        if (global.mnfight == 2 && instance_exists(obj_heart))
        {
            // nododge: stand still and take the hits (to test downed players and Game Over)
            if (!mp_test_has("nododge"))
            {
                var d = floor(f / 20) mod 4;
                global.input_held[d] = 1;
            }
            return;
        }
        if ((f mod 6) == 0)
        {
            var menu = global.myfight == 0 && global.mnfight == 0;
            if (menu && mp_test_has("botrand"))
            {
                var r = mp_test_rand(10);
                if (r < 3)
                    global.input_pressed[1] = 1;      // right
                else if (r < 4)
                    global.input_pressed[0] = 1;      // down
                else if (r < 5)
                    global.input_pressed[5] = 1;      // X (back)
                else
                    global.input_pressed[4] = 1;      // Z
            }
            else
            {
                global.input_pressed[4] = 1;
            }
        }
        return;
    }
    if (global.interact != 0 && (f mod 8) == 0)
        global.input_pressed[4] = 1;
    // walkto:<x>:<y> walks the player there once the other player is in the room.
    if (mp_test_has("walkto") && global.interact == 0 && instance_exists(obj_mainchara) && variable_global_exists("mp_test_posdone") && global.mp_test_timer > 300)
    {
        var wv = mp_test_arg("walkto");
        var c = string_pos(":", wv);
        var tx = real(string_copy(wv, 1, c - 1));
        var ty = real(string_delete(wv, 1, c));
        if (obj_mainchara.x < tx - 2)
            global.input_held[1] = 1;
        else if (obj_mainchara.x > tx + 2)
            global.input_held[3] = 1;
        if (obj_mainchara.y < ty - 2)
            global.input_held[0] = 1;
        else if (obj_mainchara.y > ty + 2)
            global.input_held[2] = 1;
    }
}

function mp_log(s)
{
    if (global.mp_test != "" && mp_test_has("log"))
        show_debug_message("[MPD f=" + string(global.mp_frame) + " t=" + string(current_time) + "] " + s);
}

function mp_test_battle_created()
{
    if (global.mp_test != "" && mp_test_has("weak"))
    {
        // weak: enemies have 1 HP, so the fight ends after the first hits (tests what comes after a battle).
        for (var j = 0; j < 3; j++)
        {
            global.monsterhp[j] = min(global.monsterhp[j], 1);
            global.monstermaxhp[j] = min(global.monstermaxhp[j], 1);
        }
        return;
    }
    if (global.mp_test == "" || !mp_test_has("tough"))
        return;
    for (var i = 0; i < 3; i++)
    {
        global.monsterhp[i] *= 8;
        global.monstermaxhp[i] *= 8;
    }
}

function mp_ch_test_party()
{
    for (var c = 1; c <= 3; c++)
        global.hp[c] = global.maxhp[c];
}

// One self-check line (see tools/mpcheck.py).
function mp_test_check()
{
    var mx = -1;
    var my = -1;
    var vis = 0;
    if (instance_exists(obj_mainchara))
    {
        mx = obj_mainchara.x;
        my = obj_mainchara.y;
        vis = obj_mainchara.visible && (global.mp_frame - global.mp_my_drawn) < 3;
    }
    var s = "[MPCHK] t=" + string(current_time) + " wc=" + string_format(global.mp_test_ws - ((global.mp_test_wb - current_time) / 1000), 1, 3) + " f=" + string(global.mp_frame) + " id=" + string(global.mp_myid);
    s += " on=" + string(mp_on()) + " want=" + string(global.mp_cfg_char);
    s += " room=" + room_get_name(room) + " x=" + string(round(mx)) + " y=" + string(round(my));
    var ddx = global.mp_my_x;
    var ddy = global.mp_my_y;
    var dspr = global.mp_my_spr;
    var bi = mp_board_send_info();
    if (is_array(bi))
    {
        // On the Chapter 3 board: my piece, in whole-board coordinates.
        ddx = bi[0];
        ddy = bi[1];
        dspr = bi[2];
        vis = bi[6];
        var tl0 = layer_get_id("BOARD_Tiles");
        s += " bvx=" + string(round(128 - layer_get_x(tl0))) + " bvy=" + string(round(64 - layer_get_y(tl0)));
    }
    var pli = mp_plat_send_info();
    if (is_array(pli))
    {
        // In a Chapter 5 platforming section: my platformer figure.
        ddx = pli[0];
        ddy = pli[1];
        dspr = pli[2];
        vis = pli[6];
    }
    s += " plat=" + string(mp_plat_on());
    s += " dx=" + string(round(ddx)) + " dy=" + string(round(ddy)) + " vis=" + string(vis);
    s += " drawn=" + string(mp_test_sprite_char(dspr)) + " spr=" + sprite_get_name(dspr) + " board=" + string(mp_board_on());
    s += " sst=" + string(global.mp_sstate) + " ia=" + string(global.interact) + " bat=" + string(mp_in_battle_scene()) + " dlg=" + string(global.mp_local_dlg) + " dz=" + string(mp_dz()) + " rf=" + string(global.mp_room_frames) + " hpv=" + string(global.hp[1]) + "/" + string(global.hp[2]) + "/" + string(global.hp[3]) + " cct=" + string(global.charcantarget[0]) + string(global.charcantarget[1]) + string(global.charcantarget[2]) + " ch=" + string(global.char[0]) + string(global.char[1]) + string(global.char[2]);
    s += " fol=" + string(global.mp_fol_last);
    var gs = "";
    for (var i = 0; i < 8; i++)
    {
        if (i == global.mp_myid || !global.mp_pconn[i])
            continue;
        gs += string(i) + ":" + string(global.mp_pchar[i]) + ":" + string(global.mp_proom[i]) + ":" + string(global.mp_px[i]) + ":" + string(global.mp_py[i]);
        var g = global.mp_pghost[i];
        if (instance_exists(g))
        {
            var gx = g.x;
            var gy = g.y;
            if (mp_board_on())
            {
                var tl = layer_get_id("BOARD_Tiles");
                gx -= layer_get_x(tl);
                gy -= layer_get_y(tl);
            }
            gs += ":G" + string(round(gx)) + ":" + string(round(gy));
        }
        gs += ";";
    }
    s += " peers=" + gs + " " + mp_test_hash();
    show_debug_message(s);
}

// Hash of the shared story state, split in parts so a mismatch shows what differs.
function mp_test_hash()
{
    var fl = "";
    var n = array_length(global.flag);
    for (var i = 60; i < n; i++)
    {
        if (global.flag[i] != 0)
            fl += string(i) + "=" + string(global.flag[i]) + ",";
    }
    var it = "";
    for (var j = 0; j < array_length(global.item); j++)
        it += string(global.item[j]) + ",";
    for (var j = 0; j < array_length(global.keyitem); j++)
        it += string(global.keyitem[j]) + ",";
    for (var j = 0; j < array_length(global.weapon); j++)
        it += string(global.weapon[j]) + ",";
    for (var j = 0; j < array_length(global.armor); j++)
        it += string(global.armor[j]) + ",";
    var hp = "";
    for (var j = 0; j < array_length(global.hp); j++)
        hp += string(global.hp[j]) + "/" + string(global.maxhp[j]) + ",";
    var party = string(global.char[0]) + string(global.char[1]) + string(global.char[2]);
    global.mp_tmp_mus = "none";
    if (variable_global_exists("currentsong") && is_array(global.currentsong) && audio_is_playing(global.currentsong[1]))
    {
        with (obj_astream)
        {
            if (variable_instance_exists(id, "songname") && variable_instance_exists(id, "mystream") && mystream == global.currentsong[0])
                global.mp_tmp_mus = songname;
        }
    }
    var mus = global.mp_tmp_mus;
    return "mus=" + mus + " nact=" + string(asset_get_index("obj_actor") >= 0 ? instance_number(asset_get_index("obj_actor")) : 0) + " plot=" + string(global.plot) + " xy=" + (instance_exists(obj_mainchara) ? string(obj_mainchara.x) + "," + string(obj_mainchara.y) : "-") + " gold=" + string(global.gold) + " party=" + party + " hfl=" + string_copy(md5_string_utf8(fl), 1, 8) + " hit=" + string_copy(md5_string_utf8(it), 1, 8) + " hhp=" + string_copy(md5_string_utf8(hp), 1, 8);
}

// Character a (field or board) sprite belongs to.
function mp_test_sprite_char(spr)
{
    if (!sprite_exists(spr))
        return 0;
    var n = sprite_get_name(spr);
    if (string_pos("spr_board_", n) == 1)
        n = "spr_" + string_delete(n, 1, 10);
    if (string_pos("spr_kris", n) == 1)
        return 1;
    if (string_pos("spr_susie", n) == 1)
        return 2;
    if (string_pos("spr_ralsei", n) == 1)
        return 3;
    if (string_pos("spr_noelle", n) == 1)
        return 4;
    return 0;
}
