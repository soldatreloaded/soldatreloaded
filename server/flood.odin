package server

import "core:log"

import "../core/game"
import "../core/utils"

// Flooding (ServerLoop.pas): a player heard from more than the config's flooding_packets
// times in a second gets a warning, and past flood_warnings of them is kicked and barred
// for a quarter of an hour; a warning is forgiven every five minutes. A client sends one
// state a tick, so the default leaves room for twice that. Chat is counted apart: every
// line is a warning, one is forgiven a second, and more than five outstanding is a
// five-minute kick.

FLOOD_PACKETS_DEFAULT :: 120
FLOOD_WARNINGS_DEFAULT :: 4
FLOOD_FORGIVE_TICKS :: 5 * 60 * game.TICK_RATE
FLOOD_BAN_SECONDS :: 15 * 60
CHAT_FLOOD_WARNINGS :: 5
CHAT_FLOOD_BAN_SECONDS :: 5 * 60

// Each tick: once a second, whoever was heard from more than the limit gets a warning
// and the count starts over, and the chat warnings drain one, kicking past five; every
// five minutes a flood warning is forgiven. A kick bars the address.
flood_tick :: proc(sv: ^Server) {
	second := sv.ticks % game.TICK_RATE == 0
	five_minutes := sv.ticks % FLOOD_FORGIVE_TICKS == 0
	if !second && !five_minutes do return
	limit := int(sv.options.config.network.flooding_packets)
	if limit <= 0 do limit = FLOOD_PACKETS_DEFAULT
	warnings_max := int(sv.options.config.network.flood_warnings)
	if warnings_max <= 0 do warnings_max = FLOOD_WARNINGS_DEFAULT
	for &player, i in sv.players {
		if !player.joined do continue
		slot := game.Soldier_Id(i)
		if five_minutes && player.flood_warnings > 0 do player.flood_warnings -= 1
		if !second do continue
		if player.messages > limit {
			log.infof("%s is flooding the server", utils.short_string_text(&player.name))
			player.flood_warnings += 1
			if player.flood_warnings > warnings_max {
				player.kick_why = .Flooding
				player_ban(sv, slot, FLOOD_BAN_SECONDS, "Flood Kicked")
				player_kick(sv, slot, "Flood Kicked")
				continue // gone; the leave frees the slot
			}
		}
		player.messages = 0
		if player.chat_warnings > CHAT_FLOOD_WARNINGS {
			player.kick_why = .Flooding
			player_ban(sv, slot, CHAT_FLOOD_BAN_SECONDS, "Chat Flood") // twenty minutes is too harsh, says the original
			player_kick(sv, slot, "Chat Flood")
			continue
		}
		if player.chat_warnings > 0 do player.chat_warnings -= 1
	}
}
