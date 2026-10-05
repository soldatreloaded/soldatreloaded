package ui

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import "../../../core/utils"

// The colour picker: a popup with a heading and the colour's hex, a square of the hue's
// shades (saturation across, value down), the hue strip beside it, swatches to start
// from, and None for a colour that may be none (the art's own). The colour is set as it
// goes, so whatever shows it (the soldier) follows. The side keys take the saturation,
// up and down the value, Q and E (the shoulders) the hue.

// A colour the picker sets: one always set, or one that may be none.
Color_Ref :: union {
	^utils.Rgba,
	^Maybe(utils.Rgba),
}

Picker_Drag :: enum {
	None,
	Square,
	Hue,
}

// A few to start from: the greys, the wheel round, and a skin and a brown.
@(rodata)
SWATCHES := [?]rl.Color {
	{255, 255, 255, 255}, {191, 191, 191, 255}, {127, 127, 127, 255}, {0, 0, 0, 255},
	{217, 59, 43, 255}, {240, 122, 30, 255}, {242, 193, 46, 255}, {91, 191, 74, 255},
	{47, 181, 165, 255}, {58, 160, 232, 255}, {47, 79, 191, 255}, {28, 42, 107, 255},
	{122, 63, 191, 255}, {217, 79, 168, 255}, {138, 90, 53, 255}, {230, 180, 120, 255},
}
SWATCH_COLS :: 8

PICK_PAD :: 8
PICK_HEAD :: 22
PICK_SQUARE_W :: 150
PICK_SQUARE_H :: 112
PICK_HUE_W :: 14
PICK_SWATCH_H :: 16
PICK_SWATCH_GAP :: 3
PICK_CLEAR :: 24

// The colour, and whether there is one.
color_get :: proc(ref: Color_Ref) -> (color: rl.Color, set: bool) {
	switch c in ref {
	case ^utils.Rgba:
		return rl.Color(c^), true
	case ^Maybe(utils.Rgba):
		if value, ok := c.?; ok do return rl.Color(value), true
	}
	return {255, 255, 255, 255}, false
}

color_set :: proc(ref: Color_Ref, color: rl.Color) {
	rgba := utils.Rgba{color.r, color.g, color.b, 255}
	switch c in ref {
	case ^utils.Rgba:        c^ = rgba
	case ^Maybe(utils.Rgba): c^ = rgba
	}
}

// None: the art's own, for a colour that may be none.
color_clear :: proc(ref: Color_Ref) {
	if c, ok := ref.(^Maybe(utils.Rgba)); ok do c^ = nil
}

color_clearable :: proc(ref: Color_Ref) -> bool {
	_, ok := ref.(^Maybe(utils.Rgba))
	return ok
}

// The colour's identity, as a text field keys it.
color_key :: proc(ref: Color_Ref) -> rawptr {
	switch c in ref {
	case ^utils.Rgba:        return c
	case ^Maybe(utils.Rgba): return c
	}
	return nil
}

@(private = "package")
popup_open_color :: proc(k: ^Kit, owner: int, ref: Color_Ref, x, y: f32) {
	p := &k.popup
	p^ = {kind = .Color, owner = owner, hover = -1, color = ref}
	p.w = PICK_PAD + PICK_SQUARE_W + PICK_PAD + PICK_HUE_W + PICK_PAD
	p.h = PICK_HEAD + PICK_SQUARE_H + PICK_PAD + 2 * PICK_SWATCH_H + PICK_SWATCH_GAP + PICK_PAD + (PICK_CLEAR if color_clearable(ref) else 0) + 4
	p.val = 1
	if color, set := color_get(ref); set do rgb_to_hsv(color, &p.hue, &p.sat, &p.val)
	popup_place(k, x + 20 - p.w, y, CTRL_H)
}

// The picker's parts, from its top left.
@(private = "file")
Parts :: struct {
	sq_x, sq_y, hue_x, sw_y, sw_w, clear_y: f32,
}

@(private = "file")
parts_of :: proc(p: ^Popup) -> (k: Parts) {
	k.sq_x = p.x + PICK_PAD
	k.sq_y = p.y + PICK_HEAD
	k.hue_x = k.sq_x + PICK_SQUARE_W + PICK_PAD
	k.sw_y = k.sq_y + PICK_SQUARE_H + PICK_PAD
	k.sw_w = (p.w - 2 * PICK_PAD - (SWATCH_COLS - 1) * PICK_SWATCH_GAP) / SWATCH_COLS
	k.clear_y = k.sw_y + 2 * PICK_SWATCH_H + PICK_SWATCH_GAP + PICK_PAD
	return
}

@(private = "file")
swatch_at :: proc(parts: Parts, i: int) -> rl.Vector2 {
	return {
		parts.sq_x + f32(i % SWATCH_COLS) * (parts.sw_w + PICK_SWATCH_GAP),
		parts.sw_y + f32(i / SWATCH_COLS) * (PICK_SWATCH_H + PICK_SWATCH_GAP),
	}
}

// The swatch under `c`, len(SWATCHES) for None, -1 for neither.
@(private = "file")
picker_item_at :: proc(p: ^Popup, c: rl.Vector2) -> int {
	parts := parts_of(p)
	for i in 0 ..< len(SWATCHES) {
		at := swatch_at(parts, i)
		if inside(c, at.x, at.y, parts.sw_w, PICK_SWATCH_H) do return i
	}
	if color_clearable(p.color) && inside(c, parts.sq_x, parts.clear_y, p.w - 2 * PICK_PAD, PICK_CLEAR - 4) do return len(SWATCHES)
	return -1
}

@(private = "package")
picker_input :: proc(k: ^Kit) {
	p := &k.popup
	// the colour changed under it (typed into the row's box): it follows
	if color, set := color_get(p.color); p.drag == .None && set && !same_rgb(color, hsv_to_rgb(p.hue, p.sat, p.val)) {
		rgb_to_hsv(color, &p.hue, &p.sat, &p.val)
	}

	changed := false
	if k.side != 0 || k.move != 0 || k.page != 0 {
		p.sat = clamp(p.sat + 0.05 * f32(k.side), 0, 1)
		p.val = clamp(p.val - 0.05 * f32(k.move), 0, 1)
		p.hue = math.mod(p.hue + 10 * f32(k.page) + 360, 360)
		changed = true
	}
	k.move, k.side, k.page = 0, 0, 0
	if k.enter || k.back do popup_close(k)
	k.enter, k.back = false, false
	if p.kind == .None do return

	parts := parts_of(p)
	mouse := k.ui.mouse
	p.hover = picker_item_at(p, mouse)
	if k.click {
		k.click = false
		if !inside(mouse, p.x, p.y, p.w, p.h) {
			popup_close(k)
			return
		}
		if inside(mouse, parts.sq_x - 4, parts.sq_y - 4, PICK_SQUARE_W + 8, PICK_SQUARE_H + 8) {
			p.drag = .Square
		} else if inside(mouse, parts.hue_x - 3, parts.sq_y - 4, PICK_HUE_W + 6, PICK_SQUARE_H + 8) {
			p.drag = .Hue
		} else if p.hover >= 0 && p.hover < len(SWATCHES) {
			rgb_to_hsv(SWATCHES[p.hover], &p.hue, &p.sat, &p.val)
			color_set(p.color, SWATCHES[p.hover])
		} else if p.hover == len(SWATCHES) {
			color_clear(p.color)
			popup_close(k)
			return
		}
	}
	if !k.held do p.drag = .None
	switch p.drag {
	case .None:
	case .Square:
		p.sat = clamp((mouse.x - parts.sq_x) / PICK_SQUARE_W, 0, 1)
		p.val = 1 - clamp((mouse.y - parts.sq_y) / PICK_SQUARE_H, 0, 1)
		changed = true
	case .Hue:
		p.hue = clamp((mouse.y - parts.sq_y) / PICK_SQUARE_H, 0, 0.9999) * 360
		changed = true
	}
	if changed do color_set(p.color, hsv_to_rgb(p.hue, p.sat, p.val))
}

@(private = "package")
picker_draw :: proc(k: ^Kit) {
	ui := k.ui
	p := &k.popup
	parts := parts_of(p)
	_, set := color_get(p.color)
	unset := color_clearable(p.color) && !set
	now := hsv_to_rgb(p.hue, p.sat, p.val)
	text_mid(k, SECTION, "COLOUR", parts.sq_x, p.y + PICK_HEAD / 2 + 1, MUTED)
	hex := "none" if unset else fmt.tprintf("#%02X%02X%02X", now.r, now.g, now.b)
	hw := width_of(ui, BODY, hex)
	text_mid(k, BODY, hex, p.x + p.w - PICK_PAD - hw, p.y + PICK_HEAD / 2 + 1, MUTED)
	if !unset do rrect(ui, p.x + p.w - PICK_PAD - hw - 18, p.y + PICK_HEAD / 2 - 5, 12, 12, 3, now)

	// the square: a grid of quads with the colour worked out at each corner, so the
	// shading is the HSV square's and not a two-triangle blend's
	GRID :: 12
	for j in 0 ..< GRID {
		for i in 0 ..< GRID {
			s0, s1 := f32(i) / GRID, f32(i + 1) / GRID
			v0, v1 := 1 - f32(j) / GRID, 1 - f32(j + 1) / GRID
			x0, x1 := parts.sq_x + s0 * PICK_SQUARE_W, parts.sq_x + s1 * PICK_SQUARE_W
			y0, y1 := parts.sq_y + (1 - v0) * PICK_SQUARE_H, parts.sq_y + (1 - v1) * PICK_SQUARE_H
			quad(ui, {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}, {hsv_to_rgb(p.hue, s0, v0), hsv_to_rgb(p.hue, s1, v0), hsv_to_rgb(p.hue, s1, v1), hsv_to_rgb(p.hue, s0, v1)})
		}
	}
	mx, my := parts.sq_x + p.sat * PICK_SQUARE_W, parts.sq_y + (1 - p.val) * PICK_SQUARE_H
	circle(ui, mx, my, 6.5, {0, 0, 0, 120})
	circle(ui, mx, my, 5.5, TEXT)
	circle(ui, mx, my, 4, now)

	// the hue strip, top to bottom round the wheel, exact at each sixth
	for i in 0 ..< 6 {
		y0 := parts.sq_y + PICK_SQUARE_H * f32(i) / 6
		y1 := parts.sq_y + PICK_SQUARE_H * f32(i + 1) / 6
		c0, c1 := hsv_to_rgb(60 * f32(i), 1, 1), hsv_to_rgb(60 * f32(i + 1), 1, 1)
		quad(ui, {{parts.hue_x, y0}, {parts.hue_x + PICK_HUE_W, y0}, {parts.hue_x + PICK_HUE_W, y1}, {parts.hue_x, y1}}, {c0, c0, c1, c1})
	}
	hy := parts.sq_y + p.hue / 360 * PICK_SQUARE_H
	rrect(ui, parts.hue_x - 3, hy - 3, PICK_HUE_W + 6, 6, 2, {0, 0, 0, 140})
	rrect(ui, parts.hue_x - 2, hy - 2, PICK_HUE_W + 4, 4, 1.5, TEXT)

	// the swatches
	for swatch, i in SWATCHES {
		at := swatch_at(parts, i)
		current := !unset && same_rgb(swatch, now)
		if current || i == p.hover {
			rrect(ui, at.x - 1.5, at.y - 1.5, parts.sw_w + 3, PICK_SWATCH_H + 3, 4, TEXT if current else {255, 255, 255, 90})
		}
		rrect(ui, at.x, at.y, parts.sw_w, PICK_SWATCH_H, 3, swatch)
	}
	if color_clearable(p.color) {
		hot := p.hover == len(SWATCHES)
		box(ui, parts.sq_x, parts.clear_y, p.w - 2 * PICK_PAD, PICK_CLEAR - 4, CONTROL_HOT if hot else CONTROL, BORDER)
		label := "None (the art's own)  *" if unset else "None (the art's own)"
		text_mid(k, BODY, label, parts.sq_x + 8, parts.clear_y + (PICK_CLEAR - 4) / 2, TEXT if hot else MUTED)
	}
}

// Hue in degrees [0, 360), saturation and value 0 to 1. A grey has no hue of its own:
// the one held stays.
@(private = "file")
rgb_to_hsv :: proc(c: rl.Color, h, s, v: ^f32) {
	r, g, b := f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255
	mx, mn := max(r, g, b), min(r, g, b)
	d := mx - mn
	v^ = mx
	s^ = d / mx if mx > 0 else 0
	if d <= 0 do return
	hue: f32
	if mx == r {
		hue = math.mod((g - b) / d, 6)
	} else if mx == g {
		hue = (b - r) / d + 2
	} else {
		hue = (r - g) / d + 4
	}
	hue *= 60
	h^ = hue + 360 if hue < 0 else hue
}

@(private = "file")
hsv_to_rgb :: proc(hue, s, v: f32) -> rl.Color {
	h := math.mod(hue, 360)
	if h < 0 do h += 360
	c := v * s
	x := c * (1 - abs(math.mod(h / 60, 2) - 1))
	m := v - c
	r, g, b: f32
	switch int(h / 60) {
	case 0: r, g = c, x
	case 1: r, g = x, c
	case 2: g, b = c, x
	case 3: g, b = x, c
	case 4: r, b = x, c
	case:   r, b = c, x
	}
	return {channel(r + m), channel(g + m), channel(b + m), 255}

	channel :: proc(f: f32) -> u8 {return u8(math.round(f * 255))}
}

@(private = "file")
same_rgb :: proc(a, b: rl.Color) -> bool {
	return a.r == b.r && a.g == b.g && a.b == b.b
}
