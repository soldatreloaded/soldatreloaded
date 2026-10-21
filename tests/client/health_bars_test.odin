package client_test

import "core:testing"

import rl "vendor:raylib"

import "../../apps/client/hud"

// Spectating, a player's health over its helmet: the bar's bottom HEALTH_BAR_RISE above
// it, centred on it, filled from the left by the health's share; red empty, yellow at
// half, green full.
@(test)
health_bars :: proc(t: ^testing.T) {
	data := hud.Hud_Data{camera = {100, 50}, view = {640, 480}, zoom = 1}
	player := hud.Player{active = true, top = {100, 50}, health = 0.25} // in the view's middle
	ground, filled := hud.health_bar_rects(&data, &player)
	size := hud.HEALTH_BAR_SIZE
	testing.expect_value(t, filled.y + filled.height, 240 - f32(hud.HEALTH_BAR_RISE))
	testing.expect_value(t, filled.x, 320 - size.x / 2)
	testing.expect_value(t, filled.width, size.x / 4)
	testing.expect(t, ground.x < filled.x && ground.width == size.x + 2, "the ground a unit round the whole bar")

	player.health = 1.5 // more than full is full
	_, filled = hud.health_bar_rects(&data, &player)
	testing.expect_value(t, filled.width, size.x)

	testing.expect_value(t, hud.health_bar_color(0), rl.Color{255, 0, 0, 255})
	testing.expect_value(t, hud.health_bar_color(0.5), rl.Color{255, 255, 0, 255})
	testing.expect_value(t, hud.health_bar_color(1), rl.Color{0, 255, 0, 255})
}
