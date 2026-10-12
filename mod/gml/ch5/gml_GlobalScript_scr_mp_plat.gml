// DELTARUNE Multiplayer - Chapter 5 platforming (side-scrolling) sections.
//
// In these rooms the game swaps the walking party for its own platformer: obj_plat_player
// (always Kris's platformer sprites), with the rest of the party as obj_plat_follower. Everyone
// plays their own copy of the room, like the Chapter 3 board: your platformer figure is what
// the others see as your ghost (same room coordinates, the platformer scrolls the normal view).

function mp_plat_on()
{
    return instance_exists(obj_plat_player);
}

// [x, y, sprite, image, xscale, yscale, visible] of my platformer figure, where it is drawn
// (obj_plat_player draws itself shifted by its sprite offset), or -1.
function mp_plat_send_info()
{
    if (!instance_exists(obj_plat_player))
        return -1;
    var p = instance_find(obj_plat_player, 0);
    var r = -1;
    with (p)
    {
        r = [round(x - (sprite_offset_x * image_xscale)), round(y - (sprite_offset_y * image_yscale)), sprite_index, image_index, image_xscale, image_yscale, player_visible ? 1 : 0];
    }
    return r;
}

// Ghosts are drawn with the platformer's own figure, just in front of it.
function mp_plat_ghost_depth()
{
    if (instance_exists(obj_plat_player))
        return instance_find(obj_plat_player, 0).depth - 1;
    return 0;
}
