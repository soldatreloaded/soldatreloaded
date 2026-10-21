package menu

import "core:fmt"
import "core:strings"

import res "../../../core/resources"
import "../hud"
import "../ui"

// The taunt editor: the modifier every taunt key is held with (Alt, Ctrl or Shift), then
// the keyboard of taunt keys, then one line for the key picked from it — what it does
// (chat, a radio call or an emote), which (everyone or the team; the call; the emote), and
// the words it says. Everything binds at once, nothing to save; Delete or Remove unbinds.
// A radio call left wordless says its own; an emote's words, if any, go to everyone.

Taunt_Editor :: struct {
	slot:     int, // the taunt the keyboard has picked, -1 for none
	modifier: Taunt_Modifier, // the one every taunt is held with; changing it moves them all
	mode:     Taunt_Mode,
	radio:    int,    // Radio's call, 1 to 9, 0 for none picked yet
	emote:    int,    // Emote's, its place in EMOTES
	text:     string, // the words being edited
	vars:     bool,   // the list of the variables the words can carry, shown
}

TAUNT_TEXT_MAX :: 255

@(rodata)
TAUNT_MODIFIER_NAMES := [?]string{"Alt", "Ctrl", "Shift"}
// The three types a key's line chooses between; Chat's own line is to everyone or the team.
@(rodata)
TAUNT_TYPE_NAMES := [?]string{"Chat", "Radio", "Emote"}
@(rodata)
CHAT_TARGET_NAMES := [?]string{"Everyone", "Team"}

// The keyboard's rows: where each begins in the slots, and how many keys it has.
@(rodata)
KEY_ROW_FIRST := [4]int{0, 10, 20, 29}
@(rodata)
KEY_ROW_COUNT := [4]int{10, 10, 9, 7}

page_taunts :: proc(menu: ^Menu) {
	k := &menu.kit
	editor := &menu.taunts

	ui.section(k, "HELD WITH")
	{ // the modifier every taunt key is held with; changing it moves every taunt to it
		mod := int(editor.modifier)
		if chip_row(k, "Key", TAUNT_MODIFIER_NAMES[:], &mod) do taunts_set_modifier(menu, Taunt_Modifier(mod))
	}

	ui.section(k, "TAUNT KEYS")
	taunt_keyboard(menu)

	if editor.slot < 0 {
		if r := ui.row(k, ui.ROW_H, false); r.shown {
			ui.text_fit(k, ui.BODY, "Pick a key above, then set what it does below. It binds as you go — nothing to save.", r.x + 10, r.y + r.h / 2, r.w - 20, ui.MUTED)
		}
	} else {
		combo := fmt.tprintf("%s + %s", TAUNT_MODIFIER_NAMES[editor.modifier], strings.to_upper(TAUNT_SLOT_KEYS[editor.slot], context.temp_allocator))
		ui.section(k, combo)
		taunt_line(menu)
		taunt_vars(menu)
		if r := ui.row(k, ui.ROW_H, true); r.shown {
			bw := ui.button_w(k, "Remove")
			if ui.button_at(k, ui.ctrl_x(r) + ui.ctrl_w(r) - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Remove", false, false) do taunt_clear(menu)
			ui.text_fit(k, ui.BODY, "or press Delete", ui.ctrl_x(r), r.y + r.h / 2, ui.ctrl_w(r) - bw - 10, ui.MUTED)
		}
	}

	taunt_list(menu)
}

// The taunts there are, each a clickable row: the combo, what it does and the words it
// says. Clicking one picks its key into the editor above.
@(private = "file")
taunt_list :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	ui.section(k, "YOUR TAUNTS")
	any := false
	for slot in 0 ..< TAUNT_SLOTS {
		taunt, found := taunt_at(menu.config, slot)
		if !found do continue
		any = true
		r := ui.row(k, ui.ROW_H, true)
		if (r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h)) || ui.take_enter(k, r.focused) do taunt_load(menu, slot)
		if !r.shown do continue
		combo := fmt.tprintf("%s+%s", TAUNT_MODIFIER_NAMES[taunt.modifier], strings.to_upper(TAUNT_SLOT_KEYS[slot], context.temp_allocator))
		kind, words := taunt_summary(menu, taunt)
		cy, cx := r.y + r.h / 2, r.x + 10
		cw := min(ui.width_of(u, ui.BOLD, combo), 84)
		ui.text_fit(k, ui.BOLD, combo, cx, cy, cw, ui.ACCENT if slot == menu.taunts.slot else ui.TEXT)
		cx += cw + 12
		kw := min(ui.width_of(u, ui.BODY, kind), 96)
		ui.text_fit(k, ui.BODY, kind, cx, cy, kw, ui.MUTED)
		cx += kw + 12
		ui.text_fit(k, ui.BODY, words, cx, cy, r.x + r.w - 10 - cx, ui.MUTED)
	}
	if !any {
		if r := ui.row(k, ui.ROW_H, false); r.shown {
			ui.text_fit(k, ui.BODY, "None yet.", r.x + 10, r.y + r.h / 2, r.w - 20, ui.MUTED)
		}
	}
}

// A taunt as the list reads it: what it does, and the words it says (a radio call's own
// when it carries none).
@(private = "file")
taunt_summary :: proc(menu: ^Menu, taunt: Taunt) -> (kind: string, words: string) {
	switch taunt.mode {
	case .Chat:
		return "To everyone", taunt.text
	case .Team:
		return "To the team", taunt.text
	case .Radio:
		return "Radio", taunt.text if taunt.text != "" else radio_words(menu, max(taunt.radio, 1))
	case .Emote:
		return fmt.tprintf("Emote: %s", EMOTES[clamp(taunt.emote, 0, len(EMOTES) - 1)].title), taunt.text
	}
	return "", ""
}

// The one line for the picked key: a type dropdown, a target dropdown (which chat, which
// call, which emote) and the words. Any change binds the key at once.
@(private = "file")
taunt_line :: proc(menu: ^Menu) {
	k := &menu.kit
	editor := &menu.taunts
	changed := false

	r := ui.row(k, ui.ROW_H, false)
	y := ui.ctrl_y(r)
	x0, w := r.x + 10, r.w - 20 // the whole row, left-aligned: no label column eats the left
	GAP :: 8
	type_w := f32(84)
	avail := w - type_w - 2 * GAP
	target_w := clamp(avail * 0.45, 110, 160)
	tx := x0
	gx := x0 + type_w + GAP
	fx := gx + target_w + GAP
	text_w := max(x0 + w - fx, 80)

	// type: Chat, Radio or Emote
	kind := 1 if editor.mode == .Radio else 2 if editor.mode == .Emote else 0
	if picked := ui.dropdown_at(k, tx, y, type_w, TAUNT_TYPE_NAMES[:], kind); picked >= 0 && picked != kind {
		switch picked {
		case 0: editor.mode = .Chat
		case 1: editor.mode = .Radio; editor.radio = max(editor.radio, 1)
		case 2: editor.mode = .Emote
		}
		kind = picked
		changed = true
	}

	// target: which chat, which call, or which emote
	placeholder := "What the key says"
	switch kind {
	case 0: // chat: to everyone or the team
		cur := 1 if editor.mode == .Team else 0
		if picked := ui.dropdown_at(k, gx, y, target_w, CHAT_TARGET_NAMES[:], cur); picked >= 0 && picked != cur {
			editor.mode = .Team if picked == 1 else .Chat
			changed = true
		}
	case 1: // radio: the config's calls, as the radio menu has them
		names: [9]string
		calls := radio_calls(menu)
		for i in 1 ..= 9 {
			call := calls[(i - 1) / 3]
			names[i - 1] = fmt.tprintf("%s - %s", cut(call.name, 18), cut(call.places[(i - 1) % 3], 12))
		}
		cur := max(editor.radio, 1) - 1
		if picked := ui.dropdown_at(k, gx, y, target_w, names[:], cur); picked >= 0 {
			editor.radio = picked + 1
			changed = true
		}
		placeholder = fmt.tprintf("Says: %s", radio_words(menu, max(editor.radio, 1)))
	case 2: // emote
		names: [len(EMOTES)]string
		for emote, i in EMOTES do names[i] = emote.title
		if picked := ui.dropdown_at(k, gx, y, target_w, names[:], editor.emote); picked >= 0 {
			editor.emote = picked
			changed = true
		}
		placeholder = "Say too (optional)"
	}

	// the words: the message, the radio's own words, or an emote's line to everyone
	fid := ui.nav_next(k)
	focused := ui.nav_focused(k, fid, y, ui.CTRL_H)
	if typed, did := ui.field_box(k, fid, focused, fx, y, text_w, &editor.text, editor.text, TAUNT_TEXT_MAX, placeholder, false); did {
		set_text(&editor.text, typed)
		changed = true
	}

	if k.erase do taunt_clear(menu) // Delete unbinds the key
	else if changed do taunt_apply(menu)
}

// The variables the words can carry (hud.TAUNT_VARS), as one line naming a few until
// it's opened; open, each with what it fills in, two to a row where there's room. A
// click on one puts it in the words.
@(private = "file")
taunt_vars :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	editor := &menu.taunts
	if r := ui.row(k, ui.ROW_H, false); r.shown {
		caption := "Hide" if editor.vars else "Variables"
		bw := ui.button_w(k, caption)
		if ui.button_at(k, r.x + r.w - 10 - bw, ui.ctrl_y(r), bw, ui.CTRL_H, caption, false, false) do editor.vars = !editor.vars
		hint := "Click one to add it. {{name}} says it in capitals." if editor.vars else "Words can carry {time_left}, {score}, {killer} and more, filled in as the key says them."
		ui.text_fit(k, ui.BODY, hint, r.x + 10, r.y + r.h / 2, r.w - bw - 30, ui.MUTED)
	}
	if !editor.vars do return
	VAR_H :: 22
	r0 := ui.row(k, 0, false)
	columns := 2 if r0.w >= 460 else 1
	cell_w := (r0.w - 20) / f32(columns)
	name_w: f32 = 0
	for v in hud.TAUNT_VARS do name_w = max(name_w, ui.width_of(u, ui.BOLD, strings.concatenate({"{", v.name, "}"}, context.temp_allocator)))
	for i := 0; i < len(hud.TAUNT_VARS); i += columns {
		r := ui.row(k, VAR_H, false)
		if !r.shown do continue
		for c in 0 ..< columns {
			if i + c >= len(hud.TAUNT_VARS) do break
			v := hud.TAUNT_VARS[i + c]
			x := r.x + 10 + f32(c) * cell_w
			token := strings.concatenate({"{", v.name, "}"}, context.temp_allocator)
			if ui.over(k, x, r.y, cell_w - 6, VAR_H) do ui.rrect(u, x, r.y + 1, cell_w - 6, VAR_H - 2, ui.RADIUS, ui.HOVER)
			if ui.take(k, -1, x, r.y, cell_w - 6, VAR_H) do taunt_var_add(menu, token)
			cy := r.y + VAR_H / 2
			ui.text_fit(k, ui.BOLD, token, x + 6, cy, name_w, ui.ACCENT)
			ui.text_fit(k, ui.BODY, v.about, x + 6 + name_w + 10, cy, cell_w - name_w - 28, ui.MUTED)
		}
	}
	ui.gap(k, 4)
}

// `token` added to the end of the words: into the box while it is typed in, else bound
// at once.
@(private = "file")
taunt_var_add :: proc(menu: ^Menu, token: string) {
	editor := &menu.taunts
	if ui.edit_append(&menu.kit, &editor.text, token) do return
	if len(editor.text) + len(token) > TAUNT_TEXT_MAX do return
	set_text(&editor.text, strings.concatenate({editor.text, token}, context.temp_allocator))
	taunt_apply(menu)
}

// The 36 keys, the number row then the qwerty rows: a bound key tinted, the picked one
// lit; clicking or Enter picks it into the editor.
@(private = "file")
taunt_keyboard :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	editor := &menu.taunts
	KEY_GAP :: 5
	KH :: 24
	kw := min(34, (k.w - 9 * KEY_GAP) / 10)
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
	ui.gap(k, 6)
}

// A labelled row of chips, one always on; `value` is its index. True when it changed.
@(private = "file")
chip_row :: proc(k: ^ui.Kit, label: string, names: []string, value: ^int) -> (changed: bool) {
	r := ui.row(k, ui.ROW_H, false)
	cy := r.y + (r.h - ui.CTRL_H) / 2
	ui.text_fit(k, ui.BODY, label, r.x, r.y + r.h / 2, 40, ui.MUTED)
	cx := ui.ctrl_x(r) + 44
	for name, i in names {
		if ui.chip(k, cx, cy, name, value^ == i) && value^ != i {
			value^ = i
			changed = true
		}
		cx += ui.chip_w(k, name) + 8
	}
	return
}

// The editor set to the key's taunt, or emptied for a fresh one. The modifier is the
// global one, not the taunt's own.
@(private = "file")
taunt_load :: proc(menu: ^Menu, slot: int) {
	editor := &menu.taunts
	ui.edit_stop(&menu.kit)
	editor.slot = slot
	taunt, found := taunt_at(menu.config, slot)
	if !found do taunt = {}
	editor.mode = taunt.mode
	editor.radio = taunt.radio
	editor.emote = taunt.emote
	set_text(&editor.text, taunt.text)
}

// The editor's taunt bound to its key at once, at the global modifier: its call, emote or
// message. A chat line with no message unbinds; a radio call stands on its own.
@(private = "file")
taunt_apply :: proc(menu: ^Menu) {
	editor := &menu.taunts
	if editor.slot < 0 do return
	if editor.mode == .Radio do editor.radio = max(editor.radio, 1)
	said := editor.mode == .Chat || editor.mode == .Team
	text := taunt_compose(editor.mode, editor.text, editor.radio, editor.emote) if !said || editor.text != "" else ""
	taunt_set(menu, editor.slot, editor.modifier, text)
}

// The picked key unbound, its editor kept so another does can be set on it at once.
@(private = "file")
taunt_clear :: proc(menu: ^Menu) {
	editor := &menu.taunts
	if editor.slot < 0 do return
	taunt_set(menu, editor.slot, editor.modifier, "")
	set_text(&editor.text, "")
	editor.mode = .Chat
}

// The modifier every taunt is held with changed to `new`: each taunt moves from the old
// combo to the new one, and the editor remembers it.
@(private = "file")
taunts_set_modifier :: proc(menu: ^Menu, new: Taunt_Modifier) {
	if new == menu.taunts.modifier do return
	for slot in 0 ..< TAUNT_SLOTS {
		if taunt, found := taunt_at(menu.config, slot); found {
			taunt_set(menu, slot, new, taunt_compose(taunt.mode, taunt.text, taunt.radio, taunt.emote))
		}
	}
	menu.taunts.modifier = new
}

// The modifier the taunts are on, for the editor to open at: the first found taunt's, or
// Alt when there are none.
taunts_modifier :: proc(config: ^res.Client_Config) -> Taunt_Modifier {
	for slot in 0 ..< TAUNT_SLOTS {
		if taunt, found := taunt_at(config, slot); found do return taunt.modifier
	}
	return .Alt
}

// The config's three radio calls, in order.
@(private = "file")
radio_calls :: proc(menu: ^Menu) -> [3]^type_of(menu.config.radio.call_1) {
	return {&menu.config.radio.call_1, &menu.config.radio.call_2, &menu.config.radio.call_3}
}

// A radio call's own words, `radio` 1 to 9: the call's name and its place's, as the radio
// menu says them.
@(private = "file")
radio_words :: proc(menu: ^Menu, radio: int) -> string {
	call := radio_calls(menu)[(radio - 1) / 3]
	return fmt.tprintf("%s %s", call.name, call.places[(radio - 1) % 3])
}

// `text` cut to `n` bytes at most.
@(private = "file")
cut :: proc(text: string, n: int) -> string {
	return text[:min(len(text), n)]
}
