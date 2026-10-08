package menu

import "core:fmt"
import "core:strings"

import "../ui"

// The taunt editor: on the left, the taunts there are, in the slots' order; on the
// right, what the key does (chat, team chat, a radio call or an emote), its message, its
// call or its emote, then the keyboard, whose key the combo is bound on. Update writes the
// loaded taunt into the config, Clear unbinds it (Delete too).

Taunt_Editor :: struct {
	slot:     int, // the taunt loaded, -1 for none
	modifier: Taunt_Modifier,
	mode:     Taunt_Mode,
	radio:    int,    // Radio's call, 1 to 9, 0 for none picked yet
	emote:    int,    // Emote's, its place in EMOTES
	text:     string, // the message being edited, Chat and Team's
}

TAUNT_TEXT_MAX :: 255

@(rodata)
TAUNT_MODE_NAMES := [Taunt_Mode]string {
	.Chat  = "Chat",
	.Team  = "Team chat",
	.Radio = "Radio",
	.Emote = "Emote",
}
@(rodata)
TAUNT_MODIFIER_NAMES := [?]string{"Alt", "Ctrl", "Shift"}

// The keyboard's rows: where each begins in the slots, and how many keys it has.
@(rodata)
KEY_ROW_FIRST := [4]int{0, 10, 20, 29}
@(rodata)
KEY_ROW_COUNT := [4]int{10, 10, 9, 7}

page_taunts :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	editor := &menu.taunts
	x, w, top_y := k.x, k.w, k.y
	two := w >= 560 // below that the two columns would be too narrow for the modes and the keyboard
	col_w := (w - 20) / 2 if two else w
	ends := [2]f32{top_y, top_y}

	k.w = col_w
	ui.section(k, "TAUNTS")
	any := false
	for slot in 0 ..< TAUNT_SLOTS {
		if taunt, found := taunt_at(menu.config, slot); found {
			any = true
			taunt_row(menu, slot, taunt)
		}
	}
	if !any {
		if r := ui.row(k, ui.ROW_H, false); r.shown {
			ui.text_fit(k, ui.BODY, "None yet: pick a key on the keyboard and type what it says.", r.x + 10, r.y + r.h / 2, r.w - 20, ui.MUTED)
		}
	}
	ui.gap(k, 6)
	ends[0] = k.y

	k.x = x + col_w + 20 if two else x
	k.y = top_y if two else ends[0]
	ui.section(k, "EDIT")
	{ // the four modes, one of them always on, on a second row when the column is narrow
		r := ui.row(k, ui.ROW_H, false)
		cx := r.x
		for name, mode in TAUNT_MODE_NAMES {
			if cx > r.x && cx + ui.chip_w(k, name) > r.x + r.w {
				r = ui.row(k, ui.ROW_H, false)
				cx = r.x
			}
			if ui.chip(k, cx, r.y + (r.h - ui.CTRL_H) / 2, name, editor.mode == mode) do editor.mode = mode
			cx += ui.chip_w(k, name) + 8
		}
	}
	if editor.mode == .Radio { // the call, picked from the config's as the radio menu has them
		names: [9]string
		calls := [3]^type_of(menu.config.radio.call_1){&menu.config.radio.call_1, &menu.config.radio.call_2, &menu.config.radio.call_3}
		for i in 1 ..= 9 {
			call := calls[(i - 1) / 3]
			// cut to the box's room: the radio's own lines in the game show them whole
			names[i - 1] = fmt.tprintf("%s - %s", cut(call.name, 20), cut(call.places[(i - 1) % 3], 12))
		}
		if picked := ui.select_box(k, "Call", names[:], nil, max(editor.radio, 1) - 1); picked >= 0 do editor.radio = picked + 1
	} else if editor.mode == .Emote { // the emote, as the game names them
		names: [len(EMOTES)]string
		for emote, i in EMOTES do names[i] = emote.title
		if picked := ui.select_box(k, "Emote", names[:], nil, editor.emote); picked >= 0 do editor.emote = picked
	} else { // the message, typed; what makes it a console line (quotes, semicolons) is left out
		r := ui.row(k, ui.ROW_H, true)
		if typed, changed := ui.field_box(k, r.id, r.focused, r.x + 10, ui.ctrl_y(r), r.w - 20, &editor.text, editor.text, TAUNT_TEXT_MAX, "What the key says", false); changed {
			set_text(&editor.text, typed)
		}
		if ui.edit_entered(k, &editor.text) do taunt_update(menu) // Enter in the message is the Update button
	}
	if picked := ui.select_box(k, "Modifier", TAUNT_MODIFIER_NAMES[:], nil, int(editor.modifier)); picked >= 0 {
		editor.modifier = Taunt_Modifier(picked)
	}
	ui.section(k, "KEY")
	{ // the 36 keys, as the number row and the qwerty rows; a taunt's key is tinted
		KEY_GAP :: 5
		KH :: 24
		kw := min(28, (col_w - 9 * KEY_GAP) / 10)
		for row_i in 0 ..< 4 {
			r := ui.row(k, KH + 6, false)
			count := KEY_ROW_COUNT[row_i]
			row_w := f32(count) * kw + f32(count - 1) * KEY_GAP
			kx := r.x + (r.w - row_w) / 2
			for key in 0 ..< count {
				slot := KEY_ROW_FIRST[row_i] + key
				_, bound := taunt_at(menu.config, slot)
				selected := editor.slot == slot
				id := ui.nav_next(k)
				focused := ui.nav_focused(k, id, r.y, KH)
				hot := ui.over(k, kx, r.y, kw, KH)
				if (r.shown && ui.take(k, id, kx, r.y, kw, KH)) || ui.take_enter(k, focused) do taunt_load(menu, slot)
				if r.shown {
					ui.focus_ring(k, focused, kx, r.y, kw, KH, ui.RADIUS)
					fill := ui.ACCENT_SOFT if selected else {232, 80, 30, 22} if bound else ui.CONTROL_HOT if hot else ui.CONTROL
					edge := ui.ACCENT if selected else ui.with_alpha(ui.ACCENT, 140) if bound else ui.BORDER
					ui.box(u, kx, r.y, kw, KH, fill, edge)
					ui.text_mid(k, ui.BOLD, strings.to_upper(TAUNT_SLOT_KEYS[slot], context.temp_allocator), kx + kw / 2, r.y + KH / 2, ui.TEXT if bound || selected else ui.MUTED)
				}
				kx += kw + KEY_GAP
			}
		}
	}
	ui.gap(k, 6)
	ends[1] = k.y

	k.x, k.w = x, w
	k.y = max(ends[0], ends[1])
	k.scrolling = false
	none := editor.slot < 0
	if k.erase do taunt_clear(menu) // Delete clears the loaded taunt
	pressed, bx := big_button(menu, x + w, "UPDATE", true, none)
	if pressed {
		taunt_update(menu)
	} else if cleared, _ := big_button(menu, bx - 12, "CLEAR", false, none); cleared {
		taunt_clear(menu)
	}
}

// A taunt as its list row reads: the combo, as Alt+Q, what it is (a radio call, an
// emote, or said to everyone or the team) and its words. A click, or Enter, loads it into the
// editor.
@(private = "file")
taunt_row :: proc(menu: ^Menu, slot: int, taunt: Taunt) {
	k := &menu.kit
	u := k.ui
	r := ui.row(k, ui.ROW_H, true)
	if (r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h)) || ui.take_enter(k, r.focused) do taunt_load(menu, slot)
	if !r.shown do return
	combo := fmt.tprintf("%s+%s", TAUNT_MODIFIER_NAMES[taunt.modifier], strings.to_upper(TAUNT_SLOT_KEYS[slot], context.temp_allocator))
	what := TAUNT_MODE_NAMES[taunt.mode]
	cy, cx := r.y + r.h / 2, r.x + 10
	cw := min(ui.width_of(u, ui.BOLD, combo), 88)
	ui.text_fit(k, ui.BOLD, combo, cx, cy, cw, ui.TEXT)
	cx += cw + 12
	ww := min(ui.width_of(u, ui.BODY, what), 110)
	ui.text_fit(k, ui.BODY, what, cx, cy, ww, ui.ACCENT if taunt.mode == .Radio || taunt.mode == .Emote else ui.MUTED)
	cx += ww + 12
	text := taunt.text
	#partial switch taunt.mode {
	case .Radio: text = radio_words(menu, taunt.radio)
	case .Emote: text = EMOTES[taunt.emote].title
	}
	ui.text_fit(k, ui.BODY, text, cx, cy, r.w - 10 - cx + r.x, ui.MUTED)
}

// The editor's taunt: the slot's bind, or a new taunt on `slot` (chat, on alt) when
// nothing is bound there.
@(private = "file")
taunt_load :: proc(menu: ^Menu, slot: int) {
	editor := &menu.taunts
	ui.edit_stop(&menu.kit)
	editor.slot = slot
	taunt, found := taunt_at(menu.config, slot)
	if !found do taunt = {}
	editor.modifier = taunt.modifier
	editor.mode = taunt.mode
	editor.radio = taunt.radio
	editor.emote = taunt.emote
	set_text(&editor.text, taunt.text)
}

// The loaded taunt written back: its radio call, its emote, or its message; the slot
// unbound when the message is empty. The game saves it with the rest as it closes.
@(private = "file")
taunt_update :: proc(menu: ^Menu) {
	editor := &menu.taunts
	if editor.slot < 0 do return
	if editor.mode == .Radio do editor.radio = max(editor.radio, 1) // the box shows the first call when none was picked
	said := editor.mode == .Chat || editor.mode == .Team
	text := taunt_compose(editor.mode, editor.text, editor.radio, editor.emote) if !said || editor.text != "" else ""
	taunt_set(menu, editor.slot, editor.modifier, text)
}

// The loaded taunt unbound, and the editor emptied.
@(private = "file")
taunt_clear :: proc(menu: ^Menu) {
	editor := &menu.taunts
	if editor.slot < 0 do return
	taunt_set(menu, editor.slot, editor.modifier, "")
	taunt_load(menu, editor.slot)
}

// A radio call's own words, `radio` 1 to 9: the call's name and its place's, as the
// radio menu says them.
@(private = "file")
radio_words :: proc(menu: ^Menu, radio: int) -> string {
	calls := [3]^type_of(menu.config.radio.call_1){&menu.config.radio.call_1, &menu.config.radio.call_2, &menu.config.radio.call_3}
	call := calls[(radio - 1) / 3]
	return fmt.tprintf("%s %s", call.name, call.places[(radio - 1) % 3])
}

// `text` cut to `n` bytes at most.
@(private = "file")
cut :: proc(text: string, n: int) -> string {
	return text[:min(len(text), n)]
}
