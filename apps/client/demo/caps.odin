package demo

import sim "../../../core/game"
import network "../../../core/network"
import res "../../../core/resources"

// The captures in a demo, and when, for its timeline: found as it opens, from the
// rounds its snapshots carry, read no further than the round. Each snapshot's round is a
// delta against its base's, so the rounds of the last STREAM_RING snapshots are kept to
// read the next against, as the line keeps them; nothing is played.

Cap :: struct {
	tick: u32, // of the demo's, as the snapshot that told it came
	team: res.Team, // the team that scored
}

// The demo's captures, in order. A round's first snapshot tells the scores it began
// with, and those a demo joined mid-round opens with before its first tick: those aren't
// marked. Free with delete.
player_caps :: proc(p: ^Player, allocator := context.allocator) -> [dynamic]Cap {
	caps := make([dynamic]Cap, allocator)
	Kept :: struct {
		tick:  u32,
		round: sim.Round,
	}
	kept: [network.STREAM_RING]Kept
	round: u16
	newest: u32
	scores: [res.Team]i32
	seen := false // a snapshot of this round has told its scores
	ticks: u32
	data := p.data
	for at := HEADER_SIZE; at + 3 <= len(data); {
		kind := Record_Kind(data[at])
		n := int(get_u16(data[at + 1:]))
		if at + 3 + n > len(data) do break
		body := data[at + 3:][:n]
		at += 3 + n
		if kind == .Tick {
			ticks += 1
			continue
		}
		if kind != .Packet do continue
		b := network.buffer_reader(body)
		msg: network.Msg_Kind
		network.msg_kind(&b, &msg)
		if !network.buffer_ok(&b) || msg != .Snapshot do continue
		h: network.Snapshot_Header
		network.msg_snapshot_header(&b, &h)
		if !network.buffer_ok(&b) do continue
		if h.round != round { // a new round: its own scores, from its own snapshots
			round, newest, seen = h.round, 0, false
			kept = {}
		}
		if h.tick <= newest do continue
		base: ^sim.Round
		if h.base != 0 {
			k := &kept[h.base % network.STREAM_RING]
			if k.tick != h.base do continue // its base never came: the line dropped it too
			base = &k.round
		}
		now: sim.Round
		network.net_round(&b, &now, base)
		if !network.buffer_ok(&b) do continue
		newest = h.tick
		kept[h.tick % network.STREAM_RING] = {h.tick, now}
		for team in res.Team {
			if seen do for _ in scores[team] ..< now.captures[team] do append(&caps, Cap{ticks, team})
			scores[team] = now.captures[team]
		}
		// the snapshots before its first tick are the ones a demo begun mid-round joins
		// with (recorder_join), older than it: they tell the scores it began with, which
		// may have moved within them
		seen = ticks > 0
	}
	return caps
}
