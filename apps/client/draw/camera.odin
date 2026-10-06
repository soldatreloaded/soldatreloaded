package draw

import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"

// The view: where it looks, and how much it shows. It is always VIEW_HEIGHT units tall,
// as the original's is, so every player sees as much of the world whatever their
// window; the width follows the window's, within the original's limits, with bars past
// them. From the C client's render/camera.c.

VIEW_HEIGHT :: 480
CAMERA_SPEED :: 0.14 // the share of the distance to the target closed per tick (CAMSPEED)

// It moves once a tick, as the original's does, and is drawn `alpha` of the way from
// where the tick before left it (CameraPrev; GameRendering.pas).
Camera :: struct {
	pos:  [2]f32, // the middle of the view, as the last tick left it
	prev: [2]f32, // as the tick before left it
	view: [2]f32, // the size of the view, in world units
}

// The original's limits on the view's shape (MIN_FOV, MAX_FOV): a window wider or
// narrower shows no more, but bars.
MIN_ASPECT :: 1.25
MAX_ASPECT :: 1.78

// Where in the window the view is drawn, in pixels: all of it, or as much as the
// original's limits allow, in the middle, between bars (Client.pas).
view_area :: proc() -> rl.Rectangle {
	w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	area := rl.Rectangle{0, 0, w, h}
	if w > h * MAX_ASPECT {
		area.width = math.ceil(h * MAX_ASPECT)
	} else if w < h * MIN_ASPECT {
		area.height = math.ceil(w / MIN_ASPECT)
	}
	area.x = math.floor((w - area.width) / 2)
	area.y = math.floor((h - area.height) / 2)
	return area
}

// The view's size for the window's, as it is now: VIEW_HEIGHT tall, and as wide as its
// shape, held within the limits, rounded (GameWidth).
camera_fit :: proc(camera: ^Camera) {
	w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	aspect := clamp(w / h, MIN_ASPECT, MAX_ASPECT)
	camera.view = {math.round(aspect * VIEW_HEIGHT), VIEW_HEIGHT}
}

// The camera put at `pos`, with nothing to come from.
camera_place :: proc(camera: ^Camera, pos: [2]f32) {
	camera.pos, camera.prev = pos, pos
}

// The camera as it is drawn, `alpha` of the way from the tick before's to the last's.
camera_between :: proc(camera: Camera, alpha: f32) -> Camera {
	shown := camera
	shown.pos = camera.prev + (camera.pos - camera.prev) * alpha
	return shown
}

// A tick's move (UpdateFrame.pas): the camera closes CAMERA_SPEED of the distance to
// `target` and leads toward the cursor (in view units) by `aim_distance` (the followed
// soldier's: a scope shortens it, and the lead grows), with the original's wide-screen
// term, and its correction for a scoped aim distance on a wide view.
camera_follow :: proc(camera: ^Camera, target, cursor: [2]f32, aim_distance: f32) {
	aim_distance := aim_distance if aim_distance >= 1 else sim.DEFAULT_AIM_DISTANCE
	offset := cursor - camera.view / 2
	width := camera.view.x
	factor := (2 * 640 / width - 1) + (width - 640) / width * (sim.DEFAULT_AIM_DISTANCE - aim_distance) / 6.8
	camera.pos.x += (target.x - camera.pos.x) * CAMERA_SPEED + offset.x / aim_distance * factor
	camera.pos.y += (target.y - camera.pos.y) * CAMERA_SPEED + offset.y / aim_distance
}

// A point in the view, in view units from its top-left, in the world.
camera_to_world :: proc(camera: Camera, point: [2]f32) -> [2]f32 {
	return camera.pos - camera.view / 2 + point
}

// The camera as raylib's, for drawing the world into the view's area of the window.
@(private = "package")
camera_raylib :: proc(camera: Camera) -> rl.Camera2D {
	area := view_area()
	return {offset = {area.x + area.width / 2, area.y + area.height / 2}, target = camera.pos, zoom = area.height / VIEW_HEIGHT}
}
