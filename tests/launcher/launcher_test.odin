package launcher_test

// The launcher (apps/launcher): a release's zip read (core/utils/zip.odin), stored and
// deflated; an update weighed from the two manifests and the files on disk. Nothing here
// reaches GitHub.
//
//   odin test tests/launcher

import "core:os"
import "core:testing"

import "../../apps/launcher"
import res "../../core/resources"
import "../../core/utils"

// A zip made with Info-ZIP: data/stored.txt stored (zip -0), deflated.txt deflated.
FIXTURE :: #load("fixture.zip")

@(test)
zip_reads_stored_and_deflated :: proc(t: ^testing.T) {
	zip := FIXTURE
	entries, ok := utils.zip_entries(zip)
	testing.expect(t, ok && len(entries) == 2, "both files, and the directory left out")

	stored, has_stored := entries["data/stored.txt"]
	deflated, has_deflated := entries["deflated.txt"]
	testing.expect(t, has_stored && stored.method == 0, "a stored file, by its path")
	testing.expect(t, has_deflated && deflated.method == 8, "and a deflated one")

	text, extracted := utils.zip_extract(zip, stored)
	testing.expect(t, extracted && string(text) == "stored as it is\n", "a stored file comes out as it went in")

	text, extracted = utils.zip_extract(zip, deflated)
	testing.expect(t, extracted && len(text) == 1341, "a deflated one at its size")
	testing.expect_value(t, launcher.sha256(text), "34a5fed655f4f5f780e79b411523e010e9630a22ff406345792b8d4c6662bb7c")

	_, not_zip := utils.zip_entries(transmute([]byte)string("not a zip at all, and long enough to look"))
	testing.expect(t, !not_zip, "what isn't a zip is said so")
}

// A release's file is found in its zip's Soldat Reloaded folder, and only there.
@(test)
archive_folder :: proc(t: ^testing.T) {
	entries := make(map[string]utils.Zip_Entry, context.temp_allocator)
	entries[launcher.ARCHIVE_FOLDER + "data/in_folder.txt"] = {size = 1}
	entries["data/at_top.txt"] = {size = 2}
	in_folder, found_in_folder := launcher.archive_entry(entries, "data/in_folder.txt")
	_, found_at_top := launcher.archive_entry(entries, "data/at_top.txt")
	testing.expect(t, found_in_folder && in_folder.size == 1, "a file in the folder")
	testing.expect(t, !found_at_top, "and not one outside it")
}

@(test)
plan_from_two_manifests_and_the_disk :: proc(t: ^testing.T) {
	// a scratch install, entered as the launcher enters its own
	temp, _ := os.temp_directory(context.temp_allocator)
	dir := utils.temp_path(temp, "soldatreloaded_launcher_test")
	os.remove_all(dir)
	os.make_directory_all(utils.temp_path(dir, "data"))
	was, _ := os.get_working_directory(context.temp_allocator)
	os.change_directory(dir)
	defer {
		os.change_directory(was)
		os.remove_all(dir)
	}

	write :: proc(path, text: string) {_ = os.write_entire_file(path, text)}
	file :: proc(path, text: string) -> res.Manifest_File {
		return {path = path, size = i64(len(text)), sha256 = launcher.sha256(transmute([]byte)text)}
	}
	write("data/same.txt", "the same")
	write("data/changed.txt", "changed by hand")
	write("data/dropped.txt", "the old release's")
	write("config.json", "the player's")

	installed := res.Manifest {
		files = {file("data/same.txt", "the same"), file("data/changed.txt", "as released"), file("data/dropped.txt", "the old release's")},
	}
	latest := res.Manifest {
		files = {file("data/same.txt", "the same"), file("data/changed.txt", "as released"), file("data/new.txt", "new")},
	}
	// the integrity check names what the install's manifest has that the disk doesn't,
	// and the plan reads the files as it hashed them
	disk := make(launcher.Disk, context.temp_allocator)
	damaged := launcher.check_integrity(installed, &disk)
	testing.expectf(t, len(damaged) == 1 && damaged[0] == "data/changed.txt", "the changed file is named, the rest are intact (%v)", damaged)
	testing.expect_value(t, len(disk), 3)
	plan := launcher.plan_update(installed, latest, &disk)
	testing.expect_value(t, len(disk), 4) // and only the new file was hashed since

	fetched := make([dynamic]string, context.temp_allocator)
	for f in plan.fetch do append(&fetched, f.path)
	testing.expectf(t, len(fetched) == 2 && fetched[0] == "data/changed.txt" && fetched[1] == "data/new.txt", "the changed and the missing are fetched, the same left (%v)", fetched)
	testing.expectf(t, len(plan.remove) == 1 && plan.remove[0] == "data/dropped.txt", "what the release dropped is deleted, the player's file not (%v)", plan.remove)

	// brought up to date, there is nothing more to do
	launcher.install_file("data/changed.txt", transmute([]byte)string("as released"))
	launcher.install_file("data/new.txt", transmute([]byte)string("new"))
	launcher.apply_remove(plan)
	again := launcher.plan_update(latest, latest)
	testing.expect(t, len(again.fetch) == 0 && len(again.remove) == 0, "an install as the release has it needs nothing")
	testing.expect(t, !os.exists("data/dropped.txt") && os.exists("config.json"), "and the player's file is where it was")
}

@(test)
manifest_parses :: proc(t: ^testing.T) {
	text := `{"version": "0.1.0", "files": [{"path": "data/maps/ctf_Ash.pms", "size": 12, "sha256": "ab"}]}`
	manifest, ok := res.manifest_parse(transmute([]byte)text, context.temp_allocator)
	testing.expect(t, ok && manifest.version == "0.1.0" && len(manifest.files) == 1, "a manifest reads")
	testing.expect(t, ok && manifest.files[0].path == "data/maps/ctf_Ash.pms" && manifest.files[0].size == 12, "with its files")

	logger := context.logger
	context.logger.lowest_level = .Fatal // the error is expected; the runner fails a test that logs one
	_, bad := res.manifest_parse(transmute([]byte)string("{nope"), context.temp_allocator)
	context.logger = logger
	testing.expect(t, !bad, "and what isn't one doesn't")
}
