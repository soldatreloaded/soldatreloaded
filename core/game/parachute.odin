package game

import res "../resources"
import "../utils"

// The parachute of a spawn high over the map: hung from the soldier's head, slowing its
// fall, let go of on the ground (or with the jets) once the spawn protection has worn
// down a little, and then left to lie a while (TSprite.Parachute, the parachuter in
// TSprite.Update, and TThing.Update's parachute).
//
// The parachute is a thing: it is let go of in its own tick, which reads its holder (a
// living one on the ground or jetting, a corpse landed). The soldier's side, in its own
// step, only reads it back: the lift, and the tick the canopy turned over, which catches
// the fall.

PARACHUTE_DISTANCE :: f32(500) // a spawn with no ground this far below gets one
PARACHUTE_LIFT :: f32(-0.5) * f32(0.06) // against gravity
PARACHUTE_LANDED_TIMEOUT :: 3 * 60

// A parachute for a soldier placed high over the map, hung from it.
parachute_deploy :: proc(world: ^World, resources: ^Resources, id: Soldier_Id) {
	soldier := &world.soldiers[id]
	if soldier.carrying.held != nil || soldier.team == .Spectator do return
	for &thing in world.things {
		if holder, held := thing.holder.?; held && holder == id do thing_kill(&thing)
	}

	pos := soldier.body.pos
	below := utils.Vec2{pos.x, pos.y + PARACHUTE_DISTANCE}
	filter := res.Ray_Filter{player = true, team = soldier.team}
	hit, blocked := res.ray_cast(world.polymap, pos, below, PARACHUTE_DISTANCE + 50, filter)
	if blocked || hit.distance <= PARACHUTE_DISTANCE - 10 do return

	parachute, made := thing_create(world, resources, .Parachute, {pos.x, pos.y + 70}, owner = id)
	if !made do return
	world.things[parachute].holder = id
	soldier.carrying.held = parachute
}

// The parachute's tick: let go of by a living holder on the ground or jetting once the
// spawn protection has worn down a little, or by a corpse landed; else hung from the
// holder's head.
parachute_update :: proc(world: ^World, resources: ^Resources, id: Thing_Id) {
	thing := &world.things[id]
	thing.flipped = false
	holder_id, held := thing.holder.?
	if !held do return

	holder := &world.soldiers[holder_id]
	corpse := &world.corpses[holder_id]
	if holder.vitals.dead {
		if corpse.active && corpse.on_ground do let_go(thing, holder)
	} else if holder.vitals.cease_fire < DEFAULT_CEASE_FIRE - 30 && (holder.body.on_ground || .Jet in holder.controls.buttons) {
		let_go(thing, holder)
	}
	if thing.holder == nil do return

	// the lines meet at the head, the living one's or the corpse's
	if holder.vitals.dead && corpse.active {
		thing.points[3] = corpse.points[11]
	} else {
		thing.points[3] = soldier_pose(resources.animations, holder, holder.body.pos)[11]
	}
	thing.forces[0].y = -holder.body.velocity.y
	holder.carrying.held = id

	// the canopy turned over: the lines swap, and the fall catches for a tick
	if thing.points[2].x < thing.points[3].x {
		head := thing.points[3]
		thing.points[3] = thing.points[2]
		thing.old_points[3] = thing.points[2]
		thing.points[2] = head
		thing.old_points[2] = head
		thing.flipped = true
	}

	// The line to the holder is cut: the parachute lies where it is a while.
	let_go :: proc(thing: ^Thing, holder: ^Soldier) {
		thing.holder = nil
		thing.cut += 1
		thing.timeout = PARACHUTE_LANDED_TIMEOUT
		holder.carrying.held = nil
	}
}

// Before the soldier's integration: a canopy that turned over catches the fall a tick.
parachute_catch :: proc(world: ^World, soldier: ^Soldier) {
	if thing := parachute_of(world, soldier); thing != nil && thing.flipped do soldier.body.forces.y = world.gravity
}

// After the soldier's step: the lift, for the next, and whether it hangs from one, which
// the next step's left and right read.
parachute_carry :: proc(world: ^World, soldier: ^Soldier) {
	soldier.carrying.parachuting = parachute_of(world, soldier) != nil
	if soldier.carrying.parachuting do soldier.body.forces.y = PARACHUTE_LIFT
}

// A holder's steer, at the things' turn. The canopy's corners are points 1 and 2:
// steering right pulls 1 down and lifts 2, left the other way (Control.pas, the left
// and right keys under a parachute).
parachute_steer :: proc(world: ^World, steer: Parachute_Steer) {
	thing := &world.things[steer.thing]
	if thing.kind == .None || thing.point_count < 3 do return
	thing.forces[1].y += 0.5 * f32(steer.way)
	thing.forces[2].y -= 0.5 * f32(steer.way)
}

// The parachute the soldier hangs from, if it does.
@(private = "file")
parachute_of :: proc(world: ^World, soldier: ^Soldier) -> ^Thing {
	held, holding := soldier.carrying.held.?
	if !holding || world.things[held].kind != .Parachute do return nil
	return &world.things[held]
}
