package menu

import "../ui"

// The server browser: the lobby's servers, a row each (name, map, players, ping),
// under a search and the filters, sorted by the column picked; below, the one picked,
// and Join. There is no network yet to ask the lobby with, so the list says so and stays
// empty: the search, the filters and the columns work, Refresh and Join wait.

Servers :: struct {
	search:          string, // by name or map
	hide_empty:      bool,
	hide_full:       bool,
	only_compatible: bool,
	sort:            Server_Sort,
	sort_up:         bool, // ascending, against the column's natural order
}

// The fullest first, at first.
Server_Sort :: enum {
	Players,
	Name,
	Map,
	Ping,
}

SEARCH_MAX :: 31

page_servers :: proc(menu: ^Menu) {
	k := &menu.kit
	s := &menu.servers
	u := k.ui
	x, w, y := k.x, k.w, f32(BODY_TOP)
	k.scrolling = false // the list scrolls itself

	// the search and the filters
	sw := clamp(w * 0.34, 120, 220)
	{
		id := ui.nav_next(k)
		focused := ui.nav_focused(k, id, y, ui.CTRL_H)
		ui.focus_ring(k, focused, x, y, sw, ui.CTRL_H, ui.RADIUS)
		if typed, changed := ui.field_box(k, id, focused, x, y, sw, &s.search, s.search, SEARCH_MAX, "Search by name or map", false); changed {
			set_text(&s.search, typed)
		}
	}
	cx := x + sw + 10
	if ui.chip(k, cx, y, "Not empty", s.hide_empty) do s.hide_empty = !s.hide_empty
	cx += ui.chip_w(k, "Not empty") + 6
	if ui.chip(k, cx, y, "Not full", s.hide_full) do s.hide_full = !s.hide_full
	cx += ui.chip_w(k, "Not full") + 6
	rw := ui.button_w(k, "Refresh")
	if cx + ui.chip_w(k, "Compatible") <= x + w - rw - 10 {
		if ui.chip(k, cx, y, "Compatible", s.only_compatible) do s.only_compatible = !s.only_compatible
	}
	ui.button_at(k, x + w - rw, y, rw, ui.CTRL_H, "Refresh", false, disabled = true) // the lobby is asked over the network
	y += ui.CTRL_H + 12

	// the columns, from the right: ping, players, map; the name has the rest
	ping_x := x + w - 46
	players_x := ping_x - 86
	map_x := players_x - clamp(w * 0.24, 80, 170)
	column_head(menu, x + 22, y, map_x - x - 30, "SERVER", .Name)
	column_head(menu, map_x, y, players_x - map_x - 6, "MAP", .Map)
	column_head(menu, players_x, y, 56, "PLAYERS", .Players)
	column_head(menu, ping_x, y, 40, "PING", .Ping)
	y += 20

	// the list, and what it is waiting on while it has nothing to show
	h := k.bottom - y
	list_id := ui.nav_next(k)
	focused := ui.nav_focused(k, list_id, y, h)
	ui.focus_ring(k, focused, x, y, w, h, ui.RADIUS)
	ui.box(u, x, y, w, h, ui.WELL, ui.LINE)
	status := ui.fit(k, ui.BODY, "The lobby can't be reached: online play isn't available yet.", w - 40)
	ui.text_mid(k, ui.BODY, status, x + (w - ui.width_of(u, ui.BODY, status)) / 2, y + h / 2, ui.WARN)

	// the action bar: the one picked, and Join
	big_button(menu, x + w, "JOIN", true, true)
}

// A column's heading, which sorts by it; a second click turns the order.
@(private = "file")
column_head :: proc(menu: ^Menu, x, y, w: f32, title: string, sort: Server_Sort) {
	k := &menu.kit
	s := &menu.servers
	sorted, hot := s.sort == sort, ui.over(k, x, y, w, 18)
	ui.text_mid(k, ui.SECTION, title, x, y + 9, ui.TEXT if sorted else ui.MUTED if hot else ui.FAINT)
	if sorted {
		// pointing down while the larger come first: the players' natural order, the
		// others' turned
		down := !s.sort_up if sort == .Players else s.sort_up
		ui.chevron(k.ui, x + ui.width_of(k.ui, ui.SECTION, title) + 8, y + 9, 5, down, ui.ACCENT)
	}
	if ui.take(k, -1, x, y, w, 18) {
		if sorted {
			s.sort_up = !s.sort_up
		} else {
			s.sort, s.sort_up = sort, false
		}
	}
}
