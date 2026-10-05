package ui

import "core:unicode/utf8"

import rl "vendor:raylib"

// A text field's typing: the field with the keyboard (by the identity of what it edits),
// and its text while typed. What is typed or pasted (Ctrl+V) goes in as far as the field
// takes, control characters left out; Backspace takes the last letter, or the whole text
// once Ctrl+A or a double click selected it all; Tab goes on to the next widget (back
// with Shift), Enter and Escape let the keyboard go. The field takes its new text on its
// next pass (field_box), so what shows it follows as it is typed.

EDIT_MAX :: 256 // a field's text at most, in bytes
DOUBLE_CLICK :: 0.4 // seconds between the clicks that select a text box's text, or join a row

Edit :: struct {
	key:        rawptr, // what the field with the keyboard edits; nil for none
	buffer:     [EDIT_MAX]u8,
	length:     int,
	max:        int,    // bytes the field takes
	select_all: bool,   // the text is all selected: the next key, or Backspace, replaces it
	dirty:      rawptr, // the field whose text changed since it last took it
	entered:    rawptr, // the field Enter was pressed in, for its page to act on
	clicked:    rawptr, // the text box last clicked, and when, for a double click on it
	clicked_at: f64,
}

// The field over `key` takes the keyboard, `value` its text.
edit_begin :: proc(k: ^Kit, key: rawptr, value: string, max: int) {
	e := &k.edit
	e.key = key
	e.length = copy(e.buffer[:], value)
	e.max = min(max, EDIT_MAX)
	e.select_all = false // the new edit starts unselected (a double click selects it after)
}

// No field has the keyboard.
edit_stop :: proc(k: ^Kit) {
	k.edit.key = nil
	k.edit.select_all = false // the field gone, its selection with it
}

edit_text :: proc(k: ^Kit) -> string {
	return string(k.edit.buffer[:k.edit.length])
}

// Whether Enter was pressed in the field over `key` since it was last asked.
edit_entered :: proc(k: ^Kit, key: rawptr) -> bool {
	if k.edit.entered != key do return false
	k.edit.entered = nil
	return true
}

// The keys, while a field has the keyboard: true if one has.
@(private = "package")
edit_input :: proc(k: ^Kit) -> bool {
	e := &k.edit
	if e.key == nil do return false
	ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	if ctrl && key_hit(.A) do e.select_all = true
	if ctrl && key_hit(.V) do edit_insert(k, string(rl.GetClipboardText()))
	for c := rl.GetCharPressed(); c != 0; c = rl.GetCharPressed() {
		bytes, n := utf8.encode_rune(c)
		edit_insert(k, string(bytes[:n]))
	}
	if key_hit(.BACKSPACE) {
		if e.select_all {
			e.length = 0 // the whole selection, gone at once
			e.select_all = false
		} else if e.length > 0 {
			_, size := utf8.decode_last_rune(e.buffer[:e.length])
			e.length -= size
		}
		e.dirty = e.key
	}
	if key_hit(.TAB) {
		edit_stop(k)
		kit_nav(k, -1 if shift else 1, 0, false, false)
	} else if key_hit(.ENTER) || key_hit(.KP_ENTER) {
		e.entered = e.key
		edit_stop(k)
	} else if key_hit(.ESCAPE) {
		edit_stop(k)
	}
	return true
}

@(private = "file")
edit_insert :: proc(k: ^Kit, str: string) {
	e := &k.edit
	if e.select_all { // all of it selected: the first key, or paste, replaces it
		e.length = 0
		e.select_all = false
	}
	for c in str {
		if c < 32 do continue
		bytes, n := utf8.encode_rune(c)
		if e.length + n > e.max do break
		copy(e.buffer[e.length:], bytes[:n])
		e.length += n
	}
	e.dirty = e.key
}
