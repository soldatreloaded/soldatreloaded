package hud

import sa "core:container/small_array"
import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../ui"

// What the feed says (feed.odin), and the HUD's other words: the big message, the kill
// feed down the right (or left) with its weapons' icons, the console in the corner, the respawn
// count and my last kill's shot. The original's RenderInterface's texts.

KILL_FEED_LEFT_TEXT :: 45 // a line's start, the kill feed on the left: past the icon
KILL_ROW_GAP :: 2 // between the kill feed's lines, past font_weaponmenusize
KILL_GAP :: 8 // KILLCONSOLE_SEPARATE_HEIGHT: above each killer's line
CONSOLE_LINE_HEIGHT :: 1.5 // font_consolelineheight: a console line, in the small font's points
BIG_MESSAGE_BASELINE :: 420
BIG_MESSAGE_WIDTH :: 0.7 // of the view's, at most
NARROW_WINDOW :: 1024 // pixels: narrower, the kill feed fades behind the scoreboard

// The big message, in the middle, low; fading as its time runs out, narrower to fit.
draw_big_message :: proc(u: ^ui.Ui, feed: ^Feed) {
	big := &feed.big
	if big.ticks <= 0 do return
	text := utils.short_string_text(&big.text)
	alpha := clamp(3 * int(big.ticks) + 25, 0, int(big.color.a))
	font := BIG_FONT
	if w := text_width(u, text, font); w > BIG_MESSAGE_WIDTH * u.width do font.scale *= BIG_MESSAGE_WIDTH * u.width / w
	a := f32(alpha) / 255
	shadow := rl.Color{0, 0, 0, u8(a * a * a * a * f32(alpha))}
	x := (u.width - text_width(u, text, font)) / 2
	write(u, text, {x, BIG_MESSAGE_BASELINE}, font, with_alpha(big.color, alpha), shadow, .Baseline)
}

// Where the kill feed begins, by interface.kill_log_position: at the top on the right
// (the original's), lower on the right, or on the left under the chat, where the icon
// comes first and the lines run from the left edge.
@(private = "file", rodata)
KILL_FEED_TOP := [res.Kill_Log_Position]f32 {
	.Top_Right   = 60,
	.Lower_Right = 210,
	.Top_Left    = 110,
}

// Where the kill feed begins: its place's top, or at the top on the right below the
// corner's stats, where they reach down past it.
kill_feed_top :: proc(data: ^Hud_Data) -> f32 {
	top := KILL_FEED_TOP[data.kill_log]
	if data.kill_log == .Top_Right do top = max(top, readouts_bottom(data) + 2)
	return top
}

// The kill feed's weapon icons, beside its lines, from `top`.
draw_kill_icons :: proc(u: ^ui.Ui, art: ^Art, feed: ^Feed, place: res.Kill_Log_Position, top: f32, dim: bool) {
	alpha: u8 = 50 if dim && narrow(u) else 255
	gap: f32 = 0
	x := 5 if place == .Top_Left else 605 * wide(u)
	for &kill, row in sa.slice(&feed.kills) {
		if !kill.icon do continue
		gap += KILL_GAP
		at := [2]f32{x, f32(row) * kill_row(u) + top - 1 + gap}
		picture(u, art.guns[kill.weapon], at, {255, 255, 255, alpha}, {0.8, 0.8})
	}
}

// Its lines, right-aligned (or from the left, past the icons), smaller when long; on a
// narrow window, faint behind the scoreboard and fainter while a line is typed.
draw_kill_feed :: proc(u: ^ui.Ui, feed: ^Feed, place: res.Kill_Log_Position, top: f32, dim, typing: bool) {
	alpha := 245
	if narrow(u) && dim do alpha = 80
	else if narrow(u) && typing do alpha = 180
	gap: f32 = 0
	for &kill, row in sa.slice(&feed.kills) {
		text := utils.short_string_text(&kill.text)
		if kill.icon do gap += KILL_GAP
		font := SMALLEST_FONT if len(text) > 14 else WEAPONS_FONT
		x := KILL_FEED_LEFT_TEXT if place == .Top_Left else 595 * wide(u) - text_width(u, text, font)
		at := [2]f32{x, top + f32(row) * kill_row(u) + gap}
		write(u, text, at, font, with_alpha(kill.color, alpha))
	}
}

// The console in the top-left corner, or while a line is `typing` the big console in its
// place, paged `scroll` lines back; faint behind the scoreboard and the menus, a line
// smaller where it runs past the view.
draw_console :: proc(u: ^ui.Ui, feed: ^Feed, dim, typing: bool, scroll: int) {
	lines: []Console_Line
	if typing {
		all := sa.slice(&feed.scrollback)
		shown := min(len(all), BIG_CONSOLE_SHOWN)
		back := clamp(scroll, 0, len(all) - shown)
		lines = all[len(all) - shown - back:][:shown]
	} else {
		all := sa.slice(&feed.console)
		lines = all[len(all) - min(len(all), max(feed.console_length, 0)):]
	}
	for &line, i in lines {
		text := utils.short_string_text(&line.text)
		font := SMALLEST_FONT if text_width(u, text, SMALL_FONT) > u.width - 10 else SMALL_FONT
		write(u, text, {5, 1 + f32(i) * console_row(u)}, font, with_alpha(line.color, 60 if dim else 255))
	}
}

// Dead: a box at the top, and the time until I am placed again.
draw_respawn :: proc(u: ^ui.Ui, art: ^Art, mine: ^Mine) {
	if !mine.dead do return
	box(u, art, {180 * wide(u), 1, 300, 22})
	if mine.respawn > 0 {
		write(u, fmt.tprintf("Respawn in... %.1f", f32(mine.respawn) / 60), {200 * wide(u), 4}, MENU_FONT, {255, 65, 55, 255})
	}
}

// My last kill's shot: how far, how long in the air, how many ricochets; pulsing.
draw_shot :: proc(u: ^ui.Ui, feed: ^Feed, seconds: f64) {
	shot := &feed.shot
	if shot.ticks <= 0 do return
	color := rl.Color{230, 65, 60, u8(150 + abs(math.sin(5.1 * seconds)) * 100)}
	write(u, fmt.tprintf("DISTANCE: %.2fm", shot.distance), {390 * wide(u), 431}, SMALL_FONT, color)
	write(u, fmt.tprintf("AIRTIME: %.2fs", shot.airtime), {228 * wide(u), 431}, SMALL_FONT, color)
	if shot.ricochets > 0 do write(u, fmt.tprintf("RICOCHETS: %d", shot.ricochets), {62 * wide(u), 431}, SMALL_FONT, color)
}

@(private = "file")
narrow :: proc(u: ^ui.Ui) -> bool {
	return u.width * u.scale < NARROW_WINDOW
}

// A kill feed line's height: its font's size in points, and a gap, as the original's.
@(private = "file")
kill_row :: proc(u: ^ui.Ui) -> f32 {
	return u.hud[.Weapons].size / ui.POINT + KILL_ROW_GAP
}

// A console line's height: its font's size in points, times font_consolelineheight.
@(private = "file")
console_row :: proc(u: ^ui.Ui) -> f32 {
	return CONSOLE_LINE_HEIGHT * u.hud[.Small].size / ui.POINT
}
