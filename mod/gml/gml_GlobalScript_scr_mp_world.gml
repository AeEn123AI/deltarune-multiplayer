// DELTARUNE Multiplayer - overworld: positions, ghosts, character sprites, shared story state.

function mp_world_init()
{
    global.mp_swapcache = ds_map_create();
    global.mp_pos_force = 0;
    global.mp_pos_last = "";
    global.mp_pos_time = 0;
    global.mp_my_spr = -1;
    global.mp_my_img = 0;
    global.mp_my_x = 0;
    global.mp_my_y = 0;
    global.mp_my_xs = 1;
    global.mp_my_ys = 1;
    global.mp_my_drawn = 0;
    global.mp_need_warp = 0;
    global.mp_warp_delay = 0;
    global.mp_fol_mask = 0;     // party followers drawn this frame, by the character shown
    global.mp_fol_last = 0;
    mp_vars_init();
}

// ---------------------------------------------------------------- sprite swapping

function mp_sprite_char(spr)
{
    if (!sprite_exists(spr))
        return 0;
    var n = sprite_get_name(spr);
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

function mp_try_sprite(name)
{
    var s = asset_get_index(name);
    if (s >= 0 && asset_get_type(name) == asset_sprite)
        return s;
    return -1;
}

// Facing direction ("d", "l", "r", "u" or "") of a party member's walking sprite.
function mp_sprite_dir(n, fromc)
{
    // Named walk sprites (Noelle's, and special ones like spr_kris_walk_left_church).
    if (string_pos("_walk_down", n) > 0)
        return "d";
    if (string_pos("_walk_left", n) > 0)
        return "l";
    if (string_pos("_walk_right", n) > 0)
        return "r";
    if (string_pos("_walk_up", n) > 0)
        return "u";
    if (fromc == 4)
        return "";
    var c = string_char_at(string_delete(n, 1, string_length("spr_" + mp_char_prefix(fromc))), 1);
    if (c == "d" || c == "l" || c == "r" || c == "u")
        return c;
    // Other walking variants: spr_kris_walkd_hold, spr_kris_walk_bow_right_can, ...
    var w = string_pos("_walk", n);
    if (w > 0)
    {
        var rest = string_delete(n, 1, w + 4);
        var c2 = string_char_at(rest, 1);
        if (c2 == "d" || c2 == "l" || c2 == "r" || c2 == "u")
            return c2;
        if (string_pos("_left", rest) > 0)
            return "l";
        if (string_pos("_right", rest) > 0)
            return "r";
        if (string_pos("_down", rest) > 0)
            return "d";
        if (string_pos("_up", rest) > 0)
            return "u";
    }
    return "";
}

// Plain walking sprite of character toc facing dirc, for the current world (dark/light).
function mp_walk_sprite(toc, dirc)
{
    var found = -1;
    if (toc == 4)
    {
        var w = "down";
        if (dirc == "l")
            w = "left";
        if (dirc == "r")
            w = "right";
        if (dirc == "u")
            w = "up";
        if (global.darkzone)
            found = mp_try_sprite("spr_noelle_walk_" + w + "_dw");
        if (found < 0)
            found = mp_try_sprite("spr_noelle_walk_" + w + "_lw");
        if (found < 0)
            found = mp_try_sprite("spr_noelle_walk_" + w + "_dw");
        return found;
    }
    var tp = "spr_" + mp_char_prefix(toc);
    if (global.darkzone)
        found = mp_try_sprite(tp + dirc + "_dark");
    if (found < 0)
        found = mp_try_sprite(tp + dirc);
    if (found < 0)
        found = mp_try_sprite(tp + dirc + "_dark");
    return found;
}

// Maps a sprite of one party member onto the equivalent sprite of another
// (e.g. spr_krisr_dark -> spr_susier_dark, spr_noelle_walk_up_dw). Falls back to the
// plain walking sprite in the same direction, then to the original sprite.
function mp_swap_sprite(spr, fromc, toc)
{
    if (fromc == toc || fromc == 0 || !sprite_exists(spr))
        return spr;
    var key = (spr * 8) + toc;
    if (ds_map_exists(global.mp_swapcache, key))
        return ds_map_find_value(global.mp_swapcache, key);
    var res = spr;
    var n = sprite_get_name(spr);
    var fp = "spr_" + mp_char_prefix(fromc);
    var tp = "spr_" + mp_char_prefix(toc);
    var found = -1;
    if (string_pos(fp, n) == 1)
    {
        if (fromc != 4 && toc != 4)
        {
            var rest = string_delete(n, 1, string_length(fp));
            found = mp_try_sprite(tp + rest);
            if (found < 0 && string_pos("_dark", rest) > 0)
                found = mp_try_sprite(tp + string_replace(rest, "_dark", ""));
            if (found < 0 && string_pos("_dark", rest) == 0)
                found = mp_try_sprite(tp + rest + "_dark");
        }
        var dirc = mp_sprite_dir(n, fromc);
        if (found < 0 && dirc != "")
            found = mp_walk_sprite(toc, dirc);
        if (found >= 0)
            res = found;
    }
    ds_map_set(global.mp_swapcache, key, res);
    return res;
}

// Draws an instance with its sprite swapped to another character, feet-aligned.
function mp_draw_swapped(spr, img, xx, yy, xs, ys, col, alpha, record)
{
    var o = sprite_index;
    var ox = xx + (xs * ((sprite_get_width(o) / 2) - sprite_get_xoffset(o)));
    var oy = yy + (ys * (sprite_get_height(o) - sprite_get_yoffset(o)));
    var dx = ox - (xs * ((sprite_get_width(spr) / 2) - sprite_get_xoffset(spr)));
    var dy = oy - (ys * (sprite_get_height(spr) - sprite_get_yoffset(spr)));
    var fr = img;
    var nf = sprite_get_number(spr);
    if (nf > 0)
        fr = floor(img) mod nf;
    draw_sprite_ext(spr, fr, dx, dy, xs, ys, 0, col, alpha);
    if (record)
    {
        global.mp_my_spr = spr;
        global.mp_my_img = fr;
        global.mp_my_x = dx;
        global.mp_my_y = dy;
        global.mp_my_xs = xs;
        global.mp_my_ys = ys;
        global.mp_my_drawn = global.mp_frame;
    }
}

// Replaces draw_self() in obj_mainchara's Draw event. xoff: horizontal shake offset some
// chapters add (Chapter 4 draws Kris with draw_sprite_ext(..., x + tower_shake_xoffset, ...)).
function mp_draw_mainchara(xoff)
{
    if (!variable_global_exists("mp_inited"))
    {
        draw_sprite_ext(sprite_index, image_index, x + xoff, y, image_xscale, image_yscale, image_angle, image_blend, image_alpha);
        return;
    }
    var spr = sprite_index;
    if (mp_on() && mp_swaps_enabled())
    {
        var me = global.mp_cfg_char;
        var src = mp_sprite_char(sprite_index);
        if (src == 1 && me != 1)
            spr = mp_swap_sprite(sprite_index, 1, me);
    }
    mp_draw_swapped(spr, image_index, x + xoff, y, image_xscale, image_yscale, image_blend, image_alpha, true);
}

// Draw event for party followers.
function mp_draw_caterpillar()
{
    if (!variable_global_exists("mp_inited") || !mp_on() || !mp_swaps_enabled())
    {
        draw_self();
        return;
    }
    var c = mp_sprite_char(sprite_index);
    if (c == 0)
    {
        draw_self();
        return;
    }
    if (!visible || image_alpha <= 0)
        return;
    // The follower that matches my character stands in for Kris (I am walking in front).
    var shown = c;
    if (c == global.mp_cfg_char)
        shown = 1;
    // A party member someone else is playing never also follows me as an NPC: that player
    // walks around by themselves (drawn as a name-tagged character when in this room).
    if (mp_char_player_other(shown) >= 0)
        return;
    global.mp_fol_mask |= 1 << shown;
    if (shown == c)
    {
        draw_self();
        return;
    }
    mp_draw_swapped(mp_swap_sprite(sprite_index, c, shown), image_index, x, y, image_xscale, image_yscale, image_blend, image_alpha, false);
}

// Sprite swaps apply outside shared story cutscenes and battles: walking around, talking to
// people, reading signs, doors, and anything that only happens in my own game. Shared
// cutscenes show the real party (their scripts move and animate it).
function mp_swaps_enabled()
{
    // (On the Chapter 3 board the party sits on the couch; the board pieces are swapped.)
    return global.mp_sstate != 1 && global.mp_sstate != 2 && !mp_in_battle_scene() && !mp_board_on();
}

// Returns the id of another connected player playing character c, or -1.
function mp_char_player_other(c)
{
    for (var i = 0; i < 8; i++)
    {
        if (i != global.mp_myid && global.mp_pconn[i] && global.mp_pchar[i] == c)
            return i;
    }
    return -1;
}

// First character (starting after c, in direction d) nobody else plays; c itself if all are taken.
function mp_char_free_from(c, d)
{
    var n = mp_char_max();
    var k = c;
    for (var i = 0; i < n; i++)
    {
        k = ((k - 1 + d + n) mod n) + 1;
        if (mp_char_player_other(k) < 0)
            return k;
    }
    return c;
}

// Two players can't play the same character: the one who joined later changes.
function mp_char_conflict_tick()
{
    if ((global.mp_frame mod 30) != 0)
        return;
    var o = mp_char_player_other(global.mp_cfg_char);
    if (o < 0 || o > global.mp_myid)
        return;
    var nc = mp_char_free_from(global.mp_cfg_char, 1);
    if (nc == global.mp_cfg_char)
        return;
    global.mp_cfg_char = nc;
    global.mp_pchar[global.mp_myid] = nc;
    mp_config_save();
    mp_send_pinfo(global.mp_myid);
    mp_notify(global.mp_pname[o] + " already plays that character: you are now " + mp_char_name(nc) + ".");
}

// Who the "go to" hotkey / menu entry takes me to: the host, or (for the host) the first other player.
function mp_goto_target()
{
    if (global.mp_role == 2)
        return 0;
    for (var i = 0; i < 8; i++)
    {
        if (i != global.mp_myid && global.mp_pconn[i])
            return i;
    }
    return -1;
}

// Moves me to where player pid is (unsticks a player from a puzzle or a broken room).
function mp_go_to_player(pid)
{
    var forced = false;
    if (!mp_on() || pid < 0 || pid == global.mp_myid || !global.mp_pconn[pid])
        return;
    if (global.mp_sstate != 0 || mp_in_battle_scene() || global.mp_warp_pending || global.mp_warp_delay > 0 || is_array(global.mp_pull) || !instance_exists(obj_mainchara) || mp_credits_running())
    {
        // Pressed again within 5 seconds: assume I am stuck and release the stuck state.
        if ((current_time - global.mp_goto_blocked) < 5000 && !mp_credits_running() && mp_unstick())
        {
            mp_notify("Released a stuck state.");
            global.mp_goto_blocked = -99999;
            forced = true;
        }
        else
        {
            global.mp_goto_blocked = current_time;
            mp_notify("Can't go there right now (press F8 again to force).");
            return;
        }
    }
    if (global.mp_proom[pid] < 0 || !room_exists(global.mp_proom[pid]))
        return;
    global.mp_warp_reenter = mp_dz_take((global.mp_pstate[pid] & 64) != 0 ? 1 : 0) || forced;
    global.mp_warp_mus = pid;
    if ((global.mp_pstate[pid] & 48) != 0)
        mp_warp(global.mp_proom[pid], -99999, 0, 0);
    else
        mp_warp(global.mp_proom[pid], global.mp_pix[pid], global.mp_piy[pid], 0);
    mp_notify("Going to " + global.mp_pname[pid] + ".");
}

// ---------------------------------------------------------------- positions

// 1 in the Dark World, 0 in the Light World (Chapter 1 and others may lack the variable).
function mp_dz()
{
    if (variable_global_exists("darkzone") && global.darkzone)
        return 1;
    return 0;
}

// Takes the sender's Light/Dark World state; true when that changes ours (the room must then
// be entered again so followers, sprites and room objects are made for the right world).
function mp_dz_take(dz)
{
    if (!variable_global_exists("darkzone") || mp_dz() == dz)
        return false;
    global.darkzone = dz;
    return true;
}

function mp_state_bits()
{
    var s = 0;
    if (mp_in_battle_scene())
        s |= 1;
    if (global.mp_sstate != 0)
        s |= 2;
    if (global.interact != 0)
        s |= 4;
    if (global.mp_ui_open)
        s |= 8;
    if (mp_board_on())
        s |= 16;
    if (mp_plat_on())
        s |= 32;
    if (mp_dz())
        s |= 64;
    return s;
}

function mp_send_pos(force, sock)
{
    var vis = 0;
    if (instance_exists(obj_mainchara) && (global.mp_frame - global.mp_my_drawn) < 3 && obj_mainchara.visible)
        vis = 1;
    var px = global.mp_my_x;
    var py = global.mp_my_y;
    var pspr = global.mp_my_spr;
    var pimg = global.mp_my_img;
    var pxs = global.mp_my_xs;
    var pys = global.mp_my_ys;
    // On the Chapter 3 board, my board piece is what the others see.
    var bi = mp_board_send_info();
    if (is_array(bi))
    {
        px = bi[0];
        py = bi[1];
        pspr = bi[2];
        pimg = bi[3];
        pxs = bi[4];
        pys = bi[5];
        vis = bi[6];
    }
    // In a Chapter 5 platforming section, my platformer figure.
    var plinfo = mp_plat_send_info();
    if (is_array(plinfo))
    {
        px = plinfo[0];
        py = plinfo[1];
        pspr = plinfo[2];
        pimg = plinfo[3];
        pxs = plinfo[4];
        pys = plinfo[5];
        vis = plinfo[6];
    }
    var sig = string(room) + "," + string(round(px)) + "," + string(round(py)) + "," + string(pspr) + "," + string(pimg) + "," + string(vis) + "," + string(mp_state_bits());
    if (!force && sig == global.mp_pos_last && (current_time - global.mp_pos_time) < 1500)
        return;
    global.mp_pos_last = sig;
    global.mp_pos_time = current_time;
    mp_begin(10);
    mp_wu16(room);
    mp_ws16(px);
    mp_ws16(py);
    mp_ws16(pspr);
    mp_wu8(pimg);
    mp_ws8(pxs * 10);
    mp_ws8(pys * 10);
    mp_wu8(vis);
    mp_wu8(mp_state_bits());
    // The character's own position (px/py above are where its sprite is drawn).
    var ix = 0;
    var iy = 0;
    if (instance_exists(obj_mainchara))
    {
        ix = obj_mainchara.x;
        iy = obj_mainchara.y;
    }
    mp_ws16(ix);
    mp_ws16(iy);
    if (is_struct(sock))
        mp_send_unreliable_to(sock);
    else
        mp_send();
}

function mp_recv_pos(pid, b)
{
    if (pid == global.mp_myid)
        return;
    var oldroom = global.mp_proom[pid];
    global.mp_proom[pid] = buffer_read(b, buffer_u16);
    global.mp_px[pid] = buffer_read(b, buffer_s16);
    global.mp_py[pid] = buffer_read(b, buffer_s16);
    global.mp_pspr[pid] = buffer_read(b, buffer_s16);
    global.mp_pimg[pid] = buffer_read(b, buffer_u8);
    global.mp_pxs[pid] = buffer_read(b, buffer_s8) / 10;
    global.mp_pys[pid] = buffer_read(b, buffer_s8) / 10;
    global.mp_pvis[pid] = buffer_read(b, buffer_u8);
    global.mp_pstate[pid] = buffer_read(b, buffer_u8);
    global.mp_pix[pid] = buffer_read(b, buffer_s16);
    global.mp_piy[pid] = buffer_read(b, buffer_s16);
    global.mp_ppostime[pid] = current_time;
    if (oldroom != global.mp_proom[pid])
    {
        var g = global.mp_pghost[pid];
        if (instance_exists(g))
            g.snap = 1;
    }
    // A freshly joined client starts next to the host.
    if (pid == 0 && global.mp_need_warp && global.mp_pvis[0])
    {
        global.mp_need_warp = 0;
        if (instance_exists(obj_mainchara) && global.mp_sstate == 0 && !mp_in_battle_scene())
        {
            // (On the Chapter 3 board the host's position is its board piece's: just go
            // to the room and sit down where the game puts us.)
            global.mp_warp_reenter = mp_dz_take((global.mp_pstate[0] & 64) != 0 ? 1 : 0);
            if ((global.mp_pstate[0] & 48) != 0)
            {
                global.mp_warp_mus = 0;
                mp_warp(global.mp_proom[0], -99999, 0, 0);
            }
            else
            {
                global.mp_warp_mus = 0;
                mp_warp(global.mp_proom[0], global.mp_pix[0], global.mp_piy[0], 0);
            }
        }
    }
}

// ---------------------------------------------------------------- ghosts

function mp_ghost_remove(pid)
{
    var g = global.mp_pghost[pid];
    if (instance_exists(g))
    {
        with (g)
            instance_destroy();
    }
    global.mp_pghost[pid] = -4;
}

function mp_ghosts_clear()
{
    with (obj_mp_ghost)
        instance_destroy();
    for (var i = 0; i < 8; i++)
        global.mp_pghost[i] = -4;
}

// Creates / removes the ghost instances that show other players walking around.
function mp_ghosts_update()
{
    var plat = mp_plat_on();
    var showall = global.mp_sstate == 0 && !mp_in_battle_scene() && (instance_exists(obj_mainchara) || plat);
    var board = mp_board_on();
    for (var i = 0; i < 8; i++)
    {
        var want = showall && i != global.mp_myid && global.mp_pconn[i] && global.mp_proom[i] == room && global.mp_pvis[i] && (global.mp_pstate[i] & 3) == 0 && sprite_exists(global.mp_pspr[i]);
        // Board pieces only show on the board, and only on the board screen I'm looking at.
        if (want && (((global.mp_pstate[i] & 16) != 0) != board))
            want = false;
        if (want && board && !is_array(mp_board_ghost_xy(i)))
            want = false;
        // Platformer figures only show in platforming sections, and the walking party only outside them.
        if (want && (((global.mp_pstate[i] & 32) != 0) != plat))
            want = false;
        var g = global.mp_pghost[i];
        if (want && !instance_exists(g))
        {
            g = instance_create_depth(global.mp_px[i], global.mp_py[i], 0, obj_mp_ghost);
            g.pid = i;
            global.mp_pghost[i] = g;
        }
        else if (!want && instance_exists(g))
        {
            mp_ghost_remove(i);
        }
    }
}

// ---------------------------------------------------------------- per-frame world logic

function mp_world_tick()
{
    if (global.mp_battle_pulled && !mp_in_battle_scene())
        mp_kill_scenes();
    if (global.mp_warp_delay > 0)
    {
        global.mp_warp_delay -= 1;
        if (global.mp_warp_delay == 0)
            mp_warp_place();
    }
    if ((global.mp_frame mod 3) == 0 || global.mp_pos_force)
    {
        mp_send_pos(global.mp_pos_force, -1);
        global.mp_pos_force = 0;
    }
    if (global.interact == 0 && button1_p() && instance_exists(obj_mainchara))
        global.mp_lastz = global.mp_frame;
    mp_vars_tick();
    mp_postbattle_tick();
    if (global.mp_goto_timer > 0)
    {
        global.mp_goto_timer -= 1;
        if (global.mp_goto_timer == 0)
            mp_go_to_player(0);
    }
    mp_room_refresh_tick();
    mp_char_conflict_tick();
    mp_music_tick();
}

// Moves the local player to (rm, xx, yy). action: 0 none, 1 start pulled battle.
function mp_warp(rm, xx, yy, action)
{
    global.mp_warp_x = xx;
    global.mp_warp_y = yy;
    global.mp_warp_action = action;
    var reenter = global.mp_warp_reenter;
    global.mp_warp_reenter = 0;
    if ((room != rm || reenter) && room_exists(rm))
    {
        global.mp_warp_pending = 1;
        global.mp_warp_room = rm;
        global.interact = 3;
        // We place the player ourselves (mp_warp_place). A door's entrance number left over
        // from the last room would make obj_mainchara look for that room's entry marker,
        // which the target room may not have (Chapter 1 crashes on a missing obj_markerC).
        global.entrance = 0;
        if (room == rm)
            room_restart();
        else
            room_goto(rm);
    }
    else
    {
        global.mp_warp_pending = 0;
        mp_warp_place();
    }
}

function mp_warp_place()
{
    // x = -99999: change room only, keep the position the game gave us.
    if (global.mp_warp_x == -99999)
    {
        var act0 = global.mp_warp_action;
        global.mp_warp_action = 0;
        if (global.interact == 3)
            global.interact = 0;
        mp_music_follow(global.mp_warp_mus);
        global.mp_warp_mus = -1;
        if (act0 == 2)
            mp_sync_arrived();
        return;
    }
    with (obj_mainchara)
    {
        x = global.mp_warp_x;
        y = global.mp_warp_y;
    }
    // (On the Chapter 3 board the party sits still on the couch.)
    with (obj_caterpillarchara)
    {
        if (instance_exists(obj_mainchara) && !mp_board_on())
        {
            x = obj_mainchara.x;
            y = obj_mainchara.y;
            scr_caterpillar_interpolate();
        }
    }
    mp_music_follow(global.mp_warp_mus);
    global.mp_warp_mus = -1;
    global.mp_fade = 1;
    var act = global.mp_warp_action;
    global.mp_warp_action = 0;
    if (global.interact == 3)
        global.interact = 0;
    if (act == 1)
    {
        mp_kill_scenes();
        mp_battle_force_start();
    }
    if (act == 2)
        mp_sync_arrived();
}

// Joining someone's battle: the room's own story scene (which may be what started their
// battle) must not start here too - it would play its dialogue over the battle, and start a
// second battle inside it. Their scene is the one that counts; we get its results via shared state.
// Every cutscene in the game is an object that calls scr_cutscene_make() and keeps the result in
// its own `cutscene_master` variable, so (whatever the object is called, in any chapter) any
// object with a cutscene master, and the masters themselves, go. Objects that haven't started yet
// are caught on the frame they start (this runs every frame until the battle exists); chapter 2
// style `obj_*scene*` / chapter 1 style `obj_*event` controllers are removed up front.
function mp_kill_scenes()
{
    if (mp_test_has("nokill"))
        return;
    with (all)
    {
        var nm = object_get_name(object_index);
        if (variable_instance_exists(id, "cutscene_master"))
        {
            var m = cutscene_master;
            if (m != noone && instance_exists(m))
            {
                with (m)
                    instance_destroy();
            }
            if (string_pos("obj_mp_", nm) != 1)
            {
                global.mp_scenes_killed = 1;
                instance_destroy();
            }
        }
        else if (string_pos("obj_", nm) == 1 && (string_pos("scene", nm) > 0 || string_pos("event", nm) > 0) && string_pos("obj_mp_", nm) != 1)
        {
            global.mp_scenes_killed = 1;
            instance_destroy();
        }
    }
    var cm = asset_get_index("obj_cutscene_master");
    if (cm >= 0)
    {
        with (cm)
            instance_destroy();
    }
}

// After a battle I was pulled into with my own cutscene cut short (mp_kill_scenes): the scene
// may have left my character hidden, the party replaced by markers and interact stuck. Once the
// others' story changes have arrived, put the character back and enter the room again at the same
// spot so it is built from the shared story state.
function mp_postbattle_tick()
{
    if (global.mp_postbattle <= 0)
        return;
    global.mp_postbattle -= 1;
    if (global.mp_postbattle > 0)
        return;
    if (mp_in_battle_scene() || global.mp_sstate != 0 || global.mp_warp_pending || global.mp_warp_delay > 0 || is_array(global.mp_pull) || !instance_exists(obj_mainchara) || mp_credits_running())
    {
        global.mp_postbattle = 30; // not yet
        return;
    }
    mp_vars_apply_queue();
    with (obj_mainchara)
        visible = 1;
    if (global.interact != 0 && !instance_exists(obj_writer) && !instance_exists(obj_dialoguer) && !mp_cutscene_running())
        global.interact = 0;
    mp_log("rebuilding the room after a battle that cut my scene short");
    global.mp_warp_reenter = 1;
    mp_warp(room, obj_mainchara.x, obj_mainchara.y, 0);
}

// Frees a stuck sync state (a cutscene or battle join that never finished): used by F8 when
// pressed twice. Never while a battle is actually on screen.
function mp_unstick()
{
    if (instance_exists(obj_battlecontroller))
        return false;
    mp_close_local_dialogue();
    global.mp_sstate = 0;
    global.mp_slead = -1;
    global.mp_pull = -1;
    global.mp_classify = 0;
    global.mp_battle_pulled = 0;
    global.mp_warp_pending = 0;
    global.mp_warp_delay = 0;
    global.mp_postbattle = 0;
    mp_kill_scenes();
    if (instance_exists(obj_mainchara))
    {
        with (obj_mainchara)
            visible = 1;
    }
    if (global.interact != 0)
        global.interact = 0;
    return true;
}

// obj_mp_controller Room Start.
function mp_room_start()
{
    if (!variable_global_exists("mp_inited"))
        return;
    mp_ghosts_clear();
    global.mp_pos_force = 1;
    global.mp_room_frames = 0;
    global.mp_room_calm = 0;
    global.mp_room_plot = variable_global_exists("plot") ? global.plot : 0;
    // The mod's warp keeps interact at 3 for a few frames; objects that read variables the
    // player object only sets while interact is 0 (Chapter 1's Ralsei run event reads runmove) would crash.
    with (obj_mainchara)
    {
        if (!variable_instance_exists(id, "runmove"))
            runmove = 0;
    }
    if (string_pos("room_gameover", room_get_name(room)) == 1)
        global.mp_gameover = 1;
    if (global.mp_warp_pending)
    {
        if (room == global.mp_warp_room)
        {
            // Wait a few frames before stepping onto the spot, like arriving through a door:
            // new party followers only get their sprites in their first Step, and a cutscene
            // starting on the very first frame would copy empty sprites into its actors.
            global.mp_warp_pending = 0;
            global.mp_warp_delay = 4;
        }
    }
}

// ---------------------------------------------------------------- shared story state

// The room's own objects (Lancer standing at the gate, doors, NPCs) are made from the story
// progress at the moment the room is entered. When another player moves the story on while
// I stand in free roam, my room is out of date: once the changes have settled, enter it again
// (same spot) so it is built like theirs.
function mp_room_refresh_tick()
{
    if (global.mp_plot_remote < 0)
        return;
    // (Only when the story moved on: taking a lower plot, e.g. when joining a host who is behind, must not rebuild the room.)
    if (!variable_global_exists("plot") || global.plot <= global.mp_room_plot)
    {
        global.mp_plot_remote = -1;
        return;
    }
    if (global.mp_frame - global.mp_plot_remote < 90)
        return;
    if (global.interact != 0 || global.mp_sstate != 0 || mp_in_battle_scene() || global.mp_warp_pending || global.mp_warp_delay > 0 || is_array(global.mp_pull))
        return;
    if (mp_cutscene_running() || mp_credits_running() || mp_board_on() || mp_plat_on() || !instance_exists(obj_mainchara))
        return;
    global.mp_plot_remote = -1;
    mp_log("room refresh: plot " + string(global.mp_room_plot) + " -> " + string(global.plot));
    global.mp_warp_reenter = 1;
    mp_warp(room, obj_mainchara.x, obj_mainchara.y, 0);
}

// Variables that make up the shared save state. len 0 = scalar.
function mp_vars_init()
{
    global.mp_vname = ["plot", "gold", "xp", "lv", "lgold", "lxp", "llv", "lweapon", "larmor", "lhp", "lmaxhp", "lat", "ldf", "flag", "item", "keyitem", "weapon", "armor", "litem", "phone", "char", "hp", "maxhp", "at", "df", "mag", "guts", "charweapon", "chararmor1", "chararmor2"];
    global.mp_vcount = array_length(global.mp_vname);
    global.mp_vlen = array_create(global.mp_vcount, 0);
    global.mp_vshadow = array_create(global.mp_vcount, 0);
    global.mp_vqueue = ds_list_create();
    global.mp_vscan = 0;
    global.mp_vscan_flag = 60;
    global.mp_loaded = 0;
}

function mp_var_index(nm)
{
    for (var v = 0; v < global.mp_vcount; v++)
    {
        if (global.mp_vname[v] == nm)
            return v;
    }
    return -1;
}

function mp_vars_valid(v)
{
    var nm = global.mp_vname[v];
    if (!variable_global_exists(nm))
        return false;
    var val = variable_global_get(nm);
    if (global.mp_vlen[v] > 0)
        return is_array(val);
    return !is_array(val);
}

function mp_vars_reset_shadow()
{
    ds_list_clear(global.mp_vqueue);
    for (var v = 0; v < global.mp_vcount; v++)
    {
        global.mp_vlen[v] = 0;
        if (!variable_global_exists(global.mp_vname[v]))
            continue;
        var val = variable_global_get(global.mp_vname[v]);
        if (is_array(val))
        {
            global.mp_vlen[v] = array_length(val);
            var sh = array_create(global.mp_vlen[v], 0);
            array_copy(sh, 0, val, 0, global.mp_vlen[v]);
            global.mp_vshadow[v] = sh;
        }
        else
        {
            global.mp_vshadow[v] = val;
        }
    }
}

// Nothing is sent while a possible cutscene is being classified either: its first flag or
// plot changes would otherwise reach the others before the pull and stop the cutscene from
// triggering in their games.
function mp_vars_can_sync()
{
    return global.mp_sstate == 0 && global.mp_classify == 0 && !mp_in_battle_scene();
}

// Story flags below 60 are settings / transient battle state and stay local.
function mp_var_local_only(v, i)
{
    return global.mp_vname[v] == "flag" && i < 60;
}

// Prepended to scr_load: a save was just loaded.
function mp_on_save_loaded()
{
    if (!variable_global_exists("mp_inited"))
        return;
    global.mp_loaded = 1;
    // Continue after a Game Over: everyone reloads their own save, so meet at the host afterwards.
    if (global.mp_gameover && mp_on() && global.mp_role == 2)
        global.mp_goto_timer = 180;
    global.mp_gameover = 0;
}

function mp_vars_tick()
{
    if (global.mp_loaded)
    {
        // Don't broadcast the differences a save file introduced. The host's world is the
        // shared one: clients ask for it again, a host pushes its own to everyone.
        global.mp_loaded = 0;
        mp_vars_reset_shadow();
        if (global.mp_role == 1)
        {
            mp_vars_send_full(-1);
        }
        else
        {
            mp_begin(21);
            mp_send();
        }
        return;
    }
    if (!mp_vars_can_sync())
        return;
    // Apply changes that arrived while we were busy.
    mp_vars_apply_queue();
    if ((global.mp_frame mod 2) != 0)
        return;
    mp_vars_send_changes(false);
}

// Sends what changed in the shared state since last time. Normally spread over frames
// (the big flag array in slices, at most one message); full = everything right now.
function mp_vars_send_changes(full)
{
    var started = false;
    for (var v = 0; v < global.mp_vcount; v++)
    {
        if (!mp_vars_valid(v))
            continue;
        var nm = global.mp_vname[v];
        var val = variable_global_get(nm);
        if (global.mp_vlen[v] > 0)
        {
            var sh = global.mp_vshadow[v];
            var a = 0;
            var z = min(global.mp_vlen[v], array_length(val));
            if (nm == "flag" && !full)
            {
                // Spread the big flag array over several frames.
                a = global.mp_vscan_flag;
                z = min(z, a + 1500);
                global.mp_vscan_flag = z;
                if (global.mp_vscan_flag >= min(global.mp_vlen[v], array_length(val)))
                    global.mp_vscan_flag = 60;
            }
            for (var i = a; i < z; i++)
            {
                if (val[i] != sh[i])
                {
                    if (!mp_var_local_only(v, i))
                    {
                        if (!started)
                        {
                            mp_begin(20);
                            mp_wu8(0);
                            started = true;
                        }
                        mp_wu8(v);
                        mp_wu16(i);
                        mp_wval(val[i]);
                    }
                    global.mp_vshadow[v][i] = val[i];
                    if (started && buffer_tell(global.mp_msg) > 900)
                    {
                        if (!full)
                            break;
                        mp_wu8(255);
                        mp_send();
                        started = false;
                    }
                }
            }
        }
        else if (val != global.mp_vshadow[v])
        {
            if (!started)
            {
                mp_begin(20);
                mp_wu8(0);
                started = true;
            }
            mp_wu8(v);
            mp_wu16(0);
            mp_wval(val);
            global.mp_vshadow[v] = val;
        }
        if (!full && started && buffer_tell(global.mp_msg) > 900)
            break; // the rest goes out next time
    }
    if (started)
    {
        mp_wu8(255);
        mp_send();
    }
}

// Applies shared-state changes that arrived while we were busy.
// (The host re-sends what it applies, since it may have sent its own value for the same
// thing in the meantime: the value the host ends up with is the one everybody gets.)
function mp_vars_apply_queue()
{
    var started = false;
    while (ds_list_size(global.mp_vqueue) > 0)
    {
        var e = ds_list_find_value(global.mp_vqueue, 0);
        ds_list_delete(global.mp_vqueue, 0);
        mp_var_apply(e[0], e[1], e[2]);
        if (global.mp_role == 1)
        {
            if (!started)
            {
                mp_begin(20);
                mp_wu8(0);
                started = true;
            }
            mp_wu8(e[0]);
            mp_wu16(e[1]);
            mp_wval(e[2]);
            if (buffer_tell(global.mp_msg) > 900)
            {
                mp_wu8(255);
                mp_send();
                started = false;
            }
        }
    }
    if (started)
    {
        mp_wu8(255);
        mp_send();
    }
}

// Sends the complete shared state to a newly joined client.
// Sends the complete shared state to one peer, or to everyone when sock is not a peer.
function mp_vars_send_full(sock)
{
    mp_vars_reset_shadow();
    mp_begin(20);
    mp_wu8(1);
    var count = 0;
    for (var v = 0; v < global.mp_vcount; v++)
    {
        if (!mp_vars_valid(v))
            continue;
        var val = variable_global_get(global.mp_vname[v]);
        if (global.mp_vlen[v] > 0)
        {
            var isflag = global.mp_vname[v] == "flag";
            for (var i = 0; i < global.mp_vlen[v]; i++)
            {
                if (mp_var_local_only(v, i))
                    continue;
                if (isflag && val[i] == 0)
                    continue;
                mp_wu8(v);
                mp_wu16(i);
                mp_wval(val[i]);
                count++;
                if (buffer_tell(global.mp_msg) > 900)
                {
                    // Keep every message well inside one datagram.
                    mp_wu8(255);
                    mp_vars_send_chunk(sock);
                    mp_begin(20);
                    mp_wu8(2);
                    count = 0;
                }
            }
        }
        else
        {
            mp_wu8(v);
            mp_wu16(0);
            mp_wval(val);
            count++;
        }
    }
    mp_wu8(255);
    mp_vars_send_chunk(sock);
}

function mp_vars_send_chunk(sock)
{
    if (is_struct(sock))
        mp_send_to(sock);
    else
        mp_send();
}

function mp_vars_recv(pid, b)
{
    var mode = buffer_read(b, buffer_u8);
    if (mode != 0 && pid != 0)
        return; // full snapshots only come from the host
    if (mode == 1)
    {
        // Full snapshot: clear our story flags first so we match the host exactly.
        if (variable_global_exists("flag"))
        {
            var nfl = array_length(global.flag);
            for (var i = 60; i < nfl; i++)
                global.flag[i] = 0;
        }
        mp_vars_reset_shadow();
        ds_list_clear(global.mp_vqueue);
        global.mp_need_warp = 1;
    }
    // The host's copy is the shared one: changes from a client are echoed back to everyone
    // (that client included) in the order the host took them, so two players changing the
    // same thing at once (e.g. both finishing a cutscene) end up with the same value.
    var echo = global.mp_role == 1 && pid != 0 && mode == 0;
    var got = [];
    var v = buffer_read(b, buffer_u8);
    while (v != 255)
    {
        var idx = buffer_read(b, buffer_u16);
        var val = mp_rval(b);
        if (v < global.mp_vcount)
        {
            if (mode != 0 || mp_vars_can_sync())
                mp_var_apply(v, idx, val);
            else
                ds_list_add(global.mp_vqueue, [v, idx, val]);
            if (echo)
                array_push(got, [v, idx, val]);
        }
        v = buffer_read(b, buffer_u8);
    }
    if (echo && array_length(got) > 0)
    {
        mp_begin(20);
        mp_wu8(0);
        for (var k = 0; k < array_length(got); k++)
        {
            var e = got[k];
            mp_wu8(e[0]);
            mp_wu16(e[1]);
            mp_wval(e[2]);
        }
        mp_wu8(255);
        mp_send();
    }
}

function mp_var_apply(v, idx, val)
{
    var nm = global.mp_vname[v];
    if (!variable_global_exists(nm))
        return;
    var cur = variable_global_get(nm);
    if (is_array(cur))
    {
        if (idx >= array_length(cur))
            return;
        mp_var_array_write(nm, idx, val);
        if (is_array(global.mp_vshadow[v]) && idx < array_length(global.mp_vshadow[v]))
            global.mp_vshadow[v][idx] = val;
    }
    else
    {
        if (nm == "plot" && cur != val)
            global.mp_plot_remote = global.mp_frame;
        variable_global_set(nm, val);
        global.mp_vshadow[v] = val;
    }
}

// Writes straight into the game's global arrays (no copy-on-write surprises).
function mp_var_array_write(nm, idx, val)
{
    switch (nm)
    {
        case "flag":
            global.flag[idx] = val;
            break;
        case "item":
            global.item[idx] = val;
            break;
        case "keyitem":
            global.keyitem[idx] = val;
            break;
        case "weapon":
            global.weapon[idx] = val;
            break;
        case "armor":
            global.armor[idx] = val;
            break;
        case "litem":
            global.litem[idx] = val;
            break;
        case "phone":
            global.phone[idx] = val;
            break;
        case "char":
            global.char[idx] = val;
            break;
        case "hp":
            global.hp[idx] = val;
            break;
        case "maxhp":
            global.maxhp[idx] = val;
            break;
        case "at":
            global.at[idx] = val;
            break;
        case "df":
            global.df[idx] = val;
            break;
        case "mag":
            global.mag[idx] = val;
            break;
        case "guts":
            global.guts[idx] = val;
            break;
        case "charweapon":
            global.charweapon[idx] = val;
            break;
        case "chararmor1":
            global.chararmor1[idx] = val;
            break;
        case "chararmor2":
            global.chararmor2[idx] = val;
            break;
    }
}
