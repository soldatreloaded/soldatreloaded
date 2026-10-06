package online

import "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"

import "../../../core/http"
import res "../../../core/resources"
import "../../../core/utils"

// The mods' catalogue: what the mods repository publishes (soldatreloaded-mods), its
// index (the client config's network.mods_index, a mods.json) listing each mod's newest
// version, where its zip is, its size and SHA-256. The index, and a mod installed from
// it, each come on a thread of their own, so a frame never waits on the web or on
// unpacking: a mod's zip is fetched, checked against its SHA-256, unpacked into a hidden
// folder of mods/, and only then put in its place, mods/<name>, over the version that
// was there. One mod is installed at a time. The Mods page reads it; nothing here draws.

Catalog_State :: enum {
	Idle,     // never asked
	Fetching, // the index asked for
	Ready,    // the index is in
	Failed,   // the index couldn't be had; `error` says why
}

// A mod the index lists.
Catalog_Mod :: struct {
	name:        string,
	version:     string,
	author:      string,
	description: string,
	licence:     string,
	source:      string,
	url:         string,
	size:        int,
	sha256:      string,
}

Install_State :: enum {
	None,
	Downloading, // `received` of its size so far
	Unpacking,
	Done,        // in its place: the mod's name says which
	Failed,      // `error` says why
}

Catalog :: struct {
	state:   Catalog_State,
	error:   string,
	mods:    []Catalog_Mod, // the index's, in its order
	fetch:   ^Index_Fetch,  // the index on its way, while fetching
	install: ^Install,      // the mod being installed, or the last one, until taken
}

// The index's request, on its thread.
@(private = "file")
Index_Fetch :: struct {
	thread: ^thread.Thread,
	done:   bool, // atomic: the thread's work is over, and what follows may be read
	url:    string,
	body:   []u8,
	ok:     bool,
}

// A mod's install, on its thread: what it installs, and how far it has got.
Install :: struct {
	thread:   ^thread.Thread,
	mod:      Catalog_Mod, // its own copy
	mods_dir: string,
	received: int,           // atomic: the zip's bytes so far
	state:    Install_State, // atomic
	error:    string,        // once failed
	taken:    bool,          // the Mods page has acted on its end (the main thread's alone)
}

// The index asked for anew from `url`; what was known of it forgotten.
catalog_refresh :: proc(c: ^Catalog, index_url: string) {
	fetch_stop(c)
	catalog_forget(c)
	url := strings.trim_space(index_url)
	if url == "" {
		catalog_fail(c, "there is no index to ask: network.mods_index is empty")
		return
	}
	f := new(Index_Fetch)
	f.url = strings.clone(url)
	f.thread = thread.create_and_start_with_data(f, proc(data: rawptr) {
		f := (^Index_Fetch)(data)
		f.body, f.ok = http.get(f.url, AGENT)
		sync.atomic_store(&f.done, true)
	})
	c.fetch = f
	c.state = .Fetching
}

// Each frame: the index taken when it comes.
catalog_pump :: proc(c: ^Catalog) {
	if c.state != .Fetching || !sync.atomic_load(&c.fetch.done) do return
	f := c.fetch
	c.fetch = nil
	defer index_fetch_free(f)
	if !f.ok {
		catalog_fail(c, "the mods' index couldn't be reached")
		return
	}
	Index :: struct {
		format: int,
		mods:   []Catalog_Mod,
	}
	index: Index
	if err := json.unmarshal(f.body, &index); err != nil || index.format != 1 {
		catalog_fail(c, "the mods' index isn't one this game reads")
		return
	}
	valid := make([dynamic]Catalog_Mod)
	for m in index.mods {
		if catalog_name_ok(m.name) && m.url != "" && len(m.sha256) == 64 {
			append(&valid, m)
		} else {
			log.warnf("the mods' index lists %q, which can't be installed; passed over", m.name)
			catalog_mod_free(m)
		}
	}
	delete(index.mods)
	c.mods = valid[:]
	c.state = .Ready
}

catalog_close :: proc(c: ^Catalog) {
	fetch_stop(c)
	catalog_forget(c)
	if c.install != nil {
		install_free(c.install) // waits out an install: closing during one is rare
		c.install = nil
	}
	c.state = .Idle
}

// The catalogue's mod `m` installed into `mods_dir`, on its own thread; nothing if an
// install is under way. Its progress is the catalogue's `install` until taken.
catalog_install :: proc(c: ^Catalog, m: Catalog_Mod, mods_dir: string) {
	if c.install != nil {
		if install_busy(c.install) do return
		install_free(c.install)
	}
	i := new(Install)
	i.mod = catalog_mod_clone(m)
	i.mods_dir = strings.clone(mods_dir)
	sync.atomic_store(&i.state, Install_State.Downloading)
	i.thread = thread.create_and_start_with_data(i, install_run)
	c.install = i
}

// Whether an install is under way.
install_busy :: proc(i: ^Install) -> bool {
	state := sync.atomic_load(&i.state)
	return state == .Downloading || state == .Unpacking
}

// An install's state, and how far its download is, 0 to 1.
install_progress :: proc(i: ^Install) -> (state: Install_State, done: f32) {
	state = sync.atomic_load(&i.state)
	done = f32(sync.atomic_load(&i.received)) / f32(max(i.mod.size, 1))
	return state, clamp(done, 0, 1)
}

// The version of the player's mod `name` in `mods_dir`, as its about.json says; empty if
// it has none, or isn't there.
installed_version :: proc(mods_dir, name: string) -> string {
	data, err := os.read_entire_file(utils.temp_path(mods_dir, name, "about.json"), context.temp_allocator)
	if err != nil do return ""
	About :: struct {
		version: string,
	}
	about: About
	if json.unmarshal(data, &about, allocator = context.temp_allocator) != nil do return ""
	return about.version
}

// ---------------------------------------------------------------------------------

// What a mod's install does, on its thread.
@(private = "file")
install_run :: proc(data: rawptr) {
	i := (^Install)(data)
	defer free_all(context.temp_allocator) // the thread's own: its zip and files, which would outlive it
	if why := install_do(i); why != "" {
		i.error = strings.clone(why)
		log.errorf("cannot install the mod %s: %s", i.mod.name, why)
		sync.atomic_store(&i.state, Install_State.Failed)
	} else {
		sync.atomic_store(&i.state, Install_State.Done)
	}
}

// The zip fetched, checked, unpacked beside the mods and put in its place. Why not, or
// "". Everything it allocates is the temp allocator's, which is the thread's own.
@(private = "file")
install_do :: proc(i: ^Install) -> string {
	context.allocator = context.temp_allocator
	m := &i.mod
	zip, ok := http.get(m.url, AGENT, context.temp_allocator, &i.received)
	if !ok do return "its download couldn't be had"
	if len(zip) != m.size || sha256(zip) != strings.to_lower(m.sha256, context.temp_allocator) {
		return "its download came damaged: try again"
	}
	sync.atomic_store(&i.state, Install_State.Unpacking)

	entries, readable := utils.zip_entries(zip)
	if !readable do return "its zip can't be read"
	// unpacked out of sight, in a folder the Mods page passes over, then moved in whole
	part := utils.temp_path(i.mods_dir, fmt.tprintf(".%s.part", m.name))
	os.remove_all(part)
	defer os.remove_all(part)
	for name, entry in entries {
		if !entry_name_ok(name) do return fmt.tprintf("its zip has a file it may not: %s", name)
		file, extracted := utils.zip_extract(zip, entry)
		if !extracted do return fmt.tprintf("its file %s couldn't be unpacked", name)
		path := utils.temp_path(part, name)
		os.make_directory_all(filepath.dir(path))
		if os.write_entire_file(path, file) != nil do return fmt.tprintf("its file %s couldn't be written", name)
	}
	dir := utils.temp_path(i.mods_dir, m.name)
	if os.exists(dir) && os.remove_all(dir) != nil do return "the version installed couldn't be replaced: is one of its files open?"
	if os.rename(part, dir) != nil do return "it couldn't be put in its place"
	return ""
}

// A name a mod's folder may have: as the mods repository allows, letters, digits, - and
// _, at most 32 of them; not Classic's, nor the old default's.
@(private = "file")
catalog_name_ok :: proc(name: string) -> bool {
	if name == "" || len(name) > res.MOD_NAME_MAX do return false
	for c in name {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') do return false
	}
	return !strings.equal_fold(name, res.MOD_CLASSIC) && !strings.equal_fold(name, "default")
}

// A zip's file a mod may have: a path inside its folder, never out of it.
@(private = "file")
entry_name_ok :: proc(name: string) -> bool {
	if name == "" || strings.has_prefix(name, "/") || strings.contains(name, ":") do return false
	for part in strings.split(name, "/", context.temp_allocator) {
		if part == "" || part == "." || part == ".." do return false
	}
	return true
}

@(private = "file")
sha256 :: proc(data: []byte) -> string {
	digest := hash.hash_bytes(.SHA256, data, context.temp_allocator)
	return string(hex.encode(digest, context.temp_allocator))
}

@(private = "file")
catalog_fail :: proc(c: ^Catalog, why: string) {
	c.state = .Failed
	delete(c.error)
	c.error = strings.clone(why)
}

@(private = "file")
catalog_forget :: proc(c: ^Catalog) {
	for m in c.mods do catalog_mod_free(m)
	delete(c.mods)
	c.mods = nil
	delete(c.error)
	c.error = ""
}

@(private = "file")
fetch_stop :: proc(c: ^Catalog) {
	if c.fetch != nil {
		index_fetch_free(c.fetch) // waits out the request: a refresh while fetching is rare
		c.fetch = nil
	}
}

@(private = "file")
index_fetch_free :: proc(f: ^Index_Fetch) {
	thread.join(f.thread)
	thread.destroy(f.thread)
	delete(f.body)
	delete(f.url)
	free(f)
}

@(private = "file")
install_free :: proc(i: ^Install) {
	thread.join(i.thread)
	thread.destroy(i.thread)
	catalog_mod_free(i.mod)
	delete(i.mods_dir)
	delete(i.error)
	free(i)
}

@(private = "file")
catalog_mod_clone :: proc(m: Catalog_Mod) -> Catalog_Mod {
	c := m
	for &s in ([]^string{&c.name, &c.version, &c.author, &c.description, &c.licence, &c.source, &c.url, &c.sha256}) {
		s^ = strings.clone(s^)
	}
	return c
}

@(private = "file")
catalog_mod_free :: proc(m: Catalog_Mod) {
	for s in ([]string{m.name, m.version, m.author, m.description, m.licence, m.source, m.url, m.sha256}) {
		delete(s)
	}
}
