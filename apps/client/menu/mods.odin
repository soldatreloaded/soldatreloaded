package menu

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../online"
import "../ui"

// The mods, on three tabs. Installed Mods: the player's mods in mods/, each a .smod or a
// folder, in one list (Classic, under them all, never listed): those on first, in their
// order, the top one's files first (graphics.mods), then those off. Each is turned on or
// off by its switch, one turned on going to the top; one on is dragged by its handle to
// another place among them. Each says what it changes, or that it has nothing the game
// uses; one picked can be deleted, after a second press to be sure, or its folder
// opened. Any change is worn at once.
//
// Mod Marketplace: the mods' catalogue (online's catalog.odin), each mod the mods
// repository publishes, installed, or updated to its newest version, in a click, its
// download's progress shown; one picked says what it is and whose. A mod installed is
// turned on, at the top; one on, updated, is loaded again.
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
	listings:   []res.Mod_Listing,
	versions:   map[string]string, // each of the player's mods' version, as its about.json says
	listed:     bool,   // read from mods/ since the page was opened
	selected:   string, // the mod picked, by name; "" for none
	about:      int,    // the catalogue's mod picked, to say what it is; -1 for none
	confirm:    bool,   // Delete pressed once: pressed again, it deletes
	note:       string, // what was last done, or why it couldn't be
	note_bad:   bool,
	import_:    Soldat_Import, // Create Mod From S1's
	dragging:   string, // the mod on being dragged by its handle, "" for none
	drag_from:  int,    // its place among those on
	drag_to:    int,    // where among them it would be dropped
	grab:       f32,    // where on its row it was taken, from its top
	drag_time:  f64,    // the kit's time at the last pass of the drag, for the others' slide
	slide:      map[string]f32, // the others on, by name, where they are drawn as they slide aside
}

// Create Mod From S1: the Soldat install, what in it to make a mod from, and its name.
Soldat_Import :: struct {
	folder:   string, // as typed, or found
	root:     string, // the install found from it; "" until one is
	problem:  string, // why none was
	editing:  bool,   // the folder asked for, the install found shown no longer
	looked:   bool,   // the install looked for where it is usually put, as the tab first opened
	scan:     enum {None, Due, Now}, // the install to be looked through: said this pass, done the next
	sources:  []res.Soldat_Source,
	pick:     int,    // of the sources; -1 for none
	with_own: bool,   // a mod of mods/ made with the changes to the install's own folders under it
	name:     string,
	named:    bool,   // the name typed by the player, not made from the source's
}

MOD_ROW :: 36
GRIP_W :: 24 // the handle a mod on is dragged by, at its row's left
CATALOG_ROW :: 36
PROGRESS_W :: 110 // an install's progress bar
ROW_BUTTON_GAP :: 4

mods_destroy :: proc(mods: ^Mods) {
	res.mods_list_destroy(mods.listings)
	versions_forget(mods)
	delete(mods.versions)
	delete(mods.selected)
	delete(mods.note)
	im := &mods.import_
	for s in ([]string{im.folder, im.root, im.problem, im.name}) do delete(s)
	res.soldat_sources_destroy(im.sources)
	delete(mods.dragging)
	for name in mods.slide do delete(name)
	delete(mods.slide)
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
	k := &menu.kit
	mods := &menu.mods
	on := enabled(menu)

	if len(mods.listings) == 0 {
		muted_line(k, "No mods yet: get one from the Mod Marketplace, or make one from Soldat 1.")
	} else {
		muted_line(k, "Mods stack, with the top ones taking priority.")
	}
	// one list: those on, in their order (drawn as they slide while one is dragged), then
	// those off
	list_top := k.y
	if !drag_list(menu, on, list_top) {
		for name, i in on do installed_row(menu, listing_of(mods, name) or_continue, true, i, len(on))
	}
	for &listing in mods.listings do if !is_on(on, listing.name) do installed_row(menu, &listing, false, -1, len(on))

	if listing, picked := listing_of(mods, mods.selected); picked && !listing.packed {
		page_making(menu, listing.name)
	}
}

// A mod's row, `lit` if it is on, the `index`th of the `count` on: its switch, and its
// handle to drag it by if there are others on to move it among; picked when clicked
// elsewhere on it.
@(private = "file")
installed_row :: proc(menu: ^Menu, listing: ^res.Mod_Listing, lit: bool, index, count: int) {
	k := &menu.kit
	mods := &menu.mods
	r := ui.row(k, MOD_ROW, true)
	if ui.take_enter(k, r.focused) do pick(mods, listing.name)
	if !r.shown do return
	if strings.equal_fold(listing.name, mods.selected) {
		ui.rrect(k.ui, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
		ui.rrect(k.ui, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
	}
	cy := r.y + r.h / 2
	sx := r.x + r.w - 8 - 30
	if ui.switch_at(k, sx, cy, lit) {
		if lit do turn_off(menu, listing.name)
		else do turn_on(menu, listing.name)
	}
	movable := lit && count > 1
	if movable && ui.take(k, -1, r.x, r.y, GRIP_W, r.h) { // the handle, held: dragged from here
		set_text(&mods.dragging, listing.name)
		mods.drag_from = index
		mods.drag_to = index
		mods.grab = k.ui.mouse.y - r.y
		mods.drag_time = k.time
	}
	if ui.take(k, r.id, r.x, r.y, r.w, r.h) do pick(mods, listing.name)
	if movable do ui.grip_draw(k, r.x + 9, cy, ui.TEXT if ui.over(k, r.x, r.y, GRIP_W, r.h) else ui.FAINT)
	row_text(menu, listing, r.x, r.y, sx - 14, lit)
}

// A mod's name, and under it what it changes, or that it changes nothing, from past its
// handle to `right`, on the row from `y`; a mod off, fainter.
@(private = "file")
row_text :: proc(menu: ^Menu, listing: ^res.Mod_Listing, x, y, right: f32, lit: bool) {
	k := &menu.kit
	tx := x + GRIP_W + 4
	room := right - tx - 8
	ui.text_fit(k, ui.LABEL, listing.title, tx, y + MOD_ROW / 2 - 7, room, ui.TEXT if lit else ui.MUTED)
	what, bad := contents_text(menu, listing)
	ui.text_fit(k, ui.TINY, what, tx, y + MOD_ROW / 2 + 8, room, ui.WARN if bad else ui.FAINT)
}

// The mods on, one being dragged by its handle: it follows the cursor, lifted, held to
// the list (whose rows begin at `list_top`), and the others slide aside to where it
// would go; let go, it goes there, worn at once, `on` put in its new order. False,
// drawing nothing, when none is dragged, or it was let go: the rows are drawn as they
// are then.
@(private = "file")
drag_list :: proc(menu: ^Menu, on: []string, list_top: f32) -> bool {
	k := &menu.kit
	mods := &menu.mods
	if mods.dragging == "" do return false
	n := len(on)
	from := -1
	for name, i in on do if strings.equal_fold(name, mods.dragging) do from = i
	if from < 0 || !k.held {
		to := mods.drag_to
		drag_end(mods)
		if from >= 0 && to != from {
			order := make([dynamic]string, context.temp_allocator)
			for name, i in on do if i != from do append(&order, name)
			inject_at(&order, clamp(to, 0, len(order)), on[from])
			copy(on, order[:]) // drawn in its new order at once, as it is worn
			use(menu, on)
		}
		return false
	}

	for _ in 0 ..< n do ui.row(k, MOD_ROW, false) // their room in the page, as their rows take it
	lifted := clamp(k.ui.mouse.y - mods.grab, list_top, list_top + f32(n - 1) * MOD_ROW)
	mods.drag_to = clamp(int((lifted - list_top) / MOD_ROW + 0.5), 0, n - 1)

	// the others toward their places with it moved, eased, quick but not at once
	ease := 1 - math.exp(-f32(k.time - mods.drag_time) * 22)
	mods.drag_time = k.time
	slot := 0
	for name, i in on {
		if i == from do continue
		if slot == mods.drag_to do slot += 1
		target := list_top + f32(slot) * MOD_ROW
		slot += 1
		y, sliding := mods.slide[name]
		if !sliding {
			y = list_top + f32(i) * MOD_ROW
			mods.slide[strings.clone(name)] = y
		}
		y += (target - y) * ease
		mods.slide[name] = y
		listing := listing_of(mods, name) or_continue
		drawn_row(menu, listing, y, false)
	}
	drawn_row(menu, listing_of(mods, on[from]) or_return, lifted, true) // over them all
	return true
}

// A mod on as the drag draws it, at `y`: its handle, name and switch, without acting on
// a click; `lifted`, the one dragged, raised over the rest.
@(private = "file")
drawn_row :: proc(menu: ^Menu, listing: ^res.Mod_Listing, y: f32, lifted: bool) {
	k := &menu.kit
	if y < k.top - 0.5 || y + MOD_ROW > k.bottom + 0.5 do return
	x, w := k.x, k.w
	if lifted {
		ui.rrect(k.ui, x + 1, y + 4, w, MOD_ROW - 2, ui.RADIUS + 1, {0, 0, 0, 110}) // its shadow
		ui.box(k.ui, x, y + 1, w, MOD_ROW - 2, ui.CONTROL_HOT, ui.BORDER_HOT)
	}
	cy := y + MOD_ROW / 2
	ui.grip_draw(k, x + 9, cy, ui.TEXT if lifted else ui.FAINT)
	sx := x + w - 8 - 30
	ui.switch_draw(k, sx, cy, true, false)
	row_text(menu, listing, x, y, sx - 14, true)
}

@(private = "file")
drag_end :: proc(mods: ^Mods) {
	set_text(&mods.dragging, "")
	for name in mods.slide do delete(name)
	clear(&mods.slide)
}

// What a mod changes, to show under its name: "Graphics, sounds  -  .smod  -  v1.0.0".
@(private = "file")
contents_text :: proc(menu: ^Menu, listing: ^res.Mod_Listing) -> (text: string, bad: bool) {
	if listing.contents == {} do return "Nothing the game uses: its files go in gostek-gfx/, sfx/... at its root", true
	parts := make([dynamic]string, context.temp_allocator)
	names := [res.Mod_Content]string{.Graphics = "Graphics", .Sounds = "Sounds", .Fonts = "Fonts", .Config = "mod.ini"}
	for content in res.Mod_Content do if content in listing.contents do append(&parts, names[content])
	text = strings.join(parts[:], ", ", context.temp_allocator)
	text = fmt.tprintf("%s  -  %s", text, ".smod" if listing.packed else "folder")
	if version := menu.mods.versions[listing.name]; version != "" do text = fmt.tprintf("%s  -  v%s", text, version)
	if listing.nested != "" do text = fmt.tprintf("%s  -  in %s", text, strings.trim_suffix(listing.nested, "/"))
	return
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
	"Drop gostek-gfx, weapons-gfx, sparks-gfx, interface-gfx, sfx, textures,",
	"scenery-gfx, mod.ini or txt/font.ini into its folder. What it hasn't comes from",
	"the mods under it, then Classic. Off and on again shows what you changed.",
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

// A mod of what the player changed in their Soldat 1.7.1. Its install, found where it is
// usually put, else asked for: any folder of it, or in it, finds it (res.soldat_root).
// Then what to make the mod from, looked through for what each changes: its own folders,
// which a player may have put their art over, and each mod of its mods/, the one it was
// last played with marked (a mod taking the changes to its own folders under it, as
// Soldat wears it, if there are any); and the mod's name, and Create.
@(private = "file")
page_import :: proc(menu: ^Menu) {
	k := &menu.kit
	mods := &menu.mods
	im := &mods.import_
	if !im.looked {
		im.looked = true
		if installs := res.soldat_installs(context.temp_allocator); len(installs) > 0 {
			set_text(&im.folder, installs[0])
			im.scan = .Due
		} else {
			im.editing = true
		}
	}
	muted_line(k, "Make a mod of the art and sounds you changed in your Soldat 1.7.1.")

	ui.section(k, "YOUR SOLDAT")
	if im.editing || im.root == "" {
		if typed, changed := ui.field_row(k, "Soldat folder", &im.folder, im.folder, 260, "C:\\Soldat"); changed {
			set_text(&im.folder, typed)
		}
		look := ui.edit_entered(k, &im.folder)
		r := ui.row(k, ui.ROW_H + 4, false)
		if r.shown {
			right := ui.ctrl_x(r) + ui.ctrl_w(r)
			y := ui.ctrl_y(r)
			pressed, left := row_button(k, right, y, "Use it", strings.trim_space(im.folder) == "", primary = true)
			if pressed do look = true
			if found, _ := row_button(k, left, y, "Find it", false); found {
				if installs := res.soldat_installs(context.temp_allocator); len(installs) > 0 {
					set_text(&im.folder, installs[0])
					look = true
				} else {
					set_text(&im.problem, "No Soldat where it is usually installed: type the folder it is in.")
				}
			}
		}
		if look && strings.trim_space(im.folder) != "" do im.scan = .Due
		if im.problem != "" do line(k, im.problem, ui.WARN)
	} else {
		r := ui.row(k, ui.ROW_H + 4, false)
		if r.shown {
			bw := ui.button_w(k, "Change")
			ui.text_fit(k, ui.LABEL, fmt.tprintf("Found at %s", shown_path(im.root)), r.x + 12, r.y + r.h / 2, r.w - bw - 32, ui.TEXT)
			if ui.button_at(k, r.x + r.w - 8 - bw, ui.ctrl_y(r), bw, ui.CTRL_H, "Change", false, false) do im.editing = true
		}
	}

	// looked through a frame after it is asked for, so that it says so while it does
	switch im.scan {
	case .None:
	case .Due:
		im.scan = .Now
		line(k, "Looking through your Soldat...", ui.MUTED)
		return
	case .Now:
		im.scan = .None
		import_look(menu)
	}
	if im.root == "" || im.editing do return

	ui.section(k, "MAKE IT FROM")
	if len(im.sources) == 0 do line(k, "Nothing in it to make a mod of.", ui.MUTED)
	for source, i in im.sources {
		r := ui.row(k, MOD_ROW, source.changed > 0)
		if source.changed > 0 && (ui.take_enter(k, r.focused) || (r.shown && ui.take(k, r.id, r.x, r.y, r.w, r.h))) do import_pick(im, i)
		if !r.shown do continue
		cy := r.y + r.h / 2
		ui.radio_draw(k, r.x + 14, cy, i == im.pick, r.hot, source.changed == 0)
		title := "Soldat's own folders" if source.name == "" else fmt.tprintf("mods/%s", source.name)
		detail := "Nothing changed" if source.changed == 0 else fmt.tprintf("%d file%s changed", source.changed, "" if source.changed == 1 else "s")
		if source.in_use do detail = fmt.tprintf("%s  -  the mod Soldat was last played with", detail)
		ui.text_fit(k, ui.LABEL, title, r.x + 30, cy - 7, r.w - 40, ui.TEXT if source.changed > 0 else ui.FAINT)
		ui.text_fit(k, ui.TINY, detail, r.x + 30, cy + 8, r.w - 40, ui.FAINT)
	}
	if im.pick < 0 {
		line(k, "Your Soldat is as it came: there is nothing in it to make a mod of.", ui.MUTED)
		line(k, "Change its art or sounds, or put a mod in its mods folder, then look again.", ui.MUTED)
		return
	}
	own := im.sources[0].changed if len(im.sources) > 0 else 0
	if im.pick > 0 && own > 0 {
		ui.toggle(k, fmt.tprintf("And the %d file%s changed in Soldat's own folders", own, "" if own == 1 else "s"), &im.with_own)
	}

	ui.section(k, "YOUR MOD")
	if typed, changed := ui.field_row(k, "Name", &im.name, im.name, res.MOD_NAME_MAX, "The mod's name"); changed {
		set_text(&im.name, typed)
		im.named = true
	}
	create := ui.edit_entered(k, &im.name)
	r := ui.row(k, ui.ROW_H + 4, false)
	if r.shown {
		pressed, _ := row_button(k, ui.ctrl_x(r) + ui.ctrl_w(r), ui.ctrl_y(r), "Create mod", im.pick < 0 || strings.trim_space(im.name) == "", primary = true)
		if pressed do create = true
	}
	if create && im.pick >= 0 && strings.trim_space(im.name) != "" do soldat_import(menu)
}

// The install of the folder given found, and looked through for what a mod can be made
// from; one picked: the folder's own mod of mods/ if it was in one, else the one Soldat
// was last played with, else its own folders, of those that change anything.
@(private = "file")
import_look :: proc(menu: ^Menu) {
	im := &menu.mods.import_
	root, in_mod, found := res.soldat_root(im.folder, context.temp_allocator)
	if !found {
		set_text(&im.problem, "No Soldat 1.7.1 there: pick the folder soldat.exe is in.")
		im.editing = true
		return
	}
	set_text(&im.problem, "")
	set_text(&im.root, root)
	set_text(&im.folder, shown_path(root))
	im.editing = false
	res.soldat_sources_destroy(im.sources)
	im.sources = res.soldat_sources(root, res.mod_classic(menu.mod))
	im.pick = -1
	im.with_own = len(im.sources) > 0 && im.sources[0].changed > 0
	best := -1
	for s, i in im.sources {
		if s.changed == 0 do continue
		if in_mod != "" && strings.equal_fold(s.name, in_mod) {
			best = i
			break
		}
		if s.in_use || best < 0 do best = i
	}
	if best >= 0 do import_pick(im, best)
}

// The source `i` picked, the mod named after it if the player hasn't named it.
@(private = "file")
import_pick :: proc(im: ^Soldat_Import, i: int) {
	im.pick = i
	if im.named do return
	base := im.sources[i].name
	// a mod named as the game's own, or as no file can be, is MySoldat
	if base == "" || res.mod_builtin(base) || res.mod_name_problem(res.MODS_DIR, base) != "" && !res.mod_exists(res.MODS_DIR, base) do base = "MySoldat"
	set_text(&im.name, free_name(base))
}

@(private = "file")
soldat_import :: proc(menu: ^Menu) {
	mods := &menu.mods
	im := &mods.import_
	source := im.sources[im.pick]
	dirs := make([dynamic]string, context.temp_allocator)
	if im.pick > 0 && im.with_own do append(&dirs, im.sources[0].dir)
	append(&dirs, source.dir)
	name := strings.clone(strings.trim_space(im.name), context.temp_allocator)
	result := res.mod_import(dirs[:], res.MODS_DIR, name, res.mod_classic(menu.mod))
	if result.problem != "" {
		note(mods, result.problem, true)
		return
	}
	note(mods, fmt.tprintf("%s made of %d changed file%s, and on.", name, result.changed, "" if result.changed == 1 else "s"), false)
	im.named = false
	import_pick(im, im.pick)
	mods.tab = .Installed
	turn_on(menu, name)
}

// `base`, or "<base>2", "<base>3"..., the first no mod has yet.
@(private = "file")
free_name :: proc(base: string) -> string {
	name := base
	for n := 2; res.mod_exists(res.MODS_DIR, name); n += 1 do name = fmt.tprintf("%s%d", base, n)
	return name
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
		was_on := is_on(enabled(menu), i.mod.name)
		mods_relist(&menu.mods)
		if was_on {
			note(&menu.mods, fmt.tprintf("%s updated to %s.", i.mod.title, i.mod.version), false)
			use(menu, enabled(menu)) // its new files, worn at once
		} else {
			note(&menu.mods, fmt.tprintf("%s %s installed, and on.", i.mod.title, i.mod.version), false)
			turn_on(menu, i.mod.name)
		}
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
		if picked && listing.packed {
			opened, ox := big_button(menu, right, "SHOW", false, false)
			right = ox - 10
			if opened do folder_open(res.MODS_DIR)
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
		footer_text(menu, x, tw, "Each file is the top mod's that has it, then Classic's.", ui.MUTED)
	case mods.tab == .Import:
		footer_text(menu, x, tw, "Only what you changed goes in: Soldat's own art as it came is left out.", ui.MUTED)
	case:
		footer_text(menu, x, tw, "A mod changes only how the game looks and sounds, never how it plays.", ui.MUTED)
	}
}

// ---------------------------------------------------------------------------------
// The mods on, and changing them

// The mods on, the top first: the config's, those in mods/; with the temp allocator.
@(private = "file")
enabled :: proc(menu: ^Menu) -> []string {
	on := make([dynamic]string, context.temp_allocator)
	for name in menu.config.graphics.mods {
		if _, present := listing_of(&menu.mods, name); present && !is_on(on[:], name) do append(&on, name)
	}
	return on[:]
}

@(private = "file")
is_on :: proc(on: []string, name: string) -> bool {
	for other in on do if strings.equal_fold(other, name) do return true
	return false
}

// The mod `name` turned on, at the top, or off; worn at once.
@(private = "file")
turn_on :: proc(menu: ^Menu, name: string) {
	on := make([dynamic]string, context.temp_allocator)
	append(&on, name)
	for other in enabled(menu) do if !strings.equal_fold(other, name) do append(&on, other)
	use(menu, on[:])
}

@(private = "file")
turn_off :: proc(menu: ^Menu, name: string) {
	on := make([dynamic]string, context.temp_allocator)
	for other in enabled(menu) do if !strings.equal_fold(other, name) do append(&on, other)
	use(menu, on[:])
}

// The mods `on`, the top first, asked to be worn: the client loads them, and the menu
// what it draws of them (menu_mods_changed).
@(private = "file")
use :: proc(menu: ^Menu, on: []string) {
	mods := make([]string, len(on))
	for name, i in on do mods[i] = strings.clone(name)
	menu.request = Use_Mod{mods}
}

// ---------------------------------------------------------------------------------

// mods/ read again, and each of the player's mods' version.
@(private = "file")
mods_relist :: proc(mods: ^Mods) {
	res.mods_list_destroy(mods.listings)
	mods.listings = res.mods_list(res.MODS_DIR)
	versions_forget(mods)
	for listing in mods.listings {
		mods.versions[strings.clone(listing.name)] = strings.clone(online.installed_version(res.MODS_DIR, listing.name))
	}
	mods.listed = true
	if _, still := listing_of(mods, mods.selected); !still do set_text(&mods.selected, "")
	mods.confirm = false
}

@(private = "file")
listing_of :: proc(mods: ^Mods, name: string) -> (listing: ^res.Mod_Listing, found: bool) {
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
	was_on := is_on(enabled(menu), gone)
	if !res.mod_delete(res.MODS_DIR, gone) {
		note(mods, fmt.tprintf("%s couldn't be deleted (a file of it may be open).", gone), true)
		mods.confirm = false
		return
	}
	note(mods, fmt.tprintf("%s deleted.", gone), false)
	mods_relist(mods)
	if was_on do turn_off(menu, gone) // no longer worn
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
