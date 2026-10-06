package network_test

// The wire, round-tripped: the bits, the soldier's halves whole and as deltas, every
// kind of word, the messages, and the two streams between a server's game and a
// client's over no line at all.
//
//   odin test tests/network

import "core:fmt"
import "core:testing"

import sa "core:container/small_array"

import "../../core/game"
import net "../../core/network"
import res "../../core/resources"
import "../../core/utils"

@(test)
tables :: proc(t: ^testing.T) {
	testing.expect(t, len(net.SOLDIER_OWNED_FIELDS) >= 30, "the owned half has its fields")
	testing.expect(t, len(net.SOLDIER_SERVED_FIELDS) > 25, "the served half has its fields")
	testing.expect_value(t, len(net.SOLDIER_LOADOUT_FIELDS), 2) // the primary and the secondary
	testing.expect(t, len(net.THING_FIELDS) > 20, "a thing has its fields")
	testing.expect_value(t, len(net.LOOK_FIELDS), 9)
	for f in net.SOLDIER_OWNED_FIELDS {
		for g in net.SOLDIER_SERVED_FIELDS {
			testing.expectf(t, f.name != g.name, "%s is in both halves", f.name)
		}
	}
}

@(test)
bits :: proc(t: ^testing.T) {
	buf: [64]u8
	b := net.buffer_writer(buf[:])
	u, s, f, r := u32(0x2A), i32(-7), f32(1.5), u32(5)
	name := utils.short_string(24, "Major")
	bit := true
	net.net_bits(&b, &u, 7)
	net.net_signed(&b, &s, 5)
	net.net_f32(&b, &f)
	net.net_range(&b, &r, 6)
	net.net_bool(&b, &bit)
	net.net_string(&b, &name)
	testing.expect(t, net.buffer_ok(&b))
	written := net.buffer_written(&b)

	b = net.buffer_reader(written)
	u2, r2: u32
	s2: i32
	f2: f32
	name2: utils.Short_String(24)
	bit2: bool
	net.net_bits(&b, &u2, 7)
	net.net_signed(&b, &s2, 5)
	net.net_f32(&b, &f2)
	net.net_range(&b, &r2, 6)
	net.net_bool(&b, &bit2)
	net.net_string(&b, &name2)
	testing.expect(t, net.buffer_done(&b))
	testing.expect_value(t, u2, u)
	testing.expect_value(t, s2, s)
	testing.expect_value(t, f2, f)
	testing.expect_value(t, r2, r)
	testing.expect_value(t, bit2, bit)
	testing.expect_value(t, utils.short_string_text(&name2), "Major")

	// a value that doesn't fit its width goes bad in the writer
	b = net.buffer_writer(buf[:])
	too_big := u32(200)
	net.net_bits(&b, &too_big, 7)
	testing.expect(t, !net.buffer_ok(&b), "200 doesn't fit 7 bits")
}

// A game with two soldiers in it, moved about a little so their state is nothing like
// zero.
@(private = "file")
make_game :: proc(authority: bool) -> ^game.Game {
	g := new(game.Game)
	settings := game.DEFAULT_GAME_SETTINGS
	assert(game.game_init(g, settings, authority))
	assert(game.game_start_round(g, "ctf_Ash", seed = 7))
	return g
}

@(private = "file")
place :: proc(g: ^game.Game, slot: int, team: res.Team) {
	game.apply_ruling(&g.world, &g.resources, game.Respawn{
		target    = game.Soldier_Id(slot),
		life      = 1,
		team      = team,
		primary   = .AK74,
		secondary = .Knife,
		pos       = game.spawn_point(g.world.polymap, team, &g.world.rng),
	})
}

@(private = "file")
run :: proc(g: ^game.Game, ticks: int, buttons: game.Buttons) {
	for _ in 0 ..< ticks {
		commands: [game.MAX_PLAYERS]game.Command
		for i in 0 ..< 2 {
			commands[i] = {sequence = g.world.tick + 1, buttons = buttons, aim = g.world.soldiers[1 - i].body.pos}
		}
		game.game_tick(g, &commands)
	}
}

@(test)
soldier_halves :: proc(t: ^testing.T) {
	g := make_game(true)
	defer {game.game_destroy(g); free(g)}
	place(g, 0, .Alpha)
	place(g, 1, .Bravo)
	run(g, 40, {.Right, .Jet, .Fire})
	soldier := &g.world.soldiers[0]

	// whole
	buf: [4096]u8
	b := net.buffer_writer(buf[:])
	net.fields_serialize(&b, net.SOLDIER_OWNED_FIELDS, soldier, nil)
	net.fields_serialize(&b, net.SOLDIER_SERVED_FIELDS, soldier, nil)
	testing.expect(t, net.buffer_ok(&b), "a soldier fits its widths")
	fmt.printfln("a soldier whole: %d bytes", net.buffer_bytes(&b))
	heard: game.Soldier
	b = net.buffer_reader(net.buffer_written(&b))
	net.fields_serialize(&b, net.SOLDIER_OWNED_FIELDS, &heard, nil)
	net.fields_serialize(&b, net.SOLDIER_SERVED_FIELDS, &heard, nil)
	testing.expect(t, net.buffer_done(&b))
	testing.expect(t, net.fields_equal(net.SOLDIER_OWNED_FIELDS, &heard, soldier), "the owned half came through")
	testing.expect(t, net.fields_equal(net.SOLDIER_SERVED_FIELDS, &heard, soldier), "the served half came through")
	testing.expect_value(t, heard.body.pos, soldier.body.pos)
	testing.expect_value(t, heard.rng, soldier.rng)
	testing.expect_value(t, heard.pose.legs.id, soldier.pose.legs.id)

	// a delta against the tick before: a few fields, far fewer bytes
	before := soldier^
	run(g, 1, {.Right, .Jet})
	b = net.buffer_writer(buf[:])
	net.fields_serialize(&b, net.SOLDIER_OWNED_FIELDS, soldier, &before)
	delta_bytes := net.buffer_bytes(&b)
	fmt.printfln("a tick's delta: %d bytes", delta_bytes)
	testing.expect(t, delta_bytes < 60, "a delta is small")
	heard = before
	b = net.buffer_reader(net.buffer_written(&b))
	net.fields_serialize(&b, net.SOLDIER_OWNED_FIELDS, &heard, &before)
	testing.expect(t, net.buffer_done(&b))
	testing.expect(t, net.fields_equal(net.SOLDIER_OWNED_FIELDS, &heard, soldier), "the delta lands on its base")
}

@(test)
words :: proc(t: ^testing.T) {
	words := [?]game.Word {
		game.Shot{owner = 3, weapon = .Barrett, pos = {1, 2}, velocity = {3, -4}, damage = 5.5, number = 77},
		game.Gun_Drop{owner = 1, weapon = .M79, ammo = 1, pos = {10, 20}, impact = {0.5, 0.25}, thrown = true},
		game.Flag_Throw{soldier = 9},
		game.Shot_End{owner = 2, shot = 12, weapon = .Frag_Grenade, pos = {5, 6}, blast = .Frag},
		game.Shot_End{owner = 2, shot = 13, weapon = .Thrown_Knife, pos = {5, 6}, blast = nil},
		game.Ruling(game.Damage{attacker = 1, target = 2, weapon = .AK74, amount = 12.5, part = 3}),
		game.Ruling(game.Kill{killer = 1, target = 2, weapon = .Knife, pos = {7, 8}, part = 2, impact = {1, 1}, fire = 3, distance = 99, airtime = 30, ricochets = 1}),
		game.Ruling(game.Respawn{target = 4, life = 2, team = .Bravo, primary = .Spas12, secondary = .LAW, pos = {100, 200}}),
		game.Ruling(game.Gun_Drop{owner = 1, weapon = .Minigun, ammo = 50, pos = {1, 1}}),
		game.Ruling(game.Knife_Land{owner = 5, pos = {2, 2}}),
		game.Ruling(game.Flag_Throw{soldier = 6}),
		game.Ruling(game.Flag_Grab{soldier = 7, flag = 1}),
		game.Ruling(game.Flag_Return{flag = 0, returner = nil}),
		game.Ruling(game.Flag_Return{flag = 1, returner = 8}),
		game.Ruling(game.Flag_Capture{soldier = 9, flag = 0}),
		game.Ruling(game.Pickup{soldier = 1, thing = 5, kind = .Weapon, weapon = .Ruger77, ammo = 4}),
		game.Ruling(game.Thing_Respawn{thing = 9}),
	}
	for word in words {
		buf: [256]u8
		b := net.buffer_writer(buf[:])
		w := word
		net.net_word(&b, &w)
		testing.expectf(t, net.buffer_ok(&b), "%v writes", word)
		heard: game.Word
		b = net.buffer_reader(net.buffer_written(&b))
		net.net_word(&b, &heard)
		testing.expectf(t, net.buffer_done(&b), "%v reads", word)
		testing.expectf(t, heard == word, "%v came back as %v", word, heard)
	}

	// nothing is bad on the wire
	buf: [16]u8
	b := net.buffer_writer(buf[:])
	none: game.Word
	net.net_word(&b, &none)
	testing.expect(t, !net.buffer_ok(&b))
}

@(test)
messages :: proc(t: ^testing.T) {
	buf: [net.MTU]u8
	hello := net.Msg_Hello{version = net.VERSION, name = utils.short_string(24, "Tester"), primary = .MP5, secondary = .Chainsaw}
	hello.look.shirt = {1, 2, 3, 4}
	hello.look.gostek = .Waifu
	bytes := net.build(buf[:], .Hello, net.msg_hello, &hello)
	testing.expect(t, bytes != nil)
	b := net.buffer_reader(bytes)
	kind: net.Msg_Kind
	heard: net.Msg_Hello
	net.msg_kind(&b, &kind)
	net.msg_hello(&b, &heard)
	testing.expect(t, net.buffer_done(&b))
	testing.expect_value(t, kind, net.Msg_Kind.Hello)
	testing.expect_value(t, heard, hello)

	chat := net.Msg_Chat{slot = nil, kind = .Script, color = {9, 8, 7, 255}, text = utils.short_string(128, "hello there")}
	bytes = net.build(buf[:], .Chat, net.msg_chat, &chat)
	b = net.buffer_reader(bytes)
	heard_chat: net.Msg_Chat
	net.msg_kind(&b, &kind)
	net.msg_chat(&b, &heard_chat)
	testing.expect(t, net.buffer_done(&b))
	testing.expect_value(t, heard_chat, chat)

	// a whole weapons mod goes in one message, within a packet, and comes back whole
	weapons := net.Msg_Weapons{weapons = res.weapon_table(res.GATHER_WEAPONS)}
	for &stats, w in weapons.weapons {
		stats.damage = f32(w) * 10 + 0.5
		stats.fire_interval = i32(w) + 1
		stats.ammo = -i32(w)
		stats.leg_modifier = f32(w) / 4
	}
	bytes = net.build(buf[:], .Weapons, net.msg_weapons, &weapons)
	testing.expect(t, bytes != nil && len(bytes) <= net.MTU, "a full weapons mod fits a packet")
	b = net.buffer_reader(bytes)
	heard_weapons: net.Msg_Weapons
	net.msg_kind(&b, &kind)
	net.msg_weapons(&b, &heard_weapons)
	testing.expect(t, net.buffer_done(&b))
	testing.expect_value(t, kind, net.Msg_Kind.Weapons)
	testing.expect(t, heard_weapons == weapons, "the mod came through")
}

// A server and a client on the same map, the client playing soldier 0, the server
// playing a bot in 1: a snapshot goes one way, a client state the other, and each side
// has the other's word.
@(test)
streams :: proc(t: ^testing.T) {
	server := make_game(true)
	client := make_game(false)
	defer {
		game.game_destroy(server)
		game.game_destroy(client)
		free(server)
		free(client)
	}
	game.soldier_place(server, 0, .Alpha, remote = true)
	game.soldier_place(server, 1, .Bravo, remote = false)
	run(server, 120, {.Right, .Jet}) // past the spawn protection

	words: net.Wire_Queue
	net.wire_queue_init(&words)
	streams := new([game.MAX_PLAYERS]net.Server_Stream)
	defer free(streams)
	net.server_stream_init(&streams[0], 1)
	names: [game.MAX_PLAYERS]net.Name
	names[0] = utils.short_string(24, "Tester")
	names[1] = utils.short_string(24, "Admiral")

	client_stream: net.Client_Stream
	net.client_stream_init(&client_stream)
	defer net.client_stream_destroy(&client_stream)
	net.client_stream_reset(&client_stream, 1)

	// a few ticks of snapshots: the first whole, the rest deltas against what the client
	// acknowledged in its states
	buf: [net.MTU]u8
	for tick in 0 ..< 5 {
		run(server, 1, {.Right, .Jet})
		net.wire_collect(&words, &server.output, server.world.tick - 1, nil)
		snapshot := net.server_stream_snapshot(&streams[0], server, 0, &words, &names, buf[:])
		testing.expect(t, snapshot != nil, "a snapshot fits")
		if tick == 0 do fmt.printfln("the first snapshot: %d bytes", len(snapshot))
		testing.expect(t, net.client_stream_hear(&client_stream, client, 0, snapshot), "the client reads it")
		net.client_stream_begin_tick(&client_stream, client, 0, 0)
		if tick < 4 do run(client, 1, {}) // the client's clock, in step with the server's

		state := net.client_stream_state(&client_stream, &client.world.soldiers[0], buf[:])
		testing.expect(t, state != nil, "a state fits")
		testing.expect(t, net.server_stream_receive(&streams[0], server, 0, state, &words), "the server reads it")
	}
	testing.expect(t, streams[0].ack != 0, "the server knows what the client has")
	testing.expect_value(t, client_stream.applied, server.world.tick)
	testing.expect_value(t, client.world.tick, server.world.tick)
	testing.expect_value(t, utils.short_string_text(&client_stream.names[1]), "Admiral")

	// the bot's soldier as the server has it, on the client; the client's own soldier
	// placed by the server's word (its first life)
	bot_server, bot_client := &server.world.soldiers[1], &client.world.soldiers[1]
	testing.expect(t, net.fields_equal(net.SOLDIER_SERVED_FIELDS, bot_client, bot_server), "the bot's served half")
	testing.expect(t, net.fields_equal(net.SOLDIER_OWNED_FIELDS, bot_client, bot_server), "the bot's owned half")
	testing.expect(t, bot_client.remote, "the bot is heard of, not played, on the client")
	me := &client.world.soldiers[0]
	testing.expect(t, me.active && me.vitals.life == server.world.soldiers[0].vitals.life, "I was placed")
	testing.expect(t, client.world.things[0].kind == server.world.things[0].kind, "the things came")
	testing.expect(t, client.round == server.round, "the round came")

	// the client's word of its soldier reached the server
	testing.expect(t, net.fields_equal(net.SOLDIER_OWNED_FIELDS, &server.world.soldiers[0], me), "my owned half on the server")

	// a shot the client fires reaches the server, which relays it; a ruling the server
	// makes reaches the client in the tick of its frame
	run(client, 1, {.Fire})
	net.client_stream_collect(&client_stream, client, 0)
	fired := 0
	for event in sa.slice(&client.output.events) {
		if _, is_shot := event.(game.Shot_Fired); is_shot do fired += 1
	}
	testing.expect(t, fired > 0, "the client fired")
	state := net.client_stream_state(&client_stream, me, buf[:])
	testing.expect(t, net.server_stream_receive(&streams[0], server, 0, state, &words))
	testing.expect_value(t, int(sa.len(server.world.heard)), fired)
	testing.expect_value(t, int(words.next - 1 - (words.first - 1)) >= fired, true)
}


// The lobby's list: an address and a port a line; what isn't one is passed over, and no
// more are read than there is room for.
@(test)
lobby_list :: proc(t: ^testing.T) {
	text := "1.2.3.4:23073\r\nnot an address\n256.1.1.1:23073\n10.0.0.1:0\n10.0.0.1:65536\n10.0.0.2\n192.168.1.20:40000\n"
	list: [8]net.Query_Address
	count := net.query_parse_list(text, list[:])
	testing.expect_value(t, count, 2)
	testing.expect_value(t, utils.short_string_text(&list[0].ip), "1.2.3.4")
	testing.expect_value(t, list[0].port, u16(23073))
	testing.expect_value(t, utils.short_string_text(&list[1].ip), "192.168.1.20")
	testing.expect_value(t, list[1].port, u16(40000))
	testing.expect_value(t, net.query_parse_list(text, list[:1]), 1)
}
