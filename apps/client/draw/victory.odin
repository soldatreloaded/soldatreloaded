package draw

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"

// The winning team's curtain call at the end of a round: their gosteks side by side on a
// stage along the bottom of the screen, standing on a strip of the map's own ground
// texture, cheering the dab into the yeah into the dab, cycled at the game's own speed
// with a breath between. Drawn in window pixels over the frozen world, each soldier in
// its real style and unarmed, whatever the draw-soldiers setting says for the game. The
// rich stats fill the rest of the screen (the HUD's end scoreboard). From nothing in the
// C client; the original just froze on the field.

VICTORY_GAP :: 22          // ticks the cheer holds between the dab and the yeah, a little breath
VICTORY_FILL :: f32(0.72)  // of the stage's height a gostek stands

// The stage along the bottom third of `area`: the winners' gosteks on a band of ground.
// `seconds` is the frame's clock, which the cheer plays by so the row stays in step.
draw_victory :: proc(art: ^Art, game: ^sim.Game, area: rl.Rectangle, seconds: f64) {
	ended, is_ended := game.round.phase.(sim.Ended)
	if !is_ended || ended.winner == res.Team.None do return
	animations := game.resources.animations
	if animations == nil do return

	winners: [sim.MAX_PLAYERS]sim.Soldier_Id
	n := 0
	for &s, id in game.world.soldiers {
		if s.active && !s.vitals.dead && s.team == ended.winner && s.team != .Spectator {
			winners[n] = sim.Soldier_Id(id)
			n += 1
		}
	}

	stage_h := area.height / 3
	stage_y := area.y + area.height - stage_h
	rl.DrawRectangleRec({area.x, stage_y, area.width, stage_h}, {10, 12, 16, 150}) // the stage, dimmed
	band_h := stage_h * 0.24
	band_y := stage_y + stage_h - band_h
	draw_ground(art, {area.x, band_y, area.width, band_h})
	rl.DrawRectangleRec({area.x, band_y, area.width, 2}, {255, 255, 255, 45}) // the lip of the ground, catching light
	if n == 0 do return

	scale := stage_h * VICTORY_FILL / 52 // a gostek is about 52 units tall
	slot := area.width / f32(n)
	for i in 0 ..< n {
		s := game.world.soldiers[winners[i]]
		victory_pose(animations, &s, seconds)
		figure := victory_figure(animations, &game.resources.skeletons.gostek, &s)
		at := rl.Vector2{area.x + slot * (f32(i) + 0.5) - 2 * scale, band_y + 2}
		hair_player: ^Poa_Hair_Player
		if id := int(winners[i]); id < len(art.gostek.poa.players) do hair_player = &art.gostek.poa.players[id]
		rl.BeginMode2D({offset = at, zoom = scale})
		rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
		rlgl.DisableBackfaceCulling() // a mirrored sprite faces either way
		draw_gostek(&art.gostek, &s, &figure, shirt_worn(&s), nil, true, false, hair_player)
		rl.EndBlendMode()
		rlgl.EnableBackfaceCulling()
		rl.EndMode2D()
	}
}

// The cheer's pose this frame: the dab played out, a breath, the yeah played out, a
// breath, cycled. Every winner reads the same clock, so the row moves as one. The body
// does the cheer; the yeah swings the legs with it, the dab stands.
@(private = "file")
victory_pose :: proc(animations: ^res.Animations, soldier: ^sim.Soldier, seconds: f64) {
	soldier.body.direction = 1
	soldier.controls.aim = {60, -14} // facing out, a touch up, as the menu stands a soldier
	soldier.arsenal.primary.weapon = .Punch   // fists: no weapon drawn
	soldier.arsenal.secondary.weapon = .Punch
	soldier.arsenal.grenades = 0               // and an empty belt
	soldier.antics.helmet = 1                  // headgear on the head

	dab := animations[res.Animation_Id.Dab].frame_count
	yeah := animations[res.Animation_Id.Yeah].frame_count
	cycle := i64(dab + VICTORY_GAP + yeah + VICTORY_GAP)
	pos := i32(i64(seconds * f64(sim.TICK_RATE)) %% max(cycle, 1))
	switch {
	case pos < dab:
		soldier.pose.body = {id = .Dab, frame = pos + 1}
		soldier.pose.legs = {id = .Stand, frame = 1}
	case pos < dab + VICTORY_GAP:
		soldier.pose.body = {id = .Dab, frame = dab} // held on its last, the breath
		soldier.pose.legs = {id = .Stand, frame = 1}
	case pos < dab + VICTORY_GAP + yeah:
		f := pos - dab - VICTORY_GAP + 1
		soldier.pose.body = {id = .Yeah, frame = f}
		soldier.pose.legs = {id = .Yeah, frame = f}
	case:
		soldier.pose.body = {id = .Yeah, frame = yeah}
		soldier.pose.legs = {id = .Yeah, frame = yeah}
	}
}

// The figure for a standing soldier, its feet at the origin: the pose's joints, then the
// chain's and the dreadlocks' points hanging straight down at rest, as `draw_preview`
// settles them. Drawn under `rl.BeginMode2D`, so the origin is the gostek's feet.
@(private = "file")
victory_figure :: proc(animations: ^res.Animations, skeleton: ^res.Skeleton, soldier: ^sim.Soldier) -> (figure: Figure) {
	joints := sim.soldier_pose(animations, soldier, {0, 0})
	copy(figure.points[:], joints[:])
	figure.clip = true // a full gun
	swing := figure.points[len(joints):]
	swing[0] = joints[8]
	swing[2] = joints[8] + (joints[11] - joints[8]) * 50
	for k in 0 ..< 2 {
		rest: f32
		if c := len(skeleton.constraints) - 2 + k; c >= 0 {
			pair := skeleton.constraints[c]
			rest = utils.length(skeleton.points[pair[1]] - skeleton.points[pair[0]])
		}
		swing[2 * k + 1] = swing[2 * k] + {0, rest}
	}
	return
}

// The ground band, the map's own texture laid along it at its own vertical scale and
// repeated across the width; a plain earth where the mod hasn't the map's texture.
@(private = "file")
draw_ground :: proc(art: ^Art, r: rl.Rectangle) {
	if art.map_texture.id == 0 {
		rl.DrawRectangleRec(r, {34, 30, 26, 255})
		return
	}
	th := f32(art.map_texture.height)
	src := rl.Rectangle{0, 0, th * r.width / r.height, th} // repeats across, the texture's own height tall
	rl.DrawTexturePro(art.map_texture, src, r, {0, 0}, 0, {170, 170, 170, 255})
}
