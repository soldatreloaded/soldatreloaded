package interfaces_test

// Soldat 1's custom interfaces (core/resources/interface.odin): setup.sif read and written
// byte for byte as the original lays its TInterface out; an interface opened from its
// folder or its .sint, its pictures found and sized by its own mod.ini; and its parts
// anchored as the original anchors them.
//
//   odin test tests/interfaces

import "core:encoding/endian"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import res "../../core/resources"
import "../../core/utils"

scratch :: proc(t: ^testing.T, name: string) -> string {
	dir := utils.temp_path(os.get_env("TEMP", context.temp_allocator) if ODIN_OS == .Windows else "/tmp", strings.concatenate({"soldatreloaded_interfaces_test_", name}, context.temp_allocator))
	os.remove_all(dir)
	testing.expect(t, os.make_directory_all(dir) == nil, "a scratch folder")
	return dir
}

write :: proc(path: string, data: []byte) {
	os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	utils.write_file(path, data)
}

// A setup.sif made by hand, at the offsets the original's record has its fields: what is
// read is what was put there, and written back it is the same bytes.
@(test)
setup_byte_for_byte :: proc(t: ^testing.T) {
	data := make([]byte, res.INTERFACE_SETUP_SIZE, context.temp_allocator)
	put :: proc(data: []byte, at: int, v: i32) {endian.put_i32(data[at:], .Little, v)}
	data[0] = 128 // Alpha
	for i in 1 ..= 11 do data[i] = 1
	data[3] = 0 // Vest
	put(data, 12, 7); put(data, 16, 400); put(data, 20, 15) // HealthIco X, Y, Rotate
	put(data, 24, 50); put(data, 28, 410); put(data, 32, 100); put(data, 36, 8) // HealthBar X, Y, Width, Height
	data[40] = 2 // HealthBar_Pos: vertical
	put(data, 44, 90) // HealthBar_Rotate
	put(data, 60, 360) // AmmoBar_X
	data[76] = 0 // AmmoBar_Pos: text
	put(data, 144, 300); put(data, 148, 460) // Nades X, Y
	data[160] = 2 // Nades_Pos
	put(data, 164, 340); put(data, 168, 450) // Bullets
	put(data, 172, 280); put(data, 176, 452) // Weapon
	put(data, 180, 410); put(data, 188, 30) // FireIco X, Rotate
	put(data, 192, 401) // FireBar_X
	put(data, 216, 570); put(data, 220, 320) // TeamBox
	put(data, 224, 600); put(data, 228, 20) // Ping
	put(data, 232, 571); put(data, 236, 422) // Status

	setup, ok := res.interface_setup_read(data)
	testing.expect(t, ok, "read")
	testing.expect_value(t, setup.alpha, 128)
	testing.expect_value(t, setup.shown, ~res.Interface_Parts{} - {.Vest})
	testing.expect_value(t, setup.health_icon, res.Interface_Icon{at = {7, 400}, rotate = 15})
	testing.expect_value(t, setup.health_bar, res.Interface_Bar{at = {50, 410}, size = {100, 8}, style = .Vertical, rotate = 90})
	testing.expect_value(t, setup.ammo_bar.at.x, 360)
	testing.expect_value(t, setup.ammo_bar.style, res.Bar_Style.Text)
	testing.expect_value(t, setup.nades.at, [2]i32{300, 460})
	testing.expect_value(t, setup.nades.style, res.Bar_Style.Vertical)
	testing.expect_value(t, setup.bullets, [2]i32{340, 450})
	testing.expect_value(t, setup.weapon, [2]i32{280, 452})
	testing.expect_value(t, setup.fire_icon, res.Interface_Icon{at = {410, 0}, rotate = 30})
	testing.expect_value(t, setup.fire_bar.at.x, 401)
	testing.expect_value(t, setup.team_box, [2]i32{570, 320})
	testing.expect_value(t, setup.ping, [2]i32{600, 20})
	testing.expect_value(t, setup.status, [2]i32{571, 422})
	testing.expect(t, slice.equal(res.interface_setup_write(setup), data), "written back, the same bytes")

	_, short := res.interface_setup_read(data[:239])
	testing.expect(t, !short, "too few bytes aren't one")
	again, _ := res.interface_setup_read(res.interface_setup_write(res.INTERFACE_DEFAULT))
	testing.expect_value(t, again, res.INTERFACE_DEFAULT)
}

// An interface in its folder, a folder down where it was unpacked, and one in a .sint:
// both listed, each opened with its layout, its pictures its own and sized by its
// mod.ini (1 where it doesn't say), the rest none of its; one without a setup.sif, and
// none at all, the game's own.
@(test)
opened :: proc(t: ^testing.T) {
	dir := scratch(t, "opened")
	defer os.remove_all(dir)
	setup := res.INTERFACE_DEFAULT
	setup.alpha = 99
	sif := res.interface_setup_write(setup)
	write(utils.temp_path(dir, "Neo", "Neo", "setup.sif"), sif)
	write(utils.temp_path(dir, "Neo", "Neo", "Health.BMP"), transmute([]byte)string("bmp"))
	write(utils.temp_path(dir, "Neo", "Neo", "mod.ini"), transmute([]byte)string("[SCALE]\nDefaultScale=2\nhealth.bmp=3\n"))
	w: utils.Zip_Writer
	utils.zip_write_begin(&w, utils.temp_path(dir, "Packed.sint"))
	utils.zip_write_add(&w, "Packed/setup.sif", sif)
	utils.zip_write_add(&w, "Packed/ammo.png", transmute([]byte)string("png"))
	utils.zip_write_end(&w)
	write(utils.temp_path(dir, "Empty", "health.bmp"), transmute([]byte)string("bmp"))

	testing.expect(t, slice.equal(res.interfaces_list(dir), []string{"Empty", "Neo", "Packed"}), "the folders and the .sint listed")

	neo := res.interface_open(dir, "Neo")
	defer res.interface_close(&neo)
	testing.expect(t, neo.custom && neo.setup.alpha == 99, "a folder's, a folder down")
	file, scale, found := res.interface_picture(&neo, "health.png")
	testing.expect(t, found && strings.has_suffix(file.path, "Health.BMP") && scale == 3, "its picture, a .bmp in any case, by its own scale")
	_, _, scroll := res.interface_picture(&neo, "scroll.png")
	testing.expect(t, !scroll, "a picture no interface has")

	packed := res.interface_open(dir, "Packed")
	defer res.interface_close(&packed)
	testing.expect(t, packed.custom && packed.setup.alpha == 99, "a .sint's")
	_, ammo_scale, ammo := res.interface_picture(&packed, "ammo.png")
	testing.expect(t, ammo && ammo_scale == 1, "its picture, at 1 without a mod.ini")
	_, _, jet := res.interface_picture(&packed, "jet.png")
	testing.expect(t, !jet, "one it hasn't is the mods'")

	for name in ([]string{"Empty", "Gone", ""}) {
		own := res.interface_open(dir, name)
		defer res.interface_close(&own)
		testing.expectf(t, !own.custom && own.setup == res.INTERFACE_DEFAULT, "%q: the game's own", name)
	}
}

// The game's own anchors each bar by its icon, the fire bar and the grenades by the
// ammo's; a custom one by the icons it has pictures of, the rest by the last of them.
@(test)
anchors :: proc(t: ^testing.T) {
	dir := scratch(t, "anchors")
	defer os.remove_all(dir)
	own := res.interface_default()
	health, ammo, jet := [2]f32{5, 439}, [2]f32{275, 439}, [2]f32{480, 439}
	testing.expect_value(t, own.anchors, res.Interface_Anchors{health = health, jet = jet, ammo = ammo, fire = ammo, nades = ammo})

	sif := res.interface_setup_write(res.INTERFACE_DEFAULT)
	write(utils.temp_path(dir, "Ammo", "setup.sif"), sif)
	write(utils.temp_path(dir, "Ammo", "ammo.bmp"), transmute([]byte)string("bmp"))
	only_ammo := res.interface_open(dir, "Ammo")
	defer res.interface_close(&only_ammo)
	testing.expect_value(t, only_ammo.anchors, res.Interface_Anchors{health = ammo, jet = ammo, ammo = ammo, fire = ammo, nades = ammo})

	write(utils.temp_path(dir, "Two", "setup.sif"), sif)
	write(utils.temp_path(dir, "Two", "health.png"), transmute([]byte)string("png"))
	write(utils.temp_path(dir, "Two", "jet.bmp"), transmute([]byte)string("bmp"))
	two := res.interface_open(dir, "Two")
	defer res.interface_close(&two)
	testing.expect_value(t, two.anchors, res.Interface_Anchors{health = health, jet = jet, ammo = jet, fire = jet, nades = jet})
}

// A Soldat 1 install's custom interfaces, and its mod's, each made a .srmod: its hud, its
// setup.sif as layout.json and its HUD's pictures; its icons, the rest of them; each
// picture brought to 4.5 from its own scale (1, without a mod.ini), see-through where it
// was green. Named as it was but for what a name can't have; not over a mod by that
// name, nor the original's Default, nor one without a setup.sif.
@(test)
imported :: proc(t: ^testing.T) {
	dir := scratch(t, "imported")
	defer os.remove_all(dir)
	install := utils.temp_path(dir, "Soldat")
	mod := utils.temp_path(install, "mods", "Tourney")
	mods_dir := utils.temp_path(dir, "mods")
	setup := res.INTERFACE_DEFAULT
	setup.alpha = 77
	sif := res.interface_setup_write(setup)
	green := res.Texture{2, 2, {{0, 255, 0, 255}, {10, 20, 30, 255}, {10, 20, 30, 255}, {10, 20, 30, 255}}}
	write(utils.temp_path(install, "custom-interfaces", "Neo", "setup.sif"), sif)
	write(utils.temp_path(install, "custom-interfaces", "Neo", "health.png"), res.texture_png(green))
	write(utils.temp_path(install, "custom-interfaces", "Neo", "cursor.png"), res.texture_png(green))
	write(utils.temp_path(install, "custom-interfaces", "Default", "setup.sif"), sif)
	write(utils.temp_path(install, "custom-interfaces", "Empty", "health.png"), res.texture_png(green))
	write(utils.temp_path(mod, "custom-interfaces", "Tourney HUD", "setup.sif"), sif)
	write(utils.temp_path(mods_dir, "Taken", "mod.json"), transmute([]byte)string(`{"format": 1, "name": "Taken", "version": "1.0.0", "parts": []}`))
	write(utils.temp_path(install, "custom-interfaces", "Taken", "setup.sif"), sif)

	names := res.interfaces_import({install, mod}, mods_dir)
	slice.sort(names)
	testing.expect(t, slice.equal(names, []string{"Neo", "Tourney_HUD"}), "Neo and the mod's, not Default, Empty or Taken")

	neo, why, ok := res.srmod_open(utils.temp_path(mods_dir, "Neo.srmod"))
	defer res.srmod_close(&neo)
	if !testing.expectf(t, ok, "Neo a mod (%s)", why) do return
	testing.expect(t, neo.parts == {.Hud, .Icons} && neo.info.title == "Neo", "its hud and its icons")
	file, found := res.srmod_file(&neo, .Hud, "layout.json")
	data, _ := res.mod_read(file, context.temp_allocator)
	layout := res.hud_layout_default()
	testing.expect(t, found && res.hud_layout_read(data, "layout.json", &layout) && layout.alpha == 77 && layout.weapon.align == .Left, "its layout, as a custom one's")
	health, has := res.srmod_file(&neo, .Hud, "health.png")
	pixels, _ := res.mod_read(health, context.temp_allocator)
	image, decoded := res.texture_decode(pixels, nil, context.temp_allocator)
	testing.expect(t, has && decoded && image.width == 9 && image.height == 9 && image.pixels[0].a == 0, "its health, at 4.5, its green see-through")
	_, cursor := res.srmod_file(&neo, .Icons, "cursor.png")
	testing.expect(t, cursor, "its cursor among its icons")

	tourney, twhy, tok := res.srmod_open(utils.temp_path(mods_dir, "Tourney_HUD.srmod"))
	defer res.srmod_close(&tourney)
	testing.expect(t, tok && tourney.info.title == "Tourney HUD" && tourney.parts == {.Hud}, twhy)
}
