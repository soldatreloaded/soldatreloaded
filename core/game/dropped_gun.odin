package game

import sa "core:container/small_array"

import res "../resources"

// Guns on the ground: thrown from a hand, let go of by a death, a thrown knife that
// landed (Sprites.pas DropWeapon, Die; Things.pas). A two-point thing, karabin.po at the
// gun's length, carrying the weapon and its ammo; it resists pickup for half a second,
// lies a while and goes if nobody takes it. The server lays them down (the Gun_Drop and
// Knife_Land rulings), at the things' turn after they are asked for, and gives them to
// whoever takes one (the Pickup ruling).

PICKUP_RESIST :: GUN_RESIST_TIME - 30 // no taking it for its first half second

// The gun out of the hand, laid down where the hand was, flying as the death or the
// throw sends it: a death gives its muzzle the killing blow.
dropped_gun_drop :: proc(world: ^World, resources: ^Resources, drop: Gun_Drop) {
	id, made := thing_create(world, resources, .Weapon, drop.pos, drop.weapon, owner = drop.owner)
	if !made do return
	world.things[id].ammo = drop.ammo
	if !drop.thrown do world.things[id].forces[1] = drop.impact
}

// A thrown knife that stopped lies there, a knife to pick up.
thrown_knife_land :: proc(world: ^World, resources: ^Resources, land: Knife_Land) {
	thing_create(world, resources, .Weapon, land.pos, .Knife, owner = land.owner)
}

// Whether the soldier would take the gun: empty-handed, with no gun among this turn's
// gifts for it yet (the original hands a gun over at once, so a second lying with it
// finds the hand full), not changing guns, once the gun has lain past its resistance.
dropped_gun_wanted :: proc(world: ^World, thing: ^Thing, id: Soldier_Id) -> bool {
	soldier := &world.soldiers[id]
	if soldier.arsenal.primary.weapon != .Punch || soldier.pose.body.id == .Change do return false
	for gift in sa.slice(&world.gifts) {
		if gift.soldier == id && gift.kind == .Weapon do return false
	}
	return thing.timeout < PICKUP_RESIST
}

// Taken: the gun is gone from the ground.
dropped_gun_take :: proc(world: ^World, pickup: Pickup) {
	thing_kill(&world.things[pickup.thing])
}

// The gun into the hands with the ammo it had.
dropped_gun_give :: proc(resources: ^Resources, soldier: ^Soldier, weapon: res.Weapon, ammo: i32) {
	soldier.arsenal.primary = weapon_state(resources, weapon)
	soldier.arsenal.primary.ammo = ammo
}
