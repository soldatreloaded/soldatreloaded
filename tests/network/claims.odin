package network_test

// Hits on the shooter's word (core/game/hit_claim.odin), over a line as a long route is:
// the snapshots late now and then, a few lost in a row now and then. A server, a client
// firing all over a soldier who strafes as a player does, and a client watching. On the
// ticks no snapshot came in time the shooter's screen shows its target stepped on its
// last keys; every hit it saw must land on the server, and the watcher must show every
// one: the watcher's own flight of the shot meets the living for show too, so it may
// show a few more, never one twice. So with every weapon: the guns, the grenades and the rockets (their
// blasts), the thrown knife.

import "core:fmt"
import "core:slice"
import "core:testing"

import sa "core:container/small_array"

import "../../core/game"
import net "../../core/network"
import res "../../core/resources"

@(private = "file")
SHOOTER :: game.Soldier_Id(0)
@(private = "file")
TARGET :: game.Soldier_Id(1)
@(private = "file")
WATCHER :: game.Soldier_Id(2)

// What the shooter does.
@(private = "file")
Arm :: enum {
	Rifle,   // the AK-74, held down
	M79,     // a grenade launched as soon as it can be
	LAW,     // a rocket, the same
	Grenade, // a frag grenade wound up and thrown
	Knife,   // a combat knife thrown, and another taken up
}

// What a play left: the hits the shooter's screen made on its target, and the wounds the
// server gave it from them; what the server told, and what the watcher showed; the
// blasts, the knives laid down; the ticks the shooter's screen guessed; the server's
// words the watcher heard.
@(private = "file")
Play :: struct {
	claimed, landed, told, watched: int,
	seen_damage, landed_damage:     f32, // a blast's, its wounds summed: the shooter's screen, the server
	fired:                          int, // grenades, rockets or knives let go
	blasts_shooter, blasts_server, blasts_watcher: int,
	knives_laid:                    int,
	guessed, heard:                 int,
	// with an enemy target, its deaths: each wall tick the server ruled one, the shooter's screen
	// showed one of mine, and the watcher's; and those the shooter's screen took back
	killed_server, killed_shown, killed_watched: [dynamic]int,
	taken_back:                     int,
}

@(test)
claims_land_what_the_shooter_saw :: proc(t: ^testing.T) {
	for delay in ([]int{1, 6, 12, 20}) { // ticks each way: a round trip of 33 ms, 200, 400 and 667
		p := claims_play(delay, .Rifle)
		fmt.printfln("a line %d ticks each way: %d hits the shooter saw, %d landed, %d told, %d shown to the watcher; %d ticks it guessed",
			delay, p.claimed, p.landed, p.told, p.watched, p.guessed)
		testing.expect(t, p.claimed >= 20, "the shooter hit its target, often")
		testing.expect(t, p.guessed >= 20, "the shooter's screen guessed, often")
		testing.expect_value(t, p.landed, p.claimed)
		testing.expect_value(t, p.told, p.landed)
		testing.expectf(t, p.watched >= p.told, "every hit told is shown to the watcher (%d told, %d shown: the rest its own flight of the shot met, for show)", p.told, p.watched)
	}
}

// An enemy shot dead on the shooter's screen dies there at once, before the server has
// heard of it, and once: the server's word of the death shows nothing more, and none is
// taken back. The watcher shows every death the server ruled, and no other.
@(test)
kills_shown_at_once :: proc(t: ^testing.T) {
	for delay in ([]int{1, 6, 12}) {
		p := claims_play(delay, .Rifle, enemy = true)
		defer {
			delete(p.killed_server)
			delete(p.killed_shown)
			delete(p.killed_watched)
		}
		early := 0
		for k, i in p.killed_server {
			if i < len(p.killed_shown) && p.killed_shown[i] < k do early += 1
		}
		fmt.printfln("a line %d ticks each way: %d deaths ruled; %d shown by the shooter's screen, %d of them before the server ruled them; %d taken back; %d shown to the watcher",
			delay, len(p.killed_server), len(p.killed_shown), early, p.taken_back, len(p.killed_watched))
		testing.expect(t, len(p.killed_server) >= 2, "the target was killed, again and again")
		testing.expect_value(t, len(p.killed_shown), len(p.killed_server))
		testing.expect_value(t, early, len(p.killed_server))
		testing.expect_value(t, p.taken_back, 0)
		testing.expect_value(t, len(p.killed_watched), len(p.killed_server))
	}
}

// Each grenade and rocket goes off once everywhere, and its blast wounds the target on
// the server as it did on the shooter's screen, by the same distance there.
@(test)
blasts_land_what_the_shooter_saw :: proc(t: ^testing.T) {
	for arm in ([]Arm{.M79, .LAW, .Grenade}) {
		for delay in ([]int{1, 8, 16}) {
			p := claims_play(delay, arm)
			fmt.printfln("%v, %d ticks each way: %d let go; gone off %d on the shooter's screen, %d on the server, %d on the watcher's; the target %d times hit there for %.1f, %d here for %.1f",
				arm, delay, p.fired, p.blasts_shooter, p.blasts_server, p.blasts_watcher, p.claimed, p.seen_damage, p.landed, p.landed_damage)
			testing.expect(t, p.fired >= 5, "it was let go of, often")
			testing.expect(t, p.claimed >= 3, "and its blast reached the target")
			testing.expect_value(t, p.blasts_shooter, p.fired)
			testing.expect_value(t, p.blasts_server, p.fired)
			testing.expect_value(t, p.blasts_watcher, p.fired)
			testing.expect_value(t, p.landed, p.claimed)
			testing.expectf(t, abs(p.landed_damage - p.seen_damage) <= 0.02 * max(p.seen_damage, 1), "the same wounds, by the same distances (%.2f there, %.2f here)", p.seen_damage, p.landed_damage)
		}
	}
}

// A thrown knife that sticks in the target lands on the server as it did on the
// shooter's screen, the watcher sees it stick, and every knife lies somewhere once.
@(test)
knives_land_what_the_shooter_saw :: proc(t: ^testing.T) {
	for delay in ([]int{1, 8, 16}) {
		p := claims_play(delay, .Knife)
		fmt.printfln("knife, %d ticks each way: %d thrown, %d laid down; %d hits the shooter saw, %d landed, %d told, %d shown to the watcher",
			delay, p.fired, p.knives_laid, p.claimed, p.landed, p.told, p.watched)
		testing.expect(t, p.fired >= 5, "knives were thrown, often")
		testing.expect(t, p.claimed >= 3, "and stuck in the target")
		testing.expect_value(t, p.knives_laid, p.fired)
		testing.expect_value(t, p.landed, p.claimed)
		testing.expect_value(t, p.told, p.landed)
		testing.expectf(t, p.watched >= p.told, "every hit told is shown to the watcher (%d told, %d shown: the rest its own flight of the shot met, for show)", p.told, p.watched)
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

// A client's grenade no claim comes for goes off on the server all the same, as its own
// flight there had it, once it has waited long enough for one.
@(test)
blast_unclaimed_goes_off :: proc(t: ^testing.T) {
	server := claims_game(true)
	defer {
		game.game_destroy(server)
		free(server)
	}
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Bravo, remote = false)
	claims_run(server, 150)
	from := server.world.soldiers[SHOOTER].body.pos - {0, 30}
	game.world_hear(&server.world, game.Shot{owner = SHOOTER, weapon = .Frag_Grenade, pos = from, velocity = {4, -3}, damage = 1, number = 1}, server.world.tick) // away: not back onto its thrower, which the server judges
	went_off := -1
	for tick in 0 ..< game.GRENADE_TIMEOUT + game.HOLD_BLAST + 10 {
		claims_run(server, 1)
		for event in sa.slice(&server.output.events) {
			if e, is := event.(game.Explosion); is && e.owner == SHOOTER do went_off = tick
		}
	}
	testing.expectf(t, went_off >= game.GRENADE_TIMEOUT + game.HOLD_BLAST - 5, "it went off once the wait for a claim was over (at %d)", went_off)
}

@(private = "file")
Packet :: struct {
	due:  int,
	to:   int, // the client it is for, 0 or 1; or, less than 0, the server, from slot -to-1
	data: []u8,
}

// A minute of the shooter armed with `arm` over a line `delay` ticks each way.
@(private = "file")
claims_play :: proc(delay: int, arm: Arm, enemy := false, trust := false) -> (p: Play) {
	server := claims_game(true)
	server.authority.trust = trust
	shooter := claims_game(false)
	watcher := claims_game(false)
	defer {
		for g in ([]^game.Game{server, shooter, watcher}) {
			game.game_destroy(g)
			free(g)
		}
	}
	primary: res.Weapon
	switch arm {
	case .Rifle:   primary = .AK74 // fast enough to go through a body
	case .M79:     primary = .M79
	case .LAW:     primary = .AK74 // the LAW is a secondary
	case .Grenade: primary = .AK74
	case .Knife:   primary = .Knife
	}
	server.world.soldiers[SHOOTER].loadout = {primary, .LAW if arm == .LAW else .Knife}
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Bravo if enemy else .Alpha, remote = false) // else a teammate: hit, and never killed
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
		for packet in line do delete(packet.data)
		delete(line)
	}
	dice: u32 = 12345
	roll :: proc(dice: ^u32, n: u32) -> u32 {
		dice^ = dice^ * 1664525 + 1013904223
		return (dice^ >> 16) % n
	}
	strafe: game.Buttons
	target_life: u8
	lost: [2]int
	sequence: u32
	buf: [net.MTU]u8
	TICKS :: 3600
	explosive := arm == .M79 || arm == .LAW || arm == .Grenade
	for wall in 0 ..< TICKS + 4 * delay + game.HOLD_BLAST + 240 {
		firing := wall > 150 && wall < TICKS // past the spawn protection; then the words drain

		// the server: the states due, its tick, its words, a snapshot to each client
		for i := 0; i < len(line); {
			packet := line[i]
			if packet.to >= 0 || packet.due > wall {
				i += 1
				continue
			}
			slot := game.Soldier_Id(-packet.to - 1)
			net.server_stream_receive(&streams[slot], server, slot, packet.data, &words)
			delete(packet.data)
			unordered_remove(&line, i)
		}
		commands: [game.MAX_PLAYERS]game.Command
		for slot in slots do commands[slot] = game.soldier_last_command(&server.world.soldiers[slot], false)
		// the target strafes as a player does, its keys changed every few ticks: a screen
		// stepping it on its last keys is wrong whenever a snapshot is late across a change
		if wall % 4 == 0 do strafe = {.Left} if roll(&dice, 2) == 0 else {.Right}
		if wall % 4 == 0 && roll(&dice, 6) == 0 do strafe += {.Jump}
		commands[TARGET] = {sequence = server.world.tick + 1, buttons = strafe, aim = server.world.soldiers[SHOOTER].body.pos}
		if !enemy do server.world.soldiers[TARGET].vitals.health = game.DEFAULT_HEALTH
		// an enemy placed where the shooter can reach it: by its own team's spawn, across the map, it can't
		if enemy && server.world.soldiers[TARGET].vitals.life != target_life && !server.world.soldiers[TARGET].vitals.dead {
			target_life = server.world.soldiers[TARGET].vitals.life
			s := &server.world.soldiers[TARGET]
			s.body.pos = game.spawn_point(server.world.polymap, .Alpha, &server.world.rng)
			s.body.old_pos = s.body.pos
		}
		game.game_tick(server, &commands)
		for event in sa.slice(&server.output.events) {
			#partial switch e in event {
			case game.Hit:
				if e.shooter != SHOOTER || e.target != TARGET do continue
				p.landed += 1
				p.landed_damage += e.amount
			case game.Shot_Hit:  if e.owner == SHOOTER && e.target == TARGET && !e.blast do p.told += 1
			case game.Explosion: if e.owner == SHOOTER do p.blasts_server += 1
			}
		}
		for ruling in sa.slice(&server.output.rulings) {
			if laid, is := ruling.(game.Knife_Land); is && laid.owner == SHOOTER do p.knives_laid += 1
			if kill, is := ruling.(game.Kill); is && kill.killer == SHOOTER && kill.target == TARGET do append(&p.killed_server, wall)
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
				packet := line[j]
				if packet.to != i || packet.due > wall {
					j += 1
					continue
				}
				net.client_stream_hear(c, g, me, packet.data)
				delete(packet.data)
				unordered_remove(&line, j)
			}
			missed := c.stats.misses
			net.client_stream_begin_tick(c, g, me, 0)
			if i == 0 do p.guessed += int(c.stats.misses - missed)
			cmds: [game.MAX_PLAYERS]game.Command
			for &s, k in g.world.soldiers {
				s.remote = game.Soldier_Id(k) != me
				if s.remote do cmds[k] = game.soldier_last_command(&s, net.client_stream_quiet(c, game.Soldier_Id(k)))
			}
			sequence += 1
			// aimed all over the body, as a player's aim is: its edges are where a guess decides
			spread := [2]f32{f32(roll(&dice, 13)) - 6, -f32(roll(&dice, 26))}
			mine := game.Command{sequence = sequence, aim = g.world.soldiers[TARGET].body.pos + spread}
			if i == 0 && firing do mine.buttons = shooter_keys(&g.world.soldiers[me], arm, wall)
			cmds[me] = mine
			game.game_tick(g, &cmds)
			for event in sa.slice(&g.output.events) {
				#partial switch e in event {
				case game.Hit_Claimed:
					if e.owner == me && e.target == TARGET do p.claimed += 1
				case game.Hit:
					if i == 0 && explosive && e.shooter == me && e.target == TARGET {
						p.claimed += 1
						p.seen_damage += e.amount
					}
				case game.Shot_Fired:
					if i == 0 && e.shot.weapon != .AK74 && e.shot.weapon != .Knife && e.shot.weapon != .Punch do p.fired += 1
				case game.Explosion:
					if e.owner != SHOOTER do continue
					if i == 0 do p.blasts_shooter += 1
					else do p.blasts_watcher += 1
				case game.Blood:
					if i == 1 && e.target == TARGET do p.watched += 1
				case game.Kill_Taken_Back:
					if i == 0 && e.target == TARGET do p.taken_back += 1
				}
			}
			for ruling in sa.slice(&g.output.rulings) {
				kill, is := ruling.(game.Kill)
				if !is || kill.killer != SHOOTER || kill.target != TARGET do continue
				append(&p.killed_shown if i == 0 else &p.killed_watched, wall)
			}
			net.client_stream_collect(c, g, me)
			if state := net.client_stream_state(c, &g.world.soldiers[me], buf[:]); state != nil {
				append(&line, Packet{due = wall + delay, to = -int(me) - 1, data = slice.clone(state)})
			}
		}
	}
	p.heard = int(client_streams[1].pending.received)
	return
}

// The shooter's keys for `arm`, and what it is given to keep at it: a launcher always
// loaded, a grenade always to throw, a knife always in hand.
@(private = "file")
shooter_keys :: proc(me: ^game.Soldier, arm: Arm, wall: int) -> game.Buttons {
	switch arm {
	case .Rifle:
		return {.Fire}
	case .M79:
		if me.arsenal.primary.ammo == 0 do me.arsenal.primary.ammo = 1
		me.arsenal.primary.reload_count = 0
		return {.Fire} if wall % 40 == 0 else {}
	case .LAW:
		if me.arsenal.primary.weapon != .LAW do me.arsenal.primary.weapon = .LAW
		if me.arsenal.primary.ammo == 0 do me.arsenal.primary.ammo = 1
		me.arsenal.primary.reload_count = 0
		return {.Crouch, .Fire} if wall % 40 < 25 else {.Crouch} // fired crouched, held through its start up
	case .Grenade:
		me.arsenal.grenades = max(me.arsenal.grenades, 1)
		return {.Throw} if wall % 60 < 25 else {} // wound up a while, then let go
	case .Knife:
		if me.arsenal.primary.weapon != .Knife {
			me.arsenal.primary.weapon = .Knife
			me.arsenal.primary.ammo = 1
		}
		return {.Drop} if wall % 40 == 0 else {}
	}
	return {}
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

// A soldier killed fires on, its own screen not yet told: what it fired after its death,
// by the game's time, is void on the server, not flown; what it fired before flies, a
// trade; and a grenade it threw after, flying here already as the death came, never
// goes off.
@(test)
shots_after_death_void :: proc(t: ^testing.T) {
	server := claims_game(true)
	defer {
		game.game_destroy(server)
		free(server)
	}
	game.soldier_place(server, SHOOTER, .Alpha, remote = true)
	game.soldier_place(server, TARGET, .Bravo, remote = false)
	claims_run(server, 150)
	flying :: proc(g: ^game.Game) -> (n: int) {
		for &bullet in g.world.bullets do if bullet.active && bullet.owner == SHOOTER do n += 1
		return
	}
	recorded :: proc(g: ^game.Game, number: u32) -> bool {
		for &record in g.authority.shots.records do if record.used && record.owner == SHOOTER && record.shot == number do return true
		return false
	}
	shot :: proc(g: ^game.Game, weapon: res.Weapon, number: u32, fired: u32) {
		from := g.world.soldiers[SHOOTER].body.pos - {0, 30}
		game.world_hear(&g.world, game.Shot{owner = SHOOTER, weapon = weapon, pos = from, velocity = {4, -3}, damage = 1, number = number}, fired)
	}

	// thrown in a tick still to come by the server's count, so after the death below
	shot(server, .Frag_Grenade, 1, server.world.tick + 10)
	claims_run(server, 1)
	testing.expect_value(t, flying(server), 1)
	game.world_ask_kill(&server.world, SHOOTER, false)
	claims_run(server, 1)
	died := server.world.tick
	testing.expect(t, server.world.soldiers[SHOOTER].vitals.dead, "killed")
	testing.expect_value(t, flying(server), 0) // the grenade let go of, unseen

	shot(server, .AK74, 2, died + 3) // fired after
	shot(server, .AK74, 3, died - 2) // fired before: a trade
	claims_run(server, 1)
	testing.expect(t, !recorded(server, 2), "the shot fired after its death not flown")
	testing.expect(t, recorded(server, 3), "the shot fired before it flown")

	went_off := false
	for _ in 0 ..< game.GRENADE_TIMEOUT + game.HOLD_BLAST + 10 {
		claims_run(server, 1)
		for event in sa.slice(&server.output.events) {
			if e, is := event.(game.Explosion); is && e.owner == SHOOTER do went_off = true
		}
	}
	testing.expect(t, !went_off, "the grenade thrown once dead never went off")
}

// A server that trusts its claims (Authority.trust) lands one its checks would turn
// down, a shot nowhere near its target, with the wound the claim says; and a claim that
// says it kills, kills, whatever the target's health was there. One that doesn't trust
// lands neither.
@(test)
trusted_claims_taken :: proc(t: ^testing.T) {
	for trust in ([]bool{false, true}) {
		server := claims_game(true)
		defer {
			game.game_destroy(server)
			free(server)
		}
		server.authority.trust = trust
		game.soldier_place(server, SHOOTER, .Alpha, remote = true)
		game.soldier_place(server, TARGET, .Bravo, remote = false)
		claims_run(server, 150)
		from := server.world.soldiers[SHOOTER].body.pos - {0, 30}
		fired := server.world.tick
		game.world_hear(&server.world, game.Shot{owner = SHOOTER, weapon = .AK74, pos = from, velocity = {4, -3}, damage = 1, number = 1}, fired)
		claims_run(server, 1)
		claim := game.Hit_Claim {
			claimed = {owner = SHOOTER, shot = 1, fired = fired, weapon = .AK74, target = TARGET, part = 9, pos = from, velocity = {4, -3}, start = from, point = from, amount = 30},
			seen = 2, taken = 2, steps = 1,
		}
		target := &server.world.soldiers[TARGET]
		game.world_hear(&server.world, claim, server.world.tick)
		claims_run(server, 1)
		wounded := target.vitals.health < game.DEFAULT_HEALTH
		testing.expectf(t, wounded == trust, "trusted %v: the claim off its target wounded it: %v (health %.1f)", trust, wounded, target.vitals.health)
		if trust do testing.expect_value(t, target.vitals.health, game.DEFAULT_HEALTH - 30)

		claim.claimed.kills = true // its screen saw it kill: the target dies, its health here what it may
		game.world_hear(&server.world, claim, server.world.tick)
		claims_run(server, 1)
		testing.expectf(t, target.vitals.dead == trust, "trusted %v: the claimed kill killed: %v", trust, target.vitals.dead)
	}
}

// With a server that trusts its claims, the shooter's screen kills and the server always
// agrees: none taken back, every death shown before the server ruled it.
@(test)
trusted_kills_never_taken_back :: proc(t: ^testing.T) {
	for delay in ([]int{1, 6, 12}) {
		p := claims_play(delay, .Rifle, enemy = true, trust = true)
		defer {
			delete(p.killed_server)
			delete(p.killed_shown)
			delete(p.killed_watched)
		}
		early := 0
		for k, i in p.killed_server {
			if i < len(p.killed_shown) && p.killed_shown[i] < k do early += 1
		}
		fmt.printfln("trusted, a line %d ticks each way: %d deaths ruled; %d shown by the shooter's screen, %d before the server ruled them; %d taken back; %d shown to the watcher",
			delay, len(p.killed_server), len(p.killed_shown), early, p.taken_back, len(p.killed_watched))
		testing.expect(t, len(p.killed_server) >= 2, "the target was killed, again and again")
		testing.expect_value(t, len(p.killed_shown), len(p.killed_server))
		testing.expect_value(t, early, len(p.killed_server))
		testing.expect_value(t, p.taken_back, 0)
		testing.expect_value(t, len(p.killed_watched), len(p.killed_server))
	}
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

// A round trip too long for a delta, past a second, sends every snapshot whole; the
// server's words still go with them, a few at a time, as nothing else has to: before,
// a whole snapshot fitted with none, and none ever went.
@(test)
words_on_a_whole_snapshot :: proc(t: ^testing.T) {
	heard := claims_play(32, .Rifle).heard
	testing.expectf(t, heard > 100, "the watcher heard the server's words (%d)", heard)
}
