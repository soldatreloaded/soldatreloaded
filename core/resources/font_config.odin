package resources

import "core:encoding/ini"
import "core:log"
import "core:strconv"
import "core:strings"

import "../utils"

// What the HUD is written in, as an original Soldat mod says it, in its txt/font.ini
// (the mod's own, else Classic's: mod_file):
//
//   [FONTS]
//   Font1File=play-regular.ttf   the menus, the big messages and the HUD's numbers
//   Font2File=play-regular.ttf   the console, the kill feed and the rest
//   Font1ScaleX=150              each font as much wider, in percent
//   Font2ScaleX=125
//   FontMenuSize=12              each style's size, in points at the view's 480
//   FontConsoleSize=9
//   FontConsoleSmallSize=7
//   FontWeaponMenuSize=8
//   FontBigSize=28
//
// A font's file is looked for in the mod's fonts/, then at its root, then in Classic's
// fonts/. Keys are matched without regard to case; the rest of the file (the fonts'
// names, their boldness) is passed over, as OpenSoldat passes it over. A key the file
// doesn't hold keeps its default; a mod without the file has them all.

FONT_CONFIG_FILE :: "txt/font.ini"

Font_Config :: struct {
	files:  [2]string, // Font1File, Font2File
	scales: [2]f32,    // Font1ScaleX, Font2ScaleX, as a stretch: 1.5 for 150
	menu, console, console_small, weapon_menu, big: f32, // in points
}

DEFAULT_FONT_CONFIG :: Font_Config {
	files         = {"play-regular.ttf", "play-regular.ttf"},
	scales        = {1.5, 1.25},
	menu          = 12,
	console       = 9,
	console_small = 7,
	weapon_menu   = 8,
	big           = 28,
}

// The mod's txt/font.ini, its files' names allocated with the temp allocator; the
// defaults if it hasn't one. A value that isn't what its key takes is passed over,
// logged.
font_config_load :: proc(mod: Mod) -> (config: Font_Config) {
	config = DEFAULT_FONT_CONFIG
	path := mod_file(mod, FONT_CONFIG_FILE)
	if !utils.file_exists(path) do return
	text, read := utils.read_file(path, context.temp_allocator)
	if !read do return

	it := ini.iterator_from_string(string(text))
	for key, value in ini.iterate(&it) {
		if !strings.equal_fold(it.section, "FONTS") do continue
		k := strings.to_lower(key, context.temp_allocator)
		switch k {
		case "font1file", "font2file":
			if value != "" do config.files[0 if k == "font1file" else 1] = value
			continue
		}
		number, is_number := strconv.parse_f32(value)
		if !is_number || number <= 0 {
			if k == "font1scalex" || k == "font2scalex" || strings.has_prefix(k, "font") && strings.has_suffix(k, "size") {
				log.warnf("%s: %s = %s isn't a number above 0; passed over", path, key, value)
			}
			continue
		}
		switch k {
		case "font1scalex":          config.scales[0] = number / 100
		case "font2scalex":          config.scales[1] = number / 100
		case "fontmenusize":         config.menu = number
		case "fontconsolesize":      config.console = number
		case "fontconsolesmallsize": config.console_small = number
		case "fontweaponmenusize":   config.weapon_menu = number
		case "fontbigsize":          config.big = number
		}
	}
	return
}

// Where the font file `name` of the mod's font.ini is: in the mod's fonts/, at its root,
// else in Classic's fonts/; with the temp allocator.
font_file :: proc(mod: Mod, name: string) -> string {
	if mod.dir != "" {
		for path in ([2]string{utils.temp_path(mod.dir, "fonts", name), utils.temp_path(mod.dir, name)}) {
			if utils.file_exists(path) do return path
		}
	}
	return utils.temp_path(mod.fallback, "fonts", name)
}
