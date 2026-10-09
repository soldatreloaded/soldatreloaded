package ui

// The client's look, shared by the menus and the HUD: its faces and text, its colours,
// shapes and widgets.
//
// Everything is laid out in units of a view 480 tall, as the game's own view is,
// whatever the window: the width follows the window, so a screen looks the same at any
// size. A match's view is held within the original's shapes, between bars (ui_fit).
//
// The widgets are the C client's main menu's, and immediate as its are: a screen lays
// its page out anew each frame in one pass of a Kit, each widget drawing itself and
// acting on the click, the wheel and the keys the kit gathered since the last pass
// (kit.odin), so there is no widget tree to keep.
//
//   ui.odin       the view's units, the faces, the mouse
//   font.odin     a face rasterized and drawn (gfx/font.c)
//   text.odin     text in units, and the menu's type: a face, a size, a tracking
//   theme.odin    the colours, the sizes and the menu's styles
//   shapes.odin   rectangles rounded or not, circles, rules, gradients, glows
//   kit.odin      a pass: the focus and the keys, rows and their layout, scrollbars
//   widgets.odin  toggle, slider, select box, text field, colour row, buttons, chips
//   popup.odin    the list a select box opens
//   picker.odin   the colour picker
//   edit.odin     a text field's typing
//   capture.odin  a key, waited for, to bind
//
// Uses: raylib, input (the keys' names). From the C client: gfx/font.c, and the
// widgets of ui/mainmenu.c.

import rl "vendor:raylib"

import res "../../../core/resources"

VIEW_HEIGHT :: 480

// The mod's faces: Play for what is read, its Bold for emphasis, Russo One (wide,
// square) for the titles, Black Ops One (a stencil) for the game's name; and the HUD's
// two, as the mod's txt/font.ini names them. A face the mod hasn't is drawn in Play.
Face :: enum {
	Regular,
	Bold,
	Display,
	Logo,
	Hud_1, // font.ini's Font1: the HUD's menus, big messages and numbers
	Hud_2, // and its Font2: the console, the kill feed and the rest
}

@(rodata)
FACE_FILES := #partial [Face]string {
	.Regular = "fonts/play-regular.ttf",
	.Bold    = "fonts/play-bold.ttf",
	.Display = "fonts/russo-one.ttf",
	.Logo    = "fonts/black-ops-one.ttf",
}

// The HUD's styles of lettering, the original's: each in one of font.ini's two fonts, at
// its size and stretch.
Hud_Style :: enum {
	Menu,     // FontMenuSize, in Font1
	Big,      // FontBigSize, in Font1
	Small,    // FontConsoleSize, in Font2
	Smallest, // FontConsoleSmallSize, in Font2
	Weapons,  // FontWeaponMenuSize, in Font2
}

Hud_Lettering :: struct {
	face:    Face,
	size:    f32, // the em, in units
	stretch: f32, // as much wider than the face has it
}

Ui :: struct {
	fonts:   [Face]Font,
	hud:     [Hud_Style]Hud_Lettering,
	scale:   f32,        // window pixels to a unit
	width:   f32,        // the view's width, in units
	origin:  rl.Vector2, // the view's top-left in the window, in pixels: a match's sits between bars
	mouse:   rl.Vector2, // in units
	clicked: bool,       // the left button went down this frame
	wheel:   f32,        // notches turned this frame, away from you positive
}

ui_init :: proc(ui: ^Ui, mod: res.Mod) {
	for path, face in FACE_FILES {
		if file, found := res.mod_file(mod, path); found && path != "" do ui.fonts[face] = font_load(res.mod_read(file) or_else nil)
	}
	fonts := res.font_config_load(mod)
	for i in 0 ..< 2 {
		file, found := res.font_file(mod, fonts, fonts.files[i])
		if found do ui.fonts[.Hud_1 if i == 0 else .Hud_2] = font_load(res.mod_read(file) or_else nil)
	}
	ui.hud = {
		.Menu     = {.Hud_1, fonts.menu * POINT, fonts.scales[0]},
		.Big      = {.Hud_1, fonts.big * POINT, fonts.scales[0]},
		.Small    = {.Hud_2, fonts.console * POINT, fonts.scales[1]},
		.Smallest = {.Hud_2, fonts.console_small * POINT, fonts.scales[1]},
		.Weapons  = {.Hud_2, fonts.weapon_menu * POINT, fonts.scales[1]},
	}
	ui_begin(ui)
}

ui_destroy :: proc(ui: ^Ui) {
	for &font in ui.fonts do font_unload(&font)
	ui^ = {}
}

// At the start of each frame, before any screen is updated: the window's size and the
// mouse.
ui_begin :: proc(ui: ^Ui) {
	ui_fit(ui, {0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
	ui.clicked = rl.IsMouseButtonPressed(.LEFT)
	ui.wheel = rl.GetMouseWheelMove()
}

// The view laid over `area` of the window, in pixels, and not the whole of it. What is
// drawn in it is drawn from its top-left: the caller moves the drawing there.
ui_fit :: proc(ui: ^Ui, area: rl.Rectangle) {
	ui.scale = area.height / VIEW_HEIGHT
	ui.width = area.width / ui.scale
	ui.origin = {area.x, area.y}
	ui.mouse = (rl.GetMousePosition() - ui.origin) / ui.scale
}

// A rectangle in units, in window pixels.
pixels :: proc(ui: ^Ui, rect: rl.Rectangle) -> rl.Rectangle {
	return {rect.x * ui.scale, rect.y * ui.scale, rect.width * ui.scale, rect.height * ui.scale}
}

// The face drawn for `face`: its own, or Play's where the mod hasn't it.
@(private = "package")
face_font :: proc(ui: ^Ui, face: Face) -> ^Font {
	return &ui.fonts[face] if ui.fonts[face].data != nil else &ui.fonts[.Regular]
}
