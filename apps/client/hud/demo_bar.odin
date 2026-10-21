package hud

import "core:fmt"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../ui"

// A demo's player bar, a video player's: along the view's bottom the timeline, with a
// red flag over it at each of alpha's captures and a blue one at bravo's, and under it
// play or pause, the time, and the speed. It shows while the mouse moves, and while the
// demo is held, seeking or the bar is in use; then fades. A click on the timeline, or a
// drag along it, takes the demo there as the button lets go (a seek back plays it again
// from its start, so not at every step of a drag). What it asks the match takes from
// Hud.demo_ask; while the pointer is on it the left button is the bar's, not the
// camera's (Demo_Bar.hot).

DEMO_BAR_H :: 34 // its height, from the view's bottom
DEMO_BAR_LINGER :: 2.5 // seconds it stays after the mouse last moved
DEMO_BAR_FADE :: 6 // its fade, in its whole alpha a second

// The speeds the speed button goes round, its own among them.
@(rodata)
DEMO_SPEEDS := [?]f32{0.5, 1, 2, 4, 8}

Demo_Bar :: struct {
	shown_at: f64,    // when the mouse last moved, or the bar was used
	mouse:    [2]f32, // the mouse as of the last frame, to tell it moved
	seconds:  f64,    // the last frame's clock, for the fade
	alpha:    f32,    // how much it shows, 0 to 1
	dragging: bool,   // the timeline held
	drag:     f32,    // where along it, 0 to 1
	hot:      bool,   // the pointer is on it, as of the last frame
}

// What the bar asked of the demo this frame; the match takes it and clears it.
Demo_Ask :: struct {
	seek:  Maybe(u32), // to that tick
	pause: bool,       // held, or let go
	speed: Maybe(f32),
}

// A capture on the timeline.
Demo_Cap :: struct {
	tick: u32,
	team: res.Team,
}

// The bar, its clicks taken. Under the menus: with one open it neither shows nor takes
// the mouse.
@(private = "package")
draw_demo_bar :: proc(u: ^ui.Ui, hud: ^Hud, data: ^Hud_Data) {
	bar := &hud.demo_bar
	demo, playing := data.demo.?
	if !playing || menus_any_open(&hud.menus) {
		bar.hot, bar.dragging = false, false
		bar.alpha = 0
		return
	}
	now := data.seconds
	dt := f32(clamp(now - bar.seconds, 0, 0.1))
	bar.seconds = now
	mouse := data.mouse
	if mouse != bar.mouse do bar.shown_at = now
	bar.mouse = mouse

	top := f32(ui.VIEW_HEIGHT - DEMO_BAR_H)
	wanted := demo.paused || demo.seeking || bar.dragging || bar.hot || now - bar.shown_at < DEMO_BAR_LINGER
	bar.alpha = clamp(bar.alpha + (DEMO_BAR_FADE if wanted else -DEMO_BAR_FADE) * dt, 0, 1)
	bar.hot = bar.alpha > 0 && mouse.y >= top - 14 // the flags over the timeline too
	if bar.alpha <= 0 do return

	// where things are: the timeline across the top of the bar, the buttons under it
	x0, x1 := f32(12), u.width - 12
	track_y := top + 9
	length := max(demo.length, 1)
	at := demo.seek_to if demo.seeking else demo.at
	share := f32(at) / f32(length)
	on_track := mouse.x >= x0 - 4 && mouse.x <= x1 + 4 && mouse.y >= track_y - 12 && mouse.y <= track_y + 8
	row := top + 15 // the buttons' row
	play_box := rl.Rectangle{x0 - 2, row, 18, 16}
	speed_text := fmt.tprintf("%vx", demo.speed)
	speed_w := text_width(u, speed_text, SMALL_FONT) + 10
	speed_box := rl.Rectangle{x1 - speed_w, row, speed_w, 16}

	// the clicks
	ask := &hud.demo_ask
	if rl.IsMouseButtonPressed(.LEFT) {
		switch {
		case on_track:
			bar.dragging = true
		case inside(mouse, play_box):
			ask.pause = true
		case inside(mouse, speed_box):
			ask.speed = speed_after(demo.speed)
		}
		if bar.hot do bar.shown_at = now
	}
	if bar.dragging {
		bar.drag = clamp((mouse.x - x0) / (x1 - x0), 0, 1)
		share = bar.drag
		if !rl.IsMouseButtonDown(.LEFT) {
			ask.seek = u32(bar.drag * f32(length))
			bar.dragging = false
		}
	}

	a := bar.alpha
	faded :: proc(c: rl.Color, a: f32) -> rl.Color {return {c.r, c.g, c.b, u8(f32(c.a) * a)}}
	rl.EndBlendMode() // the shapes' colours aren't premultiplied, as the pictures' are
	// a shade over the flags, fading up into the view; then the bar's own
	ui.quad(u, {{0, top - 16}, {u.width, top - 16}, {u.width, top}, {0, top}}, {{}, {}, faded({0, 0, 0, 120}, a), faded({0, 0, 0, 120}, a)})
	ui.rect(u, 0, top, u.width, ui.VIEW_HEIGHT, faded({0, 0, 0, 150}, a))

	// the timeline: what has played, and the rest
	thick: f32 = 4 if on_track || bar.dragging else 2
	ui.rrect(u, x0, track_y - thick / 2, x1 - x0, thick, thick / 2, faded({255, 255, 255, 70}, a))
	played := x0 + (x1 - x0) * share
	ui.rrect(u, x0, track_y - thick / 2, played - x0, thick, thick / 2, faded({230, 60, 50, 255}, a))
	if demo.seeking && !bar.dragging { // how far the seek has run, to where it goes
		ran := x0 + (x1 - x0) * f32(demo.at) / f32(length)
		ui.rrect(u, x0, track_y - thick / 2, ran - x0, thick, thick / 2, faded({255, 255, 255, 140}, a))
	}
	ui.circle(u, played, track_y, 5 if on_track || bar.dragging else 3.5, faded({240, 70, 60, 255}, a))

	// a flag over the timeline at each capture, the team's colour
	near: Maybe(Demo_Cap)
	for cap in demo.caps {
		x := x0 + (x1 - x0) * f32(cap.tick) / f32(length)
		color := rl.Color{235, 60, 50, 255} if cap.team == .Alpha else rl.Color{70, 120, 245, 255} if cap.team == .Bravo else rl.Color{230, 230, 230, 255}
		ui.rect(u, x - 0.5, track_y - 11, x + 0.5, track_y - 1, faded(color, a)) // the pole
		ui.quad(u, {{x + 0.5, track_y - 11}, {x + 7, track_y - 8.5}, {x + 0.5, track_y - 6}, {x + 0.5, track_y - 6}}, {faded(color, a), faded(color, a), faded(color, a), faded(color, a)})
		if on_track && abs(mouse.x - x) < 4 do near = cap
	}

	// play or pause: what a click would do
	rl.EndBlendMode()
	icon := faded({255, 255, 255, 230}, a)
	if inside(mouse, play_box) do icon = faded({255, 255, 255, 255}, a)
	ix, iy := play_box.x + 4, play_box.y + 3
	if demo.paused {
		ui.quad(u, {{ix, iy}, {ix + 10, iy + 5}, {ix, iy + 10}, {ix, iy + 10}}, {icon, icon, icon, icon})
	} else {
		ui.rect(u, ix, iy, ix + 3.5, iy + 10, icon)
		ui.rect(u, ix + 6.5, iy, ix + 10, iy + 10, icon)
	}

	// the time, and the speed
	shown := u32(f32(length) * bar.drag) if bar.dragging else at
	time := fmt.tprintf("%s / %s", clock(shown), clock(length))
	if demo.seeking && !bar.dragging do time = fmt.tprintf("%s  seeking...", time)
	write(u, time, {play_box.x + play_box.width + 8, row + 2}, SMALL_FONT, faded({235, 235, 235, 255}, a))
	if inside(mouse, speed_box) {
		rl.EndBlendMode()
		ui.rrect(u, speed_box.x, speed_box.y, speed_box.width, speed_box.height, 3, faded({255, 255, 255, 40}, a))
	}
	write(u, speed_text, {speed_box.x + 5, row + 2}, SMALL_FONT, faded({235, 235, 235, 255} if demo.speed == 1 else {255, 210, 90, 255}, a))

	// over the timeline under the pointer: the time there, and a capture's team at its flag
	if on_track || bar.dragging {
		hover := bar.drag if bar.dragging else clamp((mouse.x - x0) / (x1 - x0), 0, 1)
		tip := clock(u32(hover * f32(length)))
		if cap, is := near.?; is && !bar.dragging do tip = fmt.tprintf("%s  %s cap", clock(cap.tick), team_name(cap.team))
		w := text_width(u, tip, SMALL_FONT) + 10
		tx := clamp(x0 + (x1 - x0) * hover - w / 2, 2, u.width - w - 2)
		rl.EndBlendMode()
		ui.rrect(u, tx, track_y - 30, w, 15, 3, faded({0, 0, 0, 200}, a))
		write(u, tip, {tx + 5, track_y - 29}, SMALL_FONT, faded({255, 255, 255, 255}, a))
	}

	inside :: proc(p: [2]f32, r: rl.Rectangle) -> bool {
		return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height
	}
	// `ticks` as m:ss
	clock :: proc(ticks: u32) -> string {
		s := ticks / sim.TICK_RATE
		return fmt.tprintf("%d:%02d", s / 60, s % 60)
	}
	speed_after :: proc(speed: f32) -> f32 {
		for s, i in DEMO_SPEEDS do if speed < s + 0.01 do return DEMO_SPEEDS[(i + 1) % len(DEMO_SPEEDS)]
		return 1
	}
}

// Whether the bar shows: the pointer drawn over it.
demo_bar_shown :: proc(hud: ^Hud) -> bool {
	return hud.demo_bar.alpha > 0
}
