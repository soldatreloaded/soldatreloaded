package server_test

// The server over ENet on the loopback: a client connecting, Hello answered with
// Welcome, the round's Map and a soldier; the wrong version Denied; chat relayed;
// snapshots arriving and a client's state taken; a leaver's slot freed; a query
// answered. Real sockets, so the tests run one at a time on their own port.
//
//   odin test tests/server -define:ODIN_TEST_THREADS=1

import "core:testing"
import "core:time"

import "../../core/game"
import net "../../core/network"
import res "../../core/resources"
import "../../core/utils"
import "../../apps/server"
import "../../apps/server/lists"

import enet "vendor:ENet"

PORT :: 40023
ROUNDS :: 300 // of 10 ms: three seconds at most for anything to arrive

// A client's end for the tests: connects, says hello, remembers what it heard.
Test_Client :: struct {
	link:          net.Link,
	version:       u16,
	name:          string,
	connected:     bool,
	welcomed:      bool,
	denied:        bool,
	closed:        bool,
	welcome:       net.Msg_Welcome,
	map_msg:       net.Msg_Map,
	mapped:        bool,
	denial:        net.Msg_Denied,
	chat:          net.Msg_Chat,
	chats:         int, // lines from players
	announcements: int, // and from the server itself
	snapshots:     int,
	stream:        net.Client_Stream,
	game:          ^game.Game, // the client's world, made on the Map
}

client_open :: proc(c: ^Test_Client, name: string, version: u16 = net.VERSION) -> bool {
	c^ = {version = version, name = name}
	return net.net_connect(&c.link, "127.0.0.1", PORT)
}

client_close :: proc(c: ^Test_Client) {
	net.net_close(&c.link)
	if c.game != nil {
		game.game_destroy(c.game)
		free(c.game)
		net.client_stream_destroy(&c.stream)
	}
	c.game = nil
}

client_pump :: proc(c: ^Test_Client) {
	e: net.Event
	for c.link.host != nil && net.net_poll(&c.link, &e, 0) != .None {
		switch e.kind {
		case .None:
		case .Connect:
			c.connected = true
			hello := net.Msg_Hello{version = c.version, name = utils.short_string(24, c.name), primary = .AK74, secondary = .Knife}
			net.net_send_message(c.link.peer, .Hello, net.msg_hello, &hello)
		case .Disconnect:
			c.closed = true
		case .Message:
			b := net.buffer_reader(e.data[:e.size])
			kind: net.Msg_Kind
			net.msg_kind(&b, &kind)
			#partial switch e.msg {
			case .Welcome:
				net.msg_welcome(&b, &c.welcome)
				c.welcomed = true
			case .Denied:
				net.msg_denied(&b, &c.denial)
				c.denied = true
			case .Map:
				net.msg_map(&b, &c.map_msg)
				c.mapped = true
				client_map(c)
			case .Chat:
				net.msg_chat(&b, &c.chat)
				if c.chat.slot == nil {
					c.announcements += 1
				} else {
					c.chats += 1
				}
			case .Snapshot:
				if c.game != nil && net.client_stream_hear(&c.stream, c.game, c.welcome.slot, e.data[:e.size]) do c.snapshots += 1
			}
		}
	}
}

// The world the Map names, made as a client makes it: no authority.
client_map :: proc(c: ^Test_Client) {
	if c.game == nil {
		c.game = new(game.Game)
		assert(game.game_init(c.game, game.DEFAULT_GAME_SETTINGS, authority = false))
		net.client_stream_init(&c.stream)
	}
	assert(game.game_start_round(c.game, utils.short_string_text(&c.map_msg.map_name), seed = 1))
	net.client_stream_reset(&c.stream, c.map_msg.round)
}

say :: proc(c: ^Test_Client, text: string) {
	m := net.Msg_Chat{text = utils.short_string(128, text)}
	net.net_send_message(c.link.peer, .Chat, net.msg_chat, &m)
}

// The server and the clients pumped until `done`, or three seconds.
pump_until :: proc(sv: ^server.Server, clients: []^Test_Client, done: proc(clients: []^Test_Client) -> bool) -> bool {
	for _ in 0 ..< ROUNDS {
		server.server_pump(sv, 0.01)
		for c in clients do client_pump(c)
		if done(clients) do return true
		time.sleep(10 * time.Millisecond)
	}
	return false
}

// A server on the loopback, on ctf_Ash, with no bots and no lists kept.
open_server :: proc(sv: ^server.Server, config: ^res.Server_Config) -> bool {
	config^ = res.DEFAULT_SERVER_CONFIG
	config.server.port = PORT
	config.server.hostname = "Test server"
	return server.server_init(sv, {config = config, data_dir = game.DATA_DIR, first_map = "ctf_Ash"})
}

@(test)
join :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)

	a, b := new(Test_Client), new(Test_Client)
	defer {free(a); free(b)}
	testing.expect(t, client_open(a, "Alice"))
	testing.expect(t, client_open(b, "Bob"))
	defer {client_close(a); client_close(b)}
	clients := []^Test_Client{a, b}

	joined := pump_until(sv, clients, proc(cs: []^Test_Client) -> bool {
		return cs[0].welcomed && cs[1].welcomed && cs[0].mapped && cs[1].mapped && cs[0].snapshots > 0 && cs[1].snapshots > 0
	})
	testing.expect(t, joined, "both welcomed, told the map, and sent snapshots")
	testing.expect(t, a.welcome.slot != b.welcome.slot, "each its own slot")
	testing.expect_value(t, utils.short_string_text(&a.map_msg.map_name), "ctf_Ash")
	testing.expect_value(t, utils.short_string_text(&a.map_msg.hostname), "Test server")
	testing.expect_value(t, a.map_msg.round, 1)
	testing.expect(t, a.map_msg.hash != {}, "the map's hash is told")
	testing.expect(t, sv.players[a.welcome.slot].joined && sv.game.world.soldiers[a.welcome.slot].active, "Alice has a soldier")
	testing.expect_value(t, utils.short_string_text(&sv.players[b.welcome.slot].name), "Bob")
	// a spectator until it chooses
	testing.expect_value(t, sv.game.world.soldiers[a.welcome.slot].team, res.Team.Spectator)

	// a client's world, stepped by the snapshots: the round and the things as the server's
	net.client_stream_begin_tick(&a.stream, a.game, a.welcome.slot, 0)
	testing.expect(t, a.game.world.things[0].kind == sv.game.world.things[0].kind, "the things came")

	// /team 1 places Alice on alpha; everyone hears she joined
	say(a, "/team 1")
	announced := pump_until(sv, clients, proc(cs: []^Test_Client) -> bool { return cs[1].announcements > 0 })
	testing.expect(t, announced, "Bob heard Alice join a team")
	testing.expect_value(t, sv.game.world.soldiers[a.welcome.slot].team, res.Team.Alpha)
	testing.expect(t, !sv.game.world.soldiers[a.welcome.slot].vitals.dead, "and alive on it")

	// chat is relayed to everyone with the sender's slot
	say(a, "hello")
	relayed := pump_until(sv, clients, proc(cs: []^Test_Client) -> bool { return cs[1].chats > 0 })
	testing.expect(t, relayed, "Bob heard Alice")
	testing.expect_value(t, utils.short_string_text(&b.chat.text), "hello")
	testing.expect(t, b.chat.slot == a.welcome.slot, "as Alice")

	// a client's state is taken as its soldier's word
	soldier := &a.game.world.soldiers[a.welcome.slot]
	soldier^ = sv.game.world.soldiers[a.welcome.slot]
	soldier.body.pos += {5, 0}
	buf: [net.MTU]u8
	state := net.client_stream_state(&a.stream, soldier, buf[:])
	testing.expect(t, state != nil)
	net.net_send(a.link.peer, .Client_State, state)
	Moved :: struct {
		sv:   ^server.Server,
		slot: game.Soldier_Id,
		to:   f32,
	}
	@(static) moved: Moved
	moved = {sv, a.welcome.slot, soldier.body.pos.x}
	took := pump_until(sv, clients, proc(cs: []^Test_Client) -> bool {
		return moved.sv.streams[moved.slot].newest > 0
	})
	testing.expect(t, took, "the server took Alice's state")

	// Bob leaves: his slot frees, Alice hears it
	slot := b.welcome.slot
	heard := a.announcements
	net.net_close(&b.link)
	@(static) before: int
	before = heard
	left := pump_until(sv, {a}, proc(cs: []^Test_Client) -> bool { return cs[0].announcements > before })
	testing.expect(t, left, "Alice heard Bob leave")
	testing.expect(t, !sv.players[slot].joined && !sv.game.world.soldiers[slot].active, "Bob's slot is free")
}

@(test)
wrong_version :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)

	c := new(Test_Client)
	defer free(c)
	testing.expect(t, client_open(c, "Old", version = net.VERSION + 1))
	defer client_close(c)
	denied := pump_until(sv, {c}, proc(cs: []^Test_Client) -> bool { return cs[0].denied })
	testing.expect(t, denied, "another version is denied")
	testing.expect(t, !c.welcomed)
	testing.expect_value(t, server.players_count(sv), 0)
}

@(test)
password :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)
	config.server.password = "secret" // read as it stands, as a console or script may set it

	c := new(Test_Client)
	defer free(c)
	testing.expect(t, client_open(c, "Guest"))
	defer client_close(c)
	denied := pump_until(sv, {c}, proc(cs: []^Test_Client) -> bool { return cs[0].denied })
	testing.expect(t, denied, "a Hello without the password is denied")
	testing.expect_value(t, utils.short_string_text(&c.denial.reason), "wrong password")
}

@(test)
bots_and_rounds :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	config = res.DEFAULT_SERVER_CONFIG
	config.server.port = PORT
	config.server.time_limit = 1
	config.server.capture_limit = 1
	config.bots.alpha = 2
	config.bots.bravo = 1
	config.maps = {"ctf_Ash", "ctf_Run"}
	testing.expect(t, server.server_init(sv, {config = &config, data_dir = game.DATA_DIR, first_map = "ctf_Ash"}))
	defer server.server_destroy(sv)

	bots := 0
	for &player in sv.players do bots += int(player.bot)
	testing.expect_value(t, bots, 3)

	// the bots on their own: the round ends at a capture or its minute, the scores stand,
	// and the rotation's next map begins
	ended := false
	for _ in 0 ..< 60 * 60 * 3 {
		testing.expect(t, server.server_pump(sv, server.TICK_SECONDS))
		if sv.round > 1 {
			ended = true
			break
		}
	}
	testing.expect(t, ended, "the bots played a round to its end")
	testing.expect_value(t, server.server_map(sv), "ctf_Run")
	bots = 0
	for &player, i in sv.players {
		if player.bot && sv.game.world.soldiers[i].active do bots += 1
	}
	testing.expect_value(t, bots, 3)
}

@(test)
query :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)

	// the request on a plain socket, as a server browser sends it
	socket := enet.socket_create(.DATAGRAM)
	defer enet.socket_destroy(socket)
	any := enet.Address{host = enet.HOST_ANY}
	enet.socket_bind(socket, &any) // Windows sends nothing from a socket never bound
	enet.socket_set_option(socket, .NONBLOCK, 1)
	to := enet.Address{port = PORT}
	enet.address_set_host(&to, "127.0.0.1")
	request: [net.QUERY_REQUEST_SIZE]u8
	bytes := net.query_write_request(request[:], 1234)
	testing.expect(t, net.datagram_send(socket, &to, bytes), "the request went")
	got := false
	reply: [256]u8
	for _ in 0 ..< ROUNDS {
		server.server_pump(sv, 0.01)
		from: enet.Address
		if answer := net.datagram_receive(socket, &from, reply[:]); answer != nil {
			info, ok := net.query_read_reply(answer, 1234)
			testing.expect(t, ok, "the reply reads")
			testing.expect_value(t, info.protocol, u16(net.VERSION))
			testing.expect_value(t, utils.short_string_text(&info.map_name), "ctf_Ash")
			got = true
			break
		}
		time.sleep(10 * time.Millisecond)
	}
	testing.expect(t, got, "the query was answered")
}

// The console's bans and mutes by hardware ID, and an unban by the name a ban was given:
// what the command takes from the word must still be there when the lists are asked.
@(test)
hardware_ids :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)
	now := time.to_unix_seconds(time.now())

	testing.expect(t, server.admin_command(sv, nil, "banhw 0a1b2c3d4e5 Cheating"))
	_, banned := lists.lists_banned(&sv.lists, 0, "0A1B2C3D4E5", now)
	testing.expect(t, banned, "banhw bans the machine")
	testing.expect(t, server.admin_command(sv, nil, "unban 0A1B2C3D4E5"))
	_, banned = lists.lists_banned(&sv.lists, 0, "0A1B2C3D4E5", now)
	testing.expect(t, !banned, "unban by the hardware ID lifts it")

	lists.lists_ban(&sv.lists, 0, "AAAAAAAAAAA", 0, "Machine", "Cheating")
	lists.lists_ban(&sv.lists, 0, "BBBBBBBBBBB", 0, "Other", "Cheating")
	testing.expect(t, server.admin_command(sv, nil, "unban Machine"))
	_, banned = lists.lists_banned(&sv.lists, 0, "AAAAAAAAAAA", now)
	_, other := lists.lists_banned(&sv.lists, 0, "BBBBBBBBBBB", now)
	testing.expect(t, !banned && other, "unban by name lifts that ban, and no other")

	lists.lists_mute(&sv.lists, 0, "CCCCCCCCCCC", "Loud")
	testing.expect(t, server.admin_command(sv, nil, "unmute ccccccccccc"))
	testing.expect(t, !lists.lists_muted(&sv.lists, 0, "CCCCCCCCCCC"), "unmute by the hardware ID lifts it")
}

// The admin commands are one table, for the console and an admin in the chat: a player
// not logged in is refused them, one logged in runs them as the console does.
@(test)
admin_commands :: proc(t: ^testing.T) {
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)

	testing.expect(t, server.admin_command(sv, game.Soldier_Id(3), "pause"), "an admin command, though refused")
	testing.expect(t, !server.server_paused(sv), "and refused to a player not logged in")
	sv.players[3].admin = true
	testing.expect(t, server.admin_command(sv, game.Soldier_Id(3), "pause") && server.server_paused(sv), "an admin pauses the game")
	testing.expect(t, server.admin_command(sv, nil, "unpause") && !server.server_paused(sv), "and the console unpauses it")

	testing.expect(t, server.admin_command(sv, nil, "restart"))
	testing.expect(t, sv.next_round && utils.short_string_text(&sv.chosen_map) == "ctf_Ash", "restart ends the round, the same map to follow")
	testing.expect(t, server.admin_command(sv, nil, "help"), "help is everyone's")
	testing.expect(t, !server.admin_command(sv, nil, "smoke"), "a player's command is none of the admin's")
}
