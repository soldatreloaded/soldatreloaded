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
// Claimed: everything a soldier fires, throws or swings, on the living. The bullets, the
// blades and the thrown knife by the body each met (Hit_Claim). The grenades and the
// rockets by their blast (Blast_Claim): where and when it went off, the body it went off
// on if one, and the picture of each soldier it reached; the server makes each again and
// wounds it by its distance there, as the blast does (blast_on). The server's own flight
// of a client's grenade, rocket or knife passes through the living and, where it ends on
// the map or its time, is held there for the claim (bullet_hold): it goes off, or the
// knife lands, as the claim says; with none in time, as the server's own (bullet_lapse).
// Every hit on a corpse is each machine's own; a blast set off by another is the server's.

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
	bloodless: bool, // heard, not bled: a teammate's thrown knife
	blast:     bool, // a blast's: the shove alone, no blood
}

// A grenade or rocket of the shooter's own going off on its client, by its own flight
// there (explode): the event its client claims it by (client_stream_collect).
Blast_Claimed :: struct {
	owner:    Soldier_Id,
	shot:     u32,
	fired:    u32, // the tick it was fired in: with the number, which shot it was
	airtime:  u16, // the ticks of its flight before it went off
	weapon:   res.Weapon,
	kind:     Explosion_Kind,
	pos:      utils.Vec2, // where it went off
	velocity: utils.Vec2,
	direct:   Maybe(Soldier_Id), // the body it went off on, if one
	part:     u8,                // and the pose point met there
	victims:  bit_set[0 ..< MAX_PLAYERS; u32], // the living it reached there, its thrower aside
}

// The blast claim on the wire: the event, and each soldier it reached as its client had
// it, a Hit_Claim's picture apiece.
Blast_Claim :: struct {
	using claimed: Blast_Claimed,
	views:         [BLAST_VIEWS]Blast_View,
	view_count:    u8,
}

Blast_View :: struct {
	target:                    Soldier_Id,
	seen, taken, pre, steps:   u8,
}

BLAST_VIEWS :: 8 // soldiers a blast claims, at most

SEEN_STEPS_MAX :: 16 // a snapshot is stepped this far at most where it is taken: past it, it stands
CLAIM_SEEN_MAX :: 30 // ticks back a claim's picture may be from: as far as a shot is run forward
CLAIM_HITS_MAX :: 8  // claims a shot may land
CLAIM_PATH_SLACK :: f32(1.5) // how far off its shot's flight a claimed bullet may be: a pierce slows it a little behind
CLAIM_BODY_SLACK :: f32(2.5) // past a pose point's radius, for the picture made again: the client's picture of a soldier keeps a little of its own state the wire doesn't carry (whether it was jumping, its forces), which steps a pixel or two apart
CLAIM_POINT_SLACK :: f32(3)  // and for the point met, which only places the blood: the last part met, maybe not the one hit
MELEE_REACH :: f32(40)       // from the hand to the blade
BLAST_PATH_SLACK :: f32(3)   // how far off its flight a grenade or rocket may go off: a rocket goes off short of the wall, as it came in

// The ticks a grenade, rocket or knife ended on the map waits for the word of how it
// ended: on the server a client's claim, which comes a round trip after (a knife lands
// then, so not long); on a client the server's word, for another's that went through a
// body here.
HOLD_BLAST :: 90
HOLD_KNIFE :: 20
HOLD_TOLD :: 120

// Whether a bullet of `style` is claimed by the body it met (Hit_Claim): all but the
// grenades and rockets, which are claimed by their blast (Blast_Claim).
hit_claimed_style :: proc(style: Bullet_Style) -> bool {
	return !claimed_end(style) || style == .Thrown_Knife
}

// Whether a bullet of `style` ends, on the map or by its time, as its claim says: a
// grenade, a rocket, a thrown knife.
claimed_end :: proc(style: Bullet_Style) -> bool {
	#partial switch style {
	case .Frag_Grenade, .M79, .LAW, .Thrown_Knife: return true
	}
	return false
}

// Whether a living body this bullet meets is for another machine to decide: on a client,
// every bullet but its own soldier's (the server tells, Shot_Hit and Shot_End); on the
// server, any client's (Hit_Claim, Blast_Claim), but on its own shooter, whose picture on
// its own screen is no snapshot's, and which the server judges.
hit_decided_elsewhere :: proc(world: ^World, authority: ^Authority, bullet: ^Bullet, target: Soldier_Id) -> bool {
	if authority == nil do return world.soldiers[bullet.owner].remote
	return bullet.heard && target != bullet.owner
}

// Whether a grenade, rocket or knife ending on the map or by its time here waits for the
// word of how it ended: on the server, any client's, whose client may have met a body
// with it first (its flight here went through); on a client, another's that went through
// a body here, which its thrower's screen may have met.
bullet_held_for_word :: proc(world: ^World, authority: ^Authority, bullet: ^Bullet) -> bool {
	if !claimed_end(bullet.style) do return false
	if authority != nil do return bullet.heard
	return world.soldiers[bullet.owner].remote && bullet.met_body
}

// The bullet stopped where it ended, unseen, waiting for the word of it: `kind` the blast
// it would be, if a grenade or rocket. Kept in its slot even if its end was already
// told (a rocket's ricochet off a wall it can't leave ends it before it goes off), or
// nothing would ever let it go off.
bullet_hold :: proc(bullet: ^Bullet, kind: Explosion_Kind, authority: ^Authority) {
	switch {
	case authority == nil:              bullet.held = HOLD_TOLD
	case bullet.style == .Thrown_Knife: bullet.held = HOLD_KNIFE
	case:                               bullet.held = HOLD_BLAST
	}
	bullet.held_kind = kind
	bullet.active = true
}

// No word came for a held bullet. On the server it ends as its own flight here had it,
// the server's to judge: the blast goes off, the knife lands. On a client it ends unseen.
bullet_lapse :: proc(world: ^World, resources: ^Resources, id: Bullet_Id, authority: ^Authority, out: ^Tick_Output) {
	bullet := &world.bullets[id]
	if authority == nil {
		bullet_end(world, id, out)
		return
	}
	if record := bullet_record(authority, bullet); record != nil do record.settled = true
	if bullet.style == .Thrown_Knife {
		knife_land(world, bullet)
		bullet_end(world, id, out)
		return
	}
	explode(world, resources, id, bullet.held_kind, nil, -1, authority, .Lapsed, out)
}

// The record of a client's shot heard, by its flight here; nil for any other.
bullet_record :: proc(authority: ^Authority, bullet: ^Bullet) -> ^Shot_Record {
	if !bullet.heard do return nil
	record := &authority.shots.records[bullet.record]
	if !record.used || record.owner != bullet.owner || record.shot != bullet.shot || record.fired != bullet.fired do return nil
	return record
}

// ---------------------------------------------------------------------------------
// Shots fired once dead

// A soldier killed here, its death in the game's time `tick`, the tick its killer's
// screen showed. What it fires after that, its own screen not yet told, is void
// (shot_after_death); such of its shots as already fly here are let go of, unseen, so
// none goes off or lands later on the server's own.
death_seen :: proc(world: ^World, authority: ^Authority, id: Soldier_Id, tick: u32) {
	authority.deaths[id] = {life = world.soldiers[id].vitals.life, tick = tick, set = true}
	for &bullet in world.bullets {
		if !bullet.active || bullet.owner != id || !bullet.heard || bullet.fired <= tick do continue
		if record := bullet_record(authority, &bullet); record != nil do record.settled = true
		bullet.active = false
	}
}

// Whether a shot its owner fired in `fired`, by its own screen's tick, came after its
// death here in the game's time: later than the tick its killer saw it die in, in the
// life it still lies dead in. Such a shot is void: not flown, not told to the others,
// and its claims land nothing. One fired before counts though its shooter is dead by
// the time it is heard: each fired before seeing the other's land, a trade.
shot_after_death :: proc(world: ^World, authority: ^Authority, owner: Soldier_Id, fired: u32) -> bool {
	if authority == nil || int(owner) >= MAX_PLAYERS do return false
	death := &authority.deaths[owner]
	soldier := &world.soldiers[owner]
	return death.set && soldier.vitals.dead && soldier.vitals.life == death.life && fired > death.tick
}

// ---------------------------------------------------------------------------------
// The server's records of the shots its clients fired: each tick of the flight as it
// flew there, which a claim is held to.

SHOT_RECORDS :: 2048           // shots kept: a busy server's seconds of them, each to the end of its flight
SHOT_TRACE_MAX :: BULLET_TIMEOUT // a flight is kept to its end: a long shot is claimed late in it

Shot_Records :: struct {
	records:     [SHOT_RECORDS]Shot_Record,
	next:        int,
	landed:      [LANDED_KEPT]Landed_Hit, // the claims landed lately, round the ring
	landed_next: int,
	scratch:     Tick_Output, // what the steps of a claim's target made again say, which nobody hears
}

// A claim landed: the shove its shooter's client gave the target there, as its own flight
// met it, which that client's picture of the target carries until a snapshot replaces it.
Landed_Hit :: struct {
	owner, target: Soldier_Id,
	tick:          u32, // the tick it was met in, on the shooter's screen
	push:          utils.Vec2,
}

LANDED_KEPT :: 256

Shot_Record :: struct {
	used:       bool,
	index:      int,        // its place among the records
	owner:      Soldier_Id,
	shot:       u32,
	weapon:     res.Weapon,
	fired:      u32,        // the tick it was fired in, on its owner's machine
	fired_from: utils.Vec2,
	bullet:     Bullet_Id,  // its flight here, while it lasts
	hits:       int,        // claims landed
	settled:    bool,       // its end done: a blast gone off, a knife laid down, as claimed or lapsed
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
		index      = index,
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
	if shot_after_death(world, authority, claim.owner, record.fired) do return // fired once dead here
	info := &resources.weapons[claim.weapon]
	if !hit_claimed_style(info.bullet_style) do return
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
	target, made := target_as_seen(world, resources, authority, claim.owner, claim.target, seen, taken, int(claim.pre), int(claim.steps))
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
	knife := info.bullet_style == .Thrown_Knife // a hundredth the wound, no part of the body more than another, no spray, as body_collide's
	amount := speed * traced.damage * 0.01 if knife else speed * traced.damage * hitbox_modifier(&info.stats, part)
	friendly := knife && owner.team != .None && owner.team == live.team && claim.target != claim.owner
	push: utils.Vec2
	if !live.vitals.dead do push = claim.velocity * info.stats.push
	// the shove the shooter's client gave its picture of the target, which its next claims
	// on it are made again with
	landed_add(authority, claim.owner, claim.target, tick, claim.velocity * info.stats.push)
	impact := (claim.point - target.pose.skeleton[part]) * 1.3
	impact.y = -impact.y
	emit(out, Hit {
		shooter   = claim.owner,
		target    = claim.target,
		weapon    = claim.weapon,
		amount    = amount,
		part      = u8(part + 1),
		pos       = claim.point,
		push      = push,
		impact    = impact,
		spray     = !knife,
		distance  = utils.length(claim.pos - record.fired_from) / 14.0,
		airtime   = i32(age),
		ricochets = u8(clamp(traced.ricochets, 0, 255)),
		seen      = clamp(tick, record.fired, world.tick),
	})
	if info.bullet_style == .Punch && !live.vitals.dead && (live.team == .None || live.team != owner.team) {
		res.animation_switch(resources.animations, &live.pose.body, .Throw_Weapon, 11)
	}
	emit(out, Shot_Hit {
		owner     = claim.owner,
		shot      = claim.shot,
		fired     = claim.fired,
		weapon    = claim.weapon,
		target    = claim.target,
		part      = claim.part,
		offset    = claim.point - target.pose.skeleton[part],
		velocity  = claim.velocity,
		push      = push,
		stopped   = claim.stopped,
		bloodless = friendly,
	})
	// its flight here, which went on through, ends where the claim's did
	if claim.stopped {
		bullet := &world.bullets[record.bullet]
		if bullet.active && bullet.heard && bullet.owner == claim.owner && bullet.shot == claim.shot && bullet.weapon == claim.weapon && bullet.fired == claim.fired {
			bullet_end(world, record.bullet, out, claim.point)
		}
	}
	// and the knife lies where it stuck, unless it already lies where its flight here ended
	if knife && !record.settled {
		record.settled = true
		things_ask(world, Knife_Land{owner = claim.owner, pos = claim.pos})
	}
}

// A client's blast claim, said in `tick`: if it holds, the blast goes off here where it
// says, setting off what is near and throwing the dead and the things, and each soldier
// it reached, made again as its client had it, is wounded and thrown as the blast does
// it there (blast_on); everyone is told.
blast_claim_judge :: proc(world: ^World, resources: ^Resources, authority: ^Authority, claim: Blast_Claim, tick: u32, out: ^Tick_Output) {
	claim := claim
	record := shot_record_find(authority, claim.owner, claim.shot, claim.weapon, claim.fired)
	if record == nil || record.settled || len(record.trace) == 0 do return
	if shot_after_death(world, authority, claim.owner, record.fired) do return // thrown once dead here
	style := resources.weapons[claim.weapon].bullet_style
	if style != .Frag_Grenade && style != .M79 && style != .LAW do return
	age := int(claim.airtime)
	if age > len(record.trace) do return // past where its flight here had got to, or ended

	// where it went off: on its flight; on a body, exactly where the flight was then,
	// and the body met there as its client had it
	last := min(age, len(record.trace) - 1)
	if !on_flight_within(record, last, claim.pos, BLAST_PATH_SLACK) do return
	views := claim.views[:min(int(claim.view_count), BLAST_VIEWS)]
	direct, has_direct := claim.direct.?
	struck := -1
	if has_direct {
		if age >= len(record.trace) || int(direct) >= MAX_PLAYERS do return
		traced := record.trace[age]
		if utils.length(claim.pos - traced.pos) > 0.05 || utils.length(claim.velocity - traced.velocity) > 0.05 do return
		view, seen := blast_view(views, direct)
		if !seen do return
		target, made := view_target(world, resources, authority, claim.owner, view, tick)
		if !made || target.vitals.dead || target.vitals.cease_fire >= 0 || !hit_part(int(claim.part)) do return // spawn protection: it would have gone through
		center := target.pose.skeleton[claim.part] - {2, 0}
		radius := PART_RADIUS + 1.0 if style == .Frag_Grenade else PART_RADIUS
		if _, met := utils.line_circle_collision(claim.pos, claim.pos + claim.velocity, center, radius + CLAIM_BODY_SLACK); !met do return
		struck = int(claim.part)
	}

	// it holds: the blast goes off here, at its flight's place if it still flies or is
	// held, else at one of its own
	id, made := blast_bullet(world, resources, record, claim)
	if !made do return
	explode(world, resources, id, claim.kind, claim.direct, struck, authority, .Claimed, out)

	// and wounds each soldier it reached as its client had it
	traced := record.trace[last]
	for view in views {
		if view.target == claim.owner || int(view.target) >= MAX_PLAYERS || !world.soldiers[view.target].active do continue
		target, seen := view_target(world, resources, authority, claim.owner, view, tick)
		if !seen || target.vitals.dead do continue
		met := struck if has_direct && direct == view.target else -1
		amount, part, push, impact, reached := blast_on(resources, claim.kind, claim.pos, &target.pose.skeleton, target.vitals.cease_fire, met)
		if !reached do continue
		emit(out, Hit{shooter = claim.owner, target = view.target, weapon = claim.weapon, amount = amount, part = 0, pos = target.pose.skeleton[part], push = push, impact = impact, spray = true, seen = clamp(tick, record.fired, world.tick)})
		emit(out, Shot_Hit{owner = claim.owner, shot = claim.shot, fired = claim.fired, weapon = claim.weapon, target = view.target, push = push, blast = true})
		landed_add(authority, claim.owner, view.target, tick, push)
		// a rocket or an M79 grenade on a body wounds it by its own speed besides
		if met >= 0 && style != .Frag_Grenade {
			wound_push := claim.velocity * resources.weapons[claim.weapon].stats.push
			emit(out, Hit{shooter = claim.owner, target = view.target, weapon = claim.weapon, amount = utils.length(claim.velocity) * traced.damage, part = u8(met + 1), pos = target.pose.skeleton[met], push = wound_push, seen = clamp(tick, record.fired, world.tick)})
			landed_add(authority, claim.owner, view.target, tick, wound_push)
		}
	}
}

// The soldier a blast claim names, in its picture.
@(private = "file")
blast_view :: proc(views: []Blast_View, target: Soldier_Id) -> (Blast_View, bool) {
	for view in views {
		if view.target == target do return view, true
	}
	return {}, false
}

// The soldier of `view` made again as `owner`'s client showed it in `tick` (target_as_seen).
@(private = "file")
view_target :: proc(world: ^World, resources: ^Resources, authority: ^Authority, owner: Soldier_Id, view: Blast_View, tick: u32) -> (Soldier, bool) {
	if view.seen < view.taken || view.seen > CLAIM_SEEN_MAX do return {}, false
	if int(view.pre) > SEEN_STEPS_MAX || view.steps < 1 || view.steps > CLAIM_SEEN_MAX + 1 do return {}, false
	if u32(view.seen) > tick do return {}, false
	target, made := target_as_seen(world, resources, authority, owner, view.target, tick - u32(view.seen), tick - u32(view.taken), int(view.pre), int(view.steps))
	return target, made
}

// The bullet a claimed blast goes off as: its flight here, still flying or held, put
// where the claim says; or, that gone, one of its own in a free slot. False with none.
@(private = "file")
blast_bullet :: proc(world: ^World, resources: ^Resources, record: ^Shot_Record, claim: Blast_Claim) -> (id: Bullet_Id, ok: bool) {
	slot := -1
	bullet := &world.bullets[record.bullet]
	if bullet.active && bullet.heard && bullet.owner == claim.owner && bullet.shot == claim.shot && bullet.fired == claim.fired {
		slot = int(record.bullet)
	} else {
		for &b, i in world.bullets {
			if b.active do continue
			b = {
				active = true,
				style  = resources.weapons[claim.weapon].bullet_style,
				weapon = claim.weapon,
				owner  = claim.owner,
				shot   = claim.shot,
				fired  = claim.fired,
				heard  = true,
				record = record.index,
			}
			slot = i
			break
		}
	}
	if slot < 0 do return
	bullet = &world.bullets[slot]
	bullet.pos, bullet.old_pos, bullet.velocity, bullet.held = claim.pos, claim.pos, claim.velocity, 0
	return Bullet_Id(slot), true
}

// A claim landed, its shove on its shooter's picture of the target kept (Landed_Hit).
@(private = "file")
landed_add :: proc(authority: ^Authority, owner, target: Soldier_Id, tick: u32, push: utils.Vec2) {
	records := &authority.shots
	records.landed[records.landed_next] = {owner = owner, target = target, tick = tick, push = push}
	records.landed_next = (records.landed_next + 1) % LANDED_KEPT
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
		if utils.length(point - center) <= PART_RADIUS + CLAIM_POINT_SLACK do return true
	}
	return false
}

// Whether `pos` lies on the shot's flight up to tick `age`: a pierce slows a bullet, which
// then falls a little behind the flight here, which went on through at its speed.
@(private = "file")
on_flight :: proc(record: ^Shot_Record, age: int, pos: utils.Vec2) -> bool {
	return on_flight_within(record, age, pos, CLAIM_PATH_SLACK)
}

// And within `slack` of it.
@(private = "file")
on_flight_within :: proc(record: ^Shot_Record, age: int, pos: utils.Vec2, slack: f32) -> bool {
	for k in 0 ..= age {
		a := record.trace[k].pos
		b := a + record.trace[k].velocity
		if segment_distance(pos, a, b) <= slack do return true
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

// The soldier in `id` as `owner`'s client showed it, having taken it from the snapshot of
// tick `seen` in tick `taken`: stepped `pre` times there on its last keys, as
// soldier_apply steps it, then `steps` times more, once a tick, as the client's own steps
// do, with the shoves that client's own hits on it gave it since (Landed_Hit). (The ticks
// those steps ran in are taken to follow on from `taken`: a view clock nudged in between
// makes a step or two of difference, which the slack absorbs or the claim fails.) Made in
// the world's slot and put back: nothing else in the world is moved, and no dice are
// rolled that the world rolls.
@(private = "file")
target_as_seen :: proc(world: ^World, resources: ^Resources, authority: ^Authority, owner, id: Soldier_Id, seen, taken: u32, pre, steps: int) -> (soldier: Soldier, ok: bool) {
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
	for k in 0 ..< steps {
		at := taken + u32(k)
		step(world, resources, id, at, scratch)
		// a hit there met the target after it stepped, and shoves it at its next step
		for landed in authority.shots.landed {
			if landed.owner == owner && landed.target == id && landed.tick == at do world.soldiers[id].body.next_push += landed.push
		}
	}
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
	if !told.blast && !world.soldiers[told.owner].remote do return
	target := &world.soldiers[told.target]
	part := int(told.part) if hit_part(int(told.part)) else 0
	at := target.pose.skeleton[part] + told.offset
	if target.active && !told.blast do emit(out, Blood{target = told.target, pos = at, velocity = told.velocity, bloodless = told.bloodless})
	if target.active && !target.remote && !target.vitals.dead {
		target.body.next_push += told.push
		// the hit's spray, as a flight here meeting this soldier gave it: the server's word
		// of the wound, if there is one, is taken as the same hit (soldier_hit_spray); a
		// thrown knife's has none
		if told.weapon != .Thrown_Knife do soldier_hit_spray(world, resources, told.target, told.owner, .Flown)
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
