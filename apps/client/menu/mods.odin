package menu

import "core:fmt"
import "core:os"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../online"
import "../ui"

// The mods, a row each, the one in use marked: Classic, the game's own, first, then the
// player's, from mods/. A new one is an empty folder, named, to put files in to change;
// one of the player's picked says how, and opens its folder. One picked is used at once
// (Use, or a second click; Reload, for the one in use, to see what changed), or deleted
// after a second press to be sure. Classic, and the mod in use, can't be deleted.
//
// Under them, the mods' catalogue (online's catalog.odin): each mod the mods repository
// publishes, installed, or updated to its newest version, in a click, its download's
// progress shown; one picked says what it is and whose. A mod installed is the player's,
// in mods/, as one made here is; one in use, updated, is loaded again.

Mods :: struct {
	listings:   []res.Mod_Listing,
	versions:   map[string]string, // each of the player's mods' version, as its about.json says
	listed:     bool, // read from mods/ since the page was opened
	selected:   int,  // the mod picked, -1 for none
	clicked_at: f64,  // when it was picked, so a second click soon after uses it
	about:      int,  // the catalogue's mod picked, to say what it is; -1 for none
	name:       string, // the new mod's, as typed
	confirm:    bool,   // Delete pressed once: pressed again, it deletes
	note:       string, // what was last done, or why it couldn't be
	note_bad:   bool,
}

MOD_ROW :: 24
CATALOG_ROW :: 36
PROGRESS_W :: 110 // an install's progress bar

mods_destroy :: proc(mods: ^Mods) {
	res.mods_list_destroy(mods.listings)
	versions_forget(mods)
	delete(mods.versions)
	delete(mods.name)
	delete(mods.note)
	mods^ = {}
}

page_mods :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	mods := &menu.mods
	if !mods.listed {
		mods_relist(mods, menu.config.graphics.mod)
		mods.about = -1
		// the catalogue asked for as the page opens, unless it is in, or on its way
		if menu.catalog.state == .Idle || menu.catalog.state == .Failed do online.catalog_refresh(menu.catalog, menu.config.network.mods_index)
	}
	install_taken(menu)
	in_use := mod_in_use(menu)

	ui.section(k, "NEW MOD")
	if typed, changed := ui.field_row(k, "Name", &mods.name, mods.name, res.MOD_NAME_MAX, "The new mod's name"); changed {
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
	for listing, i in mods.listings {
		r := ui.row(k, MOD_ROW, true)
		picked := i == mods.selected
		if ui.take_enter(k, r.focused) do pick(mods, i)
		if r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h) {
			if picked && k.time - mods.clicked_at < ui.DOUBLE_CLICK && i != in_use do use(menu, listing.name)
			pick(mods, i)
			mods.clicked_at = k.time
		}
		if !r.shown do continue
		cy := r.y + r.h / 2
		if picked {
			ui.rrect(u, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
			ui.rrect(u, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
		}
		status := "In use" if i == in_use else "Built in" if listing.builtin else ""
		if version := mods.versions[listing.name]; status == "" && version != "" do status = fmt.tprintf("v%s", version)
		sw := ui.width_of(u, ui.BODY, status)
		ui.text_fit(k, ui.LABEL, listing.name, r.x + 12, cy, r.w - sw - 36, ui.TEXT)
		if status != "" do ui.text_mid(k, ui.BODY, status, r.x + r.w - 10 - sw, cy, ui.ACCENT if i == in_use else ui.FAINT)
	}

	if mods.selected >= 0 && mods.selected < len(mods.listings) && !mods.listings[mods.selected].builtin {
		page_making(menu, mods.listings[mods.selected].name)
	}
	page_catalog(menu)

	// the action bar: Use, and Delete before it; what was last done, or the mod picked
	x, w := k.x, k.w
	selected := mods.selected >= 0 && mods.selected < len(mods.listings)
	// the one in use, used again: loaded anew from its files, so a change to them shows
	used, px := big_button(menu, x + w, "RELOAD" if mods.selected == in_use else "USE", true, !selected)
	if used && selected do use(menu, mods.listings[mods.selected].name)
	builtin := selected && mods.listings[mods.selected].builtin
	deletable := selected && !builtin && mods.selected != in_use
	if !deletable do mods.confirm = false
	deleted, dx := big_button(menu, px - 10, "SURE?" if mods.confirm else "DELETE", false, !deletable)
	if deleted && deletable {
		if mods.confirm do mod_delete(menu, mods.listings[mods.selected].name)
		else do mods.confirm = true
	}
	tw := dx - x - 16
	c := menu.catalog
	switch {
	case mods.about >= 0 && mods.about < len(c.mods):
		m := &c.mods[mods.about]
		ui.text_fit(k, ui.BODY, m.description, x, ACTION_CY - 7, tw, ui.TEXT)
		ui.text_fit(k, ui.BODY, fmt.tprintf("By %s. %s", m.author, m.licence), x, ACTION_CY + 9, tw, ui.MUTED)
	case mods.confirm:
		footer_text(menu, x, tw, fmt.tprintf("Delete %s and all its files? Press again to.", mods.listings[mods.selected].name), ui.WARN)
	case mods.note != "":
		footer_text(menu, x, tw, mods.note, ui.WARN if mods.note_bad else ui.GOOD)
	case builtin:
		footer_text(menu, x, tw, "The game's own look and sound, under every other mod. It can't be deleted.", ui.MUTED)
	case selected && mods.selected == in_use:
		footer_text(menu, x, tw, "In use. Use another to delete this one.", ui.MUTED)
	case:
		footer_text(menu, x, tw, "A mod changes only the files it has; the rest come from Classic.", ui.MUTED)
	}
}

// How to make the player's mod `name`: what to put in its folder, and where; and its
// folder opened, to put them there.
@(private = "file", rodata)
MAKING_LINES := [?]string {
	"Drop gostek-gfx, weapons-gfx, sparks-gfx, interface-gfx, sfx, textures,",
	"scenery-gfx, mod.ini or txt/font.ini into its folder. What it hasn't comes from Classic.",
}

@(private = "file")
page_making :: proc(menu: ^Menu, name: string) {
	k := &menu.kit
	ui.section(k, fmt.tprintf("MAKING %s", strings.to_upper(name, context.temp_allocator)))
	for line in MAKING_LINES {
		r := ui.row(k, 15, false)
		if r.shown do ui.text_fit(k, ui.BODY, line, r.x + 12, r.y + r.h / 2, r.w - 24, ui.MUTED)
	}
	r := ui.row(k, ui.ROW_H + 6, false)
	caption := fmt.tprintf("Open mods/%s/", name)
	bw := ui.button_w(k, caption)
	if r.shown && ui.button_at(k, r.x + 12, r.y + (r.h - ui.CTRL_H) / 2, bw, ui.CTRL_H, caption, false, false) {
		folder_open(utils.temp_path(res.MODS_DIR, name))
	}
}

// A folder shown in the system's file browser.
@(private = "file")
folder_open :: proc(path: string) {
	full, err := os.get_absolute_path(path, context.temp_allocator)
	if err != nil do return
	when ODIN_OS == .Windows {
		full, _ = strings.replace_all(full, "/", "\\", context.temp_allocator) // explorer reads its own slashes
	}
	rl.OpenURL(strings.clone_to_cstring(full, context.temp_allocator))
}

// The catalogue's section: each mod it has, and what may be done with it; or why there
// are none to show.
@(private = "file")
page_catalog :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	mods := &menu.mods
	c := menu.catalog
	ui.section(k, "GET MODS")
	switch c.state {
	case .Idle, .Fetching:
		catalog_line(k, "Asking for the mods' catalogue...", ui.MUTED)
	case .Failed:
		r := ui.row(k, ui.ROW_H + 4, false)
		bw := ui.button_w(k, "Try again")
		if r.shown {
			ui.text_fit(k, ui.BODY, c.error, r.x + 12, r.y + r.h / 2, r.w - bw - 32, ui.WARN)
			if ui.button_at(k, r.x + r.w - 8 - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Try again", false, false) {
				online.catalog_refresh(c, menu.config.network.mods_index)
			}
		}
	case .Ready:
		if len(c.mods) == 0 do catalog_line(k, "No mods in the catalogue yet.", ui.MUTED)
		busy := c.install != nil && online.install_busy(c.install)
		for &m, i in c.mods {
			r := ui.row(k, CATALOG_ROW, true)
			// the row's action first, so a click on it is the button's, not the row's
			if r.shown do catalog_action(menu, r, &m, busy)
			if ui.take_enter(k, r.focused) || (r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h)) {
				mods.about = i
				mods.selected = -1
				mods.confirm = false
			}
			if !r.shown do continue
			if i == mods.about {
				ui.rrect(u, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
				ui.rrect(u, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
			}
			room := r.w - PROGRESS_W - 40
			ui.text_fit(k, ui.LABEL, m.name, r.x + 12, r.y + r.h / 2 - 7, room, ui.TEXT)
			meta := fmt.tprintf("v%s  -  by %s  -  %.1f MB", m.version, m.author, f32(m.size) / (1024 * 1024))
			ui.text_fit(k, ui.TINY, meta, r.x + 12, r.y + r.h / 2 + 8, room, ui.FAINT)
		}
	}
}

// A catalogue mod's action, on the right of its row: its install's progress, while it
// is installed; Install, or Update to a newer version; or why neither.
@(private = "file")
catalog_action :: proc(menu: ^Menu, r: ui.Row, m: ^online.Catalog_Mod, busy: bool) {
	k := &menu.kit
	u := k.ui
	c := menu.catalog
	right, cy := r.x + r.w - 8, r.y + r.h / 2
	if i := c.install; i != nil && online.install_busy(i) && i.mod.name == m.name {
		state, done := online.install_progress(i)
		x := right - PROGRESS_W
		ui.rrect(u, x, cy + 6, PROGRESS_W, 3, 1.5, ui.TRACK)
		if state == .Downloading {
			if done > 0 do ui.rrect(u, x, cy + 6, PROGRESS_W * done, 3, 1.5, ui.ACCENT)
			ui.text_mid(k, ui.TINY, fmt.tprintf("Downloading  %d%%", int(done * 100)), x, cy - 5, ui.MUTED)
		} else {
			ui.rrect(u, x, cy + 6, PROGRESS_W, 3, 1.5, ui.ACCENT)
			ui.text_mid(k, ui.TINY, "Unpacking...", x, cy - 5, ui.MUTED)
		}
		return
	}
	version, installed := menu.mods.versions[m.name]
	status, caption := "", ""
	switch {
	case installed && version == m.version: status = "Installed"
	case installed && version != "":        caption = "Update"
	case installed || folder_taken(menu, m.name): status = "Name taken" // a mod of the player's own, not the catalogue's
	case:                                   caption = "Install"
	}
	if status != "" {
		ui.text_mid(k, ui.BODY, status, right - ui.width_of(u, ui.BODY, status), cy, ui.FAINT)
		return
	}
	bw := ui.button_w(k, caption)
	if ui.button_at(k, right - bw, r.y + (r.h - ui.CTRL_H) / 2, bw, ui.CTRL_H, caption, caption == "Install", busy) {
		online.catalog_install(c, m^, res.MODS_DIR)
		delete(menu.mods.note)
		menu.mods.note = ""
	}
}

// Whether a mod of the player's is in mods/ by `name`, in any case, without a version
// of the catalogue's: one it made, which an install mustn't overwrite.
@(private = "file")
folder_taken :: proc(menu: ^Menu, name: string) -> bool {
	for listing in menu.mods.listings {
		if !listing.builtin && strings.equal_fold(listing.name, name) do return true
	}
	return false
}

@(private = "file")
catalog_line :: proc(k: ^ui.Kit, text: string, color: rl.Color) {
	r := ui.row(k, ui.ROW_H, false)
	if r.shown do ui.text_fit(k, ui.BODY, text, r.x + 12, r.y + r.h / 2, r.w - 24, color)
}

// An install that has ended, acted on once: the mods listed again with it among them,
// picked, and loaded again if it is the one in use; or why it failed.
@(private = "file")
install_taken :: proc(menu: ^Menu) {
	i := menu.catalog.install
	if i == nil || i.taken do return
	state, _ := online.install_progress(i)
	switch state {
	case .Done:
		i.taken = true
		note(&menu.mods, fmt.tprintf("%s %s installed.", i.mod.name, i.mod.version), false)
		mods_relist(&menu.mods, menu.config.graphics.mod)
		for listing, n in menu.mods.listings do if listing.name == i.mod.name do menu.mods.selected = n
		if i.mod.name == menu.config.graphics.mod do use(menu, i.mod.name) // its new files, worn at once
	case .Failed:
		i.taken = true
		note(&menu.mods, fmt.tprintf("%s couldn't be installed: %s", i.mod.name, i.error), true)
	case .None, .Downloading, .Unpacking:
	}
}

// mods/ read again, and each of the player's mods' version; the mod in use picked.
@(private = "file")
mods_relist :: proc(mods: ^Mods, active: string) {
	res.mods_list_destroy(mods.listings)
	mods.listings = res.mods_list(res.MODS_DIR)
	versions_forget(mods)
	for listing in mods.listings {
		if !listing.builtin do mods.versions[strings.clone(listing.name)] = strings.clone(online.installed_version(res.MODS_DIR, listing.name))
	}
	mods.listed = true
	mods.selected = 0
	for listing, i in mods.listings do if listing.name == active do mods.selected = i
	mods.confirm = false
}

@(private = "file")
versions_forget :: proc(mods: ^Mods) {
	for name, version in mods.versions {
		delete(name)
		delete(version)
	}
	clear(&mods.versions)
}

// The row of the mod in use: Classic's when none, or one no longer there, is set.
@(private = "file")
mod_in_use :: proc(menu: ^Menu) -> int {
	for listing, i in menu.mods.listings do if listing.name == menu.config.graphics.mod do return i
	return 0
}

@(private = "file")
pick :: proc(mods: ^Mods, i: int) {
	if i != mods.selected do mods.confirm = false
	mods.selected = i
	mods.about = -1
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
	note(mods, fmt.tprintf("%s made: mods/%s/, empty until you put files in it.", name, name), false)
	made := name
	mods_relist(mods, menu.config.graphics.mod)
	for listing, i in mods.listings do if listing.name == made do mods.selected = i
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
