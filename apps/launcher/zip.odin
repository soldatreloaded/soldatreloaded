package launcher

// The files out of a release's zip, as zip and 7-Zip write them: stored or deflated, no
// encryption, no ZIP64 (a release is far from 4 GB). A zip ends with its central
// directory, a record for each file saying where it is; the directory's own place is in
// the record that ends the zip.
//
//   [local header][data] [local header][data] ... [central directory] [end record]

import "core:bytes"
import "core:compress/zlib"
import "core:encoding/endian"
import "core:strings"

Zip_Entry :: struct {
	method:      u16, // 0 stored, 8 deflated
	packed_size: int,
	size:        int,
	header:      int, // where its local header is
}

@(private = "file") END_SIGNATURE :: 0x06054b50
@(private = "file") CENTRAL_SIGNATURE :: 0x02014b50
@(private = "file") LOCAL_SIGNATURE :: 0x04034b50

// Every file in the zip, by its path, with forward slashes; directories left out.
zip_entries :: proc(zip: []byte) -> (entries: map[string]Zip_Entry, ok: bool) {
	end := find_end_record(zip) or_return
	count := int(u16le(zip, end + 10))
	at := int(u32le(zip, end + 16)) // the central directory

	entries = make(map[string]Zip_Entry, count, context.temp_allocator)
	for _ in 0 ..< count {
		if at + 46 > len(zip) || u32le(zip, at) != CENTRAL_SIGNATURE do return nil, false
		name_size := int(u16le(zip, at + 28))
		extra_size := int(u16le(zip, at + 30))
		comment_size := int(u16le(zip, at + 32))
		if at + 46 + name_size > len(zip) do return nil, false

		name := string(zip[at + 46:][:name_size])
		name, _ = strings.replace_all(name, "\\", "/", context.temp_allocator)
		name = strings.trim_prefix(name, "./")
		if !strings.has_suffix(name, "/") {
			entries[name] = {
				method      = u16le(zip, at + 10),
				packed_size = int(u32le(zip, at + 20)),
				size        = int(u32le(zip, at + 24)),
				header      = int(u32le(zip, at + 42)),
			}
		}
		at += 46 + name_size + extra_size + comment_size
	}
	return entries, true
}

// A file's bytes, in the temp allocator.
zip_extract :: proc(zip: []byte, entry: Zip_Entry) -> (data: []byte, ok: bool) {
	at := entry.header
	if at + 30 > len(zip) || u32le(zip, at) != LOCAL_SIGNATURE do return nil, false
	start := at + 30 + int(u16le(zip, at + 26)) + int(u16le(zip, at + 28)) // past its name and extra
	if start + entry.packed_size > len(zip) do return nil, false
	packed := zip[start:][:entry.packed_size]

	switch entry.method {
	case 0:
		return packed, true
	case 8:
		buf: bytes.Buffer
		bytes.buffer_init_allocator(&buf, 0, entry.size, context.temp_allocator)
		if zlib.inflate_from_byte_array_raw(packed, &buf, expected_output_size = entry.size) != nil do return nil, false
		return bytes.buffer_to_bytes(&buf), true
	}
	return nil, false
}

// The record that ends the zip: 22 bytes, then a comment of up to 65535.
@(private = "file")
find_end_record :: proc(zip: []byte) -> (at: int, ok: bool) {
	for at = len(zip) - 22; at >= max(0, len(zip) - 22 - 65535); at -= 1 {
		if u32le(zip, at) == END_SIGNATURE do return at, true
	}
	return 0, false
}

@(private = "file")
u16le :: proc(b: []byte, at: int) -> u16 {
	return endian.unchecked_get_u16le(b[at:])
}

@(private = "file")
u32le :: proc(b: []byte, at: int) -> u32 {
	return endian.unchecked_get_u32le(b[at:])
}
