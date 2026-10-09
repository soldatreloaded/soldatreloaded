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

read :: proc(file: res.Mod_File) -> string {
	data, _ := res.mod_read(file, context.temp_allocator)
	return string(data)
}

// Classic, an .smod of art and a mod.ini, and a folder of sounds whose files are a
// folder down: each file is the top mod's that has it, else Classic's; each mod's images
// are sized by its own mod.ini, and the folder's, having none, by Classic's.
@(test)
stacked :: proc(t: ^testing.T) {
	dir := scratch(t, "stacked")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "classic", "gostek-gfx", "klata.png"), "classic chest")
	write(utils.temp_path(dir, "classic", "gostek-gfx", "morda.png"), "classic head")
	write(utils.temp_path(dir, "classic", "sfx", "shotgun.wav"), "classic shot")
	write(utils.temp_path(dir, "classic", "mod.ini"), "[SCALE]\nDefaultScale=4.5\n")
	write_zip(utils.temp_path(dir, "Art.smod"), {{"Art/Gostek-Gfx/KLATA.png", "art chest"}, {"Art/mod.ini", "[SCALE]\nDefaultScale=2\n"}, {"Art/readme.txt", "hi"}})
	write(utils.temp_path(dir, "Sounds", "Sounds v2", "sfx", "Shotgun.ogg"), "loud shot")
	write(utils.temp_path(dir, "Sounds", "Sounds v2", "gostek-gfx", "klata.png"), "sounds' chest")
	write(utils.temp_path(dir, "Empty", "readme.txt"), "nothing the game uses")

	mods := []string{"Art", "Sounds", "Missing"}
	mod := res.mod_make(dir, mods)
	defer res.mod_destroy(&mod)
	testing.expect_value(t, len(mod.layers), 3) // the missing one passed over, Classic last

	chest, found := res.mod_image(mod, "gostek-gfx", "klata.png")
	testing.expect(t, found && read(chest) == "art chest" && chest.layer == 0, "the top mod's, in any case, a folder down in its zip")
	head, _ := res.mod_image(mod, "gostek-gfx", "morda.png")
	testing.expect(t, read(head) == "classic head" && head.layer == 2, "Classic's where no mod has it")
	shot, heard := res.sound_file(mod, "shotgun.wav")
	testing.expect(t, heard && read(shot) == "loud shot" && shot.layer == 1, "a mod's .ogg over Classic's .wav, a folder down in the mod's folder")
	testing.expect(t, res.mod_has_image(mod, "gostek-gfx", "klata.png") && !res.mod_has_image(mod, "gostek-gfx", "morda.png"), "a mod over Classic has it, or not")

	testing.expect_value(t, mod.layers[0].config.scale.default, f32(2))
	testing.expect(t, mod.layers[1].config == mod.layers[2].config, "a mod without a mod.ini sized by Classic's")
	testing.expect_value(t, mod.layers[2].config.scale.default, f32(4.5))

	// the order is the player's: the folder on top, its chest is worn
	swapped := res.mod_make(dir, []string{"Sounds", "Art"})
	defer res.mod_destroy(&swapped)
	chest, _ = res.mod_image(swapped, "gostek-gfx", "klata.png")
	testing.expect(t, read(chest) == "sounds' chest" && chest.layer == 0, "the top one's, whichever it is")
}

// mods/ listed: Classic left out, each .smod and folder by name, with what it changes,
// and where its files were found if not at its root.
@(test)
listed :: proc(t: ^testing.T) {
	dir := scratch(t, "listed")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "classic", "mod.ini"), "")
	write_zip(utils.temp_path(dir, "Art.smod"), {{"Art/weapons-gfx/ak74.png", "gun"}, {"Art/mod.ini", ""}, {"Art/about.json", `{"name": "Art", "title": "Art and More", "version": "1.2.0"}`}})
	write(utils.temp_path(dir, "Sounds", "sfx", "shotgun.wav"), "shot")
	write(utils.temp_path(dir, "Empty", "readme.txt"), "nothing the game uses")
	write(utils.temp_path(dir, ".Half.part"), "an install under way")

	listings := res.mods_list(dir)
	defer res.mods_list_destroy(listings)
	names := make([dynamic]string, context.temp_allocator)
	for l in listings do append(&names, l.name)
	testing.expect(t, slice.equal(names[:], []string{"Art", "Empty", "Sounds"}), "the players' mods, by name, Classic and what is being installed left out")
	testing.expect(t, listings[0].packed && listings[0].contents == {.Graphics, .Config} && listings[0].nested == "Art/", "an .smod: its art and its mod.ini, a folder down")
	testing.expect(t, listings[1].contents == {}, "a folder of nothing the game uses, said so")
	testing.expect(t, !listings[2].packed && listings[2].contents == {.Sounds} && listings[2].nested == "", "a folder of sounds")
	testing.expect_value(t, res.mod_version(dir, "Art"), "1.2.0")
	testing.expect(t, listings[0].title == "Art and More" && listings[2].title == "Sounds", "shown by its about.json's title, else its name")

	testing.expect(t, res.mod_name_problem(dir, "art") != "", "a name taken, in any case, by an .smod")
	testing.expect(t, res.mod_delete(dir, "Art") && !os.exists(utils.temp_path(dir, "Art.smod")), "an .smod deleted")
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
	write(utils.temp_path(mods_dir, "classic", "gostek-gfx", "klata.png"), chest_png)
	write(utils.temp_path(mods_dir, "classic", "gostek-gfx", "biodro.png"), belt_png)
	write(utils.temp_path(mods_dir, "classic", "gostek-gfx", "morda.png"), head_png)
	write(utils.temp_path(mods_dir, "classic", "sfx", "spas12-fire.wav"), "classic shotgun")
	classic := res.mod_make(mods_dir, nil)
	defer res.mod_destroy(&classic)

	write(utils.temp_path(soldat, "soldat.exe"), "")
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
	testing.expect_value(t, result.changed, 2)

	z, opened := utils.zip_open(utils.temp_path(mods_dir, "Mine.smod"))
	defer utils.zip_close(&z)
	testing.expect(t, opened, "an .smod made")
	names := make([dynamic]string, context.temp_allocator)
	for name in z.entries do append(&names, name)
	slice.sort(names[:])
	testing.expect(t, slice.equal(names[:], []string{"gostek-gfx/morda.bmp", "mod.ini", "sfx/spas12-fire.wav"}), "what differs, and its mod.ini")

	worn := res.mod_make(mods_dir, []string{"Mine"})
	defer res.mod_destroy(&worn)
	shot, _ := res.sound_file(worn, "spas12-fire.wav")
	testing.expect(t, read(shot) == "my shotgun", "worn as any mod is")
	head, _ := res.mod_image(worn, "gostek-gfx", "morda.png")
	testing.expect(t, head.layer == 0 && worn.layers[0].config.anchors["head_centerx"] == 0.6, "its head, a .bmp where a .png is asked for, pinned by its own mod.ini")

	again := res.mod_import({soldat}, mods_dir, "Mine", classic)
	testing.expect(t, again.problem != "", "not over a mod by that name")
	stock := res.mod_import({utils.temp_path(dir, "nothing")}, mods_dir, "Other", classic)
	testing.expect(t, stock.problem != "", "nor from a folder that isn't Soldat's")
}

// A Soldat install found from any folder of it or in it; what a mod can be made from in
// it, its own folders and each mod of its mods/, the one it was last played with marked;
// and a mod of mods/ made with the changes to its own folders under it, the mod's own
// over them.
@(test)
soldat_sources :: proc(t: ^testing.T) {
	dir := scratch(t, "sources")
	defer os.remove_all(dir)
	soldat := utils.temp_path(dir, "Games", "Soldat")
	mods_dir := utils.temp_path(dir, "mods")
	write(utils.temp_path(mods_dir, "classic", "gostek-gfx", "klata.png"), picture(1, 27, 18))
	write(utils.temp_path(mods_dir, "classic", "gostek-gfx", "morda.png"), picture(2, 27, 18))
	write(utils.temp_path(mods_dir, "classic", "sfx", "spas12-fire.wav"), "classic shotgun")
	write(utils.temp_path(mods_dir, "classic", "sfx", "ak74-fire.wav"), "classic ak")
	classic := res.mod_make(mods_dir, nil)
	defer res.mod_destroy(&classic)

	write(utils.temp_path(soldat, "soldat.exe"), "")
	write(utils.temp_path(soldat, "soldat.ini"), "[GAME]\nLast_Mod=Loud\n")
	write(utils.temp_path(soldat, "gostek-gfx", "klata.png"), picture(3, 27, 18)) // its own chest, put over the game's
	write(utils.temp_path(soldat, "sfx", "spas12-fire.wav"), "own shotgun")
	write(utils.temp_path(soldat, "maps", "ctf_Ash.pms"), "a map, never a mod's")
	write(utils.temp_path(soldat, "mods", "Loud", "sfx", "spas12-fire.wav"), "loud shotgun")
	write(utils.temp_path(soldat, "mods", "Loud", "sfx", "ak74-fire.wav"), "loud ak")
	write(utils.temp_path(soldat, "mods", "Plain", "gostek-gfx", "morda.png"), picture(2, 27, 18)) // the game's head again
	write(utils.temp_path(soldat, "mods", "Notes", "readme.txt"), "not a mod")

	root, in_mod, found := res.soldat_root(utils.temp_path(soldat, "mods", "Loud", "sfx"), context.temp_allocator)
	testing.expect(t, found && strings.has_suffix(root, "Games/Soldat") && in_mod == "Loud", "found from a folder of a mod of it")
	root, in_mod, found = res.soldat_root(utils.temp_path(soldat, "gostek-gfx"), context.temp_allocator)
	testing.expect(t, found && in_mod == "", "and from a folder of its own")
	_, _, found = res.soldat_root(mods_dir, context.temp_allocator)
	testing.expect(t, !found, "not from a folder that isn't in one")

	sources := res.soldat_sources(root, classic)
	defer res.soldat_sources_destroy(sources)
	testing.expect_value(t, len(sources), 3)
	testing.expect(t, sources[0].name == "" && sources[0].changed == 2, "its own folders: its chest and its shotgun")
	testing.expect(t, sources[1].name == "Loud" && sources[1].changed == 2 && sources[1].in_use, "a mod of its mods/, the one last played")
	testing.expect(t, sources[2].name == "Plain" && sources[2].changed == 0 && !sources[2].in_use, "a mod of nothing changed")

	result := res.mod_import({sources[0].dir, sources[1].dir}, utils.temp_path(dir, "made"), "Loud", classic)
	testing.expect_value(t, result.problem, "")
	testing.expect_value(t, result.changed, 3)
	worn := res.mod_make(utils.temp_path(dir, "made"), {"Loud"})
	defer res.mod_destroy(&worn)
	shot, _ := res.sound_file(worn, "spas12-fire.wav")
	chest, _ := res.mod_image(worn, "gostek-gfx", "klata.png")
	testing.expect(t, read(shot) == "loud shotgun" && chest.layer == 0, "the mod's own over its own folders', and theirs under it")
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

// A mod's art is drawn at the scale its mod.ini gives it, whatever its size: an old
// mod's small art, from before Soldat 1.6 drew it finer, at its DefaultScale, as nothing
// is guessed from its size; a mod.ini that sizes its folder, as it says.
@(test)
scale_as_the_mod_ini_says :: proc(t: ^testing.T) {
	dir := scratch(t, "scale_as_said")
	defer os.remove_all(dir)
	parts := []string{"klata.png", "morda.png", "noga.png", "udo.png"}
	for name, i in parts {
		write(utils.temp_path(dir, "classic", "gostek-gfx", name), picture(u8(i), 27, 18))
		write(utils.temp_path(dir, "Old", "gostek-gfx", name), picture(u8(i), 6, 4))
		write(utils.temp_path(dir, "Said", "gostek-gfx", name), picture(u8(i), 6, 4))
	}
	write(utils.temp_path(dir, "classic", "mod.ini"), "[SCALE]\nDefaultScale=4.5\n")
	write(utils.temp_path(dir, "Old", "mod.ini"), "[SCALE]\nDefaultScale=4.5\n")
	write(utils.temp_path(dir, "Said", "mod.ini"), "[SCALE]\nDefaultScale=4.5\ngostek-gfx=1\n")

	mod := res.mod_make(dir, []string{"Old", "Said"})
	defer res.mod_destroy(&mod)
	scale, set := res.mod_scale(mod, 0, "gostek-gfx/klata.png")
	testing.expect(t, !set && scale == 4.5, "an old mod's small art is drawn at its DefaultScale")
	scale, set = res.mod_scale(mod, 1, "gostek-gfx/klata.png")
	testing.expect(t, set && scale == 1, "and a mod.ini that sizes its folder, as it says")
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
