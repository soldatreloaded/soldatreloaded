package network

import "core:strings"

import "../utils"

// The query: a server asked what it is playing, out of band, on its game port, by
// anyone (a server browser pinging it, the lobby checking it can be reached). One UDP
// datagram each way, outside ENet; the transport catches them before ENet sees them
// (net_answer_queries).
//
// Plain bytes, little-endian, not the game's bit-packed wire: the lobby reads these
// too, in another language, and the layout must hold still while the game's moves.
//
//   request  FF FF FF FF 'B' 'S' 'Q' 'i'  nonce:u32  zeros to QUERY_REQUEST_SIZE
//   reply    FF FF FF FF 'B' 'S' 'R' 'i'  nonce:u32  protocol:u16
//            players:u8 bots:u8 max_players:u8 mode:u8 flags:u8
//            hostname:(len:u8, bytes)  map:(len:u8, bytes)
//
// A request is padded to at least as long as any reply, so a forged source address
// gets its victim no more bytes than the forger sent. The nonce is the asker's, echoed,
// so a reply is matched to its request. Four 0xFF bytes in front are a header ENet
// itself never sends: a peer of 0xFFF with the compressed flag, which a host without a
// compressor (ours) drops.

// The lobby that lists the servers (the soldatreloaded-lobby repository): where a server
// says it is up and where the browser asks for the list.
LOBBY_URL :: "https://sr-lobby.fly.dev"

QUERY_REQUEST_SIZE :: 128
// The longest strings the reply carries: the C game's NUL-terminated buffers less the NUL,
// which the lobby holds a reply to. One longer and the lobby can't read it, and refuses
// the server as if it couldn't be reached.
QUERY_HOSTNAME_MAX :: 23
QUERY_MAP_MAX :: 63
QUERY_REPLY_MAX :: 12 + 2 + 5 + 1 + QUERY_HOSTNAME_MAX + 1 + QUERY_MAP_MAX
QUERY_FLAG_PASSWORD :: 1
QUERY_MODE_CTF :: 1 // capture the flag, as the C server and the lobby number the modes

#assert(QUERY_REPLY_MAX <= QUERY_REQUEST_SIZE, "a reply is never longer than the request it answers")

Server_Info :: struct {
	protocol:    u16,  // VERSION: whether this client can join it
	players:     u8,   // people, bots apart
	bots:        u8,
	max_players: u8,
	mode:        u8,   // QUERY_MODE_CTF from this game; another server's may be another
	password:    bool,
	hostname:    Name,
	map_name:    Map_Name,
}

@(private = "file")
MAGIC := [4]u8{0xFF, 0xFF, 0xFF, 0xFF}
@(private = "file")
REQUEST := [4]u8{'B', 'S', 'Q', 'i'}
@(private = "file")
REPLY := [4]u8{'B', 'S', 'R', 'i'}

@(private = "file")
put_u32 :: proc(p: []u8, v: u32) {
	p[0] = u8(v)
	p[1] = u8(v >> 8)
	p[2] = u8(v >> 16)
	p[3] = u8(v >> 24)
}

@(private = "file")
get_u32 :: proc(p: []u8) -> u32 {
	return u32(p[0]) | u32(p[1]) << 8 | u32(p[2]) << 16 | u32(p[3]) << 24
}

// The four 0xFF bytes in front: one of ours, whatever follows, and not ENet's.
query_is_query :: proc(data: []u8) -> bool {
	return len(data) >= 4 && data[0] == 0xFF && data[1] == 0xFF && data[2] == 0xFF && data[3] == 0xFF
}

// QUERY_REQUEST_SIZE bytes into `out`; nothing if it hasn't the room.
query_write_request :: proc(out: []u8, nonce: u32) -> []u8 {
	if len(out) < QUERY_REQUEST_SIZE do return nil
	request := out[:QUERY_REQUEST_SIZE]
	for &byte in request do byte = 0
	copy(request, MAGIC[:])
	copy(request[4:], REQUEST[:])
	put_u32(request[8:], nonce)
	return request
}

// A request, padded as it must be: true, with its nonce.
query_read_request :: proc(data: []u8) -> (nonce: u32, ok: bool) {
	if len(data) < QUERY_REQUEST_SIZE || !query_is_query(data) || string(data[4:8]) != string(REQUEST[:]) do return
	return get_u32(data[8:]), true
}

// A string as its length and its bytes, cut to `max` bytes.
@(private = "file")
put_string :: proc(p: []u8, s: ^utils.Short_String($N), max: int) -> int {
	text := utils.short_string_text(s)
	if len(text) > max do text = text[:max]
	p[0] = u8(len(text))
	copy(p[1:], text)
	return 1 + len(text)
}

// The reply's bytes into `out` (QUERY_REPLY_MAX is room enough); nothing if it hasn't
// the room.
query_write_reply :: proc(out: []u8, nonce: u32, info: ^Server_Info) -> []u8 {
	if len(out) < QUERY_REPLY_MAX do return nil
	copy(out, MAGIC[:])
	copy(out[4:], REPLY[:])
	put_u32(out[8:], nonce)
	n := 12
	out[n] = u8(info.protocol)
	out[n + 1] = u8(info.protocol >> 8)
	out[n + 2] = info.players
	out[n + 3] = info.bots
	out[n + 4] = info.max_players
	out[n + 5] = info.mode
	out[n + 6] = QUERY_FLAG_PASSWORD if info.password else 0
	n += 7
	n += put_string(out[n:], &info.hostname, QUERY_HOSTNAME_MAX)
	n += put_string(out[n:], &info.map_name, QUERY_MAP_MAX)
	return out[:n]
}

// A string as put_string lays it: false if it runs past the end or past `max`, as the
// lobby reads it.
@(private = "file")
get_string :: proc(p: ^[]u8, s: ^utils.Short_String($N), max: int) -> bool {
	if len(p) == 0 do return false
	n := int(p[0])
	if n > max || len(p) - 1 < n do return false
	utils.short_string_set(s, string(p[1:][:n]))
	p^ = p[1 + n:]
	return true
}

// A reply to the request with `nonce`, whole and nothing after: true, with what it says.
query_read_reply :: proc(data: []u8, nonce: u32) -> (info: Server_Info, ok: bool) {
	if len(data) < 19 || !query_is_query(data) || string(data[4:8]) != string(REPLY[:]) || get_u32(data[8:]) != nonce do return
	p := data[12:]
	info.protocol = u16(p[0]) | u16(p[1]) << 8
	info.players = p[2]
	info.bots = p[3]
	info.max_players = p[4]
	info.mode = p[5]
	info.password = p[6] & QUERY_FLAG_PASSWORD != 0
	p = p[7:]
	ok = get_string(&p, &info.hostname, QUERY_HOSTNAME_MAX) && get_string(&p, &info.map_name, QUERY_MAP_MAX) && len(p) == 0
	return
}

// ---------------------------------------------------------------------------------
// The lobby's list

// A server on the lobby's list: where to ask it.
Query_Address :: struct {
	ip:   utils.Short_String(15), // dotted IPv4
	port: u16,
}

// The lobby's list as its servers.txt gives it, "1.2.3.4:23073" a line, into `out`: how
// many, as many as fit. A line that isn't an IPv4 address and a port is passed over.
query_parse_list :: proc(text: string, out: []Query_Address) -> (count: int) {
	text := text
	for raw in strings.split_lines_iterator(&text) {
		if count == len(out) do break
		line := strings.trim_right(raw, "\r")
		colon := strings.last_index_byte(line, ':')
		if colon < 0 || !is_ipv4(line[:colon]) do continue
		port, is_port := port_parse(line[colon + 1:])
		if !is_port do continue
		out[count] = {ip = utils.short_string(15, line[:colon]), port = port}
		count += 1
	}
	return
}

// Four numbers to 255, dotted, each of one to three digits.
@(private = "file")
is_ipv4 :: proc(s: string) -> bool {
	rest := s
	parts := 0
	for part in strings.split_iterator(&rest, ".") {
		if len(part) == 0 || len(part) > 3 do return false
		v := 0
		for c in part {
			if c < '0' || c > '9' do return false
			v = v * 10 + int(c - '0')
		}
		if v > 255 do return false
		parts += 1
	}
	return parts == 4
}

// A port, 1 to 65535, its digits alone.
@(private = "file")
port_parse :: proc(s: string) -> (port: u16, ok: bool) {
	if len(s) == 0 || len(s) > 5 do return
	v := 0
	for c in s {
		if c < '0' || c > '9' do return
		v = v * 10 + int(c - '0')
	}
	if v < 1 || v > 65535 do return
	return u16(v), true
}
