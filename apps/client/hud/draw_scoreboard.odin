package hud

import sa "core:container/small_array"
import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../ui"

// The scoreboard (the frags menu, F1, and up while a round's scores stand): everyone by
// rank, in their teams, with kills, deaths and captures; the clock; who won. And my
// weapon stats (F2). The original's RenderFragsMenuTexts, RenderEndGameTexts and
// RenderWeaponStatsTexts, over the boxes RenderInterface lays under them.

PLAYER_ROW :: 15 // FRAGSMENU_PLAYER_HEIGHT

Ranks :: sa.Small_Array(sim.MAX_PLAYERS, sim.Soldier_Id)

// Who is in the game, best first, as the original's SortPlayers ranks them: by
// captures, then kills, then the fewer deaths.
rank_players :: proc(data: ^Hud_Data) -> (ranks: Ranks) {
	for &player, id in data.players {
		if player.active do sa.append(&ranks, sim.Soldier_Id(id))
	}
	ids := sa.slice(&ranks)
	for i in 1 ..< len(ids) {
		for j := i; j > 0 && ranked_before(&data.players[ids[j]], &data.players[ids[j - 1]]); j -= 1 {
			ids[j], ids[j - 1] = ids[j - 1], ids[j]
		}
	}
	return
}

@(private = "file")
ranked_before :: proc(a, b: ^Player) -> bool {
	if a.flags != b.flags do return a.flags > b.flags
	if a.kills != b.kills do return a.kills > b.kills
	return a.deaths < b.deaths
}

// The scoreboard's place across the view: in its middle.
@(private = "file")
board_x :: proc(u: ^ui.Ui) -> f32 {
	return math.floor(u.width / 2 - 300) - 25
}

// The groups of rows: each team that has players, in the teams' order. Each group's rows
// start where it says.
@(private = "file")
Group :: struct {
	team:  res.Team,
	count: int,
	top:   f32, // its caption's line, in the board
}

@(private = "file")
groups_of :: proc(data: ^Hud_Data, ranks: []sim.Soldier_Id) -> (groups: sa.Small_Array(len(res.Team), Group)) {
	step, above := f32(0), 0
	for team in ([?]res.Team{.Alpha, .Bravo, .Charlie, .Delta, .Spectator}) {
		count := 0
		for id in ranks do count += int(data.players[id].team == team)
		if count == 0 do continue
		sa.append(&groups, Group{team, count, 50 + step + f32(above * PLAYER_ROW)})
		step += 20
		above += count
	}
	return
}

@(private = "file")
group_of :: proc(groups: []Group, team: res.Team) -> int {
	for g, i in groups {
		if g.team == team do return i
	}
	return 0
}

// The box under the scoreboard, and each row's marks: the dead, me, the flag carried,
// the bot. Returns where the box's bottom is.
draw_scoreboard_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) -> f32 {
	x := board_x(u)
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	grouped := groups_of(data, ranks)
	groups := sa.slice(&grouped)
	bottom := 70 + f32((len(ranks) + 1) * PLAYER_ROW) + f32(len(groups) * 15)
	box(u, art, {25 + x, 5, 590, bottom})
	if bottom > ui.VIEW_HEIGHT - 80 { // more than fits: the scroll hint blinks
		blink := u8(abs(math.sin(5.1 * data.seconds)) * 255)
		picture(u, art.pictures[.Scroll], {580 + x, ui.VIEW_HEIGHT / 2}, {255, 255, 255, blink})
	}

	mark := rl.Color{255, 255, 255, STATUS_ALPHA}
	placed: [len(res.Team)]int
	for id in ranks {
		player := &data.players[id]
		g := group_of(groups, player.team)
		row := groups[g].top + 20 + f32(placed[g] * PLAYER_ROW)
		placed[g] += 1
		if player.dead do picture(u, art.pictures[.Dead_Dot], {align(u, 32 + x), align(u, row + 1)}, mark)
		if id == data.me do picture(u, art.pictures[.Small_Dot], {align(u, 31 + x), align(u, row + 1)}, mark)
		if player.flags > 0 do picture(u, art.pictures[.Flag], {align(u, 337 + x), align(u, row - 1)}, mark)
		if player.bot do picture(u, art.pictures[.Bot], {align(u, 534 + x), align(u, row)}, mark)
		// the mute sign, faint until it is muted, so every row shows it can be clicked to
		// mute; never on my own row, which can't be muted. None at all with the setting off
		if data.scoreboard_mute && id != data.me do picture(u, art.pictures[.Mute], mute_sign_at(u, x, row), {255, 255, 255, u8(STATUS_ALPHA) if player.muted else MUTE_HINT_ALPHA})
		// the line's quality, red to green: the original's by its ConnectionQuality, here by the
		// ping, whole up to 50 ms and gone by 350
		quality := clamp(100 - (player.ping - 50) / 3, 0, 100)
		connection := rl.Color{u8(255 * (100 - quality) / 100), u8(255 * quality / 100), 0, STATUS_ALPHA}
		picture(u, art.pictures[.Connection], {align(u, 520 + x), align(u, row + 2)}, connection)
	}
	// each team's caption shows the sign too, faint until the team is muted: its caption is
	// clicked to mute the whole team
	if data.scoreboard_mute {
		for g in groups {
			picture(u, art.pictures[.Mute], mute_sign_at(u, x, g.top), {255, 255, 255, u8(STATUS_ALPHA) if data.team_muted[g.team] else MUTE_HINT_ALPHA})
		}
	}
	return bottom
}

MUTE_HINT_ALPHA :: 55 // the mute sign while not muted: faint, to show it can be clicked to mute

// Where a row's mute sign sits, the row's text at `top`: drawn there, and clicked there.
@(private = "file")
mute_sign_at :: proc(u: ^ui.Ui, x, top: f32) -> [2]f32 {
	return {align(u, 246 + x), align(u, top - 1)}
}

@(private = "file") HEADING_COLOR :: rl.Color{255, 255, 230, 255}
@(private = "file") HOST_COLOR :: rl.Color{233, 180, 12, 255}
CLOCK_COLOR :: rl.Color{170, 160, 200, 230}
@(private = "file") COUNT_COLOR :: rl.Color{200, 190, 180, 240}

// Each team's kills by its caption, in its shirt's colour.
@(private = "file", rodata)
TOTAL_COLORS := #partial [res.Team]rl.Color {
	.Alpha   = {0xD2, 0x0F, 0x05, 0xDD},
	.Bravo   = {0x15, 0x1F, 0xD9, 0xDD},
	.Charlie = {0xD2, 0xD2, 0x05, 0xDD},
	.Delta   = {0x05, 0xD2, 0x05, 0xDD},
}

// The scoreboard's texts: the columns, the server and its clock, how many play, the
// players in their groups, and over the bottom (at `bottom`) the demo being recorded.
draw_scoreboard :: proc(u: ^ui.Ui, data: ^Hud_Data, bottom: f32) {
	x := board_x(u)
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	grouped := groups_of(data, ranks)
	groups := sa.slice(&grouped)

	for g in groups do line(u, {x + 35, g.top + 15}, 565, group_color(g.team))
	write(u, text(.Board_Points), {x + 280, 40}, MENU_FONT, HEADING_COLOR)
	write(u, text(.Board_Deaths), {x + 390, 40}, MENU_FONT, HEADING_COLOR)
	write(u, text(.Board_Ping), {x + 530, 40}, MENU_FONT, HEADING_COLOR)
	write(u, data.hostname, {x + 30, 15}, SMALL_FONT, HOST_COLOR)
	write(u, text(.Board_Time, fmt.tprintf("%02d:%02d", data.time_left / 60, data.time_left % 60)), {x + 485, 15}, SMALL_FONT, CLOCK_COLOR)
	write(u, data.time_of_day, {x + 485, 30}, SMALL_FONT, CLOCK_COLOR)
	write(u, text(.Board_Players), {x + 330, 15}, SMALL_FONT, COUNT_COLOR)
	for team, i in ([2]res.Team{.Alpha, .Bravo}) {
		count := 0
		for id in ranks do count += int(data.players[id].team == team)
		color := rl.Color{233, 0, 0, 240} if team == .Alpha else rl.Color{0, 0, 233, 240}
		write(u, fmt.tprintf("%d", count), {x + 440, 10 + 10 * f32(i)}, SMALL_FONT, color)
	}

	placed: [len(res.Team)]int
	totals: [len(res.Team)]i32
	for id in ranks {
		player := &data.players[id]
		g := group_of(groups, player.team)
		y := groups[g].top + 20 + f32(placed[g] * PLAYER_ROW)
		placed[g] += 1
		totals[g] += player.kills
		color := rl.Color{220, 50, 200, 113} if player.team == .Spectator else with_alpha(player.shirt, 255)
		// the small font the counts above left set: the original's rows set none of their own
		write(u, player.name, {x + 44, y}, SMALL_FONT, color)
		write(u, fmt.tprintf("%d", player.kills), {x + 284, y}, SMALL_FONT, color)
		write(u, fmt.tprintf("%d", player.deaths), {x + 394, y}, SMALL_FONT, color)
		if player.flags > 0 do write(u, fmt.tprintf("x%d", player.flags), {x + 348, y}, SMALL_FONT, color)
		if !player.bot do write(u, fmt.tprintf("%d", player.ping), {x + 534, y}, SMALL_FONT, color)
	}

	for g, i in groups {
		write(u, team_name(g.team), {x + 35, g.top}, SMALL_FONT, group_color(g.team))
		if g.team >= .Alpha && g.team <= .Delta {
			write(u, fmt.tprintf("%d", totals[i]), {x + 284, g.top + 3}, SMALL_FONT, TOTAL_COLORS[g.team])
		}
	}
	// the demo being recorded, its name blinking above the board's bottom (the original's)
	if data.recording && data.demo_name != "" {
		blink := u8(abs(math.sin(5.1 * data.seconds / 2)) * 255)
		write(u, data.demo_name, {x + 280, bottom - 10}, SMALL_FONT, {0, 128, 0, blink})
	}
}

// The round over, at the board's bottom: the team that won, or a tie.
draw_round_end :: proc(u: ^ui.Ui, data: ^Hud_Data, bottom: f32) {
	x := board_x(u)
	alpha, bravo := data.captures[.Alpha], data.captures[.Bravo]
	switch {
	case alpha == bravo: write(u, text(.Tie), {x + 137, bottom}, MENU_FONT, {245, 245, 245, 255}, vertical = .Bottom)
	case alpha > bravo:  write(u, text(.Alpha_Wins), {x + 50, bottom}, MENU_FONT, {210, 15, 5, 255}, vertical = .Bottom)
	case:                write(u, text(.Bravo_Wins), {x + 50, bottom}, MENU_FONT, {5, 15, 205, 255}, vertical = .Bottom)
	}
}

// "Game paused", along the board's top.
draw_paused :: proc(u: ^ui.Ui) {
	write(u, text(.Game_Paused), {board_x(u) + 197, 24}, MENU_FONT, {185, 250, 138, 255})
}

// My weapon stats: for each weapon I have fired, its shots, hits, accuracy and kills.
draw_stats :: proc(u: ^ui.Ui, art: ^Art, feed: ^Feed, data: ^Hud_Data, scoreboard: bool) {
	x := board_x(u)
	fired := 0
	for stat in feed.stats do fired += int(stat.shots > 0)
	if !scoreboard do box(u, art, {25 + x, 5, 590, f32(fired * 20 + 85)})

	write(u, "% = Accuracy", {x + 465, 15}, SMALL_FONT, CLOCK_COLOR)
	write(u, "HS = Headshots", {x + 465, 25}, SMALL_FONT, CLOCK_COLOR)
	write(u, "Weapon:", {x + 70, 40}, MENU_FONT, HEADING_COLOR)
	write(u, " %", {x + 240, 40}, MENU_FONT, HEADING_COLOR)
	write(u, "Shots:", {x + 290, 40}, MENU_FONT, HEADING_COLOR)
	write(u, "Hits:", {x + 390, 40}, MENU_FONT, HEADING_COLOR)
	write(u, "Kills (HS):", {x + 470, 40}, MENU_FONT, HEADING_COLOR)
	row := 0
	for stat, weapon in feed.stats {
		if stat.shots <= 0 do continue
		row += 1
		y := f32(row * 20 + 50)
		if !scoreboard do picture(u, art.guns[weapon], {30 + x, y}, {255, 255, 255, 255})
		white := rl.Color{255, 255, 255, 255}
		write(u, data.weapon_names[weapon], {x + 90, y}, SMALL_FONT, white)
		write(u, fmt.tprintf("%d%%", int(math.round(f32(stat.hits) * 100 / f32(stat.shots)))), {x + 245, y}, SMALL_FONT, white)
		write(u, fmt.tprintf("%d", stat.shots), {x + 295, y}, SMALL_FONT, white)
		write(u, fmt.tprintf("%d", stat.hits), {x + 395, y}, SMALL_FONT, white)
		write(u, fmt.tprintf("%d (%d)", stat.kills, stat.headshots), {x + 475, y}, SMALL_FONT, white)
	}
	write(u, "(Updated every 10 seconds)", {x + 230, f32((row + 1) * 20 + 50)}, SMALL_FONT, {255, 255, 230, 100})
}

// A group's caption and line: its team's colour; the spectators' purple.
@(private = "file")
group_color :: proc(team: res.Team) -> rl.Color {
	return {129, 52, 118, 255} if team == .Spectator else team_text_color(team)
}

// What a click on the open scoreboard asks the match to mute: a player, by their row, or
// a whole team, by its caption.
Mute_Target :: union {
	Mute_Player,
	Mute_Team,
}
Mute_Player :: struct {
	id: sim.Soldier_Id,
}
Mute_Team :: struct {
	team: res.Team,
}

// A left-click on the open scoreboard, as a mute request on the Hud: whichever mute sign
// is under the pointer (scoreboard_at).
@(private = "package")
scoreboard_mute_input :: proc(hud: ^Hud, u: ^ui.Ui, data: ^Hud_Data) {
	if !rl.IsMouseButtonPressed(.LEFT) do return
	if target, ok := scoreboard_at(u, data, hud.art.pictures[.Mute].size); ok do hud.mute = target
}

// Which mute sign is under the pointer on the scoreboard: a team's by its caption, or a
// player's by their row (never my own); none if the pointer is off the signs. The signs
// are placed as draw_scoreboard_box places them, `sign` big.
@(private = "file")
scoreboard_at :: proc(u: ^ui.Ui, data: ^Hud_Data, sign: [2]f32) -> (Mute_Target, bool) {
	at := data.cursor
	x := board_x(u)
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	grouped := groups_of(data, ranks)
	groups := sa.slice(&grouped)

	// the team captions, each on its own line
	for g in groups {
		if sign_hit(at, mute_sign_at(u, x, g.top), sign) do return Mute_Team{g.team}, true
	}
	// the player rows
	placed: [len(res.Team)]int
	for id in ranks {
		player := &data.players[id]
		gi := group_of(groups, player.team)
		row := groups[gi].top + 20 + f32(placed[gi] * PLAYER_ROW)
		placed[gi] += 1
		if id == data.me do continue // my own line is not muted
		if sign_hit(at, mute_sign_at(u, x, row), sign) do return Mute_Player{id}, true
	}
	return nil, false
}

// Whether `at` is on a mute sign with its top-left at `pos`, `size` big, give or take a
// couple of points so a small sign is easy to hit.
@(private = "file")
sign_hit :: proc(at, pos, size: [2]f32) -> bool {
	PAD :: 2
	return at.x >= pos.x - PAD && at.x <= pos.x + size.x + PAD && at.y >= pos.y - PAD && at.y <= pos.y + size.y + PAD
}
