package hud

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import "../ui"

// What the HUD says of where I stand beyond the game: my ping in the corner, greener the
// lower (where the original has its ping dot); whom the camera follows while I watch;
// the demo being recorded, blinking, and the one playing, how far through it is.

// My ping on the line, in the original's colours for it.
draw_ping :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	ping := data.players[data.me].ping
	color: rl.Color
	switch {
	case ping <= 50:  color = {0x00, 0xFF, 0x00, 230}
	case ping <= 100: color = {0x22, 0xFF, 0x00, 230}
	case ping <= 150: color = {0x54, 0xC7, 0x00, 230}
	case ping <= 200: color = {0x76, 0xA7, 0x00, 230}
	case ping <= 250: color = {0x93, 0x88, 0x00, 230}
	case ping <= 300: color = {0xA1, 0x77, 0x00, 230}
	case ping <= 350: color = {0xCC, 0x48, 0x00, 230}
	case:             color = {0xFF, 0x00, 0x00, 230}
	}
	write(u, fmt.tprintf("%d ms", ping), {600 * wide(u), 18}, SMALL_FONT, color)
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

// A demo being recorded: REC, blinking. One playing: how far through it is, where the
// original puts it, and whether it is held or hurried.
draw_demo_marks :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	if data.recording {
		blink := u8(abs(math.sin(5.1 * data.seconds / 2)) * 255)
		write(u, "REC", {612 * wide(u), 1}, SMALL_FONT, {195, 0, 0, blink})
	}
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
