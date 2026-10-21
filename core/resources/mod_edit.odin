package resources

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

import "../utils"

// A mod's mod.json as the Mods page changes it: what it says of itself (its title,
// version, author, description, licence and source), and the scale its parts' images
// are drawn at; and a new mod, empty, made to be filled.

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
	info_path := utils.temp_path(path, SRMOD_INFO_FILE)
	text, read := utils.read_file(info_path, context.temp_allocator)
	info: Srmod_Info
	if !read || json.unmarshal(text, &info, .JSON, context.temp_allocator) != nil do return "Its mod.json can't be read."
	for part in info.parts do if strings.equal_fold(part, PART_NAMES[.Text]) do return ""
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, ..info.parts)
	append(&parts, PART_NAMES[.Text])
	info.parts = parts[:]
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
