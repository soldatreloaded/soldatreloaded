package hud

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import "../draw"
import "../ui"

// What the HUD says of where I stand beyond the game: the frame rate and the line's
// numbers stacked in the top-right corner, each as the settings show it, with the demo
// being recorded blinking over them, and the clocks beside them; whom the camera follows
// while I watch; the round's time left, if it is shown; and the demo playing, how far
// through it is.

// Each as it is set to show; off a server the line's read 0.
Stat :: enum {
	FPS,
	Ping,
	Loss,
	Jitter,
}

Stats :: bit_set[Stat]

STATS_EDGE :: 4 // from the view's top and right
STATS_FONT :: SMALLEST_FONT
STATS_ROW :: 11
@(private = "file") STATS_COLOR :: rl.Color{239, 170, 200, 255}

// The corner's lines, top down: REC while a demo is recorded, then each stat shown.
draw_readouts :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	y: f32 = STATS_EDGE
	if data.recording {
		blink := u8(abs(math.sin(5.1 * data.seconds / 2)) * 255)
		readout(u, "REC", &y, {195, 0, 0, blink})
	}
	shown := data.stats
	if .FPS in shown do readout(u, fmt.tprintf("FPS: %d", data.fps), &y, STATS_COLOR)
	if .Ping in shown do readout(u, fmt.tprintf("Ping: %d ms", data.players[data.me].ping), &y, STATS_COLOR)
	if .Loss in shown do readout(u, fmt.tprintf("Loss: %d%%", data.loss), &y, STATS_COLOR)
	if .Jitter in shown do readout(u, fmt.tprintf("Jitter: %d ms", data.jitter), &y, STATS_COLOR)
}

// The clocks, with their setting: the round's time left and the time of day, in a row
// along the top, left of the corner's lines and in the scoreboard clock's colour. The
// lines are made room for at their widest likely numbers, so the row stays put as they
// change.
draw_clocks :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	if !data.clocks do return
	room: f32
	widest :: proc(u: ^ui.Ui, room: ^f32, likely, text: string) {
		room^ = max(room^, text_width(u, likely, STATS_FONT), text_width(u, text, STATS_FONT))
	}
	shown := data.stats
	if data.recording do widest(u, &room, "REC", "REC")
	if .FPS in shown do widest(u, &room, "FPS: 9999", fmt.tprintf("FPS: %d", data.fps))
	if .Ping in shown do widest(u, &room, "Ping: 999 ms", fmt.tprintf("Ping: %d ms", data.players[data.me].ping))
	if .Loss in shown do widest(u, &room, "Loss: 100%", fmt.tprintf("Loss: %d%%", data.loss))
	if .Jitter in shown do widest(u, &room, "Jitter: 999 ms", fmt.tprintf("Jitter: %d ms", data.jitter))
	if room > 0 do room += 12
	text := fmt.tprintf("Time %02d:%02d   %s", data.time_left / 60, data.time_left % 60, data.time_of_day)
	write(u, text, {u.width - STATS_EDGE - room - text_width(u, text, STATS_FONT), STATS_EDGE}, STATS_FONT, CLOCK_COLOR)
}

// Where the corner's lines end, for what is drawn under them.
readouts_bottom :: proc(data: ^Hud_Data) -> f32 {
	return STATS_EDGE + f32(card(data.stats) + int(data.recording)) * STATS_ROW
}

@(private = "file")
readout :: proc(u: ^ui.Ui, text: string, y: ^f32, color: rl.Color) {
	write(u, text, {u.width - STATS_EDGE - text_width(u, text, STATS_FONT), y^}, STATS_FONT, color)
	y^ += STATS_ROW
}

// Watching: the free camera, or the player followed, redder while they are dead.
draw_watching :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	text: string
	color := rl.Color{205, 205, 205, 255}
	if data.free_camera {
		text = "Free Camera"
	} else if followed, following := data.follow.?; following && followed != data.me {
		player := &data.players[followed]
		text = fmt.tprintf("Following %s", player.name)
		if player.dead do color = {205, 100, 100, 255}
	}
	if text == "" do return
	write(u, text, {(u.width - text_width(u, text, SMALL_FONT)) / 2, 430}, SMALL_FONT, color)
}

// The time left in the round, M:SS, in the middle at the top: under the respawn box, and
// under the minimap while it is shown. Paused, it stands; once the round is over it is
// gone, the scoreboard having the round's last word. The original shows the time only on
// the scoreboard (InterfaceGraphics.pas, "Time %.2d:%.2d"), whose colour it keeps.
draw_time_left :: proc(u: ^ui.Ui, data: ^Hud_Data, minimap: ^draw.Minimap) {
	if data.ended do return
	y: f32 = 26
	if data.minimap && minimap.image.texture.id != 0 do y = max(y, MINIMAP_AT.y + minimap.size.y + 3)
	text := fmt.tprintf("%d:%02d", data.time_left / 60, data.time_left % 60)
	write(u, text, {(u.width - text_width(u, text, MENU_FONT)) / 2, y}, MENU_FONT, CLOCK_COLOR)
}

// A demo playing: how far through it is, where the original puts it, and whether it is
// held or hurried.
draw_demo_marks :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	demo, playing := data.demo.?
	if !playing do return
	pace := ""
	switch {
	case demo.seeking:     pace = "  seeking..."
	case demo.paused:      pace = "  paused"
	case demo.speed != 1:  pace = fmt.tprintf("  x%v", demo.speed)
	}
	at, of := demo.at / 60, demo.length / 60
	line := fmt.tprintf("Demo: %02d:%02d / %02d:%02d%s", at / 60, at % 60, of / 60, of % 60, pace)
	write(u, line, {460 * wide(u), 80}, SMALL_FONT, {239, 170, 200, 255})
}
