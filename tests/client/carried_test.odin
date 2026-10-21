package client_test

import "core:testing"
import sim "../../core/game"
import res "../../core/resources"
import "../../core/utils"
import draw "../../apps/client/draw"

// What hangs on a soldier is drawn on the soldier as drawn, not as the game has it: a
// carried flag is pinned to point 8, which the airborne clips draw a jump's rise about 5
// units lower than the game's pose, and online a correction still easing in moves the
// soldier drawn but not the flag. The frame's shift for point 8 takes the flag from the
// game's point onto the drawn one.
@(test)
carried_on_the_drawn_soldier :: proc(t: ^testing.T) {
	g := new(sim.Game); defer free(g)
	testing.expect(t, sim.game_init(g, sim.DEFAULT_GAME_SETTINGS, authority = true))
	defer sim.game_destroy(g)
	testing.expect(t, sim.game_start_round(g, "ctf_Ash", seed = 1))
	sim.soldier_place(g, 0, .Alpha, remote = false)
	s := &g.world.soldiers[0]
	// rising from a jump, standing, no jets: the fluid Jump_Rise clip drawn
	s.body.on_ground, s.body.velocity, s.body.direction = false, {0, -4}, 1
	s.controls.buttons, s.controls.stance, s.controls.aim = {}, .Stand, s.body.pos + {100, 0}
	s.pose.legs.id, s.pose.legs.frame = .Jump, 15
	s.pose.body.id, s.pose.body.frame = .Stand, 1

	art := new(draw.Art); defer free(art)
	art.air_animations = res.air_animations_load(sim.DATA_DIR)
	defer free(art.air_animations)
	art.air_tuning = res.AIR_TUNING
	before: draw.Snapshot
	draw.snapshot_take(&before, &g.world)
	offsets: [sim.MAX_PLAYERS]utils.Vec2
	offsets[0] = {3, -2} // a correction still easing in
	frame: draw.Frame
	draw.frame_build(&frame, &before, g, 1, &offsets, art)

	figure := &frame.figures[0]
	game_flag_point := sim.soldier_pose(g.resources.animations, s, s.body.pos)[8 - 1]
	pinned := game_flag_point + figure.shift[8 - 1]
	testing.expectf(t, utils.length(pinned - figure.points[8 - 1]) < 1e-3, "the flag on the drawn point 8: %v, drawn %v", pinned, figure.points[8 - 1])
	testing.expectf(t, utils.length(figure.shift[8 - 1] - offsets[0]) > 3, "the rise drawn apart from the game's pose (%v), so this tells", figure.shift[8 - 1] - offsets[0])
}

// A held gun's magazine is drawn while it has rounds; empty, until the reload takes it
// out, and again once the new one is in (the count running down from the reload time);
// the minigun's box until 65 ticks are left of its reload.
@(test)
held_magazine_shown :: proc(t: ^testing.T) {
	g := new(sim.Game); defer free(g)
	testing.expect(t, sim.game_init(g, sim.DEFAULT_GAME_SETTINGS, authority = true))
	defer sim.game_destroy(g)
	ak := &g.resources.weapons[.AK74]
	testing.expect(t, ak.clip_in_time < ak.clip_out_time, "the AK's clip comes out before the new one goes in")
	shown :: draw.held_clip_shown
	testing.expect(t, shown({weapon = .AK74, ammo = 12}, ak), "rounds in it")
	testing.expect(t, shown({weapon = .AK74, ammo = 0, reload_count = ak.clip_out_time + 1}, ak), "empty, its reload not at the clip yet")
	testing.expect(t, !shown({weapon = .AK74, ammo = 0, reload_count = (ak.clip_in_time + ak.clip_out_time) / 2}, ak), "out, mid-reload")
	testing.expect(t, shown({weapon = .AK74, ammo = 0, reload_count = ak.clip_in_time - 1}, ak), "the new one in")
	minigun := &g.resources.weapons[.Minigun]
	testing.expect(t, shown({weapon = .Minigun, ammo = 0, reload_count = draw.MINIGUN_BOX_SHOWN - 1}, minigun), "the box, late in the reload")
	testing.expect(t, !shown({weapon = .Minigun, ammo = 0, reload_count = draw.MINIGUN_BOX_SHOWN}, minigun), "no box early in it")
}
