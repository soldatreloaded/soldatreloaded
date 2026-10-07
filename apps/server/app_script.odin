package server

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

// The scripts beside the server (script.odin): every .lua in the folder server.config.mjson
// names (`scripts`), read in name order into one state as the server starts, pumped with
// it, and the console's script_reload and lua. A script is left out by its name: one
// renamed to .lua.disabled is passed over. The folder is the install's, from its root
// where the server runs. None ship with the server (the examples are in
// soldatreloaded-scripts), so the default's absence is nothing: the server runs without
// a script. One set by hand that isn't there is said.

app_start :: proc(app: ^App) {
	dir := app.config.server.scripts
	if dir == "" do return
	paths, found := scripts_in(dir)
	if !found {
		if dir != DEFAULT_SCRIPTS do log.warnf("no scripts folder %s", dir)
		return
	}
	if len(paths) == 0 do return
	app.script.console = {run = proc(user: rawptr, text: string) { console_execute((^App)(user), text) }, user = app}
	script_open(&app.script, &app.sv, ..paths)
}

// The .lua files in `dir`, by name, in the temp allocator; false if there is no `dir`.
@(private = "file")
scripts_in :: proc(dir: string) -> (paths: []string, found: bool) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return nil, false
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory || !strings.has_suffix(strings.to_lower(entry.name, context.temp_allocator), ".lua") do continue
		append(&names, entry.name)
	}
	slice.sort(names[:])
	for &name in names do name = strings.concatenate({dir, "/", name}, context.temp_allocator)
	return names[:], true
}

// The answers to the script's requests, between pumps of the server.
app_pump :: proc(app: ^App) {
	script_pump(&app.script)
}

app_stop :: proc(app: ^App) {
	script_close(&app.script)
}

// script_reload: the scripts read again, from the start; their state is lost. lua <code>:
// a line of Lua run in the scripts' state. False for a line that is neither.
script_command :: proc(app: ^App, word, rest: string) -> bool {
	switch word {
	case "script_reload":
		app_stop(app)
		app_start(app)
	case "lua":
		if app.script.L == nil do log.info("no script is running")
		else do script_run(&app.script, rest, "console")
	case:
		return false
	}
	return true
}

DEFAULT_SCRIPTS :: "scripts"
