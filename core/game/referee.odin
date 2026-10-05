package game

import sa "core:container/small_array"

import "../utils"

// The referee: what only the machine with authority (the server) does. It judges the
// events of a step into rulings and applies each at once, so a soldier killed by a
// bullet is dead before the things move, as in Soldat.

// What the machine with authority has that others don't.
Authority :: struct {
	history: History,
}

HISTORY_TICKS :: 64

// Where everyone was over the last second, so a shot is judged against the soldiers as
// its shooter saw them.
History :: struct {
	soldiers: [HISTORY_TICKS][MAX_PLAYERS]Soldier, // by tick, round the ring
	things:   [HISTORY_TICKS][MAX_THINGS]Thing,    // for the snapshots' deltas
	newest:   u32,
	count:    u32,
}

// Judges the events not yet judged, in the order they happened. A hit lands as the C
// game's wounds pass lands it: its shove and its spray on every machine, and with
// authority the wound, before the next hit's shove (a soldier it kills is not shoved by
// the next).
judge :: proc(world: ^World, resources: ^Resources, authority: ^Authority, out: ^Tick_Output) {
	events := sa.slice(&out.events)
	for event in events[out.judged:] {
		#partial switch e in event {
		case Hit:     hit_land(world, resources, authority, e, out)
		case Suicide: hit_land(world, resources, authority, suicide_hit(world, e.soldier), out)
		}
	}
	out.judged = len(events)
}

// The server's tick on every soldier, whoever moves it: the dead respawned when their
// time is up, and those off the map at once; spawn protection running out.
judge_lives :: proc(world: ^World, resources: ^Resources, out: ^Tick_Output) {
	for &soldier, i in world.soldiers {
		if !soldier.active || soldier.team == .Spectator do continue // neither alive nor to be respawned
		id := Soldier_Id(i)
		vitals := &soldier.vitals

		if vitals.dead {
			// a corpse slid off the map (CheckSkeletonOutOfBounds) is placed again at once;
			// else the count runs out, checked before it is counted down
			corpse := &world.corpses[i]
			if vitals.respawn_counter < 1 || (corpse.active && corpse_out_of_bounds(world.polymap, corpse)) {
				judge_respawn(world, resources, id, out)
			} else {
				vitals.respawn_counter -= 1
			}
			continue
		}
		if soldier_out_of_bounds(world.polymap, soldier.body.pos) {
			judge_respawn(world, resources, id, out)
			continue
		}

		if vitals.cease_fire > -1 do vitals.cease_fire -= 1
	}
}

// A new life on one of the team's spawn points, with the guns chosen.
@(private = "file")
judge_respawn :: proc(world: ^World, resources: ^Resources, id: Soldier_Id, out: ^Tick_Output) {
	soldier := &world.soldiers[id]
	pos := spawn_point(world.polymap, soldier.team, &world.rng)
	respawn := Respawn {
		target    = id,
		life      = soldier.vitals.life + 1,
		team      = soldier.team,
		primary   = soldier.loadout.primary,
		secondary = soldier.loadout.secondary,
		pos       = pos,
	}
	rule(world, resources, respawn, out)
}

// The idle clock run out on a soldier with no antic: one of the four idle ones is picked,
// and asked of its owner.
judge_idle_antic :: proc(world: ^World, authority: ^Authority, id: Soldier_Id) {
	if authority == nil do return
	antics := &world.soldiers[id].antics
	if antics.idle_time != 1 || antics.idle_antic >= 0 do return
	antics.idle_time = 0
	antics.idle_antic = i8(rng_below(&world.rng, 4))
	antics.asked = antics.idle_antic
	antics.asked_count += 1
	antics.seen_count = antics.asked_count
}

// An exploding polygon goes off under the soldier: the map's own grenade.
judge_exploding_polygon :: proc(world: ^World, resources: ^Resources, authority: ^Authority, id: Soldier_Id, origin: utils.Vec2, out: ^Tick_Output) {
	if authority == nil do return
	soldier_shoot(world, resources, id, .M79, origin, {}, resources.weapons[.M79].stats.damage, out)
}

// Records a ruling and carries it out.
rule :: proc(world: ^World, resources: ^Resources, ruling: Ruling, out: ^Tick_Output) {
	sa.push_back(&out.rulings, ruling)
	apply_ruling(world, resources, ruling)
}

// The world as it stands, as the history's newest frame.
history_record :: proc(history: ^History, world: ^World) {
	frame := world.tick % HISTORY_TICKS
	history.soldiers[frame] = world.soldiers
	history.things[frame] = world.things
	history.newest = world.tick
	history.count = min(history.count + 1, HISTORY_TICKS)
}

// The soldiers as they were `ticks_ago`; nil if that is further back than is kept.
history_soldiers :: proc(history: ^History, ticks_ago: u32) -> ^[MAX_PLAYERS]Soldier {
	if ticks_ago >= history.count {
		return nil
	}
	return &history.soldiers[(history.newest - ticks_ago) % HISTORY_TICKS]
}

// A hit lands (the C game's damage_apply): its shove and spray on every machine, then,
// where this machine decides, its wound.
@(private = "file")
hit_land :: proc(world: ^World, resources: ^Resources, authority: ^Authority, hit: Hit, out: ^Tick_Output) {
	if !world.soldiers[hit.target].active do return
	soldier_shove(world, resources, hit)
	if authority != nil do judge_hit(world, resources, hit, out)
}

// Suicide is a hit on oneself, applied like any other, and a brutal one.
@(private = "file")
suicide_hit :: proc(world: ^World, id: Soldier_Id) -> Hit {
	return {shooter = id, target = id, weapon = .Punch, amount = 4.0 * DEFAULT_HEALTH, pos = world.soldiers[id].body.pos}
}

// Whether a hit wounds at all: a teammate's doesn't, though it still shoves. There is no
// friendly fire.
wounds :: proc(world: ^World, hit: Hit) -> bool {
	target := &world.soldiers[hit.target]
	attacker := &world.soldiers[hit.shooter]
	if target.team != .None && target.team == attacker.team && hit.target != hit.shooter do return false
	return true
}

// What a hit would take off its target's health: none where it does not wound. Every
// machine asks it, to foresee a kill a bullet goes on through.
hit_damage :: proc(world: ^World, hit: Hit) -> f32 {
	return hit.amount if wounds(world, hit) else 0
}

// The wound of a hit, and the death of a soldier it leaves below 1. A corpse is wounded
// too, which is what tears it apart, but dies once.
@(private = "file")
judge_hit :: proc(world: ^World, resources: ^Resources, hit: Hit, out: ^Tick_Output) {
	if hit.amount <= 0 || !wounds(world, hit) do return
	target := &world.soldiers[hit.target]
	damage := Damage {
		attacker = hit.shooter,
		target   = hit.target,
		weapon   = hit.weapon,
		amount   = hit_damage(world, hit),
		part     = hit.part,
	}
	rule(world, resources, damage, out)
	if target.vitals.dead || target.vitals.health >= 1.0 do return

	// whether the body burns (Sprites.pas Die, "Fire on from bullet")
	fire: u8
	#partial switch hit.weapon {
	case .M79:          if rng_below(&world.rng, 8) == 0 do fire = 2
	case .Frag_Grenade: if rng_below(&world.rng, 12) == 0 do fire = 4
	}
	rule(world, resources, Kill {
		killer    = hit.shooter,
		target    = hit.target,
		weapon    = hit.weapon,
		pos       = target.body.pos,
		part      = hit.part,
		impact    = hit.impact,
		fire      = fire,
		distance  = hit.distance,
		airtime   = hit.airtime,
		ricochets = hit.ricochets,
	}, out)
}

// The soldiers and the things as they stood at the end of `tick`, if it is still kept.
history_at :: proc(history: ^History, tick: u32) -> (soldiers: ^[MAX_PLAYERS]Soldier, things: ^[MAX_THINGS]Thing, ok: bool) {
	if tick > history.newest || history.newest - tick >= history.count {
		return
	}
	return &history.soldiers[tick % HISTORY_TICKS], &history.things[tick % HISTORY_TICKS], true
}
