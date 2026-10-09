package game

import sa "core:container/small_array"
import "core:math/linalg"

import res "../resources"
import "../utils"

// Hits on the shooter's word. Every machine shows the others where it last heard of
// them, stepped on the keys they were last heard with when a snapshot is slow to come;
// a shot is hit or missed on its shooter's screen against that picture. So that what
// the shooter saw is what lands, its client says which bodies its own bullets met
// (a claim), and the server sees the claim again: the shot's flight as it flew there,
// against the target made again from the snapshot the shooter's picture of it was taken
// from, stepped as the client stepped it. A claim that holds lands as any hit does, and
// the server tells everyone (Shot_Hit), so the victim and the onlookers show the hit the
// shooter saw, and none their own flights of it would have made.
//
// Claimed: the bullets and the blades, on the living. The grenades, the rockets and the
// thrown knife are judged by the server as before, against the shooter's past
// (bullet_target), and the onlookers shown where it says they ended (Shot_End); every hit
// on a corpse by every machine for itself.

// A bullet the shooter's own client met a living body with: the event its client
// claims it by (client_stream_collect), on that client alone.
Hit_Claimed :: struct {
	owner:    Soldier_Id,
	shot:     u32, // the owner's number for it, which the server's word of its count can hand out again
	fired:    u32, // the tick it was fired in: with the number, which shot it was
	airtime:  u16, // the ticks of its flight before this one: where in its flight it was
	weapon:   res.Weapon,
	target:   Soldier_Id,
	part:     u8,         // the pose point met, 0-based
	pos:      utils.Vec2, // the bullet where it was met from
	velocity: utils.Vec2,
	start:    utils.Vec2, // where the path met on began: the bullet, or a blade's hand
	point:    utils.Vec2, // where it met the body
	stopped:  bool,       // the bullet ended in it
}

// The claim on the wire: the event, and the picture of the target it was met in: the
// snapshot it was taken from and the tick it was taken in, each as ticks back from the
// hit; the steps it was taken with, on its last keys, and the ticks' steps since. The
// server steps the target from that snapshot as the client did.
Hit_Claim :: struct {
	using claimed: Hit_Claimed,
	seen:          u8,
	taken:         u8,
	pre:           u8,
	steps:         u8,
}

// The server's word of a hit on the living, to everyone but its shooter: the blood on the
// target's body as it is drawn where it is heard, the shove to the target's own client,
// and the bullet ended if it stopped.
Shot_Hit :: struct {
	owner:    Soldier_Id,
	shot:     u32,
	fired:    u32, // the tick it was fired in: with the number, which shot it was
	weapon:   res.Weapon,
	target:   Soldier_Id,
	part:     u8,         // the pose point met, 0-based
	offset:   utils.Vec2, // the point met, from the pose point
	velocity: utils.Vec2, // the bullet's, which the blood flies with
	push:     utils.Vec2,
	stopped:  bool,
}

SEEN_STEPS_MAX :: 16 // a snapshot is stepped this far at most where it is taken: past it, it stands
CLAIM_SEEN_MAX :: 30 // ticks back a claim's picture may be from: as far as a shot is run forward
CLAIM_HITS_MAX :: 8  // claims a shot may land
CLAIM_PATH_SLACK :: f32(1.5) // how far off its shot's flight a claimed bullet may be: a pierce slows it a little behind
CLAIM_BODY_SLACK :: f32(1)   // past a pose point's radius, for the picture made again
MELEE_REACH :: f32(40)       // from the hand to the blade

// Whether a bullet of `style` is claimed by its shooter's client.
claimed_style :: proc(style: Bullet_Style) -> bool {
	#partial switch style {
	case .Plain, .Shotgun, .Punch, .Knife: return true
	}
	return false
}

// Whether a living body this bullet meets is for another machine to decide: on a client,
// every bullet but its own soldier's (the server tells, Shot_Hit and Shot_End); on the
// server, a client's of the claimed kinds (Hit_Claim), but on its own shooter, whose
// picture on its own screen is no snapshot's, and which the server judges.
hit_decided_elsewhere :: proc(world: ^World, authority: ^Authority, bullet: ^Bullet, target: Soldier_Id) -> bool {
	if authority == nil do return world.soldiers[bullet.owner].remote
	return bullet.heard && claimed_style(bullet.style) && target != bullet.owner
}

// ---------------------------------------------------------------------------------
// The server's records of the shots its clients fired: each tick of the flight as it
// flew there, which a claim is held to.

SHOT_RECORDS :: 2048           // shots kept: a busy server's seconds of them, each to the end of its flight
SHOT_TRACE_MAX :: BULLET_TIMEOUT // a flight is kept to its end: a long shot is claimed late in it

Shot_Records :: struct {
	records: [SHOT_RECORDS]Shot_Record,
	next:    int,
	scratch: Tick_Output, // what the steps of a claim's target made again say, which nobody hears
}

Shot_Record :: struct {
	used:       bool,
	owner:      Soldier_Id,
	shot:       u32,
	weapon:     res.Weapon,
	fired:      u32,        // the tick it was fired in, on its owner's machine
	fired_from: utils.Vec2,
	bullet:     Bullet_Id,  // its flight here, while it lasts
	hits:       int,        // claims landed
	trace:      [dynamic]Shot_Trace, // a tick of the flight each; kept from shot to shot, freed by shot_records_destroy
}

// The bullet as a tick of its flight meets the bodies: past the map, which may have
// turned it.
Shot_Trace :: struct {
	pos, velocity: utils.Vec2,
	damage:        f32,
	ricochets:     i32,
}

// A record for a client's shot just heard, fired in `tick`, in the place of the oldest.
shot_record_begin :: proc(authority: ^Authority, bullet: ^Bullet, id: Bullet_Id, tick: u32) {
	records := &authority.shots
	index := records.next
	records.next = (records.next + 1) % SHOT_RECORDS
	record := &records.records[index]
	trace := record.trace
	clear(&trace)
	record^ = {
		used       = true,
		owner      = bullet.owner,
		shot       = bullet.shot,
		weapon     = bullet.weapon,
		fired      = tick,
		fired_from = bullet.fired_from,
		bullet     = id,
		trace      = trace,
	}
	bullet.record = index
}

// The bullet as this tick of its flight meets the bodies (bullet_collide).
shot_record_trace :: proc(authority: ^Authority, bullet: ^Bullet) {
	record := &authority.shots.records[bullet.record]
	if !record.used || record.owner != bullet.owner || record.shot != bullet.shot || record.fired != bullet.fired do return
	if len(record.trace) >= SHOT_TRACE_MAX do return
	append(&record.trace, Shot_Trace{bullet.pos, bullet.velocity, bullet.damage, bullet.ricochet_count})
}

// A new round: the last one's shots are no one's to claim.
shot_records_reset :: proc(records: ^Shot_Records) {
	for &record in records.records {
		record.used = false
		clear(&record.trace)
	}
}

shot_records_destroy :: proc(records: ^Shot_Records) {
	for &record in records.records do delete(record.trace)
}

// The shot numbered `shot` fired in tick `fired`: a number alone may be two shots.
@(private = "file")
shot_record_find :: proc(authority: ^Authority, owner: Soldier_Id, shot: u32, weapon: res.Weapon, fired: u32) -> ^Shot_Record {
	for &record in authority.shots.records {
		if record.used && record.owner == owner && record.shot == shot && record.weapon == weapon && record.fired == fired do return &record
	}
	return nil
}

// ---------------------------------------------------------------------------------
// The claim seen again

// A client's claim, said in `tick`: if it holds, the hit lands, and everyone is told.
hit_claim_judge :: proc(world: ^World, resources: ^Resources, authority: ^Authority, claim: Hit_Claim, tick: u32, out: ^Tick_Output) {
	record := shot_record_find(authority, claim.owner, claim.shot, claim.weapon, claim.fired)
	if record == nil || record.hits >= CLAIM_HITS_MAX do return
	info := &resources.weapons[claim.weapon]
	if !claimed_style(info.bullet_style) do return
	age := int(claim.airtime)
	if age >= len(record.trace) do return
	traced := record.trace[age]

	// the bullet: on its shot's flight, going its way, and no faster
	if !on_flight(record, age, claim.pos) do return
	speed, traced_speed := utils.length(claim.velocity), utils.length(traced.velocity)
	if speed > traced_speed + 0.01 do return
	if speed > 0 && traced_speed > 0 && linalg.dot(claim.velocity / speed, traced.velocity / traced_speed) < 0.995 do return
	melee := info.bullet_style == .Punch || info.bullet_style == .Knife
	if melee {
		if utils.length(claim.start - claim.pos) > MELEE_REACH do return
	} else if utils.length(claim.start - claim.pos) > 0.01 {
		return
	}

	// the target as the shooter's screen had it
	if int(claim.target) >= MAX_PLAYERS || !world.soldiers[claim.target].active do return
	if claim.seen < claim.taken || claim.seen > CLAIM_SEEN_MAX do return
	if int(claim.pre) > SEEN_STEPS_MAX || claim.steps < 1 || claim.steps > CLAIM_SEEN_MAX + 1 do return
	seen, taken := tick - u32(claim.seen), tick - u32(claim.taken)
	target, made := target_as_seen(world, resources, authority, claim.target, seen, taken, int(claim.pre), int(claim.steps))
	if !made || target.vitals.dead || target.vitals.cease_fire >= 0 do return
	part := int(claim.part)
	if !hit_part(part) do return
	center := target.pose.skeleton[part]
	if !melee do center.x -= 2.0 // the sprites sit two pixels off
	if _, met := utils.line_circle_collision(claim.start, claim.pos + claim.velocity, center, PART_RADIUS + CLAIM_BODY_SLACK); !met do return
	if !on_body(&target.pose.skeleton, claim.point, melee) do return

	// it holds: the hit, as the flight here would have made it
	record.hits += 1
	live := &world.soldiers[claim.target]
	owner := &world.soldiers[claim.owner]
	push: utils.Vec2
	if !live.vitals.dead do push = claim.velocity * info.stats.push
	impact := (claim.point - target.pose.skeleton[part]) * 1.3
	impact.y = -impact.y
	emit(out, Hit {
		shooter   = claim.owner,
		target    = claim.target,
		weapon    = claim.weapon,
		amount    = speed * traced.damage * hitbox_modifier(&info.stats, part),
		part      = u8(part + 1),
		pos       = claim.point,
		push      = push,
		impact    = impact,
		spray     = true,
		distance  = utils.length(claim.pos - record.fired_from) / 14.0,
		airtime   = i32(age),
		ricochets = u8(clamp(traced.ricochets, 0, 255)),
	})
	if info.bullet_style == .Punch && !live.vitals.dead && (live.team == .None || live.team != owner.team) {
		res.animation_switch(resources.animations, &live.pose.body, .Throw_Weapon, 11)
	}
	emit(out, Shot_Hit {
		owner    = claim.owner,
		shot     = claim.shot,
		fired    = claim.fired,
		weapon   = claim.weapon,
		target   = claim.target,
		part     = claim.part,
		offset   = claim.point - target.pose.skeleton[part],
		velocity = claim.velocity,
		push     = push,
		stopped  = claim.stopped,
	})
	// its flight here, which went on through, ends where the claim's did
	if claim.stopped {
		bullet := &world.bullets[record.bullet]
		if bullet.active && bullet.heard && bullet.owner == claim.owner && bullet.shot == claim.shot && bullet.weapon == claim.weapon && bullet.fired == claim.fired {
			bullet_end(world, record.bullet, out, claim.point)
		}
	}
}

@(private = "file")
hit_part :: proc(part: int) -> bool {
	for k in HIT_PARTS {
		if k == part do return true
	}
	return false
}

// Whether the point met lies on the body: on one of its pose points, which need not be the
// part met (the point is the last met along the path, in the parts' order, as the
// original's variable holds it).
@(private = "file")
on_body :: proc(skeleton: ^Joints, point: utils.Vec2, melee: bool) -> bool {
	for k in HIT_PARTS {
		center := skeleton[k]
		if !melee do center.x -= 2.0
		if utils.length(point - center) <= PART_RADIUS + CLAIM_BODY_SLACK + 0.01 do return true
	}
	return false
}

// Whether `pos` lies on the shot's flight up to tick `age`: a pierce slows a bullet, which
// then falls a little behind the flight here, which went on through at its speed.
@(private = "file")
on_flight :: proc(record: ^Shot_Record, age: int, pos: utils.Vec2) -> bool {
	for k in 0 ..= age {
		a := record.trace[k].pos
		b := a + record.trace[k].velocity
		if segment_distance(pos, a, b) <= CLAIM_PATH_SLACK do return true
	}
	return false
}

@(private = "file")
segment_distance :: proc(p, a, b: utils.Vec2) -> f32 {
	ab := b - a
	length2 := linalg.dot(ab, ab)
	t: f32 = 0
	if length2 > 0 do t = clamp(linalg.dot(p - a, ab) / length2, 0, 1)
	return utils.length(p - (a + ab * t))
}

// The soldier in `id` as a client showed it, having taken it from the snapshot of tick
// `seen` in tick `taken`: stepped `pre` times there on its last keys, as soldier_apply
// steps it, then `steps` times more, once a tick, as the client's own steps do. (The
// ticks those steps ran in are taken to follow on from `taken`: a view clock nudged in
// between makes a step or two of difference, which the slack absorbs or the claim fails.)
// Made in the world's slot and put back: nothing else in the world is moved, and no dice
// are rolled that the world rolls.
@(private = "file")
target_as_seen :: proc(world: ^World, resources: ^Resources, authority: ^Authority, id: Soldier_Id, seen, taken: u32, pre, steps: int) -> (soldier: Soldier, ok: bool) {
	frame, _, kept := history_at(&authority.history, seen)
	if !kept do return
	if !frame[id].active || frame[id].vitals.dead do return

	saved, rng, now := world.soldiers[id], world.rng, world.tick
	asked := sa.len(world.things_asked)
	scratch := &authority.shots.scratch
	world.soldiers[id] = frame[id]
	world.soldiers[id].remote = true // heard of: its keys move it, and fire nothing
	step :: proc(world: ^World, resources: ^Resources, id: Soldier_Id, at: u32, scratch: ^Tick_Output) {
		world.tick = at
		clear_output(scratch)
		soldier_update(world, resources, id, soldier_last_command(&world.soldiers[id], false), nil, scratch)
	}
	for _ in 0 ..< pre do step(world, resources, id, taken, scratch)
	for k in 0 ..< steps do step(world, resources, id, taken + u32(k), scratch)
	soldier = world.soldiers[id]
	world.soldiers[id], world.rng, world.tick = saved, rng, now
	sa.resize(&world.things_asked, asked)
	return soldier, true
}

// ---------------------------------------------------------------------------------
// The server's word heard

// A hit the server tells of: shown on the body as it stands here, the shove taken if the
// target is this machine's own, the bullet ended if it stopped. A shot of this machine's
// own soldier is shown already, as its flight here met the body.
bullet_shot_hit :: proc(world: ^World, resources: ^Resources, told: Shot_Hit, out: ^Tick_Output) {
	if !world.soldiers[told.owner].remote do return
	target := &world.soldiers[told.target]
	part := int(told.part) if hit_part(int(told.part)) else 0
	at := target.pose.skeleton[part] + told.offset
	if target.active do emit(out, Blood{target = told.target, pos = at, velocity = told.velocity})
	if target.active && !target.remote && !target.vitals.dead {
		target.body.next_push += told.push
		// the hit's spray, as a flight here meeting this soldier gave it: the server's word
		// of the wound, if there is one, is taken as the same hit (soldier_hit_spray)
		soldier_hit_spray(world, resources, told.target, told.owner, .Flown)
		owner := &world.soldiers[told.owner]
		if told.weapon == .Punch && (target.team == .None || target.team != owner.team) {
			res.animation_switch(resources.animations, &target.pose.body, .Throw_Weapon, 11)
		}
	}
	if !told.stopped do return
	for &bullet, i in world.bullets {
		if !bullet.active || bullet.owner != told.owner || bullet.shot != told.shot || bullet.weapon != told.weapon || bullet.fired != told.fired do continue
		bullet_end(world, Bullet_Id(i), out, at)
		return
	}
}
