package menu

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../online"
import "../ui"

// The mods, on two tabs. Configure Mods: Classic and the player's mods in mods/, each a
// folder, listed on the left; the one picked on the right, what it is and what of it is
// worn. Each of its parts (the soldier, the weapons, the sounds, the text, ...) is worn
// from it with a switch, and from whichever wore it before no longer; switched off, it
// is Classic's again (graphics.parts, docs/srmod.md). Its art's scale, the pixels to a
// unit its images were drawn at, part by part, and what its mod.json says of it are the
// player's to change, saved into its mod.json; its HUD opens in the HUD editor, its words
// in the text editor, its folder in the system's. Delete, after a second press to be
// sure. Any change is worn at once.
//
// Install Mods: the mods' catalogue (online's catalog.odin), each mod the mods
// repository publishes, installed, or updated to its newest version, in a click, its
// download's progress shown; one picked says what it is and whose. Over it, Create (a new
// mod, an empty folder to fill), Import .srmod (a .srmod, picked in the system's dialog;
// or a mod's file dropped on the window, on either tab) and Import S1 Mod (a folder of the
// player's Soldat 1: its install, every mod made of it at once, or a mod of its mods/ or
// one of its interfaces alone, 1.7.1's art under each as Soldat 1 wore it: res.soldat_import).

Mods_Tab :: enum {
	Configure,
	Install,
}

@(private = "file", rodata)
TAB_NAMES := [len(Mods_Tab)]string{"Configure Mods", "Install Mods"} // by Mods_Tab

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
	edit:     Mod_Edit,    // the picked mod's mod.json, as it is being changed
	file:     Folder_Pick, // Import .srmod's file dialog, while it is up
	folder:   Folder_Pick, // Import S1 Mod's folder dialog, while it is up
	adding:   Soldat_Job,  // a mod's file being added, or a Soldat 1 folder imported
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
	edit_forget(&mods.edit)
	if path, taken := folder_pick_take(&mods.file); taken do delete(path)
	if path, taken := folder_pick_take(&mods.folder); taken do delete(path)
	soldat_job_forget(&mods.adding) // waited for, if it runs
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
	if soldat_job_take(&mods.adding) do soldat_job_taken(menu, &mods.adding)
	if menu.texts.open {
		text_editor_page(menu)
		return
	}

	if picked := Mods_Tab(ui.tabs(k, TAB_NAMES[:], int(mods.tab))); picked != mods.tab {
		mods.tab = picked
		mods.confirm = false
		mods.about = -1
		set_text(&mods.note, "")
	}
	ui.gap(k, 8)
	switch mods.tab {
	case .Configure: tab_installed(menu)
	case .Install:   tab_install(menu)
	}
	action_bar(menu)
}

// ---------------------------------------------------------------------------------
// Configure Mods

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
		if r.shown do ui.text_wrap(k, ui.TINY, "No mods yet: get one, or import your own, on Install Mods.", r.x + 12, r.y + 6, r.w - 24, ui.FAINT)
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
	wrapped(k, "Classic can't be changed, but its HUD and its words can begin your own, in the HUD editor and the text editor, each saved as a mod of its own.", ui.FAINT)
	r := ui.row(k, ui.ROW_H + 6, false)
	if !r.shown do return
	x := r.x + 10
	if button(k, &x, r, "Edit HUD", true) do hud_editor_open(menu, "")
	if button(k, &x, r, "Edit words", true) do text_editor_open(menu, "", "Classic")
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
	if ok && button(k, &x, t, "Edit words", false) do text_editor_open(menu, listing.name, listing.title)
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
// Install Mods

// The catalogue's mods (page_catalog), and over them, on the right, what adds one of the
// player's own: Create, Import .srmod and Import S1 Mod; beside them, what is being added
// while it is.
@(private = "file")
tab_install :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	job := &mods.adding
	r := ui.row(k, ui.ROW_H + 6, false)
	if r.shown {
		y := r.y + (r.h - ui.CTRL_H) / 2
		held := soldat_job_busy(job) || folder_pick_busy(&mods.file) || folder_pick_busy(&mods.folder)
		pressed, left := row_button(k, r.x + r.w - 8, y, "Import S1 Mod", held, primary = true)
		if pressed do folder_pick_start(&mods.folder, "Pick your Soldat 1 folder, or a mod or an interface of it", rl.GetWindowHandle())
		pressed, left = row_button(k, left, y, "Import .srmod", held)
		if pressed do folder_pick_start(&mods.file, "Pick a mod to add", rl.GetWindowHandle(), MOD_FILE_PATTERNS[:])
		pressed, left = row_button(k, left, y, "Create", false)
		if pressed do mod_make_new(menu)
		ui.text_fit(k, ui.BODY, adding_said(job), r.x + 12, r.y + r.h / 2, left - r.x - 16, ui.MUTED)
	}
	ui.gap(k, 4)
	page_catalog(menu)
}

// What is being added, said beside the buttons: a mod's file, or a Soldat 1 folder, how far
// and for how long; else what the catalogue is.
@(private = "file")
adding_said :: proc(job: ^Soldat_Job) -> string {
	if !soldat_job_busy(job) do return "Mods made by the community."
	took := elapsed(rl.GetTime() - job.started)
	if job.kind == .Unpack do return fmt.tprintf("Adding %s... %s", filepath.base(job.root), took)
	done, total := sync.atomic_load(&job.progress.done), sync.atomic_load(&job.progress.total)
	if total > 1 do return fmt.tprintf("Importing your Soldat 1: %d of %d... %s", min(done + 1, total), total, took)
	return fmt.tprintf("Importing %s... %s", filepath.base(job.root), took)
}

// A new mod's name, numbered after the first (My_Mod_2...).
NEW_MOD_NAME :: "My_Mod"

// A new mod, empty, picked on Configure Mods to fill, its folder opened.
@(private = "file")
mod_make_new :: proc(menu: ^Menu) {
	mods := &menu.mods
	name := NEW_MOD_NAME
	for n := 2; res.mod_exists(res.MODS_DIR, name); n += 1 do name = fmt.tprintf("%s_%d", NEW_MOD_NAME, n)
	if problem := res.mod_new(res.MODS_DIR, name); problem != "" {
		note(mods, problem, true)
		return
	}
	mods_relist(mods)
	pick(mods, name)
	mods.tab = .Configure
	note(mods, fmt.tprintf("%s made: put its files in mods/%s/, and give it a title here.", name, name), false)
	folder_open(utils.temp_path(res.MODS_DIR, name))
}

// A mod's file picked in the dialog, or dropped on the window, added: unpacked (or made
// one of this game's) on the job's thread; and a Soldat 1 folder picked, imported.
@(private = "file")
files_taken :: proc(menu: ^Menu) {
	mods := &menu.mods
	if picked, taken := folder_pick_take(&mods.file); taken {
		if picked != "" do job_start(menu, .Unpack, picked)
		delete(picked)
	}
	if picked, taken := folder_pick_take(&mods.folder); taken {
		if picked != "" do job_start(menu, .Import, picked)
		delete(picked)
	}
	if !rl.IsFileDropped() do return
	dropped := rl.LoadDroppedFiles()
	defer rl.UnloadDroppedFiles(dropped)
	for i in 0 ..< int(dropped.count) {
		path := string(dropped.paths[i])
		extension := strings.to_lower(filepath.ext(path), context.temp_allocator)
		if extension == ".zip" || extension == res.SRMOD_EXTENSION || extension == res.MOD_EXTENSION {
			job_start(menu, .Unpack, path)
			return
		}
	}
	note(mods, "That isn't a mod's file: drop a .zip or a .srmod.", true)
}

@(private = "file")
job_start :: proc(menu: ^Menu, kind: Soldat_Job_Kind, path: string) {
	mods := &menu.mods
	if soldat_job_busy(&mods.adding) {
		note(mods, "Wait for what is being added to be done first.", true)
		return
	}
	set_text(&mods.note, "")
	soldat_job_start(&mods.adding, kind, rl.GetTime(), path)
}

// What the job that is over came to: a mod's file added, or a Soldat 1 folder imported,
// said; the mod made picked on Configure Mods, to wear.
@(private = "file")
soldat_job_taken :: proc(menu: ^Menu, job: ^Soldat_Job) {
	mods := &menu.mods
	switch job.kind {
	case .Unpack:
		if job.problem != "" {
			what := job.name if job.name != "" else filepath.base(job.root)
			note(mods, fmt.tprintf("%s couldn't be added: %s", what, job.problem), true)
			return
		}
		mods_relist(mods)
		pick(mods, job.name)
		mods.tab = .Configure
		note(mods, fmt.tprintf("%s added: switch on the parts to wear.", job.name), false)
	case .Import:
		r := &job.imported
		if r.kind == .Nothing {
			note(mods, "That isn't Soldat 1's: pick your Soldat folder, a mod of its mods/ or an interface of its custom-interfaces/.", true)
			return
		}
		mods_relist(mods)
		if len(r.made) == 0 {
			note(mods, imported_said(menu, r), true)
			return
		}
		pick(mods, r.made[0])
		mods.tab = .Configure
		note(mods, imported_said(menu, r), false)
	}
}

// How importing a Soldat 1 folder went, in a line: what was made, what was there before,
// what couldn't be, and whether Soldat 1's own art is under it.
@(private = "file")
imported_said :: proc(menu: ^Menu, r: ^res.Soldat_Imported) -> string {
	said := make([dynamic]string, context.temp_allocator)
	if len(r.made) == 1 {
		title := r.made[0]
		if listing, found := listing_of(&menu.mods, title); found do title = listing.title
		append(&said, fmt.tprintf("%s imported", title))
	} else if len(r.made) > 1 {
		append(&said, fmt.tprintf("%d mods imported", len(r.made)))
	}
	if len(r.made) > 0 && r.install == "" do append(&said, "no Soldat 1 found to put under it, so Classic is")
	if len(r.skipped) > 0 {
		append(&said, fmt.tprintf("%d imported before", len(r.skipped)) if len(r.made) + len(r.failed) > 0 else "All of it was imported before")
	}
	if len(r.failed) > 0 do append(&said, fmt.tprintf("%d couldn't be (%s)", len(r.failed), r.failed[0]))
	text := strings.join(said[:], "; ", context.temp_allocator)
	return fmt.tprintf("%s. Switch on the parts to wear.", text) if len(r.made) > 0 else text
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
// Configure Mods; or why it failed.
@(private = "file")
install_taken :: proc(menu: ^Menu) {
	i := menu.catalog.install
	if i == nil || i.taken do return
	state, _ := online.install_progress(i)
	switch state {
	case .Done:
		i.taken = true
		mods_relist(&menu.mods)
		note(&menu.mods, fmt.tprintf("%s %s installed: it is on Configure Mods, to wear.", i.mod.title, i.mod.version), false)
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
	deletable := mods.tab == .Configure && picked
	if !deletable do mods.confirm = false
	right := x + w
	if mods.tab == .Configure {
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
	case mods.tab == .Install && mods.about >= 0 && mods.about < len(c.mods) && mods.note == "":
		m := &c.mods[mods.about]
		ui.text_fit(k, ui.BODY, m.description, x, ACTION_CY - 7, tw, ui.TEXT)
		ui.text_fit(k, ui.BODY, fmt.tprintf("By %s. %s", m.author, m.licence), x, ACTION_CY + 9, tw, ui.MUTED)
	case mods.confirm:
		footer_text(menu, x, tw, fmt.tprintf("Delete %s and all its files? Press again to.", listing.title), ui.WARN)
	case mods.note != "":
		footer_text(menu, x, tw, mods.note, ui.WARN if mods.note_bad else ui.GOOD)
	case mods.tab == .Configure:
		footer_text(menu, x, tw, "Each part is worn from one mod; what that mod hasn't of it is Classic's.", ui.MUTED)
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
