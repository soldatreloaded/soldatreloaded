package utils

// Reads fixed-layout values one after another out of a binary file. Reading past the
// end yields zeroes, as Soldat's own loaders do, so a truncated file reads as one whose
// remaining fields are empty rather than failing halfway.
Reader :: struct {
	data:     []byte,
	position: int,
}

// The next value of type T. Use the endian-explicit types (i32le, f32le) and
// `#packed` structs that mirror the file's layout.
read :: proc(r: ^Reader, $T: typeid) -> (value: T) {
	available := clamp(len(r.data) - r.position, 0, size_of(T))
	if available > 0 {
		bytes := ([^]byte)(&value)[:size_of(T)]
		copy(bytes, r.data[r.position:][:available])
	}
	r.position += size_of(T)
	return
}

skip :: proc(r: ^Reader, bytes: int) {
	r.position += bytes
}

// The next `count` values of type T, allocated.
read_slice :: proc(r: ^Reader, $T: typeid, count: int, allocator := context.allocator) -> []T {
	values := make([]T, count, allocator)
	for &value in values {
		value = read(r, T)
	}
	return values
}

