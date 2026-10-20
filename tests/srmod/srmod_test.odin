package srmod_test

// Soldat Reloaded's mods (core/resources/srmod.odin, hud_layout.odin, docs/srmod.md): a
// mod opened from its folder or its .srmod, what its mod.json says checked against its
// folders; the mods listed; each part worn from a mod of its own, Classic's under it, file
// by file; the soldier's and the weapons' pivots; and the HUD's layout.json, read over
// Classic's, written, and to and from Soldat 1's setup.sif.
//
//   odin test tests/srmod

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import res "../../core/resources"
import "../../core/utils"

scratch :: proc(t: ^testing.T, name: string) -> string {
	dir := utils.temp_path(os.get_env("TEMP", context.temp_allocator) if ODIN_OS == .Windows else "/tmp", strings.concatenate({"soldatreloaded_srmod_test_", name}, context.temp_allocator))
	os.remove_all(dir)
	testing.expect(t, os.make_directory_all(dir) == nil, "a scratch folder")
	return dir
}

write :: proc(path: string, data: string) {
	os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	utils.write_file(path, transmute([]byte)data)
}

// A mod.json for `name`, of `parts`.
info :: proc(name: string, parts: string, format := 1, version := "1.0.0") -> string {
	return strings.concatenate({`{"format": `, format == 1 ? "1" : "2", `, "name": "`, name, `", "version": "`, version, `", "author": "Me", "parts": [`, parts, `]}`}, context.temp_allocator)
}

read :: proc(file: res.Mod_File) -> string {
	data, _ := res.mod_read(file, context.temp_allocator)
	return string(data)
}

// A mod's folder, and a zip of one a folder down: what each says of itself, its parts
// its folders, and what is wrong with what it lists said.
@(test)
opened :: proc(t: ^testing.T) {
	dir := scratch(t, "opened")
	defer os.remove_all(dir)
	folder := utils.temp_path(dir, "Plain")
	write(utils.temp_path(folder, "mod.json"), info("Plain", `"soldier", "sounds", "hats"`))
	write(utils.temp_path(folder, "soldier", "klata.png"), "chest")
	write(utils.temp_path(folder, "weapons", "ak74.png"), "gun")

	plain, why, ok := res.srmod_open(folder)
	defer res.srmod_close(&plain)
	if !testing.expectf(t, ok, "a folder opens (%s)", why) do return
	testing.expect_value(t, plain.info.name, "Plain")
	testing.expect_value(t, plain.info.title, "Plain") // none given: its name
	testing.expect_value(t, plain.parts, res.Parts{.Soldier, .Weapons})
	testing.expect_value(t, len(plain.problems), 3) // hats, sounds without a folder, weapons unlisted
	file, found := res.srmod_file(&plain, .Soldier, "KLATA.PNG")
	testing.expect(t, found && read(file) == "chest", "a file of a part, in any case")
	_, none := res.srmod_file(&plain, .Sounds, "x.wav")
	testing.expect(t, !none, "none of a part it hasn't")

	w: utils.Zip_Writer
	packed := utils.temp_path(dir, "Packed.srmod")
	utils.zip_write_begin(&w, packed)
	utils.zip_write_add(&w, "Packed/mod.json", transmute([]byte)string(`{"format": 1, "name": "Packed", "title": "Packed Up", "version": "2.1.0", "parts": ["hud"]}`))
	utils.zip_write_add(&w, "Packed/hud/layout.json", transmute([]byte)string(`{"alpha": 100}`))
	utils.zip_write_end(&w)
	zipped, zwhy, zok := res.srmod_open(packed)
	defer res.srmod_close(&zipped)
	if !testing.expectf(t, zok, "a .srmod opens, its files a folder down (%s)", zwhy) do return
	testing.expect(t, zipped.info.title == "Packed Up" && zipped.parts == {.Hud} && len(zipped.problems) == 0, "its title, its one part, nothing wrong")
	layout, has := res.srmod_file(&zipped, .Hud, "layout.json")
	testing.expect(t, has && read(layout) == `{"alpha": 100}`, "its file read from the zip")
}

// What isn't a mod, or one this game can't wear, is refused, saying why.
@(test)
refused :: proc(t: ^testing.T) {
	dir := scratch(t, "refused")
	defer os.remove_all(dir)
	cases := []struct {
		name, text, why: string,
	} {
		{"NoInfo", "", "no mod.json"},
		{"Broken", `{"format": 1,`, "isn't JSON"},
		{"Future", info("Future", "", format = 2), "format 2"},
		{"BadName", info("Bad Name!", ""), "its name"},
		{"Classic", info("Classic", ""), "its name"},
		{"BadVersion", info("BadVersion", "", version = "1.0"), "its version"},
	}
	for c in cases {
		folder := utils.temp_path(dir, c.name)
		os.make_directory_all(folder)
		if c.text != "" do write(utils.temp_path(folder, "mod.json"), c.text)
		mod, why, ok := res.srmod_open(folder)
		testing.expectf(t, !ok && strings.contains(why, c.why), "%s refused, saying %q: %q", c.name, c.why, why)
		res.srmod_close(&mod)
	}
}

// An image's scale: the longest of its mod's scales that is it or holds it, in any case
// and whatever its extension, else the mod's; SRMOD_SCALE if it says none; a mod of a
// scale out of reason refused. The scales a mod is written with, as few as say them.
@(test)
scaled :: proc(t: ^testing.T) {
	dir := scratch(t, "scaled")
	defer os.remove_all(dir)
	folder := utils.temp_path(dir, "Old")
	write(utils.temp_path(folder, "mod.json"), `{"format": 1, "name": "Old", "version": "1.0.0", "parts": ["soldier", "weapons"], "scale": 1, "scales": {"Weapons": 4.5, "weapons/icons": 2, "soldier/ranny/krew.png": 3}}`)
	write(utils.temp_path(folder, "soldier", "klata.png"), "chest")
	write(utils.temp_path(folder, "weapons", "ak74.png"), "gun")
	mod, why, ok := res.srmod_open(folder)
	defer res.srmod_close(&mod)
	if !testing.expectf(t, ok, "opened (%s)", why) do return
	testing.expect_value(t, res.srmod_scale(&mod, "soldier/klata.png"), 1)
	testing.expect_value(t, res.srmod_scale(&mod, "weapons/ak74.png"), 4.5)
	testing.expect_value(t, res.srmod_scale(&mod, "WEAPONS/Icons/1.png"), 2)
	testing.expect_value(t, res.srmod_scale(&mod, "soldier/ranny/krew.bmp"), 3)
	testing.expect_value(t, res.srmod_scale(&mod, "weaponsplus/x.png"), 1) // not in weapons/
	file, _ := res.srmod_file(&mod, .Weapons, "AK74.png")
	testing.expect_value(t, file.scale, 4.5)

	write(utils.temp_path(dir, "Plain", "mod.json"), info("Plain", ""))
	plain, _, _ := res.srmod_open(utils.temp_path(dir, "Plain"))
	testing.expect_value(t, res.srmod_scale(&plain, "soldier/klata.png"), res.SRMOD_SCALE)
	res.srmod_close(&plain)
	write(utils.temp_path(dir, "Huge", "mod.json"), `{"format": 1, "name": "Huge", "version": "1.0.0", "scale": 1000}`)
	huge, huge_why, huge_ok := res.srmod_open(utils.temp_path(dir, "Huge"))
	testing.expect(t, !huge_ok && strings.contains(huge_why, "scale"), "a scale out of reason refused")
	res.srmod_close(&huge)

	per_file := make(map[string]f32, context.temp_allocator)
	per_file["soldier/klata.png"] = 1
	per_file["soldier/morda.png"] = 1
	per_file["soldier/ranny/krew.png"] = 4.5
	per_file["weapons/ak74.png"] = 2
	per_file["weapons/m79.png"] = 2
	per_file["weapons/icons/1.png"] = 1
	per_file["hud/health.png"] = 1
	scale, scales := res.scales_compact(per_file)
	testing.expect_value(t, scale, 1)
	testing.expect_value(t, len(scales), 3)
	testing.expect(t, scales["soldier/ranny"] == 4.5 && scales["weapons"] == 2, "a folder of one scale said once")
	testing.expect_value(t, scales["weapons/icons/1.png"], 1) // within weapons/, which says 2
	said := res.Srmod{info = {scale = scale, scales = scales}}
	for path, s in per_file do testing.expectf(t, res.srmod_scale(&said, path) == s, "%s at %v", path, s)
}

// The mods in a folder: each folder with a mod.json; not a zip, Classic, a folder that is
// no mod, nor a hidden one (being written, or put aside in .old/).
@(test)
listed :: proc(t: ^testing.T) {
	dir := scratch(t, "listed")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "Alpha", "mod.json"), info("Alpha", ""))
	write(utils.temp_path(dir, "Beta", "mod.json"), info("Beta", ""))
	write(utils.temp_path(dir, "Gamma.srmod"), "zip")
	write(utils.temp_path(dir, "classic", "mod.json"), info("classic", ""))
	write(utils.temp_path(dir, "Loose", "klata.png"), "chest")
	write(utils.temp_path(dir, ".Delta.part", "mod.json"), info("Delta", ""))
	testing.expect(t, slice.equal(res.srmods_list(dir), []string{"Alpha", "Beta"}), "Alpha and Beta")
	testing.expect(t, strings.has_suffix(res.srmod_path(dir, "Alpha"), "Alpha"), "Alpha's folder")
	testing.expect_value(t, res.srmod_path(dir, "Gamma"), "")
}

// A zip of a mod, its mod.json a folder down, unpacked into the folder of its mod.json's
// name, its files as they were; a name taken refused, unless it is replaced; a zip that
// isn't a mod, or would write outside its folder, refused.
@(test)
unpacked :: proc(t: ^testing.T) {
	dir := scratch(t, "unpacked")
	defer os.remove_all(dir)
	mods := utils.temp_path(dir, "mods")
	zip :: proc(path: string, files: []struct{name, data: string}) {
		w: utils.Zip_Writer
		utils.zip_write_begin(&w, path)
		for f in files do utils.zip_write_add(&w, f.name, transmute([]byte)f.data)
		utils.zip_write_end(&w)
	}
	shared := utils.temp_path(dir, "shared.zip")
	zip(shared, {{"Neat Mod/mod.json", info("Neat", `"soldier"`)}, {"Neat Mod/soldier/Klata.png", "chest"}, {"Neat Mod/soldier/team2/klata.png", "red chest"}})
	name, problem := res.mod_unpack(shared, mods, allocator = context.temp_allocator)
	testing.expectf(t, problem == "" && name == "Neat", "unpacked as Neat (%s)", problem)
	testing.expect(t, string(utils.read_file(utils.temp_path(mods, "Neat", "soldier", "Klata.png"), context.temp_allocator) or_else nil) == "chest", "its files, their names' case kept")
	testing.expect(t, utils.file_exists(utils.temp_path(mods, "Neat", "soldier", "team2", "klata.png")), "its folders")
	testing.expect(t, !os.exists(utils.temp_path(mods, ".Neat.part")), "nothing left half written")

	_, taken := res.mod_unpack(shared, mods, allocator = context.temp_allocator)
	testing.expect(t, strings.contains(taken, "already"), "its name taken")
	newer := utils.temp_path(dir, "newer.srmod")
	zip(newer, {{"mod.json", info("Neat", `"sounds"`, version = "1.1.0")}, {"sounds/shot.wav", "bang"}})
	_, replaced := res.mod_unpack(newer, mods, replace = true, allocator = context.temp_allocator)
	testing.expect(t, replaced == "" && utils.file_exists(utils.temp_path(mods, "Neat", "sounds", "shot.wav")) && !os.exists(utils.temp_path(mods, "Neat", "soldier")), "replaced whole")
	testing.expect_value(t, res.mod_version(mods, "Neat"), "1.1.0")

	loose := utils.temp_path(dir, "loose.zip")
	zip(loose, {{"readme.txt", "hi"}})
	_, not_mod := res.mod_unpack(loose, mods, allocator = context.temp_allocator)
	testing.expect(t, strings.contains(not_mod, "mod.json"), "a zip of no mod refused")
	escaping := utils.temp_path(dir, "escaping.zip")
	zip(escaping, {{"mod.json", info("Escape", "")}, {"../outside.txt", "oops"}})
	_, unsafe := res.mod_unpack(escaping, mods, allocator = context.temp_allocator)
	testing.expect(t, unsafe != "" && !os.exists(utils.temp_path(dir, "outside.txt")) && !os.exists(utils.temp_path(mods, "Escape")), "nothing written outside, nor the mod")
}

// mods/ tidied as the game starts: a .srmod and a .zip there unpacked, each put aside in
// .old/; one whose name a folder has already, put aside, the folder kept; a zip of no mod
// left where it is; each said.
@(test)
tidied :: proc(t: ^testing.T) {
	dir := scratch(t, "tidied")
	defer os.remove_all(dir)
	zip :: proc(path, name: string) {
		w: utils.Zip_Writer
		utils.zip_write_begin(&w, path)
		utils.zip_write_add(&w, "mod.json", transmute([]byte)info(name, ""))
		utils.zip_write_end(&w)
	}
	zip(utils.temp_path(dir, "One.srmod"), "One")
	zip(utils.temp_path(dir, "two.zip"), "Two")
	zip(utils.temp_path(dir, "Kept.srmod"), "Kept")
	write(utils.temp_path(dir, "Kept", "mod.json"), info("Kept", "", version = "3.0.0"))
	write(utils.temp_path(dir, "junk.zip"), "not a zip")
	logger := context.logger
	context.logger.lowest_level = .Fatal // junk.zip's error is expected
	notes := res.mods_tidy(dir)
	context.logger = logger
	testing.expect_value(t, len(notes), 4)
	testing.expect(t, slice.equal(res.srmods_list(dir), []string{"Kept", "One", "Two"}), "One and Two unpacked, Kept kept")
	testing.expect_value(t, res.mod_version(dir, "Kept"), "3.0.0")
	for kept in ([]string{"One.srmod", "two.zip", "Kept.srmod"}) {
		testing.expectf(t, utils.file_exists(utils.temp_path(dir, ".old", kept)) && !os.exists(utils.temp_path(dir, kept)), "%s put aside", kept)
	}
	testing.expect(t, utils.file_exists(utils.temp_path(dir, "junk.zip")), "a zip of no mod left be")
}

// Classic, and two mods: the soldier and the weapons from one, the sounds from another
// that isn't there; each file the chosen mod's, else Classic's. A part asked of a mod
// without it is Classic's. The pivots: the chosen mod's over Classic's, a bad one passed
// over.
@(test)
worn :: proc(t: ^testing.T) {
	dir := scratch(t, "worn")
	defer os.remove_all(dir)
	classic := utils.temp_path(dir, "classic")
	write(utils.temp_path(classic, "mod.json"), info("classic", `"soldier", "weapons", "sounds"`))
	write(utils.temp_path(classic, "soldier", "klata.png"), "classic chest")
	write(utils.temp_path(classic, "soldier", "morda.png"), "classic head")
	write(utils.temp_path(classic, "soldier", "pivots.json"), `{"Chest": [0.1, 0.3], "Head": [0, 0.5]}`)
	write(utils.temp_path(classic, "weapons", "ak74.png"), "classic ak")
	write(utils.temp_path(classic, "sounds", "shot.wav"), "classic shot")
	mods := utils.temp_path(dir, "mods")
	write(utils.temp_path(mods, "Clean", "mod.json"), info("Clean", `"soldier", "weapons"`))
	write(utils.temp_path(mods, "Clean", "soldier", "Klata.PNG"), "clean chest")
	write(utils.temp_path(mods, "Clean", "soldier", "pivots.json"), `{"chest": [0.2, 0.4], "Bad": "x"}`)
	write(utils.temp_path(mods, "Clean", "weapons", "m79.png"), "clean m79")

	choice: [res.Part]string
	choice[.Soldier] = "Clean"
	choice[.Weapons] = "Clean"
	choice[.Sounds] = "Gone"
	choice[.Hud] = "Clean" // it has none
	w, ok := res.worn_make(classic, mods, choice)
	defer res.worn_close(&w)
	if !testing.expect(t, ok, "Classic and the mods worn") do return
	testing.expect_value(t, len(w.mods), 1)
	testing.expect(t, w.chosen[.Hud] == -1 && w.chosen[.Sounds] == -1, "a part a mod hasn't, and a mod not there: Classic's")

	got :: proc(w: ^res.Worn, part: res.Part, path: string) -> string {
		file, found := res.worn_file(w, part, path)
		return read(file) if found else ""
	}
	testing.expect_value(t, got(&w, .Soldier, "klata.png"), "clean chest")
	testing.expect_value(t, got(&w, .Soldier, "morda.png"), "classic head") // the mod's part hasn't it
	testing.expect_value(t, got(&w, .Weapons, "ak74.png"), "classic ak")
	testing.expect_value(t, got(&w, .Sounds, "shot.wav"), "classic shot")
	testing.expect_value(t, got(&w, .Soldier, "nothing.png"), "")
	testing.expect_value(t, res.worn_mod(&w, .Soldier).info.name, "Clean")

	testing.expect_value(t, res.worn_pivot(&w, .Soldier, "Chest", {}), [2]f32{0.2, 0.4})
	testing.expect_value(t, res.worn_pivot(&w, .Soldier, "head", {}), [2]f32{0, 0.5})
	testing.expect_value(t, res.worn_pivot(&w, .Soldier, "Bad", {9, 9}), [2]f32{9, 9})
	testing.expect_value(t, res.worn_pivot(&w, .Weapons, "Primary_Ak74", {0.15, 0.5}), [2]f32{0.15, 0.5})

	pivots := make(map[string][2]f32, context.temp_allocator)
	pivots["head"] = {0, 0.5}
	pivots["chest"] = {0.1, 0.3}
	testing.expect_value(t, res.pivots_text(pivots), "{\n  \"chest\": [0.1, 0.3],\n  \"head\": [0, 0.5]\n}\n")
}

// The game's own layout is the original default interface, and goes back to its
// setup.sif as it was; a layout written is read back the same; a partial one over another
// keeps what it leaves out, and a value its setting can't take.
@(test)
layout :: proc(t: ^testing.T) {
	own := res.hud_layout_default()
	testing.expect_value(t, res.hud_layout_setup(own), res.INTERFACE_DEFAULT)
	testing.expect(t, own.health.bar.fill == .Forward && own.fire.bar.fill == .Backward && own.bullets.align == .Right, "the game's own fills and alignment")
	testing.expect(t, own.fire.frame.at == {402, 464} && own.fire.bar.at == {409, 464}, "the fire bar's frame and bar, each at its own place")
	testing.expect(t, own.nades.anchor == .Ammo && own.vest.bar.anchor == .Health, "anchored as the original")

	text := res.hud_layout_text(own)
	testing.expect(t, strings.contains(text, `"anchor": "ammo"`) && strings.contains(text, `"style": "across"`), "the enums by their names")
	again := res.Hud_Layout{}
	testing.expect(t, res.hud_layout_read(transmute([]byte)text, "layout.json", &again), "read back")
	testing.expect_value(t, again, own)

	partial := own
	testing.expect(t, res.hud_layout_read(transmute([]byte)string(`{"alpha": 99, "jet": {"bar": {"style": "down", "fill": "sideways"}}, "status": {"shown": false}}`), "layout.json", &partial), "a partial layout")
	testing.expect(t, partial.alpha == 99 && partial.jet.bar.style == .Down && !partial.status.shown, "what it says taken")
	testing.expect(t, partial.jet.bar.fill == own.jet.bar.fill && partial.jet.icon == own.jet.icon && partial.health == own.health, "what it leaves out, and a fill that's no fill, as they were")
	broken := own
	logger := context.logger
	context.logger.lowest_level = .Fatal // the error is expected; the runner fails a test that logs one
	testing.expect(t, !res.hud_layout_read(transmute([]byte)string(`{"alpha": `), "layout.json", &broken) && broken == own, "not JSON: nothing taken")
	context.logger = logger

	// a custom interface's, its anchors and alignment written down
	custom := res.hud_layout_of(res.INTERFACE_DEFAULT, {health = .Ammo, jet = .Ammo, ammo = .Ammo, fire = .Ammo, nades = .Ammo}, custom = true)
	testing.expect(t, custom.health.bar.fill == .Backward && custom.ammo.reload_fill == .Forward && custom.weapon.align == .Left, "a custom interface's fills and alignment")
	testing.expect(t, custom.health.bar.anchor == .Ammo && custom.vest.bar.anchor == .Ammo, "anchored as it was")
}

// A layout worn: the game's own, under Classic's layout.json, under the chosen mod's.
@(test)
layout_worn :: proc(t: ^testing.T) {
	dir := scratch(t, "layout_worn")
	defer os.remove_all(dir)
	classic := utils.temp_path(dir, "classic")
	write(utils.temp_path(classic, "mod.json"), info("classic", `"hud"`))
	write(utils.temp_path(classic, "hud", "layout.json"), `{"alpha": 200, "ping": {"at": [10, 10]}}`)
	mods := utils.temp_path(dir, "mods")
	write(utils.temp_path(mods, "Tiny", "mod.json"), info("Tiny", `"hud"`))
	write(utils.temp_path(mods, "Tiny", "hud", "layout.json"), `{"alpha": 150, "team_box": {"at": [1, 2]}}`)

	choice: [res.Part]string
	w, _ := res.worn_make(classic, mods, choice)
	l := res.worn_layout(&w)
	testing.expect(t, l.alpha == 200 && l.ping.at == {10, 10} && l.team_box.at == {575, 330}, "Classic's over the game's own")
	res.worn_close(&w)

	choice[.Hud] = "Tiny"
	w, _ = res.worn_make(classic, mods, choice)
	defer res.worn_close(&w)
	l = res.worn_layout(&w)
	testing.expect(t, l.alpha == 150 && l.team_box.at == {1, 2} && l.ping.at == {10, 10}, "the mod's over Classic's")
}

// A HUD as the HUD editor saves it: the hud part's files of the mod it began from
// (srmod_part_files), its folder's or its .srmod's alike, and a mod of a hud alone written
// with them and a layout (hud_mod_write); saved again over itself, its description kept.
@(test)
hud_saved :: proc(t: ^testing.T) {
	dir := scratch(t, "hud_saved")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "Neo", "mod.json"), info("Neo", `"hud", "sounds"`))
	write(utils.temp_path(dir, "Neo", "hud", "health.png"), "neo health")
	write(utils.temp_path(dir, "Neo", "hud", "guns", "1.png"), "neo gun")
	write(utils.temp_path(dir, "Neo", "hud", "layout.json"), `{"alpha": 90}`)
	write(utils.temp_path(dir, "Neo", "sounds", "shot.wav"), "not the hud's")

	neo, why, ok := res.srmod_open(utils.temp_path(dir, "Neo"))
	if !testing.expectf(t, ok, "Neo opened (%s)", why) do return
	pictures := res.srmod_part_files(&neo, .Hud, context.temp_allocator)
	res.srmod_close(&neo)
	testing.expect_value(t, len(pictures), 3)
	testing.expect(t, string(pictures["health.png"]) == "neo health" && string(pictures["guns/1.png"]) == "neo gun", "its hud's files, in their folders, and no other part's")

	layout := res.hud_layout_default()
	layout.alpha = 120
	layout.health.icon.at = {50, 300}
	testing.expect(t, res.hud_mod_write(dir, "My_HUD", "My HUD", "Made in the HUD editor, from Neo's HUD.", layout, pictures), "written")
	mine, mwhy, mok := res.srmod_open(utils.temp_path(dir, "My_HUD"))
	defer res.srmod_close(&mine)
	if !testing.expectf(t, mok, "My_HUD opened (%s)", mwhy) do return
	testing.expect(t, mine.parts == {.Hud} && mine.info.title == "My HUD", "a hud alone")
	again := res.srmod_part_files(&mine, .Hud, context.temp_allocator)
	testing.expect(t, string(again["health.png"]) == "neo health" && string(again["guns/1.png"]) == "neo gun", "Neo's pictures in it")
	read_back := res.hud_layout_default()
	testing.expect(t, res.hud_layout_read(again["layout.json"], "layout.json", &read_back) && read_back == layout, "its layout, not Neo's")
	res.srmod_close(&mine)

	layout.alpha = 200
	testing.expect(t, res.hud_mod_write(dir, "My_HUD", "My HUD", mine_description(dir), layout, again), "saved over itself")
	over, _, _ := res.srmod_open(utils.temp_path(dir, "My_HUD"))
	defer res.srmod_close(&over)
	testing.expect(t, strings.has_prefix(over.info.description, res.HUD_EDITOR_MADE) && strings.contains(over.info.description, "Neo"), "the editor's, from Neo's still")

	mine_description :: proc(dir: string) -> string {
		m, _, _ := res.srmod_open(utils.temp_path(dir, "My_HUD"))
		defer res.srmod_close(&m) // let go of before it is written over
		return strings.clone(m.info.description, context.temp_allocator)
	}
}
