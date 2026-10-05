package utils

import "core:strings"

// Soldat's own INI files (a mod's mod.ini): `[Section]` headers and
// `Key=Value` lines, with `;` or `//` beginning a comment anywhere on a line. Soldat
// compares section and key names without regard to case, so callers should too
// (strings.equal_fold). The game's own configs are JSON (resources/config.odin); this
// is for the formats Soldat mods ship in, so a mod made for Soldat is taken up as it is.

Ini_Entry :: struct {
	section: string,
	key:     string,
	value:   string,
}

Ini_Iterator :: struct {
	text:    string,
	section: string,
}

ini_iterator :: proc(text: string) -> Ini_Iterator {
	return {text = text}
}

// The next key and value, with the section it is in; all pointing into the text.
ini_next :: proc(it: ^Ini_Iterator) -> (entry: Ini_Entry, ok: bool) {
	for raw in strings.split_lines_iterator(&it.text) {
		line := strip_comment(raw)
		if line == "" {
			continue
		}
		if line[0] == '[' {
			name := line[1:]
			if end := strings.index_byte(name, ']'); end >= 0 {
				name = name[:end]
			}
			it.section = strings.trim_space(name)
			continue
		}
		key, equals, value := strings.partition(line, "=")
		if equals == "" {
			continue // not an entry
		}
		return {it.section, strings.trim_space(key), strings.trim_space(value)}, true
	}
	return
}

@(private = "file")
strip_comment :: proc(line: string) -> string {
	line := line
	if i := strings.index_byte(line, ';'); i >= 0 {
		line = line[:i]
	}
	if i := strings.index(line, "//"); i >= 0 {
		line = line[:i]
	}
	return strings.trim_space(line)
}
