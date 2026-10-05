package resources

import "core:log"

import "../utils"

// A release's list of the game's files on one platform (docs/git.md, "The manifest"):
// every file of an install, by its path from the install's root, its size and its
// SHA-256 in hex. A release publishes one for each platform, manifest.<platform>.json,
// and an install carries its own as manifest.json at its root, which the launcher
// replaces as it updates the install.

MANIFEST_FILE :: "manifest.json"

Manifest :: struct {
	version: string, // "0.1.0"
	files:   []Manifest_File,
}

Manifest_File :: struct {
	path:   string, // from the install's root, with forward slashes
	size:   i64,
	sha256: string, // in lower-case hex
}

// A manifest from its JSON; false, and logged, if it isn't one.
manifest_parse :: proc(text: []byte, allocator := context.allocator) -> (manifest: Manifest, ok: bool) {
	if !read_json(text, &manifest, allocator) {
		log.error("not a manifest")
		return {}, false
	}
	return manifest, true
}

// The manifest at `path`; false if there is none or it can't be read.
manifest_load :: proc(path: string, allocator := context.allocator) -> (manifest: Manifest, ok: bool) {
	if !utils.file_exists(path) do return {}, false
	text := utils.read_file(path, context.temp_allocator) or_return
	return manifest_parse(text, allocator)
}
