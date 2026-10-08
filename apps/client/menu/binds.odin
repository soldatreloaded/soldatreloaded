package menu

import "core:fmt"
import "core:strings"

import res "../../../core/resources"

// The keys and the taunts, as the config's binds: a key's name to the command it runs.
// An empty command lets a key go (one of the game's own among them), so a key is unbound
// by binding it to nothing. From the C client's ui/mainmenu.c (key_of, rebind) and
// ui/taunts.c.

// The keys bound to `command`, two of them, "" where there are fewer: what the controls
// page shows on a control's two chips. The game's own key for it comes first while it is
// still bound to it, so a key added beside it doesn't take its place; the rest by name.
keys_of :: proc(config: ^res.Client_Config, command: string) -> (keys: [2]string) {
	first := ""
	for bind in res.DEFAULT_BINDS {
		if bind[1] == command && config.binds[bind[0]] == command do first = bind[0]
	}
	for key, bound in config.binds {
		if bound != command || key == first do continue
		switch {
		case keys[0] == "" || key < keys[0]: keys[1], keys[0] = keys[0], key
		case keys[1] == "" || key < keys[1]: keys[1] = key
		}
	}
	if first != "" do keys[1], keys[0] = keys[0], first
	return
}

// A control's chip set: its key, `was`, let go, and `key` ("" for none) doing `command`
// in its place. A key doing something else does this instead; the other chip's key, and
// any further key of `command`'s written in the config by hand, stay as they are.
set_key :: proc(menu: ^Menu, was, key, command: string) {
	if was != "" && was != key do bind(menu, was, "")
	if key != "" do bind(menu, key, command)
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
// `alt+q = "say_team Cover me!"` is a taunt, and so is a radio call: `alt+1 = "radio 1 2"`
// makes the "Enemy flagger, middle!" call, the same as the radio menu does (a bind
// written by hand with words after the call loses them here); and so is an emote:
// `alt+v = "emote victory"` cheers, as /victory does, and says nothing. A slot holds one
// taunt: setting it unbinds the slot's other modifiers. The message loses what a console
// line can't carry: `"` ends a quoted word, `;` ends a command, and `//` comments the
// rest of the line away (it becomes a space).

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

// What the key does: says its message to everyone or to the team, makes a radio call, or
// does an emote.
Taunt_Mode :: enum {
	Chat,
	Team,
	Radio,
	Emote,
}

// The emotes a key can do, as the game names them (/victory) and as the editor lists them.
Emote :: struct {
	name:  string,
	title: string,
}

@(rodata)
EMOTES := [?]Emote {
	{"tabac", "Chew tobacco"},
	{"smoke", "Smoke a cigar"},
	{"takeoff", "Take off helmet"},
	{"victory", "Victory"},
	{"breakdown", "Breakdown"},
	{"dab", "Dab"},
	{"yeah", "Yeah"},
	{"piss", "Piss"},
	{"mercy", "Mercy (press twice; costs a kill)"},
	{"pwn", "Pwn"},
}

Taunt :: struct {
	slot:     int, // its key's place in TAUNT_SLOT_KEYS
	modifier: Taunt_Modifier,
	mode:     Taunt_Mode,
	text:     string, // the message, Chat and Team's
	radio:    int,    // Radio's call: (call - 1) * 3 + place, 1 to 9
	emote:    int,    // Emote's, its place in EMOTES
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

		// a radio call: radio <call> <place>, any words after them left out
		if len(text) >= 5 && strings.equal_fold(text[:5], "radio") {
			rest := text[5:]
			call, place: int
			ok: bool
			if call, rest, ok = radio_digit(rest); ok {
				if place, rest, ok = radio_digit(rest); ok && (rest == "" || rest[0] == ' ') {
					taunt.mode = .Radio
					taunt.radio = (call - 1) * 3 + place
					return taunt, true
				}
			}
		}
		// an emote: emote <name>, one of EMOTES
		if rest, is := word_after(text, "emote"); is {
			for emote, i in EMOTES {
				if !strings.equal_fold(rest, emote.name) do continue
				taunt.mode = .Emote
				taunt.emote = i
				return taunt, true
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

// The bind's text for a taunt: `say` or `say_team` and the message,
// `radio <call> <place>`, the radio menu's call, or `emote <name>`. For this frame.
taunt_compose :: proc(mode: Taunt_Mode, text: string, radio: int, emote: int) -> string {
	if mode == .Radio do return fmt.tprintf("radio %d %d", (radio - 1) / 3 + 1, (radio - 1) % 3 + 1)
	if mode == .Emote do return fmt.tprintf("emote %s", EMOTES[clamp(emote, 0, len(EMOTES) - 1)].name)
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
	if mode == .Team do return fmt.tprintf("say_team %s", message)
	return fmt.tprintf("say %s", message)
}

// The slot's `modifier` combo bound to `text` ("" unbinds it), the slot's other combos
// unbound, so the slot holds this one taunt.
taunt_set :: proc(menu: ^Menu, slot: int, modifier: Taunt_Modifier, text: string) {
	for m in Taunt_Modifier do bind(menu, taunt_combo(slot, m), text if m == modifier else "")
}

