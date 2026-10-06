package server

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
//   weapon <weapon> <Key>=<n>... a weapon's numbers, as weapons.ini has them: weapon Desert
//                                Eagles Damage=1.7 FireInterval=20; taken at once (not
//                                saved), and everyone on is told
//   weaponlist                   every weapon's numbers, as weapons.ini writes them
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

// weapon <weapon> <Key>=<n>...: a weapon's numbers as weapons.ini has them, the weapon by
// its section's name and each number by its key, in any case: weapon Desert Eagles
// Damage=1.7 FireInterval=20. Nothing changes unless all of it is right.
@(private = "file")
weapon_command :: proc(app: ^App, text: string) {
	USAGE :: "usage: weapon <weapon> <Key>=<n>..., as weapons.ini has them (weapon Desert Eagles Damage=1.7); weaponlist shows them all"
	words := strings.fields(text, context.temp_allocator)
	first_key := len(words)
	for word, i in words {
		if strings.contains_rune(word, '=') {
			first_key = i
			break
		}
	}
	section := strings.join(words[:first_key], " ", context.temp_allocator)
	weapon, known := res.weapon_by_section(section).?
	if !known || first_key == len(words) {
		if section != "" && !known do log.infof("weapon: no weapon %s", section)
		log.info(USAGE)
		return
	}
	stats := app.weapons[weapon]
	for word in words[first_key:] {
		eq := strings.index_byte(word, '=')
		if eq < 0 {
			log.infof("weapon: %s isn't Key=number; %s", word, USAGE)
			return
		}
		field, has := res.weapon_ini_field(word[:eq])
		if !has || !res.weapon_stat_set(&stats, field, word[eq + 1:]) {
			log.infof("weapon: %s isn't a number of %s's; %s", word, section, USAGE)
			return
		}
	}
	app.weapons[weapon] = stats
	server_weapons_changed(&app.sv, app.weapons)
	log.infof("%s changed, and everyone told", res.WEAPON_INI_SECTIONS[weapon])
}

// weaponlist: every weapon's numbers, as weapons.ini writes them.
@(private = "file")
weapon_list :: proc(app: ^App) {
	log.info(res.weapons_ini_text(&app.weapons, commented = false))
}

// A thread of its own, left to run until the program ends.
thread_start :: proc(run: proc()) {
	thread.create_and_start(run, self_cleanup = true)
}
