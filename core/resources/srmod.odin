package resources

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

import "../utils"

// Soldat Reloaded's mods (docs/srmod.md): a mod is one file, <name>.srmod, a zip; or,
// being made, its folder, mods/<name>/, laid out the same. At its root, mod.json says
// what it is; each of its parts is a folder there (soldier/, weapons/, hud/, ...). The
// player wears each part from a mod of its own (Worn): a file the chosen mod's part
// hasn't is Classic's, which has them all. Every image is 4.5 pixels to a unit: there
// is no mod.ini.

SRMOD_EXTENSION :: ".srmod"
SRMOD_INFO_FILE :: "mod.json"
SRMOD_FORMAT :: 1 // of the layout, mod.json's `format`: a mod of another is refused
SRMOD_NAME_MAX :: 32
SRMOD_TITLE_MAX :: 48

// What a mod may change, each a folder at its root.
Part :: enum {
	Soldier,  // the soldier's parts and their pivots
	Weapons,  // the guns, held and dropped, their icons, and their pivots
	Effects,  // blood, smoke, sparks, explosions, flames
	Objects,  // things on the map, the flags' cloth, the kits
	Hud,      // layout.json and the pictures it places
	Icons,    // the rest of the HUD's and the menus' art
	Sounds,
	Textures, // the maps' polygon textures, and their edges'
	Scenery,  // the maps' props: Classic's alone, as Soldat 1's, no mod's (MOD_PARTS)
	Fonts,    // the HUD's fonts, and fonts.json
}
Parts :: bit_set[Part]

// The parts a mod may have: all but the scenery, which is Classic's alone, as the maps'
// art Soldat 1 never let a mod change.
MOD_PARTS :: Parts{.Soldier, .Weapons, .Effects, .Objects, .Hud, .Icons, .Sounds, .Textures, .Fonts}

// Each part's folder, and its name in mod.json and the config.
@(rodata)
PART_NAMES := [Part]string {
	.Soldier  = "soldier",
	.Weapons  = "weapons",
	.Effects  = "effects",
	.Objects  = "objects",
	.Hud      = "hud",
	.Icons    = "icons",
	.Sounds   = "sounds",
	.Textures = "textures",
	.Scenery  = "scenery",
	.Fonts    = "fonts",
}

// The mod each part is worn from, by its name, "" for Classic's: the client config's
// graphics.parts.
Part_Choice :: struct {
	soldier:  string,
	weapons:  string,
	effects:  string,
	objects:  string,
	hud:      string,
	icons:    string,
	sounds:   string,
	textures: string,
	fonts:    string,
}

// The choice's mod for `part`; nil for one no mod may have (MOD_PARTS).
part_choice_of :: proc(choice: ^Part_Choice, part: Part) -> ^string {
	switch part {
	case .Soldier:  return &choice.soldier
	case .Weapons:  return &choice.weapons
	case .Effects:  return &choice.effects
	case .Objects:  return &choice.objects
	case .Hud:      return &choice.hud
	case .Icons:    return &choice.icons
	case .Sounds:   return &choice.sounds
	case .Textures: return &choice.textures
	case .Scenery:  return nil // Classic's alone
	case .Fonts:    return &choice.fonts
	}
	return nil
}

// The choice, part by part.
part_choices :: proc(choice: Part_Choice) -> (by_part: [Part]string) {
	choice := choice
	for part in MOD_PARTS do by_part[part] = part_choice_of(&choice, part)^
	return
}

// The part named `name` (as PART_NAMES has it, in any case).
part_named :: proc(name: string) -> (part: Part, ok: bool) {
	for n, p in PART_NAMES {
		if strings.equal_fold(n, name) do return p, true
	}
	return
}

// mod.json: what a mod says it is.
Srmod_Info :: struct {
	format:      int,
	name:        string, // its file's: letters, digits, - and _, SRMOD_NAME_MAX at most
	title:       string, // what it is shown as, spaces and all; `name` if none
	version:     string, // three numbers, 1.0.0
	author:      string,
	description: string,
	licence:     string,
	source:      string,
	parts:       []string, // what it changes, by PART_NAMES
}

// A mod open: what it says, the parts it has, and its files.
Srmod :: struct {
	info:     Srmod_Info,
	parts:    Parts,     // the parts it has: its folders that are parts
	pack:     Mod_Layer, // its folder or its zip, its root where its mod.json is
	packed:   bool,      // a .srmod, installed or handed over, worn as it is; else a folder, being made, its mod.json the player's to edit
	problems: []string,  // what is wrong with it, that it is worn all the same (a part listed without its folder): the allocator's
}

// The mod at `path`, its folder or its .srmod. Not one, and why (with the temp
// allocator), if it has no mod.json that can be read, or of another format, or names
// itself wrongly; with `classic`, Classic, which alone has its name. Free with srmod_close.
srmod_open :: proc(path: string, allocator := context.allocator, classic := false) -> (mod: Srmod, problem: string, ok: bool) {
	context.allocator = allocator
	found: bool
	if mod.pack, found = pack_open(path); !found do return {}, "not a mod: it has no mod.json", false
	defer if !ok do srmod_close(&mod)

	file, has := layer_file(&mod.pack, 0, SRMOD_INFO_FILE)
	if !has do return mod, "not a mod: it has no mod.json", false
	text, read := mod_read(file, context.temp_allocator)
	if !read do return mod, "its mod.json can't be read", false
	if _, err, at := parse_json(text, .JSON); err != nil {
		return mod, fmt.tprintf("its mod.json isn't JSON, line %d", at.line), false
	}
	if err := json.unmarshal(text, &mod.info, .JSON); err != nil {
		return mod, "its mod.json says something wrongly", false
	}
	info := &mod.info
	if info.format != SRMOD_FORMAT do return mod, fmt.tprintf("a mod of format %d, which this game doesn't read", info.format), false
	if classic ? !strings.equal_fold(info.name, MOD_CLASSIC) : !srmod_name_ok(info.name) {
		return mod, "its name isn't letters, digits, - and _, 32 at most", false
	}
	mod.packed = mod.pack.archive != nil
	if strings.trim_space(info.title) == "" {
		delete(info.title)
		info.title = strings.clone(info.name)
	}
	if utf8.rune_count(info.title) > SRMOD_TITLE_MAX do return mod, "its title is longer than 48 letters", false
	if !version_ok(info.version) do return mod, "its version isn't three numbers, as 1.0.0", false

	// its parts are its folders; what mod.json says of them, checked against them
	problems := make([dynamic]string)
	listed: Parts
	for name in info.parts {
		part, known := part_named(name)
		if !known {
			append(&problems, strings.clone(fmt.tprintf("mod.json lists %q, which is no part", name)))
			continue
		}
		listed += {part}
	}
	for part in Part {
		if pack_has_folder(&mod.pack, PART_NAMES[part]) do mod.parts += {part}
	}
	// what no mod may have but Classic, said, and not worn
	if !classic {
		for part in mod.parts - MOD_PARTS {
			append(&problems, strings.clone(fmt.tprintf("its %s/ isn't worn: the %s is Classic's alone", PART_NAMES[part], PART_NAMES[part])))
		}
		listed &= MOD_PARTS
		mod.parts &= MOD_PARTS
	}
	for part in listed - mod.parts do append(&problems, strings.clone(fmt.tprintf("mod.json lists %s, but it has no %s/", PART_NAMES[part], PART_NAMES[part])))
	for part in mod.parts - listed do append(&problems, strings.clone(fmt.tprintf("it has %s/, which mod.json doesn't list", PART_NAMES[part])))
	mod.problems = problems[:]
	for p in mod.problems do log.warnf("%s: %s", path, p)
	return mod, "", true
}

srmod_close :: proc(mod: ^Srmod, allocator := context.allocator) {
	context.allocator = allocator
	info := &mod.info
	delete(info.name)
	delete(info.title)
	delete(info.version)
	delete(info.author)
	delete(info.description)
	delete(info.licence)
	delete(info.source)
	for name in info.parts do delete(name)
	delete(info.parts)
	for p in mod.problems do delete(p)
	delete(mod.problems)
	layer_close(&mod.pack)
	mod^ = {}
}

// The file at `path` in the mod's `part` ("klata.png", "team2/klata.png"), in any case.
srmod_file :: proc(mod: ^Srmod, part: Part, path: string) -> (file: Mod_File, found: bool) {
	if part not_in mod.parts do return
	return layer_file(&mod.pack, 0, strings.concatenate({PART_NAMES[part], "/", path}, context.temp_allocator))
}

// Whether `name` is one a mod may have: letters, digits, - and _, at most
// SRMOD_NAME_MAX; not Classic's.
srmod_name_ok :: proc(name: string) -> bool {
	if name == "" || len(name) > SRMOD_NAME_MAX || strings.equal_fold(name, MOD_CLASSIC) do return false
	for c in transmute([]u8)name {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
		case:
			return false
		}
	}
	return true
}

// The mods in `dir`, by name: each .srmod, and each folder with a mod.json, a folder
// before an .srmod of its name, which it hides; Classic left out. With the temp allocator.
srmods_list :: proc(dir: string) -> []string {
	names := make([dynamic]string, context.temp_allocator)
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return nil
	for entry in entries {
		name := entry.name
		if strings.has_prefix(name, ".") do continue
		if entry.type == .Directory {
			if !utils.file_exists(utils.temp_path(entry.fullpath, SRMOD_INFO_FILE)) do continue
		} else {
			if !strings.has_suffix(strings.to_lower(name, context.temp_allocator), SRMOD_EXTENSION) do continue
			name = name[:len(name) - len(SRMOD_EXTENSION)]
		}
		if strings.equal_fold(name, MOD_CLASSIC) || slice.contains(names[:], name) do continue
		append(&names, name)
	}
	slice.sort(names[:])
	return names[:]
}

// A mod as the Mods page lists it.
Srmod_Listing :: struct {
	name:        string,
	title:       string,
	version:     string,
	author:      string,
	description: string,
	parts:       Parts,
	packed:      bool,   // a .srmod; else a folder, being made
	problem:     string, // why it can't be worn, if it can't: it is listed to be deleted
}

// The mods in `dir` (srmods_list), each opened to say what it is. Free with
// srmod_listings_destroy.
srmod_listings :: proc(dir: string, allocator := context.allocator) -> []Srmod_Listing {
	listings := make([dynamic]Srmod_Listing, allocator)
	for name in srmods_list(dir) {
		path := srmod_path(dir, name)
		mod, problem, ok := srmod_open(path, context.temp_allocator)
		listing := Srmod_Listing{name = strings.clone(name, allocator), packed = !os.is_dir(path)}
		if ok {
			listing.title = strings.clone(mod.info.title, allocator)
			listing.version = strings.clone(mod.info.version, allocator)
			listing.author = strings.clone(mod.info.author, allocator)
			listing.description = strings.clone(mod.info.description, allocator)
			listing.parts = mod.parts
			srmod_close(&mod, context.temp_allocator)
		} else {
			listing.title = strings.clone(name, allocator)
			listing.problem = strings.clone(problem, allocator)
		}
		append(&listings, listing)
	}
	return listings[:]
}

srmod_listings_destroy :: proc(listings: []Srmod_Listing, allocator := context.allocator) {
	for l in listings {
		for s in ([]string{l.name, l.title, l.version, l.author, l.description, l.problem}) do delete(s, allocator)
	}
	delete(listings, allocator)
}

// Where the mod `name` in `dir` is: its folder, else its .srmod; "" if neither.
srmod_path :: proc(dir, name: string) -> string {
	folder := utils.temp_path(dir, name)
	if os.is_dir(folder) && utils.file_exists(utils.temp_path(folder, SRMOD_INFO_FILE)) do return folder
	packed := strings.concatenate({folder, SRMOD_EXTENSION}, context.temp_allocator)
	if os.is_file(packed) do return packed
	return ""
}

// ---------------------------------------------------------------------------------
// Worn: each part from its mod, Classic under them

// The mods worn: Classic, and the mod each part is chosen from, Classic's where none is.
Worn :: struct {
	classic: Srmod,
	mods:    [dynamic]Srmod,  // the mods chosen for some part, each open once
	chosen:  [Part]int,       // each part's mod in `mods`; -1 for Classic's
	pivots:  [Part]map[string][2]f32, // the soldier's and the weapons': the chosen mod's over Classic's
}

// Classic from `classic_dir`, and each part's mod named in `choice` ("" for Classic's)
// from `mods_dir`. A mod that isn't there or can't be opened, or hasn't the part, is
// passed over, logged: that part is Classic's. False if Classic can't be opened. Free with
// worn_close.
worn_make :: proc(classic_dir, mods_dir: string, choice: [Part]string, allocator := context.allocator) -> (worn: Worn, ok: bool) {
	context.allocator = allocator
	worn.mods = make([dynamic]Srmod)
	for &c in worn.chosen do c = -1
	problem: string
	worn.classic, problem, ok = srmod_open(classic_dir, classic = true)
	if !ok {
		log.errorf("Classic, %s, can't be worn: %s", classic_dir, problem)
		return
	}
	for name, part in choice {
		if name == "" || strings.equal_fold(name, MOD_CLASSIC) || part not_in MOD_PARTS do continue
		index := -1
		for &mod, i in worn.mods {
			if strings.equal_fold(mod.info.name, name) do index = i
		}
		if index < 0 {
			path := srmod_path(mods_dir, name)
			if path == "" {
				log.warnf("no mod %s in %s/: its %s is Classic's", name, mods_dir, PART_NAMES[part])
				continue
			}
			mod, why, opened := srmod_open(path)
			if !opened {
				log.warnf("%s: %s; its %s is Classic's", path, why, PART_NAMES[part])
				continue
			}
			append(&worn.mods, mod)
			index = len(worn.mods) - 1
		}
		if part not_in worn.mods[index].parts {
			log.warnf("the mod %s has no %s: Classic's is worn", name, PART_NAMES[part])
			continue
		}
		worn.chosen[part] = index
	}
	for part in ([]Part{.Soldier, .Weapons}) do worn.pivots[part] = pivots_of(&worn, part)
	return worn, true
}

worn_close :: proc(worn: ^Worn, allocator := context.allocator) {
	context.allocator = allocator
	for &mod in worn.mods do srmod_close(&mod)
	delete(worn.mods)
	srmod_close(&worn.classic)
	for &p in worn.pivots {
		for key in p do delete(key)
		delete(p)
	}
	worn^ = {}
}

// The mod `part` is worn from: its chosen mod, else Classic.
worn_mod :: proc(worn: ^Worn, part: Part) -> ^Srmod {
	if i := worn.chosen[part]; i >= 0 do return &worn.mods[i]
	return &worn.classic
}

// The file at `path` in `part`: the chosen mod's, else Classic's.
worn_file :: proc(worn: ^Worn, part: Part, path: string) -> (file: Mod_File, found: bool) {
	if i := worn.chosen[part]; i >= 0 {
		if file, found = srmod_file(&worn.mods[i], part, path); found do return
	}
	return srmod_file(&worn.classic, part, path)
}

// Where the image `id` of the soldier's or the weapons' (Soldat 1's ids: "Chest",
// "Primary_Ak74_Clip") is pinned, as fractions of its width and height: the chosen mod's,
// else Classic's; `default` where neither says.
worn_pivot :: proc(worn: ^Worn, part: Part, id: string, default: [2]f32) -> [2]f32 {
	return worn.pivots[part][strings.to_lower(id, context.temp_allocator)] or_else default
}

// ---------------------------------------------------------------------------------
// pivots.json

SRMOD_PIVOTS_FILE :: "pivots.json"

// `part`'s pivots, Classic's and then the chosen mod's over them, by their ids in lower
// case. A pivots.json that can't be read, or a value that isn't two numbers, is passed
// over, logged.
@(private = "file")
pivots_of :: proc(worn: ^Worn, part: Part) -> map[string][2]f32 {
	pivots := make(map[string][2]f32)
	pivots_over(&pivots, &worn.classic, part)
	if i := worn.chosen[part]; i >= 0 do pivots_over(&pivots, &worn.mods[i], part)
	return pivots
}

@(private = "file")
pivots_over :: proc(pivots: ^map[string][2]f32, mod: ^Srmod, part: Part) {
	file, found := srmod_file(mod, part, SRMOD_PIVOTS_FILE)
	if !found do return
	text, read := mod_read(file, context.temp_allocator)
	if !read do return
	values: map[string]json.Value
	if json.unmarshal(text, &values, .JSON, context.temp_allocator) != nil {
		log.warnf("%s: %s/%s isn't JSON: passed over", mod.info.name, PART_NAMES[part], SRMOD_PIVOTS_FILE)
		return
	}
	for id, value in values {
		pair, is_array := value.(json.Array)
		x, y: f64
		x_ok, y_ok: bool
		if is_array && len(pair) == 2 {
			x, x_ok = number(pair[0])
			y, y_ok = number(pair[1])
		}
		if !x_ok || !y_ok {
			log.warnf("%s: %s/%s: %s isn't two numbers: passed over", mod.info.name, PART_NAMES[part], SRMOD_PIVOTS_FILE, id)
			continue
		}
		key := strings.to_lower(id, context.temp_allocator)
		if had := &pivots[key]; had != nil {
			had^ = {f32(x), f32(y)}
		} else {
			pivots[strings.clone(key)] = {f32(x), f32(y)}
		}
	}

	number :: proc(v: json.Value) -> (f64, bool) {
		#partial switch n in v {
		case json.Integer: return f64(n), true
		case json.Float:   return f64(n), true
		}
		return 0, false
	}
}

// The pivots of one mod's `part`, its own alone, by id in lower case: with the temp
// allocator.
srmod_pivots :: proc(mod: ^Srmod, part: Part) -> map[string][2]f32 {
	context.allocator = context.temp_allocator
	pivots := make(map[string][2]f32)
	pivots_over(&pivots, mod, part)
	return pivots
}

// The pivots `pivots` as a pivots.json's text, by id, sorted: with the temp allocator.
pivots_text :: proc(pivots: map[string][2]f32) -> string {
	ids := make([dynamic]string, context.temp_allocator)
	for id in pivots do append(&ids, id)
	slice.sort(ids[:])
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "{\n")
	for id, i in ids {
		p := pivots[id]
		fmt.sbprintf(&b, "  %q: [%v, %v]%s\n", id, p.x, p.y, "," if i < len(ids) - 1 else "")
	}
	strings.write_string(&b, "}\n")
	return strings.to_string(b)
}

// ---------------------------------------------------------------------------------
// The pack: a folder, or a zip

// The folder or zip at `path`, its root where its mod.json is (two folders down at most).
@(private = "file")
pack_open :: proc(path: string) -> (pack: Mod_Layer, found: bool) {
	if os.is_dir(path) {
		root := marker_folder(path, SRMOD_INFO_FILE)
		if !utils.file_exists(utils.temp_path(root, SRMOD_INFO_FILE)) do return
		return {name = strings.clone(path), dir = strings.clone(root)}, true
	}
	a := archive_open_at(path, SRMOD_INFO_FILE) or_return
	return {name = strings.clone(path), archive = a}, true
}

// Whether the pack has a folder `name` at its root, with anything in it.
@(private = "file")
pack_has_folder :: proc(pack: ^Mod_Layer, name: string) -> bool {
	if a := pack.archive; a != nil {
		prefix := strings.concatenate({name, "/"}, context.temp_allocator)
		for key in a.files do if strings.has_prefix(key, prefix) && len(key) > len(prefix) do return true
		return false
	}
	entries, err := os.read_all_directory_by_path(pack.dir, context.temp_allocator)
	if err != nil do return false
	for entry in entries {
		if entry.type == .Directory && strings.equal_fold(entry.name, name) do return true
	}
	return false
}

// The zip at `path`, open, its root the shallowest folder that has `marker` (or the
// zip's own): its files keyed in lower case below it. Nil, logged, if it isn't a zip the
// game reads, or hasn't `marker`.
@(private)
archive_open_at :: proc(path, marker: string) -> (a: ^Mod_Archive, ok: bool) {
	if !os.is_file(path) do return
	a = new(Mod_Archive)
	if a.zip, ok = utils.zip_open(path); !ok {
		log.errorf("%s isn't a zip the game can read", path)
		free(a)
		return nil, false
	}
	a.path = strings.clone(path)
	depth := max(int)
	for zip_name in a.zip.entries {
		lower := strings.to_lower(zip_name, context.temp_allocator)
		if !strings.has_suffix(lower, marker) do continue
		root := zip_name[:len(zip_name) - len(marker)]
		if root != "" && !strings.has_suffix(root, "/") do continue
		if d := strings.count(root, "/"); d < depth {
			depth = d
			delete(a.root)
			a.root = strings.clone(root)
		}
	}
	a.files = make(map[string]string, len(a.zip.entries))
	for zip_name in a.zip.entries {
		if !strings.has_prefix(zip_name, a.root) do continue
		a.files[strings.to_lower(zip_name[len(a.root):])] = zip_name
	}
	if depth == max(int) {
		layer := Mod_Layer{archive = a}
		layer_close(&layer)
		return nil, false
	}
	return a, true
}

// Where in `folder` its `marker` is: the folder, or the first folder down, two at most,
// that has one; the folder itself if none has.
@(private)
marker_folder :: proc(folder, marker: string) -> string {
	level := []string{folder}
	for _ in 0 ..= 2 {
		next := make([dynamic]string, context.temp_allocator)
		for dir in level {
			entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
			if err != nil do continue
			slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
			for entry in entries {
				if entry.type != .Directory && strings.equal_fold(entry.name, marker) do return dir
			}
			for entry in entries {
				if entry.type == .Directory do append(&next, utils.temp_path(dir, entry.name))
			}
		}
		level = next[:]
	}
	return folder
}

// Whether `v` is three numbers, as 1.0.0.
@(private = "file")
version_ok :: proc(v: string) -> bool {
	parts := strings.split(v, ".", context.temp_allocator)
	if len(parts) != 3 do return false
	for p in parts {
		if p == "" do return false
		for c in transmute([]u8)p do if c < '0' || c > '9' do return false
	}
	return true
}
