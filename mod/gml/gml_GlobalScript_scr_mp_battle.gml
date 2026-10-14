// DELTARUNE Multiplayer - battles.
//
// Every player runs the battle locally. To keep all copies identical:
//  * Menu: the player who owns the hero whose turn it is drives the menu; their button
//    presses (with original frame spacing) are replayed by everyone else.
//  * Attack timing: each player presses for their own hero(es); results are shared.
//  * Random numbers are re-seeded identically at each phase.
//  * Bullets: everyone dodges with their own SOUL; hits only hurt the hero you play.
//    HP is owned by the hero's player and broadcast as it changes.
//  * Turn barrier: before each new menu turn everyone waits for the host's TURN_GO,
//    which carries the authoritative TP (everyone's grazes added up), HP and enemy state.

function mp_battle_init()
{
    global.mp_minq = ds_list_create();
    global.mp_qte = ds_map_create();
    global.mp_owner = array_create(3, 0);
    global.mp_rhp = array_create(3, 0);
    global.mp_rhp_known = array_create(3, 0);
    global.mp_hp_sent = array_create(3, -99999);
    global.mp_tdone_bid = array_create(8, -1);
    global.mp_tdone_turn = array_create(8, -1);
    global.mp_tdone_gain = array_create(8, 0);
    global.mp_tdone_late = array_create(8, 0);
    global.mp_tgo_sent = -1;
    global.mp_tgo_stash = -1;
    mp_battle_reset();
}

// Clears the per-battle buffers (inputs and attack results received from others).
function mp_battle_clear_buffers()
{
    ds_list_clear(global.mp_minq);
    ds_map_clear(global.mp_qte);
}

function mp_battle_reset()
{
    global.mp_gameover = 0;
    global.mp_tgo_sent = -1;
    global.mp_b_active = 0;
    global.mp_bid = -1;
    global.mp_bturn = 0;
    global.mp_bgo = -1;
    global.mp_prev_myfight = 0;
    global.mp_prev_charturn = 0;
    global.mp_bwait = 0;
    global.mp_bwait_names = "";
    global.mp_bwait_names_time = -99999;
    global.mp_bwait_names_sent = "";
    global.mp_bwait_turn = 0;
    global.mp_bwait_since = 0;
    global.mp_bgate_open = 0;
    global.mp_mn = 0;
    global.mp_mn_last = 0;
    global.mp_mn_pend = 0;
    global.mp_prev_mnfight = -99;
    global.mp_tension_b0 = 0;
    global.mp_qte_since = 0;
    for (var s = 0; s < 3; s++)
    {
        global.mp_rhp_known[s] = 0;
        global.mp_hp_sent[s] = -99999;
    }
}

function mp_battle_on()
{
    return global.mp_b_active && mp_on() && instance_exists(obj_battlecontroller);
}

function mp_slot_mine(s)
{
    if (!mp_battle_on())
        return true;
    if (s < 0 || s > 2)
        return false;
    return global.mp_owner[s] == global.mp_myid;
}

// Who controls each party slot: the lowest-id player who picked that character,
// otherwise the host. Players whose character is not in the party watch.
function mp_participating(i)
{
    if (!global.mp_pconn[i])
        return false;
    if (global.mp_role != 1 || i == 0)
        return true;
    return global.mp_tdone_bid[i] == global.mp_bid;
}

function mp_compute_owners()
{
    for (var s = 0; s < 3; s++)
    {
        var c = global.char[s];
        var o = 0;
        if (c == 0)
            o = 255;
        else
        {
            for (var i = 0; i < 8; i++)
            {
                if (global.mp_pchar[i] == c && mp_participating(i))
                {
                    o = i;
                    break;
                }
            }
        }
        global.mp_owner[s] = o;
    }
}

function mp_battle_seed(phase)
{
    if (!mp_battle_on())
        return;
    var sd = (global.mp_seed + (global.mp_bturn * 7919) + (phase * 104729) + (global.mp_bid * 31)) mod 2147483647;
    random_set_seed(sd);
}

// ---------------------------------------------------------------- lifecycle

// Appended to obj_battlecontroller's Create event.
function mp_battle_created()
{
    if (!mp_on())
        return;
    mp_battle_reset();
    mp_test_battle_created();
    global.mp_b_active = 1;
    global.mp_bid = global.encounterno;
    global.mp_bturn = 0;
    global.mp_bwait = 1;
    global.mp_bwait_turn = 0;
    global.mp_bwait_since = current_time;
    global.mp_tension_b0 = global.tension;
    mp_compute_owners();
    mp_send_tdone(0, 0);
    if (global.mp_role == 1)
    {
        global.mp_tdone_bid[0] = global.mp_bid;
        global.mp_tdone_turn[0] = 0;
    }
}

function mp_battle_ended()
{
    if (global.mp_scenes_killed)
    {
        global.mp_scenes_killed = 0;
        global.mp_postbattle = 120;
    }
    global.mp_b_active = 0;
    mp_battle_clear_buffers();
    global.mp_tgo_stash = -1;
    if (global.mp_role == 1)
    {
        for (var i = 0; i < 8; i++)
        {
            global.mp_tdone_bid[i] = -1;
            global.mp_tdone_turn[i] = -1;
        }
    }
}

function mp_send_tdone(turn, gain)
{
    mp_begin(44);
    mp_wu16(global.mp_bid);
    mp_wu16(turn);
    mp_wf64(gain);
    mp_send();
}

// Prepended to scr_mnendturn: holds the next menu turn until everyone is ready.
function mp_turn_gate()
{
    if (!mp_battle_on())
        return true;
    if (global.mp_bgate_open)
    {
        global.mp_bgate_open = 0;
        return true;
    }
    // Keep the battle controller from re-arming its end-of-turn alarm while we wait.
    with (obj_battlecontroller)
    {
        reset = 1;
        alarm[2] = -1;
    }
    if (!global.mp_bwait)
    {
        global.mp_bwait = 1;
        global.mp_bwait_turn = global.mp_bturn + 1;
        global.mp_bwait_since = current_time;
        mp_battle_send_hp();
        var gain = max(0, global.tension - global.mp_tension_b0);
        mp_log("gate reached, tdone " + string(global.mp_bwait_turn) + " gain=" + string(gain) + " myfight=" + string(global.myfight) + " mnfight=" + string(global.mnfight) + " mon=" + string(global.monster[0]) + string(global.monster[1]) + string(global.monster[2]) + " types=" + string(global.monstertype[0]) + "," + string(global.monstertype[1]) + "," + string(global.monstertype[2]));
        mp_send_tdone(global.mp_bwait_turn, gain);
        if (global.mp_role == 1)
        {
            global.mp_tdone_bid[0] = global.mp_bid;
            global.mp_tdone_turn[0] = global.mp_bwait_turn;
            global.mp_tdone_gain[0] = 0;
        }
    }
    return false;
}

// ---------------------------------------------------------------- receive

function mp_battle_recv(type, from, b)
{
    if (type == 41) // MENU INPUT
    {
        var bid = buffer_read(b, buffer_u16);
        var turn = buffer_read(b, buffer_u16);
        var n = buffer_read(b, buffer_u16);
        var dt = buffer_read(b, buffer_u8);
        var mask = buffer_read(b, buffer_u16);
        ds_list_add(global.mp_minq, [bid, turn, n, dt, mask]);
        return;
    }
    if (type == 42) // QTE RESULT
    {
        var bid2 = buffer_read(b, buffer_u16);
        var turn2 = buffer_read(b, buffer_u16);
        var slot = buffer_read(b, buffer_u8);
        var pts = mp_num(buffer_read(b, buffer_s16));
        ds_map_set(global.mp_qte, (turn2 * 4) + slot, pts);
        mp_log("qte recv turn=" + string(turn2) + " slot=" + string(slot) + " pts=" + string(pts));
        return;
    }
    if (type == 43) // HP
    {
        var slot2 = buffer_read(b, buffer_u8);
        var chr = buffer_read(b, buffer_u8);
        var hp = mp_num(buffer_read(b, buffer_s16));
        if (mp_battle_on() && slot2 < 3 && global.char[slot2] == chr && global.mp_owner[slot2] == from)
        {
            global.mp_rhp[slot2] = hp;
            global.mp_rhp_known[slot2] = 1;
        }
        return;
    }
    if (type == 44) // TURN DONE (host collects)
    {
        var bid3 = buffer_read(b, buffer_u16);
        var turn3 = buffer_read(b, buffer_u16);
        var gain = buffer_read(b, buffer_f64);
        if (global.mp_role == 1)
        {
            global.mp_tdone_bid[from] = bid3;
            global.mp_tdone_turn[from] = turn3;
            global.mp_tdone_gain[from] = gain;
            // Ready for a turn that was already released: a late joiner. They'll enter at
            // the next TURN_GO, so nobody waits for them until then.
            global.mp_tdone_late[from] = global.mp_b_active && bid3 == global.mp_bid && turn3 <= global.mp_tgo_sent;
        }
        return;
    }
    if (type == 46) // GAME OVER: the party was wiped in someone's game
    {
        var bid4 = buffer_read(b, buffer_u16);
        if (mp_battle_on() && bid4 == global.mp_bid && !global.mp_gameover)
        {
            mp_log("remote game over from " + string(from));
            global.mp_gameover = 1;
            scr_gameover();
        }
        return;
    }
    if (type == 45) // TURN GO
    {
        var st = [];
        st[0] = buffer_read(b, buffer_u16);
        st[1] = buffer_read(b, buffer_u16);
        st[2] = buffer_read(b, buffer_f64);
        for (var s = 0; s < 3; s++)
        {
            st[3 + s] = buffer_read(b, buffer_u8);
            st[6 + s] = mp_num(buffer_read(b, buffer_s16));
            st[9 + s] = buffer_read(b, buffer_f64);
            st[12 + s] = buffer_read(b, buffer_f64);
            st[15 + s] = buffer_read(b, buffer_u8);
        }
        if (mp_battle_on() && st[0] == global.mp_bid)
            mp_apply_tgo(st);
        return;
    }
}

// st: [bid, turn, tension, owner0..2, hp0..2, monsterhp0..2, mercy0..2, present0..2]
function mp_apply_tgo(st)
{
    var turn = st[1];
    mp_log("tgo turn=" + string(turn) + " waiting=" + string(global.mp_bwait) + "/" + string(global.mp_bwait_turn) + " alive=" + string(st[15]) + string(st[16]) + string(st[17]) + " mine=" + string(global.monster[0]) + string(global.monster[1]) + string(global.monster[2]));
    if (!global.mp_bwait || turn < global.mp_bwait_turn)
        return;
    for (var s = 0; s < 3; s++)
        global.mp_owner[s] = st[3 + s];
    if (turn > 0)
    {
        global.tension = st[2];
        for (var s2 = 0; s2 < 3; s2++)
        {
            var c = global.char[s2];
            if (c > 0 && global.mp_owner[s2] != global.mp_myid)
            {
                global.mp_rhp[s2] = st[6 + s2];
                global.mp_rhp_known[s2] = 1;
            }
            if (global.monster[s2])
            {
                global.monsterhp[s2] = st[9 + s2];
                global.mercymod[s2] = st[12 + s2];
                // The host already beat this enemy: remove it here too.
                if (!st[15 + s2])
                    mp_ch_remove_monster(s2);
            }
        }
        mp_battle_apply_hp();
    }
    global.mp_bturn = turn;
    global.mp_bgo = turn;
    global.mp_bwait = 0;
    global.mp_mn = 0;
    global.mp_mn_last = global.mp_frame - 30;
    global.mp_mn_pend = 0;
    // Drop menu inputs from older turns.
    for (var i = ds_list_size(global.mp_minq) - 1; i >= 0; i--)
    {
        var e = ds_list_find_value(global.mp_minq, i);
        if (e[1] < turn || e[0] != global.mp_bid)
            ds_list_delete(global.mp_minq, i);
    }
    mp_battle_seed(0);
    if (turn > 0)
    {
        global.mp_bgate_open = 1;
        with (obj_battlecontroller)
        {
            reset = 0;
            alarm[2] = -1;
            scr_mnendturn();
        }
        global.mp_bgate_open = 0;
    }
}

// Host: release the next turn once every participant reached the barrier.
function mp_host_turn_check()
{
    if (global.mp_role != 1 || !global.mp_bwait)
        return;
    var t = global.mp_bwait_turn;
    var waited = current_time - global.mp_bwait_since;
    var ready = true;
    for (var i = 1; i < 8; i++)
    {
        if (!global.mp_pconn[i])
            continue;
        if (global.mp_tdone_bid[i] == global.mp_bid && (global.mp_tdone_turn[i] >= t || global.mp_tdone_late[i]))
            continue;
        if (t == 0)
        {
            // Give everyone a moment to arrive at the start of a battle.
            if (waited < 12000 && (global.mp_pstate[i] & 1) == 0 && waited > 4000)
                continue;
            if (waited < 12000)
                ready = false;
        }
        else
        {
            // Only wait for players that actually joined this battle and are still in it.
            // Late joiners (not present for the previous turn) get pulled in by this TURN_GO.
            if (global.mp_tdone_bid[i] != global.mp_bid)
                continue;
            if (global.mp_tdone_late[i])
                continue;
            if ((global.mp_pstate[i] & 1) == 0 && (current_time - global.mp_ppostime[i]) < 5000 && waited > 3000)
                continue;
            if (waited < 60000)
                ready = false;
        }
    }
    if (!ready)
        return;
    mp_compute_owners();
    var tension = global.tension;
    if (t > 0)
    {
        for (var j = 1; j < 8; j++)
        {
            if (global.mp_pconn[j] && global.mp_tdone_bid[j] == global.mp_bid && global.mp_tdone_turn[j] == t)
                tension += global.mp_tdone_gain[j];
        }
        tension = min(tension, global.maxtension);
    }
    var st = [];
    st[0] = global.mp_bid;
    st[1] = t;
    st[2] = tension;
    mp_begin(45);
    mp_wu16(global.mp_bid);
    mp_wu16(t);
    mp_wf64(tension);
    for (var s = 0; s < 3; s++)
    {
        var c = global.char[s];
        var hp = 0;
        if (c > 0)
            hp = global.hp[c];
        st[3 + s] = global.mp_owner[s];
        st[6 + s] = hp;
        st[9 + s] = global.monsterhp[s];
        st[12 + s] = global.mercymod[s];
        st[15 + s] = global.monster[s];
        mp_wu8(st[3 + s]);
        mp_ws16(st[6 + s]);
        mp_wf64(st[9 + s]);
        mp_wf64(st[12 + s]);
        mp_wu8(st[15 + s]);
    }
    mp_send();
    global.mp_tgo_sent = t;
    for (var k = 0; k < 8; k++)
        global.mp_tdone_late[k] = 0;
    mp_apply_tgo(st);
}

// ---------------------------------------------------------------- per-frame

// Runs right after input sampling (before any game Step event).
function mp_battle_input()
{
    if (!mp_battle_on())
        return;
    // Seed the enemy's turn identically everywhere.
    if (global.mnfight != global.mp_prev_mnfight)
    {
        if (global.mnfight == 1)
            mp_battle_seed(2);
        if (global.mnfight == 2)
        {
            mp_battle_seed(3);
            global.mp_tension_b0 = global.tension;
        }
        global.mp_prev_mnfight = global.mnfight;
    }
    // Each hero's action (ACT, spell, attack...) starts from the same random state everywhere:
    // some ACTs roll dice after text that takes a different time to read for each player.
    if (global.myfight == 1 && (global.myfight != global.mp_prev_myfight || global.charturn != global.mp_prev_charturn))
        mp_battle_seed(10 + global.charturn);
    global.mp_prev_myfight = global.myfight;
    global.mp_prev_charturn = global.charturn;
    // Waiting for everyone at the end of a turn: nobody acts in their own game meanwhile,
    // whatever state the battle is in (e.g. an intro that opened the menu early).
    if (global.mp_bwait || global.mp_bgo < global.mp_bturn)
    {
        mp_ui_block();
        return;
    }
    var menu = global.myfight == 0 && global.mnfight == 0 && global.charturn < 3;
    if (!menu)
        return;
    var owner = global.mp_owner[global.charturn];
    if (owner == global.mp_myid)
    {
        var mask = 0;
        for (var i = 0; i < 10; i++)
        {
            if (global.input_pressed[i])
                mask |= (1 << i);
        }
        // The menu ignores presses for a few frames after the previous one. A press that
        // early would be ignored here but could land in time in the others' replay (which
        // can only be later), so hold it back until it is safely accepted everywhere.
        if ((global.mp_frame - global.mp_mn_last) < 5)
        {
            if (mask != 0)
            {
                global.mp_mn_pend = mask;
                mp_ui_block();
            }
            return;
        }
        if (mask == 0 && global.mp_mn_pend != 0)
        {
            mask = global.mp_mn_pend;
            for (var i2 = 0; i2 < 10; i2++)
            {
                if ((mask >> i2) & 1)
                {
                    global.input_pressed[i2] = 1;
                    global.input_held[i2] = 1;
                }
            }
        }
        global.mp_mn_pend = 0;
        if (mask != 0)
        {
            var dt = min(30, global.mp_frame - global.mp_mn_last);
            mp_begin(41);
            mp_wu16(global.mp_bid);
            mp_wu16(global.mp_bturn);
            mp_wu16(global.mp_mn);
            mp_wu8(dt);
            mp_wu16(mask);
            mp_send();
            mp_log("menu send n=" + string(global.mp_mn) + " mask=" + string(mask) + " ct=" + string(global.charturn) + " bm=" + string(global.bmenuno));
            global.mp_mn += 1;
            global.mp_mn_last = global.mp_frame;
        }
        return;
    }
    // Someone else is choosing: replay their presses in order, with their original spacing.
    global.mp_mn_pend = 0;
    mp_ui_block();
    for (var k = 0; k < ds_list_size(global.mp_minq); k++)
    {
        var e = ds_list_find_value(global.mp_minq, k);
        if (e[0] == global.mp_bid && e[1] == global.mp_bturn && e[2] == global.mp_mn)
        {
            if ((global.mp_frame - global.mp_mn_last) >= e[3])
            {
                for (var j = 0; j < 10; j++)
                {
                    var on = (e[4] >> j) & 1;
                    global.input_pressed[j] = on;
                    global.input_held[j] = on;
                }
                ds_list_delete(global.mp_minq, k);
                mp_log("menu apply n=" + string(global.mp_mn) + " mask=" + string(e[4]) + " ct=" + string(global.charturn) + " bm=" + string(global.bmenuno));
                global.mp_mn += 1;
                global.mp_mn_last = global.mp_frame;
            }
            break;
        }
    }
}

function mp_battle_tick()
{
    if (global.mp_role == 1 && global.mp_bwait)
    {
        var bn = mp_bwait_names();
        if ((global.mp_frame mod 30) == 0 || bn != global.mp_bwait_names_sent)
        {
            global.mp_bwait_names_sent = bn;
            mp_begin(35);
            mp_wstr(bn);
            mp_send();
        }
    }
    if (global.mp_b_active && !instance_exists(obj_battlecontroller))
        mp_battle_ended();
    // Nobody we follow is fighting: drop anything buffered from a battle we never joined.
    if (!global.mp_b_active && !mp_in_battle_scene() && (global.mp_role == 1 || (global.mp_pstate[0] & 1) == 0) && !is_array(global.mp_pull))
    {
        if (ds_list_size(global.mp_minq) > 0 || ds_map_size(global.mp_qte) > 0)
            mp_battle_clear_buffers();
        global.mp_tgo_stash = -1;
    }
    if (!mp_battle_on())
        return;
    mp_host_turn_check();
    mp_client_gate_fallback();
    mp_battle_send_hp();
    mp_battle_apply_hp();
}

// Broadcast HP of the heroes I play whenever it changes.
function mp_battle_send_hp()
{
    for (var s = 0; s < 3; s++)
    {
        var c = global.char[s];
        if (c <= 0 || global.mp_owner[s] != global.mp_myid)
            continue;
        if (global.hp[c] != global.mp_hp_sent[s])
        {
            global.mp_hp_sent[s] = global.hp[c];
            mp_log("hp send slot=" + string(s) + " hp=" + string(global.hp[c]) + " mnfight=" + string(global.mnfight));
            mp_begin(43);
            mp_wu8(s);
            mp_wu8(c);
            mp_ws16(global.hp[c]);
            mp_send();
        }
    }
}

// Brings remote heroes' HP in line with what their players report.
function mp_battle_apply_hp()
{
    var changed = false;
    for (var s = 0; s < 3; s++)
    {
        var c = global.char[s];
        if (c <= 0 || global.mp_owner[s] == global.mp_myid || global.mp_rhp_known[s] == 0)
            continue;
        // A hero someone else controls: each new report from their game is applied as is.
        // In between, my own copy of the battle may heal them the same way their game does
        // (that stands), but never hurt them below what they reported (a stray hit here).
        var old = global.hp[c];
        var nw = global.mp_rhp[s];
        if (global.mp_rhp_known[s] == 1)
            global.mp_rhp_known[s] = 2;
        else if (old >= nw)
            continue;
        if (old == nw)
            continue;
        global.hp[c] = nw;
        mp_log("hp apply slot=" + string(s) + " " + string(old) + "->" + string(nw) + " (" + typeof(nw) + ")");
        changed = true;
        var inst = global.charinstance[s];
        if (nw < old && instance_exists(inst))
        {
            with (inst)
            {
                hurt = 1;
                hurttimer = 0;
            }
            var dw = instance_create(inst.x, (inst.y + inst.myheight) - 24, obj_dmgwriter);
            dw.damage = old - nw;
            if (nw <= 0)
                dw.type = 4;
        }
        if (nw <= 0 && old > 0)
            scr_dead(s);
        if (nw > 0 && old <= 0)
            mp_ch_revive(s);
    }
    if (changed)
    {
        var alive = false;
        for (var s2 = 0; s2 < 3; s2++)
        {
            if (global.char[s2] != 0 && global.hp[global.char[s2]] > 0)
                alive = true;
        }
        if (!alive)
            scr_gameover();
    }
}

// Prepended to scr_damage: a bullet that hits my SOUL hurts the hero I play.
// Returns the slot to damage, or -1 if I play nobody in this battle.
function mp_damage_target(t)
{
    if (!mp_battle_on())
        return t;
    var mine = [];
    for (var s = 0; s < 3; s++)
    {
        if (global.char[s] != 0 && global.mp_owner[s] == global.mp_myid)
            mine[array_length(mine)] = s;
    }
    var n = array_length(mine);
    if (n == 0)
        return -1;
    if (t == 3)
    {
        if (n == mp_party_size())
            return 3;
        t = mine[0];
    }
    for (var k = 0; k < n; k++)
    {
        if (mine[k] == t && global.hp[global.char[t]] > 0)
            return t;
    }
    // Prefer one of my heroes that is still standing. If all of mine are down, the hit is
    // absorbed: it must never spill over onto a hero another player controls.
    for (var k2 = 0; k2 < n; k2++)
    {
        if (global.hp[global.char[mine[k2]]] > 0)
            return mine[k2];
    }
    return -1;
}

function mp_party_size()
{
    var n = 0;
    for (var s = 0; s < 3; s++)
    {
        if (global.char[s] != 0)
            n++;
    }
    return n;
}

// A SOUL that controls no standing hero was hit: no hero takes damage. A downed player's SOUL
// still flashes; a watcher's (nobody of theirs in the battle) shows nothing at all.
function mp_damage_spectator()
{
    if (mp_my_slot_count() == 0)
        return;
    if (global.inv < 0)
    {
        global.inv = global.invc * 40;
        snd_play(snd_hurt1);
    }
}

// ---------------------------------------------------------------- attack timing (QTE)

function mp_qte_mine(slot)
{
    return mp_slot_mine(slot);
}

// Called before a hero's attack is triggered by obj_attackpress.
function mp_qte_report(slot, pts)
{
    mp_log("qte attack slot=" + string(slot) + " pts=" + string(pts) + " mine=" + string(mp_slot_mine(slot)));
    if (!mp_battle_on() || !mp_slot_mine(slot))
        return;
    mp_begin(42);
    mp_wu16(global.mp_bid);
    mp_wu16(global.mp_bturn);
    mp_wu8(slot);
    mp_ws16(pts);
    mp_send();
}

// Can a bolt of this slot run out (miss) locally? Remote players' bolts wait for their result.
function mp_qte_canexpire(slot)
{
    if (!mp_battle_on() || mp_slot_mine(slot))
        return true;
    return false;
}

// Called each frame inside obj_attackpress: applies remote players' attack results.
function mp_qte_apply()
{
    if (!mp_battle_on())
        return;
    if (global.mp_qte_since == 0 || (current_time - global.mp_qte_since) > 600000)
        global.mp_qte_since = current_time;
    var timeout = (current_time - global.mp_qte_since) > 20000;
    for (var s = 0; s < 3; s++)
    {
        if (mp_slot_mine(s) || havechar[s] == 0 || attacked[s] == 1)
            continue;
        var key = (global.mp_bturn * 4) + s;
        var have = ds_map_exists(global.mp_qte, key);
        if (have || timeout)
        {
            var pts = 0;
            if (have)
                pts = ds_map_find_value(global.mp_qte, key);
            points[s] = pts;
            for (var i = 0; i < bolttotal; i++)
            {
                if (boltchar[i] == s && boltalive[i] == 1)
                {
                    boltalive[i] = 0;
                    if (pts > 0)
                    {
                        var bb = instance_create((x + 80 + (boltframe[i] * boltspeed)) - (boltx * boltspeed), y + (38 * s), obj_burstbolt);
                        bb.image_blend = boltcolor[s];
                    }
                }
            }
        }
    }
}

function mp_qte_done()
{
    mp_log("attackpress created");
    global.mp_qte_since = 0;
}

function mp_qte_waiting_name()
{
    if (!instance_exists(obj_attackpress))
        return "";
    var nm = "";
    with (obj_attackpress)
    {
        for (var s = 0; s < 3; s++)
        {
            if (havechar[s] == 1 && attacked[s] == 0 && !mp_slot_mine(s) && (boltx - 40) > 0)
                nm = global.mp_pname[global.mp_owner[s]];
        }
    }
    return nm;
}

// Who the turn barrier is waiting for: computed by the host, sent to the others (type 35).
function mp_bwait_names()
{
    if (global.mp_role != 1)
    {
        if ((current_time - global.mp_bwait_names_time) < 2500)
            return global.mp_bwait_names;
        return "";
    }
    var names = "";
    for (var i = 1; i < 8; i++)
    {
        if (global.mp_pconn[i] && !(global.mp_tdone_bid[i] == global.mp_bid && global.mp_tdone_turn[i] >= global.mp_bwait_turn))
        {
            if (names != "")
                names += ", ";
            names += global.mp_pname[i];
        }
    }
    return names;
}

function mp_battle_status()
{
    if (!mp_battle_on())
        return "";
    if (global.mp_bwait)
    {
        var names = mp_bwait_names();
        if (names != "")
            return "Waiting for " + names + "...";
        return "Waiting for other players...";
    }
    var q = mp_qte_waiting_name();
    if (q != "")
        return "Waiting for " + q + "'s attack...";
    if (global.myfight == 0 && global.mnfight == 0 && global.charturn < 3)
    {
        var o = global.mp_owner[global.charturn];
        var cn = mp_char_name(global.char[global.charturn]);
        if (o == global.mp_myid)
            return "Your turn: choose " + cn + "'s action!";
        if (o < 8 && global.mp_pconn[o])
            return global.mp_pname[o] + " is choosing for " + cn + "...";
    }
    if (mp_my_slot_count() == 0)
    {
        for (var s = 0; s < 3; s++)
        {
            var o2 = global.mp_owner[s];
            if (global.char[s] == global.mp_cfg_char && o2 < 8 && o2 != global.mp_myid && global.mp_pconn[o2])
                return "Watching: " + global.mp_pname[o2] + " plays " + mp_char_name(global.mp_cfg_char) + " in this battle. No need to dodge.";
        }
        return "Watching: " + mp_char_name(global.mp_cfg_char) + " is not in this battle. No need to dodge.";
    }
    return "";
}

// How many party slots I control in this battle (0: I only watch).
function mp_my_slot_count()
{
    var mine = 0;
    for (var s = 0; s < 3; s++)
    {
        if (global.char[s] != 0 && global.mp_owner[s] == global.mp_myid)
            mine++;
    }
    return mine;
}

// An enemy the host already defeated/spared is still here (desync): defeat it locally.
function mp_ch_remove_monster(s)
{
    mp_log("removing desynced enemy " + string(s));
    if (instance_exists(global.monsterinstance[s]))
    {
        with (global.monsterinstance[s])
            scr_monsterdefeat();
    }
    global.monster[s] = 0;
}

// Prepended to scr_gameover: everyone in this battle goes down together.
function mp_on_gameover()
{
    if (!variable_global_exists("mp_inited") || !mp_battle_on() || global.mp_gameover)
        return;
    global.mp_gameover = 1;
    mp_battle_send_hp();
    mp_begin(46);
    mp_wu16(global.mp_bid);
    mp_send();
    mp_flush();
}

// Client: if the host is no longer in this battle, stop waiting and carry on alone.
function mp_client_gate_fallback()
{
    if (global.mp_role != 2 || !global.mp_bwait)
        return;
    var waited = current_time - global.mp_bwait_since;
    var hostgone = (global.mp_pstate[0] & 1) == 0 && (current_time - global.mp_ppostime[0]) < 5000;
    if ((hostgone && waited > 5000) || waited > 90000)
    {
        mp_log("host left the battle; continuing alone");
        mp_notify("Host is no longer in this battle - continuing on your own.");
        for (var s = 0; s < 3; s++)
            global.mp_owner[s] = global.mp_myid;
        var st = [global.mp_bid, global.mp_bwait_turn, global.tension];
        for (var s2 = 0; s2 < 3; s2++)
        {
            st[3 + s2] = global.mp_myid;
            st[6 + s2] = 0;
            if (global.char[s2] > 0)
                st[6 + s2] = global.hp[global.char[s2]];
            st[9 + s2] = global.monsterhp[s2];
            st[12 + s2] = global.mercymod[s2];
            st[15 + s2] = global.monster[s2];
        }
        global.mp_b_active = 0;
        global.mp_bwait = 1;
        global.mp_bgate_open = 1;
        with (obj_battlecontroller)
        {
            reset = 0;
            alarm[2] = -1;
            scr_mnendturn();
        }
        global.mp_bgate_open = 0;
        global.mp_bwait = 0;
    }
}

// Starts global.encounterno exactly like an overworld enemy would (same music choice and
// "!" horn intro in every chapter) by spawning an invisible enemy that was just touched.
function mp_battle_force_start()
{
    var px = 0;
    var py = 0;
    if (instance_exists(obj_mainchara))
    {
        px = obj_mainchara.x;
        py = obj_mainchara.y;
    }
    global.interact = 0;
    var e = instance_create(px, py, obj_testoverworldenemy);
    e.visible = 0;
    e.speed = 0;
    with (e)
        event_user(0);
}

function mp_ch_revive(slot)
{
    scr_revive(slot);
}

// Appended to obj_heart's Draw: when every hero I play is down, or I play nobody in this battle,
// my SOUL is shown dimmed with a "DOWN" or "WATCHING" label (it still moves, but nothing
// happens when it is hit).
function mp_heart_draw_down()
{
    if (!variable_global_exists("mp_inited") || !mp_battle_on())
        return;
    var mine = 0;
    var up = 0;
    for (var s = 0; s < 3; s++)
    {
        if (global.char[s] != 0 && global.mp_owner[s] == global.mp_myid)
        {
            mine++;
            if (global.hp[global.char[s]] > 0)
                up++;
        }
    }
    if (mine > 0 && up > 0)
        return;
    // Nobody of mine in this battle: the SOUL is only there to watch the attacks.
    var label = mine == 0 ? "WATCHING" : "DOWN";
    var oc = draw_get_color();
    var oa = draw_get_alpha();
    var of = draw_get_font();
    var oh = draw_get_halign();
    var ov = draw_get_valign();
    draw_sprite_ext(sprite_index, image_index, x, y, image_xscale, image_yscale, image_angle, c_black, 0.6);
    if (global.mp_font_small >= 0)
        draw_set_font(global.mp_font_small);
    draw_set_halign(fa_center);
    draw_set_valign(fa_bottom);
    draw_set_alpha(1);
    draw_text_transformed_color(x + 9 + 1, y - 4 + 1, label, 1, 1, 0, c_black, c_black, c_black, c_black, 1);
    draw_text_transformed_color(x + 9, y - 4, label, 1, 1, 0, c_ltgray, c_ltgray, c_ltgray, c_ltgray, 1);
    draw_set_font(of);
    draw_set_halign(oh);
    draw_set_valign(ov);
    draw_set_color(oc);
    draw_set_alpha(oa);
}

// Prepended to scr_damage outside battles. HP is shared, so another player's hit can take one of
// my heroes to 0 HP without the game's own handling having run here. Outside battles the game
// never has a hero at 0 HP (that is a Game Over: scr_damage's target code looks for another
// hero, whose instance may not exist, and crashes), so when that has happened the Game Over
// is what has to run. Returns true then.
function mp_overworld_all_down()
{
    if (!variable_global_exists("mp_inited") || !mp_on() || mp_battle_on() || mp_in_battle_scene())
        return false;
    for (var s = 0; s < 3; s++)
    {
        if (global.char[s] != 0 && global.hp[global.char[s]] <= 0)
            return true;
    }
    return false;
}
