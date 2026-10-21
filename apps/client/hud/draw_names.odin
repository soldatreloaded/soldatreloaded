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

// The winners' names under their gosteks on the end screen's stage (data.stage): each
// centred under the feet, in the names' lettering and colour, as a name by a player.
draw_stage_names :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	h := line_height(u, WEAPONS_FONT)
	for i in 0 ..< data.stage.count {
		player := &data.players[data.stage.ids[i]]
		if !player.active do continue
		feet := data.stage.feet[i]
		w := text_width(u, player.name, WEAPONS_FONT)
		write(u, player.name, {feet.x - w / 2, feet.y + (30 - h) / 2}, WEAPONS_FONT, data.name_color)
	}
}
