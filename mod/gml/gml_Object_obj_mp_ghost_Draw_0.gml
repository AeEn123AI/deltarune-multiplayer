if (pid < 0 || !sprite_exists(sprite_index))
    exit;
draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, 0, c_white, 1);
// Name tag above the sprite's centre (sprite origins differ: walking sprites have it at the top
// left, the Chapter 5 platformer's sprites don't).
var tcx = x + (((sprite_get_width(sprite_index) / 2) - sprite_get_xoffset(sprite_index)) * image_xscale);
var tty = y - (sprite_get_yoffset(sprite_index) * image_yscale);
mp_draw_nametag(pid, tcx, tty - 4);
