package draw

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"

// The world drawn between its last two ticks, so it moves smoothly at any frame rate. A
// frame is `alpha` of the way from the tick before (a Snapshot the match keeps) to the
// latest (the world as it is): the soldiers' bodies and poses blend, and the corpses'
// points; online, the others are drawn where the line's corrections are still easing to
// (the stream's blend), so a correction glides in rather than snapping; the bullets and the things blend between their own last two positions, which
// the simulation keeps; the sparks between theirs. Everything else a frame draws is the
// latest tick's. I am drawn as everyone is, and the camera follows where I am drawn.
// From the C client's render/render_state.c.

// The part of a tick the next frames blend from.
Snapshot :: struct {
	soldiers: [sim.MAX_PLAYERS]sim.Soldier,
	corpses:  [sim.MAX_PLAYERS]sim.Corpse,
}

// The gostek's 24 points: the pose's 20, then the neck (21) with the chain's pendant
// swinging below it (22), and the head's top (23) with the dreadlocks' end below it (24).
Points :: [sim.CORPSE_POINTS]utils.Vec2

// A soldier where a frame shows it.
Figure :: struct {
	pos:    utils.Vec2, // its body
	points: Points,
	corpse: bool,       // dead with its body started: the points are the corpse's
	// each point as drawn less the game's, which what hangs on the soldier (a carried flag,
	// a parachute) is pinned to: the airborne clips' and the fluid recoil's difference, and
	// online the correction still easing in. None for a corpse, drawn as the game has it.
	shift:  sim.Joints,
	clip:   bool, // the gun in its hands drawn with its magazine (held_clip_shown)
}

Frame :: struct {
	alpha:      f32, // how far the world is drawn from the tick before to the latest, 0 to 1
	tick_alpha: f32, // how far the clock is into the next tick: alpha but while the round stands
	figures:    [sim.MAX_PLAYERS]Figure,
}

// Before each tick: the world as the frames after it blend from.
snapshot_take :: proc(snapshot: ^Snapshot, world: ^sim.World) {
	snapshot.soldiers = world.soldiers
	snapshot.corpses = world.corpses
}

// The frame `alpha` of the way from `before` to the game as it is now, each soldier moved
// by its `offsets`, if any: what a correction still has to show of it. While the round
// stands (paused, or over) the world is drawn as its latest tick, as the original's
// InterpolateState does when paused: the bullets and the things keep the last positions
// of the step that froze, which would otherwise be run through again every tick.
frame_build :: proc(frame: ^Frame, before: ^Snapshot, game: ^sim.Game, alpha: f32, offsets: ^[sim.MAX_PLAYERS]utils.Vec2 = nil, art: ^Art = nil) {
	frame.tick_alpha = clamp(alpha, 0, 1)
	frame.alpha = 1 if sim.round_standing(&game.round) else frame.tick_alpha
	world := &game.world
	for id in 0 ..< sim.MAX_PLAYERS {
		to := &world.soldiers[id]
		offset := offsets[id] if offsets != nil else {}
		frame.figures[id] = figure_between(game.resources.animations, &before.soldiers[id], to, &before.corpses[id], &world.corpses[id], frame.alpha, offset, art, world.tick, id)
		frame.figures[id].clip = held_clip_shown(to.arsenal.primary, &game.resources.weapons[to.arsenal.primary.weapon])
	}
}

// A soldier's shift as its tick is drawn (Figure.shift, without a frame's blend between
// ticks): for what is made off it at the tick, a spark off its feet or its gun. None for
// the dead, and only the offset without the art's airborne clips.
@(private = "package")
soldier_shift :: proc(art: ^Art, game: ^sim.Game, id: int, offset: utils.Vec2) -> (shift: sim.Joints) {
	soldier := &game.world.soldiers[id]
	if !soldier.active || soldier.vitals.dead do return
	animations := game.resources.animations
	base := sim.soldier_pose(animations, soldier, soldier.body.pos)
	drawn := base
	if art != nil do drawn = visual_soldier_pose(animations, art.air_animations, soldier, soldier.body.pos, game.world.tick, &art.air_transitions[id], &art.air_tuning, art.air_styles)
	for &s, i in shift do s = drawn[i] - base[i] + offset
	return
}

// The game's point `pos` of soldier `id`'s, `joints`, moved as the soldier is drawn: by
// the shift of its point nearest it. For where the game says a spark comes off it.
@(private = "package")
shifted :: proc(shift: ^sim.Joints, joints: ^sim.Joints, pos: utils.Vec2) -> utils.Vec2 {
	nearest, best := 0, max(f32)
	for joint, i in joints {
		if d := utils.length(joint - pos); d < best do nearest, best = i, d
	}
	return pos + shift[nearest]
}

// `t` of the way from `a` to `b`.
@(private = "package")
between :: proc(a, b: utils.Vec2, t: f32) -> utils.Vec2 {
	return a + (b - a) * t
}

// The pose blends whatever the animations did between the two ticks, as the original
// lerps every skeleton point from its last each frame; but a new life is a jump, not a
// journey, and the step from living to dead shows the latest tick's alone. A dead
// soldier is its corpse once that has started; until then it holds its last pose.
@(private = "file")
figure_between :: proc(animations: ^res.Animations, from, to: ^sim.Soldier, corpse_from, corpse_to: ^sim.Corpse, alpha: f32, offset: utils.Vec2, art: ^Art, tick: u32, id: int) -> (figure: Figure) {
	if !to.active do return
	continuous := from.active && from.vitals.life == to.vitals.life
	figure.pos = (between(from.body.pos, to.body.pos, alpha) if continuous else to.body.pos) + offset

	figure.corpse = to.vitals.dead && corpse_to.active
	if figure.corpse {
		for &point, k in figure.points {
			point = between(corpse_from.points[k], corpse_to.points[k], alpha) if corpse_from.active else corpse_to.points[k]
		}
		return
	}

	// the airborne clips over the game's pose, where there is art to have them; without,
	// the game's pose alone
	clips: ^res.Air_Animations
	transition: ^Air_Transition
	tuning: ^res.Air_Tuning
	styles: res.Air_Styles
	if art != nil do clips, transition, tuning, styles = art.air_animations, &art.air_transitions[id], &art.air_tuning, art.air_styles
	base := sim.soldier_pose(animations, to, figure.pos)
	joints := visual_soldier_pose(animations, clips, to, figure.pos, tick, transition, tuning, styles)
	if continuous && from.vitals.dead == to.vitals.dead {
		last := visual_soldier_pose(animations, clips, from, figure.pos, tick-1 if tick>0 else 0, transition, tuning, styles)
		last_base := sim.soldier_pose(animations, from, figure.pos)
		for &point, i in base do point = between(last_base[i], point, alpha)
		for &joint, i in joints {
			joint = between(last[i], joint, alpha)
		}
	}
	copy(figure.points[:], joints[:])
	for &s, i in figure.shift do s = joints[i] - base[i] + offset // `base` is at figure.pos, the offset in it
	for k in 0 ..< len(to.pose.swing) {
		swing := between(from.pose.swing[k], to.pose.swing[k], alpha) if continuous else to.pose.swing[k]
		figure.points[len(joints) + k] = swing + offset
		figure.points[len(joints) + k] += joints[8]-base[8]
	}
	return
}
