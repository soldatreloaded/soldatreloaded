package menu

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "../ui"

// The loading screen, shown while the client starts, before there is a menu: the menu's
// background, the game's name in the middle of it, and under that a bar that fills as
// the start goes and what is being done now. The client draws one frame of it before
// each slow step of starting, and the window holds that frame until the step is done;
// so nothing is kept, and it needs nothing of the menu but the faces.

LOADING_BAR_W :: 200
LOADING_BAR_H :: 3

// One frame of it: `doing` written under the bar, `share` (0 to 1) of the bar filled.
loading_draw :: proc(u: ^ui.Ui, doing: string, share: f32) {
	k := ui.Kit{ui = u} // for the text alone: nothing here is pressed
	rlgl.DisableBackfaceCulling() // the shapes are wound either way
	background(u, rl.GetTime())

	cx := u.width / 2
	name_w := ui.width_of(u, ui.LOGO, "SOLDAT")
	y := f32(VIEW_H) / 2 - 50
	y += logo(&k, cx - name_w / 2, y, name_w) + 28

	x := cx - LOADING_BAR_W / 2
	ui.rrect(u, x, y, LOADING_BAR_W, LOADING_BAR_H, LOADING_BAR_H / 2, ui.TRACK)
	ui.rrect(u, x, y, LOADING_BAR_W * clamp(share, 0, 1), LOADING_BAR_H, LOADING_BAR_H / 2, ui.ACCENT)
	ui.text_mid(&k, ui.BODY, doing, cx - ui.width_of(u, ui.BODY, doing) / 2, y + 18, ui.MUTED)

	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}
