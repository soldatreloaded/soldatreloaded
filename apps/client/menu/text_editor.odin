package menu

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../ui"

// The text editor: what the game says in a match (res.Strings: the kill feed's, the big
// words', the console's, the HUD's), line by line, as a mod's text part says it. It opens
// on the Mods page over the tabs, on a mod's words (its own over Classic's) or Classic's:
// each line listed by what it is about, the one picked typed into at the top, Classic's
// beside it, its placeholders (%s a name, %d a number) kept, a line that would drop one
// refused. A Soldat 1 txt/default.txt, or one of its txt/languages/*.txt, can be read into
// it. Saved, the lines that differ from Classic's are the mod's text/strings.json, and its
// text is worn; Classic's, which can't be changed, are saved as a mod of their own, My
// Text (My_Text, then My_Text_2...), as the HUD editor saves a HUD.
Text_Editor :: struct {
	open:     bool,
	from:     string, // the mod whose words these are, by its title; "Classic"
	target:   string, // the mod saved into, by name; "" until Classic's are saved once
	lines:    [res.String_Id]string, // as they are being changed
	saved:    [res.String_Id]string, // as they were opened or last saved
	classic:  [res.String_Id]string, // Classic's, under every mod's
	picked:   res.String_Id,
	typed:    string,           // the line picked, as it is being typed
	problem:  string,           // why what was typed isn't the line's
	search:   string,
	leaving:  bool,             // Close once with changes unsaved: again leaves without them
	note:     string,
	note_bad: bool,
	pick:     Folder_Pick,      // a Soldat 1 text file asked for
}

TEXT_EDITOR_NAME :: "My_Text" // the mod Classic's words are saved into, the first time: then My_Text_2...
TEXT_ROW :: 40

// The lines, by what they are about, each group from its first line to its last.
@(private = "file")
Text_Group :: struct {
	title:       string,
	first, last: res.String_Id,
}

@(private = "file", rodata)
TEXT_GROUPS := [?]Text_Group {
	{"KILLS", .Killed_By, .Multikill_17},
	{"THE FLAGS", .You_Got_Red_Flag, .Blue},
	{"SCORES AND THE ROUND", .Alpha_Scores, .Time_Left_Minutes},
	{"WHO CAME AND WENT", .Joined_Game, .No_Map_Voted},
	{"THE HUD", .Respawn_In, .Shot_Ricochets},
	{"THE SCOREBOARD", .Board_Time, .Board_Ping},
	{"VOTES", .Vote_Kick, .Menu_Select},
	{"THE ROUND'S END SCREEN", .Summary_Tie, .Award_Fastest_Capture},
}

// The editor opened on the words of the mod `name` ("" for Classic's): its own lines
// over Classic's.
text_editor_open :: proc(menu: ^Menu, name: string, title: string) {
	e := &menu.texts
	text_editor_close(menu)
	classic := res.mod_make(res.MODS_DIR)
	plain := res.strings_load(classic, context.temp_allocator)
	res.mod_destroy(&classic)
	choice: [res.Part]string
	choice[.Text] = name
	mod := res.mod_make(res.MODS_DIR, choice)
	worn := res.strings_load(mod, context.temp_allocator)
	res.mod_destroy(&mod)
	for id in res.String_Id {
		e.classic[id] = strings.clone(plain.lines[id])
		e.lines[id] = strings.clone(worn.lines[id])
		e.saved[id] = strings.clone(worn.lines[id])
	}
	e.from = strings.clone(title if name != "" else "Classic")
	if name != "" do e.target = strings.clone(name)
	e.open = true
	e.picked = .Killed_By
	set_text(&e.typed, e.lines[e.picked])
	ui.kit_reset_page(&menu.kit)
}

text_editor_close :: proc(menu: ^Menu) {
	e := &menu.texts
	if path, taken := folder_pick_take(&e.pick); taken do delete(path)
	if e.pick.thread != nil do return // its dialog up: let go of once it is closed (text_editor_page)
	for id in res.String_Id {
		delete(e.lines[id])
		delete(e.saved[id])
		delete(e.classic[id])
	}
	for s in ([]string{e.from, e.target, e.typed, e.problem, e.search, e.note}) do delete(s)
	e^ = {}
	ui.kit_reset_page(&menu.kit)
}

// The editor, over the Mods page's tabs: the line picked, typed into; then each line, by
// what it is about, found by what is searched for.
text_editor_page :: proc(menu: ^Menu) {
	k := &menu.kit
	e := &menu.texts
	if picked, taken := folder_pick_take(&e.pick); taken {
		if picked != "" do soldat_file_read(e, picked)
		delete(picked)
	}

	r := ui.row(k, 34, false)
	if r.shown {
		ui.text_fit(k, ui.BOLD, fmt.tprintf("The words of %s", e.from), r.x + 10, r.y + 14, r.w - 20, ui.TEXT)
		ui.text_fit(k, ui.TINY, "What the game says in a match. A line left as Classic's says it stays Classic's; a placeholder (%s a name, %d a number) must stay, %% for a %.", r.x + 10, r.y + 29, r.w - 20, ui.FAINT)
	}

	// the line picked
	ui.section(k, "THE LINE PICKED")
	f := ui.row(k, ui.ROW_H + 4, true)
	if typed, changed := ui.field_box(k, f.id, f.focused, f.x + 10, ui.ctrl_y(f), f.w - 20, &e.typed, e.typed, 200, e.classic[e.picked], false); changed {
		set_text(&e.typed, typed)
		line_take(e)
	}
	c := ui.row(k, 22, false)
	if c.shown {
		said := fmt.tprintf("%s  -  Classic's: %s", res.STRINGS[e.picked].key, e.classic[e.picked])
		ui.text_fit(k, ui.TINY, e.problem if e.problem != "" else said, c.x + 12, c.y + c.h / 2, c.w - 24, ui.WARN if e.problem != "" else ui.FAINT)
	}
	b := ui.row(k, ui.ROW_H + 6, false)
	if b.shown {
		x := b.x + 10
		if text_button(k, &x, b, "Classic's again", e.lines[e.picked] == e.classic[e.picked]) {
			set_text(&e.lines[e.picked], e.classic[e.picked])
			set_text(&e.typed, e.classic[e.picked])
			set_text(&e.problem, "")
			ui.edit_stop(k)
		}
		if text_button(k, &x, b, "Picking..." if folder_pick_busy(&e.pick) else "Read a Soldat 1 file...", folder_pick_busy(&e.pick)) {
			folder_pick_start(&e.pick, "Pick a Soldat 1 default.txt, or one of its languages/*.txt", rl.GetWindowHandle(), TEXT_FILE_PATTERNS[:])
		}
	}

	// the lines, found by what is searched for
	ui.gap(k, 4)
	if typed, changed := ui.field_row(k, "Find a line", &e.search, e.search, 60, "killed, flag, vote..."); changed do set_text(&e.search, typed)
	want := strings.to_lower(strings.trim_space(e.search), context.temp_allocator)
	for group in TEXT_GROUPS {
		titled := false
		for id in group.first ..= group.last {
			if want != "" && !strings.contains(strings.to_lower(e.lines[id], context.temp_allocator), want) && !strings.contains(strings.to_lower(e.classic[id], context.temp_allocator), want) && !strings.contains(res.STRINGS[id].key, want) do continue
			if !titled {
				ui.section(k, group.title)
				titled = true
			}
			text_row(menu, id)
		}
	}
	text_editor_footer(menu)
}

// A line's row: what it says, and under it what it is; lit while it is picked, an accent
// dot where it isn't Classic's.
@(private = "file")
text_row :: proc(menu: ^Menu, id: res.String_Id) {
	k := &menu.kit
	e := &menu.texts
	r := ui.row(k, TEXT_ROW, true)
	if ui.take_enter(k, r.focused) do line_pick(menu, id)
	if !r.shown do return
	if ui.take(k, r.id, r.x, r.y, r.w, r.h) do line_pick(menu, id)
	if id == e.picked {
		ui.rrect(k.ui, r.x, r.y + 1, r.w, r.h - 2, ui.RADIUS, ui.ACCENT_SOFT)
		ui.rrect(k.ui, r.x, r.y + 5, 2, r.h - 10, 1, ui.ACCENT)
	}
	changed := e.lines[id] != e.classic[id]
	if changed do ui.circle(k.ui, r.x + r.w - 14, r.y + r.h / 2, 3.5, ui.ACCENT)
	ui.text_fit(k, ui.BODY, e.lines[id], r.x + 12, r.y + 13, r.w - 40, ui.TEXT if changed else ui.MUTED)
	under := res.STRINGS[id].key if !changed else fmt.tprintf("%s  -  Classic's: %s", res.STRINGS[id].key, e.classic[id])
	ui.text_fit(k, ui.TINY, under, r.x + 12, r.y + 29, r.w - 40, ui.FAINT)
}

// The line `id` picked, typed into at the top.
@(private = "file")
line_pick :: proc(menu: ^Menu, id: res.String_Id) {
	e := &menu.texts
	ui.edit_stop(&menu.kit)
	e.picked = id
	set_text(&e.typed, e.lines[id])
	set_text(&e.problem, "")
	menu.kit.scroll = 0 // up to where it is typed
}

// What was typed made the line picked's, if its placeholders are its; nothing typed, its
// Classic's.
@(private = "file")
line_take :: proc(e: ^Text_Editor) {
	typed := e.typed
	if strings.trim_space(typed) == "" do typed = e.classic[e.picked]
	if problem := res.string_problem(e.picked, typed); problem != "" {
		set_text(&e.problem, fmt.tprintf("Not taken: %s.", problem))
		return
	}
	set_text(&e.problem, "")
	set_text(&e.lines[e.picked], typed)
	e.leaving = false
}

// A Soldat 1 text file read in: each of its lines the game says, over what is here.
@(private = "file")
soldat_file_read :: proc(e: ^Text_Editor, path: string) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		editor_note(e, fmt.tprintf("%s can't be read.", filepath.base(path)), true)
		return
	}
	read := res.strings_from_soldat(data)
	n := 0
	for line, id in read {
		if line == "" do continue
		set_text(&e.lines[id], line)
		n += 1
	}
	set_text(&e.typed, e.lines[e.picked])
	if n == 0 {
		editor_note(e, fmt.tprintf("%s says nothing other than the game's English.", filepath.base(path)), true)
	} else {
		editor_note(e, fmt.tprintf("%d line%s from %s: save to keep them.", n, "" if n == 1 else "s", filepath.base(path)), false)
	}
}

// Save, and Close: the footer's, while the editor is open.
@(private = "file")
text_editor_footer :: proc(menu: ^Menu) {
	k := &menu.kit
	e := &menu.texts
	x, w := k.x, k.w
	changed := e.lines != e.saved
	closed, cx := big_button(menu, x + w, "SURE?" if e.leaving else "CLOSE", false, false)
	saved, sx := big_button(menu, cx - 10, "SAVE", true, !changed)
	if saved do text_editor_save(menu)
	if closed {
		if changed && !e.leaving {
			e.leaving = true
		} else {
			text_editor_close(menu)
			return
		}
	}
	tw := sx - 10 - x - 6
	switch {
	case e.leaving:  footer_text(menu, x, tw, "Close without saving? Press again to.", ui.WARN)
	case e.note != "": footer_text(menu, x, tw, e.note, ui.WARN if e.note_bad else ui.GOOD)
	case changed:    footer_text(menu, x, tw, "Not saved yet.", ui.MUTED)
	case:            footer_text(menu, x, tw, "Pick a line, then type it as the mod says it.", ui.MUTED)
	}
}

// Escape, or Close: left at once without changes; once with them, the second time it is
// pressed.
text_editor_leave :: proc(menu: ^Menu) {
	e := &menu.texts
	if e.lines != e.saved && !e.leaving {
		e.leaving = true
		return
	}
	text_editor_close(menu)
}

// The lines that differ from Classic's written as the mod's text (a new mod's, made as
// Classic's are first saved), and its text worn.
@(private = "file")
text_editor_save :: proc(menu: ^Menu) {
	e := &menu.texts
	if e.target == "" {
		name := TEXT_EDITOR_NAME
		for n := 2; res.mod_exists(res.MODS_DIR, name); n += 1 do name = fmt.tprintf("%s_%d", TEXT_EDITOR_NAME, n)
		if problem := res.mod_new(res.MODS_DIR, name); problem != "" {
			editor_note(e, fmt.tprintf("Not saved: %s", problem), true)
			return
		}
		e.target = strings.clone(name)
	}
	own: [res.String_Id]string
	for id in res.String_Id do if e.lines[id] != e.classic[id] do own[id] = e.lines[id]
	if problem := res.mod_text_write(res.MODS_DIR, e.target, own); problem != "" {
		editor_note(e, fmt.tprintf("Not saved: %s", problem), true)
		return
	}
	for id in res.String_Id do set_text(&e.saved[id], e.lines[id])
	e.leaving = false
	editor_note(e, fmt.tprintf("Saved into %s, and worn.", e.target), false)
	mods_relist(&menu.mods)
	parts: [res.Part]string
	for part in res.Part do parts[part] = worn_from(menu, part)
	parts[.Text] = e.target
	use_parts(menu, parts)
}

@(private = "file")
editor_note :: proc(e: ^Text_Editor, text: string, bad: bool) {
	set_text(&e.note, text)
	e.note_bad = bad
}

// A small button, from `x` along the row `r`, `x` moved past it. Pressed.
@(private = "file")
text_button :: proc(k: ^ui.Kit, x: ^f32, r: ui.Row, caption: string, disabled: bool) -> bool {
	bw := ui.button_w(k, caption)
	pressed := ui.button_at(k, x^, r.y + (r.h - ui.CTRL_H) / 2, bw, ui.CTRL_H, caption, false, disabled)
	x^ += bw + 8
	return pressed
}
