package launcher

// The launcher: what a player starts. It brings the install up to the newest release,
// then starts the game and leaves. Its whole job, in order:
//
//   1. ask GitHub for the newest release, and that release's manifest for this platform
//   2. weigh it against the install: the files on disk, and the manifest the install
//      was last brought up to (update.odin)
//   3. bring what is missing or changed out of the release's zip, and delete what the
//      release dropped
//   4. start the game
//
// When the release can't be reached or the update fails, it says why and starts the
// game as it is. A console program, so a player sees what it is doing.
//
// It runs from the install's root, wherever it is started from.
//
//   release.odin   the newest release, its manifest and its zip, from GitHub
//   update.odin    what an update brings and deletes, and doing it
//   zip.odin       the files out of a release's zip
//   (downloads go through core/http)

import "core:fmt"
import "core:os"

import res "../../core/resources"

when ODIN_OS == .Windows {
	PLATFORM :: "windows"
	GAME :: "soldatreloaded.exe"
} else {
	PLATFORM :: "linux"
	GAME :: "soldatreloaded"
}

main :: proc() {
	enter_install()
	remove_old_launcher()

	fmt.println("Soldat Reloaded")
	if err := update(); err != "" {
		fmt.printfln("Could not update: %s", err)
		fmt.println("Starting the game as it is.")
	}

	if !launch_game() {
		fmt.printfln("Could not start %s. Reinstalling the game may help.", GAME)
		fmt.println("Press Enter to close.")
		buf: [1]byte
		_, _ = os.read(os.stdin, buf[:])
		os.exit(1)
	}
}

// The newest release's files brought into the install. The reason it couldn't, or "".
update :: proc() -> string {
	// Every release's install has its manifest; a folder without one (the source, a
	// developer's build) isn't an install, and isn't written over.
	installed, is_install := res.manifest_load(res.MANIFEST_FILE, context.temp_allocator)
	if !is_install do return "this isn't an install of a release (it has no manifest.json)"

	release, found := latest_release()
	if !found do return "the newest release couldn't be found"

	latest, latest_text, has_manifest := release_manifest(release)
	if !has_manifest do return fmt.tprintf("release %s has no manifest for %s", release.tag, PLATFORM)

	plan := plan_update(installed, latest)
	if len(plan.fetch) == 0 && len(plan.remove) == 0 {
		fmt.printfln("Up to date: %s.", latest.version)
		save_manifest(latest_text) // the install may have been brought up by hand
		return ""
	}

	fmt.printfln("Updating to %s: %d files to bring, %d to delete.", latest.version, len(plan.fetch), len(plan.remove))
	if len(plan.fetch) > 0 {
		archive, downloaded := release_archive(release, latest)
		if !downloaded do return fmt.tprintf("%s couldn't be downloaded", latest.archive)
		if err := apply_fetch(plan, archive); err != "" do return err
	}
	apply_remove(plan)
	if !save_manifest(latest_text) do return "the manifest couldn't be written"

	fmt.printfln("Updated to %s.", latest.version)
	return ""
}

// Into the directory the launcher is in: the install's root, whatever a shortcut to
// it says.
enter_install :: proc() {
	dir, err := os.get_executable_directory(context.temp_allocator)
	if err == nil do os.change_directory(dir)
}

// The game started on its own; the launcher doesn't wait for it.
launch_game :: proc() -> bool {
	if !os.exists(GAME) do return false
	_, err := os.process_start({command = {"./" + GAME}})
	return err == nil
}
