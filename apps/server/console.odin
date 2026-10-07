package server

import "core:log"
import "core:strings"
import "core:thread"

import res "../../core/resources"

// What is typed at the server, a line at a time: the console's own commands, then the
// admin commands (admin.odin), which an admin may also say in the chat:
//
//   quit                         stop the server
//   weapon <weapon> <Key>=<n>... a weapon's numbers, as weapons.ini has them: weapon Desert
//                                Eagles Damage=1.7 FireInterval=20; taken at once (not
//                                saved), and everyone on is told
//   weaponlist                   every weapon's numbers, as weapons.ini writes them
//   script_reload, lua <code>    the script (app_script.odin)
//   help                         these, and the admin commands
//   kick, ban, banip, banhw, unban, mute, unmute, map, nextmap, restart, pause, unpause,
//   addbot, addbot1, addbot2, say, bans, mutes, admins
//                                the admin commands (admin.odin)

console_execute :: proc(app: ^App, typed: string) {
	line := strings.trim_space(typed)
	if line == "" do return
	sv := &app.sv
	word, rest := next_word(line)
	switch word {
	case "quit":
		app.quit = true
	case "help":
		log.info("quit  weapon <weapon> <Key>=<n>...  weaponlist  script_reload  lua <code>")
		admin_command(sv, nil, line) // and the admin's
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
