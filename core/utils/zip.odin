package utils

// The files out of a zip (a release's, for the launcher; a mod's, for the client), as zip
// and 7-Zip write them: stored or deflated, no encryption, no ZIP64 (neither is near
// 4 GB). A zip ends with its central directory, a record for each file saying where it
// is; the directory's own place is in the record that ends the zip.
//
//   [local header][data] [local header][data] ... [central directory] [end record]
//
// A zip in memory is read whole (zip_entries, zip_extract); a zip on disk, a mod's .smod,
// is opened (zip_open) and each file read from it as it is asked for (zip_read), so a
// large one isn't held in memory. Zips are written stored, uncompressed (zip_write_*):
// what is written is a mod's own art and sounds, mostly already compressed.

import "core:bytes"
import "core:compress/zlib"
import "core:encoding/endian"
import "core:hash"
import "core:os"
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
@(private = "file") END_SIZE :: 22
@(private = "file") MAX_COMMENT :: 65535

// Every file in the zip, by its path, with forward slashes; directories left out. With
// the temp allocator.
zip_entries :: proc(zip: []byte) -> (entries: map[string]Zip_Entry, ok: bool) {
	end := find_end_record(zip) or_return
	count := int(u16le(zip, end + 10))
	at := int(u32le(zip, end + 16)) // the central directory
	if at > len(zip) do return nil, false
	return central_entries(zip[at:], count, context.temp_allocator)
}

// A file's bytes, in the temp allocator.
zip_extract :: proc(zip: []byte, entry: Zip_Entry) -> (data: []byte, ok: bool) {
	at := entry.header
	if at + 30 > len(zip) || u32le(zip, at) != LOCAL_SIGNATURE do return nil, false
	start := at + 30 + int(u16le(zip, at + 26)) + int(u16le(zip, at + 28)) // past its name and extra
	if start + entry.packed_size > len(zip) do return nil, false
	return unpack(zip[start:][:entry.packed_size], entry, context.temp_allocator)
}

// A zip on disk, open: its files' places, and the file itself, read from as they are
// asked for. Close with zip_close.
Zip_File :: struct {
	file:    ^os.File,
	entries: map[string]Zip_Entry, // by path, as zip_entries has them
}

// The zip at `path`, open, its directory read; its names allocated with `allocator`.
// False if it can't be read, or isn't a zip.
zip_open :: proc(path: string, allocator := context.allocator) -> (z: Zip_File, ok: bool) {
	f, err := os.open(path)
	if err != nil do return
	defer if !ok do os.close(f)
	size, size_err := os.file_size(f)
	if size_err != nil || size < END_SIZE do return

	tail := make([]byte, min(int(size), END_SIZE + MAX_COMMENT), context.temp_allocator)
	tail_at := size - i64(len(tail))
	if n, _ := os.read_at(f, tail, tail_at); n != len(tail) do return
	end := find_end_record(tail) or_return
	count := int(u16le(tail, end + 10))
	dir_size := int(u32le(tail, end + 12))
	dir_at := i64(u32le(tail, end + 16))
	if dir_at + i64(dir_size) > size do return

	dir := make([]byte, dir_size, context.temp_allocator)
	if n, _ := os.read_at(f, dir, dir_at); n != dir_size do return
	z.entries = central_entries(dir, count, allocator) or_return
	z.file = f
	return z, true
}

zip_close :: proc(z: ^Zip_File, allocator := context.allocator) {
	for name in z.entries do delete(name, allocator)
	delete(z.entries)
	if z.file != nil do os.close(z.file)
	z^ = {}
}

// A file of the open zip, its bytes allocated with `allocator`.
zip_read :: proc(z: ^Zip_File, entry: Zip_Entry, allocator := context.allocator) -> (data: []byte, ok: bool) {
	header: [30]byte
	if n, _ := os.read_at(z.file, header[:], i64(entry.header)); n != len(header) || u32le(header[:], 0) != LOCAL_SIGNATURE do return
	start := i64(entry.header) + 30 + i64(u16le(header[:], 26)) + i64(u16le(header[:], 28))
	if entry.method == 0 {
		data = make([]byte, entry.packed_size, allocator)
		if n, _ := os.read_at(z.file, data, start); n != entry.packed_size {
			delete(data, allocator)
			return nil, false
		}
		return data, true
	}
	packed := make([]byte, entry.packed_size, context.temp_allocator)
	if n, _ := os.read_at(z.file, packed, start); n != entry.packed_size do return
	return unpack(packed, entry, allocator)
}

// A zip being written, stored, file by file, to disk: each file's place kept for the
// directory written at its end. Begun with zip_write_begin; ended, and the file closed,
// with zip_write_end.
Zip_Writer :: struct {
	file:    ^os.File,
	at:      int,
	central: bytes.Buffer,
	count:   int,
	failed:  bool,
}

// A new zip at `path`, over any file there. False if it can't be made.
zip_write_begin :: proc(w: ^Zip_Writer, path: string) -> bool {
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil do return false
	w^ = {file = f}
	bytes.buffer_init_allocator(&w.central, 0, 0)
	return true
}

// `data` as the zip's file `name` (forward slashes, below its root).
zip_write_add :: proc(w: ^Zip_Writer, name: string, data: []byte) {
	if w.failed do return
	crc := hash.crc32(data)
	header: [30]byte
	put_u32(header[:], 0, LOCAL_SIGNATURE)
	put_u16(header[:], 4, 10) // the version needed: 1.0, stored
	put_u32(header[:], 14, crc)
	put_u32(header[:], 18, u32(len(data)))
	put_u32(header[:], 22, u32(len(data)))
	put_u16(header[:], 26, u16(len(name)))
	write(w, header[:])
	write(w, transmute([]byte)name)
	write(w, data)

	central: [46]byte
	put_u32(central[:], 0, CENTRAL_SIGNATURE)
	put_u16(central[:], 4, 20) // made by: 2.0
	put_u16(central[:], 6, 10)
	put_u32(central[:], 16, crc)
	put_u32(central[:], 20, u32(len(data)))
	put_u32(central[:], 24, u32(len(data)))
	put_u16(central[:], 28, u16(len(name)))
	put_u32(central[:], 42, u32(w.at - len(header) - len(name) - len(data)))
	bytes.buffer_write(&w.central, central[:])
	bytes.buffer_write_string(&w.central, name)
	w.count += 1
}

// The directory and the end record written, and the file closed. False if anything of
// the zip couldn't be written.
zip_write_end :: proc(w: ^Zip_Writer) -> bool {
	defer bytes.buffer_destroy(&w.central)
	defer os.close(w.file)
	dir_at := w.at
	central := bytes.buffer_to_bytes(&w.central)
	write(w, central)
	end: [END_SIZE]byte
	put_u32(end[:], 0, END_SIGNATURE)
	put_u16(end[:], 8, u16(w.count))
	put_u16(end[:], 10, u16(w.count))
	put_u32(end[:], 12, u32(len(central)))
	put_u32(end[:], 16, u32(dir_at))
	write(w, end[:])
	return !w.failed
}

@(private = "file")
write :: proc(w: ^Zip_Writer, data: []byte) {
	if w.failed do return
	if n, err := os.write(w.file, data); err != nil || n != len(data) do w.failed = true
	w.at += len(data)
}

// The central directory's `count` records, from its first.
@(private = "file")
central_entries :: proc(dir: []byte, count: int, allocator := context.allocator) -> (entries: map[string]Zip_Entry, ok: bool) {
	entries = make(map[string]Zip_Entry, count, allocator)
	at := 0
	for _ in 0 ..< count {
		if at + 46 > len(dir) || u32le(dir, at) != CENTRAL_SIGNATURE do return entries, false
		name_size := int(u16le(dir, at + 28))
		extra_size := int(u16le(dir, at + 30))
		comment_size := int(u16le(dir, at + 32))
		if at + 46 + name_size > len(dir) do return entries, false

		name := string(dir[at + 46:][:name_size])
		name, _ = strings.replace_all(name, "\\", "/", context.temp_allocator)
		name = strings.trim_prefix(name, "./")
		if !strings.has_suffix(name, "/") && name not_in entries {
			entries[strings.clone(name, allocator)] = {
				method      = u16le(dir, at + 10),
				packed_size = int(u32le(dir, at + 20)),
				size        = int(u32le(dir, at + 24)),
				header      = int(u32le(dir, at + 42)),
			}
		}
		at += 46 + name_size + extra_size + comment_size
	}
	return entries, true
}

// A file's packed bytes as it was: stored, or inflated.
@(private = "file")
unpack :: proc(packed: []byte, entry: Zip_Entry, allocator := context.allocator) -> (data: []byte, ok: bool) {
	switch entry.method {
	case 0:
		if allocator == context.temp_allocator do return packed, true
		return bytes.clone(packed, allocator), true
	case 8:
		buf: bytes.Buffer
		bytes.buffer_init_allocator(&buf, 0, entry.size, allocator)
		if zlib.inflate_from_byte_array_raw(packed, &buf, expected_output_size = entry.size) != nil {
			bytes.buffer_destroy(&buf)
			return nil, false
		}
		return bytes.buffer_to_bytes(&buf), true
	}
	return nil, false
}

// The record that ends the zip: 22 bytes, then a comment of up to 65535.
@(private = "file")
find_end_record :: proc(zip: []byte) -> (at: int, ok: bool) {
	for at = len(zip) - END_SIZE; at >= max(0, len(zip) - END_SIZE - MAX_COMMENT); at -= 1 {
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

@(private = "file")
put_u16 :: proc(b: []byte, at: int, v: u16) {
	endian.unchecked_put_u16le(b[at:], v)
}

@(private = "file")
put_u32 :: proc(b: []byte, at: int, v: u32) {
	endian.unchecked_put_u32le(b[at:], v)
}
