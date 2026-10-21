package hud

import "core:strings"

// A taunt's variables: {name} in a key's words is filled in as the key says them (the
// match's taunt_fill), {{name}} in capitals. What is filled in goes out between
// VAR_OPEN and VAR_CLOSE, which the console shows in the taunt variable colour and
// everything else leaves out. Typed text can't carry them: the text fields drop control
// characters.

VAR_OPEN :: '\x01'
VAR_CLOSE :: '\x02'
VAR_MARKS :: "\x01\x02"

Taunt_Var :: struct {
	name:  string,
	about: string, // what it fills in, for the taunt editor's list
}

// The variables, in the taunt editor's order.
@(rodata)
TAUNT_VARS := [?]Taunt_Var {
	{"time_left", "time left in the round"},
	{"caps_difference", "your team's caps minus the enemy's"},
	{"score", "the caps, your team's first"},
	{"team_caps", "your team's caps"},
	{"enemy_caps", "the enemy's caps"},
	{"cap_limit", "the caps that win"},
	{"my_caps", "your own caps"},
	{"kills", "your kills"},
	{"deaths", "your deaths"},
	{"kd", "kills per death"},
	{"killer", "who killed you last"},
	{"victim", "who you killed last"},
	{"health", "your health, percent"},
	{"weapon", "your weapon"},
	{"name", "your name"},
	{"team", "your team"},
	{"enemy_team", "the enemy team"},
	{"map", "the map"},
	{"server", "the server"},
	{"players", "players in the game"},
	{"ping", "your ping"},
	{"time", "your local time"},
}

// `text` without the variables' marks: for what can't colour them, the words over a
// player's head among them. For this frame.
unmarked :: proc(text: string) -> string {
	if strings.index_any(text, VAR_MARKS) < 0 do return text
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(text) {
		if text[i] != VAR_OPEN && text[i] != VAR_CLOSE do strings.write_byte(&b, text[i])
	}
	return strings.to_string(b)
}
