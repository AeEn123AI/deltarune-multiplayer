// DELTARUNE Multiplayer - network layer: reliable UDP.
//
// Everything travels over one UDP socket. Each datagram (<= 1200 bytes) is:
//   u8 0xD7 | u16 ack | u32 ackbits | records...
//   record: u8 kind (1 reliable, 2 unreliable) | u16 seq | u16 len | frame
//   frame:  u8 type | u8 sender | payload
// ack = last reliable seq received in order; bit i of ackbits = seq ack+2+i also received.
// Reliable records are retransmitted until acknowledged and delivered in order.
// Unreliable records (position updates) are delivered only if newer than the last one.
// The hub (host) forwards every frame of type >= 8 to all other peers.
// Types below 8 are link-level and never forwarded.

function mp_net_init()
{
    global.mp_role = 0;           // 0 = offline, 1 = host (hub + authority), 2 = client
    global.mp_linkstate = 0;      // client: 0 idle, 2 handshaking, 3 joined
    global.mp_usock = -1;
    global.mp_hub = -1;           // client: the peer struct for the host
    global.mp_peers = ds_map_create(); // "ip:port" -> peer struct
    global.mp_myid = 0;
    global.mp_seed = 0;
    global.mp_msg = buffer_create(2048, buffer_grow, 1);
    global.mp_pkt = buffer_create(1500, buffer_fixed, 1);
    global.mp_tmp = buffer_create(2048, buffer_grow, 1);
    global.mp_rtt = 0;
    global.mp_lastping = 0;
    global.mp_bytes_in = 0;
    global.mp_bytes_out = 0;
    global.mp_kbps_in = 0;
    global.mp_kbps_out = 0;
    global.mp_bw_time = current_time;
    global.mp_join_retries = 0;
    global.mp_join_retry_at = 0;
    global.mp_connect_time = 0;
    global.mp_welcome_time = 0;
}

function mp_seq_after(a, b)
{
    var d = (a - b + 65536) mod 65536;
    return d != 0 && d < 32768;
}

function mp_peer_new(ip, port)
{
    var p = {
        ip: ip,
        port: port,
        pid: -1,
        sseq: 0,
        sendq: ds_list_create(),
        unrel: ds_list_create(),
        useq: 0,
        rexp: 0,
        rbuf: ds_map_create(),
        lastu: -1,
        ackdirty: false,
        lastrecv: current_time,
        lastsent: 0,
        srtt: 300,
        created: current_time
    };
    ds_map_set(global.mp_peers, ip + ":" + string(port), p);
    return p;
}

function mp_peer_free(p)
{
    for (var i = 0; i < ds_list_size(p.sendq); i++)
    {
        var e = ds_list_find_value(p.sendq, i);
        buffer_delete(e[1]);
    }
    ds_list_destroy(p.sendq);
    for (var j = 0; j < ds_list_size(p.unrel); j++)
        buffer_delete(ds_list_find_value(p.unrel, j));
    ds_list_destroy(p.unrel);
    var k = ds_map_find_first(p.rbuf);
    while (!is_undefined(k))
    {
        buffer_delete(ds_map_find_value(p.rbuf, k));
        k = ds_map_find_next(p.rbuf, k);
    }
    ds_map_destroy(p.rbuf);
    ds_map_delete(global.mp_peers, p.ip + ":" + string(p.port));
}

// ---------------------------------------------------------------- connection management

function mp_host_start(port)
{
    mp_disconnect("");
    global.mp_usock = network_create_socket_ext(network_socket_udp, port);
    if (global.mp_usock < 0)
    {
        mp_notify("Could not host on UDP port " + string(port) + " (in use?)");
        global.mp_usock = -1;
        return 0;
    }
    global.mp_role = 1;
    global.mp_linkstate = 3;
    global.mp_myid = 0;
    global.mp_seed = (current_time * 7919 + get_timer()) mod 1000000007;
    mp_players_clear();
    mp_player_set(0, 1, global.mp_cfg_name, global.mp_cfg_char);
    mp_on_session_start();
    mp_notify("Hosting on UDP port " + string(port) + ". Waiting for players...");
    return 1;
}

function mp_join(ip, port)
{
    mp_disconnect("");
    global.mp_usock = network_create_socket(network_socket_udp);
    if (global.mp_usock < 0)
    {
        mp_notify("Could not create socket");
        return 0;
    }
    global.mp_role = 2;
    global.mp_linkstate = 2;
    global.mp_join_ip = ip;
    global.mp_join_port = port;
    global.mp_connect_time = current_time;
    global.mp_hub = mp_peer_new(ip, port);
    global.mp_hub.pid = 0;
    mp_begin(1); // HELLO
    mp_wstr("DRMP");
    mp_wu16(global.mp_version);
    mp_wu8(global.mp_chapter);
    mp_wstr(global.mp_cfg_name);
    mp_wu8(global.mp_cfg_char);
    mp_send_to(global.mp_hub);
    mp_notify("Contacting " + ip + ":" + string(port) + " ...");
    return 1;
}

function mp_disconnect(reason)
{
    var was = global.mp_role;
    if (global.mp_usock >= 0)
    {
        // Tell everyone we are leaving (best effort, unreliable).
        var k = ds_map_find_first(global.mp_peers);
        while (!is_undefined(k))
        {
            var p = ds_map_find_value(global.mp_peers, k);
            mp_begin(7);
            mp_send_unreliable_to(p);
            k = ds_map_find_next(global.mp_peers, k);
        }
        mp_flush();
        network_destroy(global.mp_usock);
    }
    var k2 = ds_map_find_first(global.mp_peers);
    while (!is_undefined(k2))
    {
        mp_peer_free(ds_map_find_value(global.mp_peers, k2));
        k2 = ds_map_find_first(global.mp_peers);
    }
    global.mp_usock = -1;
    global.mp_hub = -1;
    global.mp_resume_done = 0;
    global.mp_role = 0;
    global.mp_linkstate = 0;
    if (was != 0)
    {
        mp_on_session_end();
        mp_players_clear();
        if (reason != "")
            mp_notify(reason);
    }
}

// ---------------------------------------------------------------- message building

function mp_begin(type)
{
    buffer_seek(global.mp_msg, buffer_seek_start, 0);
    buffer_write(global.mp_msg, buffer_u8, type);
    buffer_write(global.mp_msg, buffer_u8, global.mp_myid);
}

function mp_wu8(v) { buffer_write(global.mp_msg, buffer_u8, clamp(round(v), 0, 255)); }
function mp_ws8(v) { buffer_write(global.mp_msg, buffer_s8, clamp(round(v), -128, 127)); }
function mp_wu16(v) { buffer_write(global.mp_msg, buffer_u16, clamp(round(v), 0, 65535)); }
function mp_ws16(v) { buffer_write(global.mp_msg, buffer_s16, clamp(round(v), -32768, 32767)); }
function mp_ws32(v) { buffer_write(global.mp_msg, buffer_s32, round(v)); }
function mp_wu32(v) { buffer_write(global.mp_msg, buffer_u32, round(v)); }
function mp_wf64(v) { buffer_write(global.mp_msg, buffer_f64, v); }
function mp_wstr(v) { buffer_write(global.mp_msg, buffer_string, string_copy(string(v), 1, 200)); }

// Writes a game value compactly: small integers as s8, integers as s32, other reals as f64, strings as text.
function mp_wval(v)
{
    if (is_string(v))
    {
        mp_wu8(3);
        mp_wstr(v);
    }
    else if (is_real(v) || is_int32(v) || is_int64(v) || is_bool(v))
    {
        if (v == floor(v) && v >= -128 && v <= 127)
        {
            mp_wu8(0);
            mp_ws8(v);
        }
        else if (v == floor(v) && abs(v) < 2000000000)
        {
            mp_wu8(1);
            mp_ws32(v);
        }
        else
        {
            mp_wu8(2);
            mp_wf64(v);
        }
    }
    else
    {
        mp_wu8(0);
        mp_ws8(0);
    }
}

// Numbers read from a buffer are int32: the game divides HP by max HP, and two int32s divide
// as integers (71 / 90 = 0, which drew the HP bar empty). Everything received becomes a real.
function mp_num(v)
{
    if (is_int32(v) || is_int64(v))
        return real(v);
    return v;
}

function mp_rval(b)
{
    var kind = buffer_read(b, buffer_u8);
    if (kind == 0)
        return mp_num(buffer_read(b, buffer_s8));
    if (kind == 1)
        return mp_num(buffer_read(b, buffer_s32));
    if (kind == 2)
        return buffer_read(b, buffer_f64);
    return buffer_read(b, buffer_string);
}

function mp_type_unreliable(type)
{
    return type == 10;
}

// Finishes the current message and sends it to everyone (host: all clients; client: the hub).
function mp_send()
{
    var len = buffer_tell(global.mp_msg);
    var unrel = mp_type_unreliable(buffer_peek(global.mp_msg, 0, buffer_u8));
    if (global.mp_role == 2)
    {
        if (global.mp_linkstate >= 2 && is_struct(global.mp_hub))
            mp_enqueue(global.mp_hub, global.mp_msg, 0, len, unrel);
    }
    else if (global.mp_role == 1)
    {
        var k = ds_map_find_first(global.mp_peers);
        while (!is_undefined(k))
        {
            var p = ds_map_find_value(global.mp_peers, k);
            if (p.pid >= 0)
                mp_enqueue(p, global.mp_msg, 0, len, unrel);
            k = ds_map_find_next(global.mp_peers, k);
        }
    }
}

// Finishes the current message and sends it (reliably) to a single peer.
function mp_send_to(p)
{
    if (is_struct(p))
        mp_enqueue(p, global.mp_msg, 0, buffer_tell(global.mp_msg), false);
}

function mp_send_unreliable_to(p)
{
    if (is_struct(p))
        mp_enqueue(p, global.mp_msg, 0, buffer_tell(global.mp_msg), true);
}

function mp_enqueue(p, src, off, len, unreliable)
{
    if (len > 1150)
    {
        show_debug_message("[MP] message too large, dropped: type " + string(buffer_peek(src, off, buffer_u8)) + " len " + string(len));
        return;
    }
    var b = buffer_create(max(1, len), buffer_fixed, 1);
    buffer_copy(src, off, len, b, 0);
    if (unreliable)
    {
        // Only the newest unreliable message of a kind from a sender matters: drop older ones.
        var type = buffer_peek(src, off, buffer_u8);
        var snd = buffer_peek(src, off + 1, buffer_u8);
        for (var i = ds_list_size(p.unrel) - 1; i >= 0; i--)
        {
            var ob = ds_list_find_value(p.unrel, i);
            if (buffer_peek(ob, 0, buffer_u8) == type && buffer_peek(ob, 1, buffer_u8) == snd)
            {
                buffer_delete(ob);
                ds_list_delete(p.unrel, i);
            }
        }
        ds_list_add(p.unrel, b);
    }
    else
    {
        // [seq, buffer, length, last send time, send count]
        ds_list_add(p.sendq, [p.sseq, b, len, 0, 0]);
        p.sseq = (p.sseq + 1) mod 65536;
    }
}

// ---------------------------------------------------------------- sending datagrams

function mp_peer_rto(p)
{
    return clamp((p.srtt * 2) + 60, 150, 3000);
}

function mp_pkt_begin(p)
{
    var b = global.mp_pkt;
    buffer_seek(b, buffer_seek_start, 0);
    buffer_write(b, buffer_u8, 215);
    buffer_write(b, buffer_u16, (p.rexp + 65535) mod 65536);
    var bits = 0;
    if (ds_map_size(p.rbuf) > 0)
    {
        for (var i = 0; i < 32; i++)
        {
            if (ds_map_exists(p.rbuf, (p.rexp + 1 + i) mod 65536))
                bits |= (1 << i);
        }
    }
    buffer_write(b, buffer_u32, bits);
}

function mp_pkt_send(p)
{
    var n = buffer_tell(global.mp_pkt);
    network_send_udp_raw(global.mp_usock, p.ip, p.port, global.mp_pkt, n);
    global.mp_bytes_out += n + 28;
    p.lastsent = current_time;
    p.ackdirty = false;
}

// Sends queued data for every peer: normally one datagram per peer per frame.
function mp_flush()
{
    if (global.mp_usock < 0)
        return;
    var k = ds_map_find_first(global.mp_peers);
    while (!is_undefined(k))
    {
        var p = ds_map_find_value(global.mp_peers, k);
        k = ds_map_find_next(global.mp_peers, k);
        mp_flush_peer(p);
    }
}

function mp_flush_peer(p)
{
    var now = current_time;
    var rto = mp_peer_rto(p);
    var pk = global.mp_pkt;
    var packets = 0;
    var has = false;
    mp_pkt_begin(p);
    // Reliable: new messages and those whose retransmit timer expired (with backoff).
    // At most 4 datagrams per frame so resends can't flood a slow connection.
    var n = ds_list_size(p.sendq);
    for (var i = 0; i < n; i++)
    {
        var e = ds_list_find_value(p.sendq, i);
        if (e[4] > 0 && (now - e[3]) < (rto * min(e[4], 4)))
            continue;
        if ((buffer_tell(pk) + 5 + e[2]) > 1200)
        {
            if (!has)
                continue;
            mp_pkt_send(p);
            packets += 1;
            if (packets >= 4)
                return;
            mp_pkt_begin(p);
            has = false;
        }
        buffer_write(pk, buffer_u8, 1);
        buffer_write(pk, buffer_u16, e[0]);
        buffer_write(pk, buffer_u16, e[2]);
        buffer_copy(e[1], 0, e[2], pk, buffer_tell(pk));
        buffer_seek(pk, buffer_seek_relative, e[2]);
        ds_list_set(p.sendq, i, [e[0], e[1], e[2], now, e[4] + 1]);
        has = true;
    }
    // Unreliable: newest positions.
    while (ds_list_size(p.unrel) > 0)
    {
        var ub = ds_list_find_value(p.unrel, 0);
        var ul = buffer_get_size(ub);
        if ((buffer_tell(pk) + 5 + ul) > 1200)
        {
            if (!has)
            {
                buffer_delete(ub);
                ds_list_delete(p.unrel, 0);
                continue;
            }
            mp_pkt_send(p);
            packets += 1;
            if (packets >= 4)
                return;
            mp_pkt_begin(p);
            has = false;
        }
        buffer_write(pk, buffer_u8, 2);
        buffer_write(pk, buffer_u16, p.useq);
        buffer_write(pk, buffer_u16, ul);
        buffer_copy(ub, 0, ul, pk, buffer_tell(pk));
        buffer_seek(pk, buffer_seek_relative, ul);
        p.useq = (p.useq + 1) mod 65536;
        buffer_delete(ub);
        ds_list_delete(p.unrel, 0);
        has = true;
    }
    // Pure acknowledgement / keep-alive.
    if (has || p.ackdirty || (now - p.lastsent) > 1000)
        mp_pkt_send(p);
}

// ---------------------------------------------------------------- receiving datagrams

// Called from the controller's Async - Networking event.
function mp_net_async()
{
    if (global.mp_usock < 0)
        return;
    if (ds_map_find_value(async_load, "type") != network_type_data)
        return;
    if (ds_map_find_value(async_load, "id") != global.mp_usock)
        return;
    var b = ds_map_find_value(async_load, "buffer");
    var size = ds_map_find_value(async_load, "size");
    var ip = ds_map_find_value(async_load, "ip");
    var port = ds_map_find_value(async_load, "port");
    global.mp_bytes_in += size + 28;
    if (size < 7 || buffer_peek(b, 0, buffer_u8) != 215)
        return;
    var key = ip + ":" + string(port);
    var p;
    if (ds_map_exists(global.mp_peers, key))
    {
        p = ds_map_find_value(global.mp_peers, key);
    }
    else if (global.mp_role == 2 && is_struct(global.mp_hub) && port == global.mp_hub.port && global.mp_linkstate == 2)
    {
        // The host answered from an address spelled differently than the one we typed
        // (e.g. a hostname): adopt it.
        p = global.mp_hub;
        ds_map_delete(global.mp_peers, p.ip + ":" + string(p.port));
        p.ip = ip;
        ds_map_set(global.mp_peers, key, p);
    }
    else
    {
        if (global.mp_role != 1 || ds_map_size(global.mp_peers) >= 16)
            return;
        p = mp_peer_new(ip, port);
    }
    p.lastrecv = current_time;
    // Acknowledgements.
    var ack = buffer_peek(b, 1, buffer_u16);
    var bits = buffer_peek(b, 3, buffer_u32);
    for (var i = ds_list_size(p.sendq) - 1; i >= 0; i--)
    {
        var e = ds_list_find_value(p.sendq, i);
        if (e[4] == 0)
            continue;
        var acked = !mp_seq_after(e[0], ack);
        if (!acked)
        {
            var d = (e[0] - ack - 2 + 65536) mod 65536;
            if (d < 32 && ((bits >> d) & 1))
                acked = true;
        }
        if (acked)
        {
            if (e[4] == 1)
                p.srtt = (p.srtt * 0.875) + ((current_time - e[3]) * 0.125);
            buffer_delete(e[1]);
            ds_list_delete(p.sendq, i);
        }
    }
    // Records.
    var pos = 7;
    while ((pos + 5) <= size)
    {
        var kind = buffer_peek(b, pos, buffer_u8);
        var seq = buffer_peek(b, pos + 1, buffer_u16);
        var len = buffer_peek(b, pos + 3, buffer_u16);
        pos += 5;
        if ((pos + len) > size || len < 2)
            break;
        if (kind == 1)
        {
            p.ackdirty = true;
            if (seq == p.rexp)
            {
                p.rexp = (p.rexp + 1) mod 65536;
                mp_deliver(p, b, pos, len, false);
                if (!mp_peer_alive(p))
                    return;
                // Deliver anything that was waiting for this one.
                while (ds_map_exists(p.rbuf, p.rexp))
                {
                    var hb = ds_map_find_value(p.rbuf, p.rexp);
                    ds_map_delete(p.rbuf, p.rexp);
                    p.rexp = (p.rexp + 1) mod 65536;
                    mp_deliver(p, hb, 0, buffer_get_size(hb), false);
                    buffer_delete(hb);
                    if (!mp_peer_alive(p))
                        return;
                }
            }
            else if (mp_seq_after(seq, p.rexp) && ((seq - p.rexp + 65536) mod 65536) < 1024 && !ds_map_exists(p.rbuf, seq))
            {
                var cb = buffer_create(len, buffer_fixed, 1);
                buffer_copy(b, pos, len, cb, 0);
                ds_map_set(p.rbuf, seq, cb);
            }
        }
        else if (kind == 2)
        {
            if (p.lastu < 0 || mp_seq_after(seq, p.lastu))
            {
                p.lastu = seq;
                mp_deliver(p, b, pos, len, true);
                if (!mp_peer_alive(p))
                    return;
            }
        }
        pos += len;
    }
}

function mp_peer_alive(p)
{
    return global.mp_usock >= 0 && ds_map_exists(global.mp_peers, p.ip + ":" + string(p.port));
}

// Hands one frame to the game, forwarding it to the other clients first when we are the hub.
function mp_deliver(p, b, off, len, unreliable)
{
    var type = buffer_peek(b, off, buffer_u8);
    if (global.mp_role == 1)
    {
        if (p.pid < 0 && type != 1)
            return;
        if (p.pid >= 0)
        {
            buffer_poke(b, off + 1, buffer_u8, p.pid);
            global.mp_plast[p.pid] = current_time;
            if (type >= 8)
            {
                var k = ds_map_find_first(global.mp_peers);
                while (!is_undefined(k))
                {
                    var q = ds_map_find_value(global.mp_peers, k);
                    if (q != p && q.pid >= 0)
                        mp_enqueue(q, b, off, len, unreliable);
                    k = ds_map_find_next(global.mp_peers, k);
                }
            }
        }
    }
    var tb = global.mp_tmp;
    if (buffer_get_size(tb) < len)
        buffer_resize(tb, len * 2);
    buffer_copy(b, off, len, tb, 0);
    buffer_seek(tb, buffer_seek_start, 2);
    mp_handle(type, buffer_peek(tb, 1, buffer_u8), tb, p, len);
}

function mp_host_drop(p, why)
{
    var pid = p.pid;
    mp_peer_free(p);
    if (pid >= 0 && global.mp_pconn[pid])
    {
        mp_notify(global.mp_pname[pid] + " " + why + ".");
        mp_player_set(pid, 0, global.mp_pname[pid], global.mp_pchar[pid]);
        mp_send_pinfo(pid);
    }
}

// ---------------------------------------------------------------- link-level handlers

// Returns true if the message was a link-level message (handled here).
function mp_handle_link(type, sender, b, p)
{
    if (type == 1 && global.mp_role == 1) // HELLO
    {
        if (p.pid >= 0)
            return true; // duplicate
        var magic = buffer_read(b, buffer_string);
        var ver = buffer_read(b, buffer_u16);
        var ch = buffer_read(b, buffer_u8);
        var nm = buffer_read(b, buffer_string);
        var chr = buffer_read(b, buffer_u8);
        var err = "";
        if (magic != "DRMP" || ver != global.mp_version)
            err = "Mod version mismatch (host v" + string(global.mp_version) + ", you v" + string(ver) + ")";
        else if (ch != global.mp_chapter)
            err = "Host is playing Chapter " + string(global.mp_chapter) + ". Open that chapter to join.";
        var pid = -1;
        if (err == "")
        {
            for (var i = 1; i < 8; i++)
            {
                if (!global.mp_pconn[i])
                {
                    pid = i;
                    break;
                }
            }
            if (pid < 0)
                err = "Session is full.";
        }
        if (err != "")
        {
            mp_begin(4); // KICK
            mp_wstr(err);
            mp_send_unreliable_to(p);
            mp_flush_peer(p);
            mp_peer_free(p);
            return true;
        }
        p.pid = pid;
        mp_player_set(pid, 1, mp_unique_name(nm, pid), chr);
        global.mp_plast[pid] = current_time;
        mp_begin(2); // WELCOME
        mp_wu8(pid);
        mp_wu32(global.mp_seed);
        mp_send_to(p);
        for (var j = 0; j < 8; j++)
        {
            if (global.mp_pconn[j])
            {
                mp_begin(3);
                mp_wu8(j);
                mp_wu8(1);
                mp_wstr(global.mp_pname[j]);
                mp_wu8(global.mp_pchar[j]);
                mp_send_to(p);
            }
        }
        mp_send_pinfo(pid);
        mp_vars_send_full(p);
        mp_send_pos(1, p);
        // Joining while I'm in a battle: come and join it (from the next turn).
        if (global.mp_battle_seen && mp_in_battle_scene())
            mp_send_pull_to(1, p);
        mp_notify(global.mp_pname[pid] + " joined!");
        return true;
    }
    if (type == 2 && global.mp_role == 2) // WELCOME
    {
        if (global.mp_linkstate == 3)
            return true;
        global.mp_myid = buffer_read(b, buffer_u8);
        global.mp_seed = buffer_read(b, buffer_u32);
        global.mp_linkstate = 3;
        global.mp_welcome_time = current_time;
        global.mp_join_retries = 0;
        mp_player_set(global.mp_myid, 1, global.mp_cfg_name, global.mp_cfg_char);
        mp_on_session_start();
        mp_notify("Joined the session!");
        return true;
    }
    if (type == 4 && global.mp_role == 2) // KICK
    {
        global.mp_join_retries = 0;
        mp_disconnect(buffer_read(b, buffer_string));
        return true;
    }
    if (type == 5) // PING (host answers)
    {
        var tm = buffer_read(b, buffer_u32);
        if (global.mp_role == 1)
        {
            mp_begin(6);
            mp_wu32(tm);
            mp_send_unreliable_to(p);
        }
        return true;
    }
    if (type == 6) // PONG
    {
        var tm2 = buffer_read(b, buffer_u32);
        global.mp_rtt = (current_time mod 4000000000) - tm2;
        return true;
    }
    if (type == 7) // BYE
    {
        if (global.mp_role == 1)
            mp_host_drop(p, "left");
        else
            mp_disconnect("The host closed the session.");
        return true;
    }
    return type < 8 && type != 3;
}

// Periodic link maintenance: pings, timeouts, bandwidth stats.
function mp_net_tick()
{
    if (global.mp_role == 2)
    {
        if (global.mp_linkstate == 2 && (current_time - global.mp_connect_time) > 12000)
        {
            mp_disconnect("No answer from " + global.mp_join_ip + ":" + string(global.mp_join_port) + ".");
            if (global.mp_join_retries > 0)
            {
                global.mp_join_retries -= 1;
                global.mp_join_retry_at = current_time + 2000;
            }
            return;
        }
        if (global.mp_linkstate == 3)
        {
            if ((current_time - global.mp_lastping) > 2000)
            {
                global.mp_lastping = current_time;
                mp_begin(5);
                mp_wu32(current_time mod 4000000000);
                mp_send_unreliable_to(global.mp_hub);
            }
            if ((current_time - global.mp_hub.lastrecv) > 30000)
            {
                mp_disconnect("Host stopped responding.");
                return;
            }
            if (ds_list_size(global.mp_hub.sendq) > 4000)
            {
                mp_disconnect("Connection too slow; disconnected.");
                return;
            }
        }
    }
    else if (global.mp_role == 1)
    {
        var k = ds_map_find_first(global.mp_peers);
        while (!is_undefined(k))
        {
            var p = ds_map_find_value(global.mp_peers, k);
            k = ds_map_find_next(global.mp_peers, k);
            if ((current_time - p.lastrecv) > 30000 || ds_list_size(p.sendq) > 4000)
                mp_host_drop(p, "timed out");
            else if (p.pid < 0 && (current_time - p.created) > 10000)
                mp_peer_free(p);
        }
    }
    if ((current_time - global.mp_bw_time) >= 2000)
    {
        var dt = (current_time - global.mp_bw_time) / 1000;
        global.mp_kbps_in = global.mp_bytes_in / dt / 1024;
        global.mp_kbps_out = global.mp_bytes_out / dt / 1024;
        global.mp_bytes_in = 0;
        global.mp_bytes_out = 0;
        global.mp_bw_time = current_time;
    }
}
