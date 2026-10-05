package draw

import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"

// The view: where it looks, and how much it shows. It is always VIEW_HEIGHT units tall,
// as the original's is, so every player sees as much of the world whatever their
// window; the width follows the window. From the C client's render/camera.c.

VIEW_HEIGHT :: 480
CAMERA_SPEED :: 0.14 // the share of the distance to the target closed per tick (CAMSPEED)

Camera :: struct {
	pos:  [2]f32, // the middle of the view
	view: [2]f32, // the size of the view, in world units
}

// The view's size for the window's, as it is now.
camera_fit :: proc(camera: ^Camera) {
	camera.view = {VIEW_HEIGHT * f32(rl.GetScreenWidth()) / f32(rl.GetScreenHeight()), VIEW_HEIGHT}
}

// The camera chases `target` and leads toward the cursor (in view units) by
// `aim_distance` (the followed soldier's: a scope shortens it, and the lead grows), as
// the original does, over `dt` seconds so it feels the same at any frame rate.
camera_follow :: proc(camera: ^Camera, target, cursor: [2]f32, aim_distance: f32, dt: f32) {
	aim_distance := aim_distance if aim_distance >= 1 else sim.DEFAULT_AIM_DISTANCE
	half := camera.view / 2
	offset := [2]f32{clamp(cursor.x - half.x, -half.x, half.x), clamp(cursor.y - half.y, -half.y, half.y)}
	// UpdateFrame.pas: the lead is the offset over the aim distance, with the original's
	// wide-screen term, and its correction for a scoped aim distance on a wide view
	width := camera.view.x
	factor := (2 * 640 / width - 1) + (width - 640) / width * (sim.DEFAULT_AIM_DISTANCE - aim_distance) / 6.8
	ticks := dt * sim.TICK_RATE
	k := 1 - math.pow(1 - f32(CAMERA_SPEED), ticks)
	camera.pos.x += (target.x - camera.pos.x) * k + offset.x / aim_distance * factor * ticks
	camera.pos.y += (target.y - camera.pos.y) * k + offset.y / aim_distance * ticks
}

// A point in the view, in view units from its top-left, in the world.
camera_to_world :: proc(camera: Camera, point: [2]f32) -> [2]f32 {
	return camera.pos - camera.view / 2 + point
}

// The camera as raylib's, for drawing the world into the window.
@(private = "package")
camera_raylib :: proc(camera: Camera) -> rl.Camera2D {
	screen := [2]f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	return {offset = screen / 2, target = camera.pos, zoom = screen.y / VIEW_HEIGHT}
}
