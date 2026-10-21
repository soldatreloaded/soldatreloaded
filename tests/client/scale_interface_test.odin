package client_test

import "core:math"
import "core:testing"

import sa "core:container/small_array"

import "../../apps/client/hud"
import "../../apps/client/ui"

// Scale_Interface off, as OpenSoldat's r_scaleinterface off: each part of the HUD drawn as
// big as in a 640 by 480 window, a window pixel to a unit, about its anchor; on, the
// default, as big as the window makes it. A point the pointer is on falls where it is in
// the part as laid out, so a menu's button is clicked where it is drawn.
@(test)
interface_unscaled :: proc(t: ^testing.T) {
	u := ui.Ui{scale = 2.25, width = 853} // a 1920 by 1080 window
	data: hud.Hud_Data
	testing.expect_value(t, hud.shrink_of(&u, &data), 1) // scaled, the default
	data.unscaled = true
	by := hud.shrink_of(&u, &data)
	testing.expect(t, math.abs(by - 1 / 2.25) < 1e-6, "a pixel's share of a unit")

	z := hud.Zoom{at = {600, 20}, by = by}
	laid := [2]f32{560, 60}
	drawn := z.at + (laid - z.at) * by // where the part's point is drawn, shrunk about the anchor
	back := hud.unzoomed(z, drawn)
	testing.expect(t, math.abs(back.x - laid.x) < 1e-3 && math.abs(back.y - laid.y) < 1e-3, "the pointer there is on the point as laid out")

	// the escape menu, centred at its own size: its first button is hovered where it is drawn
	menus := hud.Menus{open = {.Escape}, width = u.width, by = by}
	buttons := hud.menu_buttons(&menus, .Escape)
	first := sa.get(buttons, 0).rect
	middle := [2]f32{first.x + first.width / 2, first.y + first.height / 2}
	mz := hud.menu_zoom(&menus, .Escape)
	menus.cursor = mz.at + (middle - mz.at) * by
	menu, button, hovered := hud.menus_hovered(&menus)
	testing.expect(t, hovered && menu == .Escape && button == 0, "the button under the pointer, drawn unscaled")
	menus.cursor = middle // where it would be drawn scaled: not on it now
	_, button, hovered = hud.menus_hovered(&menus)
	testing.expect(t, !hovered || button != 0, "not where it would be scaled")
}
