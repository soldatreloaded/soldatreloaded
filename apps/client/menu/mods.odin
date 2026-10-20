package menu

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../online"
import "../ui"

// The mods, on three tabs. Installed Mods: Classic and the player's mods in mods/, each a
// folder, listed on the left; the one picked on the right, what it is and what of it is
// worn. Each of its parts (the soldier, the weapons, the sounds, the text, ...) is worn
// from it with a switch, and from whichever wore it before no longer; switched off, it
// is Classic's again (graphics.parts, docs/srmod.md). Its art's scale, the pixels to a
// unit its images were drawn at, part by part, and what its mod.json says of it are the
// player's to change, saved into its mod.json; its HUD opens in the HUD editor, its words
// in the text editor, its folder in the system's. Delete, after a second press to be
// sure. Any change is worn at once.
//
// Mod Marketplace: the mods' catalogue (online's catalog.odin), each mod the mods
// repository publishes, installed, or updated to its newest version, in a click, its
// download's progress shown; one picked says what it is and whose.
//
// Add Mods: a mod from a file (a .zip or .srmod handed over, or a Soldat 1 mod zipped),
// picked in the system's dialog or dropped on the window; a new mod, an empty folder to
// fill; and mods made of what the player changed or added in their Soldat 1.7.1.

Mods_Tab :: enum {
	Installed,
	Marketplace,
	Add,
}

@(private = "file", rodata)
TAB_NAMES := [len(Mods_Tab)]string{"Installed Mods", "Mod Marketplace", "Add Mods"} // by Mods_Tab

Mods :: struct {
	tab:      Mods_Tab,
	listings: []res.Srmod_Listing,
	versions: map[string]string, // each mod installed, by its version, as its mod.json says: the catalogue's to weigh
	listed:   bool,   // read from mods/ since the page was opened
	selected: string, // the mod picked, by name; MOD_CLASSIC for Classic
	about:    int,    // the catalogue's mod picked, to say what it is; -1 for none
	confirm:  bool,   // Delete pressed once: pressed again, it deletes
	note:     string, // what was last done, or why it couldn't be
	note_bad: bool,
	edit:     Mod_Edit,      // the picked mod's mod.json, as it is being changed
	new_name: string,        // Add Mods' new mod's, as typed
	file:     Folder_Pick,   // Add Mods' file dialog, while it is up
	adding:   Soldat_Job,    // a mod's file being added, unpacked or made one of this game's
	import_:  Soldat_Import, // Add Mods' Soldat 1's
}

// What the picked mod's mod.json says, as the player changes it on the Installed tab;
// saved when they say so.
Mod_Edit :: struct {
	name:    string, // the mod it is of; "" for none read yet
	fields:  [Mod_Field]string,
	scale:   f32,
	scales:  [res.Part]f32,
	saved:   res.Srmod_Details, // as read, to say what changed: its strings this struct's own
	deeper:  int,               // its folders' and files' own scales, kept as they are
	problem: string,            // why the last save didn't
}

Mod_Field :: enum {
	Title,
	Version,
	Author,
	Description,
	Licence,
	Source,
}

@(private = "file", rodata)
FIELD_NAMES := [Mod_Field]string{.Title = "Title", .Version = "Version", .Author = "Author", .Description = "Description", .Licence = "Licence", .Source = "Where from"}
@(private = "file", rodata)
FIELD_HINTS := [Mod_Field]string{.Title = "My Mod", .Version = "1.0.0", .Author = "Your name", .Description = "What it changes", .Licence = "Free to share, crediting me", .Source = "A link, or how to reach you"}

// From your Soldat 1: the Soldat install, and what in it to make mods from.
Soldat_Import :: struct {
	folder:  string, // as picked, or found
	root:    string, // the install found from it; "" until one is
	problem: string, // why none was
	looked:  bool,   // the install looked for where it is usually put, as the tab first opened
	sources: []res.Soldat_Source,
	job:     Soldat_Job,  // looking for the install, looking through it, importing, or unpacking a file, while it runs
	pick:    Folder_Pick, // the system's folder dialog, while it is up
}

MOD_ROW :: 42 // its name, and what it is under it
CATALOG_ROW :: 36
PROGRESS_W :: 110 // an install's progress bar
ROW_BUTTON_GAP :: 4
TWO_PANES_W :: 560 // the page this wide at least (in the menu's units): the list beside the mod picked, else above it
LIST_W :: 210
PANE_GAP :: 18

// The parts' images' scales offered, pixels to a unit, and what they are called.
@(private = "file", rodata)
SCALES := [?]f32{1, 1.5, 2, 3, 4, 4.5, 6, 9}
@(private = "file", rodata)
SCALE_NAMES := [?]string{"1 (Soldat 1's)", "1.5", "2", "3", "4", "4.5 (Classic's)", "6", "9"}

// The parts whose images are as big as their pixels over a scale: the rest are sounds,
// words and fonts, or sized by the map.
@(private = "file")
SCALED_PARTS :: res.Parts{.Soldier, .Weapons, .Effects, .Objects, .Hud, .Icons, .Textures}

mods_destroy :: proc(mods: ^Mods) {
	res.srmod_listings_destroy(mods.listings)
	versions_forget(mods)
	delete(mods.versions)
	delete(mods.selected)
	delete(mods.note)
	delete(mods.new_name)
	edit_forget(&mods.edit)
	if path, taken := folder_pick_take(&mods.file); taken do delete(path)
	im := &mods.import_
	soldat_job_forget(&im.job) // waited for, if it runs
	soldat_job_forget(&mods.adding)
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
	files_taken(menu)
	im := &mods.import_
	if soldat_job_take(&im.job) do soldat_job_taken(menu, &im.job)
	if soldat_job_take(&mods.adding) do soldat_job_taken(menu, &mods.adding)

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
	case .Add:         tab_add(menu)
	}
	action_bar(menu)
}

// ---------------------------------------------------------------------------------
// Installed

// The list of mods, and beside it (or under it, the page narrow) the one picked.
@(private = "file")
tab_installed :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	if mods.selected == "" do set_text(&mods.selected, res.MOD_CLASSIC)
	x, w := k.x, k.w
	two := w >= TWO_PANES_W
	top := k.y
	if two do k.w = LIST_W
	mod_list(menu)
	list_end := k.y
	if two {
		k.x, k.w, k.y = x + LIST_W + PANE_GAP, w - LIST_W - PANE_GAP, top
		// the panes apart, a rule between them, as far as the list goes: what of it shows
		from, to := max(top, k.top), min(max(list_end, top + 200), k.bottom)
		if to > from do ui.rect(k.ui, k.x - PANE_GAP / 2, from, k.x - PANE_GAP / 2 + 1, to, ui.LINE)
	} else {
		ui.gap(k, 10)
	}
	if strings.equal_fold(mods.selected, res.MOD_CLASSIC) {
		classic_details(menu)
	} else if listing, picked := listing_of(mods, mods.selected); picked {
		mod_details(menu, listing)
	}
	k.y = max(k.y, list_end)
	k.x, k.w = x, w
}

// Classic, then each mod: its title, and what it is or how much of it is worn.
@(private = "file")
mod_list :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	list_row(menu, res.MOD_CLASSIC, "Classic", "The game's own, under every mod", false, false)
	for &listing in mods.listings {
		worn, has := 0, 0
		for part in listing.parts {
			has += 1
			if worn_from(menu, part) == listing.name do worn += 1
		}
		what, bad := listing_text(&listing)
		if !bad && worn > 0 do what = fmt.tprintf("%s  -  %d of %d part%s worn", what, worn, has, "" if has == 1 else "s")
		list_row(menu, listing.name, listing.title, what, bad, worn > 0)
	}
	if len(mods.listings) == 0 {
		r := ui.row(k, 34, false)
		if r.shown do ui.text_wrap(k, ui.TINY, "No mods yet: get one from the Mod Marketplace, or add one on Add Mods.", r.x + 12, r.y + 6, r.w - 24, ui.FAINT)
	}
}

// A mod's row in the list, picked when clicked; lit while it is.
@(private = "file")
list_row :: proc(menu: ^Menu, name, title, what: string, bad, worn: bool) {
	k := &menu.kit
	mods := &menu.mods
	r := ui.row(k, MOD_ROW, true)
	if ui.take_enter(k, r.focused) do pick(mods, name)
	if !r.shown do return
	if ui.take(k, r.id, r.x, r.y, r.w, r.h) do pick(mods, name)
	if strings.equal_fold(name, mods.selected) {
		ui.rrect(k.ui, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
		ui.rrect(k.ui, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
	}
	if worn do ui.circle(k.ui, r.x + r.w - 14, r.y + 13, 3.5, ui.ACCENT) // something of it is worn
	ui.text_fit(k, ui.LABEL, title, r.x + 12, r.y + 13, r.w - 40, ui.TEXT)
	ui.text_fit(k, ui.TINY, what, r.x + 12, r.y + 30, r.w - 24, ui.WARN if bad else ui.FAINT)
}

// What a mod is, beside its name: "v1.0.0  -  by Calp"; or why it can't be worn, or that
// it changes nothing.
@(private = "file")
listing_text :: proc(listing: ^res.Srmod_Listing) -> (text: string, bad: bool) {
	if listing.problem != "" do return fmt.tprintf("Can't be worn: %s", listing.problem), true
	if listing.parts == {} do return "Empty: nothing in its folder yet", false
	text = fmt.tprintf("v%s", listing.version)
	if listing.author != "" do text = fmt.tprintf("%s  -  by %s", text, listing.author)
	return text, false
}

// Classic: what it is, its parts, worn where no mod's is; its HUD and its words to begin a
// mod of one's own from.
@(private = "file")
classic_details :: proc(menu: ^Menu) {
	k := &menu.kit
	details_title(k, "Classic", "mods/classic/")
	wrapped(k, "The game's own look, sound and words. Every part is Classic's where no mod's is worn, and every file a mod hasn't of a part is Classic's too.", ui.MUTED)
	ui.section(k, "PARTS")
	for part in res.MOD_PARTS {
		r := ui.row(k, ui.ROW_H, false)
		if !r.shown do continue
		ui.text_fit(k, ui.LABEL, PART_TITLES[part], r.x + 10, r.y + r.h / 2, r.w * 0.5, ui.TEXT)
		from := worn_from(menu, part)
		state := "Worn" if from == "" else fmt.tprintf("Under %s", from)
		ui.text_mid(k, ui.BODY, state, r.x + r.w - 10 - ui.width_of(k.ui, ui.BODY, state), r.y + r.h / 2, ui.TEXT if from == "" else ui.FAINT)
	}
	ui.section(k, "MAKE YOUR OWN")
	wrapped(k, "Classic can't be changed, but its HUD can begin one of your own in the HUD editor, saved as a mod of a HUD alone.", ui.FAINT)
	r := ui.row(k, ui.ROW_H + 6, false)
	if !r.shown do return
	x := r.x + 10
	if button(k, &x, r, "Edit HUD", true) do hud_editor_open(menu, "")
	if button(k, &x, r, "Open its folder", false) do folder_open(utils.temp_path(res.MODS_DIR, res.MOD_CLASSIC))
}

// A mod's own: what it is; its parts, each worn from it or not; its art's scale; what its
// mod.json says of it, changed and saved; and what may be done with it.
@(private = "file")
mod_details :: proc(menu: ^Menu, listing: ^res.Srmod_Listing) {
	k := &menu.kit
	mods := &menu.mods
	e := &mods.edit
	if !strings.equal_fold(e.name, listing.name) do edit_load(mods, listing.name)

	details_title(k, listing.title, fmt.tprintf("mods/%s/", listing.name))
	if listing.problem != "" {
		wrapped(k, fmt.tprintf("It can't be worn: %s. Mend it in its folder, or delete it.", listing.problem), ui.WARN)
	} else if listing.description != "" {
		wrapped(k, listing.description, ui.MUTED)
	}

	// its parts, a switch each
	ui.section(k, "PARTS")
	if listing.parts == {} {
		wrapped(k, "It has no parts yet. Put soldier/, weapons/, effects/, objects/, hud/, icons/, sounds/, textures/, fonts/ or text/ in its folder, laid out as Classic's: what a part hasn't is Classic's.", ui.FAINT)
	}
	every, none := true, true
	for part in res.Part {
		if part not_in listing.parts do continue
		on := worn_from(menu, part) == listing.name
		every &&= on
		none &&= !on
		r := ui.row(k, ui.ROW_H, true)
		flipped := ui.take_enter(k, r.focused) || ui.take_side(k, r.focused) != 0
		if r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h) do flipped = true
		if flipped && listing.problem == "" do wear(menu, part, "" if on else listing.name)
		if !r.shown do continue
		ui.text_fit(k, ui.LABEL, PART_TITLES[part], r.x + 10, r.y + r.h / 2, r.w * 0.4, ui.TEXT)
		sx := r.x + r.w - 8 - 30
		state := "Worn from it" if on else "Classic's" if worn_from(menu, part) == "" else fmt.tprintf("%s's", worn_from(menu, part))
		ui.text_fit(k, ui.BODY, state, sx - 10 - min(ui.width_of(k.ui, ui.BODY, state), r.w * 0.45), r.y + r.h / 2, r.w * 0.45, ui.TEXT if on else ui.MUTED)
		ui.switch_draw(k, sx, r.y + r.h / 2, on, r.hot || r.focused)
	}
	if listing.parts != {} && listing.problem == "" {
		r := ui.row(k, ui.ROW_H + 6, false)
		x := r.x + 10
		if r.shown {
			if button(k, &x, r, "Wear all of it", !every) do use_all(menu, listing)
			if button(k, &x, r, "Wear none of it", false, disabled = none) do wear_none(menu, listing.name)
		}
	}

	// its art's scale, its whole and part by part
	if listing.parts & SCALED_PARTS != {} {
		ui.section(k, "ART SCALE")
		wrapped(k, "How many pixels of its images make a unit in the world, as they were drawn: Classic's are 4.5, most of Soldat 1's 1. A bigger number draws the same image smaller.", ui.FAINT)
		scale_row(k, "The whole mod", &e.scale, e.scale)
		for part in res.Part {
			if part not_in listing.parts || part not_in SCALED_PARTS do continue
			if e.scales[part] <= 0 do e.scales[part] = e.scale
			scale_row(k, PART_TITLES[part], &e.scales[part], e.scale)
		}
		if e.deeper > 0 do wrapped(k, fmt.tprintf("Its mod.json says %d folder%s or file%s of its own scale besides, kept as they are.", e.deeper, "" if e.deeper == 1 else "s", "" if e.deeper == 1 else "s"), ui.FAINT)
	}

	// what its mod.json says of it
	ui.section(k, "ABOUT IT")
	for field in Mod_Field {
		if typed, changed := ui.field_row(k, FIELD_NAMES[field], &e.fields[field], e.fields[field], 200, FIELD_HINTS[field]); changed {
			set_text(&e.fields[field], typed)
		}
	}
	changed := edit_changed(e)
	r := ui.row(k, ui.ROW_H + 6, false)
	if r.shown {
		x := r.x + 10
		if button(k, &x, r, "Save", true, disabled = !changed) do edit_save(menu, listing)
		if button(k, &x, r, "Undo changes", false, disabled = !changed) do edit_load(mods, listing.name)
		if e.problem != "" {
			ui.text_fit(k, ui.TINY, e.problem, x + 4, r.y + r.h / 2, r.x + r.w - x - 8, ui.WARN)
		} else if changed {
			ui.text_fit(k, ui.TINY, "Not saved yet.", x + 4, r.y + r.h / 2, r.x + r.w - x - 8, ui.MUTED)
		}
	}

	// what may be done with it
	ui.section(k, "TOOLS")
	t := ui.row(k, ui.ROW_H + 6, false)
	if !t.shown do return
	x := t.x + 10
	ok := listing.problem == ""
	if .Hud in listing.parts && ok && button(k, &x, t, "Edit HUD", false) do hud_editor_open(menu, listing.name)
	if button(k, &x, t, "Open its folder", false) do folder_open(utils.temp_path(res.MODS_DIR, listing.name))
}

// The picked mod's title, and where it is.
@(private = "file")
details_title :: proc(k: ^ui.Kit, title, place: string) {
	r := ui.row(k, 34, false)
	if !r.shown do return
	ui.text_fit(k, ui.BOLD, title, r.x + 10, r.y + 14, r.w - 20, ui.TEXT)
	ui.text_fit(k, ui.TINY, place, r.x + 10, r.y + 29, r.w - 20, ui.FAINT)
}

// A scale to pick, of SCALES; a mod's own of none of them shown as it is. `whole` its
// mod's, which a part's at it is said to be.
@(private = "file")
scale_row :: proc(k: ^ui.Kit, label: string, value: ^f32, whole: f32) {
	names := make([dynamic]string, context.temp_allocator)
	current := -1
	for s, i in SCALES {
		append(&names, SCALE_NAMES[i])
		if s == value^ do current = i
	}
	if current < 0 {
		append(&names, fmt.tprintf("%v (its own)", value^))
		current = len(names) - 1
	}
	if picked := ui.select_box(k, label, names[:], nil, current); picked >= 0 && picked < len(SCALES) do value^ = SCALES[picked]
}

// A small button, from `x` along the row `r`, `x` moved past it. Pressed.
@(private = "file")
button :: proc(k: ^ui.Kit, x: ^f32, r: ui.Row, caption: string, primary: bool, disabled := false) -> bool {
	bw := ui.button_w(k, caption)
	pressed := ui.button_at(k, x^, r.y + (r.h - ui.CTRL_H) / 2, bw, ui.CTRL_H, caption, primary, disabled)
	x^ += bw + 8
	return pressed
}

// `text` wrapped to the column, a row of the lines it takes.
@(private = "file")
wrapped :: proc(k: ^ui.Kit, text: string, color: rl.Color) {
	lines := wrapped_lines(k, text, k.w - 24)
	r := ui.row(k, f32(lines) * (ui.height_of(k.ui, ui.TINY) + 2) + 8, false)
	if r.shown do ui.text_wrap(k, ui.TINY, text, r.x + 10, r.y + 4, r.w - 24, color)
}

// How many lines `text` wraps to in `width`, as ui.text_wrap wraps it.
@(private = "file")
wrapped_lines :: proc(k: ^ui.Kit, text: string, width: f32) -> int {
	lines := 1
	line := ""
	rest := text
	for word in strings.fields_iterator(&rest) {
		trial := strings.concatenate({line, " " if line != "" else "", word}, context.temp_allocator)
		if line != "" && ui.width_of(k.ui, ui.TINY, trial) > width {
			lines += 1
			line = word
		} else {
			line = trial
		}
	}
	return lines
}

// The parts as they are named.
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
	.Text     = "Text",
}

// ---------------------------------------------------------------------------------
// A mod's mod.json, changed

// The mod `name`'s mod.json read into the editing, what it says as it was.
@(private = "file")
edit_load :: proc(mods: ^Mods, name: string) {
	e := &mods.edit
	edit_forget(e)
	e.name = strings.clone(name)
	details, problem, ok := res.srmod_details(res.MODS_DIR, name)
	if !ok {
		e.problem = strings.clone(problem)
		return
	}
	e.saved = details
	for &s in ([]^string{&e.saved.title, &e.saved.version, &e.saved.author, &e.saved.description, &e.saved.licence, &e.saved.source}) do s^ = strings.clone(s^)
	e.fields = {
		.Title       = strings.clone(details.title),
		.Version     = strings.clone(details.version),
		.Author      = strings.clone(details.author),
		.Description = strings.clone(details.description),
		.Licence     = strings.clone(details.licence),
		.Source      = strings.clone(details.source),
	}
	e.scale, e.scales, e.deeper = details.scale, details.scales, details.deeper
}

@(private = "file")
edit_forget :: proc(e: ^Mod_Edit) {
	delete(e.name)
	for f in e.fields do delete(f)
	for s in ([]string{e.saved.title, e.saved.version, e.saved.author, e.saved.description, e.saved.licence, e.saved.source}) do delete(s)
	delete(e.problem)
	e^ = {}
}

// Whether anything was changed since it was read.
@(private = "file")
edit_changed :: proc(e: ^Mod_Edit) -> bool {
	s := &e.saved
	was := [Mod_Field]string{.Title = s.title, .Version = s.version, .Author = s.author, .Description = s.description, .Licence = s.licence, .Source = s.source}
	if e.fields != was || e.scale != s.scale do return true
	for part in res.Part {
		mine := e.scales[part] if e.scales[part] > 0 else e.scale
		theirs := s.scales[part] if s.scales[part] > 0 else s.scale
		if mine != theirs do return true
	}
	return false
}

// The changes written into the mod's mod.json; the mod worn again if any of it is, so its
// art is drawn at its new scale.
@(private = "file")
edit_save :: proc(menu: ^Menu, listing: ^res.Srmod_Listing) {
	mods := &menu.mods
	e := &mods.edit
	details := res.Srmod_Details {
		title       = e.fields[.Title],
		version     = e.fields[.Version],
		author      = e.fields[.Author],
		description = e.fields[.Description],
		licence     = e.fields[.Licence],
		source      = e.fields[.Source],
		scale       = e.scale,
		scales      = e.scales,
	}
	// a part at the whole mod's, said by the mod, not the part
	for part in res.Part do if details.scales[part] == details.scale do details.scales[part] = 0
	name := strings.clone(listing.name, context.temp_allocator)
	if problem := res.srmod_details_write(res.MODS_DIR, name, details); problem != "" {
		set_text(&e.problem, problem)
		return
	}
	note(mods, fmt.tprintf("%s saved.", strings.trim_space(e.fields[.Title])), false)
	worn := false
	for part in res.Part do worn ||= worn_from(menu, part) == name
	mods_relist(mods) // its listing anew: `listing` is gone
	edit_load(mods, name)
	if worn {
		parts: [res.Part]string
		for part in res.Part do parts[part] = worn_from(menu, part)
		use_parts(menu, parts)
	}
}

// ---------------------------------------------------------------------------------
// Add Mods

@(private = "file")
tab_add :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	job := &mods.adding

	ui.section(k, "FROM A FILE")
	wrapped(k, "A mod handed to you, as a .zip or a .srmod; or a Soldat 1 mod, zipped, which is made one of this game's. You can drop it on the game's window, too.", ui.MUTED)
	r := ui.row(k, ui.ROW_H + 6, false)
	if r.shown {
		x := r.x + 10
		picking := folder_pick_busy(&mods.file)
		unpacking := soldat_job_busy(job) && job.kind == .Unpack
		if button(k, &x, r, "Picking..." if picking else "Pick a file...", true, disabled = picking || soldat_job_busy(job)) {
			folder_pick_start(&mods.file, "Pick a mod to add", rl.GetWindowHandle(), file = true)
		}
		if unpacking do ui.text_fit(k, ui.BODY, fmt.tprintf("Adding %s... %s", filepath.base(job.root), elapsed(rl.GetTime() - job.started)), x + 4, r.y + r.h / 2, r.x + r.w - x - 12, ui.MUTED)
	}

	ui.section(k, "A NEW MOD")
	wrapped(k, "An empty mod, a folder in mods/ to put your art, sounds or words in. Its name is letters, digits, - and _.", ui.MUTED)
	if typed, changed := ui.field_row(k, "Name", &mods.new_name, mods.new_name, res.SRMOD_NAME_MAX, "My_Mod"); changed do set_text(&mods.new_name, typed)
	n := ui.row(k, ui.ROW_H + 6, false)
	if n.shown {
		x := n.x + 10
		if button(k, &x, n, "Make it", true, disabled = strings.trim_space(mods.new_name) == "") do mod_make_new(menu)
	}

	ui.section(k, "FROM YOUR SOLDAT 1")
	page_import(menu)
}

// The new mod made, picked on Installed Mods to fill.
@(private = "file")
mod_make_new :: proc(menu: ^Menu) {
	mods := &menu.mods
	name := strings.clone(strings.trim_space(mods.new_name), context.temp_allocator)
	if problem := res.mod_new(res.MODS_DIR, name); problem != "" {
		note(mods, problem, true)
		return
	}
	set_text(&mods.new_name, "")
	mods_relist(mods)
	pick(mods, name)
	mods.tab = .Installed
	note(mods, fmt.tprintf("%s made: put its files in mods/%s/.", name, name), false)
	folder_open(utils.temp_path(res.MODS_DIR, name))
}

// A mod's file picked in the dialog, or dropped on the window, added: unpacked (or made
// one of this game's) on the job's thread.
@(private = "file")
files_taken :: proc(menu: ^Menu) {
	mods := &menu.mods
	if picked, taken := folder_pick_take(&mods.file); taken {
		if picked != "" do file_add(menu, picked)
		delete(picked)
	}
	if !rl.IsFileDropped() do return
	dropped := rl.LoadDroppedFiles()
	defer rl.UnloadDroppedFiles(dropped)
	for i in 0 ..< int(dropped.count) {
		path := string(dropped.paths[i])
		extension := strings.to_lower(filepath.ext(path), context.temp_allocator)
		if extension == ".zip" || extension == res.SRMOD_EXTENSION || extension == res.MOD_EXTENSION {
			file_add(menu, path)
			return
		}
	}
	note(mods, "That isn't a mod's file: drop a .zip or a .srmod.", true)
}

@(private = "file")
file_add :: proc(menu: ^Menu, path: string) {
	mods := &menu.mods
	job := &mods.adding
	if soldat_job_busy(job) {
		note(mods, "Wait for what is being added to be done first.", true)
		return
	}
	set_text(&mods.note, "")
	soldat_job_start(job, .Unpack, rl.GetTime(), path)
}

// ---------------------------------------------------------------------------------
// From your Soldat 1

// Mods made from the player's Soldat 1.7.1. Its install, found where it is usually put
// (res.soldat_installs), else the folder picked in the system's folder dialog, taken as
// it is. Once it is, the install is not shown again: each thing in it a mod can be made
// of is, an Import each (res.soldat_sources), named for it: what the player changed of
// its own files, My S1 Mod; each mod of its mods/, those changes under it, as Soldat wore
// a mod over its own folders; each custom interface, the changes to its HUD's art under
// it. Those 1.7.1 ships with, untouched, aren't offered.
//
// Looking for the install, looking through it and importing each take a while (a Steam
// library on every drive; every file of the install weighed), so each runs on a thread
// (Soldat_Job), said while it does, the game drawn on.
@(private = "file")
page_import :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	im := &mods.import_
	if !im.looked {
		im.looked = true
		soldat_job_start(&im.job, .Find, rl.GetTime())
	}
	if picked, taken := folder_pick_take(&im.pick); taken {
		if picked != "" {
			set_text(&im.folder, picked)
			import_look(menu)
		}
		delete(picked)
	}
	wrapped(k, "Make mods of what you changed or added in your Soldat 1.7.1: its art and sounds, its words (txt/default.txt), its mods and its custom interfaces. Their art is kept as it was drawn.", ui.MUTED)

	busy := soldat_job_busy(&im.job)
	if busy && (im.job.kind == .Find || im.job.kind == .Scan) {
		said := "Looking for your Soldat..." if im.job.kind == .Find else "Looking through your Soldat..."
		line(k, fmt.tprintf("%s %s", said, elapsed(rl.GetTime() - im.job.started)), ui.MUTED)
		return
	}
	if im.root == "" {
		browse_row(menu, im.problem if im.problem != "" else "No Soldat 1.7.1 found where it is usually installed: browse to its folder.", im.problem != "")
		return
	}
	if busy && im.job.kind == .Import { // importing: the rest shown, its Imports held
		title := OWN_TITLE if im.job.source.kind == .Own else im.job.source.name
		line(k, fmt.tprintf("Importing %s... %s", title, elapsed(rl.GetTime() - im.job.started)), ui.MUTED)
	}
	line(k, fmt.tprintf("From %s", shown_path(im.root)), ui.FAINT)

	offered := false
	for kind in res.Soldat_Source_Kind {
		for source, i in im.sources {
			if source.kind != kind || source.changed == 0 do continue
			offered = true
			source_row(menu, source, i, im.sources[0].changed if im.sources[0].kind == .Own else 0)
		}
	}
	if !offered do line(k, "Nothing there to make a mod of: no art, sounds or words changed, no mods, no interfaces.", ui.MUTED)
	browse_row(menu, "Not your Soldat 1.7.1's folder? Browse to it.", false)
}

// Browse..., the system's folder dialog to pick the Soldat install with, beside `said`.
@(private = "file")
browse_row :: proc(menu: ^Menu, said: string, warn: bool) {
	k := &menu.kit
	im := &menu.mods.import_
	r := ui.row(k, ui.ROW_H + 4, false)
	if !r.shown do return
	picking := folder_pick_busy(&im.pick)
	bw := ui.button_w(k, "Browse...")
	if ui.button_at(k, r.x + r.w - 8 - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Picking..." if picking else "Browse...", false, picking) {
		folder_pick_start(&im.pick, "Pick your Soldat 1.7.1 folder", rl.GetWindowHandle())
	}
	ui.text_fit(k, ui.BODY, said, r.x + 12, r.y + r.h / 2, r.w - bw - 32, ui.WARN if warn else ui.MUTED)
}

// The mod of the install's own changes: its name, and its title as the Mods page shows it.
OWN_NAME :: "My_S1_Mod"
OWN_TITLE :: "My S1 Mod"

// What the player changed of the install, a mod of mods/, or a custom interface: what it
// is, what it holds, and Import, or Imported once a mod by its name is.
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
	kinds := [res.Soldat_Source_Kind]string{.Own = "Your changes", .Mod = "A mod", .Interface = "A custom interface"}
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
	ui.text_fit(k, ui.TINY, fmt.tprintf("%s: %s", kinds[source.kind], detail), r.x + 12, r.y + 30, bx - r.x - 24, ui.FAINT)
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
// holds that mods can be made of, the install taken as found; or a mod made or added,
// picked, and said how it went.
@(private = "file")
soldat_job_taken :: proc(menu: ^Menu, job: ^Soldat_Job) {
	mods := &menu.mods
	im := &mods.import_
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
	case .Import, .Unpack:
		if job.problem != "" {
			what := job.name if job.name != "" else filepath.base(job.root)
			note(mods, fmt.tprintf("%s couldn't be added: %s", what, job.problem), true)
			return
		}
		title := OWN_TITLE if job.kind == .Import && job.source.kind == .Own else job.name
		mods_relist(mods)
		pick(mods, job.name)
		mods.tab = .Installed
		note(mods, fmt.tprintf("%s added: switch on the parts to wear.", title), false)
	}
}

// "4s", "1m 05s": how long a job has been running.
@(private = "file")
elapsed :: proc(seconds: f64) -> string {
	s := int(seconds)
	if s < 60 do return fmt.tprintf("%ds", s)
	return fmt.tprintf("%dm %02ds", s / 60, s % 60)
}

// ---------------------------------------------------------------------------------
// Mod Marketplace

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

// Whether a mod of the player's is in mods/ by `name`, in any case: one an install mustn't
// overwrite, and an import mustn't be made over.
@(private = "file")
name_taken :: proc(menu: ^Menu, name: string) -> bool {
	for listing in menu.mods.listings {
		if strings.equal_fold(listing.name, name) do return true
	}
	return false
}

// An install that has ended, acted on once: the mod installed, or updated, picked on
// Installed Mods; or why it failed.
@(private = "file")
install_taken :: proc(menu: ^Menu) {
	i := menu.catalog.install
	if i == nil || i.taken do return
	state, _ := online.install_progress(i)
	switch state {
	case .Done:
		i.taken = true
		mods_relist(&menu.mods)
		note(&menu.mods, fmt.tprintf("%s %s installed: it is on Installed Mods, to wear.", i.mod.title, i.mod.version), false)
	case .Failed:
		i.taken = true
		note(&menu.mods, fmt.tprintf("%s couldn't be installed: %s", i.mod.title, i.error), true)
	case .None, .Downloading, .Unpacking:
	}
}

// ---------------------------------------------------------------------------------
// The footer

// What was last done, or what the catalogue's mod picked is; and Delete, for a mod picked
// on the Installed tab.
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
	case mods.tab == .Add:
		footer_text(menu, x, tw, "A mod changes only how the game looks, sounds and speaks, never how it plays.", ui.MUTED)
	case:
		footer_text(menu, x, tw, "A mod changes only how the game looks, sounds and speaks, never how it plays.", ui.MUTED)
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

// No part worn from the mod `name`: each Classic's again, the others as they are.
@(private = "file")
wear_none :: proc(menu: ^Menu, name: string) {
	parts: [res.Part]string
	for p in res.Part {
		parts[p] = worn_from(menu, p)
		if strings.equal_fold(parts[p], name) do parts[p] = ""
	}
	use_parts(menu, parts)
}

// ---------------------------------------------------------------------------------

// mods/ read again; and the version of each mod installed.
@(private)
mods_relist :: proc(mods: ^Mods) {
	res.srmod_listings_destroy(mods.listings)
	mods.listings = res.srmod_listings(res.MODS_DIR)
	versions_forget(mods)
	for listing in mods.listings {
		mods.versions[strings.clone(listing.name)] = strings.clone(listing.version)
	}
	mods.listed = true
	if _, still := listing_of(mods, mods.selected); !still && !strings.equal_fold(mods.selected, res.MOD_CLASSIC) do set_text(&mods.selected, "")
	edit_forget(&mods.edit) // read again as it is next shown
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
	if !strings.equal_fold(name, mods.selected) {
		mods.confirm = false
		edit_forget(&mods.edit)
	}
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
		// let go of first: the client wears it, its art and sounds loaded from its folder
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
	set_text(&mods.selected, res.MOD_CLASSIC)
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
