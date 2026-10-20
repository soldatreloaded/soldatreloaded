package menu

import "core:fmt"
import "core:slice"
import "core:strings"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../hud"
import "../ui"

// The HUD editor: a mod's HUD (its hud part's layout.json, docs/srmod.md) over the whole
// window as the game draws it, with made-up numbers, each part outlined. A part is picked
// by a click or from the panel's list, dragged or nudged with the arrows, and in the
// panel shown or hidden, its bar's style and fill, its text's alignment, what it is kept
// beside as the view widens, how it is turned; and the whole HUD's opacity. Saved, it is
// a mod of its own, a hud alone with the pictures of the HUD it began from
// (res.hud_mod_write), and worn: "My HUD", or the mod the editor made that it was opened
// on, saved over. A .srmod worn is a file open, so one saved over is let go of first.

Hud_Editor :: struct {
	open:     bool,
	from:     string, // the title of the mod whose HUD it began from, Classic's or another's
	description: string, // the mod saved's: where its HUD began, kept as it is saved over
	target:   string, // the mod it saves into: the editor's own, opened on or saved once; "" until then
	art:      hud.Art,
	pictures: map[string][]byte, // the hud part's files of the mod it began from, saved with the layout
	scales:   map[string]f32,    // and each one's pixels to a unit, as that mod says
	layout:   res.Hud_Layout,
	saved:    res.Hud_Layout, // as it was opened or last saved: unsaved while they differ, and Reset's
	undo:     [dynamic]res.Hud_Layout,
	picked:   hud.Hud_Part,
	dragging: bool, // the picked part, by the mouse
	moved:    bool, // and it has moved since it was taken
	grab:     [2]f32, // where the mouse took it, or the panel
	start:    res.Hud_Layout, // the layout as the drag began
	panel:    [2]f32, // the panel's top-left, in units
	panel_h:  f32,    // its height, as it was laid out last
	panel_on: bool,   // the panel being dragged by its title
	saving:   enum {None, Letting_Go, Writing},
	leaving:  bool, // Escape once with changes unsaved: again leaves without them
	note:     string,
	note_bad: bool,
	data:     hud.Hud_Data, // the made-up numbers it is drawn with
}

PANEL_W :: 262
PANEL_TITLE_H :: 30
EDITOR_NAME :: "My_HUD" // the mod it saves into, the first time: then My_HUD_2...
EDITOR_TITLE :: "My HUD"

// The editor opened on the HUD of the mod `name` ("" for Classic's): its layout as the
// game wears it, and its pictures drawn as the game draws them.
hud_editor_open :: proc(menu: ^Menu, name: string) {
	e := &menu.editor
	hud_editor_close(menu)
	choice: [res.Part]string
	choice[.Hud] = name
	mod := res.mod_make(res.MODS_DIR, choice)
	hud.art_load(&e.art, mod)
	hud.art_opaque(&e.art, mod)
	e.art.book.mod = {} // every picture is in hand: the mod is let go of below
	e.from = strings.clone("Classic")
	if name != "" && mod.worn != nil {
		source := res.worn_mod(mod.worn, .Hud)
		e.pictures = res.srmod_part_files(source, .Hud)
		e.scales = res.hud_picture_scales(source, e.pictures)
		delete(e.from)
		e.from = strings.clone(source.info.title)
		if strings.has_prefix(source.info.description, res.HUD_EDITOR_MADE) {
			e.target = strings.clone(name)
			e.description = strings.clone(source.info.description)
		}
	}
	res.mod_destroy(&mod)
	if e.description == "" do e.description = fmt.aprintf("%s, from %s's HUD.", res.HUD_EDITOR_MADE, e.from)

	e.open = true
	e.layout = e.art.layout
	e.saved = e.layout
	e.panel = {12, 12}
	e.panel_h = 300
	e.data = sample_data(menu)
	ui.kit_reset_page(&menu.kit)
}

hud_editor_close :: proc(menu: ^Menu) {
	e := &menu.editor
	if !e.open do return
	hud.art_destroy(&e.art)
	for path, data in e.pictures {
		delete(path)
		delete(data)
	}
	delete(e.pictures)
	for path in e.scales do delete(path)
	delete(e.scales)
	delete(e.undo)
	delete(e.from)
	delete(e.target)
	delete(e.description)
	delete(e.note)
	e^ = {}
	ui.kit_reset_page(&menu.kit)
}

// What the HUD shows in the editor: a soldier with a bit of everything left, a round
// being led.
@(private = "file")
sample_data :: proc(menu: ^Menu) -> (d: hud.Hud_Data) {
	d.players[0] = {active = true, name = "You", team = .Alpha, kills = 12}
	d.players[1] = {active = true, name = "Them", team = .Bravo, kills = 9}
	d.me = 0
	d.limit = 10
	d.captures[.Alpha], d.captures[.Bravo] = 3, 1
	d.flags_home[.Alpha], d.flags_home[.Bravo] = true, false
	d.mine = {health = sim.DEFAULT_HEALTH * 0.75, weapon = .AK74, ammo = 24, ammo_bar = 0.6, fire_bar = 0.5, jets = 0.7, grenades = 4}
	d.weapon_names = menu.weapon_names
	return
}

// The editor's frame: the HUD and its parts' outlines, the panel, and what the mouse and
// the keys do to them.
hud_editor_draw :: proc(menu: ^Menu, u: ^ui.Ui) {
	e := &menu.editor
	k := &menu.kit
	if e.saving != .None do editor_save(menu)

	popup_was := k.popup.kind != .None
	ui.popup_input(k)
	rl.EndBlendMode()
	background(u, rl.GetTime())
	ui.rect(u, 0, 0, u.width, VIEW_H, {8, 10, 15, 150})
	help :: "Drag a part, or pick it in the list.  Arrows nudge it, Shift by 10.  Ctrl+Z undoes.  Esc leaves."
	help_x := max((u.width - ui.width_of(u, ui.TINY, help)) / 2, e.panel.x + PANEL_W + 16)
	ui.text_mid(k, ui.TINY, help, help_x, 14, ui.FAINT)

	// the HUD, as the game draws it
	e.art.layout = e.layout
	hud.draw_bars(u, &e.art, &e.data.mine)
	hud.draw_team_box(u, &e.art, &e.data)
	hud.draw_bar_texts(u, &e.art, &e.data)
	hud.draw_team_scores(u, &e.art, &e.data)
	rl.EndBlendMode()

	over_panel := ui.inside(u.mouse, e.panel.x, e.panel.y, PANEL_W, e.panel_h)
	hot, has_hot := part_under(e, u)
	if over_panel || popup_was || e.dragging do has_hot = false
	for part in hud.Hud_Part {
		box := hud.part_box(u, &e.art, &e.data, part)
		shown := hud.part_shown(&e.layout, part)^
		color := ui.with_alpha(ui.TEXT, 34 if shown else 18)
		if has_hot && part == hot do color = ui.with_alpha(ui.TEXT, 150)
		if part == e.picked do color = ui.ACCENT
		outline(u, box, color, 2 if part == e.picked else 1)
	}
	picked_box := hud.part_box(u, &e.art, &e.data, e.picked)
	tag := picked_tag(e)
	ty := picked_box.y - 14 if picked_box.y > 20 else picked_box.y + picked_box.height + 3
	ui.text_at(k, ui.TINY, tag, picked_box.x, ty, ui.ACCENT)

	before := e.layout
	editor_panel(menu, u)
	if e.layout != before && !e.dragging do push_undo(e, before)

	// the canvas: a part taken and dragged, or the arrows
	if !popup_was && !over_panel && k.click && has_hot {
		k.click = false
		e.picked = hot
		e.dragging, e.moved = true, false
		e.grab = u.mouse
		e.start = e.layout
	}
	if e.dragging {
		if !k.mouse_down {
			e.dragging = false
		} else {
			by := u.mouse - e.grab
			if !e.moved && (abs(by.x) >= 1 || abs(by.y) >= 1) {
				e.moved = true
				push_undo(e, e.start)
			}
			if e.moved do e.layout = hud.part_moved(u, e.start, e.picked, by)
		}
	}
	if k.edit.key == nil && k.popup.kind == .None {
		step: f32 = 10 if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) else 1
		nudge: [2]f32
		if key_hit(.LEFT) do nudge.x -= step
		if key_hit(.RIGHT) do nudge.x += step
		if key_hit(.UP) do nudge.y -= step
		if key_hit(.DOWN) do nudge.y += step
		if nudge != {} && !e.dragging {
			if hud.part_spreads(e.picked) do nudge.x *= hud.wide(u)
			push_undo(e, e.layout)
			e.layout = hud.part_moved(u, e.layout, e.picked, nudge)
		}
		if (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) && key_hit(.Z) do editor_undo(e)
	}
	if k.back && k.popup.kind == .None {
		k.back = false
		editor_leave(menu)
	}
	ui.popup_draw(k)
}

// The picked part's name, over its outline: "(hidden)" after it while it isn't shown.
@(private = "file")
picked_tag :: proc(e: ^Hud_Editor) -> string {
	name := hud.HUD_PART_NAMES[e.picked]
	return name if hud.part_shown(&e.layout, e.picked)^ else fmt.tprintf("%s (hidden)", name)
}

// The part under the mouse: the smallest box it is in, so a part over another can be
// taken.
@(private = "file")
part_under :: proc(e: ^Hud_Editor, u: ^ui.Ui) -> (under: hud.Hud_Part, found: bool) {
	smallest := f32(1e9)
	for part in hud.Hud_Part {
		box := hud.part_box(u, &e.art, &e.data, part)
		pad: f32 = 3 // a thin bar is easier to take
		if !ui.inside(u.mouse, box.x - pad, box.y - pad, box.width + 2 * pad, box.height + 2 * pad) do continue
		if area := box.width * box.height; area < smallest {
			smallest = area
			under, found = part, true
		}
	}
	return
}

@(private = "file")
outline :: proc(u: ^ui.Ui, box: rl.Rectangle, color: rl.Color, pixels: f32) {
	t := pixels * ui.hairline(u)
	x0, y0, x1, y1 := box.x - t, box.y - t, box.x + box.width + t, box.y + box.height + t
	ui.rect(u, x0, y0, x1, y0 + t, color)
	ui.rect(u, x0, y1 - t, x1, y1, color)
	ui.rect(u, x0, y0, x0 + t, y1, color)
	ui.rect(u, x1 - t, y0, x1, y1, color)
}

@(private = "file")
push_undo :: proc(e: ^Hud_Editor, layout: res.Hud_Layout) {
	if len(e.undo) >= 200 do ordered_remove(&e.undo, 0)
	append(&e.undo, layout)
	e.leaving = false
}

@(private = "file")
editor_undo :: proc(e: ^Hud_Editor) {
	if layout, ok := pop_safe(&e.undo); ok do e.layout = layout
}

@(private = "file", rodata)
STYLE_NAMES := [res.Hud_Bar_Style]string{.Number = "Number", .Across = "Across", .Down = "Down"}
@(private = "file", rodata)
NADE_STYLE_NAMES := [res.Hud_Bar_Style]string{.Number = "Count", .Across = "Row", .Down = "Column"}
@(private = "file", rodata)
FILL_NAMES := [res.Hud_Fill]string{.Forward = "Forward", .Backward = "Backward"}
@(private = "file", rodata)
ALIGN_NAMES := [res.Hud_Align]string{.Left = "Starts there", .Right = "Ends there"}
@(private = "file", rodata)
ANCHOR_NAMES := [res.Hud_Anchor]string{.Corner = "Its place", .Health = "Health icon", .Ammo = "Ammo icon", .Jet = "Jets icon"}

// The panel: the part picked and what can be changed of it, the whole HUD's opacity,
// and Undo, Reset, Save and Close. Dragged about by its title.
@(private = "file")
editor_panel :: proc(menu: ^Menu, u: ^ui.Ui) {
	e := &menu.editor
	k := &menu.kit
	x, y := e.panel.x, e.panel.y
	ui.box(u, x, y, PANEL_W, e.panel_h, {14, 17, 25, 240}, ui.with_alpha(ui.TEXT, 30))

	// its title, which drags it
	if !e.panel_on && k.click && ui.over(k, x, y, PANEL_W, PANEL_TITLE_H) {
		k.click = false
		e.panel_on = true
		e.grab = u.mouse - e.panel
	}
	if e.panel_on {
		if !k.mouse_down do e.panel_on = false
		else do e.panel = {clamp(u.mouse.x - e.grab.x, 0, u.width - PANEL_W), clamp(u.mouse.y - e.grab.y, 0, VIEW_H - PANEL_TITLE_H)}
	}
	ui.text_mid(k, ui.LABEL, "HUD editor", x + 12, y + PANEL_TITLE_H / 2, ui.TEXT)
	from := fmt.tprintf("from %s", e.from)
	ui.text_fit(k, ui.TINY, from, x + 12 + ui.width_of(u, ui.LABEL, "HUD editor") + 8, y + PANEL_TITLE_H / 2, PANEL_W - 110, ui.FAINT)

	ui.kit_column(k, x + 6, PANEL_W - 12, y + PANEL_TITLE_H, VIEW_H + 1000)
	k.scrolling = false
	l := &e.layout
	part := e.picked
	ui.enum_select(k, "Part", &part, slice.enumerated_array(&hud.HUD_PART_NAMES))
	if part != e.picked {
		e.picked = part
		e.dragging = false
	}
	ui.toggle(k, "Shown", hud.part_shown(l, part))
	if bar := hud.part_bar(l, part); bar != nil {
		ui.enum_select(k, "Shown as", &bar.style, slice.enumerated_array(&STYLE_NAMES))
		if bar.style != .Number do ui.enum_select(k, "Fills", &bar.fill, slice.enumerated_array(&FILL_NAMES))
		if part == .Ammo_Bar && bar.style != .Number do ui.enum_select(k, "Reload fills", &l.ammo.reload_fill, slice.enumerated_array(&FILL_NAMES))
	}
	if part == .Nades do ui.enum_select(k, "Shown as", &l.nades.style, slice.enumerated_array(&NADE_STYLE_NAMES))
	if text := hud.part_text(l, part); text != nil do ui.enum_select(k, "Its place", &text.align, slice.enumerated_array(&ALIGN_NAMES))
	if anchor := hud.part_anchor(l, part); anchor != nil do ui.enum_select(k, "Kept beside", anchor, slice.enumerated_array(&ANCHOR_NAMES))
	if turn := hud.part_rotate(l, part); turn != nil do ui.slider(k, "Turned", turn, -180, 180, 1, "%d deg")
	at := where_at(l, part)
	r := ui.row(k, 18, false)
	ui.text_fit(k, ui.TINY, fmt.tprintf("At %d, %d of 640 by 480", at.x, at.y), r.x + 10, r.y + r.h / 2, r.w - 20, ui.FAINT)

	ui.section(k, "WHOLE HUD")
	ui.slider(k, "Opacity", &l.alpha, 0, 255, 1, "%d")

	ui.gap(k, 6)
	// two rows of two, each half the panel
	half: f32 = (PANEL_W - 12 - 16 - 6) / 2
	button :: proc(k: ^ui.Kit, r: ui.Row, second: bool, w: f32, caption: string, primary, disabled: bool) -> bool {
		x := r.x + 8 + (w + 6 if second else 0)
		return ui.button_at(k, x, r.y + 4, w, ui.CTRL_H, caption, primary, disabled)
	}
	b := ui.row(k, ui.CTRL_H + 8, false)
	if button(k, b, false, half, "Undo", false, len(e.undo) == 0) do editor_undo(e)
	if button(k, b, true, half, "Reset", false, e.layout == e.saved) {
		push_undo(e, e.layout)
		e.layout = e.saved
	}
	c := ui.row(k, ui.CTRL_H + 8, false)
	if button(k, c, false, half, "Close", false, false) do editor_leave(menu)
	if button(k, c, true, half, "Save", true, e.saving != .None) do e.saving = .Letting_Go
	if e.note != "" {
		n := ui.row(k, 18, false)
		ui.text_fit(k, ui.TINY, e.note, n.x + 10, n.y + n.h / 2, n.w - 20, ui.WARN if e.note_bad else ui.GOOD)
	} else if e.layout != e.saved {
		n := ui.row(k, 18, false)
		ui.text_fit(k, ui.TINY, "Not saved yet.", n.x + 10, n.y + n.h / 2, n.w - 20, ui.MUTED)
	}
	e.panel_h = k.y - y + 8
}

// Where `part` is in the layout, as its file has it.
@(private = "file")
where_at :: proc(l: ^res.Hud_Layout, part: hud.Hud_Part) -> [2]i32 {
	switch part {
	case .Health_Icon: return l.health.icon.at
	case .Ammo_Icon:   return l.ammo.icon.at
	case .Jet_Icon:    return l.jet.icon.at
	case .Fire_Frame:  return l.fire.frame.at
	case .Nades:       return l.nades.at
	case .Team_Box:    return l.team_box.at
	case .Status:      return l.status.at
	case .Health_Bar, .Ammo_Bar, .Jet_Bar, .Fire_Bar: return hud.part_bar(l, part).at
	case .Bullets, .Weapon: return hud.part_text(l, part).at
	}
	return {}
}

// Escape, or Close: the editor left, unless there are changes unsaved, which a second
// asks to leave without.
@(private = "file")
editor_leave :: proc(menu: ^Menu) {
	e := &menu.editor
	if e.layout != e.saved && !e.leaving {
		e.leaving = true
		editor_note(e, "Not saved: Esc or Close again to leave without saving.", true)
		return
	}
	hud_editor_close(menu)
}

@(private = "file")
editor_note :: proc(e: ^Hud_Editor, text: string, bad: bool) {
	delete(e.note)
	e.note = strings.clone(text)
	e.note_bad = bad
}

// Saving, a step a frame: the mod saved into let go of where the client wears it (a
// .srmod worn is a file open, which can't be written over), then written, and its HUD
// worn.
@(private = "file")
editor_save :: proc(menu: ^Menu) {
	e := &menu.editor
	if e.target == "" {
		name, title := EDITOR_NAME, EDITOR_TITLE
		for n := 2; res.mod_exists(res.MODS_DIR, name); n += 1 {
			name, title = fmt.tprintf("%s_%d", EDITOR_NAME, n), fmt.tprintf("%s %d", EDITOR_TITLE, n)
		}
		e.target = strings.clone(name)
	}
	parts: [res.Part]string
	worn := false
	for p in res.Part {
		parts[p] = worn_from(menu, p)
		if strings.equal_fold(parts[p], e.target) {
			parts[p] = ""
			worn = true
		}
	}
	switch e.saving {
	case .None:
	case .Letting_Go:
		e.saving = .Writing
		if worn do use_parts(menu, parts) // the client lets go of it before the next frame
	case .Writing:
		e.saving = .None
		title := EDITOR_TITLE
		if e.target != EDITOR_NAME do title = strings.concatenate({EDITOR_TITLE, " ", strings.trim_prefix(e.target, EDITOR_NAME + "_")}, context.temp_allocator)
		if !res.hud_mod_write(res.MODS_DIR, e.target, title, e.description, e.layout, e.pictures, e.scales) {
			editor_note(e, "It couldn't be saved: is the disk full, or the mod open elsewhere?", true)
			return
		}
		e.saved = e.layout
		e.leaving = false
		mods_relist(&menu.mods)
		parts[.Hud] = e.target
		use_parts(menu, parts)
		editor_note(e, fmt.tprintf("Saved as %s, and worn. Its HUD chip is on the Mods page.", title), false)
	}
}

// A key pressed this frame, or held and repeating.
@(private = "file")
key_hit :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}
