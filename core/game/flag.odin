package game

import res "../resources"
import "../utils"

// The flags: in base or not, grabbed, sent home, captured, thrown. Their carrying and
// timing out are every thing's (thing.odin); who grabs, returns and captures one is the
// referee's (referee_things.odin), and the rulings it makes are carried out here.

BASE_RADIUS :: f32(75) // a flag this near its spawn is in base
TOUCHDOWN_RADIUS :: f32(28) // a carrier this near its own flag, at home, captures
FLAG_THROW_POWER :: f32(4.225)
FLAG_GRAB_COOLDOWN :: TICK_RATE / 4 // a flag just thrown can't be grabbed back at once

// The team a flag is: the one that defends it and sends it home.
flag_team :: proc(kind: Thing_Kind) -> res.Team {
	return .Alpha if kind == .Alpha_Flag else .Bravo
}

// Where a flag's base is measured from: the map's first spawn point of its kind.
flag_base :: proc(polymap: ^res.Poly_Map, kind: Thing_Kind) -> utils.Vec2 {
	want: res.Spawn_Kind = .Alpha_Flag if kind == .Alpha_Flag else .Bravo_Flag
	for spawnpoint in polymap.spawnpoints {
		if spawnpoint.active && spawnpoint.kind == want do return spawnpoint.pos
	}
	return {}
}

// The flag's own tick, after its physics: in base or not; carried home by its own team
// it is back at its spawn, carried to the other flag a capture.
flag_update :: proc(world: ^World, resources: ^Resources, id: Thing_Id, authority: ^Authority, out: ^Tick_Output) {
	thing := &world.things[id]
	thing.in_base = utils.length(thing.points[0] - flag_base(world.polymap, thing.kind)) < BASE_RADIUS
	if thing.in_base {
		thing.timeout = FLAG_TIMEOUT
		thing.interest = FLAG_INTEREST_TIME
		if judge_flag_home(world, resources, authority, id, out) do return
	}
	judge_touchdown(world, resources, authority, id, out)
}

// Whether the flag's carrier, of the other team, has it at the carrier's own flag, at
// home and loose.
flag_touches_down :: proc(world: ^World, id: Thing_Id) -> bool {
	thing := &world.things[id]
	carrier := &world.soldiers[thing.holder.?]
	if carrier.team == flag_team(thing.kind) do return false
	for &other, i in world.things {
		if Thing_Id(i) == id || other.kind == .None || !other.in_base || other.holder != nil do continue
		if utils.length(thing.points[0] - other.points[0]) < TOUCHDOWN_RADIUS do return true
	}
	return false
}

// Touched, a flag stirs, and is kept from timing out.
flag_touch :: proc(thing: ^Thing) {
	thing.resting = false
	thing.timeout = FLAG_TIMEOUT
	thing.interest = FLAG_INTEREST_TIME
}

// Taken up: it hangs from the hand from its next tick.
flag_grab :: proc(world: ^World, grab: Flag_Grab) {
	world.things[grab.flag].holder = grab.soldier
}

// A point on the carrier's tally, and the flag home.
flag_capture :: proc(world: ^World, resources: ^Resources, capture: Flag_Capture) {
	world.soldiers[capture.soldier].tally.flags += 1
	thing_respawn(world, resources, capture.flag)
}

// The flag the soldier carries thrown toward its aim (TSprite.ThrowFlag), from off the
// thrower so it isn't grabbed back at once; not if it would be in a wall next tick.
flag_throw :: proc(world: ^World, resources: ^Resources, id: Soldier_Id) {
	soldier := &world.soldiers[id]
	for &thing in world.things {
		if holder, held := thing.holder.?; !held || holder != id || !thing_is_flag(thing.kind) do continue

		joints := soldier_pose(resources.animations, soldier, soldier.body.pos)
		direction := utils.normalize(soldier.controls.aim - joints[14]) * FLAG_THROW_POWER
		offset := direction * 5.0
		velocity := direction + soldier.body.velocity
		ahead := offset + velocity

		pole := thing.points[0] + ahead
		blocked := false
		for k in 1 ..< 4 {
			if blocked do break
			_, blocked = res.ray_cast(world.polymap, joints[14], thing.points[k] + ahead, 200, res.Ray_Filter{flag = true})
		}
		for corner in ([4]utils.Vec2{{-10, -8}, {10, -8}, {-10, 8}, {10, 8}}) {
			if blocked do break
			_, blocked = res.inside_solid(world.polymap, pole + corner, true)
		}
		if blocked do continue

		for k in 0 ..< 4 {
			thing.points[k] = thing.points[k] + offset + velocity
			thing.old_points[k] = thing.points[k] - velocity
		}
		// a little spin, for the look of it
		spin := utils.normalize({-velocity.y, velocity.x}) * f32(soldier.body.direction)
		thing.points[0] = thing.points[0] - spin
		thing.points[1] = thing.points[1] + spin

		thing.holder = nil
		soldier.carrying.held = nil
		soldier.carrying.flag_grab_cooldown = FLAG_GRAB_COOLDOWN
		thing.background = {in_transition = true}
		thing.resting = false
	}
}
