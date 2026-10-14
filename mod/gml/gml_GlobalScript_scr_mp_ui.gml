// DELTARUNE Multiplayer - F9 menu, HUD, notifications, name tags.

function mp_ui_init()
{
    global.mp_ui_open = 0;
    global.mp_ui_sel = 0;
    global.mp_ui_edit = -1;    // which text field is being edited (-1 none)
    global.mp_ui_text = "";
    global.mp_ui_hud = 1;
    global.mp_fade = 0;
    global.mp_status_text = "";
    global.mp_font = asset_get_index("fnt_main");
    global.mp_font_small = asset_get_index("fnt_small");
    global.mp_font_tiny = asset_get_index("fnt_tinynoelle");
}

// Menu rows (built each frame so they reflect the session state).
function mp_ui_rows()
{
    var r = ["name", "char"];
    if (global.mp_role == 0)
    {
        array_push(r, "host", "ip", "join");
    }
    else
    {
        array_push(r, "goto", "leave", "hud");
    }
    array_push(r, "stopsound", "noclip");
    // Softlock tools that change the shared story: the host's (or a single player's) to use.
    if (mp_story_tools_allowed() && variable_global_exists("plot"))
        array_push(r, "story", "rewind");
    array_push(r, "close");
    return r;
}

// Reads menu input and hides it from the game while the menu is open.
function mp_ui_input()
{
    if (keyboard_check_pressed(vk_f7) && !global.mp_ui_open)
        mp_stop_all_sound();
    if (keyboard_check_pressed(vk_f6) && !global.mp_ui_open)
        mp_noclip_toggle();
    if (keyboard_check_pressed(vk_f8) && !global.mp_ui_open && mp_on())
        mp_go_to_player(mp_goto_target());
    if (keyboard_check_pressed(vk_f9))
    {
        global.mp_ui_open = !global.mp_ui_open;
        global.mp_ui_edit = -1;
        global.mp_ui_sel = 0;
        if (variable_global_exists("plot"))
            global.mp_ui_plot = global.plot;
        mp_ui_block();
        return;
    }
    if (!global.mp_ui_open)
        return;
    var rows = mp_ui_rows();
    var nrows = array_length(rows);
    global.mp_ui_sel = clamp(global.mp_ui_sel, 0, nrows - 1);
    if (global.mp_ui_edit >= 0)
    {
        // Text entry: collect typed characters ourselves (starts empty; empty keeps the old value).
        var t = global.mp_ui_text + string_replace_all(keyboard_string, "\n", "");
        keyboard_string = "";
        if (keyboard_check_pressed(vk_backspace) && string_length(t) > 0)
            t = string_copy(t, 1, string_length(t) - 1);
        if (string_length(t) > 40)
            t = string_copy(t, 1, 40);
        global.mp_ui_text = t;
        if (keyboard_check_pressed(vk_enter))
        {
            if (rows[global.mp_ui_edit] == "name" && t != "")
            {
                global.mp_cfg_name = string_copy(t, 1, 12);
                if (mp_on())
                {
                    global.mp_pname[global.mp_myid] = global.mp_cfg_name;
                    mp_send_pinfo(global.mp_myid);
                }
            }
            if (rows[global.mp_ui_edit] == "ip" && t != "")
                mp_cfg_set_address(t);
            mp_config_save();
            global.mp_ui_edit = -1;
        }
        if (keyboard_check_pressed(vk_escape))
            global.mp_ui_edit = -1;
        mp_ui_block();
        return;
    }
    if (global.input_pressed[2])
        global.mp_ui_sel = (global.mp_ui_sel + nrows - 1) mod nrows;
    if (global.input_pressed[0])
        global.mp_ui_sel = (global.mp_ui_sel + 1) mod nrows;
    var row = rows[global.mp_ui_sel];
    if (row == "char" && (global.input_pressed[1] || global.input_pressed[3]))
    {
        var d = 1;
        if (global.input_pressed[3])
            d = -1;
        global.mp_cfg_char = ((global.mp_cfg_char - 1 + d + mp_char_max()) mod mp_char_max()) + 1;
        mp_config_save();
        if (mp_on())
        {
            global.mp_pchar[global.mp_myid] = global.mp_cfg_char;
            mp_send_pinfo(global.mp_myid);
        }
    }
    if (row == "story" && (global.input_pressed[1] || global.input_pressed[3]))
    {
        var step = keyboard_check(vk_shift) ? 10 : 1;
        if (global.input_pressed[3])
            step = -step;
        global.mp_ui_plot = max(0, global.mp_ui_plot + step);
    }
    var confirm = global.input_pressed[4] || keyboard_check_pressed(vk_enter);
    if (confirm)
    {
        if (row == "name" || row == "ip")
        {
            global.mp_ui_edit = global.mp_ui_sel;
            keyboard_string = "";
            global.mp_ui_text = "";
        }
        if (row == "host")
        {
            mp_config_save();
            mp_host_start(global.mp_cfg_port);
            global.mp_ui_open = 0;
        }
        if (row == "join")
        {
            mp_config_save();
            mp_join(global.mp_cfg_ip, global.mp_cfg_port);
            global.mp_ui_open = 0;
        }
        if (row == "goto")
        {
            global.mp_ui_open = 0;
            mp_go_to_player(mp_goto_target());
        }
        if (row == "leave")
        {
            mp_resume_clear();
            mp_disconnect("You left the session.");
            global.mp_ui_open = 0;
        }
        if (row == "hud")
            global.mp_ui_hud = !global.mp_ui_hud;
        if (row == "stopsound")
            mp_stop_all_sound();
        if (row == "noclip")
            mp_noclip_toggle();
        if (row == "story")
        {
            global.mp_ui_open = 0;
            mp_story_set(global.mp_ui_plot);
        }
        if (row == "rewind")
        {
            global.mp_ui_open = 0;
            mp_checkpoint_rewind();
        }
        if (row == "close")
            global.mp_ui_open = 0;
    }
    if (global.input_pressed[5])
        global.mp_ui_open = 0;
    mp_ui_block();
}

function mp_ui_block()
{
    for (var i = 0; i < 10; i++)
    {
        global.input_pressed[i] = 0;
        global.input_held[i] = 0;
    }
}

function mp_ui_rowtext(row)
{
    switch (row)
    {
        case "name":
            return "Name:  " + global.mp_cfg_name;
        case "char":
            var ct = "Play as:  < " + mp_char_name(global.mp_cfg_char) + " >";
            // Several players may play the same character; in battle the first of them
            // (lowest player number) controls it and the others watch.
            var co = mp_on() ? mp_char_player_other(global.mp_cfg_char) : -1;
            if (co >= 0)
            {
                ct += "  (also " + global.mp_pname[co];
                if (co < global.mp_myid)
                    ct += ": you watch battles";
                ct += ")";
            }
            return ct;
        case "host":
            return "Host a game (port " + string(global.mp_cfg_port) + ")";
        case "ip":
            return "Host address:  " + global.mp_cfg_ip + ":" + string(global.mp_cfg_port);
        case "join":
            return "Join game";
        case "goto":
            var gt = mp_goto_target();
            if (gt < 0)
                return "Go to other player (F8)";
            return "Go to " + global.mp_pname[gt] + "  (F8)";
        case "leave":
            if (global.mp_role == 1)
                return "Stop hosting";
            return "Leave session";
        case "hud":
            if (global.mp_ui_hud)
                return "Player list:  ON";
            return "Player list:  OFF";
        case "stopsound":
            return "Stop all music and sounds  (F7)";
        case "noclip":
            return "Noclip (walk through walls):  " + (global.mp_noclip ? "ON" : "OFF") + "  (F6)";
        case "story":
            var sp = "Fix softlock: story progress < " + string(global.mp_ui_plot) + " >";
            if (global.mp_ui_plot != global.plot)
                sp += " (now " + string(global.plot) + ")";
            return sp;
        case "rewind":
            return "Fix softlock: replay this room's story";
        case "close":
            return "Close";
    }
    return row;
}

function mp_draw_text_outlined(xx, yy, str, col)
{
    draw_set_color(c_black);
    draw_text(xx + 1, yy + 1, str);
    draw_text(xx - 1, yy + 1, str);
    draw_text(xx + 1, yy - 1, str);
    draw_text(xx - 1, yy - 1, str);
    draw_set_color(col);
    draw_text(xx, yy, str);
}

function mp_draw_gui()
{
    if (!variable_global_exists("mp_inited"))
        return;
    var gw = display_get_gui_width();
    var gh = display_get_gui_height();
    var sc = max(1, floor(gh / 480));
    var oldfont = draw_get_font();
    var oldcol = draw_get_color();
    var oldalpha = draw_get_alpha();
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    if (global.mp_font_small >= 0)
        draw_set_font(global.mp_font_small);
    draw_set_alpha(1);

    // Player list.
    if (global.mp_role != 0 && global.mp_ui_hud)
    {
        var yy = 4 * sc;
        var head = "";
        if (global.mp_role == 1)
            head = "HOST";
        else if (global.mp_linkstate == 3)
            head = "PING " + string(global.mp_rtt) + "ms";
        else
            head = "CONNECTING...";
        draw_set_alpha(0.8);
        draw_text_transformed_color(4 * sc, yy, head + "  " + string_format(global.mp_kbps_in + global.mp_kbps_out, 1, 1) + "KB/s", sc, sc, 0, c_gray, c_gray, c_gray, c_gray, 0.8);
        draw_set_alpha(1);
        yy += 10 * sc;
        for (var i = 0; i < 8; i++)
        {
            if (!global.mp_pconn[i])
                continue;
            var label = global.mp_pname[i] + " (" + mp_char_name(global.mp_pchar[i]) + ")";
            if (i == global.mp_myid)
                label = "> " + label;
            else if (global.mp_proom[i] != room && global.mp_proom[i] >= 0)
                label += " - elsewhere";
            var st = global.mp_pstate[i];
            if (i == global.mp_myid)
                st = mp_state_bits();
            if (st & 1)
                label += " [battle]";
            else if (st & 2)
                label += " [cutscene]";
            var col = mp_char_color(global.mp_pchar[i]);
            draw_text_transformed_color(4 * sc + 1, yy + 1, label, sc, sc, 0, c_black, c_black, c_black, c_black, 1);
            draw_text_transformed_color(4 * sc, yy, label, sc, sc, 0, col, col, col, col, 1);
            yy += 9 * sc;
        }
    }

    // Battle / sync status line.
    var status = mp_status_line();
    if (status != "")
    {
        var w = string_width(status) * sc;
        var sx = (gw - w) / 2;
        var sy = 4 * sc;
        draw_set_color(c_black);
        draw_set_alpha(0.6);
        draw_rectangle(sx - 6 * sc, sy - 2 * sc, sx + w + 6 * sc, sy + 10 * sc, false);
        draw_set_alpha(1);
        draw_text_transformed_color(sx, sy, status, sc, sc, 0, c_yellow, c_yellow, c_yellow, c_yellow, 1);
    }

    // Spectators of a cutscene that didn't start in their game see the leader's dialogue.
    if (global.mp_sstate == 4 && global.mp_watch_text != "")
    {
        var tw = gw - 40 * sc;
        var th = 52 * sc;
        var tx = 20 * sc;
        var ty = gh - th - 24 * sc;
        draw_set_color(c_black);
        draw_set_alpha(0.85);
        draw_rectangle(tx, ty, tx + tw, ty + th, false);
        draw_set_alpha(1);
        draw_set_color(c_white);
        draw_rectangle(tx, ty, tx + tw, ty + th, true);
        draw_text_ext_transformed(tx + 8 * sc, ty + 6 * sc, global.mp_watch_text, 10, (tw - 16 * sc) / sc, sc, sc, 0);
    }

    // Notifications.
    var ny = gh - (14 * sc);
    for (var n = ds_list_size(global.mp_notes) - 1; n >= 0; n--)
    {
        var age = current_time - ds_list_find_value(global.mp_note_time, n);
        if (age > 6000)
            continue;
        var a = clamp((6000 - age) / 1000, 0, 1);
        var txt = ds_list_find_value(global.mp_notes, n);
        draw_text_transformed_color(4 * sc + 1, ny + 1, txt, sc, sc, 0, c_black, c_black, c_black, c_black, a);
        draw_text_transformed_color(4 * sc, ny, txt, sc, sc, 0, c_white, c_white, c_white, c_white, a);
        ny -= 10 * sc;
    }

    // Fade in after the mod moved me (like a door transition).
    if (global.mp_fade > 0)
    {
        draw_set_color(c_black);
        draw_set_alpha(global.mp_fade);
        draw_rectangle(0, 0, gw, gh, false);
        draw_set_alpha(1);
        global.mp_fade = max(0, global.mp_fade - 0.06);
    }

    // F9 menu.
    if (global.mp_ui_open)
    {
        var rows = mp_ui_rows();
        if (global.mp_font >= 0)
            draw_set_font(global.mp_font);
        var tw = 0;
        for (var r0 = 0; r0 < array_length(rows); r0++)
            tw = max(tw, string_width(mp_ui_rowtext(rows[r0])));
        var bw = min(max(300, tw + 40) * sc, gw - 8 * sc);
        var bh = (54 + (array_length(rows) * 22)) * sc;
        var bx = (gw - bw) / 2;
        var by = (gh - bh) / 2;
        draw_set_color(c_black);
        draw_rectangle(bx, by, bx + bw, by + bh, false);
        draw_set_color(c_white);
        draw_rectangle(bx, by, bx + bw, by + bh, true);
        draw_rectangle(bx + sc, by + sc, (bx + bw) - sc, (by + bh) - sc, true);
        if (global.mp_font >= 0)
            draw_set_font(global.mp_font);
        draw_text_transformed(bx + 12 * sc, by + 6 * sc, "MULTIPLAYER", sc, sc, 0);
        for (var r = 0; r < array_length(rows); r++)
        {
            var t = mp_ui_rowtext(rows[r]);
            if (global.mp_ui_edit == r)
                t = "> " + global.mp_ui_text + "_";
            var c2 = c_white;
            if (r == global.mp_ui_sel)
                c2 = c_yellow;
            draw_text_transformed_color(bx + 20 * sc, by + (32 + r * 22) * sc, t, sc, sc, 0, c2, c2, c2, c2, 1);
        }
        if (global.mp_font_small >= 0)
            draw_set_font(global.mp_font_small);
        var hint = "Z: select   X: close   F9: toggle";
        if (global.mp_ui_edit >= 0)
            hint = "Type, then ENTER (empty keeps the old value, ESC cancels)";
        draw_text_transformed_color(bx + 12 * sc, (by + bh) - 14 * sc, hint, sc, sc, 0, c_gray, c_gray, c_gray, c_gray, 1);
    }
    else if (global.mp_role == 0 && global.mp_frame < 300)
    {
        draw_text_transformed_color(4 * sc, 4 * sc, "Multiplayer mod: press F9", sc, sc, 0, c_gray, c_gray, c_gray, c_gray, 1);
    }
    draw_set_font(oldfont);
    draw_set_color(oldcol);
    draw_set_alpha(oldalpha);
}

// Name tag drawn above a ghost (world coordinates).
function mp_draw_nametag(pid, cx, ty)
{
    var oldfont = draw_get_font();
    if (global.mp_font_small >= 0)
        draw_set_font(global.mp_font_small);
    draw_set_halign(fa_center);
    draw_set_valign(fa_bottom);
    var col = mp_char_color(global.mp_pchar[pid]);
    var s = global.mp_pname[pid];
    draw_set_color(c_black);
    draw_text(cx + 1, ty + 1, s);
    draw_set_color(col);
    draw_text(cx, ty, s);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_font(oldfont);
    draw_set_color(c_white);
}

// Accepts "host", "host:port" (and "[ipv6]:port"); an invalid port keeps the current one.
function mp_cfg_set_address(t)
{
    t = string_replace_all(t, " ", "");
    var c = string_last_pos(":", t);
    var b = string_pos("]", t);
    if (c > 0 && c > b && string_count(":", t) == 1 || (c > 0 && b > 0 && c > b))
    {
        var portstr = string_delete(t, 1, c);
        var host = string_copy(t, 1, c - 1);
        var pv = -1;
        if (portstr != "" && string_digits(portstr) == portstr)
            pv = real(portstr);
        if (pv >= 1 && pv <= 65535)
            global.mp_cfg_port = pv;
        else
            mp_notify("Invalid port '" + portstr + "' - keeping " + string(global.mp_cfg_port));
        t = host;
    }
    t = string_replace_all(string_replace_all(t, "[", ""), "]", "");
    if (t != "")
        global.mp_cfg_ip = t;
}

// Stops every sound and song that is playing (for when the music got out of step). The game
// starts a room's song again the next time it is entered, since rooms only start one when none plays.
function mp_stop_all_sound()
{
    audio_stop_all();
    mp_notify("Stopped all music and sounds.");
}
