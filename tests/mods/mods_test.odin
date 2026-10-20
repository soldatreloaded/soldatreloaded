package mods_test

// The mods as the game wears them (core/resources/mod.odin): a stack of .smods and
// folders over Classic, each file the top one's that has it, each mod's images sized by
// its own mod.ini, or Classic's; a mod's files found a folder down where a zip put them;
// the mods listed, with what each changes. And a mod made from a Soldat 1.7.1 install
// (mod_import.odin): only what differs from Classic, an image by its pixels, goes in.
//
//   odin test tests/mods

import "base:runtime"
import "core:c"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import res "../../core/resources"
import "../../core/utils"

import stbi "vendor:stb/image"

// A folder of its own for a test, empty, in the system's temp folder.
scratch :: proc(t: ^testing.T, name: string) -> string {
	dir := utils.temp_path(os.get_env("TEMP", context.temp_allocator) if ODIN_OS == .Windows else "/tmp", strings.concatenate({"soldatreloaded_mods_test_", name}, context.temp_allocator))
	os.remove_all(dir)
	testing.expect(t, os.make_directory_all(dir) == nil, "a scratch folder")
	return dir
}

write :: proc(path: string, data: string) {
	os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	utils.write_file(path, transmute([]byte)data)
}

// A zip of `files`, by their names in it.
write_zip :: proc(path: string, files: []struct {
		name, data: string,
	}) {
	w: utils.Zip_Writer
	utils.zip_write_begin(&w, path)
	for f in files do utils.zip_write_add(&w, f.name, transmute([]byte)f.data)
	utils.zip_write_end(&w)
}

// Every file below `dir`, by its path from it with forward slashes, sorted.
files_in :: proc(dir: string) -> []string {
	files := make([dynamic]string, context.temp_allocator)
	walk :: proc(files: ^[dynamic]string, dir, below: string) {
		entries, _ := os.read_all_directory_by_path(utils.temp_path(dir, below) if below != "" else dir, context.temp_allocator)
		for entry in entries {
			path := strings.concatenate({below, "/", entry.name}, context.temp_allocator) if below != "" else entry.name
			if entry.type == .Directory do walk(files, dir, path)
			else do append(files, path)
		}
	}
	walk(&files, dir, "")
	slice.sort(files[:])
	return files[:]
}

read :: proc(file: res.Mod_File) -> string {
	data, _ := res.mod_read(file, context.temp_allocator)
	return string(data)
}

// Mods of before, as the game starts: an .smod (its files a folder down, its about.json,
// its mod.ini's scales) and a folder of sounds and fonts, each converted whole into a mod
// of now, its parts by Soldat 1's folders, its images as they were at their scales
// (Classic's 4.5 where its mod.ini said none), its about.json its mod.json; each put aside
// in .old/. A folder of nothing the game uses, and Classic, left be; a name taken, said.
@(test)
converted :: proc(t: ^testing.T) {
	dir := scratch(t, "converted")
	defer os.remove_all(dir)
	write_classic(dir, {{"soldier/klata.png", picture(1)}, {"sounds/shot.wav", "classic shot"}, {"fonts/font.ini", "[FONTS]\n"}})
	write_zip(utils.temp_path(dir, "Art.smod"), {
		{"Art/weapons-gfx/ak74.png", picture(2)},
		{"Art/gostek-gfx/klata.png", picture(3, 12, 8)},
		{"Art/mod.ini", "[SCALE]\nDefaultScale=2\ngostek-gfx=9\n"},
		{"Art/about.json", `{"name": "Art", "title": "Art and More", "version": "1.2.0", "author": "Me", "description": "Shiny guns.", "licence": "CC0"}`},
	})
	write(utils.temp_path(dir, "Loud Sounds", "sfx", "shot.wav"), "loud shot")
	write(utils.temp_path(dir, "Loud Sounds", "txt", "font.ini"), "[FONTS]\nFont1File=big.ttf\n")
	write(utils.temp_path(dir, "Loud Sounds", "fonts", "big.ttf"), "a font")
	write(utils.temp_path(dir, "Loud Sounds", "txt", "weaponnames.txt"), "not the fonts'")
	write(utils.temp_path(dir, "Empty", "readme.txt"), "nothing the game uses")
	write_zip(utils.temp_path(dir, "Taken.smod"), {{"sfx/shot.wav", "x"}})
	write(utils.temp_path(dir, "Taken", "mod.json"), `{"format": 1, "name": "Taken", "version": "1.0.0"}`)

	notes := res.mods_tidy(dir)
	testing.expectf(t, len(notes) == 3, "three said: %v", notes)
	testing.expect(t, slice.equal(res.srmods_list(dir), []string{"Art", "Loud_Sounds", "Taken"}), "Art and Loud Sounds converted, named as mods may be")

	art, why, ok := res.srmod_open(utils.temp_path(dir, "Art"))
	defer res.srmod_close(&art)
	if !testing.expectf(t, ok, "Art opens (%s)", why) do return
	testing.expect(t, art.info.title == "Art and More" && art.info.version == "1.2.0" && art.info.author == "Me" && art.info.licence == "CC0" && art.info.description == "Shiny guns.", "its about.json its mod.json")
	testing.expect_value(t, art.parts, res.Parts{.Soldier, .Weapons})
	testing.expect_value(t, res.srmod_scale(&art, "weapons/ak74.png"), 2)
	testing.expect_value(t, res.srmod_scale(&art, "soldier/klata.png"), 9)
	chest, _ := res.srmod_file(&art, .Soldier, "klata.png")
	image, decoded := res.texture_decode(transmute([]byte)read(chest), nil, context.temp_allocator)
	testing.expect(t, decoded && image.width == 12 && image.height == 8, "its pixels as they were")

	loud, lwhy, lok := res.srmod_open(utils.temp_path(dir, "Loud_Sounds"))
	defer res.srmod_close(&loud)
	if !testing.expectf(t, lok, "Loud Sounds opens (%s)", lwhy) do return
	testing.expect_value(t, loud.parts, res.Parts{.Sounds, .Fonts})
	font, has_font := res.srmod_file(&loud, .Fonts, "big.ttf")
	ini, has_ini := res.srmod_file(&loud, .Fonts, "font.ini")
	testing.expect(t, has_font && read(font) == "a font" && has_ini && strings.contains(read(ini), "big.ttf"), "its fonts and its font.ini")
	_, names := res.srmod_file(&loud, .Fonts, "weaponnames.txt")
	testing.expect(t, !names, "no other of txt/")

	for kept in ([]string{"Art.smod", "Loud Sounds", "Taken.smod"}) do testing.expectf(t, os.exists(utils.temp_path(dir, ".old", kept)), "%s put aside", kept)
	testing.expect(t, os.is_dir(utils.temp_path(dir, "Empty")) && !os.exists(utils.temp_path(dir, ".converting")), "a folder of nothing left be, nothing left half made")
	testing.expect_value(t, res.mod_version(dir, "Taken"), "1.0.0")

	testing.expect(t, res.mod_name_problem(dir, "art") != "", "a name taken, in any case, by a folder")
	testing.expect(t, res.mod_delete(dir, "Art") && !os.exists(utils.temp_path(dir, "Art")), "a mod's folder deleted")
}

// A zip of a Soldat 1 mod, with no mod.json, unpacked (as the catalogue's of before are,
// and a zip dropped on the game): converted, named as asked, over the one there with
// replace.
@(test)
zipped_soldat_mod :: proc(t: ^testing.T) {
	dir := scratch(t, "zipped_soldat_mod")
	defer os.remove_all(dir)
	mods := utils.temp_path(dir, "mods")
	write_classic(mods, {{"sounds/shot.wav", "classic shot"}})
	zip := utils.temp_path(dir, "download")
	write_zip(zip, {{"Competitive/sfx/shot.wav", "quiet"}, {"Competitive/about.json", `{"title": "Competitive", "version": "2.0.0"}`}})
	name, problem := res.mod_unpack(zip, mods, name = "Competitive", allocator = context.temp_allocator)
	testing.expectf(t, problem == "" && name == "Competitive", "converted (%s)", problem)
	testing.expect_value(t, res.mod_version(mods, "Competitive"), "2.0.0")
	write_zip(zip, {{"Competitive/sfx/shot.wav", "quieter"}, {"Competitive/about.json", `{"version": "2.1.0"}`}})
	_, again := res.mod_unpack(zip, mods, name = "Competitive", replace = true, allocator = context.temp_allocator)
	testing.expect(t, again == "" && res.mod_version(mods, "Competitive") == "2.1.0", "updated over itself")
	shot, _ := utils.read_file(utils.temp_path(mods, "Competitive", "sounds", "shot.wav"), context.temp_allocator)
	testing.expect_value(t, string(shot), "quieter")
}

// A mod made from a Soldat install: only what differs from Classic goes in, an image by
// its pixels as the game draws it, so Classic's own picture as the original's green-keyed
// .bmp is left out; its mod.ini goes in; and the mod made is an .smod the game reads.
@(test)
imported :: proc(t: ^testing.T) {
	dir := scratch(t, "imported")
	defer os.remove_all(dir)
	soldat := utils.temp_path(dir, "Soldat")
	mods_dir := utils.temp_path(dir, "mods")
	// a Classic of a chest, a belt and a head, see-through about them, and a shot
	chest_png, belt_png, head_png := picture(1), picture(2), picture(3)
	write_classic(mods_dir, {{"soldier/klata.png", chest_png}, {"soldier/biodro.png", belt_png}, {"soldier/morda.png", head_png}, {"soldier/pivots.json", `{"Head": [0, 0.5]}`}, {"sounds/spas12-fire.wav", "classic shotgun"}})
	classic := res.mod_make(mods_dir)
	defer res.mod_destroy(&classic)

	write(utils.temp_path(soldat, "mod.ini"), "[GOSTEK]\nHead_CenterX=0.6\n")
	// Classic's chest as it is, and its belt as the original's .bmp: the same pictures
	write(utils.temp_path(soldat, "gostek-gfx", "klata.png"), chest_png)
	write(utils.temp_path(soldat, "gostek-gfx", "biodro.bmp"), as_bitmap(t, belt_png))
	// the player's own head, and a sound; and a file Classic hasn't, never asked for
	write(utils.temp_path(soldat, "gostek-gfx", "morda.bmp"), as_bitmap(t, chest_png))
	write(utils.temp_path(soldat, "sfx", "spas12-fire.wav"), "my shotgun")
	write(utils.temp_path(soldat, "sfx", "flamer.wav"), "a gun this game hasn't")

	testing.expect(t, res.soldat_is_install(soldat), "a Soldat folder")
	result := res.mod_import({soldat}, mods_dir, "Mine", classic)
	testing.expect_value(t, result.problem, "")
	testing.expect_value(t, result.changed, 3) // its head, its shotgun, and its head's pivot

	testing.expect(t, os.is_dir(utils.temp_path(mods_dir, "Mine")), "a mod's folder made")
	testing.expect(t, slice.equal(files_in(utils.temp_path(mods_dir, "Mine")), []string{"mod.json", "soldier/morda.png", "soldier/pivots.json", "sounds/spas12-fire.wav"}), "what differs, by part")

	// worn: its head a PNG as it was, at 1 (it had no mod.ini's scale), its green
	// see-through; its shotgun; its head pinned where its mod.ini said, the half it didn't
	// say Classic's
	choice: [res.Part]string
	choice[.Soldier], choice[.Sounds] = "Mine", "Mine"
	worn := res.mod_make(mods_dir, choice)
	defer res.mod_destroy(&worn)
	head, found := res.mod_image(worn, "gostek-gfx", "morda.png")
	data, _ := res.mod_read(head, context.temp_allocator)
	image, decoded := res.texture_decode(data, nil, context.temp_allocator)
	testing.expect(t, found && decoded && image.width == 6 && image.height == 4, "its head, its pixels as they were")
	testing.expect_value(t, head.scale, 1) // its install had no mod.ini: Soldat 1 drew it at 1, and so does its mod
	testing.expect(t, decoded && image.pixels[0].a == 0 && image.pixels[2 * 6 + 2] == {60, 100, 200, 255}, "see-through where it was green, its colour where it wasn't")
	shot, _ := res.sound_file(worn, "spas12-fire.wav")
	testing.expect_value(t, read(shot), "my shotgun")
	testing.expect_value(t, res.worn_pivot(worn.worn, .Soldier, "Head", {}), [2]f32{0.6, 0.5})

	again := res.mod_import({soldat}, mods_dir, "Mine", classic)
	testing.expect(t, again.problem != "", "not over a mod by that name")
	stock := res.mod_import({utils.temp_path(dir, "nothing")}, mods_dir, "Other", classic)
	testing.expect(t, stock.problem != "", "nor from a folder that isn't Soldat's")
}

// What a mod can be made from in a Soldat install: its own folders and each mod of its
// mods/, the one it was last played with marked; and a mod of mods/ made with the
// changes to its own folders under it, the mod's own over them.
@(test)
soldat_sources :: proc(t: ^testing.T) {
	dir := scratch(t, "sources")
	defer os.remove_all(dir)
	soldat := utils.temp_path(dir, "Games", "Soldat")
	mods_dir := utils.temp_path(dir, "mods")
	write_classic(mods_dir, {{"soldier/klata.png", picture(1, 27, 18)}, {"soldier/morda.png", picture(2, 27, 18)}, {"sounds/spas12-fire.wav", "classic shotgun"}, {"sounds/ak74-fire.wav", "classic ak"}})
	classic := res.mod_make(mods_dir)
	defer res.mod_destroy(&classic)

	write(utils.temp_path(soldat, "soldat.ini"), "[GAME]\nLast_Mod=Loud\n")
	write(utils.temp_path(soldat, "gostek-gfx", "klata.png"), picture(3, 27, 18)) // its own chest, put over the game's
	write(utils.temp_path(soldat, "sfx", "spas12-fire.wav"), "own shotgun")
	write(utils.temp_path(soldat, "maps", "ctf_Ash.pms"), "a map, never a mod's")
	write(utils.temp_path(soldat, "mods", "Loud", "sfx", "spas12-fire.wav"), "loud shotgun")
	write(utils.temp_path(soldat, "mods", "Loud", "sfx", "ak74-fire.wav"), "loud ak")
	write(utils.temp_path(soldat, "mods", "Plain", "gostek-gfx", "morda.png"), picture(2, 27, 18)) // the game's head again
	write(utils.temp_path(soldat, "mods", "Notes", "readme.txt"), "not a mod")

	sources := res.soldat_sources(soldat, classic)
	defer res.soldat_sources_destroy(sources)
	testing.expect_value(t, len(sources), 3)
	testing.expect(t, sources[0].name == "" && sources[0].changed == 2, "its own folders: its chest and its shotgun")
	testing.expect(t, sources[1].name == "Loud" && sources[1].changed == 2 && sources[1].in_use, "a mod of its mods/, the one last played")
	testing.expect(t, sources[2].name == "Plain" && sources[2].changed == 1 && !sources[2].in_use, "a mod of mods/ whole, though its head is Classic's again")

	result := res.mod_import({sources[0].dir, sources[1].dir}, utils.temp_path(dir, "made"), "Loud", classic)
	testing.expect_value(t, result.problem, "")
	testing.expect_value(t, result.changed, 3)
	loud := utils.temp_path(dir, "made", "Loud")
	shot, _ := utils.read_file(utils.temp_path(loud, "sounds", "spas12-fire.wav"), context.temp_allocator)
	chest := utils.file_exists(utils.temp_path(loud, "soldier", "klata.png"))
	testing.expect(t, string(shot) == "loud shotgun" && chest, "the mod's own over its own folders', and theirs under it")
}

// A .png of `w` by `h`: a block of colour `shade` in the middle, see-through about it.
picture :: proc(shade: u8, w := 6, h := 4) -> string {
	pixels := make([]utils.Rgba, w * h, context.temp_allocator)
	for &p, i in pixels {
		x, y := i % w, i / w
		if x > 0 && x < w - 1 && y > 0 && y < h - 1 do p = {shade * 60, 100, 200, 255}
	}
	out := make([dynamic]byte, context.temp_allocator)
	stbi.write_png_to_func(proc "c" (ctx: rawptr, data: rawptr, size: c.int) {
		context = runtime.default_context()
		append((^[dynamic]byte)(ctx), ..([^]byte)(data)[:size])
	}, &out, c.int(w), c.int(h), 4, raw_data(pixels), c.int(w * 4))
	return string(out[:])
}


// Classic laid out as a .srmod folder: its mod.json, of every part, and `files` by their
// paths in it.
write_classic :: proc(mods_dir: string, files: [][2]string) {
	write(utils.temp_path(mods_dir, "classic", "mod.json"), `{"format": 1, "name": "classic", "version": "1.0.0", "parts": ["soldier", "weapons", "effects", "objects", "hud", "icons", "sounds", "textures", "scenery", "fonts", "text"]}`)
	for f in files do write(utils.temp_path(mods_dir, "classic", f[0]), f[1])
}

// The game asks for a file by Soldat 1's path, and finds it in the part that holds it:
// the chosen mod's, else Classic's; and Classic's alone, asked of Classic.
@(test)
by_part :: proc(t: ^testing.T) {
	dir := scratch(t, "by_part")
	defer os.remove_all(dir)
	write_classic(dir, {
		{"soldier/klata.png", "classic chest"},
		{"soldier/morda.png", "classic head"},
		{"weapons/icons/1.png", "classic icon"},
		{"hud/health.png", "classic health"},
		{"icons/cursor.png", "classic cursor"},
		{"objects/textures/flag.png", "classic cloth"},
		{"fonts/font.ini", "[FONTS]"},
		{"sounds/shotgun.wav", "classic shot"},
	})
	write(utils.temp_path(dir, "Art", "mod.json"), `{"format": 1, "name": "Art", "version": "1.0.0", "parts": ["soldier", "sounds"]}`)
	write(utils.temp_path(dir, "Art", "soldier", "KLATA.png"), "art chest")
	write(utils.temp_path(dir, "Art", "sounds", "Shotgun.ogg"), "loud shot")

	choice: [res.Part]string
	choice[.Soldier] = "Art"
	choice[.Sounds] = "Art"
	mod := res.mod_make(dir, choice)
	defer res.mod_destroy(&mod)
	if !testing.expect(t, mod.worn != nil, "Classic and Art worn") do return

	got :: proc(file: res.Mod_File, found: bool) -> string {return read(file) if found else ""}
	chest, found := res.mod_image(mod, "gostek-gfx", "klata.png")
	testing.expect(t, found && read(chest) == "art chest" && chest.layer == int(res.Part.Soldier), "the chosen mod's, in any case, of the soldier")
	testing.expect_value(t, got(res.mod_image(mod, "gostek-gfx", "morda.png")), "classic head")
	testing.expect_value(t, got(res.sound_file(mod, "shotgun.wav")), "loud shot")
	testing.expect_value(t, got(res.mod_image(mod, "interface-gfx/guns", "1.png")), "classic icon")
	testing.expect_value(t, got(res.mod_image(mod, "interface-gfx", "health.png")), "classic health")
	testing.expect_value(t, got(res.mod_image(mod, "interface-gfx", "cursor.png")), "classic cursor")
	testing.expect_value(t, got(res.mod_image(mod, "textures/objects", "flag.bmp")), "classic cloth")
	testing.expect_value(t, got(res.mod_file(mod, "txt/font.ini")), "[FONTS]")
	testing.expect(t, res.mod_has_image(mod, "gostek-gfx", "klata.png") && !res.mod_has_image(mod, "gostek-gfx", "morda.png"), "a chosen mod has it, or not")

	classic := res.mod_classic(mod)
	testing.expect_value(t, got(res.mod_image(classic, "gostek-gfx", "klata.png")), "classic chest")
	testing.expect(t, !res.mod_has_image(classic, "gostek-gfx", "klata.png"), "Classic is no mod over itself")
}

// A .png's picture as the original keeps one: a 24-bit .bmp, pure green where it is
// see-through.
as_bitmap :: proc(t: ^testing.T, png: string) -> string {
	image, decoded := res.texture_decode(transmute([]byte)png, nil, context.temp_allocator)
	testing.expect(t, decoded, "Classic's image decoded")
	row := (image.width * 3 + 3) &~ 3
	size := 54 + row * image.height
	b := make([]byte, size, context.temp_allocator)
	put :: proc(b: []byte, at: int, v: u32, n: int) {
		for i in 0 ..< n do b[at + i] = u8(v >> (8 * u32(i)))
	}
	b[0], b[1] = 'B', 'M'
	put(b, 2, u32(size), 4)
	put(b, 10, 54, 4)
	put(b, 14, 40, 4)
	put(b, 18, u32(image.width), 4)
	put(b, 22, u32(image.height), 4)
	put(b, 26, 1, 2)
	put(b, 28, 24, 2)
	for y in 0 ..< image.height {
		for x in 0 ..< image.width {
			p := image.pixels[y * image.width + x]
			if p.a == 0 do p = {0, 255, 0, 255}
			at := 54 + (image.height - 1 - y) * row + x * 3
			b[at], b[at + 1], b[at + 2] = p.b, p.g, p.r
		}
	}
	return string(b)
}
