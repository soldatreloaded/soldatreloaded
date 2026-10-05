package hud

import rl "vendor:raylib"

import res "../../../core/resources"
import "../draw"
import "../ui"

// The minimap in the top middle (ui_minimap): the map in small (draw.Minimap), with my
// side on it, a dot each, mine white and a flag carrier's yellow. The original's
// "Minimap".

MINIMAP_AT :: [2]f32{285, 5} // ui_minimap_posx and posy, not anchored across
MINIMAP_ALPHA :: 230

draw_minimap :: proc(u: ^ui.Ui, art: ^Art, minimap: ^draw.Minimap, data: ^Hud_Data) {
	if minimap.image.texture.id == 0 do return
	picture(
		u,
		{image = minimap.image, size = minimap.size},
		{align(u, MINIMAP_AT.x), align(u, MINIMAP_AT.y)},
		{255, 255, 255, u8(STATUS_ALPHA * 0.85)},
	)

	mine := &data.players[data.me]
	for &player, id in data.players {
		if !player.active || player.team == .Spectator || player.team != mine.team do continue
		scale: f32 = 0.65
		color := with_alpha({} if player.dead else minimap_color(player.team), MINIMAP_ALPHA) // the dead's black
		switch {
		case player.flag:
			scale, color = 1, {0xFF, 0xFF, 0x00, MINIMAP_ALPHA}
		case id == int(data.me):
			scale, color = 0.8, {255, 255, 255, MINIMAP_ALPHA}
		}
		dot := art.pictures[.Small_Dot]
		at := MINIMAP_AT + draw.minimap_point(minimap, player.head) - scale * dot.size / 2
		picture(u, dot, {align(u, at.x), align(u, at.y)}, color, {scale, scale})
	}
}

// A teammate's dot, alive.
@(private = "file")
minimap_color :: proc(team: res.Team) -> rl.Color {
	#partial switch team {
	case .Alpha:   return {0xFF, 0x00, 0x00, 255}
	case .Bravo:   return {0x13, 0x13, 0xFF, 255}
	case .Charlie: return {0xFF, 0xFF, 0x00, 255}
	case .Delta:   return {0x00, 0xFF, 0x00, 255}
	}
	return {}
}
