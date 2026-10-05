package utils

import "core:fmt"
import "core:strconv"
import "core:strings"

// Channels in .r .g .b .a order.
Rgba :: [4]u8

// Soldat's binary files store colours blue first.
Bgra :: [4]u8

rgba_from_bgra :: proc(c: Bgra) -> Rgba {
	return c.zyxw
}

// "RRGGBB" in hex, with or without a '#' first: the form the configs write colours in.
// Always opaque.
parse_hex_color :: proc(text: string) -> (color: Rgba, ok: bool) {
	hex := strings.trim_prefix(text, "#")
	if len(hex) != 6 {
		return
	}
	for i in 0 ..< 3 {
		channel := strconv.parse_uint(hex[2 * i:][:2], 16) or_return
		color[i] = u8(channel)
	}
	color.a = 255
	return color, true
}

// The "RRGGBB" parse_hex_color reads, allocated with the temp allocator.
format_hex_color :: proc(color: Rgba) -> string {
	return fmt.tprintf("%02X%02X%02X", color.r, color.g, color.b)
}
