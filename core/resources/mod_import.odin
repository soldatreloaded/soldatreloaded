package resources

import "core:hash"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

import "../utils"

// A mod made from a Soldat 1.7.1 install, as its player has it: the art and sounds they
// put over the game's own, packed into mods/<name>.smod. What goes in is what they
// changed: a file of Classic's names that is neither 1.7.1's own as it came
// (SOLDAT_STOCK, by its size and CRC-32: Classic's art is redrawn, and the original's
// would replace it) nor the same as Classic's (an image by its pixels as the game draws
// it, so the same picture as a .bmp is the same); and the install's mod.ini and fonts,
// which pin and letter that art. The rest is Classic's already.
//
// The install is found where Soldat is usually put (soldat_installs), or from any folder
// of it (soldat_root); what a mod can be made from in it is its own folders, which a
// player may have put their art over, and each mod of its mods/ (soldat_sources), a mod
// over its own folders, as Soldat wears it.

// The files of an original Soldat 1.7.1 install as it came (data/'s, from the client's
// working directory): "<size> <crc32, hex> <path in lower case>" a line.
SOLDAT_STOCK :: "data/soldat-1.7.1.txt"

// Where Soldat 1.7.1 may be, besides wherever the player says: its installer's and
// Steam's places, and a few a player is likely to have put it.
soldat_installs :: proc(allocator := context.allocator) -> []string {
	context.allocator = context.temp_allocator
	candidates := make([dynamic]string)
	when ODIN_OS == .Windows {
		home := os.get_env("USERPROFILE", context.temp_allocator)
		for drive in ([?]string{"C:", "D:", "E:"}) {
			append(&candidates, utils.temp_path(drive, "Soldat"), utils.temp_path(drive, "Games", "Soldat"))
		}
		for program_files in ([?]string{os.get_env("ProgramFiles(x86)", context.temp_allocator), os.get_env("ProgramFiles", context.temp_allocator)}) {
			if program_files == "" do continue
			append(&candidates, utils.temp_path(program_files, "Soldat"))
			steam := utils.temp_path(program_files, "Steam")
			append(&candidates, utils.temp_path(steam, "steamapps", "common", "Soldat"))
			for library in steam_libraries(steam) do append(&candidates, utils.temp_path(library, "steamapps", "common", "Soldat"))
		}
		if home != "" {
			for under in ([?]string{"", "Desktop", "Documents", "Downloads", "Games"}) {
				append(&candidates, utils.temp_path(home, under, "Soldat") if under != "" else utils.temp_path(home, "Soldat"))
			}
		}
	} else {
		home := os.get_env("HOME", context.temp_allocator)
		if home != "" {
			append(&candidates, utils.temp_path(home, ".wine", "drive_c", "Soldat"), utils.temp_path(home, "Soldat"), utils.temp_path(home, "Games", "Soldat"))
			for steam in ([?]string{utils.temp_path(home, ".local", "share", "Steam"), utils.temp_path(home, ".steam", "steam")}) {
				append(&candidates, utils.temp_path(steam, "steamapps", "common", "Soldat"))
				for library in steam_libraries(steam) do append(&candidates, utils.temp_path(library, "steamapps", "common", "Soldat"))
			}
		}
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

// The mod `name` made in `mods_dir`, an .smod, from the folders `dirs` of an original
// Soldat install, each over the last as Soldat wears a mod over its own folders (the
// install's own first, then a mod of its mods/): each file of their art, sounds and
// fonts that is one of Classic's, neither 1.7.1's own as it came nor the same as
// Classic's; and the mod.ini of the last that has one. A folder that is the install
// itself is looked through for its own folders alone, not its mods/ or maps/.
mod_import :: proc(dirs: []string, mods_dir, name: string, classic: Mod) -> (result: Import_Result) {
	if problem := mod_name_problem(mods_dir, name); problem != "" do return {problem = problem}
	if len(dirs) == 0 do return {problem = "Pick what to make the mod from."}
	stock := stock_load()
	merged := make(map[string]Packed, 256, context.temp_allocator)
	for dir in dirs {
		if !soldat_is_install(dir) do return {problem = "That isn't a Soldat folder: there is no gostek-gfx, weapons-gfx or the like in it."}
		files, _ := scan(dir, classic, &stock, own = is_soldat(dir))
		for f in files do merged[strings.to_lower(f.name, context.temp_allocator)] = f
	}
	packed := make([dynamic]Packed, context.temp_allocator)
	for _, f in merged do append(&packed, f)
	result.changed = changed_of(packed[:])
	if result.changed == 0 {
		return {problem = "Nothing there differs from the game as it came. Put your art and sounds in its folders first."}
	}

	os.make_directory_all(mods_dir)
	path := utils.temp_path(mods_dir, strings.concatenate({name, MOD_EXTENSION}, context.temp_allocator))
	part := utils.temp_path(mods_dir, strings.concatenate({".", name, ".part"}, context.temp_allocator))
	w: utils.Zip_Writer
	if !utils.zip_write_begin(&w, part) do return {problem = "The mod couldn't be written into mods/."}
	for p in packed {
		data, read := utils.read_file(p.path, context.temp_allocator)
		if !read {
			log.warnf("cannot read %s; left out of the mod", p.path)
			continue
		}
		utils.zip_write_add(&w, p.name, data)
	}
	if !utils.zip_write_end(&w) || os.rename(part, path) != nil {
		os.remove(part)
		return {problem = "The mod couldn't be written into mods/: is the disk full?"}
	}
	log.infof("made the mod %s from %v: %d files that differ from the game's", path, dirs, result.changed)
	return
}

// A file a mod is made of: its name in the .smod, and where it is.
@(private = "file")
Packed :: struct {
	name: string,
	path: string,
}

// What of the folder `dir` goes in a mod (mod_import): each file of the game's folders
// that differs, and its mod.ini and fonts. `own`, it is an install's own: only its
// game's folders are looked through. With the temp allocator.
@(private = "file")
scan :: proc(dir: string, classic: Mod, stock: ^map[string]Stock_File, own: bool) -> (files: []Packed, ok: bool) {
	root := dir if own else folder_root(dir)
	at := install_path(root) // where its files are in the install, as the stock list has them
	packed := make([dynamic]Packed, context.temp_allocator)
	for file in files_below(root, own) {
		top := file[:max(strings.index_byte(file, '/'), 0)]
		if top == "" || !is_root_name(top, true) do continue
		if is_stock(stock, root, file, at) || !differs(classic, root, file) do continue
		append(&packed, Packed{file, utils.temp_path(root, file)})
	}
	if len(packed) == 0 do return nil, true
	// its mod.ini, which pins and sizes its art, and the fonts its font.ini names
	for file in files_at(root) {
		config := strings.equal_fold(file, MOD_CONFIG_FILE)
		font := strings.equal_fold(filepath.ext(file), ".ttf") || strings.equal_fold(filepath.ext(file), ".otf")
		if config || (font && differs(classic, root, file)) do append(&packed, Packed{file, utils.temp_path(root, file)})
	}
	return packed[:], true
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

// How many of the files are art or sounds: not the fonts, nor mod.ini.
@(private = "file")
changed_of :: proc(files: []Packed) -> (n: int) {
	for f in files {
		top := strings.to_lower(f.name[:max(strings.index_byte(f.name, '/'), 0)], context.temp_allocator)
		if top != "" && top != "txt" && top != "fonts" do n += 1
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

// Whether the file `file` (below `root`) is one of Classic's, and isn't the same: an
// image whose pixels differ, else bytes that do. A file Classic hasn't isn't one: the
// game never asks for it.
@(private = "file")
differs :: proc(classic: Mod, root, file: string) -> bool {
	slash := strings.last_index_byte(file, '/')
	dir, name := file[:max(slash, 0)], file[slash + 1:]
	extension := strings.to_lower(filepath.ext(name), context.temp_allocator)
	theirs: Mod_File
	found: bool
	switch {
	case extension == ".png" || extension == ".bmp" || extension == ".jpg" || extension == ".gif" || extension == ".tga":
		theirs, found = mod_image(classic, dir, name)
	case strings.has_prefix(strings.to_lower(file, context.temp_allocator), "sfx/") && (extension == ".wav" || extension == ".ogg" || extension == ".mp3"):
		theirs, found = sound_file(classic, file[len("sfx/"):])
	case:
		theirs, found = mod_file(classic, file)
	}
	if !found do return false
	mine := utils.read_file(utils.temp_path(root, file), context.temp_allocator) or_return
	classics := mod_read(theirs, context.temp_allocator) or_return
	if slice.equal(mine, classics) do return false
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
	text, read := utils.read_file(SOLDAT_STOCK, context.temp_allocator)
	if !read do return stock
	rest := string(text)
	for line in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(line, "//") do continue
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) != 3 do continue
		size, size_ok := strconv.parse_int(fields[0])
		crc, crc_ok := strconv.parse_u64_of_base(fields[1], 16)
		if size_ok && crc_ok do stock[fields[2]] = {size, u32(crc)}
	}
	return stock
}

// Whether `file` (below `root`, which is `at` in its install: "", or "mods/classic/") is
// Soldat 1.7.1's own, as it came.
@(private = "file")
is_stock :: proc(stock: ^map[string]Stock_File, root, file, at: string) -> bool {
	known := stock[strings.to_lower(strings.concatenate({at, file}, context.temp_allocator), context.temp_allocator)] or_return
	data := utils.read_file(utils.temp_path(root, file), context.temp_allocator) or_return
	return len(data) == known.size && hash.crc32(data) == known.crc
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
