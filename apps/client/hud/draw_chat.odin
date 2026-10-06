package hud

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import "../ui"

// The chat as the original draws it (RenderInterface's chat, vote and radio parts): the
// prompt with its caret blinking, what each player said over their head with the dots
// while they type, the vote's box with how to answer it, and the radio menu's two
// columns.

MORE_CHAT_TEXT :: 60 // a longer line isn't shown over the head (MORECHATTEXT)
PROMPT_BASELINE :: 420

@(private = "file") ABOVE_CHAT_COLOR :: rl.Color{0xFD, 0xFD, 0xF9, 0xFF}
@(private = "file") CARET_COLOR :: rl.Color{255, 230, 170, 255}

// What I am typing, after what it is, with its caret blinking.
draw_prompt :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	prompt := &data.prompt
	prefix: string
	color: rl.Color
	switch prompt.mode {
	case .None:    return
	case .Public:  prefix, color = "Say:", CHAT_COLOR
	case .Team:    prefix, color = "Team Say:", TEAM_CHAT_COLOR
	case .Command: prefix, color = "Cmd: ", ENTER_COLOR
	}
	line := fmt.tprintf("%s%s", prefix, prompt.text)
	font := SMALL_FONT if text_width(u, line, SMALL_FONT) < u.width - 80 else SMALLEST_FONT
	write(u, line, {5, PROMPT_BASELINE}, font, color, vertical = .Baseline)

	t := data.seconds - prompt.changed_at
	if t - math.floor(t) > 0.5 do return
	before := line[:len(prefix) + clamp(prompt.cursor, 0, len(prompt.text))]
	// a trailing space is measured by doubling it, as the original works around
	if len(before) > 0 && before[len(before) - 1] == ' ' do before = fmt.tprintf("%s ", before)
	pixel := 1 / u.scale
	height := line_height(u, font)
	x := align(u, 5 + text_width(u, before, font)) + 2 * pixel
	y := align(u, PROMPT_BASELINE - height)
	fill(u, {x, y, pixel, align(u, 1.4 * height)}, CARET_COLOR)
}

// What each player said, over their head, and the dots while they type: not over the
// dead or a spectator, who have no head on the field to put it over.
draw_said :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	for &player in data.players {
		typing := player.typing && data.typing != .Off
		if !player.active || player.dead || player.team == .Spectator || (!typing && player.said_ticks <= 0) do continue
		at := in_view(data, player.top)
		dy: f32 = -25
		if typing { // the dots stepping one to three, after "Typing" if asked (interface.typing)
			full := "Typing..." if data.typing == .Typing else "..."
			shown := full[:len(full) - 2 + int(data.tick / 30 % 3)]
			write(u, shown, {at.x - text_width(u, full, SMALL_FONT) / 2, at.y + dy}, SMALL_FONT, ABOVE_CHAT_COLOR, vertical = .Bottom)
			dy -= 15
		}
		if player.said_ticks > 0 && len(player.said) < MORE_CHAT_TEXT {
			color := with_alpha(ABOVE_CHAT_COLOR, int(9 * player.said_ticks))
			write(u, player.said, {at.x - text_width(u, player.said, SMALL_FONT) / 2, at.y + dy}, SMALL_FONT, color, vertical = .Bottom)
		}
	}
}

// The vote's box, in the pictures' pass under every text, so the console's lines are
// never covered by it (InterfaceGraphics.pas).
draw_vote_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	if data.vote.kind == .None do return
	box(u, art, {45 * wide(u), 400, 252, 40}, STATUS_ALPHA * 36 / 100)
}

// What is voted on, by whom and why, and how to answer; and while a kick's reason is
// typed, what the prompt is for.
draw_vote :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	if vote := &data.vote; vote.kind != .None {
		x, y := 45 * wide(u), f32(400)
		write(u, "Kick" if vote.kind == .Kick else "Map", {x + 30, y}, WEAPONS_FONT, {254, 104, 104, 225})
		write(u, vote.target, {x + 65, y}, WEAPONS_FONT, {244, 244, 244, 225})
		write(u, fmt.tprintf("Voter: %s", vote.starter), {x + 10, y + 11}, WEAPONS_FONT, {224, 218, 244, 205})
		write(u, fmt.tprintf("Reason:%s", vote.reason), {x + 10, y + 20}, WEAPONS_FONT, {224, 218, 244, 205})
		write(u, "F12 - Yes   F11 - No", {x + 50, y + 31}, WEAPONS_FONT, {234, 234, 114, 205})
	}
	if data.prompt.reason do write(u, "Type reason for vote:", {5, 390}, SMALL_FONT, {254, 124, 124, 255})
}

// The radio menu: the calls, and the places of the one chosen; faint behind the
// scoreboard.
draw_radio :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data, dim: bool) {
	radio := &data.radio
	box(u, art, {5, 250, 180, 80})
	if radio.call != 0 do box(u, art, {185, 250, 180, 80})
	alpha := u8(80 if dim else 230)
	write(u, "Radio:", {10, 252}, MENU_FONT, {255, 255, 255, alpha})
	plain, chosen := rl.Color{200, 200, 200, alpha}, rl.Color{210, 210, 5, alpha}
	for call, i in radio.calls {
		write(u, fmt.tprintf("%d: %s", i + 1, call), {10, 270 + 12 * f32(i)}, SMALL_FONT, chosen if radio.call == i + 1 else plain)
	}
	if radio.call == 0 do return
	for place, i in radio.places {
		write(u, fmt.tprintf("%d: %s", i + 1, place), {190, 270 + 12 * f32(i)}, SMALL_FONT, plain)
	}
}
