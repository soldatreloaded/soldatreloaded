package opensoldat

// The port against OpenSoldat, the original: each scenario played by OpenSoldat's own
// simulation (the reference, built by build.sh) and by the port, side by side, on the
// same commands. After every tick both are probed into the same flat struct, and the
// scenario reports where they first part:
//
//   - the first field to differ at all, bit for bit, and
//   - the first to differ by more than a rounding would (TOLERANCE): where the two play
//     differently, rather than round differently.
//
// tests/compare holds the port to the C game it was ported from, exactly; this holds it
// to the original that game was ported from, which it is not bound to match: what
// differs here may be the C game's own choice. It reads soldiers and bullets: moving
// and fighting, not the things or the round. The dice can't agree (OpenSoldat rolls
// Free Pascal's, the port its own), so both play with no spread, and the rest of what
// is random is left out of the probe or out of the scenarios.
//
//   tests/opensoldat/build.sh
//   odin run tests/opensoldat
//   odin run tests/opensoldat -- jump      just the scenarios whose names contain this
//   odin run tests/opensoldat -- jump 120 130
//                                          and both games' soldiers and bullets, where
//                                          they differ, on those ticks

import "base:runtime"
import sa "core:container/small_array"
import "core:dynlib"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

import "../../core/game"
import res "../../core/resources"

// The reference, from where the comparison runs (assets/).
REFERENCE :: "../tests/opensoldat/build/reference.dll"

// How far two floats may be apart and still be the same play: as far as a different
// rounding takes a value in a few ticks, relative to its size.
TOLERANCE :: 1e-3

// The ticks to show both games' soldiers and bullets on, where they differ.
Trace :: struct {
	from, to: int,
}

main :: proc() {
	filter := os.args[1] if len(os.args) > 1 else ""
	trace := Trace{-1, -1}
	if len(os.args) > 3 {
		trace.from, _ = strconv.parse_int(os.args[2])
		trace.to, _ = strconv.parse_int(os.args[3])
	}
	if os.change_directory("assets") != nil { // both games read data/ from the install's root
		fmt.eprintln("run from the repository's root, where assets/ is")
		os.exit(2)
	}
	agreed, parted := 0, 0
	for &scenario in SCENARIOS {
		if !strings.contains(scenario.name, filter) do continue
		if play(&scenario, trace) {
			agreed += 1
		} else {
			parted += 1
		}
		free_all(context.temp_allocator)
	}
	fmt.printfln("\n%d played alike throughout, %d parted", agreed, parted)
}

// Plays a scenario in both games; whether they agreed, bit for bit, every tick.
play :: proc(scenario: ^Scenario, trace: Trace) -> bool {
	reference, loaded := reference_load()
	if !loaded do os.exit(2)
	defer dynlib.unload_library(reference.library)

	port := new(game.Game)
	defer {
		game.game_destroy(port)
		free(port)
	}
	setup: Setup
	if !port_scene(port, scenario, &setup) {
		fmt.printfln("FAIL %s: the port cannot load %s", scenario.name, scenario.map_name)
		return false
	}
	data := strings.clone_to_cstring(game.DATA_DIR, context.temp_allocator)
	map_name := strings.clone_to_cstring(scenario.map_name, context.temp_allocator)
	if reference.scene(data, map_name, 1, &setup) == 0 {
		fmt.printfln("FAIL %s: OpenSoldat cannot load %s", scenario.name, scenario.map_name)
		return false
	}

	os_probe, port_probe := new(Probe), new(Probe)
	defer {
		free(os_probe)
		free(port_probe)
	}
	exact, behaviour: Parting
	for tick in 0 ..= scenario.ticks {
		reference.probe(os_probe)
		probe_world(port, port_probe)
		if tick >= trace.from && tick <= trace.to do show(tick, os_probe, port_probe)
		// tick 0 is each game's own setting up (OpenSoldat leaves a new sprite's
		// direction for its first update to work out, for one): compared from the first
		// tick played
		if tick > 0 && !behaviour.found {
			if field, differs := first_difference(os_probe, port_probe, 0); differs && !exact.found do exact = {true, tick, field}
			if field, differs := first_difference(os_probe, port_probe, TOLERANCE); differs do behaviour = {true, tick, field}
		}
		if tick == scenario.ticks || (behaviour.found && tick >= trace.to) do break

		buttons := scenario.press(tick)
		commands: [game.MAX_PLAYERS]game.Command
		for i in 0 ..< 2 do commands[i] = command(os_probe, i, buttons[i])
		reference.tick(&commands)
		game.game_tick(port, &commands)
	}

	switch {
	case !exact.found:
		fmt.printfln("SAME %s (%d ticks)", scenario.name, scenario.ticks)
		return true
	case !behaviour.found:
		fmt.printfln("NEAR %s (%d ticks): rounding only, from tick %d: %s", scenario.name, scenario.ticks, exact.tick, exact.field)
	case:
		fmt.printfln("DIFF %s at tick %d: %s", scenario.name, behaviour.tick, behaviour.field)
		if exact.tick < behaviour.tick do fmt.printfln("     rounding apart from tick %d: %s", exact.tick, exact.field)
	}
	return false
}

// Both games' soldiers and bullets on `tick`, those that differ, one line for each game.
show :: proc(tick: int, reference, port: ^Probe) {
	fmt.printfln("tick %d", tick)
	for i in 0 ..< len(reference.soldiers) {
		if reference.soldiers[i] == port.soldiers[i] do continue
		fmt.printfln("  soldier %d  OpenSoldat %v", i, reference.soldiers[i])
		fmt.printfln("  soldier %d  port       %v", i, port.soldiers[i])
	}
	for i in 0 ..< PROBE_BULLETS {
		if reference.bullets[i] == port.bullets[i] do continue
		fmt.printfln("  bullet %d   OpenSoldat %v", i, reference.bullets[i])
		fmt.printfln("  bullet %d   port       %v", i, port.bullets[i])
	}
}

// Where two probes first part: the tick, and the field with both values.
Parting :: struct {
	found: bool,
	tick:  int,
	field: string,
}

// As the C comparison aims: each soldier at the other's chest, in whole units, as
// OpenSoldat keeps its aim. Aimed from OpenSoldat's world, so both get the same.
command :: proc(probe: ^Probe, from: int, buttons: game.Buttons) -> game.Command {
	target := probe.soldiers[1 - from].pos
	aim := [2]f32{math.round(target[0]), math.round(target[1] - 8)}
	return {sequence = u32(probe.tick + 1), buttons = buttons, aim = aim}
}

// The port's scene: soldier 0 on an alpha spawn point, as the C comparison picks it,
// and soldier 1 the scenario's gap to its right; no spread; and field they stand, for
// OpenSoldat to place its own.
port_scene :: proc(port: ^game.Game, scenario: ^Scenario, setup: ^Setup) -> bool {
	settings := game.DEFAULT_GAME_SETTINGS
	for &stats in settings.weapons {
		stats.bullet_spread = 0
		stats.movement_accuracy = 0
	}
	if !game.game_init(port, settings, authority = true) || !game.game_start_round(port, scenario.map_name, seed = 1) {
		return false
	}

	rng := game.Rng{7}
	spawn := game.spawn_point(&port.polymap, .Alpha, &rng)
	teams := [2]res.Team{.Alpha, .Bravo}
	for i in 0 ..< 2 {
		setup.at[i] = {spawn.x + f32(i) * scenario.gap, spawn.y}
		setup.weapons[i] = i32(scenario.weapons[i])
		game.apply_ruling(&port.world, &port.resources, game.Respawn {
			target    = game.Soldier_Id(i),
			team      = teams[i],
			primary   = scenario.weapons[i],
			secondary = .USSOCOM,
			pos       = setup.at[i],
		})
	}
	sa.clear(&port.world.things_asked) // no parachute: OpenSoldat's is taken away too
	return true
}

// ---------------------------------------------------------------------------------
// The probe: what is compared, the same for both games. Mirrors TProbe in
// reference/probe.inc.

PROBE_BULLETS :: 254 // OpenSoldat's MAX_BULLETS: the port's first that many

Probe :: struct {
	tick:     i32,
	soldiers: [2]Probe_Soldier,
	bullets:  [PROBE_BULLETS]Probe_Bullet,
}

Probe_Soldier :: struct {
	active:         i32,
	dead:           i32,
	health:         f32,
	pos:            [2]f32,
	old_pos:        [2]f32,
	vel:            [2]f32,
	forces:         [2]f32,
	direction:      i32,
	stance:         i32,
	on_ground:      i32,
	jets:           i32,
	legs_anim:      i32,
	legs_frame:     i32,
	legs_count:     i32,
	body_anim:      i32,
	body_frame:     i32,
	body_count:     i32,
	weapon:         i32,
	ammo:           i32,
	fire_count:     i32,
	reload_count:   i32,
	startup_count:  i32,
	secondary:      i32,
	secondary_ammo: i32,
	grenades:       i32,
	cease_fire:     i32,
}

Probe_Bullet :: struct {
	active:  i32,
	style:   i32,
	weapon:  i32,
	owner:   i32,
	pos:     [2]f32,
	vel:     [2]f32,
	damage:  f32,
	timeout: i32,
}

// What else a scene needs, the same in both: mirrors TSetup in reference/probe.inc.
Setup :: struct {
	at:      [2][2]f32, // field each soldier stands
	weapons: [2]i32,    // each one's primary, the port's number
}

// The port's world into the probe.
probe_world :: proc(port: ^game.Game, p: ^Probe) {
	p^ = {}
	world := &port.world
	p.tick = i32(world.tick)
	for i in 0 ..< 2 {
		s := &world.soldiers[i]
		if !s.active do continue
		p.soldiers[i] = {
			active         = 1,
			dead           = i32(s.vitals.dead),
			health         = s.vitals.health,
			pos            = s.body.pos,
			old_pos        = s.body.old_pos,
			vel            = s.body.velocity,
			forces         = s.body.forces,
			direction      = i32(s.body.direction),
			stance         = i32(s.controls.stance),
			on_ground      = i32(s.body.on_ground),
			jets           = s.body.jet_fuel,
			legs_anim      = i32(s.pose.legs.id),
			legs_frame     = s.pose.legs.frame,
			legs_count     = s.pose.legs.count,
			body_anim      = i32(s.pose.body.id),
			body_frame     = s.pose.body.frame,
			body_count     = s.pose.body.count,
			weapon         = i32(s.arsenal.primary.weapon),
			ammo           = s.arsenal.primary.ammo,
			fire_count     = s.arsenal.primary.fire_count,
			reload_count   = s.arsenal.primary.reload_count,
			startup_count  = s.arsenal.primary.startup_count,
			secondary      = i32(s.arsenal.secondary.weapon),
			secondary_ammo = s.arsenal.secondary.ammo,
			grenades       = s.arsenal.grenades,
			cease_fire     = s.vitals.cease_fire,
		}
	}
	for i in 0 ..< PROBE_BULLETS {
		bullet := &world.bullets[i]
		if !bullet.active do continue
		p.bullets[i] = {
			active  = 1,
			style   = i32(bullet.style),
			weapon  = i32(bullet.weapon),
			owner   = i32(bullet.owner) + 1, // OpenSoldat numbers its sprites from 1
			pos     = bullet.pos,
			vel     = bullet.velocity,
			damage  = bullet.damage,
			timeout = bullet.timeout,
		}
	}
}

// ---------------------------------------------------------------------------------
// Comparing

// The first field the two probes differ in, with both values. With no `tolerance`, bit
// for bit; with one, floats differ when they are further apart than that, relative to
// their size, and everything else when it differs at all.
first_difference :: proc(reference, port: ^Probe, tolerance: f32) -> (difference: string, differs: bool) {
	return compare_value(reference, port, typeid_of(Probe), "", tolerance)
}

@(private = "file")
compare_value :: proc(a, b: rawptr, id: typeid, path: string, tolerance: f32) -> (difference: string, differs: bool) {
	info := runtime.type_info_base(type_info_of(id))
	#partial switch kind in info.variant {
	case runtime.Type_Info_Struct:
		for i in 0 ..< int(kind.field_count) {
			offset := kind.offsets[i]
			field_path := kind.names[i] if path == "" else fmt.tprintf("%s.%s", path, kind.names[i])
			difference, differs = compare_value(rawptr(uintptr(a) + offset), rawptr(uintptr(b) + offset), kind.types[i].id, field_path, tolerance)
			if differs do return
		}
		return "", false
	case runtime.Type_Info_Array:
		for i in 0 ..< kind.count {
			offset := uintptr(i * kind.elem_size)
			difference, differs = compare_value(rawptr(uintptr(a) + offset), rawptr(uintptr(b) + offset), kind.elem.id, fmt.tprintf("%s[%d]", path, i), tolerance)
			if differs do return
		}
		return "", false
	case runtime.Type_Info_Float:
		if tolerance > 0 {
			x, y := (^f32)(a)^, (^f32)(b)^
			if abs(x - y) <= tolerance * max(1, abs(x), abs(y)) do return "", false
		}
	}
	if runtime.memory_compare(a, b, info.size) == 0 {
		return "", false
	}
	return fmt.tprintf("%s is %v in OpenSoldat, %v in the port", path, any{a, id}, any{b, id}), true
}

// ---------------------------------------------------------------------------------
// OpenSoldat, from build/reference.dll

Reference :: struct {
	library:    dynlib.Library,
	scene:      proc "c" (data, map_name: cstring, seed: u32, setup: ^Setup) -> i32,
	tick:       proc "c" (commands: ^[game.MAX_PLAYERS]game.Command),
	probe:      proc "c" (probe: ^Probe),
	probe_size: proc "c" () -> i32,
}

// The reference loaded afresh: OpenSoldat keeps its world in globals, so each scenario
// has the library to itself.
reference_load :: proc() -> (reference: Reference, ok: bool) {
	library, loaded := dynlib.load_library(REFERENCE)
	if !loaded {
		fmt.eprintfln("cannot load %s: build it with tests/opensoldat/build.sh", REFERENCE)
		return
	}
	reference.library = library
	reference.scene = auto_cast dynlib.symbol_address(library, "os_scene")
	reference.tick = auto_cast dynlib.symbol_address(library, "os_tick")
	reference.probe = auto_cast dynlib.symbol_address(library, "os_probe")
	reference.probe_size = auto_cast dynlib.symbol_address(library, "os_probe_size")
	if reference.scene == nil || reference.tick == nil || reference.probe == nil || reference.probe_size == nil {
		fmt.eprintfln("%s lacks what the comparison calls: rebuild it", REFERENCE)
		return
	}
	if reference.probe_size() != size_of(Probe) {
		fmt.eprintfln("the probe is %d bytes in OpenSoldat and %d in Odin: rebuild, or fix the mirror", reference.probe_size(), size_of(Probe))
		return
	}
	return reference, true
}

#assert(size_of(game.Command) == 16) // as TCommand in reference/probe.inc
