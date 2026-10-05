package network

import "base:intrinsics"
import "core:math"

import "../utils"

// The wire: what the client and the server say to each other, and how it is laid out.
// Transport is ENet (transport.odin), one unreliable channel and one reliable; this is
// the bits.
//
// One serializer serves both directions. A Buffer is writing or reading, and every
// net_* call writes the value it is given or reads into it, so a message has one
// routine that reads and writes it and cannot disagree with itself. Reading refuses
// what it cannot trust: bits past the end, a float that is not a number, a value past
// its range, a string too long. The buffer goes bad and stays bad, and the caller drops
// the message whole (buffer_ok). Writing a value that does not fit its width goes bad
// the same way, so a width chosen too small is found in a test, not on the wire.
//
// The bits go out least significant first, filling each byte from its low end.

MTU :: 1200 // a packet, so that nothing is fragmented

Buffer :: struct {
	data:     []u8,
	bit:      int,  // where the next bit goes, or comes from
	reading:  bool,
	overflow: bool, // writing past the end
	bad:      bool, // reading something untrustworthy, or writing what does not fit
}

// A writer over `data`, zeroed.
buffer_writer :: proc(data: []u8) -> Buffer {
	for &byte in data do byte = 0
	return {data = data}
}

buffer_reader :: proc(data: []u8) -> Buffer {
	return {data = data, reading = true}
}

// Nothing has gone wrong.
buffer_ok :: proc(b: ^Buffer) -> bool {
	return !b.overflow && !b.bad
}

// The bytes holding what was written, or read so far.
buffer_bytes :: proc(b: ^Buffer) -> int {
	return (b.bit + 7) / 8
}

// What was written, as a slice of the data.
buffer_written :: proc(b: ^Buffer) -> []u8 {
	return b.data[:buffer_bytes(b)]
}

// A reader that read everything: within the last byte's padding, and nothing wrong.
buffer_done :: proc(b: ^Buffer) -> bool {
	return buffer_ok(b) && b.reading && b.bit <= len(b.data) * 8 && len(b.data) * 8 - b.bit < 8
}

@(private = "file")
put_bits :: proc(b: ^Buffer, v: u32, bits: int) {
	for i in 0 ..< bits {
		if b.bit >= len(b.data) * 8 {
			b.overflow = true
			return
		}
		if v >> uint(i) & 1 != 0 {
			b.data[b.bit / 8] |= 1 << uint(b.bit % 8)
		}
		b.bit += 1
	}
}

@(private = "file")
get_bits :: proc(b: ^Buffer, bits: int) -> (v: u32) {
	for i in 0 ..< bits {
		if b.bit >= len(b.data) * 8 {
			b.bad = true
			return 0
		}
		if b.data[b.bit / 8] >> uint(b.bit % 8) & 1 != 0 {
			v |= 1 << uint(i)
		}
		b.bit += 1
	}
	return
}

// Unsigned in 1 to 32 bits.
net_bits :: proc(b: ^Buffer, v: ^u32, bits: int) {
	if b.reading {
		v^ = get_bits(b, bits)
	} else {
		if bits < 32 && v^ >> uint(bits) != 0 do b.bad = true // doesn't fit its width
		put_bits(b, v^, bits)
	}
}

// Signed in 2 to 32 bits, two's complement.
net_signed :: proc(b: ^Buffer, v: ^i32, bits: int) {
	if b.reading {
		raw := get_bits(b, bits)
		if bits < 32 && raw >> uint(bits - 1) & 1 != 0 { // sign-extend
			raw |= ~((1 << uint(bits)) - 1)
		}
		v^ = i32(raw)
	} else {
		lo, hi := -(i64(1) << uint(bits - 1)), (i64(1) << uint(bits - 1)) - 1
		if i64(v^) < lo || i64(v^) > hi do b.bad = true
		mask := u32(0xffffffff) if bits == 32 else (1 << uint(bits)) - 1
		put_bits(b, u32(v^) & mask, bits)
	}
}

net_bool :: proc(b: ^Buffer, v: ^bool) {
	bit := u32(1) if v^ else 0
	net_bits(b, &bit, 1)
	v^ = bit != 0
}

net_u8 :: proc(b: ^Buffer, v: ^u8) {
	x := u32(v^)
	net_bits(b, &x, 8)
	v^ = u8(x)
}

net_u16 :: proc(b: ^Buffer, v: ^u16) {
	x := u32(v^)
	net_bits(b, &x, 16)
	v^ = u16(x)
}

net_u32 :: proc(b: ^Buffer, v: ^u32) {
	net_bits(b, v, 32)
}

net_u64 :: proc(b: ^Buffer, v: ^u64) {
	lo, hi := u32(v^), u32(v^ >> 32)
	net_bits(b, &lo, 32)
	net_bits(b, &hi, 32)
	v^ = u64(hi) << 32 | u64(lo)
}

// The bits a value up to `max` needs.
bits_for :: proc(max: u32) -> int {
	bits := 1
	for bits < 32 && max >> uint(bits) != 0 do bits += 1
	return bits
}

// 0 to `max`, in as few bits as max needs; reading past max is bad.
net_range :: proc(b: ^Buffer, v: ^u32, max: u32) {
	if !b.reading && v^ > max do b.bad = true
	net_bits(b, v, bits_for(max))
	if b.reading && v^ > max do b.bad = true
}

// An enum, in as few bits as its last value needs.
net_enum :: proc(b: ^Buffer, v: ^$E) where intrinsics.type_is_enum(E) {
	x := u32(v^)
	net_range(b, &x, u32(max(E)))
	v^ = E(x)
}

// 32 bits; reading a NaN or an infinity is bad.
net_f32 :: proc(b: ^Buffer, v: ^f32) {
	raw := transmute(u32)v^
	net_bits(b, &raw, 32)
	v^ = transmute(f32)raw
	if b.reading && (math.is_nan(v^) || math.is_inf(v^)) do b.bad = true
}

net_vec2 :: proc(b: ^Buffer, v: ^utils.Vec2) {
	net_f32(b, &v.x)
	net_f32(b, &v.y)
}

// Up to N characters, with the length first; reading a longer one is bad.
net_string :: proc(b: ^Buffer, s: ^utils.Short_String($N)) {
	length := u32(s.length)
	net_bits(b, &length, 8)
	if int(length) > N {
		b.bad = true
		return
	}
	s.length = u8(length)
	for i in 0 ..< int(length) do net_u8(b, &s.chars[i])
	if b.reading {
		for i in int(length) ..< N do s.chars[i] = 0
	}
}
