package game

import "core:math"

import res "../resources"
import "../utils"

// A grenade or rocket going off (TBullet.ExplosionHit): a Hit on every soldier in the
// radius, the corpses and the things thrown about, the grenades and rockets near it set
// off.
//
// Who judges the living depends on whose the blast is (hit_claim.odin). A client's own
// grenade or rocket, gone off by its own flight there, wounds the living as its screen
// had them, and is claimed; the server, seeing the claim again, wounds them as that
// screen had them, and tells everyone. Anywhere else a client's blast touches only the
// dead and the things: the living are the server's word. The server judges every other
// blast itself: its bots', a chain's, and one a claim never came for.

Explosion_Kind :: enum u8 {
	Frag, // a frag grenade
	M79,  // an M79 grenade, a LAW rocket
}

// Why a blast goes off.
Blast_Cause :: enum u8 {
	Flight,  // its own flight here: a wall, a collider, a body, its time
	Chain,   // another blast near it
	Told,    // the server's word of it (bullet_shot_end)
	Claimed, // its client's claim, seen again (the server)
	Lapsed,  // the server's own: a client's no claim came for in time
}

M79_EXPLOSION_RADIUS :: f32(64)
FRAG_EXPLOSION_RADIUS :: f32(85)
AFTER_EXPLOSION_RADIUS :: f32(50) // grenades and rockets this near go off too
EXPLOSION_IMPACT_MULTIPLY :: f32(3.75)
EXPLOSION_DEADIMPACT_MULTIPLY :: f32(4.5)
CORPSE_BLAST_POINTS :: 16 // the corpse's points a blast throws about

// Bullet `id` goes off where it is, and ends. `hit_soldier` and `hit_part` name a
// soldier it struck directly, and the pose point struck; else nil and -1.
explode :: proc(
	world: ^World,
	resources: ^Resources,
	id: Bullet_Id,
	kind: Explosion_Kind,
	hit_soldier: Maybe(Soldier_Id),
	hit_part: int,
	authority: ^Authority,
	cause: Blast_Cause,
	out: ^Tick_Output,
) {
	bullet := &world.bullets[id]
	radius := explosion_radius(kind)
	shot_end_tell(authority, bullet, bullet.pos, kind, nil, out) // where it went off, for the clients' own flights of it
	if authority != nil { // a client's, gone off here however it did: its end is done, a claim of it after lands nothing
		if record := bullet_record(authority, bullet); record != nil do record.settled = true
	}
	emit(out, Explosion{owner = bullet.owner, weapon = explosion_weapon(kind), pos = bullet.pos, velocity = bullet.velocity, radius = radius})

	// whose the living are: see above
	own := authority == nil && !world.soldiers[bullet.owner].remote && cause == .Flight
	judged := own || (authority != nil && !(bullet.heard && cause == .Claimed))
	victims: bit_set[0 ..< MAX_PLAYERS; u32]
	for &soldier, i in world.soldiers {
		if !soldier.active || soldier.team == .Spectator do continue
		if soldier.vitals.dead {
			blast_corpse(world, resources, bullet, Soldier_Id(i), kind, out)
		} else if judged || (authority != nil && Soldier_Id(i) == bullet.owner) { // its thrower, the server's to judge (hit_decided_elsewhere)
			target := bullet_target(world, authority, bullet, i) // as the thrower saw it
			if blast_soldier(world, resources, bullet, Soldier_Id(i), target, kind, hit_soldier, hit_part, authority, judged, out) && Soldier_Id(i) != bullet.owner {
				victims += {i}
			}
		}
	}
	if own {
		emit(out, Blast_Claimed {
			owner    = bullet.owner,
			shot     = bullet.shot,
			fired    = bullet.fired,
			airtime  = u16(clamp(resources.weapons[bullet.weapon].timeout - bullet.timeout, 0, 65535)),
			weapon   = bullet.weapon,
			kind     = kind,
			pos      = bullet.pos,
			velocity = bullet.velocity,
			direct   = hit_soldier,
			part     = u8(max(hit_part, 0)),
			victims  = victims,
		})
	}

	// the things it may shove: every point in range has its last place pulled back, which
	// the Verlet step turns into a kick away from the blast
	for &thing in world.things {
		if thing.kind == .None || !thing_collides_with_bullets(world, &thing) do continue
		for k in 0 ..< thing.point_count {
			a := bullet.pos - thing.points[k]
			distance2 := a.x * a.x + a.y * a.y
			if distance2 >= radius * radius do continue
			thing.old_points[k] = thing.old_points[k] + a * (0.5 * (1.0 / (math.sqrt(distance2) + 1.0)) * EXPLOSION_IMPACT_MULTIPLY)
			thing.resting = false
		}
	}

	// and it sets off the grenades and rockets near it, held ones too
	bullet_end(world, id, out)
	for &other, i in world.bullets {
		if !other.active do continue
		if other.style != .Frag_Grenade && other.style != .M79 && other.style != .LAW do continue
		a := bullet.pos - other.pos
		if a.x * a.x + a.y * a.y >= AFTER_EXPLOSION_RADIUS * AFTER_EXPLOSION_RADIUS do continue
		other.held = 0
		explode(world, resources, Bullet_Id(i), .Frag if other.style == .Frag_Grenade else .M79, nil, -1, authority, .Chain, out)
	}
}

// A grenade or rocket going off by its own flight (a wall, a collider, its time): at once
// where the blast is this machine's to decide; else held where it is for the word of it
// (hit_claim.odin), and false.
explode_flight :: proc(world: ^World, resources: ^Resources, id: Bullet_Id, kind: Explosion_Kind, authority: ^Authority, out: ^Tick_Output) -> (went_off: bool) {
	bullet := &world.bullets[id]
	if bullet_held_for_word(world, authority, bullet) {
		bullet_hold(bullet, kind, authority)
		return false
	}
	explode(world, resources, id, kind, nil, -1, authority, .Flight, out)
	return true
}

// The server's word of where a shot ended, for the clients' own flights of it (EventShotEnd):
// in a blast of `blast`, or with nil stopped in a body at `pos`, `target`'s if told. Only
// with authority: a client's shots end as the server's word puts them (bullet_shot_end).
shot_end_tell :: proc(authority: ^Authority, bullet: ^Bullet, pos: utils.Vec2, blast: Maybe(Explosion_Kind), target: Maybe(Soldier_Id), out: ^Tick_Output) {
	if authority == nil do return
	emit(out, Shot_End{owner = bullet.owner, shot = bullet.shot, fired = bullet.fired, weapon = bullet.weapon, pos = pos, blast = blast, target = target})
}

explosion_radius :: proc(kind: Explosion_Kind) -> f32 {
	switch kind {
	case .Frag: return FRAG_EXPLOSION_RADIUS
	case .M79:  return M79_EXPLOSION_RADIUS
	}
	return 0
}

// The weapon whose numbers the blast hits by.
explosion_weapon :: proc(kind: Explosion_Kind) -> res.Weapon {
	return .M79 if kind == .M79 else .Frag_Grenade
}

// What a blast of `kind` at `pos` does to a living soldier of skeleton `joints`: the pose
// point nearest it (or `struck`, the one it met directly, if not -1) takes a wound
// falling off with distance, and the soldier is thrown from it; nothing past the radius.
// Spawn protection spares the wound, not the throw.
blast_on :: proc(resources: ^Resources, kind: Explosion_Kind, pos: utils.Vec2, joints: ^Joints, cease_fire: i32, struck: int) -> (amount: f32, part: int, push, impact: utils.Vec2, reached: bool) {
	stats := &resources.weapons[explosion_weapon(kind)].stats
	radius := explosion_radius(kind)
	part = struck
	if part < 0 {
		best := max(f32)
		for k in HIT_PARTS {
			d := pos - joints[k]
			distance := d.x * d.x + d.y * d.y
			if distance < best {
				best = distance
				part = k
			}
		}
	}
	a := pos - joints[part]
	distance2 := a.x * a.x + a.y * a.y
	if distance2 >= radius * radius do return
	distance := math.sqrt(distance2)
	a = a * (1.0 / (distance + 1.0)) * EXPLOSION_IMPACT_MULTIPLY
	a.y *= 2.0
	if cease_fire < 0 do amount = (1.0 / (distance + 1.0)) * stats.damage * hitbox_modifier(stats, part)
	return amount, part, a * -1.0, a, true
}

// A living soldier in the blast (blast_on): its Hit, and on the server its word to the
// soldier's own client, which takes the throw from it (Shot_Hit). Whether it reached.
@(private = "file")
blast_soldier :: proc(
	world: ^World,
	resources: ^Resources,
	bullet: ^Bullet,
	id: Soldier_Id,
	soldier: ^Soldier,
	kind: Explosion_Kind,
	hit_soldier: Maybe(Soldier_Id),
	hit_part: int,
	authority: ^Authority,
	tell: bool, // its throw for its own client: not for a claimed blast's thrower, whose client threw it itself
	out: ^Tick_Output,
) -> bool {
	struck := -1
	if who, direct := hit_soldier.?; direct && who == id && hit_part >= 0 do struck = hit_part
	amount, part, push, impact, reached := blast_on(resources, kind, bullet.pos, &soldier.pose.skeleton, soldier.vitals.cease_fire, struck)
	if !reached do return false
	pos := soldier.pose.skeleton[part]
	emit(out, Hit{shooter = bullet.owner, target = id, weapon = bullet.weapon, amount = amount, part = 0, pos = pos, push = push, impact = impact, spray = true})
	if authority != nil && tell {
		emit(out, Shot_Hit{owner = bullet.owner, shot = bullet.shot, fired = bullet.fired, weapon = bullet.weapon, target = id, push = push, blast = true})
	}
	return true
}

// The dead: every point in reach is thrown, and the body takes a wound by the last of
// them, which is what tears it apart.
@(private = "file")
blast_corpse :: proc(world: ^World, resources: ^Resources, bullet: ^Bullet, id: Soldier_Id, kind: Explosion_Kind, out: ^Tick_Output) {
	corpse := &world.corpses[id]
	if !corpse.active do return
	stats := &resources.weapons[explosion_weapon(kind)].stats
	radius := explosion_radius(kind)

	reached := false
	last: f32 = 0
	for k in 0 ..< CORPSE_BLAST_POINTS {
		a := bullet.pos - corpse.points[k]
		distance2 := a.x * a.x + a.y * a.y
		if distance2 >= radius * radius do continue
		distance := math.sqrt(distance2)
		corpse.old_points[k] = corpse.old_points[k] + a * ((1.0 / (distance + 1.0)) * EXPLOSION_DEADIMPACT_MULTIPLY)
		reached = true
		last = distance
	}
	if !reached do return

	if kind == .M79 do last = max(last, 20.0000001)
	emit(out, Hit{shooter = bullet.owner, target = id, weapon = bullet.weapon, amount = (1.0 / (last + 1.0)) * stats.damage, part = 0, pos = bullet.pos})
}
