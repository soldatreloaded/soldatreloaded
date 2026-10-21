package hud

import "core:math"

import rl "vendor:raylib"

import "../ui"

// My teammates' names, when they are out of the view (interface.player_names): held at
// the view's edge, toward where they are, fainter the further; with interface.team_names
// always, by them when they are in it; and spectating, everyone's, by them. The
// original's RenderPlayerNames.

@(private = "file") DEAD_COLOR :: rl.Color{0x98, 0x33, 0x33, 0xFF} // OUTOFSCREENDEAD_MESSAGE_COLOR

draw_names :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	mine := &data.players[data.me]
	watching := mine.team == .Spectator
	only_out := !data.team_names && !watching
	by := shrink_of(u, data)
	for &player, id in data.players {
		if !player.active || player.team == .Spectator do continue
		if !watching && (id == int(data.me) || player.team != mine.team) do continue
		// out of view, its top at the head's; in view, its middle a little under it
		at := in_view(data, player.head) + {0, 5 if only_out else 20}
		if only_out && at.x >= 0 && at.x <= u.width && at.y >= 0 && at.y <= ui.VIEW_HEIGHT do continue

		w, h := text_width(u, player.name, WEAPONS_FONT), line_height(u, WEAPONS_FONT)
		x := max(0, min(u.width - w, at.x - w / 2))
		y := max(0, min(ui.VIEW_HEIGHT - h, at.y - (0 if only_out else h / 2)))
		dx := max(abs(mine.head.x - player.head.x), 1)
		dy := max(abs(mine.head.y - player.head.y), 1)
		alpha := min(255, 50 + int(math.round(100000 / (dx + dy / 2))))
		color := data.carrier_color if player.flag else DEAD_COLOR if player.dead else data.name_color
		z := zoom_around(u, {x + w / 2, y + h / 2}, by) // unscaled, as big as in a 640 by 480 window (zoom.odin)
		write(u, player.name, {x, y}, WEAPONS_FONT, with_alpha(color, alpha))
		zoom_end(z)
	}
}

// Spectating, a bar of each living player's health over its helmet (data.health_bars):
// red to yellow to green as it fills, on a dark ground.
HEALTH_BAR_SIZE :: [2]f32{24, 3}
HEALTH_BAR_RISE :: 14 // its bottom over the helmet, in units: under what is said over the head
@(private = "file") HEALTH_BAR_GROUND :: rl.Color{0, 0, 0, 150}

draw_health_bars :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	if data.players[data.me].team != .Spectator do return
	by := shrink_of(u, data)
	for &player in data.players {
		if !player.active || player.team == .Spectator || player.dead do continue
		ground, filled := health_bar_rects(data, &player)
		z := zoom_around(u, {ground.x + ground.width / 2, ground.y + ground.height}, by) // unscaled, as the names
		fill(u, ground, HEALTH_BAR_GROUND)
		if filled.width > 0 do fill(u, filled, health_bar_color(player.health))
		zoom_end(z)
	}
}

// The bar's ground, a unit round it, and its filled share, from the left, in the view.
health_bar_rects :: proc(data: ^Hud_Data, player: ^Player) -> (ground, filled: rl.Rectangle) {
	at := in_view(data, player.top) - {0, HEALTH_BAR_RISE} // the bar's bottom middle
	size := HEALTH_BAR_SIZE
	filled = {at.x - size.x / 2, at.y - size.y, size.x * clamp(player.health, 0, 1), size.y}
	ground = {at.x - size.x / 2 - 1, at.y - size.y - 1, size.x + 2, size.y + 2}
	return
}

// Red when it is nearly gone, yellow at half, green full.
health_bar_color :: proc(health: f32) -> rl.Color {
	h := clamp(health, 0, 1)
	if h < 0.5 do return {255, u8(255 * h * 2), 0, 255}
	return {u8(255 * (1 - h) * 2), 255, 0, 255}
}

