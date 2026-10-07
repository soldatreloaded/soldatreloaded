package online

import "core:crypto/sha2"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

import sim "../../../core/game"
import network "../../../core/network"
import "../../../core/utils"

// The round's map: the copy here whose .pms has the hash the server named, or else the
// server's own, fetched in parts and kept; and the map's own art the same way, each file
// by its hash. A map is looked for in data/maps first, then among the maps downloaded
// before (DOWNLOADS_DIR/maps); one fetched goes there, so a server's version of a map
// never takes the place of the one the game came with. Its own art is in a folder of its
// name beside it (data/maps/<name>/, laid out as a mod is: textures/, textures/edges/,
// scenery-gfx/), and what is fetched of it goes to DOWNLOADS_DIR/maps/<name>/ (map_art_dirs).
//
// The art is told after the Map, a Map_Art for each file; once it has all come, what
// isn't here is fetched, a file at a time, each asked for FETCH_AHEAD parts at a time,
// more as they come, and checked against its hash before it is kept. The map is made
// once all is here. Snapshots wait while it comes, and nothing is said of my soldier:
// the server holds it still. A .pms that can't be had ends the joining; an art file
// that can't is passed over, the map drawn without it.

DOWNLOADS_DIR :: sim.DATA_DIR + "/downloads" // a data folder of its own: maps/ under it
FETCH_AHEAD :: 64 // parts asked for ahead of the one awaited: some 64 KB in flight
FETCH_STEP :: 32  // asked for again once this many of them have come

Fetch :: struct {
	round:    u16,
	name:     network.Map_Name,
	hash:     [network.MAP_HASH_SIZE]u8, // the .pms's
	pms:      bool, // the .pms isn't here: it is fetched first
	art:      [dynamic]network.Msg_Map_Art, // the map's own art, as the server told it
	art_told: int,  // how many files of it the Map said
	queue:    [dynamic]u8, // the files to fetch after the one coming, by their `file`
	art_got:  int,  // the art files fetched, and their bytes, for the last word
	art_kb:   int,

	// the file coming
	on:       bool,
	file:     u8,   // 0 the .pms, i + 1 the art's i-th
	data:     []u8, // as it comes
	total:    u32,  // its bytes, as the first part said; 0 before
	next:     u32,  // the part awaited
	asked:    u32,  // the parts asked for, from the first
	told:     int,  // the quarters of it said, for the .pms
}

// How much of the file coming has come, 0 to 1.
fetch_share :: proc(f: ^Fetch) -> f32 {
	if f.total == 0 do return 0
	return min(f32(u64(f.next) * network.MAP_PART) / f32(f.total), 1)
}

// Whether the round's map is still coming: its art being told, or a file fetched. The
// snapshots wait meanwhile.
fetch_busy :: proc(f: ^Fetch) -> bool {
	return f.on || len(f.art) < f.art_told
}

// What is coming, in a line, for the HUD and the menu; empty while nothing is.
fetch_status :: proc(f: ^Fetch) -> string {
	if !f.on do return ""
	name := utils.short_string_text(&f.name)
	if f.file == 0 do return strings.concatenate({"Downloading ", name, "... ", percent(fetch_share(f))}, context.temp_allocator)
	left := len(f.queue) + 1
	return strings.concatenate({"Downloading ", name, "'s images... ", count_text(left), " left"}, context.temp_allocator)
}

@(private = "file")
percent :: proc(share: f32) -> string {
	buf: [8]u8
	return strings.concatenate({strconv.write_int(buf[:], i64(share * 100), 10), "%"}, context.temp_allocator)
}

@(private = "file")
count_text :: proc(n: int) -> string {
	buf: [20]u8
	return strings.clone(strconv.write_int(buf[:], i64(n), 10), context.temp_allocator)
}

@(private = "package")
fetch_stop :: proc(f: ^Fetch) {
	delete(f.data)
	delete(f.art)
	delete(f.queue)
	f^ = {}
}

// The folders the map `name`'s own art is looked for in, the downloaded first: what was
// fetched is the server's, where a copy shipped here may be another's.
map_art_dirs :: proc(name: string) -> [2]string {
	return {utils.temp_path(DOWNLOADS_DIR, "maps", name), utils.temp_path(sim.DATA_DIR, "maps", name)}
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

// A Map heard: the round's map here, or to be fetched, and its art told after it. With
// none told (or a demo, which fetches nothing), the map is had, or fetched, now.
@(private = "package")
fetch_map :: proc(n: ^Line, m: ^network.Msg_Map) {
	f := &n.fetch
	fetch_stop(f)
	name := utils.short_string_text(&m.map_name)
	if !name_safe(name) {
		say(n, .Warning, "The server's map has a name no file can have: %s", name)
		line_disconnect(n)
		return
	}
	f.round, f.name, f.hash = m.round, m.map_name, m.hash
	f.art_told = 0 if n.playback else int(m.art)
	dir, here := map_here(name, m.hash, any_copy = n.playback)
	f.pms = !here
	n.map_dir = dir if here else DOWNLOADS_DIR
	if f.art_told == 0 do fetch_begin(n)
}

// One of the map's art files told: kept, and once all have come, what isn't here fetched.
@(private = "package")
fetch_art_told :: proc(n: ^Line, a: ^network.Msg_Map_Art) {
	f := &n.fetch
	if a.round != f.round || len(f.art) >= f.art_told || int(a.index) != len(f.art) do return
	append(&f.art, a^)
	if len(f.art) == f.art_told do fetch_begin(n)
}

// What of the map isn't here, fetched in turn: the .pms, then the art. With nothing to
// fetch, the world is made of it now.
@(private = "file")
fetch_begin :: proc(n: ^Line) {
	f := &n.fetch
	clear(&f.queue)
	if f.pms do append(&f.queue, 0)
	name := utils.short_string_text(&f.name)
	missing := 0
	for &art, i in f.art {
		path := utils.short_string_text(&art.path)
		if !art_path_safe(path) || art_here(name, &art) do continue
		append(&f.queue, u8(i + 1))
		missing += 1
	}
	if len(f.queue) == 0 {
		n.mapped = true
		return
	}
	if f.pms do say(n, .Client, "Downloading map %s...", name)
	if missing > 0 do say(n, .Client, "Downloading %d of map %s's own images...", missing, name)
	fetch_next(n)
}

// The next file in the queue asked for; or, the queue done, the world made.
@(private = "file")
fetch_next :: proc(n: ^Line) {
	f := &n.fetch
	delete(f.data)
	f.data, f.total, f.next, f.asked, f.told = nil, 0, 0, 0, 0
	if len(f.queue) == 0 {
		if f.art_got > 0 do say(n, .Client, "Downloaded %d of map %s's own images (%d KB)", f.art_got, utils.short_string_text(&f.name), f.art_kb)
		f.on = false
		n.mapped = true // the world is made of it now
		return
	}
	f.file = pop_front(&f.queue)
	f.on = true
	fetch_ask(n, FETCH_AHEAD)
}

// A part come: kept where it goes, the next asked for, and the file whole at the last.
@(private = "package")
fetch_part :: proc(n: ^Line, p: ^network.Msg_Map_Part) {
	f := &n.fetch
	if !f.on || p.round != f.round || p.file != f.file || p.part != f.next do return
	if f.data == nil {
		if p.total == 0 || p.total > network.MAP_MAX || (f.file > 0 && p.total != f.art[f.file - 1].size) {
			fetch_fail(n, "the server's file is too large, or not as it said")
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
	if f.file == 0 && quarter > f.told && quarter < 4 {
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
	m := network.Msg_Map_Fetch{round = f.round, file = f.file, part = f.asked, count = count}
	network.net_send_message(n.link.peer, .Map_Fetch, network.msg_map_fetch, &m)
	f.asked += count
}

// The file whole: kept among the downloads once it is the one the server named, written
// beside its place first and moved in; then the next.
@(private = "file")
fetch_done :: proc(n: ^Line) {
	f := &n.fetch
	name := utils.short_string_text(&f.name)
	if f.file == 0 {
		if f.hash != {} && hash_of(f.data) != f.hash {
			fetch_fail(n, "what came isn't the server's map")
			return
		}
		if why := keep(map_path(DOWNLOADS_DIR, name), f.data); why != "" {
			fetch_fail(n, why)
			return
		}
		say(n, .Client, "Downloaded map %s (%d KB)", name, (f.total + 1023) / 1024)
		n.map_dir = DOWNLOADS_DIR
	} else {
		art := &f.art[f.file - 1]
		path := utils.short_string_text(&art.path)
		why := "what came isn't the server's" if hash_of(f.data) != art.hash else keep(utils.temp_path(DOWNLOADS_DIR, "maps", name, path), f.data)
		if why != "" {
			say(n, .Warning, "Couldn't download %s of map %s: %s; it is drawn without it", path, name, why)
		} else {
			f.art_got += 1
			f.art_kb += (int(f.total) + 1023) / 1024
		}
	}
	fetch_next(n)
}

// `data` kept at `path`, written beside it first and moved in over what was there. Why
// not, if it couldn't be.
@(private = "file")
keep :: proc(path: string, data: []u8) -> (why: string) {
	dir := filepath.dir(path)
	os.make_directory_all(dir)
	part := utils.temp_path(dir, "download.part")
	if !utils.write_file(part, data) do return strings.concatenate({"it couldn't be written into ", dir}, context.temp_allocator)
	os.remove(path) // another version, downloaded before
	if os.rename(part, path) != nil {
		os.remove(part)
		return strings.concatenate({"it couldn't be put in ", dir}, context.temp_allocator)
	}
	return ""
}

// The .pms that can't be had: the joining given up.
@(private = "file")
fetch_fail :: proc(n: ^Line, why: string) {
	f := &n.fetch
	if f.file > 0 { // an art file: passed over, the rest fetched
		say(n, .Warning, "Couldn't download %s of map %s: %s", utils.short_string_text(&f.art[f.file - 1].path), utils.short_string_text(&f.name), why)
		fetch_next(n)
		return
	}
	say(n, .Warning, "Couldn't download map %s: %s", utils.short_string_text(&f.name), why)
	fetch_stop(f)
	line_disconnect(n)
}

// Whether the art file is here as the server has it, by its hash: downloaded, or with
// the map as it shipped. A download the shipped copy makes needless is let go, so the
// shipped one is the one drawn (map_art_dirs looks among the downloads first).
@(private = "file")
art_here :: proc(name: string, art: ^network.Msg_Map_Art) -> bool {
	path := utils.short_string_text(&art.path)
	dirs := map_art_dirs(name)
	downloaded := utils.temp_path(dirs[0], path)
	if data, err := os.read_entire_file(downloaded, context.temp_allocator); err == nil && hash_of(data) == art.hash do return true
	if data, err := os.read_entire_file(utils.temp_path(dirs[1], path), context.temp_allocator); err == nil && hash_of(data) == art.hash {
		os.remove(downloaded)
		return true
	}
	return false
}

// Whether a map's name can be a file's, and no more: the server's word makes paths here.
@(private = "file")
name_safe :: proc(name: string) -> bool {
	return name != "" && !strings.contains_any(name, "/\\:*?\"<>|") && !strings.has_prefix(name, ".")
}

// Whether an art file's path is one a map's art has, under its own folder and nowhere
// else: textures/, textures/edges/ or scenery-gfx/, then a file's name, an image's.
@(private = "file")
art_path_safe :: proc(path: string) -> bool {
	file := path
	switch {
	case strings.has_prefix(path, "textures/edges/"): file = path[len("textures/edges/"):]
	case strings.has_prefix(path, "textures/"):       file = path[len("textures/"):]
	case strings.has_prefix(path, "scenery-gfx/"):    file = path[len("scenery-gfx/"):]
	case:                                             return false
	}
	if !name_safe(file) do return false
	ext := strings.to_lower(filepath.ext(file), context.temp_allocator)
	return ext == ".png" || ext == ".bmp" || ext == ".gif" || ext == ".jpg" || ext == ".jpeg"
}

@(private = "file")
map_path :: proc(dir, name: string) -> string {
	return utils.temp_path(dir, "maps", strings.concatenate({name, ".pms"}, context.temp_allocator))
}

// A file's SHA-256, as the server names it.
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
