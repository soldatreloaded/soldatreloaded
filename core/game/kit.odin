package game

import sa "core:container/small_array"

import "../utils"

// The kits: the medical and grenade kits of the map, which move to another of their
// spawn points when taken. Who may take which, and what each gives.
//
// sv_healthcooldown: the original sets HasPack on taking a medikit and clears it only
// when the player joins, so with the setting on (its default) a player takes one medikit
// a game. The setting says it is the wait before a second one, and that is what this does.

KIT_SPAWN_JITTER :: 25 // a kit comes up this far either way of its spawn point (SPAWNRANDOMVELOCITY)

// `amount` kits of a kind, each at a spawn point of its kind, none if the map has none.
kits_spawn :: proc(world: ^World, resources: ^Resources, kind: Thing_Kind, amount: int) {
	for _ in 1 ..= amount {
		pos, found := kit_spawn_point(world, kind)
		if !found do return
		thing_create(world, resources, kind, pos)
	}
}

// Where a new kit of the kind comes up: about one of its spawn points; not `found` if the
// map has none.
@(private = "file")
kit_spawn_point :: proc(world: ^World, kind: Thing_Kind) -> (pos: utils.Vec2, found: bool) {
	spawn := spawn_kind(kind)
	// The kits go round their spawn points, not twice running at the same; the original
	// keeps that memory in the pool's next-to-last slot, whatever thing is in it.
	pos, found = thing_spawn_boxes(world.polymap, spawn, &world.things[MAX_THINGS - 2], &world.rng)
	if !found {
		pos, found = thing_spawn_point(world.polymap, spawn, &world.rng)
		if !found do return
	}
	pos.x = pos.x - KIT_SPAWN_JITTER + f32(rng_below(&world.rng, 2 * 100 * KIT_SPAWN_JITTER)) / 100.0
	pos.y = pos.y - KIT_SPAWN_JITTER + f32(rng_below(&world.rng, 2 * 100 * KIT_SPAWN_JITTER)) / 100.0
	return
}

// Whether the soldier has use for the kit: hurt, and not just healed, for a medikit;
// short of grenades for a grenade kit.
kit_wanted :: proc(world: ^World, kind: Thing_Kind, soldier: ^Soldier) -> bool {
	#partial switch kind {
	case .Medical_Kit: return soldier.vitals.health < DEFAULT_HEALTH && soldier.carrying.medikit_cooldown <= 0
	case .Grenade_Kit: return soldier.arsenal.grenades < world.rules.max_grenades
	}
	return false
}

// Taken: the kit comes up again at another of its spawn points. A medikit's taker waits
// for the next.
kit_take :: proc(world: ^World, resources: ^Resources, pickup: Pickup) {
	if pickup.kind == .Medical_Kit do world.soldiers[pickup.soldier].carrying.medikit_cooldown = world.rules.medikit_cooldown
	thing_respawn(world, resources, pickup.thing)
}

// The soldier as the end of the turn will leave it, given the kits and guns it has taken
// so far this turn: what the next is judged against, so two lying together aren't both
// taken by one the first filled (the original gives at once).
gift_receiver :: proc(world: ^World, resources: ^Resources, id: Soldier_Id) -> Soldier {
	soldier := world.soldiers[id]
	for gift in sa.slice(&world.gifts) {
		if gift.soldier != id do continue
		if gift.kind == .Weapon {
			dropped_gun_give(resources, &soldier, gift.weapon, gift.ammo)
		} else {
			kit_give(world, &soldier, gift.kind)
		}
	}
	return soldier
}

// What the kit gives: the health back, or the grenades.
kit_give :: proc(world: ^World, soldier: ^Soldier, kind: Thing_Kind) {
	#partial switch kind {
	case .Medical_Kit: soldier.vitals.health = DEFAULT_HEALTH
	case .Grenade_Kit: soldier.arsenal.grenades = world.rules.max_grenades
	}
}
