package resources

import "core:strconv"

import "../utils"

// The particle-and-constraint objects in data/objects (.po files) that the game's
// Verlet bodies are built from: the gostek, the flag, the medikit and grenade kits, the
// parachute and the rifles dropped on the ground. Ported from Anims.pas.

// The scales Anims.pas loads each object at.
FLAG_SCALE :: 4.0
KIT_SCALE :: 2.15
PARACHUTE_SCALE :: 5.0
GOSTEK_SCALE :: ANIMATION_SCALE // the animations', so the rest lengths match the poses

// karabin.po at every length a dropped gun has (the original's RifleSkeleton10 to 55).
@(rodata)
RIFLE_SCALES := [?]f32{1.0, 1.1, 1.8, 2.2, 2.8, 3.6, 3.7, 3.9, 4.3, 5.5}

// One .po file: points, and the pairs of them held at a distance.
Skeleton :: struct {
	points:      []utils.Vec2,
	constraints: [][2]int, // 0-based point indices
}

// Every skeleton the game uses.
Skeletons :: struct {
	flag:      Skeleton,
	kit:       Skeleton,
	parachute: Skeleton,
	gostek:    Skeleton, // for the corpses' constraints and rest lengths
	rifles:    [len(RIFLE_SCALES)]Skeleton,
}

// A .po file's text at a scale: for each point a name line, then its x, y (depth,
// unused in 2D) and z, a line each; CONSTRAINTS; then the pairs, as "P1" and "P2" on a
// line each (1-based); ENDFILE at the end.
skeleton_parse :: proc(text: string, scale: f32, allocator := context.allocator) -> Skeleton {
	points := make([dynamic]utils.Vec2, allocator)
	constraints := make([dynamic][2]int, allocator)

	text := text
	for name in utils.next_line(&text) {
		if name == "CONSTRAINTS" {
			break
		}
		x := next_coordinate(&text)
		_ = next_coordinate(&text) // y: depth
		z := next_coordinate(&text)
		append(&points, utils.Vec2{-x * scale / 1.2, -z * scale})
	}

	for {
		a := utils.next_line(&text) or_break
		if a == "ENDFILE" {
			break
		}
		b := utils.next_line(&text) or_break
		if len(a) < 2 || len(b) < 2 {
			break
		}
		append(&constraints, [2]int{point_number(a) - 1, point_number(b) - 1})
	}

	return {points[:], constraints[:]}
}

// <data_dir>/objects/<file> at a scale. False, with the reason logged, if it can't be read.
skeleton_load :: proc(data_dir, file: string, scale: f32, allocator := context.allocator) -> (skeleton: Skeleton, ok: bool) {
	text := utils.read_file(utils.temp_path(data_dir, "objects", file), context.temp_allocator) or_return
	return skeleton_parse(string(text), scale, allocator), true
}

skeleton_destroy :: proc(skeleton: ^Skeleton, allocator := context.allocator) {
	delete(skeleton.points, allocator)
	delete(skeleton.constraints, allocator)
	skeleton^ = {}
}

// Every skeleton the game uses, from <data_dir>/objects. False, with the file that
// failed logged, if one can't be read.
skeletons_load :: proc(data_dir: string, allocator := context.allocator) -> (skeletons: Skeletons, ok: bool) {
	defer if !ok {
		skeletons_destroy(&skeletons, allocator)
	}
	skeletons.flag = skeleton_load(data_dir, "flag.po", FLAG_SCALE, allocator) or_return
	skeletons.kit = skeleton_load(data_dir, "kit.po", KIT_SCALE, allocator) or_return
	skeletons.parachute = skeleton_load(data_dir, "para.po", PARACHUTE_SCALE, allocator) or_return
	skeletons.gostek = skeleton_load(data_dir, "gostek.po", GOSTEK_SCALE, allocator) or_return
	for scale, i in RIFLE_SCALES {
		skeletons.rifles[i] = skeleton_load(data_dir, "karabin.po", scale, allocator) or_return
	}
	return skeletons, true
}

skeletons_destroy :: proc(skeletons: ^Skeletons, allocator := context.allocator) {
	skeleton_destroy(&skeletons.flag, allocator)
	skeleton_destroy(&skeletons.kit, allocator)
	skeleton_destroy(&skeletons.parachute, allocator)
	skeleton_destroy(&skeletons.gostek, allocator)
	for &rifle in skeletons.rifles {
		skeleton_destroy(&rifle, allocator)
	}
}

// The number in a point name, "P12".
@(private = "file")
point_number :: proc(name: string) -> int {
	number, _ := strconv.parse_int(name[1:])
	return number
}
