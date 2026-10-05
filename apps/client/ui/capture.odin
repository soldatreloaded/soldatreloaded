package ui

import "core:fmt"

import rl "vendor:raylib"

import "../../../core/utils"
import "../input"

// A key waited for, to bind: whatever goes down next, a key, a mouse button or the
// wheel, named as the binds name it (input/keys.odin). A modifier (Shift, Ctrl, Alt)
// waits: let go alone, it is the key; held with another, the two are, as "shift+e",
// which the binds look up first. Escape, or a controller's B, gives up. While a key is
// waited for it takes every key and click.

Capture :: struct {
	owner:    int, // the widget waiting, -1 for none
	modifier: utils.Short_String(16), // pressed while it waits
	key:      utils.Short_String(32), // the key it got, for the owner to take
	done:     bool,
}

@(rodata)
MODIFIER_KEYS := [?]rl.KeyboardKey{.LEFT_SHIFT, .RIGHT_SHIFT, .LEFT_CONTROL, .RIGHT_CONTROL, .LEFT_ALT, .RIGHT_ALT}

capture_start :: proc(k: ^Kit, owner: int) {
	k.capture = {owner = owner}
}

capturing :: proc(k: ^Kit, owner: int) -> bool {
	return k.capture.owner == owner && !k.capture.done
}

// The modifier held while waiting, "" for none.
capture_modifier :: proc(k: ^Kit) -> string {
	return utils.short_string_text(&k.capture.modifier)
}

// The key `owner` waited for, once it is pressed.
capture_take :: proc(k: ^Kit, owner: int) -> (key: string, ok: bool) {
	c := &k.capture
	if c.owner != owner || !c.done do return
	c.owner = -1
	c.done = false
	return utils.short_string_text(&c.key), true
}

// The keys while a key is waited for: true if one is.
@(private = "package")
capture_input :: proc(k: ^Kit) -> bool {
	c := &k.capture
	if c.owner < 0 || c.done do return false
	if rl.IsKeyPressed(.ESCAPE) || (rl.IsGamepadAvailable(0) && rl.IsGamepadButtonPressed(0, .RIGHT_FACE_RIGHT)) {
		c.owner = -1
		return true
	}
	for key in MODIFIER_KEYS {
		name, _ := input.key_name(key)
		if rl.IsKeyPressed(key) && c.modifier.length == 0 do utils.short_string_set(&c.modifier, name)
		if rl.IsKeyReleased(key) && c.modifier.length > 0 {
			capture_done(c, capture_modifier(k))
			return true
		}
	}
	for key := rl.GetKeyPressed(); key != .KEY_NULL; key = rl.GetKeyPressed() {
		if is_modifier(key) do continue
		name := input.key_name(key) or_continue
		// the modifier held, named as the binds name it: Alt before Ctrl before Shift
		with := ""
		if input.modifier_down(.Alt) {
			with = "alt"
		} else if input.modifier_down(.Ctrl) {
			with = "ctrl"
		} else if input.modifier_down(.Shift) {
			with = "shift"
		}
		capture_done(c, fmt.tprintf("%s+%s", with, name) if with != "" else name)
		return true
	}
	for b in 0 ..= int(rl.MouseButton.EXTRA) { // mouse1 to mouse5
		button := rl.MouseButton(b)
		if !rl.IsMouseButtonPressed(button) do continue
		name, _ := input.key_name(button)
		capture_done(c, name)
		return true
	}
	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		capture_done(c, "mwheelup" if wheel > 0 else "mwheeldown")
	}
	return true

	is_modifier :: proc(key: rl.KeyboardKey) -> bool {
		for modifier in MODIFIER_KEYS do if key == modifier do return true
		return false
	}
}

@(private = "file")
capture_done :: proc(c: ^Capture, key: string) {
	utils.short_string_set(&c.key, key)
	c.modifier = {}
	c.done = true
}
