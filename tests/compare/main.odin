package compare

// The comparison: each scenario played by the C game (the reference, built by build.sh)
// and by the Odin port, side by side, on the same commands. After every tick both worlds
// are probed into the same flat struct and compared field by field, bit for bit; the
// first difference is reported by name. A scenario passes when every tick matches.
//
//   tests/compare/build.sh
//   odin run tests/compare
//   odin run tests/compare -- run_right      just the scenarios whose names contain this

import "base:runtime"
import sa "core:container/small_array"
import "core:fmt"
import "core:os"
import "core:strings"

import "../../core/game"
import res "../../core/resources"

// The C game plays by its own data at the pinned commit, which build.sh exports: it has
// what the port left out, such as the bow's animation. The port plays by the repository's
// (game.DATA_DIR). Both are relative to assets/, where the comparison runs.
C_DATA :: "../tests/compare/build/source/assets/data"

main :: proc() {
	filter := os.args[1] if len(os.args) > 1 else ""
	if os.change_directory("assets") != nil { // the game reads data/ from its install's root
		fmt.eprintln("run from the repository's root, where assets/ is")
		os.exit(2)
	}
	if ref_probe_size() != size_of(Probe) {
		fmt.eprintfln("the probe is %d bytes in C and %d in Odin: rebuild with build.sh, or fix the mirror", ref_probe_size(), size_of(Probe))
		os.exit(2)
	}
	passed, failed := 0, 0
	for &scenario in SCENARIOS {
		if !strings.contains(scenario.name, filter) {
			continue
		}
		if play(&scenario) {
			passed += 1
		} else {
			failed += 1
		}
		free_all(context.temp_allocator)
	}
	fmt.printfln("\n%d passed, %d failed", passed, failed)
	os.exit(0 if failed == 0 else 1)
}

// Plays a scenario in both games; whether every tick matched.
play :: proc(scenario: ^Scenario) -> bool {
	map_name := strings.clone_to_cstring(scenario.map_name, context.temp_allocator)
	spawn: [2]f32
	reference := ref_scene(C_DATA, map_name, scenario.gap, i32(scenario.weapons[0]), i32(scenario.weapons[1]), i32(scenario.collide), &scenario.setup, &spawn)
	if reference == nil {
		fmt.printfln("FAIL %s: the C game cannot load %s", scenario.name, scenario.map_name)
		return false
	}
	defer ref_free(reference)

	port := new(game.Game)
	defer {
		game.game_destroy(port)
		free(port)
	}
	if !odin_scene(port, scenario, spawn) {
		fmt.printfln("FAIL %s: the port cannot load %s", scenario.name, scenario.map_name)
		return false
	}

	c_probe, odin_probe := new(Probe), new(Probe)
	defer {
		free(c_probe)
		free(odin_probe)
	}

	for tick in 0 ..= scenario.ticks {
		ref_probe(reference, c_probe)
		probe_world(port, odin_probe)
		if difference, differs := first_difference(c_probe, odin_probe); differs {
			fmt.printfln("FAIL %s at tick %d: %s", scenario.name, tick, difference)
			return false
		}
		if tick == scenario.ticks {
			break
		}

		buttons := scenario.press(tick)
		commands: [game.MAX_PLAYERS]game.Command
		for i in 0 ..< 2 {
			commands[i] = command(c_probe, i, buttons[i])
		}
		ref_tick(reference, &commands)
		game.game_tick(port, &commands)
	}
	fmt.printfln("PASS %s (%d ticks)", scenario.name, scenario.ticks)
	return true
}

// As the C tests aim: each soldier at the other's chest.
command :: proc(probe: ^Probe, from: int, buttons: game.Buttons) -> game.Command {
	target := probe.soldiers[1 - from].pos
	return {sequence = u32(probe.tick + 1), buttons = buttons, aim = {target[0], target[1] - 8}}
}

// The port's scene, as ref_scene makes the C game's.
odin_scene :: proc(port: ^game.Game, scenario: ^Scenario, spawn: [2]f32) -> bool {
	settings := game.DEFAULT_GAME_SETTINGS
	settings.guns_collide = scenario.collide
	settings.kits_collide = scenario.collide
	setup := &scenario.setup
	if !game.game_init(port, settings, authority = true) || !game.game_start_round(port, scenario.map_name, seed = 1) {
		return false
	}

	teams := [2]res.Team{.Alpha, .Bravo}
	for i in 0 ..< 2 {
		game.apply_ruling(&port.world, &port.resources, game.Respawn {
			target    = game.Soldier_Id(i),
			team      = teams[i],
			primary   = scenario.weapons[i],
			secondary = .USSOCOM,
			pos       = setup.at[i] if setup.placed else [2]f32{spawn.x + f32(i) * scenario.gap, spawn.y},
		})
	}
	sa.clear(&port.world.things_asked) // the C scene places them telling the things nothing: no parachute
	for i in 0 ..< 2 {
		if setup.health[i] > 0 do port.world.soldiers[i].vitals.health = setup.health[i]
	}
	for gun, i in setup.guns {
		if gun != .Punch do game.thing_create(&port.world, &port.resources, .Weapon, setup.guns_at[i], gun)
	}
	for &thing in port.world.things {
		if setup.flag == .None || thing.kind != setup.flag do continue
		move := setup.flag_at - thing.points[0]
		for k in 0 ..< thing.point_count {
			thing.points[k] = thing.points[k] + move
			thing.old_points[k] = thing.old_points[k] + move
		}
	}
	return true
}

// ---------------------------------------------------------------------------------
// The probe: what is compared, the same for both games. Mirrors Probe in reference.c.

Probe :: struct {
	rng:         u64,
	tick:        i32,
	frozen:      i32,
	time_left:   i32,
	ended:       i32,
	alpha_score: i32,
	bravo_score: i32,
	soldiers:    [game.MAX_PLAYERS]Probe_Soldier,
	bullets:     [game.MAX_BULLETS]Probe_Bullet,
	things:      [game.MAX_THINGS]Probe_Thing,
	corpses:     [game.MAX_PLAYERS]Probe_Corpse,
}

Probe_Soldier :: struct {
	rng:                u64,
	active:             i32,
	team:               i32,
	dead:               i32,
	life:               i32,
	health:             f32,
	pos:                [2]f32,
	old_pos:            [2]f32,
	vel:                [2]f32,
	forces:             [2]f32,
	next_push:          [2]f32,
	direction:          i32,
	stance:             i32,
	on_ground:          i32,
	jets:               i32,
	aim:                [2]f32,
	aim_dist:           f32,
	legs_anim:          i32,
	legs_frame:         i32,
	legs_count:         i32,
	body_anim:          i32,
	body_frame:         i32,
	body_count:         i32,
	weapon:             i32,
	ammo:               i32,
	fire_count:         i32,
	reload_count:       i32,
	startup_count:      i32,
	secondary:          i32,
	secondary_ammo:     i32,
	grenades:           i32,
	cease_fire:         i32,
	respawn_counter:    i32,
	held:               i32,
	hit_spray:          i32,
	kills:              i32,
	deaths:             i32,
	flags:              i32,
	idle_time:          i32,
	idle_antic:         i32,
	death_pos:          [2]f32,
	death_vel:          [2]f32,
	death_part:         i32,
	death_fire:         i32,
	shot_count:         i32,
	medikit_cooldown:   i32,
	flag_grab_cooldown: i32,
}

Probe_Bullet :: struct {
	active:         i32,
	style:          i32,
	weapon:         i32,
	owner:          i32,
	pos:            [2]f32,
	vel:            [2]f32,
	damage:         f32,
	timeout:        i32,
	old_pos:        [2]f32,
	initial:        [2]f32,
	hit_spot:       [2]f32,
	hit_body:       i32,
	ricochet_count: i32,
	degrade_count:  i32,
}

Probe_Thing :: struct {
	kind:       i32,
	holder:     i32,
	timeout:    i32,
	resting:    i32,
	points:     [4][2]f32,
	weapon:     i32,
	ammo:       i32,
	owner:      i32,
	flip:       i32,
	old_points: [4][2]f32,
	in_base:    i32,
	interest:   i32,
	last_spawn: i32,
}

Probe_Corpse :: struct {
	active:     i32,
	points:     [game.CORPSE_POINTS][2]f32,
	old_points: [game.CORPSE_POINTS][2]f32,
	torn:       i32,
	hits:       i32,
	dead_time:  i32,
	on_ground:  i32,
}

// The port's world into the probe.
probe_world :: proc(port: ^game.Game, p: ^Probe) {
	p^ = {}
	world := &port.world
	p.rng = world.rng.state
	p.tick = i32(world.tick)
	p.frozen = i32(world.rules.frozen)
	p.time_left = port.round.time_left
	_, ended := port.round.phase.(game.Ended)
	p.ended = i32(ended)
	p.alpha_score = port.round.captures[.Alpha]
	p.bravo_score = port.round.captures[.Bravo]

	for &soldier, i in world.soldiers {
		if soldier.active do probe_soldier(&soldier, &p.soldiers[i])
	}
	for &bullet, i in world.bullets {
		if !bullet.active do continue
		p.bullets[i] = {
			active         = 1,
			style          = i32(bullet.style),
			weapon         = i32(bullet.weapon),
			owner          = i32(bullet.owner),
			pos            = bullet.pos,
			vel            = bullet.velocity,
			damage         = bullet.damage,
			timeout        = bullet.timeout,
			old_pos        = bullet.old_pos,
			initial        = bullet.fired_from,
			hit_spot       = bullet.last_ricochet,
			hit_body       = id_plus_one(bullet.last_hit),
			ricochet_count = bullet.ricochet_count,
			degrade_count  = bullet.degrade_count,
		}
	}
	for &thing, i in world.things {
		if thing.kind == .None do continue
		p.things[i] = {
			kind    = i32(thing.kind),
			holder  = id_plus_one(thing.holder),
			timeout = thing.timeout,
			resting = i32(thing.resting),
			weapon  = i32(thing.weapon),
			ammo    = thing.ammo,
			owner   = id_plus_one(thing.owner),
			flip       = i32(thing.flip),
			in_base    = i32(thing.in_base),
			interest   = thing.interest,
			last_spawn = id_plus_one(thing.last_spawn),
		}
		for k in 0 ..< thing.point_count {
			p.things[i].points[k] = thing.points[k]
			p.things[i].old_points[k] = thing.old_points[k]
		}
	}
	for &corpse, i in world.corpses {
		if !corpse.active do continue
		p.corpses[i] = {
			active     = 1,
			points     = corpse.points,
			old_points = corpse.old_points,
			torn       = i32(transmute(u32)corpse.torn),
			hits       = i32(corpse.landings),
			dead_time  = corpse.dead_time,
			on_ground  = i32(corpse.on_ground),
		}
	}
}

probe_soldier :: proc(s: ^game.Soldier, p: ^Probe_Soldier) {
	p^ = {
		rng                = s.rng.state,
		active             = 1,
		team               = i32(s.team),
		dead               = i32(s.vitals.dead),
		life               = i32(s.vitals.life),
		health             = s.vitals.health,
		pos                = s.body.pos,
		old_pos            = s.body.old_pos,
		vel                = s.body.velocity,
		forces             = s.body.forces,
		next_push          = s.body.next_push,
		direction          = i32(s.body.direction),
		stance             = i32(s.controls.stance),
		on_ground          = i32(s.body.on_ground),
		jets               = s.body.jet_fuel,
		aim                = s.controls.aim,
		aim_dist           = s.aim.distance,
		legs_anim          = i32(s.pose.legs.id),
		legs_frame         = s.pose.legs.frame,
		legs_count         = s.pose.legs.count,
		body_anim          = i32(s.pose.body.id),
		body_frame         = s.pose.body.frame,
		body_count         = s.pose.body.count,
		weapon             = i32(s.arsenal.primary.weapon),
		ammo               = s.arsenal.primary.ammo,
		fire_count         = s.arsenal.primary.fire_count,
		reload_count       = s.arsenal.primary.reload_count,
		startup_count      = s.arsenal.primary.startup_count,
		secondary          = i32(s.arsenal.secondary.weapon),
		secondary_ammo     = s.arsenal.secondary.ammo,
		grenades           = s.arsenal.grenades,
		cease_fire         = s.vitals.cease_fire,
		respawn_counter    = s.vitals.respawn_counter,
		held               = id_plus_one(s.carrying.held),
		hit_spray          = i32(s.aim.hit_spray),
		kills              = s.tally.kills,
		deaths             = s.tally.deaths,
		flags              = s.tally.flags,
		idle_time          = s.antics.idle_time,
		idle_antic         = i32(s.antics.idle_antic),
		death_pos          = s.vitals.death.pos,
		death_vel          = s.vitals.death.velocity,
		death_part         = i32(s.vitals.death.part),
		death_fire         = i32(s.vitals.death.fire),
		shot_count         = i32(s.arsenal.shot_count),
		medikit_cooldown   = s.carrying.medikit_cooldown,
		flag_grab_cooldown = s.carrying.flag_grab_cooldown,
	}
}

// The C game's way of naming one: its index + 1, 0 for none.
id_plus_one :: proc(id: Maybe($T)) -> i32 {
	value, has := id.?
	return i32(value) + 1 if has else 0
}

// ---------------------------------------------------------------------------------
// Comparing

// The first field the two probes differ in, with both values; bit for bit, so a float
// that differs in its last place differs.
first_difference :: proc(c, odin: ^Probe) -> (difference: string, differs: bool) {
	return compare_value(c, odin, typeid_of(Probe), "")
}

@(private = "file")
compare_value :: proc(c, odin: rawptr, id: typeid, path: string) -> (difference: string, differs: bool) {
	info := runtime.type_info_base(type_info_of(id))
	#partial switch kind in info.variant {
	case runtime.Type_Info_Struct:
		for i in 0 ..< int(kind.field_count) {
			offset := kind.offsets[i]
			field_path := kind.names[i] if path == "" else fmt.tprintf("%s.%s", path, kind.names[i])
			difference, differs = compare_value(rawptr(uintptr(c) + offset), rawptr(uintptr(odin) + offset), kind.types[i].id, field_path)
			if differs do return
		}
		return "", false
	case runtime.Type_Info_Array:
		for i in 0 ..< kind.count {
			offset := uintptr(i * kind.elem_size)
			difference, differs = compare_value(rawptr(uintptr(c) + offset), rawptr(uintptr(odin) + offset), kind.elem.id, fmt.tprintf("%s[%d]", path, i))
			if differs do return
		}
		return "", false
	}
	if runtime.memory_compare(c, odin, info.size) == 0 {
		return "", false
	}
	return fmt.tprintf("%s is %v in C, %v in Odin", path, any{c, id}, any{odin, id}), true
}

// ---------------------------------------------------------------------------------
// The C game, from build/reference.lib

foreign import reference "build/reference.lib"

C_Game :: distinct rawptr

@(default_calling_convention = "c")
foreign reference {
	ref_scene :: proc(data: cstring, map_name: cstring, gap: f32, a_weapon, b_weapon, collide: i32, setup: ^Setup, spawn: ^[2]f32) -> C_Game ---
	ref_free :: proc(g: C_Game) ---
	ref_tick :: proc(g: C_Game, commands: ^[game.MAX_PLAYERS]game.Command) ---
	ref_probe :: proc(g: C_Game, probe: ^Probe) ---
	ref_probe_size :: proc() -> i32 ---
}

#assert(size_of(game.Command) == 16) // as the C game's Command: seq, buttons, aim

