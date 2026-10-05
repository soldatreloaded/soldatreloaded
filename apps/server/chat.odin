package server

import "core:fmt"
import "core:log"
import "core:strings"

import "../../core/game"
import net "../../core/network"
import "../../core/utils"

// Chat: a player's line relayed to everyone, or its team, with the sender's slot. A
// line beginning with '/' is a command: a vote, a team, a taunt, an admin's order, or
// a script's; it is answered and reaches nobody else.

// A line said by the player in `slot`.
chat :: proc(sv: ^Server, slot: game.Soldier_Id, e: ^net.Event) {
	player := &sv.players[slot]
	if !player.joined do return
	b := net.buffer_reader(e.data[:e.size])
	kind: net.Msg_Kind
	m: net.Msg_Chat
	net.msg_kind(&b, &kind)
	net.msg_chat(&b, &m)
	if !net.buffer_done(&b) do return

	m.slot = slot // whatever it claimed, it is who it is
	m.kind = .Server
	m.color = {}
	text := utils.short_string_text(&m.text)
	player.chat_warnings += 1
	// a script hears it first, and may keep it
	if sv.hooks.chat != nil && sv.hooks.chat(sv.hooks.user, slot, text, m.team) do return
	if strings.has_prefix(text, "/") {
		if !admin_command(sv, slot, text[1:]) do player_command(sv, slot, text[1:])
		return
	}
	if player.muted { // its chat reaches nobody; it alone is told
		tell(sv, slot, "You are muted.")
		return
	}
	log.infof("%s%s: %s", "(team) " if m.team else "", utils.short_string_text(&player.name), text)
	if !m.team {
		broadcast(sv, .Chat, net.msg_chat, &m)
		return
	}
	team := sv.game.world.soldiers[slot].team // to the team, the sender among them
	buf: [net.MTU]u8
	bytes := net.build(buf[:], .Chat, net.msg_chat, &m)
	for &other, i in sv.players {
		if other.joined && sv.game.world.soldiers[i].team == team do net.net_send(other.peer, .Chat, bytes)
	}
}

// The first word of `text`, and the rest past the spaces after it.
next_word :: proc(text: string) -> (word, rest: string) {
	word, _, rest = strings.partition(text, " ")
	return word, strings.trim_left(rest, " ")
}

// A command said in the chat: team <n>, votemap <map>, votekick <player> [reason], yes,
// no, the taunts, kill; else a script's, if it has one by that name.
player_command :: proc(sv: ^Server, slot: game.Soldier_Id, text: string) {
	word, rest := next_word(text)
	switch word {
	case "team":
		team_command(sv, slot, rest)
	case "votemap", "votekick", "yes", "no":
		vote_command(sv, slot, word, rest)
	case "tabac", "smoke", "takeoff", "victory", "piss", "mercy", "pwn":
		taunt(sv, slot, word)
	case "kill", "brutalkill":
		// the original's: a death by one's own hand, a kill fewer. (The Suicide button is
		// the game's way, which tears the body apart as the original's brutalkill does.)
		soldier := &sv.game.world.soldiers[slot]
		if !soldier.active || soldier.vitals.dead do return
		sv.suicides[slot] = true
	case:
		if sv.hooks.command != nil && sv.hooks.command(sv.hooks.user, slot, text) do return
		tell(sv, slot, fmt.tprintf("Unknown command: /%s", word))
	}
}

// /team <n>: the team menu's choice, the original's numbering: 1 alpha, 2 bravo, 5 to
// watch. The soldier is placed anew on it.
@(private = "file")
team_command :: proc(sv: ^Server, slot: game.Soldier_Id, rest: string) {
	n, is_number := parse_int(rest)
	team := res_team(n)
	if !is_number || (team != .Alpha && team != .Bravo && team != .Spectator) {
		tell(sv, slot, "Teams: 1 alpha, 2 bravo, 5 spectator")
		return
	}
	player := &sv.players[slot]
	if player.chose_team && player.team == team do return // already there
	player.chose_team = true
	player.team = team
	player_place(sv, slot, team)
	announce_join(sv, slot)
}

// CommandPlayerCommand: the taunts, asked of the soldier's idle machine by their number
// (Idle.random's); a mercy costs a kill.
@(private = "file")
taunt :: proc(sv: ^Server, slot: game.Soldier_Id, word: string) {
	TAUNTS :: [?]string{"tabac", "smoke", "", "", "takeoff", "victory", "piss", "mercy", "pwn"}
	soldier := &sv.game.world.soldiers[slot]
	if !soldier.active || soldier.vitals.dead do return
	for name, i in TAUNTS {
		if name == "" || name != word do continue
		soldier.antics.asked = i8(i)
		soldier.antics.asked_count += 1
		if name == "mercy" && soldier.tally.kills > 0 do soldier.tally.kills -= 1
	}
}
