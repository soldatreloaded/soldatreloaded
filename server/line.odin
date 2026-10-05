package server

import "../core/game"
import net "../core/network"

// The line each tick: everything that came in, the command each player's soldier steps
// on, and after the tick a snapshot to every player.

// Everything the line has for the server right now: joins, leaves, states, chat.
line_poll :: proc(sv: ^Server) {
	// everyone's round trip, for the HUDs, in the served half
	for &player, i in sv.players {
		if player.joined do sv.game.world.soldiers[i].player.ping = net.peer_ping(player.peer)
	}
	e: net.Event
	for net.net_poll(&sv.link, &e, 0) != .None {
		switch e.kind {
		case .None:
		case .Connect: // nobody until its Hello
		case .Disconnect:
			leave(sv, e.peer)
		case .Message:
			slot, known := slot_of(sv, e.peer)
			if known do sv.players[slot].messages += 1
			switch {
			case e.msg == .Hello:        hello(sv, e.peer, &e)
			case !known:                 deny(sv, e.peer, "no Hello first") // the rest is for players
			case e.msg == .Chat:         chat(sv, slot, &e)
			case e.msg == .Client_State: net.server_stream_receive(&sv.streams[slot], sv.game, slot, e.data[:e.size], &sv.words)
			case e.msg == .Map_Query:    map_query(sv, e.peer, &e)
			case e.msg == .Map_Fetch:    map_fetch(sv, e.peer, &e)
			}
		}
	}
}

// The command each player's soldier steps on this tick: its last keys, or none once
// quiet; and the suicide a player asked for in the chat.
line_commands :: proc(sv: ^Server, commands: ^[game.MAX_PLAYERS]game.Command) {
	for &player, i in sv.players {
		if !player.joined do continue
		soldier := &sv.game.world.soldiers[i]
		commands[i] = game.soldier_last_command(soldier, net.server_stream_quiet(&sv.streams[i], sv.game.world.tick))
		if sv.suicides[i] {
			commands[i].buttons += {.Suicide}
			sv.suicides[i] = false
		}
	}
}

// After the tick: what it left that travels (the server's decisions, and the shots
// heard this tick, for the others) into the queue, then a snapshot to every player.
line_snapshots :: proc(sv: ^Server) {
	sv.ticks += 1
	vote_tick(sv)
	flood_tick(sv)
	net.wire_collect(&sv.words, &sv.game.output, sv.game.world.tick - 1, nil) // the tick just run
	names: [game.MAX_PLAYERS]net.Name
	for &player, i in sv.players {
		if player_present(&player) do names[i] = player.name
	}
	buf: [net.MTU]u8
	for &player, i in sv.players {
		if !player.joined do continue
		bytes := net.server_stream_snapshot(&sv.streams[i], sv.game, game.Soldier_Id(i), &sv.words, &names, buf[:])
		if bytes != nil do net.net_send(player.peer, .Snapshot, bytes)
	}
}

// The weapons the game plays by to one peer, or to everyone with nil.
tell_weapons :: proc(sv: ^Server, peer: net.Peer) {
	m := net.Msg_Weapons{weapons = sv.settings.weapons}
	if peer != nil {
		net.net_send_message(peer, .Weapons, net.msg_weapons, &m)
	} else {
		broadcast(sv, .Weapons, net.msg_weapons, &m)
	}
}
