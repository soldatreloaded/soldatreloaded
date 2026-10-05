package ui

// The client's look, shared by the menus and the HUD: its faces and text, its colours,
// shapes and widgets.
//
// Everything is laid out in units of a view 480 tall, as the game's own view is,
// whatever the window: the width follows the window, so a screen looks the same at any
// size.
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
// square) for the titles, Black Ops One (a stencil) for the game's name. A face the mod
// hasn't is drawn in Play.
Face :: enum {
	Regular,
	Bold,
	Display,
	Logo,
}

@(rodata)
FACE_FILES := [Face]string {
	.Regular = "fonts/play-regular.ttf",
	.Bold    = "fonts/play-bold.ttf",
	.Display = "fonts/russo-one.ttf",
	.Logo    = "fonts/black-ops-one.ttf",
}

Ui :: struct {
	fonts:   [Face]Font,
	scale:   f32,        // window pixels to a unit
	width:   f32,        // the view's width, in units
	mouse:   rl.Vector2, // in units
	clicked: bool,       // the left button went down this frame
	wheel:   f32,        // notches turned this frame, away from you positive
}

ui_init :: proc(ui: ^Ui, mod: res.Mod) {
	for file, face in FACE_FILES do ui.fonts[face] = font_load(mod, file)
	ui_begin(ui)
}

ui_destroy :: proc(ui: ^Ui) {
	for &font in ui.fonts do font_unload(&font)
	ui^ = {}
}

// At the start of each frame, before any screen is updated: the window's size and the
// mouse.
ui_begin :: proc(ui: ^Ui) {
	ui.scale = f32(rl.GetScreenHeight()) / VIEW_HEIGHT
	ui.width = f32(rl.GetScreenWidth()) / ui.scale
	ui.mouse = rl.GetMousePosition() / ui.scale
	ui.clicked = rl.IsMouseButtonPressed(.LEFT)
	ui.wheel = rl.GetMouseWheelMove()
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
