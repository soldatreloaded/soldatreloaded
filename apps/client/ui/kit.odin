package ui

import "core:math"
import "core:strings"

import rl "vendor:raylib"

// A pass over a screen's widgets: the C menu's Ui, and what of its MainMenu the widgets
// keep. Each frame the screen gathers the keys and the mouse (kit_input), then lays its
// page out in one pass (kit_begin ... kit_end), each widget drawing itself where the
// layout puts it and acting on what was gathered: the click is the first widget's under
// it to take, the keys the focused widget's, and what none takes moves the focus.
//
// The page is a column of rows going down from `y`, scrolled by `scroll`; what lies
// outside [top, bottom] is not drawn (there is no clipping), and `extent` is how far the
// page reaches. A popup open over it has the keys and the click first, and nothing under
// it is hovered.

SCROLL_STEP :: 30
SCROLL_W :: 3
SCROLL_HIT :: 16 // the bar is thin; the mouse gets more
SCROLL_PAGE :: 0 // the page's scrollbar; a list's are numbered after it

Kit :: struct {
	ui:            ^Ui,

	// kept from pass to pass
	in_page:       bool, // the keys are on the page's widgets, not on the screen's own
	nav:           int,  // the page's widget with the keys, in their order
	keys_used:     bool, // the keys moved the focus since the mouse last moved: it shows
	last_mouse:    rl.Vector2,
	scroll:        f32, // the page's, in units
	scroll_max:    f32,
	scroll_follow: bool, // the keys moved the focus: the page scrolls to it
	drag:          int,  // the slider being dragged, -1 for none
	scroll_drag:   int,  // the scrollbar being dragged, -1 for none
	scroll_grab:   f32,  // where on its knob it was taken, from the knob's top
	popup:         Popup,
	picked_owner:  int, // a list's choice, for the widget that opened it to take on its next pass
	picked:        int,
	edit:          Edit,
	capture:       Capture,
	axis:          [2]int, // a controller's stick, as a direction, so a push is one step
	time:          f64,    // seconds, for the caret's blink and the pulses

	// gathered since the last pass
	gathered:      Gathered,
	mouse_down:    bool, // the left button, for a slider's drag

	// the pass's
	click:         bool, // used up by the first widget that takes it
	held:          bool, // the left button is down: a slider follows the cursor
	blocked:       bool, // a popup is open: nothing under it is hovered or clicked
	block:         rl.Rectangle,
	move, side:    int,  // the arrows: up and down, left and right
	page:          int,  // Q and E, a controller's shoulders: the pages turned
	enter, back:   bool,
	erase:         bool, // Delete
	wheel:         int,  // notches, up positive: a list's, else the page's
	show_focus:    bool,
	nav_count:     int,  // the focusable widgets laid out so far
	x, w, y:       f32,
	top, bottom:   f32,
	extent:        f32,
	scrolling:     bool, // the rows here scroll with the page
}

Gathered :: struct {
	click:       bool,
	wheel:       int,
	move, side:  int,
	page:        int,
	enter, back: bool,
	erase:       bool,
}

kit_init :: proc(k: ^Kit) {
	k^ = {drag = -1, scroll_drag = -1, picked_owner = -1, capture = {owner = -1}}
}

// The keys and the mouse since the last pass: a key being captured takes them all, a
// text field the keys; the rest move the focus.
kit_input :: proc(k: ^Kit) {
	g := &k.gathered
	if capture_input(k) do return
	k.mouse_down = rl.IsMouseButtonDown(.LEFT)
	if rl.IsMouseButtonPressed(.LEFT) do g.click = true
	g.wheel += int(math.round(rl.GetMouseWheelMove()))
	if edit_input(k) do return

	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	if key_hit(.UP) do kit_nav(k, -1, 0, false, false)
	if key_hit(.DOWN) do kit_nav(k, 1, 0, false, false)
	if key_hit(.LEFT) do kit_nav(k, 0, -1, false, false)
	if key_hit(.RIGHT) do kit_nav(k, 0, 1, false, false)
	if key_hit(.TAB) do kit_nav(k, -1 if shift else 1, 0, false, false)
	if key_hit(.ENTER) || key_hit(.KP_ENTER) || key_hit(.SPACE) do kit_nav(k, 0, 0, true, false)
	if key_hit(.ESCAPE) do kit_nav(k, 0, 0, false, true)
	if key_hit(.Q) do kit_turn(k, -1)
	if key_hit(.E) do kit_turn(k, 1)
	if key_hit(.DELETE) do g.erase = true

	// a controller's pad, its buttons, and its stick as the pad: a step each time it is
	// pushed over
	if !rl.IsGamepadAvailable(0) do return
	pad :: proc(button: rl.GamepadButton) -> bool {return rl.IsGamepadButtonPressed(0, button)}
	if pad(.LEFT_FACE_UP) do kit_nav(k, -1, 0, false, false)
	if pad(.LEFT_FACE_DOWN) do kit_nav(k, 1, 0, false, false)
	if pad(.LEFT_FACE_LEFT) do kit_nav(k, 0, -1, false, false)
	if pad(.LEFT_FACE_RIGHT) do kit_nav(k, 0, 1, false, false)
	if pad(.RIGHT_FACE_DOWN) do kit_nav(k, 0, 0, true, false)
	if pad(.RIGHT_FACE_RIGHT) do kit_nav(k, 0, 0, false, true)
	if pad(.LEFT_TRIGGER_1) do kit_turn(k, -1)
	if pad(.RIGHT_TRIGGER_1) do kit_turn(k, 1)
	for axis in 0 ..< 2 {
		value := rl.GetGamepadAxisMovement(0, .LEFT_X if axis == 0 else .LEFT_Y)
		dir := 1 if value > 0.61 else -1 if value < -0.61 else 0
		if dir != 0 && dir != k.axis[axis] do kit_nav(k, dir if axis == 1 else 0, dir if axis == 0 else 0, false, false)
		if dir != 0 || abs(value) < 0.37 do k.axis[axis] = dir
	}
}

// Moves of the focus, gathered for the next pass.
kit_nav :: proc(k: ^Kit, move, side: int, enter, back: bool) {
	g := &k.gathered
	g.move += move
	g.side += side
	g.enter |= enter
	g.back |= back
	k.keys_used = true
	if move != 0 do k.scroll_follow = true
}

@(private = "file")
kit_turn :: proc(k: ^Kit, pages: int) {
	k.gathered.page += pages
	k.keys_used = true
}

// A key gone down this frame, or repeating while held.
@(private = "package")
key_hit :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

// The pass begins: what was gathered is its to use up. The focus shows once the keys
// moved it, until the mouse moves.
kit_begin :: proc(k: ^Kit, ui: ^Ui, time: f64) {
	k.ui = ui
	k.time = time
	g := k.gathered
	k.gathered = {}
	moved := abs(ui.mouse.x - k.last_mouse.x) > 0.01 || abs(ui.mouse.y - k.last_mouse.y) > 0.01
	if moved || g.click do k.keys_used = false
	k.last_mouse = ui.mouse
	if !k.mouse_down do k.drag, k.scroll_drag = -1, -1
	k.click, k.held = g.click, k.mouse_down
	k.blocked = false
	k.move, k.side, k.page = g.move, g.side, g.page
	k.enter, k.back, k.erase = g.enter, g.back, g.erase
	k.wheel = g.wheel
	k.show_focus = k.keys_used
	k.nav_count = 0
}

// The page's column: `w` wide from `x`, shown between `top` and `bottom`, scrolled.
kit_column :: proc(k: ^Kit, x, w, top, bottom: f32) {
	k.scroll = clamp(k.scroll, 0, k.scroll_max)
	k.x, k.w = x, w
	k.top, k.bottom = top, bottom
	k.y = top - k.scroll
	k.extent = top
	k.scrolling = true
}

// After the page: what no widget took. Up and down move the focus along the page; up
// from its first widget, or a page with none, leaves it, which is the screen's to take
// (true).
kit_page_keys :: proc(k: ^Kit) -> (left: bool) {
	if k.in_page {
		if k.move < 0 && k.nav == 0 {
			k.in_page = false
			left = true
		} else if k.move != 0 {
			k.nav += k.move
		}
	}
	k.nav = clamp(k.nav, 0, max(k.nav_count - 1, 0))
	if k.in_page && k.nav_count == 0 {
		k.in_page = false
		left = true
	}
	return
}

// The page's scroll, by the wheel over `area`; its bar at `bar_x` when there is more
// than shows, dragged.
kit_page_scroll :: proc(k: ^Kit, area: rl.Rectangle, bar_x: f32) {
	k.scroll_max = max(k.extent - k.bottom, 0)
	if k.wheel != 0 && k.popup.kind == .None && inside(k.ui.mouse, area.x, area.y, area.width, area.height) {
		k.scroll -= f32(k.wheel) * SCROLL_STEP
		k.scroll_follow = false
	}
	k.scroll = clamp(k.scroll, 0, k.scroll_max)
	if k.scroll_max > 0 {
		track := k.bottom - k.top
		view := track / (track + k.scroll_max)
		knob := max(track * view, 16)
		pos := scroll_take(k, SCROLL_PAGE, bar_x, k.top, track, knob, k.scroll / k.scroll_max)
		k.scroll = pos * k.scroll_max
		scroll_draw(k, SCROLL_PAGE, bar_x, k.top, track, knob, pos)
	}
	k.wheel = 0
}

// The pass is over: a click on nothing takes the keyboard from a field.
kit_end :: proc(k: ^Kit) {
	if k.click do edit_stop(k)
}

// Everything that was going on (a drag, a popup, a field, a key awaited) let go, and
// the page back to its top: another page is shown.
kit_reset_page :: proc(k: ^Kit) {
	k.nav = 0
	k.scroll, k.scroll_max = 0, 0
	k.capture.owner = -1
	k.drag = -1
	popup_close(k)
	edit_stop(k)
	k.edit.dirty, k.edit.entered = nil, nil
}

// ---------------------------------------------------------------------------------
// The mouse and the focus

inside :: proc(p: rl.Vector2, x, y, w, h: f32) -> bool {
	return p.x >= x && p.x < x + w && p.y >= y && p.y < y + h
}

over :: proc(k: ^Kit, x, y, w, h: f32) -> bool {
	if k.blocked && inside(k.ui.mouse, k.block.x, k.block.y, k.block.width, k.block.height) do return false
	return inside(k.ui.mouse, x, y, w, h)
}

// The click, if it is on this box: used up, and the widget `id` (if any) takes the focus.
take :: proc(k: ^Kit, id: int, x, y, w, h: f32) -> bool {
	if !k.click || !over(k, x, y, w, h) do return false
	k.click = false
	if id >= 0 {
		k.in_page = true
		k.nav = id
	}
	return true
}

take_side :: proc(k: ^Kit, focused: bool) -> int {
	if !focused do return 0
	side := k.side
	k.side = 0
	return side
}

take_enter :: proc(k: ^Kit, focused: bool) -> bool {
	if !focused || !k.enter do return false
	k.enter = false
	return true
}

// The next widget in the keys' order.
nav_next :: proc(k: ^Kit) -> int {
	id := k.nav_count
	k.nav_count += 1
	return id
}

// Whether the widget `id` has the focus. A focused one out of view brings the page to
// it, if the keys put the focus there.
nav_focused :: proc(k: ^Kit, id: int, y, h: f32) -> bool {
	focused := k.in_page && k.nav == id
	if focused && k.scrolling && k.scroll_follow {
		if y < k.top {
			k.scroll -= k.top - y + 6
		} else if y + h > k.bottom {
			k.scroll += y + h - k.bottom + 6
		}
	}
	return focused
}

focus_ring :: proc(k: ^Kit, focused: bool, x, y, w, h, r: f32) {
	if focused && k.show_focus do rrect(k.ui, x - 2, y - 2, w + 4, h + 4, r + 2, with_alpha(ACCENT, 170))
}

// ---------------------------------------------------------------------------------
// Scrollbars: the page's, and the lists' own

// A scrollbar's mouse: the bar `track` tall from `top` at `x`, its knob `knob` tall at
// `pos` (0 to 1) of the way down. A press on the knob holds it; one on the track beside
// it brings the knob there and holds on. The position, moved as the mouse drags. Called
// before whatever lies under the bar, so the press is the bar's.
scroll_take :: proc(k: ^Kit, id: int, x, top, track, knob, pos: f32) -> f32 {
	run := track - knob
	hit_x := x - (SCROLL_HIT - SCROLL_W) / 2
	if run <= 0 do return pos
	knob_y := top + run * pos
	mouse := k.ui.mouse
	if k.click && over(k, hit_x, top, SCROLL_HIT, track) {
		k.click = false
		k.scroll_drag = id
		k.scroll_grab = mouse.y - knob_y if inside(mouse, hit_x, knob_y, SCROLL_HIT, knob) else knob / 2
	}
	if k.scroll_drag == id && k.held {
		k.scroll_follow = false
		return clamp((mouse.y - k.scroll_grab - top) / run, 0, 1)
	}
	return pos
}

scroll_draw :: proc(k: ^Kit, id: int, x, top, track, knob, pos: f32) {
	active := k.scroll_drag == id || over(k, x - (SCROLL_HIT - SCROLL_W) / 2, top, SCROLL_HIT, track)
	rrect(k.ui, x, top + (track - knob) * pos, SCROLL_W, knob, SCROLL_W / 2, MUTED if active else FAINT)
}

// ---------------------------------------------------------------------------------
// Rows

// A row of the column: its box, whether it is in view, focused, under the cursor. The
// focused one, and the one under the cursor, are lit.
Row :: struct {
	x, y, w, h: f32,
	id:         int,
	shown:      bool,
	focused:    bool,
	hot:        bool,
}

row :: proc(k: ^Kit, h: f32, focusable: bool) -> Row {
	r := Row{x = k.x, y = k.y, w = k.w, h = h, id = -1}
	k.y += h
	if k.scrolling do k.extent = max(k.extent, r.y + h + k.scroll)
	r.shown = r.y >= k.top - 0.5 && r.y + h <= k.bottom + 0.5
	if focusable {
		r.id = nav_next(k)
		r.focused = nav_focused(k, r.id, r.y, h)
	}
	r.hot = r.shown && focusable && over(k, r.x, r.y, r.w, h)
	if r.shown && r.focused && k.show_focus {
		rrect(k.ui, r.x, r.y + 1, r.w, h - 2, RADIUS, ACCENT_SOFT)
		rrect(k.ui, r.x, r.y + 6, 2, h - 12, 1, ACCENT)
	} else if r.hot {
		rrect(k.ui, r.x, r.y + 1, r.w, h - 2, RADIUS, HOVER)
	}
	return r
}

gap :: proc(k: ^Kit, h: f32) {
	k.y += h
}

// A heading over the rows that follow: small tracked capitals, a rule after them.
section :: proc(k: ^Kit, title: string) {
	r := row(k, SECTION_H, false)
	if !r.shown do return
	cy := r.y + r.h - 10
	text_mid(k, SECTION, title, r.x + 2, cy, MUTED)
	tw := width_of(k.ui, SECTION, title)
	rule(k.ui, r.x + tw + 12, r.x + r.w, cy, LINE)
}

// Where a row's control goes: on its right, half of it at most.
ctrl_w :: proc(r: Row) -> f32 {return clamp(r.w * 0.5, 110, 220)}
ctrl_x :: proc(r: Row) -> f32 {return r.x + r.w - 8 - ctrl_w(r)}
ctrl_y :: proc(r: Row) -> f32 {return r.y + (r.h - CTRL_H) / 2}

row_label :: proc(k: ^Kit, r: Row, label: string) {
	text_fit(k, LABEL, label, r.x + 10, r.y + r.h / 2, r.w - ctrl_w(r) - 28, TEXT)
}

// ---------------------------------------------------------------------------------
// Text, as the menu places it

text_at :: proc(k: ^Kit, style: Style, str: string, x, y: f32, color: rl.Color) {
	write(k.ui, style, str, {x, y}, color)
}

// Text centred on the line `cy`.
text_mid :: proc(k: ^Kit, style: Style, str: string, x, cy: f32, color: rl.Color) {
	text_at(k, style, str, x, cy - height_of(k.ui, style) / 2, color)
}

// `str` cut to fit `width` in `style`, "..." where it was cut.
fit :: proc(k: ^Kit, style: Style, str: string, width: f32) -> string {
	if width_of(k.ui, style, str) <= width do return str
	for n := len(str); n > 0; n -= 1 {
		cut := strings.concatenate({str[:n], "..."}, context.temp_allocator)
		if width_of(k.ui, style, cut) <= width do return cut
	}
	return "..."
}

text_fit :: proc(k: ^Kit, style: Style, str: string, x, cy, width: f32, color: rl.Color) {
	text_mid(k, style, fit(k, style, str, width), x, cy, color)
}

// `str` in lines no wider than `width`, broken between words, from `y` down: the
// height it took.
text_wrap :: proc(k: ^Kit, style: Style, str: string, x, y, width: f32, color: rl.Color) -> f32 {
	lh := height_of(k.ui, style) + 2
	at := y
	line := ""
	rest := str
	for word in strings.fields_iterator(&rest) {
		trial := strings.concatenate({line, " " if line != "" else "", word}, context.temp_allocator)
		if line != "" && width_of(k.ui, style, trial) > width {
			text_at(k, style, line, x, at, color)
			at += lh
			line = word
		} else {
			line = trial
		}
	}
	if line != "" {
		text_at(k, style, line, x, at, color)
		at += lh
	}
	return at - y
}
