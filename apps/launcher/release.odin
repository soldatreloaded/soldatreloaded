package launcher

// The newest release, as GitHub serves it: a release's files are at fixed addresses under
// releases/latest/download/, which move on to each new release as it is published (not
// to a pre-release). Two of them are the launcher's (docs/git.md, "Releases"):
//
//   manifest.<platform>.json        every file of the game on this platform
//   soldatreloaded-<platform>.zip   the game for this platform, which those files are in

import "core:fmt"

import "../../core/http"
import res "../../core/resources"

REPOSITORY :: "soldatreloaded/soldatreloaded-odin"
LATEST_URL :: "https://github.com/" + REPOSITORY + "/releases/latest/download/"
MANIFEST :: "manifest." + PLATFORM + ".json"
ARCHIVE :: "soldatreloaded-" + PLATFORM + ".zip"
AGENT :: "soldatreloaded-launcher" // what the requests say they are

// The newest release's manifest for this platform, and its text as published, to keep as
// the install's once the install is brought up to it.
latest_manifest :: proc() -> (manifest: res.Manifest, text: []byte, ok: bool) {
	text = download(LATEST_URL + MANIFEST) or_return
	manifest = res.manifest_parse(text, context.temp_allocator) or_return
	return manifest, text, true
}

// The newest release's zip of the game for this platform.
latest_archive :: proc() -> (archive: []byte, ok: bool) {
	fmt.printfln("Downloading %s...", ARCHIVE)
	return download(LATEST_URL + ARCHIVE)
}

// The file at `url`, in the temp allocator.
download :: proc(url: string) -> ([]byte, bool) {
	return http.get(url, AGENT, context.temp_allocator)
}
