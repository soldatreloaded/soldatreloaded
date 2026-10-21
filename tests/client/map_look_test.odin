package client_test

import "core:testing"

import "../../apps/client/draw"
import res "../../core/resources"
import "../../core/utils"

// The map's polygons as the graphics settings have them: by default as the map has them,
// its shader left out; the saturation and brightness held within the settings' range; a
// forced colour in place of each corner's, the corner's opacity kept.
@(test)
map_look :: proc(t: ^testing.T) {
	graphics := res.DEFAULT_CLIENT_CONFIG.graphics
	look := draw.map_look_of(&graphics)
	testing.expect(t, look.saturation == 1 && look.brightness == 1 && !look.forced, "the map's own, by default")
	corner := utils.Rgba{10, 20, 30, 100}
	testing.expect_value(t, draw.map_corner(look, corner), corner)

	graphics.map_saturation, graphics.map_brightness = -50, 1000
	look = draw.map_look_of(&graphics)
	testing.expect(t, look.saturation == 0 && look.brightness == f32(res.MAP_BRIGHTNESS_HIGHEST) / 100, "held within the range")
	graphics.map_brightness = 0
	testing.expect_value(t, draw.map_look_of(&graphics).brightness, f32(res.MAP_BRIGHTNESS_LOWEST) / 100)

	graphics.force_polygon_color = true
	graphics.forced_polygon_color = {200, 150, 100, 255}
	look = draw.map_look_of(&graphics)
	testing.expect_value(t, draw.map_corner(look, corner), utils.Rgba{200, 150, 100, 100})
}
