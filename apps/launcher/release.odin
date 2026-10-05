package launcher

// The newest release, as GitHub has it: its tag and the files attached to it, among them
// a manifest and a zip for each package and platform (docs/git.md, "Releases"). GitHub's
// "latest" is the newest published release that isn't a pre-release.

import "core:fmt"

import "../../core/http"
import res "../../core/resources"

REPOSITORY :: "soldatreloaded/soldatreloaded-odin"
AGENT :: "soldatreloaded-launcher" // what the requests say they are; GitHub wants one
LATEST_RELEASE_URL :: "https://api.github.com/repos/" + REPOSITORY + "/releases/latest"

Release :: struct {
	tag:    string `json:"tag_name"`, // "v0.1.0"
	assets: []Asset,
}

Asset :: struct {
	name: string,
	url:  string `json:"browser_download_url"`,
	size: i64,
}

latest_release :: proc() -> (release: Release, ok: bool) {
	text := download(LATEST_RELEASE_URL) or_return
	if !res.read_json(text, &release, context.temp_allocator) do return {}, false
	return release, true
}

// The release's manifest for the game on this platform, and its text as published, to
// keep as the install's once the install is brought up to it.
release_manifest :: proc(release: Release) -> (manifest: res.Manifest, text: []byte, ok: bool) {
	version := release.tag[1:] if len(release.tag) > 0 && release.tag[0] == 'v' else release.tag
	asset := find_asset(release, fmt.tprintf("soldatreloaded-%s-%s.manifest.json", version, PLATFORM)) or_return
	text = download(asset.url) or_return
	manifest = res.manifest_parse(text, context.temp_allocator) or_return
	return manifest, text, true
}

// The release's zip that the manifest's files are in.
release_archive :: proc(release: Release, manifest: res.Manifest) -> (archive: []byte, ok: bool) {
	asset := find_asset(release, manifest.archive) or_return
	fmt.printfln("Downloading %s (%.1f MB)...", asset.name, f64(asset.size) / (1024 * 1024))
	return download(asset.url)
}

find_asset :: proc(release: Release, name: string) -> (Asset, bool) {
	for asset in release.assets do if asset.name == name do return asset, true
	return {}, false
}

// The file at `url`, in the temp allocator.
download :: proc(url: string) -> ([]byte, bool) {
	return http.get(url, AGENT, context.temp_allocator)
}
