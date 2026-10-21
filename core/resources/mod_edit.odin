package resources

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"

import "../utils"

// A mod as the Mods page changes it: what its mod.json says of it (its title, version,
// author, description, licence and source), the scale its parts' images are drawn at, and
// its name; its words and its HUD's layout, from the editors; and a new mod, a copy of
// Classic to make one's own.

// What the Mods page shows of a mod and lets the player change, with the temp allocator.
Srmod_Details :: struct {
	title, version, author, description, licence, source: string,
	scale:  f32,         // the mod's own: its images', where a part or a folder doesn't say
	scales: [Part]f32,   // each part's, as srmod_scale finds it for the part's folder
	own:    [Part]bool,  // and whether mod.json says it for the part itself
	deeper: int,         // the scales it says for folders or files within a part, kept as they are
}

// The mod `name` of `mods_dir`'s details; false, and why, if its mod.json can't be read.
srmod_details :: proc(mods_dir, name: string) -> (details: Srmod_Details, problem: string, ok: bool) {
	path := srmod_path(mods_dir, name)
	if path == "" do return {}, "it isn't there", false
	mod, why, opened := srmod_open(path, context.temp_allocator)
	if !opened do return {}, why, false
	defer srmod_close(&mod, context.temp_allocator)
	info := &mod.info
	details = {
		title       = strings.clone(info.title, context.temp_allocator),
		version     = strings.clone(info.version, context.temp_allocator),
		author      = strings.clone(info.author, context.temp_allocator),
		description = strings.clone(info.description, context.temp_allocator),
		licence     = strings.clone(info.licence, context.temp_allocator),
		source      = strings.clone(info.source, context.temp_allocator),
		scale       = info.scale,
	}
	for part in Part {
		details.scales[part] = srmod_scale(&mod, PART_NAMES[part])
		for key in info.scales {
			if strings.equal_fold(strings.trim(key, "/"), PART_NAMES[part]) do details.own[part] = true
		}
	}
	for key in info.scales {
		if _, is_part := part_named(strings.trim(key, "/")); !is_part do details.deeper += 1
	}
	return details, "", true
}

// The mod `name`'s mod.json said again with `details`' title, version, author,
// description, licence and source, and each part's scale (one at the mod's own, not
// said for the part); what else it says (its parts, its folders' and files' own scales)
// kept. Why not, or "".
srmod_details_write :: proc(mods_dir, name: string, details: Srmod_Details) -> string {
	path := srmod_path(mods_dir, name)
	if path == "" do return "It isn't in mods/ any more."
	info_path := utils.temp_path(path, SRMOD_INFO_FILE)
	text, read := utils.read_file(info_path, context.temp_allocator)
	if !read do return "Its mod.json can't be read."
	info: Srmod_Info
	if json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "Its mod.json says something wrongly."

	title := strings.trim_space(details.title)
	switch {
	case title == "":
		return "Give it a title."
	case utf8.rune_count(title) > SRMOD_TITLE_MAX:
		return fmt.tprintf("A title is %d letters at most.", SRMOD_TITLE_MAX)
	case !version_ok(strings.trim_space(details.version)):
		return "A version is three numbers, as 1.0.0."
	case !scale_ok(details.scale):
		return fmt.tprintf("A scale is from %v to %v pixels to a unit.", SRMOD_SCALE_MIN, SRMOD_SCALE_MAX)
	}
	info.title = title
	info.version = strings.trim_space(details.version)
	info.author = strings.trim_space(details.author)
	info.description = strings.trim_space(details.description)
	info.licence = strings.trim_space(details.licence)
	info.source = strings.trim_space(details.source)
	info.scale = details.scale

	scales := make(map[string]f32, context.temp_allocator)
	for key, value in info.scales {
		if _, is_part := part_named(strings.trim(key, "/")); !is_part do scales[key] = value // a folder's or a file's own, kept
	}
	for part in MOD_PARTS {
		s := details.scales[part]
		if s <= 0 || s == details.scale do continue
		if !scale_ok(s) do return fmt.tprintf("A scale is from %v to %v pixels to a unit.", SRMOD_SCALE_MIN, SRMOD_SCALE_MAX)
		scales[PART_NAMES[part]] = s
	}
	info.scales = scales
	return "" if info_write(info_path, info) else "Its mod.json couldn't be written."
}

// A new mod of the player's, `name`: its folder in `mods_dir` and its mod.json, of no
// part yet, titled as it is named. Why not, or "".
mod_new :: proc(mods_dir, name: string) -> string {
	if problem := mod_name_problem(mods_dir, name); problem != "" do return problem
	if !srmod_name_ok(name) do return "A mod's name is letters, digits, - and _, 32 at most."
	dir := utils.temp_path(mods_dir, name)
	if err := os.make_directory_all(dir); err != nil {
		log.errorf("cannot make %s: %v", dir, err)
		return "Its folder couldn't be made."
	}
	info := Srmod_Info{format = SRMOD_FORMAT, name = name, title = name, version = "1.0.0", parts = {}, scale = SRMOD_SCALE}
	if !info_write(utils.temp_path(dir, SRMOD_INFO_FILE), info) do return "Its mod.json couldn't be written."
	return ""
}

// The mod `name`'s words: `lines` (those not "") its text/strings.json, and its mod.json
// listing its text part. Why not, or "".
mod_text_write :: proc(mods_dir, name: string, lines: [String_Id]string) -> string {
	path := srmod_path(mods_dir, name)
	if path == "" do return "It isn't in mods/ any more."
	for line, id in lines {
		if line == "" do continue
		if problem := string_problem(id, line); problem != "" do return fmt.tprintf("%s: %s", STRINGS[id].key, problem)
	}
	folder := utils.temp_path(path, PART_NAMES[.Text])
	if os.make_directory_all(folder) != nil || os.write_entire_file(utils.temp_path(folder, STRINGS_FILE), transmute([]byte)strings_json(lines)) != nil {
		return "Its text/strings.json couldn't be written."
	}
	return part_listed(path, .Text)
}

// The mod `name`'s HUD laid out as `layout`: its hud/layout.json, and its mod.json listing
// its hud part. Its pictures are kept as they are, Classic's where it has none, as the
// HUD editor showed them. Why not, or "".
mod_hud_write :: proc(mods_dir, name: string, layout: Hud_Layout) -> string {
	path := srmod_path(mods_dir, name)
	if path == "" do return "It isn't in mods/ any more."
	folder := utils.temp_path(path, PART_NAMES[.Hud])
	if os.make_directory_all(folder) != nil || os.write_entire_file(utils.temp_path(folder, HUD_LAYOUT_FILE), transmute([]byte)hud_layout_text(layout)) != nil {
		return "Its hud/layout.json couldn't be written."
	}
	return part_listed(path, .Hud)
}

// The mod's at `path` mod.json listing `part`, if it doesn't already. Why not, or "".
@(private = "file")
part_listed :: proc(path: string, part: Part) -> string {
	info_path := utils.temp_path(path, SRMOD_INFO_FILE)
	text, read := utils.read_file(info_path, context.temp_allocator)
	info: Srmod_Info
	if !read || json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "Its mod.json can't be read."
	for listed in info.parts do if strings.equal_fold(listed, PART_NAMES[part]) do return ""
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, ..info.parts)
	append(&parts, PART_NAMES[part])
	info.parts = parts[:]
	return "" if info_write(info_path, info) else "Its mod.json couldn't be written."
}

// A new mod's name, numbered after the first (NewMod_2...), and its title.
MOD_NEW_NAME :: "NewMod"
MOD_NEW_TITLE :: "New Mod"

// A new mod of the player's, a copy of Classic to change: the first of NewMod, NewMod_2...
// free in `mods_dir`, titled New Mod (New Mod 2...), every file of Classic's but the
// scenery, which no mod has; its licence Classic's, as a copy of its art is under it. Made
// out of sight, then moved into its place whole. Its name, with `allocator`; or why not.
mod_from_classic :: proc(mods_dir: string, allocator := context.allocator) -> (name, problem: string) {
	classic := utils.temp_path(mods_dir, MOD_CLASSIC)
	text, read := utils.read_file(utils.temp_path(classic, SRMOD_INFO_FILE), context.temp_allocator)
	info: Srmod_Info
	if !read || json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "", "Classic's mod.json can't be read."
	name = MOD_NEW_NAME
	title := MOD_NEW_TITLE
	for n := 2; mod_exists(mods_dir, name); n += 1 {
		name, title = fmt.tprintf("%s_%d", MOD_NEW_NAME, n), fmt.tprintf("%s %d", MOD_NEW_TITLE, n)
	}
	partial := utils.temp_path(mods_dir, strings.concatenate({".", name, ".part"}, context.temp_allocator))
	os.remove_all(partial)
	scenery := PART_NAMES[.Scenery]
	for file in files_below(classic) {
		top := file[:max(strings.index_byte(file, '/'), 0)]
		if strings.equal_fold(file, SRMOD_INFO_FILE) || strings.equal_fold(top, scenery) do continue
		// each file let go of as it is copied, so all of Classic takes no more
		mark := runtime.default_temp_allocator_temp_begin()
		data, ok := utils.read_file(utils.temp_path(classic, file), context.temp_allocator)
		at := utils.temp_path(partial, file)
		copied := ok && os.make_directory_all(filepath.dir(at)) == nil && os.write_entire_file(at, data) == nil
		runtime.default_temp_allocator_temp_end(mark)
		if !copied {
			os.remove_all(partial)
			return "", "Classic couldn't be copied: is the disk full?"
		}
	}
	parts := make([dynamic]string, context.temp_allocator)
	for part in info.parts do if !strings.equal_fold(part, scenery) do append(&parts, part)
	info.name, info.title, info.version = name, title, "1.0.0"
	info.author, info.source = "", ""
	info.description = "A copy of Classic, to make your own."
	info.parts = parts[:]
	if !info_write(utils.temp_path(partial, SRMOD_INFO_FILE), info) {
		os.remove_all(partial)
		return "", "Its mod.json couldn't be written."
	}
	if problem = move_in(partial, mods_dir, name, false); problem != "" do return "", problem
	return strings.clone(name, allocator), ""
}

// The mod `from` of `mods_dir` named `to`: its folder, and the name its mod.json says, by
// which it is worn. Why not, or "".
mod_rename :: proc(mods_dir, from, to: string) -> string {
	path := srmod_path(mods_dir, from)
	if path == "" do return "It isn't in mods/ any more."
	if to == from do return ""
	only_case := strings.equal_fold(to, from)
	if !only_case {
		if problem := mod_name_problem(mods_dir, to); problem != "" do return problem
	}
	if !srmod_name_ok(to) do return "A name is letters, digits, - and _, 32 at most."
	if only_case { // a folder in another case is the same folder on Windows: by way of another name
		between := utils.temp_path(mods_dir, strings.concatenate({".", to, ".renaming"}, context.temp_allocator))
		if os.rename(path, between) != nil do return "Its folder couldn't be renamed: is a file of it open?"
		path = between
	}
	dest := utils.temp_path(mods_dir, to)
	if os.rename(path, dest) != nil do return "Its folder couldn't be renamed: is a file of it open?"
	info_path := utils.temp_path(dest, SRMOD_INFO_FILE)
	text, read := utils.read_file(info_path, context.temp_allocator)
	info: Srmod_Info
	if !read || json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "Its mod.json can't be read."
	info.name = to
	return "" if info_write(info_path, info) else "Its mod.json couldn't be written."
}

// `info` written as the mod.json at `path`, as the game writes one. False, logged, if it
// can't be.
@(private)
info_write :: proc(path: string, info: Srmod_Info) -> bool {
	options := json.Marshal_Options{spec = .JSON, pretty = true, use_spaces = true, spaces = 2, sort_maps_by_key = true}
	text, err := json.marshal(info, options, context.temp_allocator)
	if err != nil || os.write_entire_file(path, text) != nil {
		log.errorf("cannot write %s", path)
		return false
	}
	return true
}
