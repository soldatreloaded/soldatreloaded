package network_test

import "core:fmt"
import "core:testing"

import sa "core:container/small_array"

import "../../core/game"
import net "../../core/network"
import "../../core/utils"

// Eats measured on a line made up here: a server, and a client playing soldier 0 over a
// line of a given delay each way, jitter and loss, its snapshots one a tick and its
// states one a tick, each side stepping the other's soldiers on their last commands as a
// game does. Soldier 1, the server's own, runs, jumps, crouches and now and then jets on
// keys changed at random, kept within a few hundred units of soldier 0, which aims at its
// chest as the client shows it and fires an AK all the while. The target's health is
// topped up, so it lives.
//
// The client counts its eats as it would in a game (network.eats_tick). Knowing both
// worlds, each is also put down to what truly caused it, by the target as the client had
// it at the end of the tick the hit struck in, against the target the server judges a
// client's shot of each tick against (judged_frame):
//
// - the same as the server's of that tick: the shot was past the catch-up, or judged
//   there against another frame ("server frame");
// - the same as the server's of another tick: the view's tick was off ("view off");
// - the same as none: the client had stepped it on from an older word ("stepped"), or
//   had the tick's word and still not the server's soldier ("diverged").
//
// Measured, not judged: the test fails only if nothing was hit.
//
//   odin test tests/network -define:ODIN_TEST_NAMES=network_test.eats_on_a_lossy_line -define:EATS_MINUTES=10

@(private = "file")
Line_Kind :: struct {
	name:   string,
	delay:  u32, // ticks each way
	jitter: u32, // ticks a packet may come later still, at random
	loss:   u32, // percent of packets lost
	strafe: bool, // the target changing keys every few ticks, not every fraction of a second
}

@(private = "file", rodata)
LINES := [?]Line_Kind {
	{"clean, 50 ms each way", 3, 0, 0, false},
	{"jitter of 3 ticks", 3, 3, 0, false},
	{"5% loss, jitter of a tick", 3, 1, 5, false},
	{"300 ms each way", 18, 1, 1, false},
	{"10% loss, jitter of 3 ticks", 3, 3, 10, false},
	{"jitter of 3 ticks, a strafing target", 3, 3, 0, true},
	{"5% loss, a strafing target", 3, 1, 5, true},
}

@(private = "file")
Truth :: enum {
	Target_Gone,
	Past_Catch_Up,
	Server_Frame,
	View_Off,
	Stepped,
	Diverged,
}

@(private = "file", rodata)
TRUTH_NAMES := [Truth]string {
	.Target_Gone   = "target gone",
	.Past_Catch_Up = "past catch-up",
	.Server_Frame  = "server frame",
	.View_Off      = "view off",
	.Stepped       = "stepped",
	.Diverged      = "diverged",
}

@(private = "file")
Measured :: struct {
	stats:   net.Eat_Stats,
	truths:  [Truth]u32,
	agreed:  u32, // eats whose cause the client told right
	ticks:   u32, // ticks of firing
	matched: u32, // of them, those the client had the target as the server judges it
}

@(private = "file")
Packet :: struct {
	due:  u32,
	size: int,
	data: [net.MTU]u8,
}

@(private = "file")
RING :: 256

// The target's joints at the end of each tick, by the tick.
@(private = "file")
Frames :: struct {
	tick:   [RING]u32,
	joints: [RING]game.Joints,
}

EATS_WARM_UP :: 240 // ticks before the firing: placed, and past the spawn's protection
EATS_MINUTES :: #config(EATS_MINUTES, 1) // of firing: longer with -define:EATS_MINUTES=10
EATS_FIRING :: EATS_MINUTES * 60 * game.TICK_RATE

@(test)
eats_on_a_lossy_line :: proc(t: ^testing.T) {
	for line in LINES {
		m := eats_measured(line)
		causes := ""
		for count, truth in m.truths {
			if count > 0 do causes = fmt.tprintf("%s%s%s %d", causes, ", " if causes != "" else "", TRUTH_NAMES[truth], count)
		}
		fmt.printfln("eats over %s: %s", line.name, net.eats_said(m.stats))
		fmt.printfln("    truly: %s; the client's own cause right for %d of %d; the target as the server judges it in %d%% of ticks",
			causes if causes != "" else "none", m.agreed, net.eats_total(m.stats), m.matched * 100 / max(m.ticks, 1))
		testing.expectf(t, m.stats.hits > 50, "%s: the shooter hit (%d)", line.name, m.stats.hits)
	}
}

// The target as the server judges a client's shot of the tick just run against: its own
// frame of the tick, as its history keeps it (game.bullet_target).
@(private = "file")
judged_frame :: proc(server: ^game.Game, target: game.Soldier_Id) -> ^game.Soldier {
	return &server.world.soldiers[target]
}

@(private = "file")
eats_measured :: proc(line: Line_Kind) -> (m: Measured) {
	server := eats_game(true)
	client := eats_game(false)
	defer {
		game.game_destroy(server)
		game.game_destroy(client)
		free(server)
		free(client)
	}
	server.world.soldiers[0].loadout = {.AK74, .Knife}
	game.soldier_place(server, 0, .Alpha, remote = true)
	game.soldier_place(server, 1, .Bravo, remote = false)
	// the target near the shooter: at another of the shooter's team's spawns
	target := &server.world.soldiers[1]
	target.body.pos = game.spawn_point(server.world.polymap, .Alpha, &server.world.rng)
	target.body.old_pos = target.body.pos

	words: net.Wire_Queue
	net.wire_queue_init(&words)
	streams := new([game.MAX_PLAYERS]net.Server_Stream)
	defer free(streams)
	net.server_stream_init(&streams[0], 1)
	names: [game.MAX_PLAYERS]net.Name
	cs: net.Client_Stream
	net.client_stream_init(&cs)
	defer net.client_stream_destroy(&cs)
	net.client_stream_reset(&cs, 1)

	down := make([dynamic]Packet)
	up := make([dynamic]Packet)
	defer delete(down)
	defer delete(up)
	server_frames := new(Frames)
	client_frames := new(Frames)
	defer free(server_frames)
	defer free(client_frames)
	rng := game.Rng{0x9E3779B97F4A7C15}
	keys: game.Buttons
	keys_left := 0
	buf: [net.MTU]u8
	ping := u16((2 * line.delay + line.jitter / 2) * 1000 / game.TICK_RATE) // as the server would measure the line

	for now in u32(0) ..< EATS_WARM_UP + EATS_FIRING {
		firing := now >= EATS_WARM_UP
		if now == EATS_WARM_UP do cs.eats = {} // the count from the firing on

		// the server's tick: the client's soldier on its last word, the target on its keys,
		// kept near; then a snapshot down the line
		shooter := &server.world.soldiers[0]
		keys_left -= 1
		if keys_left <= 0 {
			keys_left = 2 + int(game.rng_next(&rng) % 7) if line.strafe else 10 + int(game.rng_next(&rng) % 30)
			choices := [?]game.Buttons{{.Right}, {.Left}, {.Jump}, {.Right, .Jump}, {.Left, .Jump}, {}, {.Crouch}, {.Right}, {.Left}, {.Jet}}
			keys = choices[game.rng_next(&rng) % len(choices)]
		}
		steer := keys
		if target.body.pos.x - shooter.body.pos.x > 260 do steer = (steer - {.Right}) + {.Left}
		if target.body.pos.x - shooter.body.pos.x < 60 do steer = (steer - {.Left}) + {.Right}
		commands: [game.MAX_PLAYERS]game.Command
		commands[0] = game.soldier_last_command(shooter, false)
		commands[1] = {sequence = server.world.tick + 1, buttons = steer, aim = shooter.body.pos}
		shooter.player.ping = ping
		game.game_tick(server, &commands)
		target.vitals.health = game.DEFAULT_HEALTH
		frame_keep(server_frames, server.world.tick - 1, server, judged_frame(server, 1))
		net.wire_collect(&words, &server.output, server.world.tick - 1, nil)
		if snapshot := net.server_stream_snapshot(&streams[0], server, 0, &words, &names, buf[:]); snapshot != nil {
			send(&down, &rng, line, now, snapshot)
		}

		// the client's: what has come, the view set, my soldier aimed at the target as shown
		// and firing, the others on their last words
		for &p in delivered(&down, now) do net.client_stream_hear(&cs, client, 0, p.data[:p.size])
		net.client_stream_begin_tick(&cs, client, 0, 0)
		shown := &client.world.soldiers[1]
		mine: [game.MAX_PLAYERS]game.Command
		for &s, i in client.world.soldiers do if s.remote do mine[i] = game.soldier_last_command(&s, false)
		chest := game.soldier_pose(client.resources.animations, shown, shown.body.pos)[10 - 1]
		mine[0] = {sequence = client.world.tick + 1, buttons = {.Fire} if firing && shown.active else {}, aim = chest}
		game.game_tick(client, &mine)
		shown_tick := client.world.tick - 1
		frame_keep(client_frames, shown_tick, client, shown)
		if firing {
			m.ticks += 1
			if same_frame(server_frames, shown_tick, &client_frames.joints[shown_tick % RING]) do m.matched += 1
		}
		net.client_stream_collect(&cs, client, 0)
		for eat in sa.slice(&cs.eats.recent) {
			truth := eat_truth(server_frames, client_frames, eat)
			m.truths[truth] += 1
			if agrees(eat.cause, truth) do m.agreed += 1
		}
		sa.clear(&cs.eats.recent)
		if state := net.client_stream_state(&cs, &client.world.soldiers[0], buf[:]); state != nil {
			send(&up, &rng, line, now, state)
		}

		// the server hears what has come up
		for &p in delivered(&up, now) do net.server_stream_receive(&streams[0], server, 0, p.data[:p.size], &words)
	}
	m.stats = cs.eats.stats
	return

	// What truly caused an eat, by the target as the client had it the tick it struck.
	eat_truth :: proc(server_frames, client_frames: ^Frames, eat: net.Eat) -> Truth {
		if eat.cause == .Target_Gone do return .Target_Gone
		mine := &client_frames.joints[eat.tick % RING]
		if client_frames.tick[eat.tick % RING] == eat.tick {
			if same_frame(server_frames, eat.tick, mine) {
				return .Past_Catch_Up if eat.behind > game.CATCH_UP_MAX else .Server_Frame
			}
			for off in u32(1) ..< 20 {
				if eat.tick >= off && same_frame(server_frames, eat.tick - off, mine) do return .View_Off
				if same_frame(server_frames, eat.tick + off, mine) do return .View_Off
			}
		}
		return .Stepped if eat.cause == .Extrapolated else .Diverged
	}
	agrees :: proc(cause: net.Eat_Cause, truth: Truth) -> bool {
		#partial switch truth {
		case .Target_Gone:   return cause == .Target_Gone
		case .Past_Catch_Up: return cause == .Catch_Up || cause == .History
		case .Stepped:       return cause == .Extrapolated
		}
		return cause == .Unexplained
	}
}

// Whether `joints` are the target's as `frames` has it at the end of `tick`.
@(private = "file")
same_frame :: proc(frames: ^Frames, tick: u32, joints: ^game.Joints) -> bool {
	if frames.tick[tick % RING] != tick do return false
	for joint, i in frames.joints[tick % RING] {
		if utils.length(joint - joints[i]) > 0.01 do return false
	}
	return true
}

// The target's joints at the end of the tick just run.
@(private = "file")
frame_keep :: proc(frames: ^Frames, tick: u32, g: ^game.Game, soldier: ^game.Soldier) {
	frames.tick[tick % RING] = tick
	frames.joints[tick % RING] = game.soldier_pose(g.resources.animations, soldier, soldier.body.pos)
}

// `data` onto the line, due `delay` ticks from `now` and up to `jitter` more, unless lost.
@(private = "file")
send :: proc(queue: ^[dynamic]Packet, rng: ^game.Rng, line: Line_Kind, now: u32, data: []u8) {
	if line.loss > 0 && game.rng_next(rng) % 100 < u64(line.loss) do return
	p := Packet{due = now + line.delay, size = len(data)}
	if line.jitter > 0 do p.due += u32(game.rng_next(rng) % u64(line.jitter + 1))
	copy(p.data[:], data)
	append(queue, p)
}

// The packets due by `now`, in the order they come, taken off the line: valid until the
// next call.
@(private = "file")
delivered :: proc(queue: ^[dynamic]Packet, now: u32) -> []Packet {
	due := make([dynamic]Packet, context.temp_allocator)
	for i := 0; i < len(queue); {
		if queue[i].due <= now {
			append(&due, queue[i])
			ordered_remove(queue, i)
		} else {
			i += 1
		}
	}
	return due[:]
}

// A game on ctf_Ash, the server's or a client's.
@(private = "file")
eats_game :: proc(authority: bool) -> ^game.Game {
	g := new(game.Game)
	assert(game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority))
	assert(game.game_start_round(g, "ctf_Ash", seed = 7))
	return g
}
