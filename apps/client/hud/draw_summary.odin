package hud

import sa "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import sim "../../../core/game"
import res "../../../core/resources"
import "../ui"

// The end-of-round screen's panel, over the curtain that covers the field and above the
// winners' stage in the bottom third (draw.draw_victory). Laid out as a broadcast's: the
// server and the limit in the top corners, the headline of who won, the scorebug under
// it with each team's captures in a block of its colour, then a table for each team side
// by side, every player ranked with kills, deaths, captures, accuracy, headshots and best
// streak, the figures right-aligned under their captions and totalled under them, and
// along the bottom the round's awards as cards. It fades in with the curtain
// (Hud_Data.ended_fade). Set in the menu's type, as the menus are, not the mod's HUD
// fonts: it is the client's own screen.

@(private = "file") STAGE_TOP :: f32(ui.VIEW_HEIGHT) * 2 / 3 // the stage takes the bottom third below this
@(private = "file") PANEL_W :: f32(720)  // at most; a narrower view narrows it
@(private = "file") MARGIN :: f32(18)    // the view's edge to the panel, at least
@(private = "file") PAD :: f32(14)       // inside the panel
@(private = "file") HEAD_H :: f32(18)    // a table's caption row
@(private = "file") ROW_H :: f32(15)     // a player's row, at most
@(private = "file") ROW_MIN :: f32(11)   // and at least, where a team is long
@(private = "file") CARD_H :: f32(38)    // an award's card
@(private = "file") CARD_GAP :: f32(8)
@(private = "file") CARDS_ACROSS :: 4
@(private = "file") BAR :: f32(3)        // a team's colour bar

// the type
@(private = "file") HEADLINE :: ui.Style{.Display, ui.DISPLAY_POINTS * 1.45, 0.02}
@(private = "file") SCORE :: ui.Style{.Display, ui.DISPLAY_POINTS * 1.5, 0}
@(private = "file") TEAM_STYLE :: ui.Style{.Bold, ui.UI_POINTS * 0.9, 0.14}
@(private = "file") CAPTION :: ui.Style{.Bold, ui.UI_POINTS * 0.68, 0.2} // small capitals, tracked out
@(private = "file") CELL :: ui.Style{.Regular, ui.UI_POINTS * 0.88, 0}
@(private = "file") CELL_BOLD :: ui.Style{.Bold, ui.UI_POINTS * 0.88, 0}
@(private = "file") VALUE :: ui.Style{.Display, ui.DISPLAY_POINTS * 0.95, 0} // an award's figure

// the colours: the menu's, with the teams' softened for a dark ground
@(private = "file") PANEL_FILL :: rl.Color{22, 27, 38, 232}
@(private = "file") ROW_STRIPE :: rl.Color{255, 255, 255, 9}
@(private = "file") MY_STRIPE :: rl.Color{232, 80, 30, 34}
@(private = "file") CARD_FILL :: rl.Color{255, 255, 255, 10}
@(private = "file") GOLD :: rl.Color{236, 192, 84, 255}
@(private = "file") TIE_COLOR :: rl.Color{236, 239, 244, 255}

@(private = "file", rodata)
TEAM_COLORS := #partial [res.Team]rl.Color {
	.Alpha   = {236, 72, 60, 255},
	.Bravo   = {82, 128, 255, 255},
	.Charlie = {0xDF, 0xDF, 0x53, 0xFF},
	.Delta   = {0x53, 0xDF, 0x53, 0xFF},
}

// What every part of the panel draws with.
@(private = "file")
Panel :: struct {
	u:    ^ui.Ui,
	data: ^Hud_Data,
	fade: f32, // how far in the screen is: every colour's alpha is scaled by it
}

// The whole panel: the header, the teams' tables, the awards.
draw_round_summary :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	p := Panel{u, data, data.ended_fade}
	if p.fade <= 0 do return
	rl.EndBlendMode() // the shapes' colours aren't premultiplied, as the pictures' are
	rlgl.DisableBackfaceCulling() // and are wound either way, as the menu draws them
	defer {
		rlgl.DrawRenderBatchActive()
		rlgl.EnableBackfaceCulling()
	}
	w := min(u.width - 2 * MARGIN, PANEL_W)
	x := math.floor((u.width - w) / 2)
	top, bottom := f32(12), STAGE_TOP - 12
	ui.box_r(u, x, top, w, bottom - top, 6, faded(&p, PANEL_FILL), faded(&p, ui.BORDER))
	y := header(&p, x, top, w)
	y = tables(&p, x + PAD, y, w - 2 * PAD, bottom - PAD)
	awards(&p, x + PAD, y, w - 2 * PAD, bottom - PAD)
}

// The top of the panel: the winners' colour along its edge, the server and the limit in
// its corners, the headline, and the scorebug. Returns the y where the tables begin.
@(private = "file")
header :: proc(p: ^Panel, x, top, w: f32) -> f32 {
	u, data := p.u, p.data
	alpha, bravo := data.captures[.Alpha], data.captures[.Bravo]
	winner := res.Team.None
	if alpha > bravo do winner = .Alpha
	if bravo > alpha do winner = .Bravo

	// the edge: the winners' colour, or each team's half on a tie
	if winner == .None {
		flat(p, x + 6, top, w / 2 - 6, BAR, TEAM_COLORS[.Alpha])
		flat(p, x + w / 2, top, w / 2 - 6, BAR, TEAM_COLORS[.Bravo])
	} else {
		flat(p, x + 6, top, w - 12, BAR, TEAM_COLORS[winner])
	}

	// the corners: the server, and what the round was played to
	say(p, CAPTION, upper(data.hostname), x + PAD, top + 10, ui.MUTED)
	limit := text(.Summary_Final)
	if data.limit > 0 do limit = text(.Summary_Limit, data.limit)
	say_right(p, CAPTION, limit, x + w - PAD, top + 10, ui.MUTED)

	// the headline
	title, color := text(.Summary_Tie), TIE_COLOR
	#partial switch winner {
	case .Alpha: title, color = text(.Summary_Alpha_Wins), TEAM_COLORS[.Alpha]
	case .Bravo: title, color = text(.Summary_Bravo_Wins), TEAM_COLORS[.Bravo]
	}
	cx := x + w / 2
	say_mid(p, HEADLINE, title, cx, top + 20, color)

	// the scorebug: each team's captures in a block of its colour, its name beside it
	BLOCK_W :: f32(46)
	BLOCK_H :: f32(28)
	GAP :: f32(3)
	y := top + 20 + ui.height_of(u, HEADLINE) + 6
	ui.rrect(u, cx - GAP / 2 - BLOCK_W, y, BLOCK_W, BLOCK_H, 3, faded(p, with_alpha(TEAM_COLORS[.Alpha], 225)))
	ui.rrect(u, cx + GAP / 2, y, BLOCK_W, BLOCK_H, 3, faded(p, with_alpha(TEAM_COLORS[.Bravo], 225)))
	score_y := y + (BLOCK_H - ui.height_of(u, SCORE)) / 2
	say_mid(p, SCORE, fmt.tprintf("%d", alpha), cx - GAP / 2 - BLOCK_W / 2, score_y, ui.TEXT)
	say_mid(p, SCORE, fmt.tprintf("%d", bravo), cx + GAP / 2 + BLOCK_W / 2, score_y, ui.TEXT)
	name_y := y + (BLOCK_H - ui.height_of(u, TEAM_STYLE)) / 2
	say_right(p, TEAM_STYLE, upper(team_name(.Alpha)), cx - GAP / 2 - BLOCK_W - 10, name_y, TEAM_COLORS[.Alpha])
	say(p, TEAM_STYLE, upper(team_name(.Bravo)), cx + GAP / 2 + BLOCK_W + 10, name_y, TEAM_COLORS[.Bravo])
	return y + BLOCK_H + 14
}

// The teams' tables side by side, between `y` and `bottom`, leaving the awards a row of
// cards where the teams are short. The rows shrink where a team is long; longer still,
// the awards go, and what still doesn't fit is counted under the table. Returns the y
// below the tables, where the awards begin.
@(private = "file")
tables :: proc(p: ^Panel, x, y, w, bottom: f32) -> f32 {
	data := p.data
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	teams: sa.Small_Array(4, res.Team)
	longest := 0
	for team in ([?]res.Team{.Alpha, .Bravo, .Charlie, .Delta}) {
		n := 0
		for id in ranks do n += int(data.players[id].team == team)
		if n == 0 do continue
		sa.append(&teams, team)
		longest = max(longest, n)
	}
	if sa.len(teams) == 0 do return y

	AWARDS_H :: CARD_H + 30 // a row of cards, its caption and the gaps about it
	frame := HEAD_H + ROW_H + 6 // the caption row and the totals
	room := bottom - y - frame - AWARDS_H
	row_h := clamp(math.floor(room / f32(longest)), ROW_MIN, ROW_H)
	rows := min(longest, int(room / row_h))
	if rows < longest { // the awards' room given to the rows instead
		room = bottom - y - frame
		row_h = clamp(math.floor(room / f32(longest)), ROW_MIN, ROW_H)
		rows = min(longest, int(room / row_h))
	}
	GAP :: f32(12)
	count := f32(sa.len(teams))
	tw := math.floor((w - GAP * (count - 1)) / count)
	h := frame + f32(rows) * row_h
	for team, i in sa.slice(&teams) {
		table(p, team, ranks, {x + (tw + GAP) * f32(i), y, tw, h}, row_h, rows)
	}
	return y + h + 12
}

// One team's table: its caption row, the colour bar down its left, each player's row
// with the figures right-aligned under their captions, and the team's totals.
@(private = "file")
table :: proc(p: ^Panel, team: res.Team, ranks: []sim.Soldier_Id, r: rl.Rectangle, row_h: f32, rows: int) {
	u, data := p.u, p.data
	color := TEAM_COLORS[team]

	// the columns' right edges, laid from the right; the name takes what is left
	widths := [6]f32{26, 26, 32, 38, 28, 36}
	captions := [6]string{text(.Summary_Kills), text(.Summary_Deaths), text(.Summary_Captures), text(.Summary_Accuracy), text(.Summary_Headshots), text(.Summary_Streak)}
	cols: [6]f32
	edge := r.x + r.width - 6
	for i := len(cols) - 1; i >= 0; i -= 1 {
		cols[i] = edge
		edge -= widths[i]
	}
	name_x := r.x + BAR + 8
	rank_w := f32(16)
	name_w := edge - 10 - name_x - rank_w

	// the caption row: the team's name, the columns' captions, a rule in its colour
	flat(p, r.x, r.y, BAR, r.height, color)
	flat(p, r.x + BAR, r.y, r.width - BAR, HEAD_H, with_alpha(color, 26))
	say(p, TEAM_STYLE, upper(team_name(team)), name_x, r.y + (HEAD_H - ui.height_of(u, TEAM_STYLE)) / 2, color)
	cap_y := r.y + (HEAD_H - ui.height_of(u, CAPTION)) / 2
	for caption, i in captions do say_right(p, CAPTION, caption, cols[i], cap_y, ui.MUTED)
	hair(p, r.x + BAR, r.x + r.width, r.y + HEAD_H, with_alpha(color, 110))

	// the rows, ranked
	y := r.y + HEAD_H
	kills, deaths, caps, shots, hits, headshots: i32
	placed := 0
	for id in ranks {
		pl := &data.players[id]
		if pl.team != team do continue
		kills += pl.kills
		deaths += pl.deaths
		caps += pl.flags
		shots += pl.shots
		hits += pl.hits
		headshots += pl.headshots
		placed += 1
		if placed > rows do continue // off the bottom, counted under the table
		if placed % 2 == 0 do flat(p, r.x + BAR, y, r.width - BAR, row_h, ROW_STRIPE)
		if id == data.me do flat(p, r.x + BAR, y, r.width - BAR, row_h, MY_STRIPE)
		style := CELL_BOLD if id == data.me else CELL
		ty := y + (row_h - ui.height_of(u, style)) / 2
		say(p, CAPTION, fmt.tprintf("%d", placed), name_x, y + (row_h - ui.height_of(u, CAPTION)) / 2, ui.FAINT)
		say(p, style, fit(p, style, pl.name, name_w), name_x + rank_w, ty, ui.TEXT)
		figures := [6]string{
			fmt.tprintf("%d", pl.kills),
			fmt.tprintf("%d", pl.deaths),
			fmt.tprintf("%d", pl.flags),
			fmt.tprintf("%d%%", percent_of(pl.hits, pl.shots)),
			fmt.tprintf("%d", pl.headshots),
			fmt.tprintf("%d", pl.streak),
		}
		for figure, i in figures do say_right(p, style, figure, cols[i], ty, ui.TEXT)
		y += row_h
	}

	// the totals, and how many rows are off the bottom
	y = r.y + HEAD_H + f32(rows) * row_h + 3
	hair(p, r.x + BAR, r.x + r.width, y, ui.DIVIDER)
	y += 3
	ty := y + (ROW_H - ui.height_of(u, CAPTION)) / 2
	say(p, CAPTION, text(.Summary_Total), name_x, ty, ui.MUTED)
	if placed > rows {
		more_x := name_x + ui.width_of(u, CAPTION, text(.Summary_Total)) + 10
		say(p, CAPTION, text(.Summary_More, placed - rows), more_x, ty, ui.FAINT)
	}
	totals := [5]string{
		fmt.tprintf("%d", kills),
		fmt.tprintf("%d", deaths),
		fmt.tprintf("%d", caps),
		fmt.tprintf("%d%%", percent_of(hits, shots)),
		fmt.tprintf("%d", headshots),
	}
	ty = y + (ROW_H - ui.height_of(u, CELL_BOLD)) / 2
	for total, i in totals do say_right(p, CELL_BOLD, total, cols[i], ty, with_alpha(ui.TEXT, 210))
}

// The round's awards along the bottom, as cards: four across, the combat ones first,
// the flag ones in a second row where there is room. None where the tables took the room.
@(private = "file")
awards :: proc(p: ^Panel, x, y, w, bottom: f32) {
	CAPTION_H :: f32(20)
	rows := 0
	switch room := bottom - y; {
	case room >= CAPTION_H + 2 * CARD_H + CARD_GAP: rows = 2
	case room >= CAPTION_H + CARD_H:                rows = 1
	}
	if rows == 0 do return
	caption := text(.Summary_Awards)
	say(p, CAPTION, caption, x, y + 2, GOLD)
	hair(p, x + ui.width_of(p.u, CAPTION, caption) + 8, x + w, y + 2 + ui.height_of(p.u, CAPTION) / 2, with_alpha(GOLD, 60))
	cy := y + CAPTION_H
	cw := math.floor((w - CARD_GAP * (CARDS_ACROSS - 1)) / CARDS_ACROSS)
	for a, i in AWARDS {
		if i >= rows * CARDS_ACROSS do break
		col, row := i % CARDS_ACROSS, i / CARDS_ACROSS
		card(p, a, {x + (cw + CARD_GAP) * f32(col), cy + (CARD_H + CARD_GAP) * f32(row), cw, CARD_H})
	}
}

// An award's card: its name small along the top, the leader's name in their team's colour
// under it, and the figure big on the right; a dash where nobody qualifies.
@(private = "file")
card :: proc(p: ^Panel, a: Award, r: rl.Rectangle) {
	u := p.u
	ui.box_r(u, r.x, r.y, r.width, r.height, 3, faded(p, CARD_FILL), faded(p, ui.BORDER))
	id := best_of(p.data, a.score)
	bar := ui.FAINT
	if id >= 0 do bar = TEAM_COLORS[p.data.players[id].team]
	flat(p, r.x, r.y + 6, BAR, r.height - 12, bar)
	tx := r.x + BAR + 8
	say(p, CAPTION, upper(text(a.label)), tx, r.y + 6, ui.MUTED)
	name_y := r.y + 6 + ui.height_of(u, CAPTION) + 2
	if id < 0 {
		say(p, CELL, "-", tx, name_y, ui.FAINT)
		return
	}
	pl := &p.data.players[id]
	val := a.value(pl)
	say_right(p, VALUE, val, r.x + r.width - 8, r.y + (r.height - ui.height_of(u, VALUE)) / 2, ui.TEXT)
	name_w := r.width - BAR - 8 - ui.width_of(u, VALUE, val) - 20
	say(p, CELL_BOLD, fit(p, CELL_BOLD, pl.name, name_w), tx, name_y, bar)
}

// ---------------------------------------------------------------------------------
// The awards: each a label, a scorer that ranks the players (higher is better, and a
// player who does not qualify scores far below any), and how the leader's figure reads.

@(private = "file") UNRANKED :: f32(-1e18)
@(private = "file") Scorer :: proc(p: ^Player) -> f32

@(private = "file")
Award :: struct {
	label: res.String_Id,
	score: Scorer,
	value: proc(p: ^Player) -> string,
}

@(private = "file", rodata)
AWARDS := [8]Award {
	{.Award_Top_Fragger, score_kills, value_kills},
	{.Award_Best_Accuracy, score_accuracy, value_accuracy},
	{.Award_Longest_Streak, score_streak, value_streak},
	{.Award_Most_Captures, score_caps, value_caps},
	{.Award_Most_Headshots, score_headshots, value_headshots},
	{.Award_Deadliest_Aim, score_hs_rate, value_hs_rate},
	{.Award_Longest_Carry, score_carry, value_carry},
	{.Award_Fastest_Capture, score_fastest, value_fastest},
}

// The leading player by `score`, or -1 where nobody qualifies. Spectators sit out.
@(private = "file")
best_of :: proc(data: ^Hud_Data, score: Scorer) -> int {
	best_id := -1
	best := UNRANKED
	for &p, id in data.players {
		if !p.active || p.team == .Spectator do continue
		if v := score(&p); v > best {
			best, best_id = v, id
		}
	}
	return best_id if best > UNRANKED / 2 else -1
}

@(private = "file") score_kills :: proc(p: ^Player) -> f32 {return f32(p.kills) if p.kills > 0 else UNRANKED}
@(private = "file") score_accuracy :: proc(p: ^Player) -> f32 {return f32(p.hits) / f32(p.shots) if p.shots >= 5 else UNRANKED}
@(private = "file") score_headshots :: proc(p: ^Player) -> f32 {return f32(p.headshots) if p.headshots > 0 else UNRANKED}
@(private = "file") score_hs_rate :: proc(p: ^Player) -> f32 {return f32(p.headshots) / f32(p.kills) if p.kills >= 3 && p.headshots > 0 else UNRANKED}
@(private = "file") score_streak :: proc(p: ^Player) -> f32 {return f32(p.streak) if p.streak > 1 else UNRANKED}
@(private = "file") score_caps :: proc(p: ^Player) -> f32 {return f32(p.flags) if p.flags > 0 else UNRANKED}
@(private = "file") score_carry :: proc(p: ^Player) -> f32 {return f32(p.carry_ticks) if p.carry_ticks > 0 else UNRANKED}
@(private = "file") score_fastest :: proc(p: ^Player) -> f32 {return -f32(p.fastest_cap) if p.fastest_cap > 0 else UNRANKED}

@(private = "file") value_kills :: proc(p: ^Player) -> string {return fmt.tprintf("%d", p.kills)}
@(private = "file") value_accuracy :: proc(p: ^Player) -> string {return fmt.tprintf("%d%%", percent_of(p.hits, p.shots))}
@(private = "file") value_headshots :: proc(p: ^Player) -> string {return fmt.tprintf("%d", p.headshots)}
@(private = "file") value_hs_rate :: proc(p: ^Player) -> string {return fmt.tprintf("%d%%", percent_of(p.headshots, p.kills))}
@(private = "file") value_streak :: proc(p: ^Player) -> string {return fmt.tprintf("%d", p.streak)}
@(private = "file") value_caps :: proc(p: ^Player) -> string {return fmt.tprintf("%d", p.flags)}
@(private = "file") value_carry :: proc(p: ^Player) -> string {return carry_time(p.carry_ticks)}
@(private = "file") value_fastest :: proc(p: ^Player) -> string {return fmt.tprintf("%.1fs", f32(p.fastest_cap) / f32(sim.TICK_RATE))}

// ---------------------------------------------------------------------------------
// Little helpers: every colour through the fade, text placed by its left, right or middle.

@(private = "file")
faded :: proc(p: ^Panel, color: rl.Color) -> rl.Color {
	return {color.r, color.g, color.b, u8(f32(color.a) * p.fade)}
}

// A flat rectangle, `w` by `h` from `x, y`.
@(private = "file")
flat :: proc(p: ^Panel, x, y, w, h: f32, color: rl.Color) {
	ui.rect(p.u, x, y, x + w, y + h, faded(p, color))
}

// A hairline across, from `x0` to `x1` at `y`.
@(private = "file")
hair :: proc(p: ^Panel, x0, x1, y: f32, color: rl.Color) {
	ui.rule(p.u, x0, x1, y, faded(p, color))
}

// `str` in `style`, its line's top at `y` and its left at `x`, over the menu's shadow.
@(private = "file")
say :: proc(p: ^Panel, style: ui.Style, str: string, x, y: f32, color: rl.Color) {
	ui.text(p.u, str, {x, y}, style.size, faded(p, color), shadow = faded(p, ui.MENU_SHADOW), face = style.face, tracking = style.tracking)
}

// `str` with its right end at `right_x`.
@(private = "file")
say_right :: proc(p: ^Panel, style: ui.Style, str: string, right_x, y: f32, color: rl.Color) {
	say(p, style, str, right_x - ui.width_of(p.u, style, str), y, color)
}

// `str` with its middle at `cx`.
@(private = "file")
say_mid :: proc(p: ^Panel, style: ui.Style, str: string, cx, y: f32, color: rl.Color) {
	say(p, style, str, cx - ui.width_of(p.u, style, str) / 2, y, color)
}

// `str` in capitals, for the frame's duration.
@(private = "file")
upper :: proc(str: string) -> string {
	return strings.to_upper(str, context.temp_allocator)
}

// `str` cut to fit `limit` units in `style`, with an ellipsis where it is cut.
@(private = "file")
fit :: proc(p: ^Panel, style: ui.Style, str: string, limit: f32) -> string {
	if ui.width_of(p.u, style, str) <= limit do return str
	for n := len(str) - 1; n > 0; n -= 1 {
		if !utf8.rune_start(str[n]) do continue
		cut := fmt.tprintf("%s...", str[:n])
		if ui.width_of(p.u, style, cut) <= limit do return cut
	}
	return "..."
}

// `part` of `whole`, in whole percent, 100 at most (a shotgun's pellets can hit more than
// its shots count); 0 of nothing.
@(private = "file")
percent_of :: proc(part, whole: i32) -> i32 {
	return min(i32(math.round(f32(part) * 100 / f32(whole))), 100) if whole > 0 else 0
}

// A flag-carry time: minutes and seconds past a minute, else whole seconds.
@(private = "file")
carry_time :: proc(ticks: i32) -> string {
	s := ticks / sim.TICK_RATE
	return fmt.tprintf("%d:%02d", s / 60, s % 60) if s >= 60 else fmt.tprintf("%ds", s)
}
