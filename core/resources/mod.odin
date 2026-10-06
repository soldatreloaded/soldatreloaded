package resources

import "core:strings"

import "../utils"

// What the game looks and sounds like: mods/default/, the game's own, and over it the
// one mod a player picks (graphics.mod), mods/<name>/. A mod holds only what it
// changes: each file is looked for in the mod first, then in the default, so a mod may
// be a single sound. What the game plays by (the maps, animations, skeletons) is not a
// mod's but data/'s, the same for everyone in a game.

MOD_DEFAULT :: "default"

Mod :: struct {
	dir:      string, // mods/<name>; empty for the default alone
	fallback: string, // mods/default
}

// The mod `name` over the default, both under `mods_dir`; an empty name, or "default",
// for the default alone.
mod_make :: proc(mods_dir, name: string, allocator := context.allocator) -> (mod: Mod) {
	mod.fallback = strings.join({mods_dir, MOD_DEFAULT}, "/", allocator)
	if name != "" && name != MOD_DEFAULT {
		mod.dir = strings.join({mods_dir, name}, "/", allocator)
	}
	return
}

mod_destroy :: proc(mod: ^Mod, allocator := context.allocator) {
	delete(mod.dir, allocator)
	delete(mod.fallback, allocator)
	mod^ = {}
}

// The path of a file named relative to a mod ("sfx/shotgun.wav"): the mod's if it has
// it, else the default's, whether it is there or not, so a file that can't be found is
// reported where it belongs. Allocated with the temp allocator.
mod_file :: proc(mod: Mod, file: string) -> string {
	if mod.dir != "" {
		path := utils.temp_path(mod.dir, file)
		if utils.file_exists(path) {
			return path
		}
	}
	return utils.temp_path(mod.fallback, file)
}

// An image in a mod's directory `dir` ("scenery-gfx"), as Soldat finds one: in any
// case, preferring a .png whatever extension `name` gives. The mod's if it has it, else
// the default's. Allocated with the temp allocator.
mod_image :: proc(mod: Mod, dir, name: string, listings: ^utils.Dir_Listings = nil) -> (path: string, ok: bool) {
	if mod.dir != "" {
		path, ok = utils.find_file_any_case(utils.temp_path(mod.dir, dir), name, ".png", context.temp_allocator, listings)
		if ok {
			return
		}
	}
	return utils.find_file_any_case(utils.temp_path(mod.fallback, dir), name, ".png", context.temp_allocator, listings)
}
