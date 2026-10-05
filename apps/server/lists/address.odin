package lists

import "core:fmt"

import "../../../core/utils"

// The text forms of what names a player on the lists: an IPv4 address as ENet keeps it,
// and a machine's hardware ID.

HWID_DIGITS :: 11 // a hardware ID is this many hex digits

// Eleven hex digits, in capitals; empty for none.
Hwid :: utils.Short_String(HWID_DIGITS)

// "1.2.3.4" to ENet's form: the four bytes as they lie in memory, so a dotted address
// read on one machine matches ENet's own on the same. False if `text` isn't an IPv4
// address: four numbers of up to three digits each, 0 to 255, dots between, nothing
// else; a part beginning with 0 is the single digit, as ENet reads them.
address_parse :: proc(text: string) -> (host: u32, ok: bool) {
	bytes: [4]u8
	part := 0
	digits := 0
	value := 0
	for c, i in transmute([]u8)text {
		if c == '.' {
			if digits == 0 || part == 3 do return 0, false
			bytes[part] = u8(value)
			part += 1
			digits, value = 0, 0
			continue
		}
		if c < '0' || c > '9' || digits == 3 do return 0, false
		if digits == 1 && value == 0 do return 0, false // "01": ENet takes a 0 as the whole part
		value = value * 10 + int(c - '0')
		digits += 1
		if value > 255 do return 0, false
		if i == len(text) - 1 {
			if part != 3 do return 0, false
			bytes[part] = u8(value)
			return transmute(u32)bytes, true
		}
	}
	return 0, false
}

// And back: an address in ENet's form as "1.2.3.4".
address_text :: proc(host: u32, allocator := context.temp_allocator) -> string {
	bytes := transmute([4]u8)host
	return fmt.aprintf("%d.%d.%d.%d", bytes[0], bytes[1], bytes[2], bytes[3], allocator = allocator)
}

// Whether `text` is a hardware ID, eleven hex digits; it in capitals if so, as the lists
// keep them.
hwid_parse :: proc(text: string) -> (hwid: Hwid, ok: bool) {
	if len(text) != HWID_DIGITS do return {}, false
	for c, i in transmute([]u8)text {
		switch c {
		case '0' ..= '9', 'A' ..= 'F':
			hwid.chars[i] = c
		case 'a' ..= 'f':
			hwid.chars[i] = c - 'a' + 'A'
		case:
			return {}, false
		}
	}
	hwid.length = HWID_DIGITS
	return hwid, true
}

// A player's address and hardware ID as the lists and the console show them:
// "1.2.3.4 0A1B2C3D4E5", "-" for either they lack.
whom_text :: proc(host: u32, hwid: string, allocator := context.temp_allocator) -> string {
	ip := address_text(host, context.temp_allocator) if host != 0 else "-"
	return fmt.aprintf("%s %s", ip, hwid if hwid != "" else "-", allocator = allocator)
}
