// @chapters 1,2,4,5
// DELTARUNE Multiplayer - Chapter 3 board game support (stubs; see gml/ch3 for the real one).

function mp_board_on()
{
    return false;
}

function mp_board_send_info()
{
    return -1;
}

function mp_board_ghost_xy(pid)
{
    return -1;
}

function mp_board_ghost_depth()
{
    return 0;
}

function mp_board_draw_piece(xx, yy)
{
    draw_sprite_ext(sprite_index, image_index, xx, yy, image_xscale, image_yscale, image_angle, image_blend, image_alpha);
}
