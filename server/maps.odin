package server

import "core:log"
import "core:crypto/sha2"

import net "../core/network"
import "../core/utils"

// The round's map as the players hear of it: its name and its hash, told with the
// round; the server's list, which the map window pages; and the map itself, its .pms,
// sent in parts to a player who lacks it.

// The round's map, by its .pms's hash, for the Map to tell: once a round. Zeros, which
// a client takes as any copy, where the file can't be read.
map_identify :: proc(sv: ^Server) {
	delete(sv.map_file)
	sv.map_file = nil
	sv.map_missing = false
	sv.map_hash = {}
	data, found := map_read(sv)
	if !found do return
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sha2.final(&ctx, sv.map_hash[:])
}

// The round's .pms, read once and kept for the round; nothing if it can't be.
@(private = "file")
map_read :: proc(sv: ^Server) -> ([]u8, bool) {
	if sv.map_file != nil do return sv.map_file, true
	if sv.map_missing do return nil, false
	path, found := utils.find_file_any_case(utils.temp_path(sv.options.data_dir, "maps"), server_map(sv), ".pms", context.temp_allocator)
	if found do sv.map_file, found = utils.read_file(path)
	if !found || len(sv.map_file) > net.MAP_MAX {
		delete(sv.map_file)
		sv.map_file = nil
		sv.map_missing = true
		log.warnf("%s can't be sent to the players who lack it", server_map(sv))
		return nil, false
	}
	return sv.map_file, true
}

// The round's map to one peer.
tell_map :: proc(sv: ^Server, peer: net.Peer) {
	m := net.Msg_Map{round = sv.round, map_name = sv.map_name, hash = sv.map_hash}
	utils.short_string_set(&m.hostname, sv.options.config.server.hostname)
	net.net_send_message(peer, .Map, net.msg_map, &m)
}

// The map window asks for the n-th of the server's maps: its name, and how many there
// are (the original's VoteMapReply). Nothing is answered past the end.
map_query :: proc(sv: ^Server, peer: net.Peer, e: ^net.Event) {
	b := net.buffer_reader(e.data[:e.size])
	kind: net.Msg_Kind
	q: net.Msg_Map_Query
	net.msg_kind(&b, &kind)
	net.msg_map_query(&b, &q)
	if !net.buffer_done(&b) do return
	m := net.Msg_Map_Reply{index = q.index}
	if len(sv.maps) > 0 {
		if int(q.index) >= len(sv.maps) do return
		m.count = u16(len(sv.maps))
		utils.short_string_set(&m.map_name, sv.maps[q.index])
	} else { // no list: the map being played is the whole of it
		if q.index > 0 do return
		m.count = 1
		m.map_name = sv.map_name
	}
	net.net_send_message(peer, .Map_Reply, net.msg_map_reply, &m)
}

// A player who lacks the round's map asks for parts of it: each is sent, out of the
// .pms, read on the first ask and kept for the round.
map_fetch :: proc(sv: ^Server, peer: net.Peer, e: ^net.Event) {
	b := net.buffer_reader(e.data[:e.size])
	kind: net.Msg_Kind
	f: net.Msg_Map_Fetch
	net.msg_kind(&b, &kind)
	net.msg_map_fetch(&b, &f)
	if !net.buffer_done(&b) || f.round != sv.round do return // a fetch of a map since changed
	data, found := map_read(sv)
	if !found do return
	if f.part == 0 do log.infof("sending %s (%d KB) to a player who lacks it", server_map(sv), (len(data) + 1023) / 1024)
	for i in 0 ..< f.count {
		at := int(f.part + i) * net.MAP_PART
		if at >= len(data) do break
		part := data[at:min(at + net.MAP_PART, len(data))]
		p := new(net.Msg_Map_Part, context.temp_allocator)
		p^ = {round = sv.round, total = u32(len(data)), part = f.part + i, size = u16(len(part))}
		copy(p.data[:], part)
		net.net_send_message(peer, .Map_Part, net.msg_map_part, p)
	}
}
