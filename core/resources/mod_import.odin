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
// put over the game's own, or in a mod of its mods/, made mods/<name>.srmod
// (docs/srmod.md, "Bringing mods in"). What goes in is what they changed: a file of
// Classic's names that is neither 1.7.1's own as it came (SOLDAT_STOCK, by its size and
// CRC-32: Classic's art is redrawn, and the original's would replace it) nor the same as
// Classic's (an image by its pixels as the game draws it, so the same picture as a .bmp
// is the same), each laid out by part and its images brought to SRMOD_SCALE; and the
// pivots its mod.ini changes. The rest is Classic's already. Its custom interfaces are
// made mods of their own (interfaces_import).
//
// The install is found where Soldat is usually put (soldat_installs), or from any folder
// of it (soldat_root); what a mod can be made from in it is its own folders, which a
// player may have put their art over, and each mod of its mods/ (soldat_sources), a mod
// over its own folders, as Soldat wears it.

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
		// the game itself, not a folder that only holds its art, nor this game's install
		if !soldat_is_install(dir) || !(utils.file_exists(utils.temp_path(dir, "soldat.exe")) || utils.file_exists(utils.temp_path(dir, "soldat.ini"))) do continue
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

// What making a mod found: how many of its files change something of the game's.
Import_Result :: struct {
	changed: int,    // its art and sounds that differ from Classic's
	problem: string, // why no mod was made; empty if one was
}

// The Soldat install a folder is of, or in (C:\Soldat, C:\Soldat\gostek-gfx,
// C:\Soldat\mods\Foo): the first folder up from it, four at most, with soldat.exe or
// soldat.ini; and the mod of its mods/ the folder is in, if it is in one. With
// `allocator`. False if it isn't in one.
soldat_root :: proc(path: string, allocator := context.allocator) -> (root, mod: string, ok: bool) {
	context.allocator = context.temp_allocator
	full, err := os.get_absolute_path(strings.trim_space(path), context.temp_allocator)
	if err != nil do return
	full, _ = strings.replace_all(full, "\\", "/", context.temp_allocator)
	full = strings.trim_right(full, "/")
	dir := full
	for _ in 0 ..= 4 {
		if is_soldat(dir) {
			below := strings.trim_prefix(strings.trim_prefix(full, dir), "/")
			if strings.has_prefix(strings.to_lower(below, context.temp_allocator), "mods/") {
				rest := below[len("mods/"):]
				mod = rest[:strings.index_byte(rest, '/')] if strings.index_byte(rest, '/') >= 0 else rest
			}
			return strings.clone(dir, allocator), strings.clone(mod, allocator), true
		}
		up := filepath.dir(dir)
		if up == dir || up == "" || up == "." do break
		dir, _ = strings.replace_all(up, "\\", "/", context.temp_allocator)
	}
	return
}

// Whether `dir` is an original Soldat's install: soldat.exe or soldat.ini in it.
@(private = "file")
is_soldat :: proc(dir: string) -> bool {
	return utils.file_exists(utils.temp_path(dir, "soldat.exe")) || utils.file_exists(utils.temp_path(dir, "soldat.ini"))
}

// One place in a Soldat install a mod can be made from: its own folders, which a player
// may have put their art and sounds over, or a mod of its mods/.
Soldat_Source :: struct {
	name:    string, // the mod's, in mods/; "" for the install's own folders
	dir:     string,
	changed: int,    // its art and sounds that differ from the game's
	in_use:  bool,   // the mod Soldat was last played with (soldat.ini's Last_Mod)
}

// What a mod can be made from in the install at `root`: its own folders, then each mod
// of its mods/ that has any art or sounds, by name; each looked through for what it
// changes. With `allocator`; free with soldat_sources_destroy.
soldat_sources :: proc(root: string, classic: Mod, allocator := context.allocator) -> []Soldat_Source {
	sources := make([dynamic]Soldat_Source, allocator)
	stock := stock_load()
	files, _ := scan(root, classic, &stock, own = true)
	append(&sources, Soldat_Source{dir = strings.clone(root, allocator), changed = changed_of(files)})
	last := last_mod(root)
	mods_dir := utils.temp_path(root, "mods")
	entries, _ := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)})
	for entry in entries {
		if entry.type != .Directory do continue
		dir := utils.temp_path(mods_dir, entry.name)
		if !soldat_is_install(dir) do continue
		mod_files, _ := scan(dir, classic, &stock, own = false)
		append(&sources, Soldat_Source {
			name    = strings.clone(entry.name, allocator),
			dir     = strings.clone(dir, allocator),
			changed = changed_of(mod_files),
			in_use  = last != "" && strings.equal_fold(last, entry.name),
		})
	}
	return sources[:]
}

soldat_sources_destroy :: proc(sources: []Soldat_Source, allocator := context.allocator) {
	for s in sources {
		delete(s.name, allocator)
		delete(s.dir, allocator)
	}
	delete(sources, allocator)
}

// The mod `name` made in `mods_dir`, a .srmod, from the folders `dirs` of an original
// Soldat install, each over the last as Soldat wears a mod over its own folders (the
// install's own first, then a mod of its mods/): each file of their art and sounds that
// is one of Classic's, neither 1.7.1's own as it came nor the same as Classic's, laid out
// by part (MOD_PATHS), each image keyed as the game keys it, its see-through made alpha,
// and brought from the scale Soldat 1 drew it at to SRMOD_SCALE (import_image); and the
// soldier's and the weapons' pivots, from their mod.inis' [GOSTEK], where they differ
// from Classic's. A folder that is the install itself is looked through for its own
// folders alone, not its mods/ or maps/.
mod_import :: proc(dirs: []string, mods_dir, name: string, classic: Mod) -> (result: Import_Result) {
	if problem := mod_name_problem(mods_dir, name); problem != "" do return {problem = problem}
	if !srmod_name_ok(name) do return {problem = "A mod's name is letters, digits, - and _, 32 at most."}
	if len(dirs) == 0 do return {problem = "Pick what to make the mod from."}
	stock := stock_load()
	merged := make(map[string]Packed, 256, context.temp_allocator)
	anchors := make(map[string]f32, context.temp_allocator)
	for dir in dirs {
		if !soldat_is_install(dir) do return {problem = "That isn't a Soldat folder: there is no gostek-gfx, weapons-gfx or the like in it."}
		own := is_soldat(dir)
		files, _ := scan(dir, classic, &stock, own)
		for f in files do merged[strings.to_lower(f.name, context.temp_allocator)] = f
		// its mod.ini's pivots, unless it is 1.7.1's own as it came: those are no player's
		root := dir if own else folder_root(dir)
		if !utils.file_exists(utils.temp_path(root, MOD_CONFIG_FILE)) || is_stock(&stock, utils.temp_path(root, MOD_CONFIG_FILE), MOD_CONFIG_FILE, install_path(root)) do continue
		config := soldat_config(root)
		for key, value in config.anchors do anchors[key] = value
	}

	// the files, by where each goes in the mod; a .png before a .bmp of its name, as
	// Soldat 1 takes it
	entries := make(map[string][]byte, 256, context.temp_allocator)
	from_png := make(map[string]bool, 256, context.temp_allocator)
	for _, f in merged {
		dest, data, ok := import_file(f)
		if !ok do continue
		png := strings.equal_fold(filepath.ext(f.name), ".png")
		if from_png[dest] && !png do continue
		entries[dest] = data
		from_png[dest] = png
		result.changed += 1
	}

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
	if !srmod_write(mods_dir, name, name, fmt.tprintf("Made from %s, in Soldat 1.7.1.", strings.join(dirs, " and ", context.temp_allocator)), entries) {
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
scan :: proc(dir: string, classic: Mod, stock: ^map[string]Stock_File, own: bool) -> (files: []Packed, ok: bool) {
	root := dir if own else folder_root(dir)
	at := install_path(root) // where its files are in the install, as the stock list has them
	config := soldat_config(root)
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
soldat_config :: proc(root: string) -> Mod_Config {
	layer := Mod_Layer{dir = root}
	config, _ := mod_config_read(&layer, context.temp_allocator, default_scale = 1)
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

// A Soldat 1 file of a mod as it goes in a .srmod: where (by part), and its bytes. An
// image keyed as the game keys it, its see-through made alpha, a PNG, and as big as it
// should be at SRMOD_SCALE: an image whose size is its own from the scale Soldat 1 drew
// it at; an edge's texture from 1, as Soldat 1 drew those; the rest, whose size the map
// sets, as it is. A sound as it is. False for anything no part a mod may have holds (the
// scenery is Classic's alone).
@(private = "file")
import_file :: proc(f: Packed) -> (dest: string, data: []byte, ok: bool) {
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
		by: f32 = 1
		switch {
		case part == .Textures && strings.has_prefix(strings.to_lower(in_part, context.temp_allocator), "edges"):
			by = SRMOD_SCALE
		case part == .Textures, part == .Scenery, part == .Objects && in_part == "textures":
		case:
			by = SRMOD_SCALE / f.scale
		}
		texture = texture_rescale(texture, by)
		return utils.temp_path(base, strings.concatenate({filepath.stem(file), ".png"}, context.temp_allocator)), texture_png(texture), true
	case ".wav", ".ogg", ".mp3":
		if part != .Sounds do return
		return utils.temp_path(base, file), bytes, true
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

// A .srmod written, `mods_dir`/`name`.srmod: its mod.json, of the parts `entries` have
// (by their paths in it), and them. False, logged, if it can't be.
srmod_write :: proc(mods_dir, name, title, description: string, entries: map[string][]byte) -> bool {
	parts := make([dynamic]string, context.temp_allocator)
	for part in Part {
		for dest in entries {
			if strings.has_prefix(dest, strings.concatenate({PART_NAMES[part], "/"}, context.temp_allocator)) {
				append(&parts, PART_NAMES[part])
				break
			}
		}
	}
	info := Srmod_Info{format = SRMOD_FORMAT, name = name, title = title, version = "1.0.0", author = "", description = description, parts = parts[:]}
	options := json.Marshal_Options{spec = .JSON, pretty = true, use_spaces = true, spaces = 2}
	text, err := json.marshal(info, options, context.temp_allocator)
	if err != nil do return false

	os.make_directory_all(mods_dir)
	path := utils.temp_path(mods_dir, strings.concatenate({name, SRMOD_EXTENSION}, context.temp_allocator))
	partial := utils.temp_path(mods_dir, strings.concatenate({".", name, ".part"}, context.temp_allocator))
	w: utils.Zip_Writer
	if !utils.zip_write_begin(&w, partial) do return false
	utils.zip_write_add(&w, SRMOD_INFO_FILE, text)
	names := make([dynamic]string, context.temp_allocator)
	for dest in entries do append(&names, dest)
	slice.sort(names[:])
	for dest in names do utils.zip_write_add(&w, dest, entries[dest])
	if !utils.zip_write_end(&w) || os.rename(partial, path) != nil {
		os.remove(partial)
		log.errorf("could not write %s", path)
		return false
	}
	return true
}

// Where the folder `dir` is in the Soldat install it is in, in lower case, with its slash
// ("mods/classic/"); "" for the install itself, or a folder in none.
@(private = "file")
install_path :: proc(dir: string) -> string {
	root, _, found := soldat_root(dir, context.temp_allocator)
	if !found do return ""
	full, err := os.get_absolute_path(dir, context.temp_allocator)
	if err != nil do return ""
	full, _ = strings.replace_all(full, "\\", "/", context.temp_allocator)
	below := strings.trim(strings.trim_prefix(strings.trim_right(full, "/"), root), "/")
	if below == "" do return ""
	return strings.to_lower(strings.concatenate({below, "/"}, context.temp_allocator), context.temp_allocator)
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
	text, read := utils.read_file(utils.temp_path(root, "soldat.ini"), context.temp_allocator)
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
@(private = "file")
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
folder_is_stock :: proc(dir: string) -> bool {
	stock := stock_load()
	at := install_path(dir)
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
