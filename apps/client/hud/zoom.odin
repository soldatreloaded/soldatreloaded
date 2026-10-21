package hud

import rlgl "vendor:raylib/rlgl"

import "../ui"

// Scale_Interface off (Hud_Data.unscaled), as OpenSoldat's r_scaleinterface off: each
// part of the HUD at the size it has in a 640 by 480 window, a window pixel to one of its
// units, at any window; and where the window's size puts its anchor (the original's
// _iscala on a part's anchor point, its offsets from it kept in pixels). Here a part is
// laid out as ever, in units of a view 480 tall, which puts its anchor where it should be,
// and drawn shrunk about that point by a pixel's share of a unit: the same. On, the
// default, the HUD grows with the window, as it always has.

Zoom :: struct {
	at: [2]f32, // the part's anchor, in units: it stays where it is
	by: f32,    // how much bigger the part is drawn than it is laid out; 1 scaled
}

// How much bigger than laid out each part is drawn: 1 while the interface scales, a
// pixel's share of a unit while it doesn't.
shrink_of :: proc(u: ^ui.Ui, data: ^Hud_Data) -> f32 {
	if !data.unscaled || u.scale <= 0 do return 1
	return 1 / u.scale
}

// What is drawn until zoom_end drawn `by` as big, about `at`.
zoom_around :: proc(u: ^ui.Ui, at: [2]f32, by: f32) -> Zoom {
	z := Zoom{at, by}
	if by == 1 do return z
	px := at * u.scale
	rlgl.PushMatrix()
	rlgl.Translatef(px.x, px.y, 0)
	rlgl.Scalef(by, by, 1)
	rlgl.Translatef(-px.x, -px.y, 0)
	return z
}

zoom_end :: proc(z: Zoom) {
	if z.by != 1 do rlgl.PopMatrix()
}

// A point of the view, in units, where it falls in the part as it is laid out: for a part
// that hit-tests the pointer.
unzoomed :: proc(z: Zoom, point: [2]f32) -> [2]f32 {
	return z.at + (point - z.at) / z.by
}
