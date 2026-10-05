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
// gives, one of the same stem ending in `preferred_extension`. This is how Soldat finds
// its images: a map asking for "Tree.bmp" gets tree.png if there is one.
find_file_any_case :: proc(dir, name, preferred_extension: string, allocator := context.allocator) -> (path: string, ok: bool) {
	if name == "" {
		return
	}
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		return
	}

	preferred := strings.concatenate({filepath.stem(name), preferred_extension}, context.temp_allocator)
	found := ""
	for entry in entries {
		if entry.type == .Directory {
			continue
		}
		if strings.equal_fold(entry.name, preferred) {
			found = entry.name
			break
		}
		if strings.equal_fold(entry.name, name) {
			found = entry.name
		}
	}
	if found == "" {
		return
	}
	return strings.join({dir, found}, "/", allocator), true
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
