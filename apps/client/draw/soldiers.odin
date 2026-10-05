package draw

import sim "../../../core/game"
import "../../../core/utils"

// The soldiers, living and dead, each its gostek where the frame shows it. From the C
// client's render/render.c.

@(private = "package")
draw_soldiers :: proc(art: ^Art, game: ^sim.Game, frame: ^Frame, grenade_color: Maybe(utils.Rgba)) {
	for &soldier, id in game.world.soldiers {
		if !soldier.active || soldier.team == .Spectator do continue
		draw_gostek(&art.gostek, &soldier, &frame.figures[id], shirt_worn(&soldier), grenade_color)
	}
}
