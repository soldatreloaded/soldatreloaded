package utils

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// A whole file, or false with the reason logged.
read_file :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
	err: os.Error
	data, err = os.read_entire_file(path, allocator)
	if err != nil {
		log.errorf("cannot read %s: %v", path, err)
		return nil, false
	}
	return data, true
}

// Joins path parts with '/', allocated with the temp allocator.
temp_path :: proc(parts: ..string) -> string {
	return strings.join(parts, "/", context.temp_allocator)
}

// The next line of `text`, trimmed of surrounding whitespace, and `text` moved past it.
// False when the text is used up.
next_line :: proc(text: ^string) -> (line: string, ok: bool) {
	raw := strings.split_lines_iterator(text) or_return
	return strings.trim_space(raw), true
}

// The files in `dir` (not its directories) whose names end in `extension`, compared
// without regard to case: their names without it, sorted. Empty if `dir` can't be read.
list_files :: proc(dir, extension: string, allocator := context.allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return nil
	}

	names := make([dynamic]string, allocator)
	for entry in entries {
		if entry.type == .Directory || len(entry.name) <= len(extension) {
			continue
		}
		stem := entry.name[:len(entry.name) - len(extension)]
		if strings.equal_fold(entry.name[len(stem):], extension) {
			append(&names, strings.clone(stem, allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// The file in `dir` named `name` whatever its case; preferring, whatever extension `name`
// gives, one of the same stem ending in `preferred_extension`; and failing both, one of
// the same stem that is a .bmp. This is how Soldat finds its images: a map asking for
// "Tree.bmp" gets tree.png if there is one, and an old mod's art, all .bmp, is found
// where a .png is asked for.
// With `listings`, each folder's files are read once and kept there for the next look in
// it: for loading many images from a few folders at once.
find_file_any_case :: proc(dir, name, preferred_extension: string, allocator := context.allocator, listings: ^Dir_Listings = nil) -> (path: string, ok: bool) {
	if name == "" {
		return
	}
	files := dir_files(dir, listings) or_return

	stem := filepath.stem(name)
	preferred := strings.concatenate({stem, preferred_extension}, context.temp_allocator)
	bitmap := strings.concatenate({stem, ".bmp"}, context.temp_allocator)
	found, as_bitmap := "", ""
	for file in files {
		if strings.equal_fold(file, preferred) {
			found = file
			break
		}
		if strings.equal_fold(file, name) {
			found = file
		} else if strings.equal_fold(file, bitmap) {
			as_bitmap = file
		}
	}
	if found == "" {
		found = as_bitmap
	}
	if found == "" {
		return
	}
	return strings.join({dir, found}, "/", allocator), true
}

// The files of folders, by the folder's path, as read once; kept with the allocator
// the map was made with, as is all it holds.
Dir_Listings :: map[string][]string

// The names of the files in `dir`, not its folders; from `listings` if it has them, and
// kept there if not. False if `dir` can't be read.
@(private = "file")
dir_files :: proc(dir: string, listings: ^Dir_Listings) -> (files: []string, ok: bool) {
	if listings != nil {
		if kept, found := listings[dir]; found do return kept, kept != nil
	}
	allocator := listings.allocator if listings != nil else context.temp_allocator
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err == nil {
		names := make([dynamic]string, 0, len(entries), allocator)
		for entry in entries {
			if entry.type != .Directory do append(&names, strings.clone(entry.name, allocator))
		}
		files = names[:]
	}
	if listings != nil do listings[strings.clone(dir, allocator)] = files // nil for a folder that isn't there: not read again
	return files, err == nil
}

// Writes `data` as the whole of the file at `path`. False, with the reason logged, if
// it can't be written.
write_file :: proc(path: string, data: []byte) -> bool {
	if err := os.write_entire_file(path, data); err != nil {
		log.errorf("cannot write %s: %v", path, err)
		return false
	}
	return true
}

file_exists :: proc(path: string) -> bool {
	return os.exists(path)
}
