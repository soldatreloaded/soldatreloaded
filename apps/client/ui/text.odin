package ui

import rl "vendor:raylib"

// Text in units, in the lettering of font.odin. A size is the em, in units.

// What a text's y is: its line's top, its baseline, or its line's bottom.
Vertical :: enum {
	Top,
	Baseline,
	Bottom,
}

// `str` at `pos`, its em `size` units, `stretch` times as wide as the face has it and
// `tracking` ems more between its letters, in `face`; over a `shadow` a pixel down and
// to the right, where that has any alpha.
text :: proc(
	ui: ^Ui,
	str: string,
	pos: rl.Vector2,
	size: f32,
	color: rl.Color,
	stretch: f32 = 1,
	shadow := rl.Color{},
	vertical := Vertical.Top,
	face := Face.Regular,
	tracking: f32 = 0,
) {
	font := face_font(ui, face)
	em := size * ui.scale
	at := pos * ui.scale
	if vertical != .Top {
		ascent, descent := font_metrics(font, em)
		at.y -= ascent if vertical == .Baseline else ascent + descent
	}
	font_draw(font, str, at, em, stretch, tracking, color, shadow)
}

text_width :: proc(ui: ^Ui, str: string, size: f32, stretch: f32 = 1, face := Face.Regular, tracking: f32 = 0) -> f32 {
	return font_width(face_font(ui, face), str, size * ui.scale, stretch, tracking) / ui.scale
}

// A line's height, its ascent and descent, in units.
line_height :: proc(ui: ^Ui, size: f32, face := Face.Regular) -> f32 {
	ascent, descent := font_metrics(face_font(ui, face), size * ui.scale)
	return (ascent + descent) / ui.scale
}

// ---------------------------------------------------------------------------------
// The menu's type: four roles, each a face at a size, with the space between its
// letters (theme.odin names them). Every text of the menu stands over a soft shadow.

Style :: struct {
	face:     Face,
	size:     f32, // the em, in units
	tracking: f32, // ems between the letters
}

POINT :: 96.0 / 72.0 // a point, in units: the original sizes its faces in points at the view's 480

MENU_SHADOW :: rl.Color{0, 0, 0, 160}

// `str` in `style`, its line's top at `pos`.
write :: proc(ui: ^Ui, style: Style, str: string, pos: rl.Vector2, color: rl.Color) {
	text(ui, str, pos, style.size, color, shadow = MENU_SHADOW, face = style.face, tracking = style.tracking)
}

width_of :: proc(ui: ^Ui, style: Style, str: string) -> f32 {
	return text_width(ui, str, style.size, face = style.face, tracking = style.tracking)
}

height_of :: proc(ui: ^Ui, style: Style) -> f32 {
	return line_height(ui, style.size, style.face)
}
