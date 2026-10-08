package launcher

// An update, weighed from three things the launcher knows:
//
//   the latest release's manifest   what the install should be
//   the files on disk               what the install is
//   the installed manifest          what the install was last brought up to
//
// A file the latest release lists that is missing on disk, or whose hash differs, is
// fetched: so an update repairs as it goes. A file the installed manifest lists that the
// latest doesn't is the old release's, dropped, and deleted. What neither manifest lists
// is the player's (the configs, their own mods beside mods/classic, demos, their
// scripts) and never touched.

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"

import res "../../core/resources"
import "../../core/utils"

when ODIN_OS == .Windows {
	LAUNCHER :: "soldatreloaded-launcher.exe"
} else {
	LAUNCHER :: "soldatreloaded-launcher"
}

Plan :: struct {
	fetch:  [dynamic]res.Manifest_File, // missing or changed on disk
	remove: [dynamic]string,            // the old release's, dropped by the latest
}

// The files on disk as hashed so far, by path: each file's SHA-256, "" if it is missing.
// The integrity check fills it and the plan reads it, so no file is hashed twice.
Disk :: map[string]string

// The installed manifest's files that are missing or changed on disk, by path.
check_integrity :: proc(installed: res.Manifest, disk: ^Disk) -> (damaged: [dynamic]string) {
	damaged = make([dynamic]string, context.temp_allocator)
	for file in installed.files {
		if !on_disk(file, disk) do append(&damaged, file.path)
	}
	return
}

plan_update :: proc(installed, latest: res.Manifest, disk: ^Disk = nil) -> (plan: Plan) {
	plan.fetch = make([dynamic]res.Manifest_File, context.temp_allocator)
	plan.remove = make([dynamic]string, context.temp_allocator)
	disk := disk
	if disk == nil do disk = new_clone(make(Disk, context.temp_allocator), context.temp_allocator)

	for file in latest.files {
		if !on_disk(file, disk) do append(&plan.fetch, file)
	}

	kept := make(map[string]bool, context.temp_allocator)
	for file in latest.files do kept[file.path] = true
	for file in installed.files {
		if !kept[file.path] && os.exists(file.path) do append(&plan.remove, file.path)
	}
	return
}

// Whether the file on disk is the one the manifest lists, hashed once into `disk`.
on_disk :: proc(file: res.Manifest_File, disk: ^Disk) -> bool {
	hashed, seen := disk[file.path]
	if !seen {
		hashed = ""
		if data, err := os.read_entire_file(file.path, context.allocator); err == nil {
			hashed = sha256(data)
			delete(data)
		}
		disk[file.path] = hashed
	}
	return hashed != "" && hashed == file.sha256
}

// The files to fetch, out of the release's zip. The reason it couldn't, or "".
apply_fetch :: proc(plan: Plan, archive: []byte) -> string {
	entries, readable := utils.zip_entries(archive)
	if !readable do return "the release's zip couldn't be read"

	for file in plan.fetch {
		entry, found := entries[file.path]
		if !found do return fmt.tprintf("%s isn't in the release's zip", file.path)
		data, extracted := utils.zip_extract(archive, entry)
		if !extracted || sha256(data) != file.sha256 do return fmt.tprintf("%s came out of the zip damaged", file.path)
		if !install_file(file.path, data) do return fmt.tprintf("%s couldn't be written", file.path)
	}
	return ""
}

apply_remove :: proc(plan: Plan) {
	for path in plan.remove do os.remove(path)
}

// The installed manifest replaced with the release's, as published.
save_manifest :: proc(text: []byte) -> bool {
	return os.write_entire_file(res.MANIFEST_FILE, text) == nil
}

// A file written into the install, its directory made first. The launcher can't write
// over itself while it runs, but it may move itself aside: the old one is deleted when
// the new one next starts (remove_old_launcher).
install_file :: proc(path: string, data: []byte) -> bool {
	if dir := filepath.dir(path); dir != "." {
		os.make_directory_all(dir)
	}
	if path == LAUNCHER do os.rename(LAUNCHER, LAUNCHER + ".old")

	perm := os.Permissions_Read_All + {.Write_User}
	if path == LAUNCHER || path == GAME do perm += os.Permissions_Execute_All // on Linux, programs are marked so
	return os.write_entire_file(path, data, perm) == nil
}

remove_old_launcher :: proc() {
	os.remove(LAUNCHER + ".old")
}

sha256 :: proc(data: []byte) -> string {
	digest := hash.hash_bytes(.SHA256, data, context.temp_allocator)
	return string(hex.encode(digest, context.temp_allocator))
}
