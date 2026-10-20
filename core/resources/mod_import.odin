package resources

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:mem/virtual"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

import stbi "vendor:stb/image"

import "../utils"

// A mod made from a Soldat 1.7.1 install, as its player has it: the art and sounds they
// put over the game's own, or in a mod of its mods/, made the folder mods/<name>/
// (docs/srmod.md, "Bringing mods in"). What goes in is what they changed: a file of
// Classic's names that is neither 1.7.1's own as it came (SOLDAT_STOCK, by its size and
// CRC-32: Classic's art is redrawn, and the original's would replace it) nor the same as
// Classic's (an image by its pixels as the game draws it, so the same picture as a .bmp
// is the same), each laid out by part, its images at the scale Soldat 1 drew them at; and the
// pivots its mod.ini changes. The rest is Classic's already. Its custom interfaces are
// made mods of their own (interface_install).
//
// The install is found where Soldat is usually put (soldat_installs), or picked by the
// player; what a mod can be made from in it is its own folders, which a player may have
// put their art over, each mod of its mods/ and each custom interface (soldat_sources).

// The files of an original Soldat 1.7.1 install as it came (data/'s, from the client's
// working directory): "<size> <crc32, hex> <path in lower case>" a line.
SOLDAT_STOCK :: "data/soldat-1.7.1.txt"

// Where Soldat 1.7.1 may be, besides wherever the player says: where its installer puts
// it (C:\Soldat), Steam's (it is there as 1.7.1.1: any folder of a library's
// steamapps/common named for it, Steam found where Windows has it written, where it is
// usually put, and in the libraries it lists), Wine's and a few places a player is
// likely to have put it.
soldat_installs :: proc(allocator := context.allocator) -> []string {
	context.allocator = context.temp_allocator
	candidates := make([dynamic]string)
	steams := make([dynamic]string)
	when ODIN_OS == .Windows {
		home := os.get_env("USERPROFILE", context.temp_allocator)
		for drive in ([?]string{"C:", "D:", "E:", "F:", "G:"}) {
			append(&candidates, utils.temp_path(drive, "Soldat"), utils.temp_path(drive, "Games", "Soldat"))
			append(&steams, utils.temp_path(drive, "Steam"), utils.temp_path(drive, "SteamLibrary"), utils.temp_path(drive, "Games", "Steam"), utils.temp_path(drive, "Games", "SteamLibrary"))
		}
		for program_files in ([?]string{os.get_env("ProgramFiles(x86)", context.temp_allocator), os.get_env("ProgramFiles", context.temp_allocator)}) {
			if program_files == "" do continue
			append(&candidates, utils.temp_path(program_files, "Soldat"))
			append(&steams, utils.temp_path(program_files, "Steam"))
		}
		for steam in steam_registry() do append(&steams, steam)
		if home != "" {
			for under in ([?]string{"", "Desktop", "Documents", "Downloads", "Games"}) {
				append(&candidates, utils.temp_path(home, under, "Soldat") if under != "" else utils.temp_path(home, "Soldat"))
			}
		}
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			append(&candidates, utils.temp_path(home, "Soldat"), utils.temp_path(home, "Games", "Soldat"))
			// Wine's own prefix, where an installer run by it puts it
			for under in ([?]string{"Soldat", "Program Files (x86)/Soldat", "Program Files/Soldat", "Games/Soldat"}) {
				append(&candidates, utils.temp_path(home, ".wine", "drive_c", under))
			}
			// Steam's, run natively, as a Flatpak or as a Snap; on macOS its own
			for steam in ([?]string{
				".local/share/Steam",
				".steam/steam",
				".steam/root",
				".var/app/com.valvesoftware.Steam/.local/share/Steam",
				".var/app/com.valvesoftware.Steam/data/Steam",
				"snap/steam/common/.local/share/Steam",
				"Library/Application Support/Steam",
			}) {
				append(&steams, utils.temp_path(home, steam))
			}
		}
	}
	for steam in steams {
		steam_soldats(&candidates, steam)
		for library in steam_libraries(steam) do steam_soldats(&candidates, library)
	}
	found := make([dynamic]string, allocator)
	for dir in candidates {
		// the game's art folders in it itself (gostek-gfx, sfx...), not a folder or two down
		if !soldat_is_install(dir) || !strings.equal_fold(folder_root(dir), dir) do continue
		full, err := os.get_absolute_path(dir, context.temp_allocator)
		if err != nil do full = dir
		already := false
		for f in found do already ||= strings.equal_fold(f, full)
		if !already do append(&found, strings.clone(full, allocator))
	}
	return found[:]
}

// Whether `dir` is an original Soldat's install, or a mod laid out as one: art of the
// game's in it, its own or a folder or two down.
soldat_is_install :: proc(dir: string) -> bool {
	if dir == "" || !os.is_dir(dir) do return false
	root := folder_root(dir)
	entries, err := os.read_all_directory_by_path(root, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		if entry.type == .Directory && is_root_name(entry.name, true) && !strings.equal_fold(entry.name, "txt") do return true
	}
	return false
}

// How a mod is made (mod_import): from a Soldat install, the default; or from a mod of
// before, whole.
Import_Options :: struct {
	whole:         bool,        // every file of the first folder goes in, laid out as a Soldat 1 mod: a mod of before
	default_scale: f32,         // pixels to a unit where a mod.ini says none: Soldat 1's 1 (0), our mods of before Classic's 4.5
	about:         Srmod_About, // what its mod.json says of it beside its name and title
	description:   string,      // its description; "" for where it was made from
}

// What a mod's mod.json says of it, as it is written (srmod_write), beside its name,
// title and description: "" where it says nothing, its version 1.0.0 if none.
Srmod_About :: struct {
	version: string,
	author:  string,
	licence: string,
	source:  string,
}

// Whether `dir` is a mod laid out as Soldat 1's, of any of its folders (txt/ and fonts/
// too) or its mod.ini, at its root or a folder or two down.
old_layout :: proc(dir: string) -> bool {
	if dir == "" || !os.is_dir(dir) do return false
	entries, err := os.read_all_directory_by_path(folder_root(dir), context.temp_allocator)
	if err != nil do return false
	for entry in entries do if is_root_name(entry.name, entry.type == .Directory) do return true
	return false
}

// What making a mod found: how many of its files change something of the game's.
Import_Result :: struct {
	changed: int,    // its art and sounds that differ from Classic's
	problem: string, // why no mod was made; empty if one was
}

// What a mod can be made of in a Soldat install: what the player changed of its own
// files, a mod of its mods/, or a custom interface.
Soldat_Source_Kind :: enum {
	Own,
	Mod,
	Interface,
}

// One thing in a Soldat install a mod can be made of.
Soldat_Source :: struct {
	kind:    Soldat_Source_Kind,
	name:    string, // the mod's, in mods/, or the interface's; "" for the install's own
	dir:     string, // the install's, the mod's folder, or the custom-interfaces/ the interface is in
	changed: int,    // its art and sounds a mod may have: of the install's own, those that differ from the game's
	in_use:  bool,   // the mod Soldat was last played with (soldat.ini's Last_Mod)
}

// What mods can be made of in the install at `root`: what the player changed of its own
// files (always first, its count perhaps 0); each mod of its mods/; each custom interface,
// its own and its mods'. Those 1.7.1 ships with, every file as it came, are left out,
// being nobody's. With `allocator`; free with soldat_sources_destroy.
soldat_sources :: proc(root: string, classic: Mod, allocator := context.allocator) -> []Soldat_Source {
	sources := make([dynamic]Soldat_Source, allocator)
	stock := stock_load()
	files, _ := scan(root, root, classic, &stock, own = true)
	append(&sources, Soldat_Source{kind = .Own, dir = strings.clone(root, allocator), changed = changed_of(files)})
	last := last_mod(root)
	interface_dirs := make([dynamic]string, context.temp_allocator)
	append(&interface_dirs, utils.temp_path(root, "custom-interfaces"))
	mods_dir := utils.temp_path(root, "mods")
	for entry in sorted_entries(mods_dir) {
		if entry.type != .Directory do continue
		dir := utils.temp_path(mods_dir, entry.name)
		append(&interface_dirs, utils.temp_path(folder_root(dir), "custom-interfaces")) // a mod's, though it be an interface alone
		if !soldat_is_install(dir) || folder_is_stock(root, dir) do continue
		mod_files, _ := scan(root, dir, classic, &stock, own = false)
		append(&sources, Soldat_Source {
			kind    = .Mod,
			name    = strings.clone(entry.name, allocator),
			dir     = strings.clone(dir, allocator),
			changed = changed_of(mod_files),
			in_use  = last != "" && strings.equal_fold(last, entry.name),
		})
	}
	for dir in interface_dirs {
		for entry in sorted_entries(dir) {
			title := entry.name
			if entry.type == .Directory {
				if !utils.file_exists(utils.temp_path(marker_folder(entry.fullpath, INTERFACE_SETUP_FILE), INTERFACE_SETUP_FILE)) || folder_is_stock(root, entry.fullpath) do continue
			} else {
				if !strings.has_suffix(strings.to_lower(title, context.temp_allocator), INTERFACE_EXTENSION) do continue
				title = title[:len(title) - len(INTERFACE_EXTENSION)]
			}
			if title == "" || strings.has_prefix(title, ".") || strings.equal_fold(title, "default") do continue
			append(&sources, Soldat_Source{kind = .Interface, name = strings.clone(title, allocator), dir = strings.clone(dir, allocator), changed = 1})
		}
	}
	return sources[:]

	sorted_entries :: proc(dir: string) -> []os.File_Info {
		entries, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
		slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)})
		return entries
	}
}

soldat_sources_destroy :: proc(sources: []Soldat_Source, allocator := context.allocator) {
	for s in sources {
		delete(s.name, allocator)
		delete(s.dir, allocator)
	}
	delete(sources, allocator)
}

// The mod `name` (titled `title`, else its name) made in `mods_dir`, a folder, from the
// folders `dirs` of an original Soldat install, each over the last as Soldat wears a mod
// over its own folders: the install itself first, looked through for its own folders
// alone, not its mods/ or maps/; then a mod of its mods/. Each file of their art and
// sounds that is one of Classic's, neither 1.7.1's own as it came nor the same as
// Classic's, laid out by part (MOD_PATHS), each image keyed as the game keys it, its
// see-through made alpha, its pixels as they were and its mod.json saying the scale
// Soldat 1 drew it at (import_file); and the soldier's and the weapons' pivots, from their mod.inis'
// [GOSTEK], where they differ from Classic's. With `options.whole`, the first folder is a
// mod of its own, all of it going in (a mod of before, converted: mods_tidy).
mod_import :: proc(dirs: []string, mods_dir, name: string, classic: Mod, title := "", options := Import_Options{}) -> (result: Import_Result) {
	if problem := mod_name_problem(mods_dir, name); problem != "" do return {problem = problem}
	if !srmod_name_ok(name) do return {problem = "A mod's name is letters, digits, - and _, 32 at most."}
	if len(dirs) == 0 do return {problem = "Pick what to make the mod from."}
	default_scale := options.default_scale if options.default_scale > 0 else 1
	stock := stock_load()
	merged := make(map[string]Packed, 256, context.temp_allocator)
	anchors := make(map[string]f32, context.temp_allocator)
	for dir, i in dirs {
		whole := options.whole && i == 0
		if !soldat_is_install(dir) && !(whole && old_layout(dir)) do return {problem = "That isn't a Soldat folder: there is no gostek-gfx, weapons-gfx or the like in it."}
		own := i == 0 && !whole // the install itself
		files, _ := scan(dirs[0], dir, classic, &stock, own, default_scale)
		for f in files do merged[strings.to_lower(f.name, context.temp_allocator)] = f
		// its mod.ini's pivots, unless it is 1.7.1's own as it came: those are no player's
		root := dir if own else folder_root(dir)
		if !utils.file_exists(utils.temp_path(root, MOD_CONFIG_FILE)) || is_stock(&stock, utils.temp_path(root, MOD_CONFIG_FILE), MOD_CONFIG_FILE, install_path(dirs[0], root)) do continue
		config := soldat_config(root, default_scale)
		for key, value in config.anchors do anchors[key] = value
	}

	packed := make([dynamic]Packed, 0, len(merged), context.temp_allocator)
	for _, f in merged do append(&packed, f)
	entries: map[string][]byte
	scales := make(map[string]f32, context.temp_allocator)
	entries, result.changed = entries_of(packed[:], MOD_PARTS, &scales)

	// the pivots that differ from Classic's
	for part in ([]Part{.Soldier, .Weapons}) {
		theirs := srmod_pivots(&classic.worn.classic, part) if classic.worn != nil else nil
		pivots := make(map[string][2]f32, context.temp_allocator)
		// key by key, as Soldat 1 lays a mod's over the base's: a half it doesn't say is
		// Classic's
		for key in anchors {
			id: string
			switch {
			case strings.has_suffix(key, "_centerx"): id = key[:len(key) - len("_centerx")]
			case strings.has_suffix(key, "_centery"): id = key[:len(key) - len("_centery")]
			case: continue
			}
			if pivot_part(id) != part || id in pivots do continue
			old, had := theirs[id]
			if !had do continue // an image this game hasn't (the flamer, the bow): Classic pins all it draws
			x := anchors[strings.concatenate({id, "_centerx"}, context.temp_allocator)] or_else old.x
			y := anchors[strings.concatenate({id, "_centery"}, context.temp_allocator)] or_else old.y
			if abs(old.x - x) < 0.0001 && abs(old.y - y) < 0.0001 do continue
			pivots[id] = {x, y}
		}
		if len(pivots) == 0 do continue
		entries[strings.concatenate({PART_NAMES[part], "/", SRMOD_PIVOTS_FILE}, context.temp_allocator)] = transmute([]byte)pivots_text(pivots)
		result.changed += 1
	}
	if result.changed == 0 {
		return {problem = "Nothing there differs from the game as it came. Put your art and sounds in its folders first."}
	}
	description := options.description if options.description != "" else fmt.tprintf("Made from %s, in Soldat 1.7.1.", strings.join(dirs, " and ", context.temp_allocator))
	if !srmod_write(mods_dir, name, title if title != "" else name, description, entries, scales, options.about) {
		return {problem = "The mod couldn't be written into mods/: is the disk full?"}
	}
	log.infof("made the mod %s from %v: %d files that differ from the game's", name, dirs, result.changed)
	return
}

// A file a mod is made of: its path as Soldat 1 has it, where it is, and its pixels to a
// unit, as Soldat 1 sizes it (soldat_scale).
@(private = "file")
Packed :: struct {
	name:  string,
	path:  string,
	scale: f32,
}

// What of the folder `dir` goes in a mod (mod_import), each with the scale its mod.ini
// gives it: a mod of mods/, every file of the game's folders; `own`, an install's own, each
// that is neither 1.7.1's as it came nor Classic's, its game's folders alone looked
// through. With the temp allocator.
@(private = "file")
scan :: proc(install, dir: string, classic: Mod, stock: ^map[string]Stock_File, own: bool, default_scale: f32 = 1) -> (files: []Packed, ok: bool) {
	root := dir if own else folder_root(dir)
	at := install_path(install, root) // where its files are in the install, as the stock list has them
	config := soldat_config(root, default_scale)
	packed := make([dynamic]Packed, context.temp_allocator)
	// Classic's folders, read once for every file; kept in an arena of their own, as the
	// temp allocator's is let go of file by file
	arena: virtual.Arena
	_ = virtual.arena_init_growing(&arena)
	defer virtual.arena_destroy(&arena)
	listings := new(utils.Dir_Listings, virtual.arena_allocator(&arena))
	listings^ = make(utils.Dir_Listings, virtual.arena_allocator(&arena))
	for file in files_below(root, own) {
		top := file[:max(strings.index_byte(file, '/'), 0)]
		if top == "" || !is_root_name(top, true) do continue
		path := utils.temp_path(root, file)
		// a mod of mods/ is the player's whole: all of it goes in. The install's own
		// folders are 1.7.1's, but for what the player put over them
		if !own || keep(stock, classic, path, file, at, listings) do append(&packed, Packed{file, path, soldat_scale(&config, file)})
	}
	return packed[:], true

	// Whether the file goes in: not 1.7.1's own, and not Classic's. What it reads and
	// decodes is let go of as it is weighed, so a mod of many files takes no more.
	keep :: proc(stock: ^map[string]Stock_File, classic: Mod, path, file, at: string, listings: ^utils.Dir_Listings) -> bool {
		mark := runtime.default_temp_allocator_temp_begin()
		defer runtime.default_temp_allocator_temp_end(mark)
		if is_stock(stock, path, file, at) do return false
		data := utils.read_file(path, context.temp_allocator) or_return
		return differs(classic, data, file, listings)
	}
}

// A Soldat 1 folder's mod.ini, as Soldat 1 reads it: its scales 1 where it doesn't say,
// as a mod without one is; with the temp allocator.
@(private = "file")
soldat_config :: proc(root: string, default_scale: f32 = 1) -> Mod_Config {
	layer := Mod_Layer{dir = root}
	config, _ := mod_config_read(&layer, context.temp_allocator, default_scale = default_scale)
	return config
}

// The scale Soldat 1 draws the image at `path` (below the mod.ini's folder) at: its own,
// else its folder's, else the default (GetImageScale).
@(private = "file")
soldat_scale :: proc(config: ^Mod_Config, path: string) -> f32 {
	key := strings.to_lower(path, context.temp_allocator)
	if value, found := config.scale.paths[key]; found && value > 0 do return value
	if slash := strings.last_index_byte(key, '/'); slash >= 0 {
		if value, found := config.scale.paths[key[:slash]]; found && value > 0 do return value
	}
	return config.scale.default if config.scale.default > 0 else 1
}

// The part whose pivots.json pins the image of Soldat 1's id `id`: the weapons' for the
// guns and the grenades on the belt, the soldier's for the rest.
pivot_part :: proc(id: string) -> Part {
	lower := strings.to_lower(id, context.temp_allocator)
	for prefix in ([]string{"primary_", "secondary_", "frag_grenade", "cluster_grenade"}) {
		if strings.has_prefix(lower, prefix) do return .Weapons
	}
	return .Soldier
}

// A Soldat 1 file of a mod as it goes in a mod: where (by part), its bytes, and an
// image's pixels to a unit. An image keyed as the game keys it, its see-through made
// alpha, a PNG, its pixels as they were: at the scale Soldat 1 drew it at, which its mod
// then says (srmod_write); an edge's texture at 1, as Soldat 1 drew those; the rest, whose
// size the map sets, at none (0). A sound as it is. False for anything no part a mod may
// have holds (the scenery is Classic's alone).
@(private = "file")
import_file :: proc(f: Packed) -> (dest: string, data: []byte, scale: f32, ok: bool) {
	slash := strings.last_index_byte(f.name, '/')
	dir, file := f.name[:max(slash, 0)], f.name[slash + 1:]
	part, in_part := mod_part_of(dir, file) or_return
	if part not_in MOD_PARTS do return // the scenery: Classic's alone
	base := utils.temp_path(PART_NAMES[part], in_part) if in_part != "" else PART_NAMES[part]
	bytes := utils.read_file(f.path, context.temp_allocator) or_return
	extension := strings.to_lower(filepath.ext(file), context.temp_allocator)
	switch extension {
	case ".png", ".bmp", ".jpg", ".gif", ".tga":
		texture := texture_decode(bytes, image_key(f.name), context.temp_allocator) or_return
		switch {
		case part == .Textures && strings.has_prefix(strings.to_lower(in_part, context.temp_allocator), "edges"):
			scale = 1
		case part == .Textures, part == .Scenery, part == .Objects && in_part == "textures":
		case:
			scale = f.scale
		}
		return utils.temp_path(base, strings.concatenate({filepath.stem(file), ".png"}, context.temp_allocator)), texture_png(texture), scale, true
	case ".wav", ".ogg", ".mp3":
		if part != .Sounds do return
		return utils.temp_path(base, file), bytes, 0, true
	case ".ttf", ".otf":
		if part != .Fonts do return
		return utils.temp_path(base, file), bytes, 0, true
	case ".ini":
		// txt/font.ini: the fonts' own, which the fonts part holds; no other of txt/
		if part != .Fonts || !strings.equal_fold(file, "font.ini") do return
		return utils.temp_path(base, file), bytes, 0, true
	}
	return
}

// What the game keys out of the Soldat 1 image at `path`: black for the smoke, the spawn's
// spark and the parachute's rope; nothing for a map's polygon texture; green for the rest.
@(private = "file")
image_key :: proc(path: string) -> Maybe(utils.Rgba) {
	lower := strings.to_lower(path, context.temp_allocator)
	stem := strings.trim_suffix(lower, filepath.ext(lower))
	switch stem {
	case "sparks-gfx/minismoke", "sparks-gfx/bigsmoke", "sparks-gfx/spawnspark", "gostek-gfx/para-rope":
		return BLACK_KEY
	}
	if strings.has_prefix(stem, "sparks-gfx/explosion/smoke") do return BLACK_KEY
	if strings.has_prefix(lower, "textures/") && !strings.has_prefix(lower, "textures/edges/") && !strings.has_prefix(lower, "textures/objects/") do return nil
	return COLOR_KEY
}

// A mod written, the folder `mods_dir`/`name`: its mod.json, of the parts `entries` have
// (by their paths in it), and them; its images at `scales`, each by its path, as few as
// say them (scales_compact), SRMOD_SCALE those it hasn't. Written into a hidden folder
// first, which the game passes over, then moved into its place whole, over a mod of its
// name already there (the HUD editor saving over its own). False, logged, if it can't be.
srmod_write :: proc(mods_dir, name, title, description: string, entries: map[string][]byte, scales: map[string]f32 = nil, about := Srmod_About{}) -> bool {
	parts := make([dynamic]string, context.temp_allocator)
	for part in Part {
		for dest in entries {
			if strings.has_prefix(dest, strings.concatenate({PART_NAMES[part], "/"}, context.temp_allocator)) {
				append(&parts, PART_NAMES[part])
				break
			}
		}
	}
	// every image's scale, SRMOD_SCALE where none is given, so the most of them is the mod's
	per_image := make(map[string]f32, context.temp_allocator)
	for dest in entries {
		lower := strings.to_lower(dest, context.temp_allocator)
		// the maps' polygon textures and the flags' cloth: their size the map's, no scale's
		if (strings.has_prefix(lower, "textures/") && !strings.has_prefix(lower, "textures/edges/")) || strings.has_prefix(lower, "objects/textures/") do continue
		switch filepath.ext(lower) {
		case ".png", ".bmp", ".jpg", ".gif", ".tga":
			per_image[dest] = scales[dest] or_else SRMOD_SCALE
		}
	}
	scale, compact := scales_compact(per_image)
	info := Srmod_Info {
		format      = SRMOD_FORMAT,
		name        = name,
		title       = title,
		version     = about.version if version_ok(about.version) else "1.0.0",
		author      = about.author,
		description = description,
		licence     = about.licence,
		source      = about.source,
		parts       = parts[:],
		scale       = scale,
		scales      = compact,
	}
	options := json.Marshal_Options{spec = .JSON, pretty = true, use_spaces = true, spaces = 2}
	text, err := json.marshal(info, options, context.temp_allocator)
	if err != nil do return false

	path := utils.temp_path(mods_dir, name)
	partial := utils.temp_path(mods_dir, strings.concatenate({".", name, ".part"}, context.temp_allocator))
	os.remove_all(partial)
	written := os.make_directory_all(partial) == nil && os.write_entire_file(utils.temp_path(partial, SRMOD_INFO_FILE), text) == nil
	for dest in entries {
		if !written do break
		if !zip_name_safe(dest) {
			log.errorf("%s: %s is no path within a mod", name, dest)
			written = false
			break
		}
		at := utils.temp_path(partial, dest)
		written = os.make_directory_all(filepath.dir(at)) == nil && os.write_entire_file(at, entries[dest]) == nil
	}
	if written && os.is_dir(path) do written = os.remove_all(path) == nil
	if !written || os.rename(partial, path) != nil {
		os.remove_all(partial)
		log.errorf("could not write %s", path)
		return false
	}
	return true
}

// Where the folder `dir` is in the Soldat install `install`, in lower case, with its
// slash ("mods/classic/"); "" for the install itself, or a folder not in it.
@(private = "file")
install_path :: proc(install, dir: string) -> string {
	slashed :: proc(path: string) -> string {
		full, err := os.get_absolute_path(path, context.temp_allocator)
		if err != nil do full = path
		full, _ = strings.replace_all(full, "\\", "/", context.temp_allocator)
		return strings.to_lower(strings.trim_right(full, "/"), context.temp_allocator)
	}
	root, full := slashed(install), slashed(dir)
	if !strings.has_prefix(full, root) do return ""
	below := strings.trim(full[len(root):], "/")
	if below == "" do return ""
	return strings.concatenate({below, "/"}, context.temp_allocator)
}

// How many of the files are art or sounds a mod may have: not the fonts, the scenery or
// mod.ini.
@(private = "file")
changed_of :: proc(files: []Packed) -> (n: int) {
	for f in files {
		slash := strings.last_index_byte(f.name, '/')
		top := strings.to_lower(f.name[:max(strings.index_byte(f.name, '/'), 0)], context.temp_allocator)
		if top == "" || top == "txt" || top == "fonts" do continue
		part, _, ok := mod_part_of(f.name[:max(slash, 0)], f.name[slash + 1:])
		if ok && part in MOD_PARTS do n += 1 // not the scenery, Classic's alone
	}
	return
}

// The mod Soldat was last played with: soldat.ini's Last_Mod; empty for none.
@(private = "file")
last_mod :: proc(root: string) -> string {
	ini := utils.temp_path(root, "soldat.ini")
	if !utils.file_exists(ini) do return ""
	text, read := utils.read_file(ini, context.temp_allocator)
	if !read do return ""
	rest := string(text)
	for line in strings.split_lines_iterator(&rest) {
		key, _, value := strings.partition(line, "=")
		if strings.equal_fold(strings.trim_space(key), "Last_Mod") do return strings.trim_space(value)
	}
	return ""
}

// Whether the file `file` (its bytes `mine`) is one of Classic's, and isn't the same: an
// image whose pixels differ, else bytes that do. A file Classic hasn't isn't one: the
// game never asks for it. Images of other sizes differ without being decoded.
@(private = "file")
differs :: proc(classic: Mod, mine: []byte, file: string, listings: ^utils.Dir_Listings = nil) -> bool {
	slash := strings.last_index_byte(file, '/')
	dir, name := file[:max(slash, 0)], file[slash + 1:]
	extension := strings.to_lower(filepath.ext(name), context.temp_allocator)
	theirs: Mod_File
	found: bool
	image := extension == ".png" || extension == ".bmp" || extension == ".jpg" || extension == ".gif" || extension == ".tga"
	switch {
	case image:
		theirs, found = mod_image(classic, dir, name, listings)
	case strings.has_prefix(strings.to_lower(file, context.temp_allocator), "sfx/") && (extension == ".wav" || extension == ".ogg" || extension == ".mp3"):
		theirs, found = sound_file(classic, file[len("sfx/"):])
	case:
		theirs, found = mod_file(classic, file)
	}
	if !found do return false
	classics := mod_read(theirs, context.temp_allocator) or_return
	if slice.equal(mine, classics) do return false
	if image {
		wa, ha, ca, wb, hb, cb: c.int
		if stbi.info_from_memory(raw_data(mine), c.int(len(mine)), &wa, &ha, &ca) != 0 && stbi.info_from_memory(raw_data(classics), c.int(len(classics)), &wb, &hb, &cb) != 0 {
			if wa != wb || ha != hb do return true
		}
	}
	a, decoded_a := texture_decode(mine, COLOR_KEY, context.temp_allocator)
	b, decoded_b := texture_decode(classics, COLOR_KEY, context.temp_allocator)
	if !decoded_a || !decoded_b do return true
	return a.width != b.width || a.height != b.height || !same_pixels(a.pixels, b.pixels)
}

// Whether two images' pixels are the same as they are drawn: the green keyed out, as the
// game keys it, and any see-through pixel the same as another, whatever colour it hides.
@(private = "file")
same_pixels :: proc(a, b: []utils.Rgba) -> bool {
	for pa, i in a {
		pb := b[i]
		if pa.a == 0 && pb.a == 0 do continue
		if pa != pb do return false
	}
	return true
}

@(private = "file")
Stock_File :: struct {
	size: int,
	crc:  u32,
}

// SOLDAT_STOCK's files, by their path in lower case; none if it can't be read. With the
// temp allocator.
@(private = "file")
stock_load :: proc() -> map[string]Stock_File {
	stock := make(map[string]Stock_File, 2048, context.temp_allocator)
	if !utils.file_exists(SOLDAT_STOCK) do return stock // not beside the game: none
	text, read := utils.read_file(SOLDAT_STOCK, context.temp_allocator)
	if !read do return stock
	rest := string(text)
	for line in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(line, "//") do continue
		// its size, its CRC, and the rest its path, which may have spaces ("soldat style")
		size_text, _, after := strings.partition(strings.trim_space(line), " ")
		crc_text, _, path := strings.partition(after, " ")
		if path == "" do continue
		size, size_ok := strconv.parse_int(size_text)
		crc, crc_ok := strconv.parse_u64_of_base(crc_text, 16)
		if size_ok && crc_ok do stock[path] = {size, u32(crc)}
	}
	return stock
}

// Whether the file at `path`, `file` in its folder, which is `at` in its install ("", or
// "mods/classic/"), is Soldat 1.7.1's own, as it came: its size, then (only if that
// matches) its CRC.
@(private = "file")
is_stock :: proc(stock: ^map[string]Stock_File, path, file, at: string) -> bool {
	known := stock[strings.to_lower(strings.concatenate({at, file}, context.temp_allocator), context.temp_allocator)] or_return
	info, err := os.stat(path, context.temp_allocator)
	if err != nil || int(info.size) != known.size do return false
	data := utils.read_file(path, context.temp_allocator) or_return
	return hash.crc32(data) == known.crc
}

// Every file below `root`, by its path from it with forward slashes; `own`, only in its
// game's folders (gostek-gfx/, sfx/...), an install's maps/, demos/ and mods/ passed
// over. With the temp allocator.
@(private)
files_below :: proc(root: string, own := false) -> []string {
	files := make([dynamic]string, context.temp_allocator)
	walk :: proc(files: ^[dynamic]string, root, below: string) {
		entries, err := os.read_all_directory_by_path(utils.temp_path(root, below) if below != "" else root, context.temp_allocator)
		if err != nil do return
		for entry in entries {
			path := utils.temp_path(below, entry.name) if below != "" else entry.name
			if entry.type == .Directory {
				walk(files, root, path)
			} else {
				append(files, path)
			}
		}
	}
	if !own {
		walk(&files, root, "")
		return files[:]
	}
	entries, _ := os.read_all_directory_by_path(root, context.temp_allocator)
	for entry in entries do if entry.type == .Directory && is_root_name(entry.name, true) do walk(&files, root, entry.name)
	return files[:]
}

// The files at `root` itself, not in its folders.
@(private = "file")
files_at :: proc(root: string) -> []string {
	files := make([dynamic]string, context.temp_allocator)
	entries, _ := os.read_all_directory_by_path(root, context.temp_allocator)
	for entry in entries do if entry.type != .Directory do append(&files, entry.name)
	return files[:]
}

// The libraries Steam keeps games in, besides its own folder: libraryfolders.vdf's
// "path"s.
@(private = "file")
steam_libraries :: proc(steam: string) -> []string {
	libraries := make([dynamic]string, context.temp_allocator)
	vdf := utils.temp_path(steam, "steamapps", "libraryfolders.vdf")
	if !utils.file_exists(vdf) do return nil
	text, read := utils.read_file(vdf, context.temp_allocator)
	if !read do return nil
	rest := string(text)
	for line in strings.split_lines_iterator(&rest) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 2 || fields[0] != `"path"` do continue
		path := strings.trim(strings.join(fields[1:], " ", context.temp_allocator), `"`)
		path, _ = strings.replace_all(path, `\\`, "/", context.temp_allocator)
		append(&libraries, path)
	}
	return libraries[:]
}

// Whether every file of the folder `dir` is Soldat 1.7.1's own as it came, by where the
// folder is in its install: one of the custom interfaces it ships with, untouched.
@(private)
folder_is_stock :: proc(install, dir: string) -> bool {
	stock := stock_load()
	at := install_path(install, dir)
	files := files_below(dir)
	if len(files) == 0 do return false
	for file in files do if !is_stock(&stock, utils.temp_path(dir, file), file, at) do return false
	return true
}

// Each folder of the Steam library `library`'s steamapps/common named for Soldat, in any
// case ("Soldat"), added to `candidates`.
@(private = "file")
steam_soldats :: proc(candidates: ^[dynamic]string, library: string) {
	common := utils.temp_path(library, "steamapps", "common")
	entries, err := os.read_all_directory_by_path(common, context.temp_allocator)
	if err != nil do return
	for entry in entries {
		if entry.type == .Directory && strings.contains(strings.to_lower(entry.name, context.temp_allocator), "soldat") {
			append(candidates, utils.temp_path(common, entry.name))
		}
	}
}

// The Soldat 1 files `files` as a mod's entries, by where each goes in it (import_file),
// those of `parts` alone: a .png before a .bmp of its name, as Soldat 1 takes it; each
// image's scale, by the same path, put in `scales`. And how many there are. With the temp
// allocator.
@(private = "file")
entries_of :: proc(files: []Packed, parts: Parts, scales: ^map[string]f32) -> (entries: map[string][]byte, count: int) {
	entries = make(map[string][]byte, 256, context.temp_allocator)
	from_png := make(map[string]bool, 256, context.temp_allocator)
	for f in files {
		dest, data, scale, ok := import_file(f)
		if !ok do continue
		part, _ := part_named(dest[:max(strings.index_byte(dest, '/'), 0)])
		if part not_in parts do continue
		png := strings.equal_fold(filepath.ext(f.name), ".png")
		if from_png[dest] && !png do continue
		if dest not_in entries do count += 1
		entries[dest] = data
		from_png[dest] = png
		if scale > 0 do scales[dest] = scale
		else do delete_key(scales, dest)
	}
	return
}

// The custom interface `title` of `from` (a custom-interfaces/ of the install at `root`,
// or of one of its mods) made the .srmod of its name (mod_name_from) in `mods_dir`, its
// hud and its icons; and under them the player's own changes to the install's HUD and
// icons that it hasn't of its own. Its name; or why it couldn't be made.
interface_install :: proc(root, from, title, mods_dir: string, classic: Mod) -> (name, problem: string) {
	name = mod_name_from(title)
	if name == "" do return "", "That interface's name can't be a mod's."
	if mod_exists(mods_dir, name) do return name, "There is a mod by that name already."
	stock := stock_load()
	own, _ := scan(root, root, classic, &stock, own = true)
	scales := make(map[string]f32, context.temp_allocator)
	entries, _ := entries_of(own, {.Hud, .Icons}, &scales)
	if !interface_entries(from, title, &entries, &scales) do return name, "That interface has no setup.sif to read."
	if !srmod_write(mods_dir, name, fmt.tprintf("%s interface", title), fmt.tprintf("Soldat 1's custom interface %s, its HUD's layout and pictures.", title), entries, scales) {
		return name, "The mod couldn't be written into mods/: is the disk full?"
	}
	return name, ""
}
