package resources

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import "../utils"

// What the game looks and sounds like: mods/classic/, the game's own, which ships with it,
// and the players' mods, each in mods/<name>/. Classic is under every other: a player
// picks one mod (graphics.mod), and each file is looked for in it first, then in
// Classic, so a mod holds only what it changes; a mod may be a single sound. Classic is
// the release's, kept and updated by the launcher; the players' are theirs, and never
// touched by an update. What the game plays by (the maps, animations, skeletons) is not
// a mod's but data/'s, the same for everyone in a game.

MOD_CLASSIC :: "classic"
MODS_DIR :: "mods" // where the mods are, from the client's working directory

Mod :: struct {
	dir:      string, // the mod's folder; empty for Classic alone
	fallback: string, // Classic's
}

// The mod `name` over Classic, both under `mods_dir`. An empty name, Classic's, or the
// "default" that named it before, for Classic alone.
mod_make :: proc(mods_dir, name: string, allocator := context.allocator) -> (mod: Mod) {
	mod.fallback = strings.join({mods_dir, MOD_CLASSIC}, "/", allocator)
	if name != "" && !mod_builtin(name) && !strings.equal_fold(name, "default") {
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

// A mod as the Mods page lists it.
Mod_Listing :: struct {
	name:    string,
	builtin: bool, // Classic: the game's, not to be deleted, and kept by the launcher
}

// The mods under `mods_dir`: Classic first, then the players', sorted by name. Free with
// mods_list_destroy.
mods_list :: proc(mods_dir: string, allocator := context.allocator) -> []Mod_Listing {
	listings := make([dynamic]Mod_Listing, allocator)
	append(&listings, Mod_Listing{strings.clone(MOD_CLASSIC, allocator), true})
	for name in folders(mods_dir) {
		// a hidden folder isn't a mod: a mod being installed is unpacked into one
		if mod_builtin(name) || reserved(name) || strings.has_prefix(name, ".") do continue
		append(&listings, Mod_Listing{strings.clone(name, allocator), false})
	}
	return listings[:]
}

mods_list_destroy :: proc(listings: []Mod_Listing, allocator := context.allocator) {
	for listing in listings do delete(listing.name, allocator)
	delete(listings, allocator)
}

// The folders in `dir`, sorted; with the temp allocator.
@(private = "file")
folders :: proc(dir: string) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return nil
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory do append(&names, entry.name)
	}
	slice.sort(names[:])
	return names[:]
}

// A name no player's mod may have besides Classic's: the old default's, which an install
// updated from before may still hold until the launcher clears it.
@(private = "file")
reserved :: proc(name: string) -> bool {
	return strings.equal_fold(name, "default")
}

// Whether the mod `name` is the one the game ships, Classic, in any case: so no player's
// mod takes its name, even where the files' names are told apart by it.
mod_builtin :: proc(name: string) -> bool {
	return strings.equal_fold(name, MOD_CLASSIC)
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
	if reserved(name) do return "That name is the game's own."
	if mod_builtin(name) || utils.file_exists(utils.temp_path(mods_dir, name)) {
		return "There is a mod by that name already."
	}
	return ""
}

// A new mod of the player's, `name`: an empty folder, which wears Classic until files
// are put in it to change it. Why not, if it can't be made.
mod_create :: proc(mods_dir, name: string) -> (problem: string) {
	if problem = mod_name_problem(mods_dir, name); problem != "" do return
	dir := utils.temp_path(mods_dir, name)
	if err := os.make_directory_all(dir); err != nil {
		log.errorf("cannot make %s: %v", dir, err)
		return "Its folder couldn't be made."
	}
	return
}

// The player's mod `name` gone from `mods_dir`, all its files; never Classic. False,
// with the reason logged, if it couldn't be.
mod_delete :: proc(mods_dir, name: string) -> bool {
	if name == "" || reserved(name) || mod_builtin(name) || name == "." || name == ".." || strings.contains_any(name, "\\/") do return false
	dir := utils.temp_path(mods_dir, name)
	if err := os.remove_all(dir); err != nil {
		log.errorf("cannot delete %s: %v", dir, err)
		return false
	}
	return true
}

// The path of a file named relative to a mod ("sfx/shotgun.wav"): the mod's if it has
// it, else Classic's, whether it is there or not, so a file that can't be found is
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
// Classic's. Allocated with the temp allocator.
mod_image :: proc(mod: Mod, dir, name: string, listings: ^utils.Dir_Listings = nil) -> (path: string, ok: bool) {
	if mod.dir != "" {
		path, ok = utils.find_file_any_case(utils.temp_path(mod.dir, dir), name, ".png", context.temp_allocator, listings)
		if ok {
			return
		}
	}
	return utils.find_file_any_case(utils.temp_path(mod.fallback, dir), name, ".png", context.temp_allocator, listings)
}
