package game

import sa "core:container/small_array"

// What the things give the soldiers: a kit's gift, a gun into the hands. The thing is
// taken in its own tick (the Pickup ruling); what it gives is the soldier's at the end of
// the things' turn, as the C game's receipts pass gives it, so the things after it this
// turn find the soldier as it was.

MAX_GIFTS :: MAX_THINGS

// A kit or gun taken by a soldier: gone, or a map's kit up again elsewhere; what it gives
// is kept for the end of the turn.
thing_pick_up :: proc(world: ^World, resources: ^Resources, pickup: Pickup) {
	if pickup.kind == .Weapon {
		dropped_gun_take(world, pickup)
	} else {
		kit_take(world, resources, pickup)
	}
	sa.push_back(&world.gifts, pickup)
}

// At the end of the things' turn: what they gave, in the order it was taken.
soldiers_receive :: proc(world: ^World, resources: ^Resources) {
	for gift in sa.slice(&world.gifts) {
		soldier := &world.soldiers[gift.soldier]
		if gift.kind == .Weapon {
			dropped_gun_give(resources, soldier, gift.weapon, gift.ammo)
		} else {
			kit_give(world, soldier, gift.kind)
		}
	}
	sa.clear(&world.gifts)
}
