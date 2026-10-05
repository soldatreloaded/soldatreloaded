package server

import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"

import "../core/game"
import net "../core/network"
import res "../core/resources"
import "../core/utils"

// The votes as the original runs them (Game.pas StartVote, CountVote, TimerVote): twenty
// seconds to decide; only a yes is counted, against the number of players on when it
// began, and it passes at the config's vote percentage of them; a no is the voter's own
// business (its client drops the box) and a vote that gathers too few yeses simply runs
// out. Nobody may start one within two minutes of joining or of their last. A kick
// passed puts the player off for an hour, by address and machine; a map passed is the
// round's to play next (rounds.odin).

VOTE_TICKS :: 20 * game.TICK_RATE              // DEFAULT_VOTING_TIME
VOTE_COOLDOWN_TICKS :: 2 * 60 * game.TICK_RATE // DEFAULT_VOTE_TIME
VOTE_PERCENT_DEFAULT :: 60
VOTE_KICK_BAN_SECONDS :: 60 * 60 // an hour
VOTE_LEFT_BAN_SECONDS :: 5 * 60  // a kick vote's target who leaves before it is decided

Vote :: struct {
	kind:       net.Vote_Kind, // None: none running
	target:     net.Map_Name,  // the map, or the player's name
	reason:     net.Reason,    // a kick's, as the starter typed it
	slot:       game.Soldier_Id, // the player, for a kick
	starter:    Maybe(game.Soldier_Id),
	ticks_left: i32,
	max_votes:  int,           // the players on when it began (VoteMaxVotes)
	answer:     [game.MAX_PLAYERS]bool, // voted yes
}

// The vote as it stands, to one peer or (nil) everyone: for the HUD.
tell_vote :: proc(sv: ^Server, peer: net.Peer) {
	m := net.Msg_Vote{kind = sv.vote.kind, target = sv.vote.target, reason = sv.vote.reason, seconds = u16((sv.vote.ticks_left + game.TICK_RATE - 1) / game.TICK_RATE)}
	if starter, started := sv.vote.starter.?; started do m.starter = sv.players[starter].name
	if peer != nil {
		net.net_send_message(peer, .Vote, net.msg_vote, &m)
	} else {
		broadcast(sv, .Vote, net.msg_vote, &m)
	}
}

// The player a command names, a bot among them as in the original: a slot's number, or
// a name, whole or as much of it as typed; nobody for nothing.
player_named :: proc(sv: ^Server, name: string) -> (game.Soldier_Id, bool) {
	if name == "" do return 0, false
	if n, is_number := strconv.parse_int(name); is_number {
		if n < 0 || n >= game.MAX_PLAYERS || !player_present(&sv.players[n]) do return 0, false
		return game.Soldier_Id(n), true
	}
	found := -1
	for &player, i in sv.players {
		if !player_present(&player) do continue
		known := utils.short_string_text(&player.name)
		if known == name do return game.Soldier_Id(i), true
		if strings.has_prefix(known, name) && found < 0 do found = i
	}
	return game.Soldier_Id(max(found, 0)), found >= 0
}

// Over (StopVote): the original says nothing of a kick that ran out, and of a map vote
// that did, that no map was voted; a pass shows as the kick or the next map.
vote_end :: proc(sv: ^Server, passed: bool) {
	if sv.vote.kind == .Map && !passed do announce(sv, .Vote, "No map has been voted")
	sv.vote = {starter = nil}
	tell_vote(sv, nil)
}

// A yes from `slot` (CountVote): once each; passed when the yeses reach the percentage
// of the players there were when the vote began. A kick passed puts the player off for
// an hour; a map passed is the server's to play next.
@(private = "file")
vote_count :: proc(sv: ^Server, slot: game.Soldier_Id) {
	if sv.vote.kind == .None || sv.vote.answer[slot] do return
	sv.vote.answer[slot] = true
	yes := 0
	for answer in sv.vote.answer do yes += int(answer)
	percent := sv.options.config.server.vote_percent
	if percent <= 0 do percent = VOTE_PERCENT_DEFAULT
	if f32(yes) / f32(max(sv.vote.max_votes, 1)) < f32(percent) / 100 do return
	v := sv.vote
	if v.kind == .Map {
		sv.vote_map = v.target
	} else if sv.players[v.slot].joined {
		sv.players[v.slot].kick_why = .Voted
		player_ban(sv, v.slot, VOTE_KICK_BAN_SECONDS, "Vote Kicked")
		player_kick(sv, v.slot, "Vote Kicked")
	}
	vote_end(sv, true)
	if v.kind == .Kick && sv.players[v.slot].bot do player_remove_bot(sv, v.slot) // a bot is taken off
}

// Each tick (TimerVote): the vote runs out, and the cooldowns run down.
vote_tick :: proc(sv: ^Server) {
	for &cooldown in sv.vote_cooldown {
		if cooldown > -1 do cooldown -= 1
	}
	if sv.vote.kind == .None do return
	sv.vote.ticks_left -= 1
	if sv.vote.ticks_left <= 0 do vote_end(sv, false)
}

// StartVote: the players on now, people alone, are the votes there are to gather; the
// starter may not start another for two minutes. Nobody has voted by starting it: the
// starter presses F12 as everyone does, kick or map, as the original plays (its client
// means to send a kick starter's yes, but reads the vote's kind before it is set).
@(private = "file")
vote_start :: proc(sv: ^Server, slot: game.Soldier_Id, kind: net.Vote_Kind, target: string, target_slot: game.Soldier_Id, reason: string) {
	sv.vote = {kind = kind, slot = target_slot, starter = slot, ticks_left = VOTE_TICKS, max_votes = players_count(sv)}
	utils.short_string_set(&sv.vote.target, target)
	utils.short_string_set(&sv.vote.reason, reason)
	sv.vote_cooldown[slot] = VOTE_COOLDOWN_TICKS
	tell_vote(sv, nil) // the vote's box says who wants what; the original's console says nothing
	if kind == .Kick do log.infof("%s started votekick against %s - Reason:%s", utils.short_string_text(&sv.players[slot].name), target, reason)
}

// A vote said in the chat, as the original's ServerHandleVoteKick and CommandVotemap
// take them: votemap <map>, votekick <player> [reason], yes, no.
vote_command :: proc(sv: ^Server, slot: game.Soldier_Id, word, rest: string) {
	switch word {
	case "votemap":
		// CommandVotemap: with a vote on, a yes to it if it is for this map; else a new one,
		// for a map the server has, by a player who may
		if rest == "" do return // with nothing named, nothing
		if sv.vote.kind != .None {
			if sv.vote.kind == .Map && utils.short_string_text(&sv.vote.target) == rest do vote_count(sv, slot)
			return
		}
		if !map_known(sv, rest) {
			tell(sv, slot, fmt.tprintf("Map not found (%s)", rest))
			return
		}
		if sv.vote_cooldown[slot] >= 0 {
			tell(sv, slot, "Can't vote for 2:00 minutes after joining game or last vote")
			return
		}
		vote_start(sv, slot, .Map, rest, 0, "---")
	case "votekick":
		// ServerHandleVoteKick: a yes to the kick on, unless I am its target; else a new one,
		// quietly refused within the cooldown, and never against myself (the kick window's
		// button refuses it). The reason is the rest as said, past one space: the kick
		// window's keeps its leading space, as the original's box shows it ("Reason: afk").
		who, _, reason := strings.partition(rest, " ")
		target, found := player_named(sv, who)
		if sv.vote.kind != .None {
			if sv.vote.kind != .Kick do return
			if sv.vote.slot == slot {
				tell(sv, slot, "A vote has been cast against you. You can not vote.")
				return
			}
			if found && target == sv.vote.slot do vote_count(sv, slot)
			return
		}
		if sv.vote_cooldown[slot] >= 0 || (found && target == slot) do return
		if !found {
			if who != "" do tell(sv, slot, fmt.tprintf("No such player: %s", who))
			return
		}
		vote_start(sv, slot, .Kick, utils.short_string_text(&sv.players[target].name), target, reason)
	case "yes":
		// F12: a yes to the vote on, whatever it is for; its target may not
		if sv.vote.kind == .None do return
		if sv.vote.kind == .Kick && sv.vote.slot == slot {
			tell(sv, slot, "A vote has been cast against you. You can not vote.")
			return
		}
		vote_count(sv, slot)
	case "no":
		// F11 is the voter's own business: the original's client only drops the box
	}
}

// A map vote passed since last asked (or an admin's /map): the map, once.
vote_take_map :: proc(sv: ^Server) -> (map_name: string, passed: bool) {
	if sv.vote_map.length == 0 do return
	map_name = utils.short_string_text(&sv.vote_map)
	sv.vote_map = {}
	return map_name, true
}

// ---------------------------------------------------------------------------------

// A number at the start of `text`, and nothing after it.
parse_int :: proc(text: string) -> (int, bool) {
	return strconv.parse_int(strings.trim_space(text))
}

// The original's numbering of the teams, as /team says them.
res_team :: proc(n: int) -> res.Team {
	if n < 0 || n > int(res.Team.Spectator) do return .Charlie // never one a player may choose
	return res.Team(n)
}
