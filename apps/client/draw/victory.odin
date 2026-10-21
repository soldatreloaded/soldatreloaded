package draw

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"

// The end of a round: a curtain fades in over the frozen field and covers it, and along
// the bottom third of the screen the winning team takes a stage, their gosteks side by
// side on a strip of the map's own ground texture, cheering the dab into the yeah into
// the dab, cycled at the game's own speed with a breath between. Drawn in window pixels,
// each soldier in its real style and unarmed, whatever the draw-soldiers setting says
// for the game. The round's figures fill the two thirds above (the HUD's end screen,
// hud/draw_summary.odin), which fades in with the curtain (victory_fade). From nothing
// in the C client; the original just froze on the field.

VICTORY_GAP :: 22          // ticks the cheer holds between the dab and the yeah, a little breath
VICTORY_FILL :: f32(0.72)  // of the stage's height a gostek stands
VICTORY_FADE_TICKS :: 45   // the curtain takes this long to cover the field: three quarters of a second
VICTORY_SPACING :: f32(64) // between the winners on the stage, in a gostek's own units; closer where they don't fit

CURTAIN_TOP :: rl.Color{16, 20, 30, 255}   // night at the top
CURTAIN_BOTTOM :: rl.Color{8, 10, 15, 255} // into near black
STAGE_LIGHT_TIE :: rl.Color{200, 200, 210, 255}

// How far the end screen has come in: 0 while the round plays, 1 once the curtain covers
// the field. By the round's own countdown, so every machine and a demo agree.
victory_fade :: proc(game: ^sim.Game) -> f32 {
	ended, is_ended := game.round.phase.(sim.Ended)
	if !is_ended do return 0
	return clamp(f32(sim.ROUND_END_TICKS - ended.countdown) / VICTORY_FADE_TICKS, 0, 1)
}

// The curtain over `area`, and the stage along its bottom third: the winners' gosteks on
// a band of ground, lit from below in their colour. `seconds` is the frame's clock, which
// the cheer plays by so the row stays in step.
draw_victory :: proc(art: ^Art, game: ^sim.Game, area: rl.Rectangle, seconds: f64) {
	fade := victory_fade(game)
	if fade <= 0 do return
	ended := game.round.phase.(sim.Ended)

	// the curtain, the field going under it
	rl.EndBlendMode()
	top, bottom := faded(CURTAIN_TOP, fade), faded(CURTAIN_BOTTOM, fade)
	rl.DrawRectangleGradientEx(area, top, bottom, bottom, top)

	// the stage: a wash of the winners' colour rising from the ground, the ground itself
	// with a lit lip and a shadow under it
	stage_h := area.height / 3
	stage_y := area.y + area.height - stage_h
	band_h := stage_h * 0.22
	band_y := stage_y + stage_h - band_h
	light := stage_light(ended.winner)
	px := max(1, area.height / 480) // a unit of the view, in pixels
	wash := rl.Rectangle{area.x, stage_y, area.width, stage_h - band_h}
	rl.DrawRectangleGradientEx(wash, faded(light, 0), faded(light, 0.22 * fade), faded(light, 0.22 * fade), faded(light, 0))
	draw_ground(art, {area.x, band_y, area.width, band_h}, fade)
	shadow := rl.Rectangle{area.x, band_y + band_h * 0.45, area.width, band_h * 0.55}
	rl.DrawRectangleGradientEx(shadow, faded(rl.BLACK, 0), faded(rl.BLACK, 0.6 * fade), faded(rl.BLACK, 0.6 * fade), faded(rl.BLACK, 0))
	rl.DrawRectangleRec({area.x, band_y, area.width, px}, faded(light, 0.55 * fade))
	rl.DrawRectangleRec({area.x, band_y + px, area.width, px}, faded(rl.WHITE, 0.18 * fade))

	// the winners step on once the curtain is down: a gostek can't be drawn half there
	if fade < 1 || ended.winner == res.Team.None do return
	animations := game.resources.animations
	if animations == nil do return
	winners: [sim.MAX_PLAYERS]sim.Soldier_Id
	n := 0
	for &s, id in game.world.soldiers {
		if s.active && s.team == ended.winner && s.team != .Spectator {
			winners[n] = sim.Soldier_Id(id)
			n += 1
		}
	}
	if n == 0 do return

	scale := stage_h * VICTORY_FILL / 52 // a gostek is about 52 units tall
	spacing := min(area.width / f32(n), VICTORY_SPACING * scale)
	first := area.x + area.width / 2 - spacing * f32(n - 1) / 2
	for i in 0 ..< n {
		s := game.world.soldiers[winners[i]]
		victory_pose(animations, &s, seconds)
		figure := victory_figure(animations, &game.resources.skeletons.gostek, &s)
		at := rl.Vector2{first + spacing * f32(i) - 2 * scale, band_y + 2}
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

// `color` at `alpha` of its own.
@(private = "file")
faded :: proc(color: rl.Color, alpha: f32) -> rl.Color {
	return {color.r, color.g, color.b, u8(f32(color.a) * clamp(alpha, 0, 1))}
}

// The stage's light: the winners' colour, softened for a dark stage; a cold white for a tie.
@(private = "file")
stage_light :: proc(winner: res.Team) -> rl.Color {
	#partial switch winner {
	case .Alpha:   return {236, 72, 60, 255}
	case .Bravo:   return {72, 124, 255, 255}
	case .Charlie: return {0xDF, 0xDF, 0x53, 0xFF}
	case .Delta:   return {0x53, 0xDF, 0x53, 0xFF}
	}
	return STAGE_LIGHT_TIE
}

// The cheer's pose this frame: the dab played out, a breath, the yeah played out, a
// breath, cycled. Every winner reads the same clock, so the row moves as one. The body
// does the cheer; the yeah swings the legs with it, the dab stands. A winner who died at
// the buzzer stands with the rest.
@(private = "file")
victory_pose :: proc(animations: ^res.Animations, soldier: ^sim.Soldier, seconds: f64) {
	soldier.vitals.dead = false
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
// repeated across the width, `fade` of the way in; a plain earth where the mod hasn't
// the map's texture.
@(private = "file")
draw_ground :: proc(art: ^Art, r: rl.Rectangle, fade: f32) {
	if art.map_texture.id == 0 {
		rl.DrawRectangleRec(r, faded({34, 30, 26, 255}, fade))
		return
	}
	th := f32(art.map_texture.height)
	src := rl.Rectangle{0, 0, th * r.width / r.height, th} // repeats across, the texture's own height tall
	rl.DrawTexturePro(art.map_texture, src, r, {0, 0}, 0, faded({150, 150, 150, 255}, fade))
}
