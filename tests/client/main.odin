package client_test

// The client's line (apps/client/net) and its demos (apps/client/demo) against a real
// server on the loopback: the join, the round's map and its snapshots, a team chosen,
// chat, the map window's question, a map the client lacks fetched from the server, a
// demo recorded and played back, and the browser asking a server what it plays. Real
// sockets, so the tests run one at a time on their own port.
//
//   odin test tests/client -define:ODIN_TEST_THREADS=1

import sa "core:container/small_array"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

import "../../apps/client/demo"
import "../../apps/client/online"
import "../../apps/server"
import "../../core/game"
import network "../../core/network"
import res "../../core/resources"
import "../../core/utils"

PORT :: 40024
ROUNDS :: 600 // of 5 ms: three seconds at most for anything to come

// A server, and a client's line to it with the world it plays.
Session :: struct {
	sv:       ^server.Server,
	config:   res.Server_Config,
	n:        online.Line,
	game:     ^game.Game, // the client's, made on the first Map
	recorder: ^demo.Recorder, // the session recorded, while it is
}

session_open :: proc(s: ^Session, data_dir := game.DATA_DIR) -> bool {
	s.sv = new(server.Server)
	s.config = res.DEFAULT_SERVER_CONFIG
	s.config.server.port = PORT
	s.config.server.hostname = "Test server"
	s.config.server.capture_limit = 7
	if !server.server_init(s.sv, {config = &s.config, data_dir = data_dir, first_map = "ctf_Ash"}) do return false
	if !online.line_init(&s.n) do return false
	hello := network.Msg_Hello{primary = .AK74, secondary = .Knife}
	utils.short_string_set(&hello.name, "Tester")
	online.line_connect(&s.n, fmt.tprintf("127.0.0.1:%d", PORT), hello)
	return true
}

session_close :: proc(s: ^Session) {
	online.line_shutdown(&s.n)
	if s.game != nil {
		game.game_destroy(s.game)
		free(s.game)
	}
	server.server_destroy(s.sv)
	free(s.sv)
}

// A frame: the server's, the line polled, the client's world made on a Map, and its tick
// on the server's word, standing still.
pump :: proc(s: ^Session) {
	server.server_pump(s.sv, 0.005)
	online.line_poll(&s.n, s.game)
	if online.line_take_map(&s.n) {
		if s.game == nil {
			s.game = new(game.Game)
			assert(game.game_init(s.game, game.DEFAULT_GAME_SETTINGS, authority = false))
		}
		assert(game.game_start_round(s.game, utils.short_string_text(&s.n.map_name), seed = 1, data_dir = s.n.map_dir))
	}
	if s.recorder != nil do demo.recorder_frame(s.recorder)
	if s.game != nil && online.line_live(&s.n) {
		online.line_begin_tick(&s.n, s.game, 0)
		view := s.game.world.tick
		commands: [game.MAX_PLAYERS]game.Command
		for &soldier, i in s.game.world.soldiers {
			soldier.remote = game.Soldier_Id(i) != s.n.slot
			if soldier.remote do commands[i] = game.soldier_last_command(&soldier, online.line_quiet(&s.n, game.Soldier_Id(i)))
		}
		game.game_tick(s.game, &commands)
		online.line_tick(&s.n, s.game)
		if s.recorder != nil {
			me := &s.game.world.soldiers[s.n.slot]
			demo.recorder_tick(s.recorder, view, commands[s.n.slot], {}, me if me.active else nil)
		}
	}
	online.line_flush(&s.n)
	time.sleep(5 * time.Millisecond)
}

// Pumped until `done`, or the rounds run out.
until :: proc(s: ^Session, done: proc(s: ^Session) -> bool) -> bool {
	for _ in 0 ..< ROUNDS {
		pump(s)
		if done(s) do return true
	}
	return false
}

joined :: proc(s: ^Session) -> bool {
	return online.line_live(&s.n) && s.game != nil && s.n.stream.stats.arrived > 10
}

@(test)
join_and_play :: proc(t: ^testing.T) {
	s := new(Session)
	defer free(s)
	testing.expect(t, session_open(s))
	defer session_close(s)

	testing.expect(t, until(s, joined), "joined, with the round's world and its snapshots")
	testing.expect_value(t, utils.short_string_text(&s.n.map_name), "ctf_Ash")
	testing.expect_value(t, utils.short_string_text(&s.n.hostname), "Test server")
	testing.expect_value(t, s.n.limit, 7)
	testing.expect_value(t, s.n.map_dir, game.DATA_DIR) // the map here is the server's
	id := online.hwid()
	text := utils.short_string_text(&id)
	testing.expect(t, len(text) == 0 || len(text) == 11, "the hardware ID is eleven digits, or none")
	for c in text do testing.expect(t, (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'), "in hex, in capitals")

	// a team chosen in the chat: the server places me on it
	testing.expect(t, online.line_say(&s.n, "/team 1", false, false))
	placed := until(s, proc(s: ^Session) -> bool {
		me := &s.game.world.soldiers[s.n.slot]
		return me.active && me.team == .Alpha && !me.vitals.dead
	})
	testing.expect(t, placed, "placed on alpha")

	// a line said comes back from the server, mine
	testing.expect(t, online.line_say(&s.n, "hello there", false, false))
	heard := until(s, proc(s: ^Session) -> bool {
		for &chat in sa.slice(&s.n.inbox) {
			if chat.slot == s.n.slot && utils.short_string_text(&chat.text) == "hello there" do return true
		}
		return false
	})
	testing.expect(t, heard, "the line came back")

	// the map window's question answered
	online.line_map_query(&s.n, 0)
	answered := until(s, proc(s: ^Session) -> bool {return online.line_take_map_reply(&s.n)})
	testing.expect(t, answered, "the map window's question answered")
	testing.expect(t, s.n.map_reply.count >= 1 && s.n.map_reply.map_name.length > 0, "with a map")
}

// The server's ctf_Ash isn't the client's (one byte of its header differs), and it has
// a scenery image of its own: the client fetches both, keeps them among its downloads,
// and plays on it. A file in the map's folder it doesn't draw with isn't offered.
@(test)
map_fetched :: proc(t: ^testing.T) {
	SERVER_DATA :: "test_fetch_data"
	defer os.remove_all(SERVER_DATA)
	defer os.remove_all(online.DOWNLOADS_DIR)
	ash, read := os.read_entire_file("data/maps/ctf_Ash.pms", context.allocator)
	testing.expect(t, read == nil)
	defer delete(ash)
	ash[84] ~= 0xFF // the map's random id: the same map, another file
	os.make_directory_all(SERVER_DATA + "/maps/ctf_Ash/scenery-gfx")
	testing.expect(t, utils.write_file(SERVER_DATA + "/maps/ctf_Ash.pms", ash))
	polymap, loaded := res.map_load(game.DATA_DIR, "ctf_Ash", context.temp_allocator)
	testing.expect(t, loaded && len(polymap.scenery) > 0, "ctf_Ash draws with scenery")
	image := fmt.tprintf("%s.png", filepath.stem(polymap.scenery[0]))
	ART :: "the map's own image, as far as the line can tell"
	testing.expect(t, utils.write_file(fmt.tprintf("%s/maps/ctf_Ash/scenery-gfx/%s", SERVER_DATA, image), transmute([]u8)string(ART)))
	testing.expect(t, utils.write_file(SERVER_DATA + "/maps/ctf_Ash/scenery-gfx/unused.png", transmute([]u8)string("not drawn")))

	s := new(Session)
	defer free(s)
	testing.expect(t, session_open(s, data_dir = SERVER_DATA))
	defer session_close(s)

	testing.expect(t, until(s, joined), "joined, once the map came")
	testing.expect_value(t, s.n.map_dir, online.DOWNLOADS_DIR)
	kept, kept_read := os.read_entire_file(online.DOWNLOADS_DIR + "/maps/ctf_Ash.pms", context.allocator)
	defer delete(kept)
	testing.expect(t, kept_read == nil && string(kept) == string(ash), "the server's map, kept as it came")
	art, art_read := os.read_entire_file(fmt.tprintf("%s/maps/ctf_Ash/scenery-gfx/%s", online.DOWNLOADS_DIR, image), context.allocator)
	defer delete(art)
	testing.expect(t, art_read == nil && string(art) == ART, "and its own image, in the map's folder of downloads")
	testing.expect(t, !os.exists(online.DOWNLOADS_DIR + "/maps/ctf_Ash/scenery-gfx/unused.png"), "but nothing it doesn't draw with")
	dirs := online.map_art_dirs("ctf_Ash")
	found, has := res.map_image({fallback = "mods/classic"}, dirs[:], "scenery-gfx", polymap.scenery[0])
	testing.expect(t, has && filepath.base(found) == image, "which the map's scenery is drawn with, before Classic's")
}

// A game recorded as it is played, then played back on the same line: the same map, as
// many ticks, the snapshots heard again, my soldier in it.
@(test)
demo_round_trip :: proc(t: ^testing.T) {
	PATH :: "test_demos/round.srdm"
	defer os.remove_all("test_demos")
	s := new(Session)
	defer free(s)
	testing.expect(t, session_open(s))
	defer session_close(s)
	testing.expect(t, until(s, joined))
	online.line_say(&s.n, "/team 2", false, false)

	recorder := new(demo.Recorder)
	defer free(recorder)
	header := demo.Header{date = 1234, slot = u8(s.n.slot), map_name = s.n.map_name}
	utils.short_string_set(&header.name, "Tester")
	testing.expect(t, demo.recorder_open(recorder, PATH, header), "the demo is written")
	heard_before := s.n.stream.stats.arrived
	demo.recorder_join(recorder, &s.n)
	s.recorder = recorder
	s.n.tap = proc(user: rawptr, data: []u8, kind: network.Msg_Kind) {
		if kind != .Map && kind != .Map_Part do demo.recorder_packet((^demo.Recorder)(user), data)
	}
	s.n.tap_user = recorder
	for _ in 0 ..< 240 do pump(s)
	s.n.tap = nil
	s.recorder = nil
	live := s.n.stream.stats.arrived - heard_before
	recorded := recorder.ticks
	demo.recorder_close(recorder)
	testing.expect(t, recorded > 100, "ticks were recorded")

	player := new(demo.Player)
	defer free(player)
	why, opened := demo.player_open(player, PATH)
	testing.expectf(t, opened, "the demo opens: %s", why)
	defer demo.player_close(player)
	testing.expect_value(t, player.header.ticks, recorded)
	testing.expect_value(t, utils.short_string_text(&player.header.name), "Tester")
	testing.expect_value(t, utils.short_string_text(&player.header.map_name), "ctf_Ash")
	testing.expect_value(t, game.Soldier_Id(player.header.slot), s.n.slot)

	// played back as the match plays it
	n := &s.n
	online.line_play(n, game.Soldier_Id(player.header.slot))
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = false))
	defer game.game_destroy(g)
	made := false
	ticks: u32
	present := false
	loop: for {
		switch record in demo.player_next(player) {
		case []u8:
			online.line_feed(n, g if made else nil, record)
		case demo.Frame:
			if online.line_take_map(n) {
				made = game.game_start_round(g, utils.short_string_text(&n.map_name), seed = 1, data_dir = n.map_dir)
			}
		case ^demo.Tick:
			n.stream.view_at = record.view
			online.line_begin_tick(n, g, 0)
			commands: [game.MAX_PLAYERS]game.Command
			commands[n.slot] = record.command
			game.game_tick(g, &commands)
			ticks += 1
			present ||= record.present && g.world.soldiers[n.slot].active
		case nil:
			break loop
		}
	}
	testing.expect(t, made, "the demo's world was made from its Map")
	testing.expect_value(t, ticks, recorded)
	testing.expect(t, n.stream.stats.arrived >= live, "its snapshots were heard again")
	testing.expect(t, present, "my soldier is in it")
}

// The browser's queries: a server on the list asked what it plays, and answering.
@(test)
browser_asks :: proc(t: ^testing.T) {
	s := new(Session)
	defer free(s)
	testing.expect(t, session_open(s))
	defer session_close(s)

	b := new(online.Browser)
	defer free(b)
	b.count = 1
	b.servers[0] = {address = {ip = utils.short_string(15, "127.0.0.1"), port = PORT}, nonce = 42, sent = -1e9}
	testing.expect(t, network.query_socket_open(&b.socket))
	b.state = .Querying
	for _ in 0 ..< ROUNDS {
		pump(s)
		online.browser_pump(b)
		if b.state == .Done do break
	}
	defer online.browser_close(b)
	testing.expect_value(t, b.state, online.Browser_State.Done)
	testing.expect_value(t, b.answered, 1)
	info := &b.servers[0].info
	testing.expect_value(t, utils.short_string_text(&info.hostname), "Test server")
	testing.expect_value(t, utils.short_string_text(&info.map_name), "ctf_Ash")
	testing.expect_value(t, info.protocol, u16(network.VERSION))
}
