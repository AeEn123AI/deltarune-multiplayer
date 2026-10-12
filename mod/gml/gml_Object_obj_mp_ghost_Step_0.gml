if (pid < 0)
{
    instance_destroy();
    exit;
}
var tx = global.mp_px[pid];
var ty = global.mp_py[pid];
var board = (global.mp_pstate[pid] & 16) != 0;
if (board)
{
    // Chapter 3 board piece: board position -> my screen (the board scrolls under the view).
    var bxy = mp_board_ghost_xy(pid);
    if (!is_array(bxy))
        exit;
    tx = bxy[0];
    ty = bxy[1];
}
if (snap || point_distance(x, y, tx, ty) > 120)
{
    x = tx;
    y = ty;
    snap = 0;
}
else
{
    // Positions arrive ~10 times a second; ease towards them for smooth motion at any latency.
    x = lerp(x, tx, 0.4);
    y = lerp(y, ty, 0.4);
    if (abs(x - tx) < 0.5)
        x = tx;
    if (abs(y - ty) < 0.5)
        y = ty;
}
sprite_index = global.mp_pspr[pid];
image_index = global.mp_pimg[pid];
image_xscale = global.mp_pxs[pid];
image_yscale = global.mp_pys[pid];
if (board)
    depth = mp_board_ghost_depth();
else if ((global.mp_pstate[pid] & 32) != 0)
    depth = mp_plat_ghost_depth();
else
    depth = 100000 - ((y * 10) + (sprite_get_height(sprite_index) * image_yscale * 10));
