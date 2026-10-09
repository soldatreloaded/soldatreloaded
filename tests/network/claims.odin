package network_test

// Hits on the shooter's word (core/game/hit_claim.odin), over a line as a long route is:
// the snapshots late now and then, a few lost in a row now and then. A server, a client
// firing all over a soldier who strafes as a player does, and a client watching. On the
// ticks no snapshot came in time the shooter's screen shows its target stepped on its
// last keys; every hit it saw must land on the server, and the watcher must show every
// one, and no other.

import "core:fmt"
import "core:slice"
import "core:testing"

import sa "core:container/small_array"

import "../../core/game"
import net "../../core/network"

@(private = "file")
SHOOTER :: game.Soldier_Id(0)
@(private = "file")
TARGET :: game.Soldier_Id(1)
@(private = "file")
WATCHER :: game.Soldier_Id(2)

@(test)
claims_land_what_the_shooter_saw :: proc(t: ^testing.T) {
	for delay in ([]int{1, 6, 12}) { // ticks each way: a round trip of 33 ms, 200 and 400
		claimed, landed, told, watched, guessed := claims_play(delay)
		fmt.printfln("a line %d ticks each way: %d hits the shooter saw, %d landed, %d told, %d shown to the watcher; %d ticks it guessed",
			delay, claimed, landed, told, watched, guessed)
		testing.expect(t, claimed >= 20, "the shooter hit its target, often")
		testing.expect(t, guessed >= 20, "the shooter's screen guessed, often")
		testing.expect_value(t, landed, claimed)
		testing.expect_value(t, told, landed)
		testing.expect_value(t, watched, told)
	}
}

// A claim the shooter's screen couldn't have made doesn't land: a shot said to have met
// a soldier nowhere near its flight.
@(test)
claims_held_to_the_flight :: proc(t: ^testing.T) {
	server := claims_game(true)
	defer {
		game.game_destroy(server)
		free(server)
	}
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Bravo, remote = false)
	claims_run(server, 150)
	from := server.world.soldiers[SHOOTER].body.pos - {0, 10}
	fired := server.world.tick
	game.world_hear(&server.world, game.Shot{owner = SHOOTER, weapon = .MP5, pos = from, velocity = {18, 0}, damage = 1, number = 1}, fired)
	claims_run(server, 1)

	// the target, at the far end of the map, claimed met on the first tick of the flight
	target := &server.world.soldiers[TARGET]
	claim := game.Hit_Claim {
		claimed = {
			owner = SHOOTER, shot = 1, fired = fired, airtime = 0, weapon = .MP5, target = TARGET, part = 9,
			pos = from, velocity = {18, 0}, start = from, point = target.pose.skeleton[9],
		},
		seen = 1,
		steps = 1,
	}
	game.world_hear(&server.world, claim, fired)
	claims_run(server, 1)
	for event in sa.slice(&server.output.events) {
		hit, is_hit := event.(game.Hit)
		testing.expect(t, !(is_hit && hit.shooter == SHOOTER && hit.target == TARGET), "a claim off the flight lands nothing")
	}
}

@(private = "file")
Packet :: struct {
	due:  int,
	to:   int, // the client it is for, 0 or 1; or, less than 0, the server, from slot -to-1
	data: []u8,
}

// A minute of the shooter firing over a line `delay` ticks each way: the hits its screen
// saw, those that landed, those the server told of, those the watcher showed, and the
// ticks the shooter's screen guessed.
@(private = "file")
claims_play :: proc(delay: int) -> (claimed, landed, told, watched, guessed: int) {
	server := claims_game(true)
	shooter := claims_game(false)
	watcher := claims_game(false)
	defer {
		for g in ([]^game.Game{server, shooter, watcher}) {
			game.game_destroy(g)
			free(g)
		}
	}
	server.world.soldiers[SHOOTER].loadout = {.AK74, .Knife} // fast enough to go through a body
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Alpha, remote = false) // a teammate: hit, and never killed
	game.soldier_place(server, WATCHER, .Alpha, remote = true)

	words: net.Wire_Queue
	net.wire_queue_init(&words)
	streams := new([game.MAX_PLAYERS]net.Server_Stream)
	defer free(streams)
	clients := [2]^game.Game{shooter, watcher}
	slots := [2]game.Soldier_Id{SHOOTER, WATCHER}
	client_streams: [2]net.Client_Stream
	for i in 0 ..< 2 {
		net.server_stream_init(&streams[slots[i]], 1)
		net.client_stream_init(&client_streams[i])
		net.client_stream_reset(&client_streams[i], 1)
	}
	defer for &c in client_streams do net.client_stream_destroy(&c)
	names: [game.MAX_PLAYERS]net.Name

	line: [dynamic]Packet
	defer {
		for p in line do delete(p.data)
		delete(line)
	}
	dice: u32 = 12345
	roll :: proc(dice: ^u32, n: u32) -> u32 {
		dice^ = dice^ * 1664525 + 1013904223
		return (dice^ >> 16) % n
	}
	strafe: game.Buttons
	lost: [2]int
	sequence: u32
	buf: [net.MTU]u8
	TICKS :: 3600
	for wall in 0 ..< TICKS + 4 * delay + 60 {
		firing := wall > 150 && wall < TICKS // past the spawn protection; then the words drain

		// the server: the states due, its tick, its words, a snapshot to each client
		for i := 0; i < len(line); {
			p := line[i]
			if p.to >= 0 || p.due > wall {
				i += 1
				continue
			}
			slot := game.Soldier_Id(-p.to - 1)
			net.server_stream_receive(&streams[slot], server, slot, p.data, &words)
			delete(p.data)
			unordered_remove(&line, i)
		}
		commands: [game.MAX_PLAYERS]game.Command
		for slot in slots do commands[slot] = game.soldier_last_command(&server.world.soldiers[slot], false)
		// the target strafes as a player does, its keys changed every few ticks: a screen
		// stepping it on its last keys is wrong whenever a snapshot is late across a change
		if wall % 4 == 0 do strafe = {.Left} if roll(&dice, 2) == 0 else {.Right}
		if wall % 4 == 0 && roll(&dice, 6) == 0 do strafe += {.Jump}
		commands[TARGET] = {sequence = server.world.tick + 1, buttons = strafe, aim = server.world.soldiers[SHOOTER].body.pos}
		server.world.soldiers[TARGET].vitals.health = game.DEFAULT_HEALTH
		game.game_tick(server, &commands)
		for event in sa.slice(&server.output.events) {
			#partial switch e in event {
			case game.Hit:      if e.shooter == SHOOTER && e.target == TARGET do landed += 1
			case game.Shot_Hit: if e.owner == SHOOTER && e.target == TARGET do told += 1
			}
		}
		net.wire_collect(&words, &server.output, server.world.tick - 1, nil)
		for i in 0 ..< 2 {
			bytes := net.server_stream_snapshot(&streams[slots[i]], server, slots[i], &words, &names, buf[:])
			if bytes == nil do continue
			// a few lost in a row now and then; the rest `delay` late, and now and then two more
			if lost[i] == 0 && roll(&dice, 25) == 0 do lost[i] = 2 + int(roll(&dice, 3))
			if lost[i] > 0 {
				lost[i] -= 1
				continue
			}
			late := delay + (2 if roll(&dice, 5) == 0 else 0)
			append(&line, Packet{due = wall + late, to = i, data = slice.clone(bytes)})
		}

		// each client, as online_step: the snapshots due, its tick on show, the others on
		// their last keys, its own on its keys, and its state to the server
		for i in 0 ..< 2 {
			g := clients[i]
			me := slots[i]
			c := &client_streams[i]
			for j := 0; j < len(line); {
				p := line[j]
				if p.to != i || p.due > wall {
					j += 1
					continue
				}
				net.client_stream_hear(c, g, me, p.data)
				delete(p.data)
				unordered_remove(&line, j)
			}
			missed := c.stats.misses
			net.client_stream_begin_tick(c, g, me, 0)
			if i == 0 do guessed += int(c.stats.misses - missed)
			cmds: [game.MAX_PLAYERS]game.Command
			for &s, k in g.world.soldiers {
				s.remote = game.Soldier_Id(k) != me
				if s.remote do cmds[k] = game.soldier_last_command(&s, net.client_stream_quiet(c, game.Soldier_Id(k)))
			}
			sequence += 1
			// aimed all over the body, as a player's aim is: its edges are where a guess decides
			spread := [2]f32{f32(roll(&dice, 13)) - 6, -f32(roll(&dice, 26))}
			mine := game.Command{sequence = sequence, aim = g.world.soldiers[TARGET].body.pos + spread}
			if i == 0 && firing do mine.buttons = {.Fire}
			cmds[me] = mine
			game.game_tick(g, &cmds)
			for event in sa.slice(&g.output.events) {
				#partial switch e in event {
				case game.Hit_Claimed: if e.owner == me && e.target == TARGET do claimed += 1
				case game.Blood:       if i == 1 && e.target == TARGET do watched += 1
				}
			}
			net.client_stream_collect(c, g, me)
			if state := net.client_stream_state(c, &g.world.soldiers[me], buf[:]); state != nil {
				append(&line, Packet{due = wall + delay, to = -int(me) - 1, data = slice.clone(state)})
			}
		}
	}
	return
}

@(private = "file")
claims_game :: proc(authority: bool, gravity := game.DEFAULT_GAME_SETTINGS.gravity) -> ^game.Game {
	g := new(game.Game)
	settings := game.DEFAULT_GAME_SETTINGS
	settings.gravity = gravity
	for &stats in settings.weapons do stats.bullet_spread, stats.movement_accuracy = 0, 0 // every shot where it is aimed
	assert(game.game_init(g, settings, authority))
	assert(game.game_start_round(g, "ctf_Ash", seed = 7))
	return g
}

// `ticks` of the server alone, the first two soldiers standing, aimed at each other.
@(private = "file")
claims_run :: proc(g: ^game.Game, ticks: int) {
	for _ in 0 ..< ticks {
		commands: [game.MAX_PLAYERS]game.Command
		for i in 0 ..< 2 {
			commands[i] = {sequence = g.world.tick + 1, aim = g.world.soldiers[1 - i].body.pos}
		}
		game.game_tick(g, &commands)
	}
}

// A long shot is claimed to the end of its flight: met after more ticks than the history
// keeps, it lands. With no gravity, so a slow shot flies straight and far: flown once to
// find where it is then, and again from where that puts the target's chest on it; the
// claim is the shot's own, as its client's would be.
@(test)
claims_on_a_long_flight :: proc(t: ^testing.T) {
	FLOWN :: 80 // past the history's 64 ticks
	velocity := [2]f32{-6, 0}
	where_flown :: proc(origin, velocity: [2]f32) -> (pos, vel: [2]f32, chest: [2]f32, ok: bool) {
		server := claims_game(true, gravity = 0)
		defer {
			game.game_destroy(server)
			free(server)
		}
		game.soldier_place(server, SHOOTER, .Alpha, remote = true)
		game.soldier_place(server, TARGET, .Bravo, remote = false)
		claims_run(server, 150)
		chest = server.world.soldiers[TARGET].pose.skeleton[9] - {2, 0}
		game.world_hear(&server.world, game.Shot{owner = SHOOTER, weapon = .MP5, pos = chest + origin, velocity = velocity, damage = 1, number = 1}, server.world.tick)
		claims_run(server, FLOWN + 2)
		for record in server.authority.shots.records {
			if record.used && len(record.trace) > FLOWN do return record.trace[FLOWN].pos - chest, record.trace[FLOWN].velocity, chest, true
		}
		return
	}
	// flown from 300 to the right of the chest, it ends up somewhere short of it; flown
	// again from there less where it ended up, it ends up on the chest
	ended, _, _, flew := where_flown({300, 0}, velocity)
	testing.expect(t, flew, "the shot flew the whole way")
	if !flew do return
	origin := [2]f32{300, 0} - ended

	server := claims_game(true, gravity = 0)
	defer {
		game.game_destroy(server)
		free(server)
	}
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Bravo, remote = false)
	claims_run(server, 150)
	target := &server.world.soldiers[TARGET]
	chest := target.pose.skeleton[9] - {2, 0}
	fired := server.world.tick
	game.world_hear(&server.world, game.Shot{owner = SHOOTER, weapon = .MP5, pos = chest + origin, velocity = velocity, damage = 1, number = 1}, fired)
	claims_run(server, FLOWN + 1)
	record: ^game.Shot_Record
	for &r in server.authority.shots.records {
		if r.used do record = &r
	}
	testing.expect(t, record != nil && len(record.trace) > FLOWN, "the shot flew the whole way again")
	if record == nil || len(record.trace) <= FLOWN do return
	at := record.trace[FLOWN]
	claim := game.Hit_Claim {
		claimed = {
			owner = SHOOTER, shot = 1, fired = fired, airtime = FLOWN, weapon = .MP5, target = TARGET, part = 9,
			pos = at.pos, velocity = at.velocity, start = at.pos, point = target.pose.skeleton[9],
		},
		seen = 1,
		steps = 1,
	}
	game.world_hear(&server.world, claim, fired + FLOWN)
	claims_run(server, 1)
	landed := false
	for event in sa.slice(&server.output.events) {
		if hit, is_hit := event.(game.Hit); is_hit && hit.shooter == SHOOTER && hit.target == TARGET do landed = true
	}
	testing.expect(t, landed, fmt.tprintf("a hit %d ticks into its flight lands (the shot at %v, the chest at %v)", FLOWN, at.pos, chest))
}
