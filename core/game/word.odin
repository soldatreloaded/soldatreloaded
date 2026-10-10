package game

import sa "core:container/small_array"

// Word from another machine: what the wire brings between ticks, done in the step at
// the turn the C game's pass would have taken it from its mail. A client hears the
// server's rulings, the others' shots and where a shot ended; the server hears each
// owner's decisions: its shots, its gun thrown, its flag thrown.

Word :: union {
	Shot,       // an owner's, fired where it says; run forward to the present when heard
	Gun_Drop,   // an owner's gun thrown, for the referee to lay down
	Flag_Throw, // an owner's flag thrown, for the referee to allow
	Shot_End,   // the server's word of where a shot ended
	Ruling,     // the server's decision
	Hit_Claim,  // an owner's: a body its own shot met on its screen (hit_claim.odin)
	Shot_Hit,   // the server's word of a hit on the living, claimed or its own
	Blast_Claim, // an owner's: its own grenade or rocket gone off on its screen, and whom it reached
}

MAX_HEARD :: 256
CATCH_UP_MAX :: 30 // ticks a heard shot is run forward at most: half a second

Hearing :: struct {
	word:     Word,
	catch_up: u8, // a shot's: how far behind the present it was fired
	tick:     u32, // when it was said, on the machine that said it
}

// `word`, said at `tick` on the machine it came from, for the next step. Dropped if the
// inbox is full, as the C game's mail would be.
world_hear :: proc(world: ^World, word: Word, tick: u32) {
	catch_up: u8
	if _, is_shot := word.(Shot); is_shot {
		behind := world.tick - tick if world.tick > tick else 0
		catch_up = u8(min(behind, CATCH_UP_MAX))
	}
	sa.push_back(&world.heard, Hearing{word, catch_up, tick})
}

// The turns of a step at which what was heard is done.
Turn :: enum {
	Soldiers, // before them: the owners' throws, asked of the things as a soldier's are
	Bullets,  // at the start of theirs: shots, and shots' ends, as the C game's bullets pass reads them
	Wounds,   // where the referee lands the hits: wounds, deaths, new lives
	Things,   // before the things' requests: what was decided about them
}

// What was heard that `turn` does, in the order heard; the inbox is emptied at the last.
heard_apply :: proc(world: ^World, resources: ^Resources, authority: ^Authority, out: ^Tick_Output, turn: Turn) {
	flashed: bit_set[0 ..< MAX_PLAYERS; u32] // the shooters given their flash this turn, one each
	for hearing in sa.slice(&world.heard) {
		switch w in hearing.word {
		case Gun_Drop:   if turn == .Soldiers do things_ask(world, w)
		case Flag_Throw: if turn == .Soldiers do things_ask(world, w)
		case Shot:
			if turn != .Bullets do continue
			if authority == nil && int(w.owner) not_in flashed { // a client hearing of it: the flash
				flashed += {int(w.owner)}
				bullet_remote_fire(world, resources, w, out)
			}
			bullet_hear(world, resources, w, hearing.catch_up, hearing.tick, authority, out)
			// a player's grenade, thrown on its own machine: the server keeps the count
			// (stream_server.odin), so the throw is taken off it here
			if authority != nil && w.weapon == .Frag_Grenade {
				arsenal := &world.soldiers[w.owner].arsenal
				arsenal.grenades = max(arsenal.grenades - 1, 0)
			}
		case Shot_End:   if turn == .Bullets do bullet_shot_end(world, resources, w, out)
		case Shot_Hit:   if turn == .Bullets && authority == nil do bullet_shot_hit(world, resources, w, out)
		case Hit_Claim:  if turn == .Bullets && authority != nil do hit_claim_judge(world, resources, authority, w, hearing.tick, out)
		case Blast_Claim: if turn == .Bullets && authority != nil do blast_claim_judge(world, resources, authority, w, hearing.tick, out)
		// recorded as the server's own are, for the sounds, the sparks and the feed; a
		// client's collection for the wire leaves rulings out, so none goes back
		case Ruling:
			if turn != ruling_turn(w) do continue
			// a placing the snapshot has already made: the snapshot often comes before the
			// word, and placed again the soldier was put back at its spawn with the round's
			// first loadout, a weapon picked since taken from it. Recorded, not done again.
			if respawn, is_respawn := w.(Respawn); is_respawn && placed_already(world, respawn) {
				sa.push_back(&out.rulings, w)
				continue
			}
			rule(world, resources, w, out)
		}
	}
	if turn == .Things do sa.clear(&world.heard)
}

// Whether the soldier is already alive in the life `respawn` begins.
@(private = "file")
placed_already :: proc(world: ^World, respawn: Respawn) -> bool {
	soldier := &world.soldiers[respawn.target]
	return soldier.active && !soldier.vitals.dead && soldier.vitals.life == respawn.life
}

@(private = "file")
ruling_turn :: proc(ruling: Ruling) -> Turn {
	#partial switch _ in ruling {
	case Damage, Kill, Respawn: return .Wounds
	}
	return .Things
}
