package resources

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import "../utils"

// What the game looks and sounds like: a stack of mods over Classic. Classic,
// mods/classic/, is the game's own, ships with it and is kept by the launcher; under
// every other, it is never listed nor turned off. The players' mods are theirs, in
// mods/, each a .smod (a zip, as OpenSoldat's are, and what the Mods page installs) or a
// folder (for making one, its changes seen as they are made), and never touched by an
// update. The player turns on any of them, in an order (graphics.mods, the top first),
// and each file is looked for in each mod in turn, then in Classic: so a mod holds only
// what it changes, and a mod of the soldier's art and one of sounds are worn together.
//
// A mod's files sit at its root as Classic's do (gostek-gfx/, sfx/, mod.ini, ...); one
// packed or unpacked a folder or two down, as zips often are, is read from where its
// files are. Names are matched without regard to case. Each mod's images are sized and
// pinned by its own mod.ini, or by Classic's if it hasn't one. What the game plays by
// (the maps, animations, skeletons) is not a mod's but data/'s, the same for everyone.

MOD_CLASSIC :: "classic"
MODS_DIR :: "mods" // where the mods are, from the client's working directory
MOD_EXTENSION :: ".smod"
MOD_NAME_MAX :: 32

// What is at a mod's root, by which its root is known: its folders and its mod.ini.
@(rodata)
MOD_FOLDERS := [?]string{"gostek-gfx", "weapons-gfx", "interface-gfx", "sparks-gfx", "objects-gfx", "scenery-gfx", "textures", "sfx", "txt", "fonts"}

Mod :: struct {
	layers: []Mod_Layer, // the mods on, the top first, then Classic, always last
}

// One mod of the stack: a folder, or an .smod open.
Mod_Layer :: struct {
	name:       string,
	dir:        string,       // a folder's root: where its files are; "" for an .smod
	archive:    ^Mod_Archive, // an .smod's
	config:     ^Mod_Config,  // its mod.ini's, else Classic's
	own_config: bool,
	old_art:    map[string]bool, // by folder, whether its art is the old, small kind (mod_old_art), as found
}

// An .smod open: its files, by their path below the mod's root in lower case.
Mod_Archive :: struct {
	path:  string,
	zip:   utils.Zip_File,
	files: map[string]string, // to the zip's own name for it
	root:  string,            // the folders above the mod's root in the zip, "" for none
}

// A file found in a mod: read it with mod_read.
Mod_File :: struct {
	layer:   int,          // of the mod's layers; -1 for a map's own folder of art
	archive: ^Mod_Archive, // its .smod; nil for a file on disk
	path:    string,       // on disk, or the zip's name for it; with the temp allocator
}

// The mods `names`, the top first, over Classic, all under `mods_dir`. A name that
// isn't in mods/ is passed over, logged. Free with mod_destroy.
mod_make :: proc(mods_dir: string, names: []string, allocator := context.allocator) -> (mod: Mod) {
	context.allocator = allocator
	layers := make([dynamic]Mod_Layer)
	for name in names {
		if name == "" || mod_builtin(name) || reserved(name) do continue
		layer, found := layer_open(mods_dir, name)
		if !found {
			log.warnf("the mod %s isn't in %s/; passed over", name, mods_dir)
			continue
		}
		append(&layers, layer)
	}
	classic := Mod_Layer{name = strings.clone(MOD_CLASSIC), dir = strings.join({mods_dir, MOD_CLASSIC}, "/")}
	classic.config = new(Mod_Config)
	classic.config^, _ = mod_config_read(&classic)
	classic.own_config = true // freed with it, read or not
	append(&layers, classic)
	for &layer in layers[:len(layers) - 1] {
		config, has := mod_config_read(&layer)
		if has {
			layer.config = new(Mod_Config)
			layer.config^ = config
			layer.own_config = true
		} else {
			mod_config_destroy(&config)
			layer.config = classic.config
		}
	}
	for &layer in layers do layer.old_art = make(map[string]bool)
	mod.layers = layers[:]
	return
}

mod_destroy :: proc(mod: ^Mod, allocator := context.allocator) {
	context.allocator = allocator
	for &layer in mod.layers {
		if layer.own_config {
			mod_config_destroy(layer.config)
			free(layer.config)
		}
		for dir in layer.old_art do delete(dir)
		delete(layer.old_art)
		layer_close(&layer)
	}
	delete(mod.layers)
	mod^ = {}
}

// Classic alone, of `mod`: its last layer.
mod_classic :: proc(mod: Mod) -> Mod {
	return {layers = mod.layers[len(mod.layers) - 1:]}
}

// ---------------------------------------------------------------------------------
// Finding and reading a mod's files

// The file at `path` relative to a mod ("txt/font.ini"), in any case: the top mod's that
// has it, else Classic's. False if none has it.
mod_file :: proc(mod: Mod, path: string) -> (file: Mod_File, found: bool) {
	for &layer, i in mod.layers {
		if file, found = layer_file(&layer, i, path); found do return
	}
	return
}

// An image in a mod's folder `dir` ("scenery-gfx"), as Soldat finds one: in any case,
// preferring a .png whatever extension `name` gives, then `name` itself, then a .bmp of
// it. The top mod's that has it, else Classic's.
mod_image :: proc(mod: Mod, dir, name: string, listings: ^utils.Dir_Listings = nil) -> (file: Mod_File, found: bool) {
	for &layer, i in mod.layers {
		if file, found = layer_find(&layer, i, dir, name, ".png", listings); found do return
	}
	return
}

// Whether a mod over Classic, not Classic, has the image `name` in `dir`, found as
// mod_image finds one.
mod_has_image :: proc(mod: Mod, dir, name: string, listings: ^utils.Dir_Listings = nil) -> bool {
	for &layer, i in mod.layers[:max(len(mod.layers) - 1, 0)] {
		if _, found := layer_find(&layer, i, dir, name, ".png", listings); found do return true
	}
	return false
}

// An image a map draws with, in `dir` ("scenery-gfx"), as mod_image finds one: the mods'
// over Classic, then the map's own (in each of `map_dirs`, the map's folders of art, as
// it shipped or was downloaded with it), then Classic's.
map_image :: proc(mod: Mod, map_dirs: []string, dir, name: string) -> (file: Mod_File, found: bool) {
	last := len(mod.layers) - 1
	for &layer, i in mod.layers[:max(last, 0)] {
		if file, found = layer_find(&layer, i, dir, name, ".png"); found do return
	}
	for map_dir in map_dirs {
		if path, ok := utils.find_file_any_case(utils.temp_path(map_dir, dir), name, ".png", context.temp_allocator); ok {
			return {layer = -1, path = path}, true
		}
	}
	if last >= 0 do return layer_find(&mod.layers[last], last, dir, name, ".png")
	return
}

// A file found in a mod, its bytes allocated with `allocator`. False, logged, if it
// can't be read.
mod_read :: proc(file: Mod_File, allocator := context.allocator) -> (data: []byte, ok: bool) {
	if file.archive == nil do return utils.read_file(file.path, allocator)
	entry, has := file.archive.zip.entries[file.path]
	if has do data, ok = utils.zip_read(&file.archive.zip, entry, allocator)
	if !ok do log.errorf("cannot read %s from %s", file.path, file.archive.path)
	return
}

// Where a file found in a mod is, to say so: its path, or its .smod's and its name in it.
mod_file_name :: proc(file: Mod_File) -> string {
	if file.archive == nil do return file.path
	return strings.concatenate({file.archive.path, ":", file.path}, context.temp_allocator)
}

// The file at `path` in one layer, in any case.
@(private)
layer_file :: proc(layer: ^Mod_Layer, index: int, path: string) -> (file: Mod_File, found: bool) {
	if a := layer.archive; a != nil {
		name := a.files[strings.to_lower(path, context.temp_allocator)] or_return
		return {layer = index, archive = a, path = name}, true
	}
	exact := utils.temp_path(layer.dir, path)
	if utils.file_exists(exact) do return {layer = index, path = exact}, true
	slash := strings.last_index_byte(path, '/')
	dir := utils.temp_path(layer.dir, path[:slash]) if slash >= 0 else layer.dir
	name := path[slash + 1:]
	if found_path, ok := utils.find_file_any_case(dir, name, filepath.ext(name), context.temp_allocator); ok && strings.equal_fold(filepath.base(found_path), name) {
		return {layer = index, path = found_path}, true
	}
	return
}

// The file `name` in `dir` of one layer, as utils.find_file_any_case finds one: in any
// case, a `preferred` extension of its stem first, then `name`, then a .bmp of it.
@(private)
layer_find :: proc(layer: ^Mod_Layer, index: int, dir, name, preferred: string, listings: ^utils.Dir_Listings = nil) -> (file: Mod_File, found: bool) {
	if name == "" do return
	a := layer.archive
	if a == nil {
		path := utils.find_file_any_case(utils.temp_path(layer.dir, dir), name, preferred, context.temp_allocator, listings) or_return
		return {layer = index, path = path}, true
	}
	stem := filepath.stem(name)
	for candidate in ([3]string{strings.concatenate({stem, preferred}, context.temp_allocator), name, strings.concatenate({stem, ".bmp"}, context.temp_allocator)}) {
		key := strings.to_lower(utils.temp_path(dir, candidate) if dir != "" else candidate, context.temp_allocator)
		if zip_name, has := a.files[key]; has do return {layer = index, archive = a, path = zip_name}, true
	}
	return
}

// The names of the files in `dir` of one layer, in no order; with the temp allocator.
@(private)
layer_folder :: proc(layer: ^Mod_Layer, dir: string) -> []string {
	names := make([dynamic]string, context.temp_allocator)
	if a := layer.archive; a != nil {
		prefix := strings.to_lower(strings.concatenate({dir, "/"}, context.temp_allocator), context.temp_allocator)
		for key in a.files {
			if strings.has_prefix(key, prefix) && strings.index_byte(key[len(prefix):], '/') < 0 do append(&names, key[len(prefix):])
		}
		return names[:]
	}
	entries, _ := os.read_all_directory_by_path(utils.temp_path(layer.dir, dir), context.temp_allocator)
	for entry in entries do if entry.type != .Directory do append(&names, entry.name)
	return names[:]
}

// ---------------------------------------------------------------------------------
// The mods in mods/

// A mod as the Mods page lists it.
Mod_Listing :: struct {
	name:     string,
	title:    string,        // what it is shown as: its about.json's title, else its name
	packed:   bool,          // an .smod; else a folder
	contents: Mod_Contents,  // what of the game it changes
	nested:   string,        // the folders its files are found under, if not at its root
}

Mod_Content :: enum {
	Graphics, // gostek, weapons, interface, sparks, objects, scenery or textures
	Sounds,
	Fonts,    // txt/font.ini, or fonts/
	Config,   // mod.ini
}
Mod_Contents :: bit_set[Mod_Content]

// The players' mods under `mods_dir`, by name, Classic left out: each .smod and each
// folder, a folder before an .smod of its name, which it hides. Free with
// mods_list_destroy.
mods_list :: proc(mods_dir: string, allocator := context.allocator) -> []Mod_Listing {
	listings := make([dynamic]Mod_Listing, allocator)
	entries, err := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	if err != nil do return listings[:]
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		name := entry.name
		if entry.type != .Directory {
			if !strings.equal_fold(filepath.ext(name), MOD_EXTENSION) do continue
			name = name[:len(name) - len(MOD_EXTENSION)]
		}
		// a hidden one isn't a mod: one being installed is written as one
		if name == "" || mod_builtin(name) || reserved(name) || strings.has_prefix(name, ".") do continue
		if !slice.contains(names[:], name) do append(&names, name)
	}
	slice.sort_by(names[:], proc(a, b: string) -> bool {return strings.to_lower(a, context.temp_allocator) < strings.to_lower(b, context.temp_allocator)})
	for name in names {
		layer, found := layer_open(mods_dir, name, context.temp_allocator)
		if !found do continue
		listing := Mod_Listing{name = strings.clone(name, allocator), packed = layer.archive != nil, contents = layer_contents(&layer)}
		title := layer_about(&layer).title
		listing.title = strings.clone(title if strings.trim_space(title) != "" else name, allocator)
		if layer.archive != nil {
			listing.nested = strings.clone(layer.archive.root, allocator)
		} else {
			listing.nested = strings.clone(strings.trim_prefix(strings.trim_prefix(layer.dir, utils.temp_path(mods_dir, name)), "/"), allocator)
		}
		layer_close(&layer, context.temp_allocator)
		append(&listings, listing)
	}
	return listings[:]
}

mods_list_destroy :: proc(listings: []Mod_Listing, allocator := context.allocator) {
	for listing in listings {
		delete(listing.name, allocator)
		delete(listing.title, allocator)
		delete(listing.nested, allocator)
	}
	delete(listings, allocator)
}

// What the mod `name` says of itself in its about.json, as the mods repository writes
// it: its version; empty if it has none.
mod_version :: proc(mods_dir, name: string) -> string {
	layer, found := layer_open(mods_dir, name, context.temp_allocator)
	if !found do return ""
	defer layer_close(&layer, context.temp_allocator)
	return layer_about(&layer).version
}

// What a mod's about.json says of it, as the mods repository writes it; empty where it
// says nothing, or has none. With the temp allocator.
Mod_About :: struct {
	version: string,
	title:   string, // the name it is shown by, spaces and all
}

@(private = "file")
layer_about :: proc(layer: ^Mod_Layer) -> (about: Mod_About) {
	file, found := layer_file(layer, 0, "about.json")
	if !found do return
	data, read := mod_read(file, context.temp_allocator)
	if !read do return
	json.unmarshal(data, &about, allocator = context.temp_allocator)
	return
}

// The mod `name` in `mods_dir`, open: its folder, else its .smod.
@(private = "file")
layer_open :: proc(mods_dir, name: string, allocator := context.allocator) -> (layer: Mod_Layer, found: bool) {
	context.allocator = allocator
	folder := utils.temp_path(mods_dir, name)
	if os.is_dir(folder) {
		return {name = strings.clone(name), dir = strings.clone(folder_root(folder))}, true
	}
	path := strings.concatenate({folder, MOD_EXTENSION}, context.temp_allocator)
	if !os.is_file(path) do return
	a := new(Mod_Archive)
	ok: bool
	if a.zip, ok = utils.zip_open(path); !ok {
		log.errorf("%s isn't a zip the game can read", path)
		free(a)
		return
	}
	a.path = strings.clone(path)
	a.root = strings.clone(archive_root(a.zip.entries))
	a.files = make(map[string]string, len(a.zip.entries))
	for zip_name in a.zip.entries {
		if !strings.has_prefix(zip_name, a.root) do continue
		a.files[strings.to_lower(zip_name[len(a.root):])] = zip_name
	}
	return {name = strings.clone(name), archive = a}, true
}

@(private = "file")
layer_close :: proc(layer: ^Mod_Layer, allocator := context.allocator) {
	context.allocator = allocator
	if a := layer.archive; a != nil {
		for key in a.files do delete(key)
		delete(a.files)
		utils.zip_close(&a.zip)
		delete(a.path)
		delete(a.root)
		free(a)
	}
	delete(layer.name)
	delete(layer.dir)
	layer^ = {}
}

// What a layer has of the game's: its root's folders and files.
@(private = "file")
layer_contents :: proc(layer: ^Mod_Layer) -> (contents: Mod_Contents) {
	tops := make([dynamic]string, context.temp_allocator)
	if a := layer.archive; a != nil {
		for key in a.files {
			slash := strings.index_byte(key, '/')
			append(&tops, key[:slash] if slash >= 0 else key)
		}
	} else {
		entries, _ := os.read_all_directory_by_path(layer.dir, context.temp_allocator)
		for entry in entries do append(&tops, strings.to_lower(entry.name, context.temp_allocator))
	}
	for top in tops {
		switch top {
		case "gostek-gfx", "weapons-gfx", "interface-gfx", "sparks-gfx", "objects-gfx", "scenery-gfx", "textures":
			contents += {.Graphics}
		case "sfx":
			contents += {.Sounds}
		case "txt", "fonts":
			contents += {.Fonts}
		case "mod.ini":
			contents += {.Config}
		}
	}
	return
}

// Where a folder's mod's files are: the folder, if they are at its root; else the
// first folder down, two at most, that has them. The folder itself if none has.
@(private)
folder_root :: proc(folder: string) -> string {
	level := []string{folder}
	for _ in 0 ..= 2 {
		next := make([dynamic]string, context.temp_allocator)
		for dir in level {
			entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
			if err != nil do continue
			slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
			for entry in entries {
				if is_root_name(entry.name, entry.type == .Directory) do return dir
			}
			for entry in entries {
				if entry.type == .Directory do append(&next, utils.temp_path(dir, entry.name))
			}
		}
		level = next[:]
	}
	return folder
}

// Where in a zip a mod's files are: "" if at its root, else the shallowest folder that
// has them ("Competitive/"), with its slash.
@(private = "file")
archive_root :: proc(entries: map[string]utils.Zip_Entry) -> string {
	best := ""
	best_depth := max(int)
	for name in entries {
		parts := strings.split(name, "/", context.temp_allocator)
		for part, i in parts {
			if i >= best_depth do break
			if is_root_name(part, i < len(parts) - 1) {
				best_depth = i
				best = strings.join(parts[:i], "/", context.temp_allocator)
				break
			}
		}
	}
	if best_depth == max(int) || best == "" do return ""
	return strings.concatenate({best, "/"}, context.temp_allocator)
}

// Whether a name, of a folder or a file, is one a mod's root has.
@(private)
is_root_name :: proc(name: string, folder: bool) -> bool {
	if !folder do return strings.equal_fold(name, MOD_CONFIG_FILE)
	for known in MOD_FOLDERS {
		if strings.equal_fold(name, known) do return true
	}
	return false
}

// ---------------------------------------------------------------------------------
// The players' mods, made and deleted

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

// Whether a mod `name` is in `mods_dir`, as a folder or an .smod, in any case.
mod_exists :: proc(mods_dir, name: string) -> bool {
	entries, err := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		other := entry.name
		if entry.type != .Directory {
			if !strings.equal_fold(filepath.ext(other), MOD_EXTENSION) do continue
			other = other[:len(other) - len(MOD_EXTENSION)]
		}
		if strings.equal_fold(other, name) do return true
	}
	return false
}

// Why `name` can't be a new mod's under `mods_dir`; empty if it can.
mod_name_problem :: proc(mods_dir, name: string) -> string {
	switch {
	case name == "":
		return "Give the mod a name."
	case len(name) > MOD_NAME_MAX:
		return "That name is too long."
	case name == "." || name == ".." || strings.has_prefix(name, ".") || strings.has_suffix(name, ".") || strings.has_suffix(name, " "):
		return "A name can't begin or end with a dot, nor end with a space."
	case strings.contains_any(name, "\\/:*?\"<>|"):
		return "A name can't have any of \\ / : * ? \" < > |"
	}
	for c in name {
		if c < 32 do return "That name has a character a file can't."
	}
	if reserved(name) do return "That name is the game's own."
	if mod_builtin(name) || mod_exists(mods_dir, name) {
		return "There is a mod by that name already."
	}
	return ""
}

// A new mod of the player's, `name`: an empty folder, which changes nothing until files
// are put in it. Why not, if it can't be made.
mod_create :: proc(mods_dir, name: string) -> (problem: string) {
	if problem = mod_name_problem(mods_dir, name); problem != "" do return
	dir := utils.temp_path(mods_dir, name)
	if err := os.make_directory_all(dir); err != nil {
		log.errorf("cannot make %s: %v", dir, err)
		return "Its folder couldn't be made."
	}
	return
}

// The player's mod `name` gone from `mods_dir`: its folder and its .smod, both if it has
// both; never Classic. False, with the reason logged, if it couldn't be.
mod_delete :: proc(mods_dir, name: string) -> bool {
	if name == "" || reserved(name) || mod_builtin(name) || name == "." || name == ".." || strings.contains_any(name, "\\/") do return false
	dir := utils.temp_path(mods_dir, name)
	if os.is_dir(dir) {
		if err := os.remove_all(dir); err != nil {
			log.errorf("cannot delete %s: %v", dir, err)
			return false
		}
	}
	packed := strings.concatenate({dir, MOD_EXTENSION}, context.temp_allocator)
	if os.is_file(packed) {
		if err := os.remove(packed); err != nil {
			log.errorf("cannot delete %s: %v", packed, err)
			return false
		}
	}
	return true
}

// Where the mod `name` is on disk, to show the player: its folder, or mods/ for an
// .smod.
mod_location :: proc(mods_dir, name: string) -> string {
	dir := utils.temp_path(mods_dir, name)
	return dir if os.is_dir(dir) else mods_dir
}
