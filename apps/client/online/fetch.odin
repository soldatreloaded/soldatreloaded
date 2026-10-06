package online

import "core:crypto/sha2"
import "core:os"
import "core:strings"

import sim "../../../core/game"
import network "../../../core/network"
import "../../../core/utils"

// The round's map: the copy here whose .pms has the hash the server named, or else the
// server's own, fetched in parts and kept. A map is looked for in data/maps first, then
// among the maps downloaded before (DOWNLOADS_DIR/maps); one fetched goes there, so a
// server's version of a map never takes the place of the one the game came with. It is
// asked for FETCH_AHEAD parts at a time, more as they come, and checked against the hash
// before it is kept. Snapshots wait while it comes, and nothing is said of my soldier:
// the server holds it still.

DOWNLOADS_DIR :: sim.DATA_DIR + "/downloads" // a data folder of its own: maps/ under it
FETCH_AHEAD :: 64 // parts asked for ahead of the one awaited: some 64 KB in flight
FETCH_STEP :: 32  // asked for again once this many of them have come

Fetch :: struct {
	on:    bool,
	round: u16,
	name:  network.Map_Name,
	hash:  [network.MAP_HASH_SIZE]u8,
	data:  []u8, // the map as it comes
	total: u32,  // its bytes, as the first part said; 0 before
	next:  u32,  // the part awaited
	asked: u32,  // the parts asked for, from the first
	told:  int,  // the quarters of it said
}

// How much of it has come, 0 to 1.
fetch_share :: proc(f: ^Fetch) -> f32 {
	if f.total == 0 do return 0
	return min(f32(u64(f.next) * network.MAP_PART) / f32(f.total), 1)
}

@(private = "package")
fetch_stop :: proc(f: ^Fetch) {
	delete(f.data)
	f^ = {}
}

// The data folder that holds `name` as the server has it: by its hash, or any copy of
// that name with `any_copy` (a demo's, or a hash of zeros).
@(private = "package")
map_here :: proc(name: string, hash: [network.MAP_HASH_SIZE]u8, any_copy := false) -> (dir: string, ok: bool) {
	for folder in ([?]string{sim.DATA_DIR, DOWNLOADS_DIR}) {
		data, err := os.read_entire_file(map_path(folder, name), context.temp_allocator)
		if err != nil do continue
		if any_copy || hash == {} || hash_of(data) == hash do return folder, true
	}
	return "", false
}

@(private = "package")
fetch_start :: proc(n: ^Line, m: ^network.Msg_Map) {
	f := &n.fetch
	fetch_stop(f)
	f^ = {on = true, round = m.round, name = m.map_name, hash = m.hash}
	say(n, .Client, "Downloading map %s...", utils.short_string_text(&f.name))
	fetch_ask(n, FETCH_AHEAD)
}

// A part come: kept where it goes, the next asked for, and the map whole at the last.
@(private = "package")
fetch_part :: proc(n: ^Line, p: ^network.Msg_Map_Part) {
	f := &n.fetch
	if !f.on || p.round != f.round || p.part != f.next do return
	if f.data == nil {
		if p.total == 0 || p.total > network.MAP_MAX {
			fetch_fail(n, "the server's map is too large")
			return
		}
		f.data = make([]u8, p.total)
		f.total = p.total
	}
	at := int(p.part) * network.MAP_PART
	if p.total != f.total || at + int(p.size) > int(f.total) do return
	copy(f.data[at:], p.data[:p.size])
	f.next += 1
	got := at + int(p.size)
	quarter := got * 4 / int(f.total)
	if quarter > f.told && quarter < 4 {
		f.told = quarter
		say(n, .Client, "Downloading map %s: %d%%", utils.short_string_text(&f.name), quarter * 25)
	}
	if got == int(f.total) {
		fetch_done(n)
		return
	}
	parts := (f.total + network.MAP_PART - 1) / network.MAP_PART
	if f.asked < parts && f.asked - f.next <= FETCH_AHEAD - FETCH_STEP do fetch_ask(n, FETCH_STEP)
}

@(private = "file")
fetch_ask :: proc(n: ^Line, count: u32) {
	f := &n.fetch
	m := network.Msg_Map_Fetch{round = f.round, part = f.asked, count = count}
	network.net_send_message(n.link.peer, .Map_Fetch, network.msg_map_fetch, &m)
	f.asked += count
}

// The map whole: kept among the downloads once it is the one the server named, written
// beside its place first and moved in, and the world made of it.
@(private = "file")
fetch_done :: proc(n: ^Line) {
	f := &n.fetch
	name := utils.short_string_text(&f.name)
	if f.hash != {} && hash_of(f.data) != f.hash {
		fetch_fail(n, "what came isn't the server's map")
		return
	}
	path := map_path(DOWNLOADS_DIR, name)
	part := utils.temp_path(DOWNLOADS_DIR, "maps", "download.part")
	os.make_directory_all(utils.temp_path(DOWNLOADS_DIR, "maps"))
	if !utils.write_file(part, f.data) {
		fetch_fail(n, "it couldn't be written into " + DOWNLOADS_DIR + "/maps")
		return
	}
	os.remove(path) // another version of the map, downloaded before
	if os.rename(part, path) != nil {
		os.remove(part)
		fetch_fail(n, "it couldn't be put in " + DOWNLOADS_DIR + "/maps")
		return
	}
	say(n, .Client, "Downloaded map %s (%d KB)", name, (f.total + 1023) / 1024)
	fetch_stop(f)
	n.map_dir = DOWNLOADS_DIR
	n.mapped = true // the world is made of it now
}

@(private = "file")
fetch_fail :: proc(n: ^Line, why: string) {
	say(n, .Warning, "Couldn't download map %s: %s", utils.short_string_text(&n.fetch.name), why)
	fetch_stop(&n.fetch)
	line_disconnect(n)
}

@(private = "file")
map_path :: proc(dir, name: string) -> string {
	return utils.temp_path(dir, "maps", strings.concatenate({name, ".pms"}, context.temp_allocator))
}

// A map's .pms, SHA-256, as the server names it.
@(private = "file")
hash_of :: proc(data: []u8) -> (hash: [network.MAP_HASH_SIZE]u8) {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sha2.final(&ctx, hash[:])
	return
}

// Whether a copy of the map `name` is here, any copy: what a demo plays on.
line_map_present :: proc(name: string) -> bool {
	_, here := map_here(name, {}, any_copy = true)
	return here
}
