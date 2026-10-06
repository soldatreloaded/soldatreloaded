package server

import "core:log"

import "../../core/utils"

// The script beside the server (script.odin): the one server.config.mjson names, read as the
// server starts, pumped with it, and the console's script_reload and lua. Its path is
// the install's, from its root where the server runs; a path set by hand that isn't
// there is said, the default's absence is nothing.

app_start :: proc(app: ^App) {
	path := app.config.server.script
	if path == "" do return
	if !utils.file_exists(path) {
		if path != DEFAULT_SCRIPT do log.warnf("no script at %s", path)
		return
	}
	app.script.console = {run = proc(user: rawptr, text: string) { console_execute((^App)(user), text) }, user = app}
	script_open(&app.script, &app.sv, path)
}

// The answers to the script's requests, between pumps of the server.
app_pump :: proc(app: ^App) {
	script_pump(&app.script)
}

app_stop :: proc(app: ^App) {
	script_close(&app.script)
}

// script_reload: the script read again, from the start; its state is lost. lua <code>:
// a line of Lua run in the script's state. False for a line that is neither.
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

DEFAULT_SCRIPT :: "scripts/main.lua"
