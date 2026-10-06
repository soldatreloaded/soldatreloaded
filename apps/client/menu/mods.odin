package menu

import "core:fmt"

import res "../../../core/resources"
import "../ui"

// The mods in mods/, a row each, the one in use marked: the default (the game's own)
// first. A new one is a copy of the default, named, to change as one likes; one picked
// is used at once (Use, or a second click), or deleted, after a second press to be sure.
// The default, and the mod in use, can't be deleted.

Mods :: struct {
	names:      []string,
	listed:     bool, // read from mods/ since the page was opened
	selected:   int,  // the mod picked, -1 for none
	clicked_at: f64,  // when it was picked, so a second click soon after uses it
	name:       string, // the new mod's, as typed
	confirm:    bool,   // Delete pressed once: pressed again, it deletes
	note:       string, // what was last done, or why it couldn't be
	note_bad:   bool,
}

MOD_ROW :: 24

mods_destroy :: proc(mods: ^Mods) {
	res.mods_list_destroy(mods.names)
	delete(mods.name)
	delete(mods.note)
	mods^ = {}
}

page_mods :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	mods := &menu.mods
	if !mods.listed do mods_relist(mods, menu.config.graphics.mod)
	in_use := mod_in_use(menu)

	ui.section(k, "NEW MOD")
	if typed, changed := ui.field_row(k, "Name", &mods.name, mods.name, res.MOD_NAME_MAX, "A copy of the default, to change"); changed {
		set_text(&mods.name, typed)
	}
	create := ui.edit_entered(k, &mods.name)
	{
		r := ui.row(k, ui.ROW_H + 4, false)
		bw := ui.button_w(k, "Create")
		if r.shown && ui.button_at(k, ui.ctrl_x(r) + ui.ctrl_w(r) - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Create", true, mods.name == "") do create = true
	}
	if create && mods.name != "" do mod_create(menu)

	ui.section(k, "MODS")
	for name, i in mods.names {
		r := ui.row(k, MOD_ROW, true)
		picked := i == mods.selected
		if ui.take_enter(k, r.focused) do pick(mods, i)
		if r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h) {
			if picked && k.time - mods.clicked_at < ui.DOUBLE_CLICK && i != in_use do use(menu, name)
			pick(mods, i)
			mods.clicked_at = k.time
		}
		if !r.shown do continue
		cy := r.y + r.h / 2
		if picked {
			ui.rrect(u, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
			ui.rrect(u, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
		}
		status := "In use" if i == in_use else "The game's own" if i == 0 else ""
		sw := ui.width_of(u, ui.BODY, status)
		ui.text_fit(k, ui.LABEL, name, r.x + 12, cy, r.w - sw - 36, ui.TEXT)
		if status != "" do ui.text_mid(k, ui.BODY, status, r.x + r.w - 10 - sw, cy, ui.ACCENT if i == in_use else ui.FAINT)
	}

	// the action bar: Use, and Delete before it; what was last done, or the mod picked
	x, w := k.x, k.w
	selected := mods.selected >= 0 && mods.selected < len(mods.names)
	used, px := big_button(menu, x + w, "USE", true, !selected || mods.selected == in_use)
	if used && selected do use(menu, mods.names[mods.selected])
	deletable := selected && mods.selected != 0 && mods.selected != in_use
	if !deletable do mods.confirm = false
	deleted, dx := big_button(menu, px - 10, "SURE?" if mods.confirm else "DELETE", false, !deletable)
	if deleted && deletable {
		if mods.confirm do mod_delete(menu, mods.names[mods.selected])
		else do mods.confirm = true
	}
	tw := dx - x - 16
	switch {
	case mods.confirm:
		footer_text(menu, x, tw, fmt.tprintf("Delete %s and all its files? Press again to.", mods.names[mods.selected]), ui.WARN)
	case mods.note != "":
		footer_text(menu, x, tw, mods.note, ui.WARN if mods.note_bad else ui.GOOD)
	case selected && mods.selected == 0:
		footer_text(menu, x, tw, "The game's own look and sound. It can't be deleted.", ui.MUTED)
	case selected && mods.selected == in_use:
		footer_text(menu, x, tw, "In use. Use another to delete this one.", ui.MUTED)
	case:
		footer_text(menu, x, tw, "A mod changes only the files it has; the rest come from the default.", ui.MUTED)
	}
}

// mods/ read again; the mod in use picked.
@(private = "file")
mods_relist :: proc(mods: ^Mods, active: string) {
	res.mods_list_destroy(mods.names)
	mods.names = res.mods_list(res.MODS_DIR)
	mods.listed = true
	mods.selected = 0
	for name, i in mods.names do if name == active do mods.selected = i
	mods.confirm = false
}

// The row of the mod in use: the default's when none, or one no longer there, is set.
@(private = "file")
mod_in_use :: proc(menu: ^Menu) -> int {
	for name, i in menu.mods.names do if name == menu.config.graphics.mod do return i
	return 0
}

@(private = "file")
pick :: proc(mods: ^Mods, i: int) {
	if i != mods.selected do mods.confirm = false
	mods.selected = i
}

@(private = "file")
use :: proc(menu: ^Menu, name: string) {
	menu.request = Use_Mod{name}
}

@(private = "file")
mod_create :: proc(menu: ^Menu) {
	mods := &menu.mods
	name := mods.name
	if problem := res.mod_create(res.MODS_DIR, name); problem != "" {
		note(mods, problem, true)
		return
	}
	note(mods, fmt.tprintf("%s made, a copy of the default in mods/%s.", name, name), false)
	made := name
	mods_relist(mods, menu.config.graphics.mod)
	for n, i in mods.names do if n == made do mods.selected = i
	set_text(&mods.name, "")
}

@(private = "file")
mod_delete :: proc(menu: ^Menu, name: string) {
	mods := &menu.mods
	gone := fmt.tprintf("%s deleted.", name)
	if !res.mod_delete(res.MODS_DIR, name) {
		note(mods, fmt.tprintf("%s couldn't be deleted (a file of it may be open).", name), true)
		mods.confirm = false
		return
	}
	note(mods, gone, false)
	mods_relist(mods, menu.config.graphics.mod)
}

@(private = "file")
note :: proc(mods: ^Mods, text: string, bad: bool) {
	set_text(&mods.note, text)
	mods.note_bad = bad
}
