package resources

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../utils"

// A mod at rest is a folder of mods/ (docs/srmod.md): a zip is how one comes in, a .srmod
// or a .zip handed over or downloaded, and it is unpacked into its folder (mod_unpack). The
// game tidies mods/ as it starts (mods_tidy): what is there that isn't a folder of the
// format is made one, and what it was made from moved into mods/.old/, kept, never worn.
//
// A mod of before (laid out as a Soldat 1 mod, gostek-gfx/, sfx/... and its mod.ini and
// about.json, a folder or an .smod) is converted (old_convert): all of it goes in, laid out
// by part as the importer lays out a Soldat 1 mod, its images at the scales its mod.ini
// gave them, Classic's 4.5 where it gave none, as the game drew them; its about.json its
// mod.json. A zip of a Soldat 1 mod is taken so too.

MODS_OLD_DIR :: ".old" // in mods/: what a mod was made from, kept
@(private = "file") CONVERTING_DIR :: ".converting" // in mods/: a mod of before being made one, out of sight

// The mod zipped at `path` (a .srmod or a .zip, its mod.json at its root or a folder or
// two down) unpacked into `mods_dir`, the folder of its name (its mod.json's). A zip of a
// mod of before, or of a Soldat 1 mod, without a mod.json, is converted (old_convert),
// named `name`, else for its file. A mod of that name already there is a problem, but
// with `replace` (the catalogue's update), which takes its place once the new one is
// whole. Its name, with `allocator`; or why not.
mod_unpack :: proc(path, mods_dir: string, name := "", replace := false, allocator := context.allocator) -> (unpacked: string, problem: string) {
	a, found := archive_open_at(path, SRMOD_INFO_FILE)
	if !found do return old_unpack(path, mods_dir, name, replace, allocator)
	layer := Mod_Layer{archive = a}
	defer layer_close(&layer)

	info: Srmod_Info
	file, _ := layer_file(&layer, 0, SRMOD_INFO_FILE)
	text, read := mod_read(file, context.temp_allocator)
	if !read || json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "", "Its mod.json can't be read."
	if !srmod_name_ok(info.name) do return "", "Its mod.json's name isn't letters, digits, - and _, 32 at most."
	if !replace && (mod_exists(mods_dir, info.name) || mod_builtin(info.name)) {
		return strings.clone(info.name, allocator), "There is a mod by that name already."
	}
	partial := utils.temp_path(mods_dir, strings.concatenate({".", info.name, ".part"}, context.temp_allocator))
	if problem = unzip_to(&a.zip, a.root, partial); problem == "" do problem = move_in(partial, mods_dir, info.name, replace)
	if problem != "" do return strings.clone(info.name, allocator), problem
	log.infof("unpacked %s into %s/%s", path, mods_dir, info.name)
	return strings.clone(info.name, allocator), ""
}

// A zip without a mod.json: a mod of before, or a Soldat 1 mod, laid out as Soldat 1's,
// unpacked out of sight and converted (old_convert). Not one if nothing in it is laid out
// so.
@(private = "file")
old_unpack :: proc(path, mods_dir, name: string, replace: bool, allocator: runtime.Allocator) -> (unpacked: string, problem: string) {
	z, opened := utils.zip_open(path, context.temp_allocator)
	if !opened do return "", "It isn't a zip the game can read."
	defer utils.zip_close(&z, context.temp_allocator)
	if !archive_is_old(&z) do return "", "It isn't a mod: there is no mod.json in it, nor anything laid out as a Soldat mod's."
	stem := name if name != "" else filepath.stem(path)
	unpacked = mod_name_from(stem)
	if unpacked == "" do return "", "Its name can't be a mod's."
	if !replace && (mod_exists(mods_dir, unpacked) || mod_builtin(unpacked)) do return strings.clone(unpacked, allocator), "There is a mod by that name already."
	source := utils.temp_path(mods_dir, CONVERTING_DIR, "zip")
	os.remove_all(source)
	defer os.remove_all(utils.temp_path(mods_dir, CONVERTING_DIR))
	if problem = unzip_to(&z, "", source); problem != "" do return strings.clone(unpacked, allocator), problem
	problem = old_convert(source, mods_dir, unpacked, replace)
	return strings.clone(unpacked, allocator), problem
}

// Whether a zip's files are laid out as a Soldat 1 mod's: any of its folders, or its
// mod.ini, at its root or a folder or two down.
@(private = "file")
archive_is_old :: proc(z: ^utils.Zip_File) -> bool {
	for zip_name in z.entries {
		parts := strings.split(zip_name, "/", context.temp_allocator)
		for part, i in parts[:min(len(parts), 3)] {
			if is_root_name(part, i < len(parts) - 1) do return true
		}
	}
	return false
}

// The mod of before at `dir`, laid out as a Soldat 1 mod (at its root or a folder or two
// down), made the mod `name` in `mods_dir`, whole: each file of its art, sounds and fonts
// laid out by part, its images at their scales (its mod.ini's, else Classic's 4.5), its
// pivots, and its about.json's title, version, author, description and licence its
// mod.json's. Made out of sight, then moved into its place, over a mod of that name with
// `replace`; `dir`, if in `mods_dir`, moved first into mods/.old/. Why not, or "".
old_convert :: proc(dir, mods_dir, name: string, replace := false) -> (problem: string) {
	about := old_about(folder_root(dir))
	title := about.title if strings.trim_space(about.title) != "" else name
	description := about.description if about.description != "" else fmt.tprintf("%s, a mod of before, converted.", title)
	building := utils.temp_path(mods_dir, CONVERTING_DIR, "made")
	os.remove_all(building)
	defer os.remove_all(building)
	os.make_directory_all(building)

	classic := mod_make(mods_dir, allocator = context.temp_allocator)
	defer mod_destroy(&classic, context.temp_allocator)
	options := Import_Options {
		whole         = true,
		default_scale = SRMOD_SCALE,
		about         = {version = about.version, author = about.author, licence = about.licence, source = about.source},
		description   = description,
	}
	result := mod_import({dir}, building, name, classic, title, options)
	if result.problem != "" do return result.problem
	// the folder converted is in mods/ itself: put aside before the mod takes its place
	if within(dir, mods_dir) do set_aside(mods_dir, dir)
	return move_in(utils.temp_path(building, name), mods_dir, name, replace)
}

// What a mod of before said of itself, in its about.json, as the mods repository wrote
// it; "" where it said nothing. With the temp allocator.
@(private = "file")
Old_About :: struct {
	title, version, author, description, licence, source: string,
}

@(private = "file")
old_about :: proc(root: string) -> (about: Old_About) {
	path := utils.temp_path(root, "about.json")
	if !utils.file_exists(path) do return
	text, read := utils.read_file(path, context.temp_allocator)
	if read do json.unmarshal(text, &about, allocator = context.temp_allocator)
	return
}

// The zip's files below its folder `root` ("" for all of it) written into the folder
// `dest`, made anew. Why not, or "".
@(private)
unzip_to :: proc(z: ^utils.Zip_File, root, dest: string) -> string {
	os.remove_all(dest)
	os.make_directory_all(dest)
	for zip_name, entry in z.entries {
		if !strings.has_prefix(zip_name, root) do continue
		below := zip_name[len(root):]
		if below == "" || strings.has_suffix(below, "/") do continue
		if !zip_name_safe(below) {
			os.remove_all(dest)
			return fmt.tprintf("It has a file it may not: %s", below)
		}
		// each file let go of as it is written, so a large mod takes no more
		mark := runtime.default_temp_allocator_temp_begin()
		data, read := utils.zip_read(z, entry, context.temp_allocator)
		at := utils.temp_path(dest, below)
		os.make_directory_all(filepath.dir(at))
		written := read && os.write_entire_file(at, data) == nil
		runtime.default_temp_allocator_temp_end(mark)
		if !written {
			os.remove_all(dest)
			return "It couldn't be written into mods/: is it damaged, or the disk full?" if read else fmt.tprintf("Its %s can't be read: is it damaged?", below)
		}
	}
	return ""
}

// The folder `made` moved into `mods_dir` as the mod `name`, over a mod of that name with
// `replace`. Why not, or "".
@(private = "file")
move_in :: proc(made, mods_dir, name: string, replace: bool) -> string {
	target := utils.temp_path(mods_dir, name)
	if os.is_dir(target) {
		if !replace {
			os.remove_all(made)
			return "There is a mod by that name already."
		}
		if os.remove_all(target) != nil {
			os.remove_all(made)
			return "The mod there couldn't be replaced: is a file of it open?"
		}
	}
	if os.rename(made, target) != nil {
		os.remove_all(made)
		return "It couldn't be put in its place in mods/."
	}
	return ""
}

// Whether `path` is in the folder `dir`, itself or below.
@(private = "file")
within :: proc(path, dir: string) -> bool {
	full :: proc(p: string) -> string {
		abs, err := os.get_absolute_path(p, context.temp_allocator)
		if err != nil do abs = p
		slashed, _ := strings.replace_all(abs, "\\", "/", context.temp_allocator)
		return strings.to_lower(strings.trim_right(slashed, "/"), context.temp_allocator)
	}
	p, d := full(path), full(dir)
	return strings.has_prefix(p, d) && len(p) > len(d) && p[len(d)] == '/'
}

// Whether `name`, a zip's file's path, stays inside the folder it is unpacked into.
zip_name_safe :: proc(name: string) -> bool {
	if name == "" || strings.has_prefix(name, "/") || strings.contains(name, ":") || strings.contains(name, "\\") do return false
	for part in strings.split(name, "/", context.temp_allocator) {
		if part == "" || part == "." || part == ".." do return false
	}
	return true
}

// mods/ made folders of the format: each .srmod and .zip in it unpacked (a mod by its name
// already there is left as it is), and each mod of before, an .smod or a folder without a
// mod.json laid out as a Soldat 1 mod, converted; what each was made from moved into
// mods/.old/. What was done, a line each for the player, with the temp allocator.
mods_tidy :: proc(mods_dir: string) -> []string {
	notes := make([dynamic]string, context.temp_allocator)
	os.remove_all(utils.temp_path(mods_dir, CONVERTING_DIR)) // a conversion cut short
	defer os.remove_all(utils.temp_path(mods_dir, CONVERTING_DIR))
	entries, err := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	if err != nil do return nil
	for entry in entries {
		if strings.has_prefix(entry.name, ".") || mod_builtin(entry.name) || reserved(entry.name) do continue
		if entry.type == .Directory {
			if utils.file_exists(utils.temp_path(entry.fullpath, SRMOD_INFO_FILE)) || !old_layout(entry.fullpath) do continue
			name := mod_name_from(entry.name)
			switch {
			case name == "":
				append(&notes, fmt.tprintf("mods/%s/, a mod of before, has a name a mod can't: rename it.", entry.name))
			case name != entry.name && mod_exists(mods_dir, name):
				append(&notes, fmt.tprintf("mods/%s/, a mod of before, would be %s, which there is already.", entry.name, name))
			case:
				if problem := old_convert(entry.fullpath, mods_dir, name); problem != "" {
					append(&notes, fmt.tprintf("mods/%s/, a mod of before, couldn't be converted: %s", entry.name, problem))
				} else {
					append(&notes, fmt.tprintf("mods/%s/, a mod of before, is one of now; it was put in mods/.old/.", name))
				}
			}
			continue
		}
		extension := strings.to_lower(filepath.ext(entry.name), context.temp_allocator)
		if extension != SRMOD_EXTENSION && extension != ".zip" && extension != MOD_EXTENSION do continue
		name, problem := mod_unpack(entry.fullpath, mods_dir, allocator = context.temp_allocator)
		switch {
		case problem == "":
			append(&notes, fmt.tprintf("%s is mods/%s/ now.", entry.name, name))
		case name != "" && mod_exists(mods_dir, name):
			append(&notes, fmt.tprintf("%s is mods/%s/, which was there already: it was put aside.", entry.name, name))
		case:
			// not one the game reads: left where it is, said
			append(&notes, fmt.tprintf("%s: %s", entry.name, problem))
			continue
		}
		set_aside(mods_dir, entry.fullpath)
	}
	return notes[:]
}

// The file or folder at `path` moved into `mods_dir`/.old/, kept, out of the way; a name
// there already, numbered.
@(private)
set_aside :: proc(mods_dir, path: string) {
	old := utils.temp_path(mods_dir, MODS_OLD_DIR)
	os.make_directory_all(old)
	base := filepath.base(path)
	dest := utils.temp_path(old, base)
	for n := 2; os.exists(dest); n += 1 {
		stem := strings.trim_suffix(base, filepath.ext(base))
		dest = utils.temp_path(old, fmt.tprintf("%s_%d%s", stem, n, filepath.ext(base)))
	}
	if err := os.rename(path, dest); err != nil do log.errorf("cannot move %s into %s: %v", path, old, err)
}
