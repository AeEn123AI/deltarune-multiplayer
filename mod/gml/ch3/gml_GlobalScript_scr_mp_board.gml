// DELTARUNE Multiplayer - Chapter 3 board game.
//
// The board works like walking around: everyone plays their own copy of the board, and the
// other players' pieces are shown on it. The board is always shown at the same place in the
// room (x 128-512, y 64-320); moving to another board screen shifts the BOARD_Tiles layer,
// so a position on the whole board is the piece's x/y minus that layer's offset.

function mp_board_on()
{
    return instance_exists(obj_mainchara_board) && layer_get_id("BOARD_Tiles") != -1;
}

// The piece I steer, or noone.
function mp_board_lead()
{
    var k = noone;
    with (obj_mainchara_board)
    {
        if (controlled && name == "kris")
            k = id;
    }
    if (k == noone)
    {
        with (obj_mainchara_board)
        {
            if (controlled)
                k = id;
        }
    }
    return k;
}

function mp_board_char(nm)
{
    if (nm == "kris")
        return 1;
    if (nm == "susie")
        return 2;
    if (nm == "ralsei")
        return 3;
    return 0;
}

// Board sprite of another character (spr_board_kris_walk_down -> spr_board_susie_walk_down).
function mp_board_swap(spr, fromc, toc)
{
    if (fromc == toc || fromc == 0 || toc == 0 || !sprite_exists(spr))
        return spr;
    var key = "b" + string(spr) + "_" + string(toc);
    if (ds_map_exists(global.mp_swapcache, key))
        return ds_map_find_value(global.mp_swapcache, key);
    var n = sprite_get_name(spr);
    var fp = "spr_board_" + mp_char_prefix(fromc);
    var res = spr;
    if (string_pos(fp, n) == 1)
    {
        var s = mp_try_sprite("spr_board_" + mp_char_prefix(toc) + string_delete(n, 1, string_length(fp)));
        if (s < 0)
        {
            // Fall back to walking in the same direction.
            var d = "down";
            if (string_pos("_left", n) > 0)
                d = "left";
            if (string_pos("_right", n) > 0)
                d = "right";
            if (string_pos("_up", n) > 0)
                d = "up";
            s = mp_try_sprite("spr_board_" + mp_char_prefix(toc) + "_walk_" + d);
        }
        if (s >= 0)
            res = s;
    }
    ds_map_set(global.mp_swapcache, key, res);
    return res;
}

// Replaces the board pieces' own drawing (obj_mainchara_board Draw).
function mp_board_draw_piece(xx, yy)
{
    var spr = sprite_index;
    if (variable_global_exists("mp_inited") && mp_on())
    {
        var c = mp_board_char(name);
        if (c != 0)
        {
            var shown = c;
            if (c == 1)
                shown = global.mp_cfg_char;
            else if (c == global.mp_cfg_char)
                shown = 1;
            // Pieces other players are playing are shown where they are (their ghost).
            if (mp_char_player_other(shown) >= 0)
                return;
            spr = mp_board_swap(sprite_index, c, shown);
            if (c != 1)
                global.mp_fol_mask |= 1 << shown;
            if (c == 1)
            {
                global.mp_board_spr = spr;
                global.mp_board_img = image_index;
                global.mp_board_drawn = global.mp_frame;
            }
        }
    }
    draw_sprite_ext(spr, image_index, xx, yy, image_xscale, image_yscale, image_angle, image_blend, image_alpha);
}

// What to send as my position while on the board: [x, y, sprite, frame, xs, ys, visible]
// with x/y relative to the whole board.
function mp_board_send_info()
{
    if (!mp_board_on())
        return -1;
    var k = mp_board_lead();
    if (k == noone)
        return -1;
    var tl = layer_get_id("BOARD_Tiles");
    var spr = k.sprite_index;
    var img = k.image_index;
    if (variable_global_exists("mp_board_drawn") && (global.mp_frame - global.mp_board_drawn) < 3)
    {
        spr = global.mp_board_spr;
        img = global.mp_board_img;
    }
    var vis = k.visible;
    if (variable_instance_exists(k, "myhealth") && k.myhealth <= 0)
        vis = false;
    return [k.x - layer_get_x(tl), k.y - layer_get_y(tl), spr, img, k.image_xscale, k.image_yscale, vis];
}

// Where another player's piece is on my screen, or -1 if it isn't on the board screen I see.
function mp_board_ghost_xy(pid)
{
    if (!mp_board_on())
        return -1;
    var tl = layer_get_id("BOARD_Tiles");
    var gx = global.mp_px[pid] + layer_get_x(tl);
    var gy = global.mp_py[pid] + layer_get_y(tl);
    if (gx < 128 || gy < 64 || gx > (512 - 16) || gy > (320 - 16))
        return -1;
    return [gx, gy];
}

function mp_board_ghost_depth()
{
    var k = mp_board_lead();
    if (k != noone)
        return k.depth + 1;
    return 0;
}
