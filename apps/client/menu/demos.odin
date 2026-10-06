package menu

import "core:fmt"
import "core:strings"

import "../../../core/utils"
import "../demo"
import "../ui"

// The demos in demos/, newest first, a row each: its name, map, recorder, length and
// date, as its header says. A click picks one, a second plays it, as Play does; the
// wheel scrolls, and with the focus on the list the arrows pick and Enter plays. Above,
// whether every game is recorded; below, the one picked, and Play, or why the last
// couldn't be played.

Demos :: struct {
	listings:   []demo.Listing,
	listed:     bool, // read from demos/ since the page was opened
	scroll:     int,  // the list's first row shown
	selected:   int,  // the demo picked, -1 for none
	clicked_at: f64,    // when it was picked, so a second click soon after plays it
	note:       string, // why the demo last asked for couldn't be played
}

DEMO_ROW :: 20
SCROLL_DEMOS :: ui.SCROLL_PAGE + 3

demos_destroy :: proc(demos: ^Demos) {
	demo.listings_destroy(demos.listings)
	delete(demos.note)
	demos^ = {}
}

page_demos :: proc(menu: ^Menu) {
	k := &menu.kit
	u := k.ui
	demos := &menu.demos
	if !demos.listed {
		demo.listings_destroy(demos.listings)
		demos.listings = demo.demo_list()
		demos.listed = true
		demos.selected = -1
	}
	n := len(demos.listings)
	x, w, y := k.x, k.w, f32(BODY_TOP)
	k.scrolling = false // the list scrolls itself

	record := &menu.config.demos.record_rounds
	if ui.chip(k, x, y, "Record every game", record^) do record^ = !record^
	counted := "1 demo" if n == 1 else fmt.tprintf("%d demos", n)
	ui.text_mid(k, ui.BODY, counted, x + w - ui.width_of(u, ui.BODY, counted), y + ui.CTRL_H / 2, ui.FAINT)
	y += ui.CTRL_H + 12

	// the columns, from the right: date, length, player, map; the name has the rest
	date_x := x + w - 108
	length_x := date_x - 66
	player_x := length_x - clamp(w * 0.18, 70, 120)
	map_x := player_x - clamp(w * 0.2, 70, 140)
	ui.text_mid(k, ui.SECTION, "NAME", x + 12, y + 9, ui.FAINT)
	ui.text_mid(k, ui.SECTION, "MAP", map_x, y + 9, ui.FAINT)
	ui.text_mid(k, ui.SECTION, "PLAYER", player_x, y + 9, ui.FAINT)
	ui.text_mid(k, ui.SECTION, "LENGTH", length_x, y + 9, ui.FAINT)
	ui.text_mid(k, ui.SECTION, "RECORDED", date_x, y + 9, ui.FAINT)
	y += 20

	h := k.bottom - y
	rows := max(int(h / DEMO_ROW), 1)
	list_id := ui.nav_next(k)
	focused := ui.nav_focused(k, list_id, y, h)
	if focused && k.move != 0 { // the arrows pick along the list, and past its ends leave it
		to := (0 if k.move > 0 else -1) if demos.selected < 0 else demos.selected + k.move
		if to >= 0 && to < n {
			demos.selected = to
			k.move = 0
			if to < demos.scroll do demos.scroll = to
			if to >= demos.scroll + rows do demos.scroll = to - rows + 1
		}
	}
	if ui.over(k, x, y, w, h) && k.wheel != 0 {
		demos.scroll -= k.wheel * 3
		k.wheel = 0
	}
	demos.scroll = clamp(demos.scroll, 0, max(n - rows, 0))
	track, knob: f32
	if n > rows { // its bar, dragged: before the rows, so the press is the bar's
		track = h - 8
		knob = max(track * f32(rows) / f32(n), 10)
		pos := ui.scroll_take(k, SCROLL_DEMOS, x + w - 6, y + 4, track, knob, f32(demos.scroll) / f32(n - rows))
		demos.scroll = clamp(int(pos * f32(n - rows) + 0.5), 0, n - rows)
	}
	ui.focus_ring(k, focused, x, y, w, h, ui.RADIUS)
	ui.box(u, x, y, w, h, ui.WELL, ui.LINE)
	for row_at := 0; row_at < rows && demos.scroll + row_at < n; row_at += 1 {
		i := demos.scroll + row_at
		d := &demos.listings[i]
		ry := y + 2 + f32(row_at) * DEMO_ROW
		cy := ry + DEMO_ROW / 2
		picked, hot := i == demos.selected, ui.over(k, x, ry, w, DEMO_ROW)
		if picked {
			ui.rrect(u, x + 2, ry, w - 4, DEMO_ROW, ui.RADIUS, ui.ACCENT_SOFT)
			ui.rrect(u, x + 2, ry + 4, 2, DEMO_ROW - 8, 1, ui.ACCENT)
		} else if hot {
			ui.rrect(u, x + 2, ry, w - 4, DEMO_ROW, ui.RADIUS, ui.HOVER)
		}
		ui.text_fit(k, ui.BODY, d.name, x + 12, cy, map_x - x - 20, ui.TEXT)
		ui.text_fit(k, ui.BODY, utils.short_string_text(&d.header.map_name), map_x, cy, player_x - map_x - 8, ui.MUTED)
		ui.text_fit(k, ui.BODY, utils.short_string_text(&d.header.name), player_x, cy, length_x - player_x - 8, ui.MUTED)
		ui.text_mid(k, ui.BODY, demo.ticks_text(d.header.ticks), length_x, cy, ui.MUTED)
		ui.text_fit(k, ui.BODY, d.recorded, date_x, cy, x + w - date_x - 8, ui.MUTED)
		if ui.take(k, list_id, x, ry, w, DEMO_ROW) {
			if picked && k.time - demos.clicked_at < ui.DOUBLE_CLICK do play(menu, d)
			demos.selected = i
			demos.clicked_at = k.time
		}
	}
	if n > rows { // where in the list this is
		ui.scroll_draw(k, SCROLL_DEMOS, x + w - 6, y + 4, track, knob, f32(demos.scroll) / f32(n - rows))
	}
	if n == 0 { // the list's empty state: how to make one
		none := ui.fit(k, ui.BODY, "No demos yet. Type record in the console during a game, or record every game.", w - 40)
		ui.text_mid(k, ui.BODY, none, x + (w - ui.width_of(u, ui.BODY, none)) / 2, y + h / 2, ui.MUTED)
	}
	selected := demos.selected >= 0 && demos.selected < n
	if focused && k.enter {
		k.enter = false
		if selected do play(menu, &demos.listings[demos.selected])
	}

	// the action bar: the one picked, and Play
	pressed, px := big_button(menu, x + w, "PLAY", true, !selected)
	if pressed && selected do play(menu, &demos.listings[demos.selected])
	tw := px - x - 16
	if demos.note != "" {
		footer_text(menu, x, tw, demos.note, ui.WARN)
	} else if selected {
		d := &demos.listings[demos.selected]
		ui.text_fit(k, ui.LABEL, d.name, x, ACTION_CY - 7, tw, ui.TEXT)
		line := fmt.tprintf("%s on %s, %s  -  %s", utils.short_string_text(&d.header.name), utils.short_string_text(&d.header.map_name), demo.ticks_text(d.header.ticks), d.recorded)
		ui.text_fit(k, ui.BODY, line, x, ACTION_CY + 9, tw, ui.MUTED)
	} else if n > 0 {
		footer_text(menu, x, tw, "Pick a demo, or double-click one to play it. The arrows skip ten seconds as it plays.", ui.MUTED)
	}
}

// The demo asked for: played in the menu's place, if it can be.
@(private = "file")
play :: proc(menu: ^Menu, d: ^demo.Listing) {
	delete(menu.demos.note)
	menu.demos.note = ""
	menu.request = Play_Demo{d.name}
}

// The demo asked for couldn't be played: why, on the demos page.
menu_demo_failed :: proc(menu: ^Menu, why: string) {
	if menu.page != .Demos do go_page(menu, .Demos)
	delete(menu.demos.note)
	menu.demos.note = strings.clone(why)
}
