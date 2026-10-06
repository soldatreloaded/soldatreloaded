package resources

import "core:encoding/ini"
import "core:log"
import "core:strconv"
import "core:strings"

import "../utils"

// What a mod says of itself, in its mod.ini (the mod's own, else Classic's: mod_file), as
// an original Soldat or OpenSoldat mod says it:
//
//   [SCALE]   how big its images are in the world: DefaultScale, the pixels to a unit of
//             any image, and then an image's own, by its path ("interface-gfx/cursor.png")
//             or its folder's
//   [GOSTEK]  where the soldier's parts and weapons are pinned: <id>_CenterX and
//             <id>_CenterY, 0 to 1 across the image, by the original's ids for them
//             ("Left_Thigh", "Secondary_Ak74", "Primary_Ak74_Fire")
//
// Sections and keys are matched without regard to case. A key the file doesn't hold
// keeps its default; a mod without the file has them all.

MOD_CONFIG_FILE :: "mod.ini"

Mod_Config :: struct {
	scale:   Scale_Settings,
	anchors: map[string]f32, // [GOSTEK]: by its key, in lower case ("left_thigh_centerx")
}

// An image's pixels to a unit in the world: by its path relative to the mod
// ("interface-gfx/cursor.png"), else by its folder's ("interface-gfx"), else `default`.
// Paths are matched without regard to case or which way their slashes lean.
Scale_Settings :: struct {
	default: f32,
	paths:   map[string]f32,
}

DEFAULT_MOD_SCALE :: 4.5

// The mod's mod.ini, its strings and maps allocated with `allocator`; the defaults if it
// hasn't one. A value that isn't a number is passed over, logged. Free with
// mod_config_destroy.
mod_config_load :: proc(mod: Mod, allocator := context.allocator) -> (config: Mod_Config) {
	config.scale.default = DEFAULT_MOD_SCALE
	config.scale.paths = make(map[string]f32, allocator)
	config.anchors = make(map[string]f32, allocator)
	path := mod_file(mod, MOD_CONFIG_FILE)
	if !utils.file_exists(path) do return
	text, read := utils.read_file(path, context.temp_allocator)
	if !read do return

	it := ini.iterator_from_string(string(text))
	for key, raw in ini.iterate(&it) {
		value, is_number := strconv.parse_f32(raw)
		if !is_number {
			log.warnf("%s: [%s] %s = %s isn't a number; passed over", path, it.section, key, raw)
			continue
		}
		section := strings.to_lower(it.section, context.temp_allocator)
		switch section {
		case "scale":
			if strings.equal_fold(key, "DefaultScale") {
				config.scale.default = value
			} else {
				config.scale.paths[strings.to_lower(key, allocator)] = value
			}
		case "gostek":
			config.anchors[strings.to_lower(key, allocator)] = value
		}
	}
	return
}

mod_config_destroy :: proc(config: ^Mod_Config, allocator := context.allocator) {
	for path in config.scale.paths do delete(path, allocator)
	delete(config.scale.paths)
	for key in config.anchors do delete(key, allocator)
	delete(config.anchors)
	config^ = {}
}

// Where the part or weapon of the original's id `id` is pinned, by [GOSTEK]; `default`
// where it doesn't say, or says only one of the two.
mod_anchor :: proc(config: ^Mod_Config, id: string, default: [2]f32) -> (center: [2]f32) {
	center = default
	if id == "" do return
	x := strings.to_lower(strings.concatenate({id, "_centerx"}, context.temp_allocator), context.temp_allocator)
	y := strings.to_lower(strings.concatenate({id, "_centery"}, context.temp_allocator), context.temp_allocator)
	if value, found := config.anchors[x]; found do center.x = value
	if value, found := config.anchors[y]; found do center.y = value
	return
}
