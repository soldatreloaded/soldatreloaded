package hud

import "core:math"

import rl "vendor:raylib"

import "../ui"

// My teammates' names, when they are out of the view (interface.player_names): held at
// the view's edge, toward where they are, fainter the further; with interface.team_names
// always, by them when they are in it. The original's RenderPlayerNames; spectating,
// everyone's, by them, comes with spectating.

@(private = "file") NAME_COLOR :: rl.Color{0x99, 0xDF, 0x99, 0xFF} // OUTOFSCREEN_MESSAGE_COLOR
@(private = "file") CARRIER_COLOR :: rl.Color{0xDC, 0xDC, 0x33, 0xFF} // OUTOFSCREENFLAG_MESSAGE_COLOR
@(private = "file") DEAD_COLOR :: rl.Color{0x98, 0x33, 0x33, 0xFF} // OUTOFSCREENDEAD_MESSAGE_COLOR

draw_names :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	mine := &data.players[data.me]
	only_out := !data.team_names
	for &player, id in data.players {
		if !player.active || id == int(data.me) || player.team != mine.team do continue
		// out of view, its top at the head's; in view, its middle a little under it
		at := in_view(data, player.head) + {0, 5 if only_out else 20}
		if only_out && at.x >= 0 && at.x <= u.width && at.y >= 0 && at.y <= ui.VIEW_HEIGHT do continue

		w, h := text_width(u, player.name, WEAPONS_FONT), line_height(u, WEAPONS_FONT)
		x := max(0, min(u.width - w, at.x - w / 2))
		y := max(0, min(ui.VIEW_HEIGHT - h, at.y - (0 if only_out else h / 2)))
		dx := max(abs(mine.head.x - player.head.x), 1)
		dy := max(abs(mine.head.y - player.head.y), 1)
		alpha := min(255, 50 + int(math.round(100000 / (dx + dy / 2))))
		color := CARRIER_COLOR if player.flag else DEAD_COLOR if player.dead else NAME_COLOR
		write(u, player.name, {x, y}, WEAPONS_FONT, with_alpha(color, alpha))
	}
}
