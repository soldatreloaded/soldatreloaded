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

MODS_OLD_DIR :: ".old" // in mods/: what a mod was made from, kept

// The mod zipped at `path` (a .srmod or a .zip, its mod.json at its root or a folder or
// two down) unpacked into `mods_dir`, the folder of its name (its mod.json's). A mod of
// that name already there is a problem, but with `replace` (the catalogue's update), which
// takes its place once the new one is whole. Its name, with `allocator`; or why not.
mod_unpack :: proc(path, mods_dir: string, replace := false, allocator := context.allocator) -> (name: string, problem: string) {
	a, found := archive_open_at(path, SRMOD_INFO_FILE)
	if !found do return "", "It isn't a mod: there is no mod.json in it."
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
	if problem = unzip_into(&a.zip, a.root, mods_dir, info.name, replace); problem != "" do return strings.clone(info.name, allocator), problem
	log.infof("unpacked %s into %s/%s", path, mods_dir, info.name)
	return strings.clone(info.name, allocator), ""
}

// The zip's files below its folder `root` ("" for all of it) written into `mods_dir`/`name`:
// into a hidden folder first, which the game passes over, then moved into its place whole,
// over what was there with `replace`. Why not, or "".
@(private)
unzip_into :: proc(z: ^utils.Zip_File, root, mods_dir, name: string, replace: bool) -> string {
	os.make_directory_all(mods_dir)
	target := utils.temp_path(mods_dir, name)
	partial := utils.temp_path(mods_dir, strings.concatenate({".", name, ".part"}, context.temp_allocator))
	os.remove_all(partial)
	for zip_name, entry in z.entries {
		if !strings.has_prefix(zip_name, root) do continue
		below := zip_name[len(root):]
		if below == "" || strings.has_suffix(below, "/") do continue
		if !zip_name_safe(below) {
			os.remove_all(partial)
			return fmt.tprintf("It has a file it may not: %s", below)
		}
		// each file let go of as it is written, so a large mod takes no more
		mark := runtime.default_temp_allocator_temp_begin()
		data, read := utils.zip_read(z, entry, context.temp_allocator)
		dest := utils.temp_path(partial, below)
		os.make_directory_all(filepath.dir(dest))
		written := read && os.write_entire_file(dest, data) == nil
		runtime.default_temp_allocator_temp_end(mark)
		if !written {
			os.remove_all(partial)
			return "It couldn't be written into mods/: is it damaged, or the disk full?" if read else fmt.tprintf("Its %s can't be read: is it damaged?", below)
		}
	}
	if replace && os.is_dir(target) && os.remove_all(target) != nil {
		os.remove_all(partial)
		return "The mod there couldn't be replaced: is a file of it open?"
	}
	if os.rename(partial, target) != nil {
		os.remove_all(partial)
		return "It couldn't be put in its place in mods/."
	}
	return ""
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
// already there is left as it is), and what it was made from moved into mods/.old/. What
// was done, a line each for the player, with the temp allocator.
mods_tidy :: proc(mods_dir: string) -> []string {
	notes := make([dynamic]string, context.temp_allocator)
	entries, err := os.read_all_directory_by_path(mods_dir, context.temp_allocator)
	if err != nil do return nil
	for entry in entries {
		if entry.type == .Directory || strings.has_prefix(entry.name, ".") do continue
		extension := strings.to_lower(filepath.ext(entry.name), context.temp_allocator)
		if extension != SRMOD_EXTENSION && extension != ".zip" do continue
		name, problem := mod_unpack(entry.fullpath, mods_dir, allocator = context.temp_allocator)
		switch {
		case problem == "":
			append(&notes, fmt.tprintf("%s is a folder now, mods/%s/.", entry.name, name))
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
