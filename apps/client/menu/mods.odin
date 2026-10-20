package menu

import "core:fmt"
import "core:os"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../online"
import "../ui"

// The mods, on three tabs. Installed Mods: the player's mods in mods/, each a .srmod or a
// folder (Classic, under every part, never listed), each with the parts it has (the
// soldier, the weapons, the sounds, ...). A part clicked is worn from that mod, and from
// whichever wore it before no longer; clicked again, Classic's is worn again. Use All
// wears every part the mod has (graphics.parts, docs/srmod.md). One picked can be
// deleted, after a second press to be sure, or its folder opened. Any change is worn at
// once.
//
// Mod Marketplace: the mods' catalogue (online's catalog.odin), each mod the mods
// repository publishes, installed, or updated to its newest version, in a click, its
// download's progress shown; one picked says what it is and whose.
//
// Create Mod From S1: a mod made of what the player changed in their Soldat 1.7.1, its
// folder found, or typed.

Mods_Tab :: enum {
	Installed,
	Marketplace,
	Import,
}

@(private = "file", rodata)
TAB_NAMES := [len(Mods_Tab)]string{"Installed Mods", "Mod Marketplace", "Create Mod From S1"} // by Mods_Tab

Mods :: struct {
	tab:        Mods_Tab,
	listings:   []res.Srmod_Listing,
	versions:   map[string]string, // each of the catalogue's mods installed, by its version, as its about.json says
	listed:     bool,   // read from mods/ since the page was opened
	selected:   string, // the mod picked, by name; "" for none
	about:      int,    // the catalogue's mod picked, to say what it is; -1 for none
	confirm:    bool,   // Delete pressed once: pressed again, it deletes
	note:       string, // what was last done, or why it couldn't be
	note_bad:   bool,
	import_:    Soldat_Import, // Create Mod From S1's
}

// From your Soldat 1: the Soldat install, and what in it to make mods from.
Soldat_Import :: struct {
	folder:   string, // as picked, or found
	root:     string, // the install found from it; "" until one is
	problem:  string, // why none was
	looked:   bool,   // the install looked for where it is usually put, as the tab first opened
	sources:  []res.Soldat_Source,
	job:      Soldat_Job,  // looking for the install, looking through it, or importing, while it runs
	pick:     Folder_Pick, // the system's folder dialog, while it is up
}

MOD_ROW :: 50 // its name and what it is, and under them its parts
CHIP_H :: 16
CHIP_GAP :: 4
CATALOG_ROW :: 36
PROGRESS_W :: 110 // an install's progress bar
ROW_BUTTON_GAP :: 4

mods_destroy :: proc(mods: ^Mods) {
	res.srmod_listings_destroy(mods.listings)
	versions_forget(mods)
	delete(mods.versions)
	delete(mods.selected)
	delete(mods.note)
	im := &mods.import_
	soldat_job_forget(&im.job) // waited for, if it runs
	for s in ([]string{im.folder, im.root, im.problem}) do delete(s)
	res.soldat_sources_destroy(im.sources)
	mods^ = {}
}

page_mods :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	if !mods.listed {
		mods_relist(mods)
		mods.about = -1
		// the catalogue asked for as the page opens, unless it is in, or on its way
		if menu.catalog.state == .Idle || menu.catalog.state == .Failed do online.catalog_refresh(menu.catalog, menu.config.network.mods_index)
	}
	install_taken(menu)

	if picked := Mods_Tab(ui.tabs(k, TAB_NAMES[:], int(mods.tab))); picked != mods.tab {
		mods.tab = picked
		mods.confirm = false
		mods.about = -1
		set_text(&mods.note, "")
	}
	ui.gap(k, 8)
	switch mods.tab {
	case .Installed:   tab_installed(menu)
	case .Marketplace: page_catalog(menu)
	case .Import:      page_import(menu)
	}
	action_bar(menu)
}

// ---------------------------------------------------------------------------------
// Installed

@(private = "file")
tab_installed :: proc(menu: ^Menu) {
	mods := &menu.mods
	k := &menu.kit
	if len(mods.listings) == 0 {
		muted_line(k, "No mods yet: get one from the Mod Marketplace, or make one from Soldat 1.")
		classic_row(menu)
		return
	}
	muted_line(k, "Click a mod's part to wear it from that mod, and from no other; again, for Classic's.")
	classic_row(menu)
	for &listing in mods.listings do installed_row(menu, &listing)
	if listing, picked := listing_of(mods, mods.selected); picked do page_making(menu, listing.name)
}

// Classic, the game's own: not worn as a mod is, but its HUD may begin one in the editor.
@(private = "file")
classic_row :: proc(menu: ^Menu) {
	k := &menu.kit
	r := ui.row(k, ui.ROW_H + 8, false)
	if !r.shown do return
	edit, ex := row_button(k, r.x + r.w - 8, r.y + (r.h - ui.CTRL_H) / 2, "Edit HUD", false)
	if edit do hud_editor_open(menu, "")
	ui.text_fit(k, ui.LABEL, "Classic", r.x + 12, r.y + r.h / 2, 80, ui.MUTED)
	ui.text_fit(k, ui.TINY, "The game's own, under every mod", r.x + 12 + ui.width_of(k.ui, ui.LABEL, "Classic") + 10, r.y + r.h / 2, ex - r.x - 110, ui.FAINT)
}

// A mod's row: its name, and what it is; under them a chip for each part it has, lit if
// that part is worn from it, which a click wears from it or gives back to Classic; and
// Use All. Picked when clicked elsewhere on it.
@(private = "file")
installed_row :: proc(menu: ^Menu, listing: ^res.Srmod_Listing) {
	k := &menu.kit
	mods := &menu.mods
	r := ui.row(k, MOD_ROW, true)
	if ui.take_enter(k, r.focused) do pick(mods, listing.name)
	if !r.shown do return
	if strings.equal_fold(listing.name, mods.selected) {
		ui.rrect(k.ui, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
		ui.rrect(k.ui, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
	}
	worn_any := false
	for part in res.Part do worn_any ||= part in listing.parts && worn_from(menu, part) == listing.name

	// Use All, at the right of its top line
	all := listing.parts != {} && listing.problem == ""
	every := true
	for part in listing.parts do every &&= worn_from(menu, part) == listing.name
	used, ux := row_button(k, r.x + r.w - 8, r.y + 5, "Use All", !all || every)
	if used do use_all(menu, listing)
	if .Hud in listing.parts && listing.problem == "" {
		edit, ex := row_button(k, ux, r.y + 5, "Edit HUD", false)
		ux = ex
		if edit do hud_editor_open(menu, listing.name)
	}

	tx := r.x + 12
	ui.text_fit(k, ui.LABEL, listing.title, tx, r.y + 13, ux - tx - 8, ui.TEXT if worn_any else ui.MUTED)
	what, bad := listing_text(listing)
	ui.text_fit(k, ui.TINY, what, tx + min(ui.width_of(k.ui, ui.LABEL, listing.title), ux - tx - 8) + 10, r.y + 13, ux - tx - 18, ui.WARN if bad else ui.FAINT)

	// its parts, a chip each
	x := tx
	cy := r.y + MOD_ROW - 6 - CHIP_H / 2
	for part in res.Part {
		if part not_in listing.parts do continue
		name := PART_TITLES[part]
		w := ui.width_of(k.ui, ui.TINY, name) + 24
		if x + w > r.x + r.w - 8 do break
		lit := worn_from(menu, part) == listing.name
		hot := ui.over(k, x, cy - CHIP_H / 2, w, CHIP_H)
		ui.rrect(k.ui, x, cy - CHIP_H / 2, w, CHIP_H, CHIP_H / 2, ui.ACCENT if lit else (ui.HOVER if hot else ui.CONTROL))
		// a dot, filled where the part is worn from it: a switch, not a tag
		ui.rrect(k.ui, x + 5, cy - 3.5, 7, 7, 3.5, ui.TEXT if lit else ui.FAINT)
		if !lit do ui.rrect(k.ui, x + 6.5, cy - 2, 4, 4, 2, ui.HOVER if hot else ui.CONTROL)
		ui.text_mid(k, ui.TINY, name, x + 16, cy, ui.TEXT if lit || hot else ui.MUTED)
		if listing.problem == "" && ui.take(k, -1, x, cy - CHIP_H / 2, w, CHIP_H) {
			wear(menu, part, "" if lit else listing.name)
		}
		x += w + CHIP_GAP
	}
	if ui.take(k, r.id, r.x, r.y, r.w, r.h) do pick(mods, listing.name)
}

// The parts as the chips name them.
@(private = "file", rodata)
PART_TITLES := [res.Part]string {
	.Soldier  = "Soldier",
	.Weapons  = "Weapons",
	.Effects  = "Effects",
	.Objects  = "Objects",
	.Hud      = "HUD",
	.Icons    = "Icons",
	.Sounds   = "Sounds",
	.Textures = "Textures",
	.Scenery  = "Scenery",
	.Fonts    = "Fonts",
}

// What a mod is, beside its name: "v1.0.0  -  by Calp"; or why it can't be worn, or that
// it changes nothing.
@(private = "file")
listing_text :: proc(listing: ^res.Srmod_Listing) -> (text: string, bad: bool) {
	if listing.problem != "" do return fmt.tprintf("Can't be worn: %s", listing.problem), true
	if listing.parts == {} do return "Nothing the game uses: its files go in soldier/, sounds/... at its root", true
	text = fmt.tprintf("v%s", listing.version)
	if listing.author != "" do text = fmt.tprintf("%s  -  by %s", text, listing.author)
	return text, false
}

// A small button on a row, its right edge at `right`. Pressed, and where its left edge
// is, for the next one.
@(private = "file")
row_button :: proc(k: ^ui.Kit, right, y: f32, caption: string, disabled: bool, primary := false) -> (pressed: bool, left: f32) {
	bw := ui.button_w(k, caption)
	left = right - bw
	pressed = ui.button_at(k, left, y, bw, ui.CTRL_H, caption, primary, disabled)
	left -= ROW_BUTTON_GAP
	return
}

// How to make the player's mod `name`: what to put in its folder, and where; and its
// folder opened, to put them there.
@(private = "file", rodata)
MAKING_LINES := [?]string {
	"Put soldier/, weapons/, effects/, objects/, hud/, icons/, sounds/, textures/,",
	"scenery/ or fonts/ in its folder, laid out as Classic's (mods/classic/). What a",
	"part hasn't comes from Classic's. Wearing the part again shows what you changed.",
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

// ---------------------------------------------------------------------------------
// Mod Marketplace, and Create Mod From S1

// Mods made from the player's Soldat 1.7.1. Its install, found where it is usually put
// (res.soldat_installs), else the folder picked in the system's folder dialog, taken as
// it is. Once it is, the install is not shown again: each thing in it a mod can be made
// of is, an Import each (res.soldat_sources), named for it: what the player changed of
// its own files, My S1 Mod; each mod of its mods/, those changes under it, as Soldat wore
// a mod over its own folders; each custom interface, the changes to its HUD's art under
// it. Those 1.7.1 ships with, untouched, aren't offered.
//
// Looking for the install, looking through it and importing each take a while (a Steam
// library on every drive; every file of the install weighed; every image of a mod
// rescaled), so each runs on a thread (Soldat_Job), said while it does, the game drawn on.
@(private = "file")
page_import :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	im := &mods.import_
	if !im.looked {
		im.looked = true
		soldat_job_start(&im.job, .Find, rl.GetTime())
	}
	if soldat_job_take(&im.job) do soldat_job_taken(menu)
	if picked, taken := folder_pick_take(&im.pick); taken {
		if picked != "" {
			set_text(&im.folder, picked)
			import_look(menu)
		}
		delete(picked)
	}
	muted_line(k, "Make mods of what you changed or added in your Soldat 1.7.1.")

	busy := soldat_job_busy(&im.job)
	if busy && im.job.kind != .Import {
		said := "Looking for your Soldat..." if im.job.kind == .Find else "Looking through your Soldat..."
		line(k, fmt.tprintf("%s %s", said, elapsed(rl.GetTime() - im.job.started)), ui.MUTED)
		return
	}
	if im.root == "" {
		browse_row(menu, im.problem if im.problem != "" else "No Soldat 1.7.1 found where it is usually installed: browse to its folder.", im.problem != "")
		return
	}
	if busy { // importing: the rest of the tab shown, its Imports held
		title := OWN_TITLE if im.job.source.kind == .Own else im.job.source.name
		line(k, fmt.tprintf("Importing %s... %s", title, elapsed(rl.GetTime() - im.job.started)), ui.MUTED)
	}

	offered := false
	for kind in res.Soldat_Source_Kind {
		titled := false
		for source, i in im.sources {
			if source.kind != kind || source.changed == 0 do continue
			if !titled {
				sections := [res.Soldat_Source_Kind]string{.Own = "YOUR CHANGES", .Mod = "MODS", .Interface = "CUSTOM INTERFACES"}
				ui.section(k, sections[kind])
				titled = true
			}
			offered = true
			source_row(menu, source, i, im.sources[0].changed if im.sources[0].kind == .Own else 0)
		}
	}
	if !offered {
		line(k, "Nothing there to make a mod of: no art or sounds changed, no mods, no interfaces.", ui.MUTED)
		browse_row(menu, "Not your Soldat 1.7.1's folder? Browse to it.", false)
	}
}

// Browse..., the system's folder dialog to pick the Soldat install with, beside `said`.
@(private = "file")
browse_row :: proc(menu: ^Menu, said: string, warn: bool) {
	k := &menu.kit
	im := &menu.mods.import_
	r := ui.row(k, ui.ROW_H + 4, false)
	if !r.shown do return
	picking := im.pick.thread != nil
	bw := ui.button_w(k, "Browse...")
	if ui.button_at(k, r.x + r.w - 8 - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Picking..." if picking else "Browse...", true, picking) {
		folder_pick_start(&im.pick, "Pick your Soldat 1.7.1 folder", rl.GetWindowHandle())
	}
	ui.text_fit(k, ui.LABEL, said, r.x + 12, r.y + r.h / 2, r.w - bw - 32, ui.WARN if warn else ui.MUTED)
}

// The mod of the install's own changes: its name, and its title as the Mods page shows it.
OWN_NAME :: "My_S1_Mod"
OWN_TITLE :: "My S1 Mod"

// What the player changed of the install, a mod of mods/, or a custom interface: its
// name, what it holds, and Install, or Installed once a mod by its name is.
@(private = "file")
source_row :: proc(menu: ^Menu, source: res.Soldat_Source, i, own: int) {
	k := &menu.kit
	r := ui.row(k, MOD_ROW, false)
	if !r.shown do return
	name := OWN_NAME if source.kind == .Own else res.mod_name_from(source.name)
	taken := name == "" || name_taken(menu, name)
	job := &menu.mods.import_.job
	importing := soldat_job_busy(job) && job.kind == .Import && job.source.kind == source.kind && job.source.name == source.name
	caption := "Importing..." if importing else "Imported" if taken else "Import"
	pressed, bx := row_button(k, r.x + r.w - 8, r.y + (r.h - ui.CTRL_H) / 2, caption, taken || soldat_job_busy(job), primary = !taken)
	if pressed && !taken && !soldat_job_busy(job) {
		soldat_job_start(job, .Import, rl.GetTime(), menu.mods.import_.root, source)
		set_text(&menu.mods.note, "")
	}
	title, detail: string
	switch source.kind {
	case .Own:
		title = OWN_TITLE
		detail = fmt.tprintf("%d file%s you changed in Soldat's own folders", own, "" if own == 1 else "s")
	case .Mod:
		title = source.name
		detail = fmt.tprintf("%d file%s", source.changed, "" if source.changed == 1 else "s")
		if own > 0 do detail = fmt.tprintf("%s, and your %d changed under %s", detail, own, "it" if own == 1 else "them")
		if source.in_use do detail = fmt.tprintf("%s  -  the mod Soldat was last played with", detail)
	case .Interface:
		title = source.name
		detail = "Its HUD's layout and pictures, and your changes to the HUD's art under them" if own > 0 else "Its HUD's layout and pictures"
	}
	ui.text_fit(k, ui.LABEL, title, r.x + 12, r.y + 13, bx - r.x - 24, ui.TEXT)
	ui.text_fit(k, ui.TINY, detail, r.x + 12, r.y + 31, bx - r.x - 24, ui.FAINT)
}

// The folder given, if it opens, looked through (on the job's thread) for what mods can be
// made of.
@(private = "file")
import_look :: proc(menu: ^Menu) {
	im := &menu.mods.import_
	if soldat_job_busy(&im.job) do return
	if !os.is_dir(im.folder) {
		set_text(&im.problem, "That folder can't be opened: browse to your Soldat 1.7.1's.")
		set_text(&im.root, "")
		return
	}
	set_text(&im.problem, "")
	soldat_job_start(&im.job, .Scan, rl.GetTime(), im.folder)
}

// What the job that is over came to: the install found, and looked through next; what it
// holds that mods can be made of, the install taken as found; or a mod made, and said how
// it went.
@(private = "file")
soldat_job_taken :: proc(menu: ^Menu) {
	mods := &menu.mods
	im := &mods.import_
	job := &im.job
	switch job.kind {
	case .Find:
		if len(job.installs) > 0 {
			set_text(&im.folder, job.installs[0])
			import_look(menu)
		}
	case .Scan:
		set_text(&im.root, job.root)
		res.soldat_sources_destroy(im.sources)
		im.sources, job.sources = job.sources, nil // the tab's now
	case .Import:
		if job.problem != "" {
			note(mods, fmt.tprintf("%s couldn't be made: %s", job.name, job.problem), true)
			return
		}
		note(mods, fmt.tprintf("%s imported: wear its parts on Installed Mods.", OWN_TITLE if job.source.kind == .Own else job.name), false)
		mods_relist(mods)
	}
}

// "4s", "1m 05s": how long a job has been running.
@(private = "file")
elapsed :: proc(seconds: f64) -> string {
	s := int(seconds)
	if s < 60 do return fmt.tprintf("%ds", s)
	return fmt.tprintf("%dm %02ds", s / 60, s % 60)
}

// The catalogue's section: each mod it has, and what may be done with it; or why there
// are none to show.
@(private = "file")
page_catalog :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	mods := &menu.mods
	c := menu.catalog
	muted_line(k, "Mods made by the community.")
	switch c.state {
	case .Idle, .Fetching:
		muted_line(k, "Asking for the mods' catalogue...")
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
		if len(c.mods) == 0 do muted_line(k, "No mods in the catalogue yet.")
		busy := c.install != nil && online.install_busy(c.install)
		for &m, i in c.mods {
			r := ui.row(k, CATALOG_ROW, true)
			// the row's action first, so a click on it is the button's, not the row's
			if r.shown do catalog_action(menu, r, &m, busy)
			if ui.take_enter(k, r.focused) || (r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h)) {
				mods.about = i
				mods.confirm = false
			}
			if !r.shown do continue
			if i == mods.about {
				ui.rrect(u, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
				ui.rrect(u, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
			}
			room := r.w - PROGRESS_W - 40
			ui.text_fit(k, ui.LABEL, m.title, r.x + 12, r.y + r.h / 2 - 7, room, ui.TEXT)
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
			ui.text_mid(k, ui.TINY, "Installing...", x, cy - 5, ui.MUTED)
		}
		return
	}
	version, installed := menu.mods.versions[m.name]
	status, caption := "", ""
	switch {
	case installed && version == m.version: status = "Installed"
	case installed && version != "":        caption = "Update"
	case installed || name_taken(menu, m.name): status = "Name taken" // a mod of the player's own, not the catalogue's
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
name_taken :: proc(menu: ^Menu, name: string) -> bool {
	for listing in menu.mods.listings {
		if strings.equal_fold(listing.name, name) do return true
	}
	return false
}

// An install that has ended, acted on once: a new mod turned on, at the top, and one on,
// updated, loaded again; or why it failed.
@(private = "file")
install_taken :: proc(menu: ^Menu) {
	i := menu.catalog.install
	if i == nil || i.taken do return
	state, _ := online.install_progress(i)
	switch state {
	case .Done:
		i.taken = true
		mods_relist(&menu.mods)
		note(&menu.mods, fmt.tprintf("%s %s installed.", i.mod.title, i.mod.version), false)
	case .Failed:
		i.taken = true
		note(&menu.mods, fmt.tprintf("%s couldn't be installed: %s", i.mod.title, i.error), true)
	case .None, .Downloading, .Unpacking:
	}
}

// ---------------------------------------------------------------------------------
// The footer

// What was last done, or what the mod or the catalogue's mod picked is; and Delete, for
// a mod picked on the Installed tab.
@(private = "file")
action_bar :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	x, w := k.x, k.w
	listing, picked := listing_of(mods, mods.selected)
	deletable := mods.tab == .Installed && picked
	if !deletable do mods.confirm = false
	right := x + w
	if mods.tab == .Installed {
		deleted, dx := big_button(menu, right, "SURE?" if mods.confirm else "DELETE", false, !deletable)
		right = dx - 10
		if deleted && deletable {
			if mods.confirm do mod_delete(menu, listing.name)
			else do mods.confirm = true
		}
		if picked {
			opened, ox := big_button(menu, right, "SHOW", false, false)
			right = ox - 10
			if opened do folder_open(utils.temp_path(res.MODS_DIR, listing.name))
		}
	}
	tw := right - x - 6
	c := menu.catalog
	switch {
	case mods.tab == .Marketplace && mods.about >= 0 && mods.about < len(c.mods) && mods.note == "":
		m := &c.mods[mods.about]
		ui.text_fit(k, ui.BODY, m.description, x, ACTION_CY - 7, tw, ui.TEXT)
		ui.text_fit(k, ui.BODY, fmt.tprintf("By %s. %s", m.author, m.licence), x, ACTION_CY + 9, tw, ui.MUTED)
	case mods.confirm:
		footer_text(menu, x, tw, fmt.tprintf("Delete %s and all its files? Press again to.", listing.title), ui.WARN)
	case mods.note != "":
		footer_text(menu, x, tw, mods.note, ui.WARN if mods.note_bad else ui.GOOD)
	case mods.tab == .Installed:
		footer_text(menu, x, tw, "Each part is worn from one mod; what that mod hasn't of it is Classic's.", ui.MUTED)
	case mods.tab == .Import:
		footer_text(menu, x, tw, "Only what you changed goes in: Soldat's own art as it came is left out.", ui.MUTED)
	case:
		footer_text(menu, x, tw, "A mod changes only how the game looks and sounds, never how it plays.", ui.MUTED)
	}
}

// ---------------------------------------------------------------------------------
// The parts worn, and changing them

// The mod `part` is worn from, by name; "" for Classic's: the config's, if that mod is
// in mods/ and has the part.
@(private)
worn_from :: proc(menu: ^Menu, part: res.Part) -> string {
	chosen := res.part_choice_of(&menu.config.graphics.parts, part)
	if chosen == nil do return "" // the scenery, Classic's alone
	name := chosen^
	listing, present := listing_of(&menu.mods, name)
	if !present || part not_in listing.parts || listing.problem != "" do return ""
	return listing.name
}

// `part` worn from the mod `name` ("" for Classic's), the others as they are: at once.
@(private = "file")
wear :: proc(menu: ^Menu, part: res.Part, name: string) {
	parts: [res.Part]string
	for p in res.Part do parts[p] = worn_from(menu, p)
	parts[part] = name
	use_parts(menu, parts)
}

// Every part `listing` has worn from it, the others as they are.
@(private = "file")
use_all :: proc(menu: ^Menu, listing: ^res.Srmod_Listing) {
	parts: [res.Part]string
	for p in res.Part do parts[p] = listing.name if p in listing.parts else worn_from(menu, p)
	use_parts(menu, parts)
}

// ---------------------------------------------------------------------------------

// mods/ read again; and the version of each of the catalogue's mods installed.
@(private)
mods_relist :: proc(mods: ^Mods) {
	res.srmod_listings_destroy(mods.listings)
	mods.listings = res.srmod_listings(res.MODS_DIR)
	versions_forget(mods)
	installed := res.mods_list(res.MODS_DIR, context.temp_allocator)
	for listing in installed {
		mods.versions[strings.clone(listing.name)] = strings.clone(online.installed_version(res.MODS_DIR, listing.name))
	}
	mods.listed = true
	if _, still := listing_of(mods, mods.selected); !still do set_text(&mods.selected, "")
	mods.confirm = false
}

@(private = "file")
listing_of :: proc(mods: ^Mods, name: string) -> (listing: ^res.Srmod_Listing, found: bool) {
	if name == "" do return
	for &l in mods.listings do if strings.equal_fold(l.name, name) do return &l, true
	return
}

@(private = "file")
versions_forget :: proc(mods: ^Mods) {
	for name, version in mods.versions {
		delete(name)
		delete(version)
	}
	clear(&mods.versions)
}

@(private = "file")
pick :: proc(mods: ^Mods, name: string) {
	if name != mods.selected do mods.confirm = false
	set_text(&mods.selected, name)
	mods.about = -1
	set_text(&mods.note, "")
}

@(private = "file")
mod_delete :: proc(menu: ^Menu, name: string) {
	mods := &menu.mods
	gone := strings.clone(name, context.temp_allocator)
	// the parts worn from it, Classic's again
	parts: [res.Part]string
	worn := false
	for p in res.Part {
		parts[p] = worn_from(menu, p)
		if strings.equal_fold(parts[p], gone) {
			parts[p] = ""
			worn = true
		}
	}
	if worn {
		// let go of first: the client wears it, and a .srmod worn is a file open
		use_parts(menu, parts)
		note(mods, fmt.tprintf("%s is no longer worn: press Delete again to delete it.", gone), false)
		mods.confirm = false
		return
	}
	if !res.mod_delete(res.MODS_DIR, gone) {
		note(mods, fmt.tprintf("%s couldn't be deleted (a file of it may be open).", gone), true)
		mods.confirm = false
		return
	}
	note(mods, fmt.tprintf("%s deleted.", gone), false)
	mods_relist(mods)
}

// A folder shown in the system's file browser.
@(private = "package")
folder_open :: proc(path: string) {
	full, err := os.get_absolute_path(path, context.temp_allocator)
	if err != nil do return
	when ODIN_OS == .Windows {
		full, _ = strings.replace_all(full, "/", "\\", context.temp_allocator) // explorer reads its own slashes
	}
	rl.OpenURL(strings.clone_to_cstring(full, context.temp_allocator))
}

// A path as the system writes it: with backslashes on Windows.
@(private = "file")
shown_path :: proc(path: string) -> string {
	when ODIN_OS == .Windows {
		shown, _ := strings.replace_all(path, "/", "\\", context.temp_allocator)
		return shown
	}
	return path
}

@(private = "file")
muted_line :: proc(k: ^ui.Kit, text: string) {
	line(k, text, ui.MUTED)
}

@(private = "file")
line :: proc(k: ^ui.Kit, text: string, color: rl.Color) {
	r := ui.row(k, ui.ROW_H, false)
	if r.shown do ui.text_fit(k, ui.BODY, text, r.x + 12, r.y + r.h / 2, r.w - 24, color)
}

@(private = "file")
note :: proc(mods: ^Mods, text: string, bad: bool) {
	set_text(&mods.note, text)
	mods.note_bad = bad
}

// What the client did to mods/ as it started, said on the Mods page until something else is.
mods_note :: proc(menu: ^Menu, text: string) {
	note(&menu.mods, text, false)
}

// Each part worn from the mod `parts` names for it, asked of the client, which takes the
// request at the next frame's start: so its names are its own, made with the context's
// allocator, outliving this frame's temp allocator, and the client frees them.
@(private)
use_parts :: proc(menu: ^Menu, parts: [res.Part]string) {
	kept: [res.Part]string
	for name, part in parts do kept[part] = strings.clone(name)
	menu.request = Use_Mod{kept}
}
