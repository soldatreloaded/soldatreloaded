package utils

// A fixed-size string: a length byte, then room for N characters. Soldat's files hold
// their names in these, and so do the game's messages, which must not allocate.
Short_String :: struct($N: int) #packed {
	length: u8,
	chars:  [N]u8,
}

// The text a Short_String holds, pointing into it. Empty if its length is impossible.
short_string_text :: proc(s: ^Short_String($N)) -> string {
	if int(s.length) > N {
		return ""
	}
	text := s.chars[:s.length]
	for c, i in text {
		if c == 0 {
			return string(text[:i])
		}
	}
	return string(text)
}

// `text` into `s`, cut to what fits.
short_string_set :: proc(s: ^Short_String($N), text: string) {
	n := min(len(text), N)
	s^ = {}
	s.length = u8(n)
	copy(s.chars[:n], text[:n])
}

// A Short_String of N characters holding `text`, cut to what fits.
short_string :: proc($N: int, text: string) -> (s: Short_String(N)) {
	short_string_set(&s, text)
	return
}
