package server

import "core:encoding/json"
import "core:log"
import "core:strings"
import "core:thread"

import res "../../core/resources"

// What is typed at the server, a line at a time:
//
//   quit                         stop the server
//   say <text>                   say something to everyone, as the server
//   nextmap                      end the round and begin the next
//   addbot [name]                a bot on the emptier side; addbot1, addbot2 on alpha, bravo
//   pause / unpause              the game stands where it is, or goes on
//   weapon <json>                weapons' numbers, as server.config.json's `weapons` has them;
//                                taken at once (not saved), and everyone on is told
//   weaponlist                   every weapon's numbers, as the config writes them
//   kick, ban, banip, banhw, unban, mute, unmute, map, bans, mutes, admins
//                                the admin commands (admin.odin)
//   script_reload, lua <code>    the script (app_script.odin)

console_execute :: proc(app: ^App, typed: string) {
	line := strings.trim_space(typed)
	if line == "" do return
	sv := &app.sv
	word, rest := next_word(line)
	switch word {
	case "quit":
		app.quit = true
	case "say":
		if rest == "" do log.info("usage: say <text>")
		else do server_say(sv, rest)
	case "nextmap":
		server_end_round(sv)
	case "addbot", "addbot1", "addbot2":
		team := res.Team.Alpha if word == "addbot1" else .Bravo if word == "addbot2" else .None
		if _, added := server_add_bot(sv, team, rest); !added do log.info("no room for a bot, or no such bot")
	case "pause", "unpause":
		paused := word == "pause"
		if server_pause(sv, paused) do server_say_kind(sv, .Game, {}, "Game paused" if paused else "Game unpaused")
	case "weapon":
		weapon_command(app, rest)
	case "weaponlist":
		weapon_list(app)
	case:
		if script_command(app, word, rest) do return
		if !admin_command(sv, nil, line) do log.infof("no command %s", word)
	}
}

// weapon <json>: weapons' numbers as server.config.json's `weapons` has them, as much as
// is to change: weapon {"desert_eagles": {"damage": 1.7, "fire_interval": 20}}. A name
// the config doesn't have is passed over, as the config passes it over.
@(private = "file")
weapon_command :: proc(app: ^App, text: string) {
	weapons := app.weapons
	if err := json.unmarshal_string(text, &weapons, allocator = context.temp_allocator); err != nil {
		log.infof("weapon: %v; usage: weapon {{\"desert_eagles\": {{\"damage\": 1.7}}}}, weaponlist shows them all", err)
		return
	}
	app.weapons = weapons
	server_weapons_changed(&app.sv, res.weapon_table(app.weapons))
	log.info("weapons changed, and everyone told")
}

// weaponlist: every weapon's numbers, as the config writes them.
@(private = "file")
weapon_list :: proc(app: ^App) {
	text, err := json.marshal(app.weapons, {pretty = true, use_spaces = true, spaces = 2}, context.temp_allocator)
	if err != nil do return
	log.info(string(text))
}

// A thread of its own, left to run until the program ends.
thread_start :: proc(run: proc()) {
	thread.create_and_start(run, self_cleanup = true)
}
