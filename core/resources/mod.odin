package resources

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import "../utils"

// What the game looks and sounds like: mods/default/, the game's own, and over it the
// one mod a player picks (graphics.mod), mods/<name>/. A mod holds only what it
// changes: each file is looked for in the mod first, then in the default, so a mod may
// be a single sound. What the game plays by (the maps, animations, skeletons) is not a
// mod's but data/'s, the same for everyone in a game.

MOD_DEFAULT :: "default"
MODS_DIR :: "mods" // where the mods are, from the client's working directory

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

MOD_NAME_MAX :: 32

// The mods under `mods_dir`, by their folders' names: the default first, the rest
// sorted. Free with mods_list_destroy.
mods_list :: proc(mods_dir: string, allocator := context.allocator) -> []string {
	names := make([dynamic]string, allocator)
	append(&names, strings.clone(MOD_DEFAULT, allocator))
	entries, err := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	if err == nil {
		for entry in entries {
			if entry.type != .Directory || strings.equal_fold(entry.name, MOD_DEFAULT) do continue
			append(&names, strings.clone(entry.name, allocator))
		}
	}
	slice.sort(names[1:])
	return names[:]
}

mods_list_destroy :: proc(names: []string, allocator := context.allocator) {
	for name in names do delete(name, allocator)
	delete(names, allocator)
}

// Why `name` can't be a new mod's folder under `mods_dir`; empty if it can.
mod_name_problem :: proc(mods_dir, name: string) -> string {
	switch {
	case name == "":
		return "Give the mod a name."
	case len(name) > MOD_NAME_MAX:
		return "That name is too long."
	case name == "." || name == ".." || strings.has_suffix(name, ".") || strings.has_suffix(name, " "):
		return "A name can't end with a dot or a space."
	case strings.contains_any(name, "\\/:*?\"<>|"):
		return "A name can't have any of \\ / : * ? \" < > |"
	}
	for c in name {
		if c < 32 do return "That name has a character a folder can't."
	}
	if strings.equal_fold(name, MOD_DEFAULT) || utils.file_exists(utils.temp_path(mods_dir, name)) {
		return "There is a mod by that name already."
	}
	return ""
}

// A new mod, `name`: a copy of the default to change. Why not, if it can't be made; a
// copy only part made is taken away again.
mod_create :: proc(mods_dir, name: string) -> (problem: string) {
	if problem = mod_name_problem(mods_dir, name); problem != "" do return
	dir := utils.temp_path(mods_dir, name)
	if err := os.copy_directory_all(dir, utils.temp_path(mods_dir, MOD_DEFAULT)); err != nil {
		log.errorf("cannot copy %s/%s to %s: %v", mods_dir, MOD_DEFAULT, dir, err)
		os.remove_all(dir)
		return "The default mod couldn't be copied."
	}
	return
}

// The mod `name` gone from `mods_dir`, all its files; never the default. False, with the
// reason logged, if it couldn't be.
mod_delete :: proc(mods_dir, name: string) -> bool {
	if name == "" || strings.equal_fold(name, MOD_DEFAULT) || name == "." || name == ".." || strings.contains_any(name, "\\/") do return false
	dir := utils.temp_path(mods_dir, name)
	if err := os.remove_all(dir); err != nil {
		log.errorf("cannot delete %s: %v", dir, err)
		return false
	}
	return true
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
