package game

import res "../resources"
import "../utils"

// A bullet, grenade, rocket or blade in flight: made, its tick (what it meets, then the
// timeout and the damage falling off), its flight, its end. What it does to a soldier is
// a Hit event: a bullet never wounds anyone itself.
//
// As in the original's loop, every bullet has its tick, and then every bullet flies.

BULLET_GRAVITY :: f32(2.25) // a bullet falls this many times the world's gravity
BULLET_DAMPING :: f32(0.99)

Bullet :: struct {
	active:         bool,
	style:          Bullet_Style,
	weapon:         res.Weapon,
	owner:          Soldier_Id,
	shot:           u32, // the owner's count of its bullets: the same number on every machine
	command:        u32, // the owner's command that fired it
	lag:            u8,  // ticks behind the present it meets soldiers at, as its shooter saw them
	pos, old_pos:   utils.Vec2,
	velocity:       utils.Vec2,
	forces:         utils.Vec2,
	fired_from:     utils.Vec2, // the damage falls off from here
	last_ricochet:  utils.Vec2, // so one surface deflects it once
	timeout:        i32,
	damage:         f32,
	last_hit:       Maybe(Soldier_Id), // so a piercing bullet hits a soldier once
	ricochet_count: i32,
	degrade_count:  i32,
	knocked:        [4]Knocked_Thing,
	catch_up:       i16, // a heard shot run forward to where its shooter has it: drawn as a trail
	catch_up_start: i16,
	fired:          u32, // the tick it was fired in, on its owner's machine: with its number, which shot it is
	// On the server: a client's shot, heard; its hits on the living are its client's to
	// claim, and its flight is kept in `record` (hit_claim.odin).
	heard:          bool,
	record:         int,
	// Its end waiting for word of it (hit_claim.odin): the ticks it waits more, stopped and
	// unseen; the blast it would be, for the server's own if none comes.
	held:           i32,
	held_kind:      Explosion_Kind,
	met_body:       bool, // a client's flight of another's grenade or rocket went through the living
}

// A thing a bullet pushed recently, not to be pushed again every tick.
Knocked_Thing :: struct {
	thing: Maybe(Thing_Id),
	until: u32,
}

// A bullet asked for: by a weapon, a grenade, a punch, the map, or a shot heard from
// another machine.
Shot :: struct {
	owner:    Soldier_Id,
	weapon:   res.Weapon,
	pos:      utils.Vec2,
	velocity: utils.Vec2,
	damage:   f32,
	number:   u32,  // the owner's count of its bullets
	harmless: bool, // the mercy antic's, which leaves its shooter alone
}

// Puts a shot in flight in the first free slot; false if there is none. The owner's
// count of its bullets follows the shot's number, so word of a shot from elsewhere keeps
// the count in step.
//
// The C game makes the shots asked for at the start of the bullets' turn, in the order
// asked. Made where they are asked, they take the same slots in the same order, as
// nothing frees or takes a slot in between.
bullet_fire :: proc(world: ^World, resources: ^Resources, shot: Shot) -> (id: Bullet_Id, ok: bool) {
	for &bullet, i in world.bullets {
		if bullet.active do continue
		info := &resources.weapons[shot.weapon]
		owner := &world.soldiers[shot.owner]
		if shot.number > owner.arsenal.shot_count do owner.arsenal.shot_count = shot.number
		bullet = {
			active     = true,
			style      = info.bullet_style,
			weapon     = shot.weapon,
			owner      = shot.owner,
			command    = owner.controls.sequence,
			shot       = shot.number,
			pos        = shot.pos,
			old_pos    = shot.pos,
			velocity   = shot.velocity,
			fired_from = shot.pos,
			timeout    = info.timeout,
			damage     = shot.damage,
			last_hit   = shot.owner if shot.harmless else nil,
			fired      = world.tick,
		}
		return Bullet_Id(i), true
	}
	return
}

// A shot heard from another machine fires nothing here: its soldier steps unarmed, so
// the flash, the smoke and the sound that the weapon gives a shot of its own are given
// here instead, once per shooter per tick (a shotgun is one bang), at the muzzle of the
// soldier as it stands here (remote_fire).
bullet_remote_fire :: proc(world: ^World, resources: ^Resources, shot: Shot, out: ^Tick_Output) {
	soldier := &world.soldiers[shot.owner]
	if !soldier.active do return
	joints := &soldier.pose.skeleton
	aim := utils.normalize(soldier.controls.aim - joints[14])
	muzzle := utils.Vec2{joints[14].x - aim.x * 4.0, joints[14].y - aim.y * 4.0 - 2.0}
	soldier.arsenal.fired = true // the gostek's muzzle flash
	emit(out, Fired{shot.owner, shot.weapon, muzzle, shot.velocity})
}

// A shot heard from another machine, run forward `catch_up` ticks to where its shooter
// has it, each step judged against the soldiers as the shooter saw them then
// (bullet_target); caught up, it meets the present like any other. A client draws it
// with a trail over the run. Heard at the start of the bullets' turn, after
// bullets_fade_trails, as the C game takes them. On the server its flight is recorded
// from the tick it was fired in, `fired`, for its client's claims (hit_claim.odin).
bullet_hear :: proc(world: ^World, resources: ^Resources, shot: Shot, catch_up: u8, fired: u32, authority: ^Authority, out: ^Tick_Output) {
	id, made := bullet_fire(world, resources, shot)
	if !made do return
	bullet := &world.bullets[id]
	if authority == nil {
		bullet.catch_up = i16(catch_up)
		bullet.catch_up_start = i16(catch_up)
	}
	bullet.fired = fired // as its owner's machine stamped it: the shot, by its number and this
	if authority != nil {
		bullet.heard = true
		shot_record_begin(authority, bullet, id, fired)
	}
	for a in 0 ..< catch_up {
		if !bullet.active do break
		bullet.lag = catch_up - a
		bullet_update(world, resources, id, authority, out)
		if bullet.active do bullet_fly(bullet, world.gravity)
	}
	bullet.lag = 0
}

// The trails of the shots run forward fade, four ticks of theirs a tick, the gone ones
// too, before anything new is heard (UpdateFrame.pas, after the bullets' updates).
bullets_fade_trails :: proc(world: ^World) {
	for &bullet in world.bullets {
		if bullet.catch_up > 0 do bullet.catch_up -= 4
	}
}

// The server's word of where a shot ended, on a client: its own flight of the shot, if
// still flying, is put there and ended the same way, so a grenade that went off on
// someone there goes off on them here, whatever path it took here. One already ended
// here stays ended: a second blast for it would be a blast twice. A body it stopped in
// that the flight here never met is hit here all the same, for the hit's sound and
// blood (a thrown knife's, which only a flight meeting a body makes).
// TODO(net): heard at the start of the bullets' turn, as the C game takes it.
bullet_shot_end :: proc(world: ^World, resources: ^Resources, end: Shot_End, out: ^Tick_Output) {
	for &bullet, i in world.bullets {
		if !bullet.active || bullet.owner != end.owner || bullet.shot != end.shot || bullet.weapon != end.weapon || bullet.fired != end.fired do continue
		bullet.pos = end.pos
		bullet.old_pos = end.pos
		if kind, blast := end.blast.?; blast {
			bullet.held = 0
			explode(world, resources, Bullet_Id(i), kind, nil, -1, nil, .Told, out)
			return
		}
		if target, told := end.target.?; told && bullet.last_hit != target {
			owner, live := &world.soldiers[bullet.owner], &world.soldiers[target]
			friendly := owner.team != .None && owner.team == live.team && target != bullet.owner
			emit(out, Blood{target = target, pos = end.pos, velocity = bullet.velocity, bloodless = friendly})
		}
		bullet_end(world, Bullet_Id(i), out, end.pos)
		return
	}
}

// One tick of a bullet, all but its flight: the map's edge, what it meets (as
// `authority`'s history has the soldiers where its shooter saw them, else where they
// stand), its timeout, the damage falling off.
bullet_update :: proc(world: ^World, resources: ^Resources, id: Bullet_Id, authority: ^Authority, out: ^Tick_Output) {
	bullet := &world.bullets[id]
	polymap := world.polymap
	bound := f32(polymap.sector_reach * polymap.sector_size - 10)
	if bullet.held > 0 { // waiting for word of its end, stopped
		bullet.held -= 1
		if bullet.held == 0 do bullet_lapse(world, resources, id, authority, out)
		return
	}
	if abs(bullet.pos.x) > bound || abs(bullet.pos.y) > bound {
		bullet_end(world, id, out)
		return
	}

	bullet_collide(world, resources, id, authority, out)
	if !bullet.active || bullet.held > 0 do return

	bullet.timeout -= 1
	if bullet.timeout == 0 {
		#partial switch bullet.style {
		case .Frag_Grenade, .M79, .LAW:
			if !explode_flight(world, resources, id, .Frag, authority, out) do return // the M79 too: a spent round goes off as a frag; held, it waits
		}
		bullet_end(world, id, out)
		return
	}

	// the damage falls off with the distance flown
	weapon := bullet.weapon
	if bullet.timeout % 6 == 0 && weapon != .Barrett && weapon != .M79 && weapon != .Knife && weapon != .LAW {
		distance := utils.length(bullet.fired_from - bullet.pos)
		if (bullet.degrade_count == 0 && distance > 500) || (bullet.degrade_count == 1 && distance > 900) {
			bullet.damage *= 0.5
			bullet.degrade_count += 1
		}
	}
}

// Euler on the bullet, after every bullet's tick (Parts.pas).
bullet_fly :: proc(bullet: ^Bullet, gravity: f32) {
	if bullet.held > 0 do return // stopped where it ended, waiting for word of it
	bullet.forces.y += gravity * BULLET_GRAVITY
	previous := bullet.pos
	bullet.velocity += bullet.forces
	bullet.pos += bullet.velocity
	bullet.velocity *= BULLET_DAMPING
	bullet.old_pos = previous
	bullet.forces = {}
}

// Every end goes through here, so it is told where it happens. `impact`: where it
// stopped against something, if it did.
bullet_end :: proc(world: ^World, id: Bullet_Id, out: ^Tick_Output, impact: Maybe(utils.Vec2) = nil) {
	bullet := &world.bullets[id]
	if !bullet.active do return
	bullet.active = false
	pos, struck := impact.?
	emit(out, Bullet_Ended{bullet = id, owner = bullet.owner, weapon = bullet.weapon, pos = pos if struck else bullet.pos, impact = struck})
}
