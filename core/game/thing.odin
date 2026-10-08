package game

import "core:math"
import "core:math/linalg"

import res "../resources"
import "../utils"

// A thing: a small Verlet skeleton of 2 or 4 points that lies or is carried. Flags, kits,
// dropped guns and the parachute. The fields tagged
// `served` are the server's word of it on the wire; the rest each machine's own.

Thing :: struct {
	kind:        Thing_Kind `net:"served"`, // .None: the slot is free
	weapon:      res.Weapon `net:"served"`, // a dropped gun's
	ammo:        i32 `net:"served 16"`,
	flip:        bool `net:"served"`, // a dropped gun thrown facing left
	holder:      Maybe(Soldier_Id) `net:"served"`,
	owner:       Maybe(Soldier_Id) `net:"served"`, // who let it go: it passes the polygons that soldier's team does
	timeout:     i32 `net:"served"`,
	resting:     bool `net:"served"`, // no physics until something moves it
	point_count: int `net:"served 4"`, // 2 or 4
	points:      [4]utils.Vec2 `net:"served"`,
	old_points:  [4]utils.Vec2 `net:"served"`,
	forces:      [4]utils.Vec2,
	touches:     [4]u8, // per point, for the landing sounds
	cut:         u8 `net:"served"`, // constraints let go of: a landed parachute's lines
	flipped:     bool,  // a parachute's canopy turned over this tick
	in_base:     bool `net:"served"`, // a flag at home
	interest:    i32 `net:"served 16"`, // how long the bots still go for it
	last_spawn:  Maybe(int) `net:"served"`, // the spawn point a kit last came up at
	background:  Background_State,
}

Thing_Kind :: enum u8 {
	None,
	Alpha_Flag,
	Bravo_Flag,
	Medical_Kit,
	Grenade_Kit,
	Weapon,
	Parachute,
}

// The map's things at the start of a round: the flags and the kits.
things_place :: proc(world: ^World, resources: ^Resources) {
	for &thing in world.things {
		thing_kill(&thing)
	}
	alpha, alpha_spot := thing_spawn_point(world.polymap, .Alpha_Flag, &world.rng)
	bravo, bravo_spot := thing_spawn_point(world.polymap, .Bravo_Flag, &world.rng)
	if alpha_spot do thing_create(world, resources, .Alpha_Flag, alpha)
	if bravo_spot do thing_create(world, resources, .Bravo_Flag, bravo)
	kits_spawn(world, resources, .Medical_Kit, int(world.polymap.medikits))
	if world.rules.max_grenades > 0 do kits_spawn(world, resources, .Grenade_Kit, int(world.polymap.grenade_packs))
}

// A new thing of `kind` at `pos`, in `slot` or else the first free one; none if the pool
// is full. A new flag replaces the old. A gun let go of by `owner` lies the way it faced.
thing_create :: proc(
	world: ^World,
	resources: ^Resources,
	kind: Thing_Kind,
	pos: utils.Vec2,
	weapon := res.Weapon.Punch,
	owner: Maybe(Soldier_Id) = nil,
	slot: Maybe(Thing_Id) = nil,
) -> (
	id: Thing_Id,
	ok: bool,
) {
	if thing_is_flag(kind) {
		for &thing in world.things {
			if thing.kind == kind do thing_kill(&thing)
		}
	}
	id, ok = slot.?
	if !ok {
		for thing, i in world.things {
			if thing.kind == .None {
				id, ok = Thing_Id(i), true
				break
			}
		}
		if !ok do return
	}

	thing := &world.things[id]
	thing_kill(thing)
	thing.kind = kind
	thing.weapon = weapon
	thing.owner = owner
	thing.in_base = thing_is_flag(kind)
	thing.background = {in_transition = true}
	if kind == .Weapon do thing.ammo = resources.weapons[weapon].stats.ammo

	#partial switch kind {
	case .Alpha_Flag, .Bravo_Flag:
		thing.timeout = FLAG_TIMEOUT
		thing.interest = FLAG_INTEREST_TIME
	case .Weapon:
		thing.timeout = GUN_RESIST_TIME
	case .Medical_Kit:
		thing.timeout = world.rules.respawn_time * GUN_RESIST_TIME // never runs out: it is not among those that go
		thing.interest = DEFAULT_INTEREST_TIME
	case .Grenade_Kit:
		thing.timeout = FLAG_TIMEOUT
		thing.interest = DEFAULT_INTEREST_TIME
	case .Parachute:
		thing.timeout = PARACHUTE_TIMEOUT
	}

	skeleton := thing_skeleton(resources, thing)
	thing.point_count = min(len(skeleton.points), 4)
	for k in 0 ..< thing.point_count {
		thing.points[k] = skeleton.points[k]
	}
	// the two flags face each other: alpha's cloth is on the other side of the pole
	if kind == .Alpha_Flag {
		thing.points[2].x = 12.0
		thing.points[3].x = 12.0
	}
	// a knife lies blade first, never quite level
	if kind == .Weapon && weapon == .Knife {
		grip := thing.points[1]
		thing.points[1] = thing.points[0]
		thing.points[0] = grip
		thing.points[0].x += f32(rng_below(&world.rng, 100)) / 100.0
		thing.points[1].x -= f32(rng_below(&world.rng, 100)) / 100.0
	}
	for k in 0 ..< thing.point_count {
		thing.points[k] = thing.points[k] + pos
		thing.old_points[k] = thing.points[k]
	}

	if holder, held := owner.?; held {
		soldier := &world.soldiers[holder]
		// A gun leaving a hand flies off with it: the hand's speed, the grip barely and the
		// muzzle along the aim, less so from the dead. Not the knife: it lands, or is thrown
		// as a bullet.
		if kind == .Weapon && weapon != .Knife {
			joints := soldier_pose(resources.animations, soldier, soldier.body.pos)
			aim := utils.normalize(soldier.controls.aim - joints[14])
			grip: f32 = 0.02 if soldier.vitals.dead else 0.01
			muzzle: f32 = 0.64 if soldier.vitals.dead else 3.0
			thing.points[0] = thing.points[0] + soldier.body.velocity + aim * grip
			thing.points[1] = thing.points[1] + soldier.body.velocity + aim * muzzle
		}
		thing.flip = soldier.body.direction != 1
	}
	return id, true
}

// The slot let go of; which spawn point a kit last came up at is the slot's, and stays.
thing_kill :: proc(thing: ^Thing) {
	last_spawn := thing.last_spawn
	thing^ = {}
	thing.last_spawn = last_spawn
}

// Back to a spawn point of its kind, as new but for its timeout: a flag home, a kit taken
// or fallen off the map. Its holder lets go.
thing_respawn :: proc(world: ^World, resources: ^Resources, id: Thing_Id) {
	thing := &world.things[id]
	if holder, held := thing.holder.?; held do world.soldiers[holder].carrying.held = nil
	kind, weapon := thing.kind, thing.weapon
	thing_kill(thing)

	pos: utils.Vec2
	if kind == .Medical_Kit || kind == .Grenade_Kit {
		pos, _ = thing_spawn_boxes(world.polymap, spawn_kind(kind), thing, &world.rng)
	} else {
		pos, _ = thing_spawn_point(world.polymap, spawn_kind(kind), &world.rng)
	}

	thing_create(world, resources, kind, pos, weapon, slot = id)
	thing.timeout = FLAG_TIMEOUT
	thing.interest = FLAG_INTEREST_TIME if thing_is_flag(kind) else DEFAULT_INTEREST_TIME
}

// A random active spawn point of the kind, a few pixels off (RandomizeStart); of any
// kind if the map has none of this one, and then not `found`. The origin if it has none
// at all.
thing_spawn_point :: proc(polymap: ^res.Poly_Map, kind: res.Spawn_Kind, rng: ^Rng) -> (pos: utils.Vec2, found: bool) {
	found = true
	count := 0
	for spawnpoint in polymap.spawnpoints {
		if spawnpoint.active && spawnpoint.kind == kind do count += 1
	}
	if count == 0 {
		found = false
		for spawnpoint in polymap.spawnpoints {
			if spawnpoint.active do count += 1
		}
	}
	if count == 0 do return

	pick := rng_below(rng, count)
	for spawnpoint in polymap.spawnpoints {
		if !spawnpoint.active || (found && spawnpoint.kind != kind) do continue
		if pick == 0 {
			pos = spawn_jitter(spawnpoint.pos, rng)
			break
		}
		pick -= 1
	}
	return
}

// As thing_spawn_point, but not the spawn point `thing`'s slot last came up at, unless it
// is the only one of the kind (SpawnBoxes). The slot remembers the one it comes up at.
thing_spawn_boxes :: proc(polymap: ^res.Poly_Map, kind: res.Spawn_Kind, thing: ^Thing, rng: ^Rng) -> (pos: utils.Vec2, found: bool) {
	spawns: [res.MAX_SPAWNPOINTS]int
	count := 0
	previous: Maybe(int)
	found = true
	for i in 0 ..< min(len(polymap.spawnpoints), res.MAX_SPAWNPOINTS) {
		if !polymap.spawnpoints[i].active || polymap.spawnpoints[i].kind != kind do continue
		if last, has := thing.last_spawn.?; has && last == i {
			previous = i
		} else {
			spawns[count] = i
			count += 1
		}
	}
	if count == 0 {
		if last, has := previous.?; has {
			spawns[count] = last
			count += 1
		} else {
			found = false
			for i in 0 ..< min(len(polymap.spawnpoints), res.MAX_SPAWNPOINTS) {
				if polymap.spawnpoints[i].active {
					spawns[count] = i
					count += 1
				}
			}
		}
	}
	if count == 0 do return

	i := spawns[rng_below(rng, count)]
	pos = spawn_jitter(polymap.spawnpoints[i].pos, rng)
	thing.last_spawn = i
	return
}

// A few pixels off a spawn point. The C game rolls both in one call's arguments, which
// its build (clang, for Windows) evaluates right to left: y is rolled first.
@(private = "file")
spawn_jitter :: proc(spot: utils.Vec2, rng: ^Rng) -> (pos: utils.Vec2) {
	pos.y = spot.y - 4.0 + f32(rng_below(rng, 4))
	pos.x = spot.x - 4.0 + f32(rng_below(rng, 8))
	return
}

thing_is_flag :: proc(kind: Thing_Kind) -> bool {
	return kind == .Alpha_Flag || kind == .Bravo_Flag
}

thing_is_kit :: proc(kind: Thing_Kind) -> bool {
	return kind == .Medical_Kit || kind == .Grenade_Kit
}

// One tick of a thing: its physics, held or loose; its own kind's tick; who takes it, as
// the referee rules; its timing out, and its falling off the map.
thing_update :: proc(world: ^World, resources: ^Resources, id: Thing_Id, authority: ^Authority, out: ^Tick_Output) {
	thing := &world.things[id]
	was_resting := thing.resting

	if !thing.resting do thing_physics(world, resources, id, out)
	if thing_is_flag(thing.kind) do flag_update(world, resources, id, authority, out)
	if thing.kind != .None do judge_pickup(world, resources, authority, id, out)
	if thing.kind == .None do return // taken, and gone

	if thing.kind == .Parachute do parachute_update(world, resources, id)

	thing.timeout -= 1
	if thing.timeout < -1000 do thing.timeout = -1000
	if thing.timeout == 0 {
		if thing_is_flag(thing.kind) {
			judge_flag_timeout(world, resources, authority, id, out)
		} else if thing.kind == .Weapon || thing.kind == .Parachute {
			thing_kill(thing)
			return
		}
	}

	if thing_out_of_bounds(world.polymap, thing) {
		if thing_is_flag(thing.kind) || thing_is_kit(thing.kind) {
			if authority != nil do rule(world, resources, Thing_Respawn{id}, out) // back at a spawn point of its kind
		} else if thing.kind == .Weapon {
			thing_kill(thing)
			return
		}
		// a parachute off the map is left to its timeout
	}

	if !was_resting && thing.resting {
		for k in 0 ..< 4 do thing.old_points[k] = thing.points[k]
	}
}

// Before the things' turn: their counters on the soldiers, a flag just thrown and a
// medikit just taken.
things_cool_down :: proc(world: ^World) {
	for &soldier in world.soldiers {
		if !soldier.active do continue
		if soldier.carrying.flag_grab_cooldown > 0 do soldier.carrying.flag_grab_cooldown -= 1
		if soldier.carrying.medikit_cooldown > 0 do soldier.carrying.medikit_cooldown -= 1
	}
}

// The skeleton's tick: each point against the map, the Verlet step, rest once settled;
// a carried flag hangs from its carrier's hand.
@(private = "file")
thing_physics :: proc(world: ^World, resources: ^Resources, id: Thing_Id, out: ^Tick_Output) {
	thing := &world.things[id]
	flag := thing_is_flag(thing.kind)
	collided, collided_twice := false, false

	background_test_prepare(&thing.background)
	for k in 0 ..< thing.point_count {
		if thing.holder != nil && k != 1 do continue // carried, only the cloth's tip meets the map
		hit: bool
		if flag && k == 0 {
			// the pole's foot feels around itself, so a flag can stand on a ledge
			p := thing.points[0]
			hit =
				map_collide(world, thing, 0, {p.x - 10, p.y - 8}, out) ||
				map_collide(world, thing, 0, {thing.points[0].x + 10, thing.points[0].y - 8}, out) ||
				map_collide(world, thing, 0, {thing.points[0].x - 10, thing.points[0].y}, out) ||
				map_collide(world, thing, 0, {thing.points[0].x + 10, thing.points[0].y}, out)
			if hit do thing.forces[1].y += FLAG_STAND_FORCE_UP * world.gravity
		} else {
			hit = map_collide(world, thing, k, thing.points[k], out)
		}
		if !hit do continue
		if collided do collided_twice = true
		collided = true
	}
	background_test_reset(&thing.background)

	verlet(world, resources, thing)

	if collided && collided_twice {
		movement := (utils.length(thing.points[0] - thing.old_points[0]) + utils.length(thing.points[1] - thing.old_points[1])) / 2.0
		if movement < MIN_MOVE_DELTA do thing.resting = true
	}

	if holder_id, held := thing.holder.?; flag && held {
		holder := &world.soldiers[holder_id]
		joints := soldier_pose(resources.animations, holder, holder.body.pos)
		thing.points[0] = joints[7] // the hand
		thing.forces[1].y += FLAG_HOLDING_FORCE_UP * world.gravity
		thing.interest = FLAG_INTEREST_TIME
		holder.carrying.held = id
		thing.timeout = FLAG_TIMEOUT
		if !thing.background.in_transition {
			thing.background.in_transition = holder.body.background.in_transition
			thing.background.polygon = holder.body.background.polygon
		}
	}
}

// One point against the map (CheckMapCollision): a flag's pole foot stops dead and its
// other points bounce along the push out; anything else is put back where it was and
// pushed out, so it slides to a stop.
@(private = "file")
map_collide :: proc(world: ^World, thing: ^Thing, k: int, at: utils.Vec2, out: ^Tick_Output) -> (hit: bool) {
	polymap := world.polymap
	pos := utils.Vec2{at.x, at.y - 0.5}
	n := int(polymap.sector_reach)
	sx := utils.round_half_even(pos.x / f32(polymap.sector_size))
	sy := utils.round_half_even(pos.y / f32(polymap.sector_size))
	if !(sx > -n && sx < n && sy > -n && sy < n) do return false

	background_test_big_polygon(polymap, &thing.background, pos)
	flag := thing_is_flag(thing.kind)
	owner: ^Soldier
	if owner_id, owned := thing.owner.?; owned do owner = &world.soldiers[owner_id]

	for index in res.sector_polygons(polymap, sx, sy) {
		polygon := &polymap.polygons[index]
		type := polygon.type
		team := res.object_collides(type, owner.team) if owner != nil else true
		if flag && type > .Lava && type < .Bouncy do team = false // the flags pass every team's polygons
		if !team || type == .Only_Bullets || type == .Only_Player || type == .Doesnt || type == .Only_Flaggers || type == .Not_Flaggers {
			continue
		}
		if !res.point_in_polygon_edges(pos, polygon) do continue
		if background_test(polymap, &thing.background, int(index)) do continue

		normal, distance, _ := res.closest_edge(polygon, pos)
		push := utils.normalize(normal) * distance
		p, o := &thing.points[k], &thing.old_points[k]
		if flag && k == 0 {
			p^ = o^
		} else if flag {
			travel := utils.length(p^ - o^)
			p^ = p^ - push
			o^ = p^ + utils.normalize(push) * travel
			if k == 1 && thing.holder == nil do thing.forces[1].y -= 1
		} else {
			p^ = o^ - push
			// the landing sounds: the first touch, then any hard enough bounce
			limit: u8 = 30 if thing.kind == .Weapon else 3
			heard := thing.touches[k] == 0 || (utils.length(p^ - o^) > 1.5 && thing.touches[k] < limit)
			if heard do emit(out, Thing_Hit{thing = thing.kind, pos = p^, velocity = p^ - o^, part = u8(k)})
		}
		thing.touches[k] += 1
		hit = true
	}
	return
}

// Verlet with the thing's damping and gravity, then one pass of its constraints.
@(private = "file")
verlet :: proc(world: ^World, resources: ^Resources, thing: ^Thing) {
	damping, gravity := thing_physics_of(thing)
	for k in 0 ..< thing.point_count {
		thing.forces[k].y += gravity * world.gravity
		p := thing.points[k]
		thing.points[k] = p * (1.0 + damping) - thing.old_points[k] * damping + thing.forces[k]
		thing.old_points[k] = p
		thing.forces[k] = {}
	}

	skeleton := thing_skeleton(resources, thing)
	for c in 0 ..< len(skeleton.constraints) - int(thing.cut) {
		a, b := skeleton.constraints[c][0], skeleton.constraints[c][1]
		if a >= thing.point_count || b >= thing.point_count do continue
		rest := utils.length(skeleton.points[b] - skeleton.points[a])
		d := thing.points[b] - thing.points[a]
		length := math.sqrt(linalg.dot(d, d))
		diff := (length - rest) / length if length != 0 else 0
		thing.points[a] = thing.points[a] + d * (0.5 * diff)
		thing.points[b] = thing.points[b] - d * (0.5 * diff)
	}
}

// Its damping and the share of the world's gravity it falls by.
@(private = "file")
thing_physics_of :: proc(thing: ^Thing) -> (damping, gravity: f32) {
	#partial switch thing.kind {
	case .Alpha_Flag, .Bravo_Flag: return 0.991, 1.0
	case .Weapon:                  return GUN_BODIES[thing.weapon].damping, GUN_BODIES[thing.weapon].gravity
	case .Medical_Kit:             return 0.989, 1.05
	case .Grenade_Kit:             return 0.989, 1.07
	case .Parachute:               return 0.993, 1.15
	}
	return 0, 0 // none: the slot is free
}

@(private = "file")
thing_out_of_bounds :: proc(polymap: ^res.Poly_Map, thing: ^Thing) -> bool {
	bound := f32(polymap.sector_reach * polymap.sector_size - 10)
	for point in thing.points[:thing.point_count] {
		if abs(point.x) > bound || abs(point.y) > bound do return true
	}
	return false
}

// Whether bullets and blasts knock it about: the flags always, dropped guns and kits as
// the round says, the parachute never.
thing_collides_with_bullets :: proc(world: ^World, thing: ^Thing) -> bool {
	#partial switch thing.kind {
	case .Alpha_Flag, .Bravo_Flag:   return true
	case .Weapon:                    return world.rules.guns_collide
	case .Medical_Kit, .Grenade_Kit: return world.rules.kits_collide
	}
	return false
}

// A bullet's knock on point `point`, along its way.
// The point takes the bullet's velocity over its own, by the weapon's push, and the
// thing is moving again.
thing_knock :: proc(thing: ^Thing, point: int, velocity: utils.Vec2, push: f32) {
	if thing.kind == .None || point >= thing.point_count do return
	thing_velocity := thing.points[point] - thing.old_points[point]
	thing.points[point] = thing.points[point] + (velocity - thing_velocity) * push
	thing.resting = false
}

// Who would take it (CheckSpriteCollision): the nearest living soldier in reach, but not
// one with full health for a medikit, nor full of frag grenades for a grenade kit, nor
// spawn protected for a flag. Reach is measured from the middle of its first two points,
// else from either; where a far soldier left the measure is where the next is measured
// from first, as in the original.
thing_taker :: proc(world: ^World, resources: ^Resources, thing: ^Thing) -> (taker: Soldier_Id, found: bool) {
	radius := thing_radius(thing)
	pos := (thing.points[0] + thing.points[1]) * 0.5
	closest := f32(9999999)
	for &soldier, j in world.soldiers {
		if !soldier.active || soldier.vitals.dead || soldier.team == .Spectator do continue
		if utils.length(pos - soldier.body.pos) >= radius {
			pos = thing.points[0]
			if utils.length(pos - soldier.body.pos) >= radius do pos = thing.points[1]
		}
		distance := utils.length(pos - soldier.body.pos)
		if distance >= radius || distance >= closest do continue
		if thing.kind == .Medical_Kit || thing.kind == .Grenade_Kit { // as this turn's kits leave it
			given := kit_receiver(world, Soldier_Id(j))
			if thing.kind == .Medical_Kit && given.vitals.health == DEFAULT_HEALTH do continue
			if thing.kind == .Grenade_Kit && given.arsenal.grenades == world.rules.max_grenades do continue
		}
		if thing_is_flag(thing.kind) && soldier.vitals.cease_fire > 0 do continue
		closest = distance
		taker, found = Soldier_Id(j), true
	}
	return
}

// ---------------------------------------------------------------------------------
// What each kind is made of

// How long things last, in ticks.
FLAG_TIMEOUT :: 60 * 25 // a loose flag lies this long before it goes home
GUN_RESIST_TIME :: 60 * 20 // a dropped gun lies this long, and resists pickup at first
PARACHUTE_TIMEOUT :: 3600

MIN_MOVE_DELTA :: f32(0.63) // a thing on the ground moving less than this on average comes to rest
FLAG_STAND_FORCE_UP :: f32(-16) // a fallen flag's pole stands up again, by this much gravity
FLAG_HOLDING_FORCE_UP :: f32(-14) // a carried flag's cloth flies, by this much

// How near a soldier must be to take it; the parachute is not taken.
thing_radius :: proc(thing: ^Thing) -> f32 {
	#partial switch thing.kind {
	case .Alpha_Flag, .Bravo_Flag: return 19
	case .Parachute:               return 0
	case .Weapon:                  return 15 if thing.weapon == .Knife else 10
	}
	return 12 // the kits
}

// How long the bots go for a thing, in ticks.
FLAG_INTEREST_TIME :: 60 * 25
DEFAULT_INTEREST_TIME :: 60 * 5 + 50

// A dropped gun's body: the length of karabin.po it is, and how it falls.
Gun_Body :: struct {
	scale:   f32,
	damping: f32,
	gravity: f32,
}

@(rodata)
GUN_BODIES := #partial [res.Weapon]Gun_Body {
	.USSOCOM       = {1.0, 0.994, 1.05},
	.Desert_Eagles = {1.1, 0.996, 1.09},
	.MP5           = {2.2, 0.995, 1.11},
	.AK74          = {3.7, 0.994, 1.16},
	.Steyr_AUG     = {3.7, 0.994, 1.16},
	.Spas12        = {3.6, 0.993, 1.15},
	.Ruger77       = {3.6, 0.993, 1.13},
	.M79           = {2.8, 0.994, 1.15},
	.Barrett       = {4.3, 0.993, 1.18},
	.Minimi        = {3.9, 0.993, 1.2},
	.Minigun       = {5.5, 0.991, 1.4},
	.Knife         = {1.8, 0.994, 1.15},
	.Chainsaw      = {2.8, 0.994, 1.15},
	.LAW           = {2.8, 0.994, 1.15},
}

thing_skeleton :: proc(resources: ^Resources, thing: ^Thing) -> ^res.Skeleton {
	#partial switch thing.kind {
	case .Alpha_Flag, .Bravo_Flag:
		return &resources.skeletons.flag
	case .Parachute:
		return &resources.skeletons.parachute
	case .Weapon:
		for scale, i in res.RIFLE_SCALES {
			if scale == GUN_BODIES[thing.weapon].scale do return &resources.skeletons.rifles[i]
		}
		return &resources.skeletons.rifles[0]
	}
	return &resources.skeletons.kit
}

// The spawn points a thing of the kind comes up at; the general ones for one that has none.
spawn_kind :: proc(kind: Thing_Kind) -> res.Spawn_Kind {
	#partial switch kind {
	case .Alpha_Flag:  return .Alpha_Flag
	case .Bravo_Flag:  return .Bravo_Flag
	case .Medical_Kit: return .Medical_Kit
	case .Grenade_Kit: return .Grenade_Kit
	}
	return .General
}
