package hud

import sa "core:container/small_array"
import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../ui"

// The end-of-round screen, redesigned: while the scores stand the top two thirds carry a
// panel of the round's story — who won and by how much, each team's totals, every
// player's figures in a table, and the round's awards (the best fragger, the sharpest
// aim, the longest flag run, the quickest capture). The bottom third is the winners'
// stage (draw.draw_victory). This stands in for the plain scoreboard at a round's end.

@(private = "file") TITLE_FONT :: Lettering{.Menu, 1.7}
@(private = "file") PANEL_BOTTOM :: f32(314) // the stage takes the bottom third below this
@(private = "file") SUMMARY_PAD :: f32(16)
@(private = "file") ROW_H :: f32(14)

@(private = "file") LABEL_COLOR :: rl.Color{200, 196, 186, 235}
@(private = "file") DIM_COLOR :: rl.Color{168, 164, 180, 210}
@(private = "file") WHITE :: rl.Color{255, 255, 255, 255}

// The whole end screen's panel: the header band, the players' table on the left and the
// awards on the right.
draw_round_summary :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	m := math.floor(u.width * 0.5 - 320)
	m = max(m, 24)
	panel := rl.Rectangle{m, 8, u.width - 2 * m, PANEL_BOTTOM - 8}
	box(u, art, panel, FULL_BOX_ALPHA)

	inner_x := panel.x + SUMMARY_PAD
	inner_w := panel.width - 2 * SUMMARY_PAD
	header_bottom := summary_header(u, data, panel)

	// the table on the left, the awards on the right
	table_w := math.floor(inner_w * 0.60)
	summary_table(u, data, {inner_x, header_bottom, table_w, panel.y + panel.height - SUMMARY_PAD - header_bottom})
	divider_x := inner_x + table_w + 10
	fill(u, {divider_x, header_bottom + 4, 1, panel.y + panel.height - SUMMARY_PAD - header_bottom - 8}, {255, 255, 255, 40})
	summary_awards(u, data, {divider_x + 12, header_bottom, inner_x + inner_w - divider_x - 12, 0})
}

// The header: who won across the top, the final score in the teams' colours under it,
// and each team's totals to its side. Returns the y where the body begins.
@(private = "file")
summary_header :: proc(u: ^ui.Ui, data: ^Hud_Data, panel: rl.Rectangle) -> f32 {
	cx := panel.x + panel.width / 2
	alpha, bravo := data.captures[.Alpha], data.captures[.Bravo]

	title: string
	color: rl.Color
	switch {
	case alpha == bravo: title, color = text(.Summary_Tie), {245, 245, 245, 255}
	case alpha > bravo:  title, color = text(.Summary_Alpha_Wins), team_text_color(.Alpha)
	case:                title, color = text(.Summary_Bravo_Wins), team_text_color(.Bravo)
	}
	write(u, title, {cx - text_width(u, title, TITLE_FONT) / 2, panel.y + 10}, TITLE_FONT, color)

	// the final score, each team's number in its colour
	score := fmt.tprintf("%d", alpha)
	dash := "  :  "
	sw := text_width(u, score, MENU_FONT)
	dw := text_width(u, dash, MENU_FONT)
	score_y := panel.y + 40
	write(u, score, {cx - dw / 2 - sw, score_y}, MENU_FONT, team_text_color(.Alpha))
	write(u, dash, {cx - dw / 2, score_y}, MENU_FONT, DIM_COLOR)
	write(u, fmt.tprintf("%d", bravo), {cx + dw / 2, score_y}, MENU_FONT, team_text_color(.Bravo))

	// each team's totals, to its own side of the score
	summary_team_totals(u, data, .Alpha, {panel.x + SUMMARY_PAD, score_y + 1}, false)
	summary_team_totals(u, data, .Bravo, {panel.x + panel.width - SUMMARY_PAD, score_y + 1}, true)
	return panel.y + 64
}

// A team's round totals (kills, captures, accuracy), anchored to the left or the right.
@(private = "file")
summary_team_totals :: proc(u: ^ui.Ui, data: ^Hud_Data, team: res.Team, at: [2]f32, right: bool) {
	kills, caps, shots, hits: i32
	for &p in data.players {
		if !p.active || p.team != team do continue
		kills += p.kills; caps += p.flags; shots += p.shots; hits += p.hits
	}
	acc := i32(math.round(f32(hits) * 100 / f32(shots))) if shots > 0 else 0
	text := fmt.tprintf("%d kills  %d caps  %d%% acc", kills, caps, acc)
	x := at.x - text_width(u, text, SMALL_FONT) if right else at.x
	write(u, text, {x, at.y}, SMALL_FONT, with_alpha(team_text_color(team), 220))
}

// The players' table: each team captioned in its colour, its players ranked under it,
// with kills, deaths, captures, accuracy, headshots and best streak.
@(private = "file")
summary_table :: proc(u: ^ui.Ui, data: ^Hud_Data, r: rl.Rectangle) {
	// the columns' right edges, across the region's width
	w := r.width
	cK := r.x + w * 0.56
	cD := r.x + w * 0.66
	cCap := r.x + w * 0.77
	cAcc := r.x + w * 0.89
	cHS := r.x + w * 0.955
	cStrk := r.x + w - 2

	y := r.y
	write(u, text(.Summary_Player), {r.x + 2, y}, SMALL_FONT, DIM_COLOR)
	right(u, text(.Summary_Kills), cK, y, DIM_COLOR)
	right(u, text(.Summary_Deaths), cD, y, DIM_COLOR)
	right(u, text(.Summary_Captures), cCap, y, DIM_COLOR)
	right(u, text(.Summary_Accuracy), cAcc, y, DIM_COLOR)
	right(u, text(.Summary_Headshots), cHS, y, DIM_COLOR)
	right(u, text(.Summary_Streak), cStrk, y, DIM_COLOR)
	y += 4
	fill(u, {r.x, y + ROW_H - 3, w, 1}, {255, 255, 255, 30})

	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	for team in ([?]res.Team{.Alpha, .Bravo, .Charlie, .Delta}) {
		members := 0
		for id in ranks do members += int(data.players[id].team == team)
		if members == 0 do continue
		y += ROW_H
		write(u, team_name(team), {r.x + 2, y}, SMALL_FONT, team_text_color(team))
		for id in ranks {
			p := &data.players[id]
			if p.team != team do continue
			y += ROW_H
			if y > r.y + r.height do break // more than fits
			color := WHITE if id == data.me else with_alpha(p.shirt, 255)
			name := fit_name(u, p.name, cK - r.x - 44)
			write(u, name, {r.x + 6, y}, SMALL_FONT, color)
			acc := i32(math.round(f32(p.hits) * 100 / f32(p.shots))) if p.shots > 0 else 0
			right(u, fmt.tprintf("%d", p.kills), cK, y, color)
			right(u, fmt.tprintf("%d", p.deaths), cD, y, color)
			right(u, fmt.tprintf("%d", p.flags), cCap, y, color)
			right(u, fmt.tprintf("%d%%", acc), cAcc, y, color)
			right(u, fmt.tprintf("%d", p.headshots), cHS, y, color)
			right(u, fmt.tprintf("%d", p.streak), cStrk, y, color)
		}
	}
}

// The round's awards, in two groups: the combat ones, then the flag ones. Each names the
// player who leads it and the figure they lead by; a dash where nobody qualifies.
@(private = "file")
summary_awards :: proc(u: ^ui.Ui, data: ^Hud_Data, r: rl.Rectangle) {
	y := r.y
	award_group(u, text(.Summary_Combat), &y, r.x, r.width)
	award(u, data, text(.Award_Top_Fragger), score_kills, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d", p.kills)})
	award(u, data, text(.Award_Best_Accuracy), score_accuracy, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d%%", i32(math.round(f32(p.hits) * 100 / f32(p.shots))))})
	award(u, data, text(.Award_Most_Headshots), score_headshots, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d", p.headshots)})
	award(u, data, text(.Award_Deadliest_Aim), score_hs_rate, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d%% HS", i32(math.round(f32(p.headshots) * 100 / f32(p.kills))))})
	award(u, data, text(.Award_Longest_Streak), score_streak, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d", p.streak)})
	y += 6
	award_group(u, text(.Summary_Flags), &y, r.x, r.width)
	award(u, data, text(.Award_Most_Captures), score_caps, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%d", p.flags)})
	award(u, data, text(.Award_Longest_Carry), score_carry, {r.x, r.width}, &y, proc(p: ^Player) -> string {return carry_time(p.carry_ticks)})
	award(u, data, text(.Award_Fastest_Capture), score_fastest, {r.x, r.width}, &y, proc(p: ^Player) -> string {return fmt.tprintf("%.1fs", f32(p.fastest_cap) / f32(sim.TICK_RATE))})
}

@(private = "file")
award_group :: proc(u: ^ui.Ui, title: string, y: ^f32, x, w: f32) {
	write(u, title, {x, y^}, SMALL_FONT, {230, 215, 120, 240})
	fill(u, {x, y^ + ROW_H - 2, w, 1}, {230, 215, 120, 70})
	y^ += ROW_H + 4
}

// One award line: its label dimmed, then under it the leader's name and the figure. A
// dash where nobody qualifies. `value` renders the leader's figure.
@(private = "file")
award :: proc(u: ^ui.Ui, data: ^Hud_Data, label: string, score: Scorer, region: [2]f32, y: ^f32, value: proc(p: ^Player) -> string) {
	x, w := region[0], region[1]
	write(u, label, {x, y^}, SMALL_FONT, LABEL_COLOR)
	id := best_of(data, score)
	if id < 0 {
		right(u, "—", x + w, y^, DIM_COLOR)
	} else {
		p := &data.players[id]
		val := value(p)
		right(u, val, x + w, y^, {240, 235, 180, 255})
		name := fit_name(u, p.name, w - text_width(u, val, SMALL_FONT) - 48)
		write(u, name, {x + 44, y^}, SMALL_FONT, with_alpha(p.shirt, 255))
	}
	y^ += ROW_H + 3
}

// ---------------------------------------------------------------------------------
// Scorers: higher is better, and a player who does not qualify scores far below any.

@(private = "file") UNRANKED :: f32(-1e18)
@(private = "file") Scorer :: proc(p: ^Player) -> f32

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

// ---------------------------------------------------------------------------------
// Little helpers

// `str` right-aligned so its end sits at `right_x`.
@(private = "file")
right :: proc(u: ^ui.Ui, str: string, right_x, y: f32, color: rl.Color) {
	write(u, str, {right_x - text_width(u, str, SMALL_FONT), y}, SMALL_FONT, color)
}

// A name cut to fit `limit` units, with an ellipsis where it is cut.
@(private = "file")
fit_name :: proc(u: ^ui.Ui, name: string, limit: f32) -> string {
	if text_width(u, name, SMALL_FONT) <= limit do return name
	for n := len(name) - 1; n > 0; n -= 1 {
		cut := fmt.tprintf("%s…", name[:n])
		if text_width(u, cut, SMALL_FONT) <= limit do return cut
	}
	return "…"
}

// A flag-carry time: minutes and seconds past a minute, else whole seconds.
@(private = "file")
carry_time :: proc(ticks: i32) -> string {
	s := ticks / sim.TICK_RATE
	return fmt.tprintf("%d:%02d", s / 60, s % 60) if s >= 60 else fmt.tprintf("%ds", s)
}
