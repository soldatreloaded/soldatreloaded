package menu

import "core:fmt"
import "core:strings"

import res "../../../core/resources"

// The keys and the taunts, as the config's binds: a key's name to the command it runs.
// An empty command lets a key go (one of the game's own among them), so a key is unbound
// by binding it to nothing. From the C client's ui/mainmenu.c (key_of, rebind) and
// ui/taunts.c.

// The key bound to `command`, the first by name if several; "" if none.
key_of :: proc(config: ^res.Client_Config, command: string) -> string {
	found := ""
	for key, bound in config.binds {
		if bound == command && (found == "" || key < found) do found = key
	}
	return found
}

// `key` does `command` now, and nothing else does.
rebind :: proc(menu: ^Menu, key, command: string) {
	binds := &menu.config.binds
	old := make([dynamic]string, context.temp_allocator)
	for k, bound in binds do if bound == command do append(&old, k)
	for k in old do binds[k] = ""
	bind(menu, key, command)
}

// `key` bound to `command`; "" unbinds it.
bind :: proc(menu: ^Menu, key, command: string) {
	binds := &menu.config.binds
	if key in binds {
		binds[key] = strings.clone(command, config_allocator(menu))
	} else if command != "" { // a key bound to nothing that isn't bound needs no word
		binds[strings.clone(key, config_allocator(menu))] = strings.clone(command, config_allocator(menu))
	}
}

// ---------------------------------------------------------------------------------
// The taunts: a modifier and a key, the message said when they are pressed.
// `alt+q = "say_team Cover me!"` is a taunt, and so is one whose text runs as a radio
// call: `alt+1 = "radio 1 2 Base!"` says "Base!" to the team as the "Enemy flagger,
// middle!" call, with its sound. A slot holds one taunt: setting it unbinds the slot's
// other modifiers. The message loses what a console line can't carry: `"` ends a quoted
// word, `;` ends a command, and `//` comments the rest of the line away (it becomes a
// space).

TAUNT_SLOTS :: 36

// The taunt keys, as the editor's keyboard shows them: the number row, then the qwerty
// rows, the original's Alt+1..0 and Alt+Q..P.
@(rodata)
TAUNT_SLOT_KEYS := [TAUNT_SLOTS]string {
	"1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
	"q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
	"a", "s", "d", "f", "g", "h", "j", "k", "l",
	"z", "x", "c", "v", "b", "n", "m",
}

Taunt_Modifier :: enum {
	Alt,
	Ctrl,
	Shift,
}

@(rodata)
TAUNT_MODIFIER_KEYS := [Taunt_Modifier]string {
	.Alt   = "alt",
	.Ctrl  = "ctrl",
	.Shift = "shift",
}

// Who hears the message: everyone, or the team (a radio call's goes to the team).
Taunt_Mode :: enum {
	Chat,
	Team,
}

Taunt :: struct {
	slot:     int, // its key's place in TAUNT_SLOT_KEYS
	modifier: Taunt_Modifier,
	mode:     Taunt_Mode,
	text:     string, // the message, a radio call's own words
	radio:    int,    // 0 none, else the call: (call - 1) * 3 + place, 1 to 9
}

// The bind's key for a slot and a modifier: "alt+q".
taunt_combo :: proc(slot: int, modifier: Taunt_Modifier) -> string {
	return fmt.tprintf("%s+%s", TAUNT_MODIFIER_KEYS[modifier], TAUNT_SLOT_KEYS[slot])
}

// The taunt bound to `slot`, its modifiers tried in order. A bind that is no taunt (a
// control on the combo, say) is passed over: the controls page owns those.
taunt_at :: proc(config: ^res.Client_Config, slot: int) -> (taunt: Taunt, found: bool) {
	for modifier in Taunt_Modifier {
		text, bound := res.client_config_bind(config, taunt_combo(slot, modifier))
		if !bound do continue
		taunt = {slot = slot, modifier = modifier}

		// a radio taunt: radio <call> <place> <words>, the words said as that call
		if len(text) >= 5 && strings.equal_fold(text[:5], "radio") {
			rest := text[5:]
			call, place: int
			ok: bool
			if call, rest, ok = radio_digit(rest); ok {
				if place, rest, ok = radio_digit(rest); ok && (rest == "" || rest[0] == ' ') {
					taunt.mode = .Team // the call goes to the team
					taunt.radio = (call - 1) * 3 + place
					taunt.text = strings.trim_left(rest, " ")
					return taunt, true
				}
			}
		}
		// a said one: `say` to everyone, `say_team` to the team, then the message
		if rest, is := word_after(text, "say_team"); is {
			taunt.mode = .Team
			taunt.text = rest
			return taunt, true
		}
		if rest, is := word_after(text, "say"); is {
			taunt.mode = .Chat
			taunt.text = rest
			return taunt, true
		}
	}
	return {}, false

	// `word` leading `text`, any case, and a space or the end after it: what follows.
	word_after :: proc(text, word: string) -> (rest: string, ok: bool) {
		if len(text) < len(word) || !strings.equal_fold(text[:len(word)], word) do return
		rest = text[len(word):]
		if rest != "" && rest[0] != ' ' do return "", false
		return strings.trim_left(rest, " "), true
	}
	// A call's or a place's digit, 1 to 3, after its spaces.
	radio_digit :: proc(text: string) -> (digit: int, rest: string, ok: bool) {
		rest = strings.trim_left(text, " ")
		if rest == "" || rest[0] < '1' || rest[0] > '3' do return
		return int(rest[0] - '0'), rest[1:], true
	}
}

// The bind's text for a taunt: `say` or `say_team` and the message, or
// `radio <call> <place>` and the message, said as that call to the team. For this
// frame.
taunt_compose :: proc(mode: Taunt_Mode, text: string, radio: int) -> string {
	clean := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(text); i += 1 {
		switch {
		case text[i] == '"' || text[i] == ';':
		case text[i] == '/' && i + 1 < len(text) && text[i + 1] == '/':
			strings.write_byte(&clean, ' ')
			i += 1
		case:
			strings.write_byte(&clean, text[i])
		}
	}
	message := strings.to_string(clean)
	if radio >= 1 && radio <= 9 do return fmt.tprintf("radio %d %d %s", (radio - 1) / 3 + 1, (radio - 1) % 3 + 1, message)
	if mode == .Team do return fmt.tprintf("say_team %s", message)
	return fmt.tprintf("say %s", message)
}

// The slot's `modifier` combo bound to `text` ("" unbinds it), the slot's other combos
// unbound, so the slot holds this one taunt.
taunt_set :: proc(menu: ^Menu, slot: int, modifier: Taunt_Modifier, text: string) {
	for m in Taunt_Modifier do bind(menu, taunt_combo(slot, m), text if m == modifier else "")
}

