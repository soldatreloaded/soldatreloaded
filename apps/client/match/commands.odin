package match

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

import res "../../../core/resources"
import "../hud"

// What a key's bind or the prompt's slash asks: the original's commands, as the C
// client's console has them, by the same names so a config's binds mean what they
// meant. A command the client doesn't know, typed after a slash, goes to the server.
//
//   escmenu teammenu weaponsmenu fragsmenu statsmenu   the menus
//   toggle <setting>    ui_minimap (vsync, the frame rate and the player names are the menus' alone)
//   togglewindow        fullscreen, or a window
//   chat teamchat cmd   the prompt, for everyone, the team, or a command
//   say <text>  say_team <text>   a line, as a key says it: a taunt
//   votemap <map>  votekick <player>
//   +radio  radio <call> <place> [words]
//   emote <name>        an emote (/victory and the rest), done and said to nobody
//   mute unmute <player | all>  muteall muteteam muteenemies mutespecs  mutes
//   freecam             the free camera, while I watch or a demo plays
//   record [name]  stop  togglerecord (record, or stop the recording)  playdemo <name>
//   demo_pause  demo_fast  demo_tick <tick>  demo_tick_r <ticks>
//   connect <address>  disconnect  quit
//   netstats            a line a second of how the line is doing
//   screenshot          the client's, in a match or out of one, taken each frame (main.odin)
//   volume <percent | +n | -n>  sensitivity <percent | +n | -n>   set, or stepped by n
//                       percent (1.00 the sensitivity's 100), and said in the console

@(private = "file", rodata)
COMMANDS := [?]string {
	"escmenu", "teammenu", "weaponsmenu", "fragsmenu", "statsmenu", "toggle", "togglewindow", "volume", "sensitivity",
	"chat", "teamchat", "cmd", "say", "say_team", "votemap", "votekick", "+radio", "-radio", "radio", "emote", "+emotes", "-emotes",
	"mute", "unmute", "muteall", "muteteam", "muteenemies", "mutespecs", "mutes", "freecam",
	"record", "stop", "togglerecord", "playdemo", "demo_pause", "demo_fast", "demo_tick", "demo_tick_r",
	"connect", "disconnect", "quit", "netstats", "screenshot",
}

// Whether the client has a command of that name, to run here rather than say.
command_known :: proc(word: string) -> bool {
	for known in COMMANDS {
		if known == word do return true
	}
	return false
}

// A command line: its word, and the rest for its arguments.
command_run :: proc(match: ^Match, line: string) {
	config := match.config
	word, _, rest := strings.partition(strings.trim_space(line), " ")
	rest = strings.trim_space(rest)
	menus := &match.hud.menus
	switch word {
	case "escmenu":
		escape_key(match)
	case "teammenu":
		hud.menus_show(menus, .Team, .Team not_in menus.open)
	case "weaponsmenu":
		weapons_menu_key(match)
	case "fragsmenu":
		hud.hud_toggle_scoreboard(&match.hud)
	case "statsmenu":
		hud.hud_toggle_stats(&match.hud)
	case "toggle":
		toggle(match, rest)
	case "togglewindow":
		graphics := &config.graphics
		graphics.window_mode = .Windowed if graphics.window_mode == .Fullscreen else .Fullscreen
	case "volume":
		percent, ok := percent_set(f64(config.sound.volume), rest, 0, 100)
		if !ok do usage(match, "volume <0 to 100 | +n | -n>")
		else {
			config.sound.volume = i32(percent)
			client_say(match, "Volume %d%%", config.sound.volume)
		}
	case "sensitivity":
		lowest, highest :: res.SENSITIVITY_LOWEST * 100, res.SENSITIVITY_HIGHEST * 100
		percent, ok := percent_set(f64(config.controls.sensitivity) * 100, rest, lowest, highest)
		if !ok do usage(match, "sensitivity <%.0f to %.0f | +n | -n>, percent", lowest, highest)
		else {
			config.controls.sensitivity = f32(percent / 100)
			client_say(match, "Sensitivity %.2f", config.controls.sensitivity)
		}
	case "chat":
		prompt_open(match, .Public)
	case "teamchat":
		prompt_open(match, .Team)
	case "cmd":
		prompt_open(match, .Command)
	case "say", "say_team":
		if rest == "" do usage(match, "%s <text>", word)
		else do say(match, word == "say_team", true, taunt_fill(match, unquoted(rest))) // a key's: a taunt, a radio call, its variables filled in
	case "votemap", "votekick":
		if rest == "" do usage(match, "%s <%s>", word, "map" if word == "votemap" else "player")
		else do say(match, false, false, fmt.tprintf("/%s %s", word, rest))
	case "emote":
		if !emote(match, strings.trim_space(rest)) do usage(match, "emote <%s>", emote_names())
	case "+radio":
		radio_toggle(match)
	case "-radio":
	case "+emotes": // the wheel, up while the key is held (emote_wheel_keys)
		emote_wheel_open(match)
	case "-emotes":
	case "radio":
		call, place, words := radio_args(rest)
		if call == 0 do usage(match, "radio <call> <place> [words], 1 to %d each", RADIO_CALLS)
		else do radio_call(match, call, place, words)
	case "mute", "unmute":
		if rest == "" do usage(match, "%s <name or slot | all>", word)
		else do mute_command(match, word == "mute", rest)
	case "muteall", "muteteam", "muteenemies", "mutespecs":
		mute_kind(match, word)
	case "mutes":
		mutes_list(match)
	case "freecam":
		freecam(match)
	case "record":
		record_ask(match, rest)
	case "stop":
		record_stop_asked(match)
	case "togglerecord":
		record_toggle(match)
	case "playdemo":
		if rest == "" do usage(match, "playdemo <name>")
		else do match.request = Play_Demo{strings.clone(rest, context.temp_allocator)}
	case "demo_pause", "demo_fast", "demo_tick", "demo_tick_r":
		demo_command(match, word, rest)
	case "connect":
		if rest == "" do usage(match, "connect <address[:port][/password]>")
		else do match.request = Connect{strings.clone(rest, context.temp_allocator)}
	case "disconnect":
		match.request = Leave{}
	case "quit":
		match.request = Quit{}
	case "netstats":
		match.quality.netstats = !match.quality.netstats
	}
}

// Escape: the radio menu shut, or the kick and map windows back to the escape menu
// alone (ControlGame.pas); else the escape menu, opened or shut.
@(private = "file")
escape_key :: proc(match: ^Match) {
	menus := &match.hud.menus
	switch {
	case match.radio.open:
		match.radio = {cooldown = match.radio.cooldown}
	case menus.open & {.Kick, .Map} != {}:
		hud.menus_show(menus, .Kick, false)
		hud.menus_show(menus, .Map, false)
	case:
		hud.menus_show(menus, .Escape, .Escape not_in menus.open)
		if .Weapons in menus.open do weapons_show(match) // brought back as the escape menu shut
	}
}

// toggle <setting>: a setting turned on or off, by the C client's name for it.
@(private = "file")
toggle :: proc(match: ^Match, name: string) {
	config := match.config
	setting: ^bool
	switch name {
	case "ui_minimap": setting = &config.interface.minimap
	case:
		usage(match, "toggle ui_minimap")
		return
	}
	setting^ = !setting^
}

// A setting in percent as `arg` has it: a number, or `now` stepped by a signed one
// ("+5", "-5"), within `lowest` and `highest`. A step lands on its own multiples, so a
// value set by hand between them comes back onto them. False for no number.
@(private = "file")
percent_set :: proc(now: f64, arg: string, lowest, highest: f64) -> (percent: f64, ok: bool) {
	n := strconv.parse_f64(arg) or_return
	percent = n
	if arg[0] == '+' || arg[0] == '-' {
		percent = math.round((now + n) / abs(n)) * abs(n) if n != 0 else now
	}
	return clamp(percent, lowest, highest), true
}

// radio's numbers, 1 to RADIO_CALLS each, and the words after them; none if they aren't.
@(private = "file")
radio_args :: proc(rest: string) -> (call, place: int, words: string) {
	first, _, after := strings.partition(rest, " ")
	second, _, words_after := strings.partition(strings.trim_space(after), " ")
	c, c_ok := strconv.parse_int(first)
	p, p_ok := strconv.parse_int(second)
	if !c_ok || !p_ok || len(first) != 1 || len(second) != 1 || c < 1 || c > RADIO_CALLS || p < 1 || p > RADIO_CALLS do return
	return c, p, unquoted(strings.trim_space(words_after))
}

// A command's text without the quotes a bind may put round it.
@(private = "package")
unquoted :: proc(text: string) -> string {
	if len(text) >= 2 && text[0] == '"' && text[len(text) - 1] == '"' do return text[1:len(text) - 1]
	return text
}

// How a command is used, said in the console.
@(private = "package")
usage :: proc(match: ^Match, format: string, args: ..any) {
	hud.console_add(&match.hud.feed, hud.ENTER_COLOR, fmt.tprintf("usage: %s", fmt.tprintf(format, ..args)))
}

// The client's own word, in the console: an answer to a command.
@(private = "package")
client_say :: proc(match: ^Match, format: string, args: ..any) {
	hud.console_add(&match.hud.feed, hud.CLIENT_COLOR, fmt.tprintf(format, ..args))
}

// Something that went wrong, in the console.
@(private = "package")
hud_warn :: proc(match: ^Match, format: string, args: ..any) {
	hud.console_add(&match.hud.feed, hud.WARNING_COLOR, fmt.tprintf(format, ..args))
}
