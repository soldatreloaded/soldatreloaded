package ui

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import rl "vendor:raylib"

import "../../../core/utils"

// The widgets, each drawn where the pass lays it out and acting there on what the kit
// gathered. Those that are a row of the column (toggle, slider, select, field, colour,
// key) take a row of their own with their label on its left; the rest (buttons, chips,
// text boxes) go where they are put.

// ---------------------------------------------------------------------------------
// Toggle

// A switch: on, the accent, its knob to the right.
switch_draw :: proc(k: ^Kit, x, cy: f32, on, hot: bool) {
	track := (ACCENT_HOT if hot else ACCENT) if on else rl.Color{70, 80, 102, 255} if hot else TRACK
	rrect(k.ui, x, cy - 7, 30, 14, 7, track)
	circle(k.ui, x + 23 if on else x + 7, cy, 5, TEXT)
}

// The whole row a switch. True if it was flipped.
toggle :: proc(k: ^Kit, label: string, value: ^bool) -> (flipped: bool) {
	r := row(k, ROW_H, true)
	flipped = take_enter(k, r.focused) || take_side(k, r.focused) != 0
	if r.shown && take(k, r.id, r.x, r.y, r.w, r.h) do flipped = true
	if flipped do value^ = !value^
	if !r.shown do return
	row_label(k, r, label)
	sx := r.x + r.w - 8 - 30
	state := "On" if value^ else "Off"
	text_mid(k, BODY, state, sx - 10 - width_of(k.ui, BODY, state), r.y + r.h / 2, TEXT if value^ else MUTED)
	switch_draw(k, sx, r.y + r.h / 2, value^, r.hot || r.focused)
	return
}

// ---------------------------------------------------------------------------------
// Slider

// A number from `lo` to `hi` in steps of `step`, dragged along its track or stepped by
// the side keys, shown as `format` of it (a %d for an integer, else a %f). True if it
// changed.
slider :: proc(k: ^Kit, label: string, value: ^$T, lo, hi, step: f32, format: string) -> (changed: bool) where intrinsics.type_is_numeric(T) {
	r := row(k, ROW_H, true)
	v := clamp(f32(value^), lo, hi)
	cw := ctrl_w(r)
	x0, x1, cy := ctrl_x(r) + 6, ctrl_x(r) + cw - 58, r.y + r.h / 2
	next := v
	if side := take_side(k, r.focused); side != 0 do next = v + f32(side) * step
	if r.shown && take(k, r.id, x0 - 8, r.y, x1 - x0 + 16, r.h) do k.drag = r.id
	if k.drag == r.id && k.held {
		t := clamp((k.ui.mouse.x - x0) / (x1 - x0), 0, 1)
		next = lo + math.round(t * (hi - lo) / step) * step
	}
	next = clamp(next, lo, hi)
	if abs(next - v) > step * 0.01 {
		when intrinsics.type_is_integer(T) {
			value^ = T(math.round(next))
		} else {
			value^ = T(math.round(next * 100) / 100) // as the cvar kept it, to two places
		}
		v = next
		changed = true
	}
	if !r.shown do return
	row_label(k, r, label)
	t := (v - lo) / (hi - lo) if hi > lo else 0
	active := r.hot || r.focused || k.drag == r.id
	rrect(k.ui, x0, cy - 1.5, x1 - x0, 3, 1.5, TRACK)
	if t > 0 do rrect(k.ui, x0, cy - 1.5, (x1 - x0) * t, 3, 1.5, ACCENT_HOT if active else ACCENT)
	circle(k.ui, x0 + (x1 - x0) * t, cy, 6 if active else 5, TEXT)
	when intrinsics.type_is_integer(T) {
		shown := fmt.tprintf(format, int(math.round(v)))
	} else {
		shown := fmt.tprintf(format, v)
	}
	text_mid(k, BODY, shown, ctrl_x(r) + cw - width_of(k.ui, BODY, shown), cy, TEXT)
	return
}

// ---------------------------------------------------------------------------------
// Select box

// A box showing names[current] that opens the list to pick from; the side keys step
// along it, past the locked (nil for none). What was picked, or -1; `preview`, if
// given, follows the list's highlight, so what shows the choice can show it before it
// is made.
select_box :: proc(k: ^Kit, label: string, names: []string, locked: []bool, current: int, preview: ^int = nil) -> int {
	count := len(names)
	r := row(k, ROW_H, true)
	picked := take_picked(k, r.id)
	if side := take_side(k, r.focused); side != 0 && count > 0 {
		at := current
		for _ in 0 ..< count {
			at = (at + side + count) % count
			if locked == nil || !locked[at] do break
		}
		if at != current && (locked == nil || !locked[at]) do picked = at
	}
	cw, cx, cy := ctrl_w(r), ctrl_x(r), ctrl_y(r)
	open := k.popup.kind == .List && k.popup.owner == r.id
	if (r.shown && take(k, r.id, r.x, r.y, r.w, r.h)) || take_enter(k, r.focused) {
		if open {
			popup_close(k)
		} else {
			popup_open_list(k, r.id, names, locked, current, cx, cy, cw)
		}
		open = !open
	}
	if open do popup_fill_list(k, names, locked) // what is locked may change with the rest
	if preview != nil {
		preview^ = picked if picked >= 0 && picked < count else current
		hover := k.popup.hover
		if open && hover >= 0 && hover < count && (locked == nil || !locked[hover]) do preview^ = hover
	}
	if !r.shown do return picked
	row_label(k, r, label)
	box(k.ui, cx, cy, cw, CTRL_H, CONTROL_HOT if r.hot || open else CONTROL, with_alpha(ACCENT, 200) if open else BORDER)
	shown := ""
	if current >= 0 && current < count {
		shown = names[current]
		if locked != nil && locked[current] do shown = fmt.tprintf("%s (locked)", shown)
	}
	text_fit(k, BODY, shown, cx + 8, cy + CTRL_H / 2, cw - 30, TEXT)
	chevron(k.ui, cx + cw - 11, cy + CTRL_H / 2, 6, !open, ACCENT if open else MUTED)
	return picked
}

// An enum's value, its names in its order, the locked (nil for none) shown but never
// set. The value the list's highlight previews.
enum_select :: proc(k: ^Kit, label: string, value: ^$E, names: []string, locked: []bool = nil) -> E where intrinsics.type_is_enum(E) {
	current := int(value^)
	preview := current
	picked := select_box(k, label, names, locked, current, &preview)
	if picked >= 0 && picked < len(names) && !(locked != nil && locked[picked]) {
		value^ = E(picked)
		preview = picked
	}
	return E(preview)
}

// A number that takes one of `values`, each named; one that is none of them shows as
// the first.
value_select :: proc(k: ^Kit, label: string, value: ^i32, values: []i32, names: []string) {
	current := 0
	for v, i in values do if value^ == v do current = i
	if picked := select_box(k, label, names, nil, current); picked >= 0 do value^ = values[picked]
}

// ---------------------------------------------------------------------------------
// Text field

// A text box over `key` (what it edits, which stands for it while it has the
// keyboard): `value`, or what is being typed while it has the keyboard, the end of it
// when it is too long, so the caret shows. `secret` shows stars. A click, or Enter while
// it is `focused`, types into it; two clicks close together select its text. The text
// typed, when it changed since the last pass.
field_box :: proc(
	k: ^Kit,
	id: int,
	focused: bool,
	x, y, w: f32,
	key: rawptr,
	value: string,
	max: int,
	placeholder: string,
	secret: bool,
) -> (typed: string, changed: bool) {
	e := &k.edit
	if e.dirty == key {
		e.dirty = nil
		typed, changed = strings.clone(edit_text(k), context.temp_allocator), true
	}
	typing := e.key == key
	hot := over(k, x, y, w, CTRL_H)
	clicked := take(k, id, x, y, w, CTRL_H)
	if clicked || take_enter(k, focused) {
		edit_begin(k, key, typed if changed else value, max)
		typing = true
	}
	if clicked { // two clicks on the same box, close together: its text all selected
		if e.clicked == key && k.time - e.clicked_at < DOUBLE_CLICK do e.select_all = true
		e.clicked = key
		e.clicked_at = k.time
	}
	ui := k.ui
	box(ui, x, y, w, CTRL_H, TYPING if typing else CONTROL_HOT if hot else CONTROL, with_alpha(ACCENT, 220) if typing else BORDER)
	shown := edit_text(k) if typing else typed if changed else value
	if secret do shown = strings.repeat("*", len(shown), context.temp_allocator)
	room, cy := w - 16, y + CTRL_H / 2
	if shown == "" && !typing {
		if placeholder != "" do text_fit(k, BODY, placeholder, x + 8, cy, room, FAINT)
		return
	}
	if !typing {
		text_fit(k, BODY, shown, x + 8, cy, room, TEXT)
		return
	}
	from := shown // the end that fits
	for len(from) > 0 && width_of(ui, BODY, from) > room - 4 do from = from[1:]
	lh := height_of(ui, BODY)
	if e.select_all && from != "" { // the whole text highlighted: a key, or Backspace, replaces it
		rect(ui, x + 8, cy - lh / 2, x + 8 + width_of(ui, BODY, from), cy + lh / 2, with_alpha(ACCENT, 90))
	}
	text_mid(k, BODY, from, x + 8, cy, TEXT)
	if math.mod(k.time, 1.0) < 0.55 {
		caret := x + 8 + width_of(ui, BODY, from) + 1
		rect(ui, caret, cy - lh / 2, caret + 1, cy + lh / 2, ACCENT)
	}
	return
}

// A row with a text box on its right: Enter, or a click on the box, types into it.
field_row :: proc(k: ^Kit, label: string, key: rawptr, value: string, max: int, placeholder: string, secret := false) -> (typed: string, changed: bool) {
	r := row(k, ROW_H, true)
	if !r.shown {
		take_enter(k, r.focused) // the page scrolls to it first
		return
	}
	row_label(k, r, label)
	return field_box(k, r.id, r.focused, ctrl_x(r), ctrl_y(r), ctrl_w(r), key, value, max, placeholder, secret)
}

// A row editing a string: what is typed kept with `allocator`.
text_row :: proc(k: ^Kit, label: string, value: ^string, max: int, placeholder: string, allocator: mem.Allocator, secret := false) {
	if typed, changed := field_row(k, label, value, value^, max, placeholder, secret); changed {
		value^ = strings.clone(typed, allocator)
	}
}


// ---------------------------------------------------------------------------------
// Colour

// A colour: its hex in a box, typed, and its swatch, which opens the picker (as Enter
// does).
color_row :: proc(k: ^Kit, label: string, ref: Color_Ref) {
	r := row(k, ROW_H, true)
	cw, cx, cy := ctrl_w(r), ctrl_x(r), ctrl_y(r)
	sx := cx + cw - CTRL_H
	open := k.popup.kind == .Color && k.popup.owner == r.id
	toggle_picker := take_enter(k, r.focused)
	if r.shown && take(k, r.id, sx, cy, CTRL_H, CTRL_H) do toggle_picker = true
	if toggle_picker {
		if open {
			popup_close(k)
		} else {
			popup_open_color(k, r.id, ref, sx, cy)
		}
	}
	if !r.shown do return
	row_label(k, r, label)
	color, set := color_get(ref)
	hex := utils.format_hex_color(utils.Rgba(color)) if set else ""
	if typed, changed := field_box(k, r.id, false, cx, cy, cw - CTRL_H - 6, color_key(ref), hex, 6, "none", false); changed {
		if parsed, ok := utils.parse_hex_color(typed); ok {
			color_set(ref, rl.Color(parsed))
		} else if typed == "" {
			color_clear(ref)
		}
	}
	ui := k.ui
	hot := over(k, sx, cy, CTRL_H, CTRL_H) || open
	edge := ACCENT if hot else rl.Color{255, 255, 255, 70}
	if color, set = color_get(ref); set {
		box(ui, sx, cy, CTRL_H, CTRL_H, color, edge)
	} else { // no colour: the art's own, a slash through an empty box
		box(ui, sx, cy, CTRL_H, CTRL_H, CONTROL, edge)
		line(ui, {sx + 5, cy + CTRL_H - 5}, {sx + CTRL_H - 5, cy + 5}, 1.5, BAD)
	}
}

// ---------------------------------------------------------------------------------
// Buttons and chips

// A button, `primary` in the accent; a disabled one is shown but never pressed. True
// when pressed, by a click or by Enter while it has the focus.
button_at :: proc(k: ^Kit, x, y, w, h: f32, caption: string, primary, disabled: bool) -> bool {
	return button_styled(k, x, y, w, h, caption, primary, disabled, BUTTON, y + h / 2)
}

button_w :: proc(k: ^Kit, caption: string) -> f32 {
	return max(width_of(k.ui, BUTTON, caption) + 28, 80)
}

// A button in `style`, its caption centred on the line `cy`.
button_styled :: proc(k: ^Kit, x, y, w, h: f32, caption: string, primary, disabled: bool, style: Style, cy: f32) -> bool {
	id := nav_next(k)
	focused := nav_focused(k, id, y, h)
	hot := !disabled && over(k, x, y, w, h)
	focus_ring(k, focused, x, y, w, h, RADIUS)
	button_ground(k, x, y, w, h, primary, disabled, hot)
	tw := width_of(k.ui, style, caption)
	text_mid(k, style, caption, x + (w - tw) / 2, cy, FAINT if disabled else TEXT)
	pressed := take(k, id, x, y, w, h) || take_enter(k, focused)
	return pressed && !disabled
}

button_ground :: proc(k: ^Kit, x, y, w, h: f32, primary, disabled, hot: bool) {
	if disabled {
		box(k.ui, x, y, w, h, DISABLED, DISABLED_EDGE)
	} else if primary {
		rrect(k.ui, x, y, w, h, RADIUS, ACCENT_HOT if hot else ACCENT)
	} else {
		box(k.ui, x, y, w, h, CONTROL_HOT if hot else CONTROL, BORDER_HOT if hot else BORDER)
	}
}

chip_w :: proc(k: ^Kit, caption: string) -> f32 {
	return width_of(k.ui, BODY, caption) + 30
}

// A chip that is on or off, as a filter is: a tick box and its name. True when pressed.
chip :: proc(k: ^Kit, x, y: f32, caption: string, on: bool) -> bool {
	ui := k.ui
	w := chip_w(k, caption)
	id := nav_next(k)
	focused := nav_focused(k, id, y, CTRL_H)
	hot := over(k, x, y, w, CTRL_H)
	focus_ring(k, focused, x, y, w, CTRL_H, RADIUS)
	box(ui, x, y, w, CTRL_H, ACCENT_SOFT if on else CONTROL_HOT if hot else CONTROL, with_alpha(ACCENT, 120) if on else BORDER)
	bx, by := x + 8, y + CTRL_H / 2 - 5
	if on {
		rrect(ui, bx, by, 10, 10, 2.5, ACCENT)
		line(ui, {bx + 2.5, by + 5}, {bx + 4.5, by + 7.5}, 1.4, TEXT)
		line(ui, {bx + 4.5, by + 7.5}, {bx + 8, by + 2.5}, 1.4, TEXT)
	} else {
		box_r(ui, bx, by, 10, 10, 2.5, TYPING, {255, 255, 255, 50})
	}
	text_mid(k, BODY, caption, x + 22, y + CTRL_H / 2, TEXT if on else MUTED)
	return take(k, id, x, y, w, CTRL_H) || take_enter(k, focused)
}

// ---------------------------------------------------------------------------------
// Key

// A key's row: what it does, and its key (`bound`, "" for none) on a chip; a click, or
// Enter, waits for the next key (capture.odin), and the row is lit while it does. The
// key pressed, once it is. `owner` names the row to the wait, the same each pass.
key_row :: proc(k: ^Kit, label: string, owner: int, bound: string) -> (key: string, rebound: bool) {
	ui := k.ui
	r := row(k, 24, true)
	key, rebound = capture_take(k, owner)
	if (r.shown && take(k, r.id, r.x, r.y, r.w, r.h)) || take_enter(k, r.focused) do capture_start(k, owner)
	if !r.shown do return
	waiting := capturing(k, owner)
	shown: string
	current := key if rebound else bound
	switch {
	case waiting && capture_modifier(k) != "": shown = fmt.tprintf("%s + ...", capture_modifier(k)) // alone, or with the next
	case waiting:                              shown = "Press a key"
	case current == "":                        shown = "unbound"
	case:                                      shown = strings.to_upper(current, context.temp_allocator)
	}
	kh := f32(18)
	kw := max(width_of(ui, BOLD, shown) + 18, 54)
	kx, ky := r.x + r.w - 8 - kw, r.y + (r.h - kh) / 2
	text_fit(k, LABEL, label, r.x + 10, r.y + r.h / 2, kx - r.x - 20, TEXT)
	if waiting {
		pulse := 0.5 + 0.5 * math.sin(f32(k.time) * 6)
		rrect(ui, kx, ky, kw, kh, RADIUS, with_alpha(ACCENT, u8(110 + 120 * pulse)))
	} else {
		box(ui, kx, ky, kw, kh, CONTROL_HOT if r.hot else CONTROL, BORDER_HOT if r.hot else BORDER)
	}
	text_mid(k, BOLD, shown, kx + (kw - width_of(ui, BOLD, shown)) / 2, ky + kh / 2, TEXT if waiting || current != "" else FAINT)
	return
}
