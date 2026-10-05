package network

import "../game"
import res "../resources"

// The two streams: the client's state every tick, the server's snapshot every tick,
// both unreliable and both delta-compressed against the newest the other side
// acknowledged, the acknowledgement riding in the packet going the other way. Both ends
// of both streams are here (stream_server.odin, stream_client.odin), so a test can
// drive either.
//
// Client state: the owned half of the client's soldier, numbered; the server takes it
// as written after its checks. It is a delta against the client's own earlier state the
// server last acknowledged, which both keep in a ring; whole when there is none young
// enough.
//
// Snapshot: numbered by the server's tick. For every slot a word: no soldier, the
// soldier's halves, or nothing this time (held back to fit the datagram; the client
// keeps stepping it). A soldier's halves are a delta against the snapshot the client
// last acknowledged, if that snapshot carried the soldier, and whole otherwise; the
// server deltas against what it sent, out of its history, and the client against what
// it received. The client applies the served half of everyone and the owned half of
// everyone but itself, and its own only on a new life: a placing.
//
// Between words, everyone steps a soldier heard of on its last keys
// (soldier_last_command), one-shot buttons cleared so a throw is not thrown again;
// after STREAM_RELEASE_TICKS of silence the keys are let go and it falls and stops.

STREAM_RING :: 32          // states kept for deltas, each side
STREAM_WHOLE_AFTER :: 24   // a baseline older than this many states or ticks: whole
STREAM_RELEASE_TICKS :: 30 // no word for this long: the keys are let go

// ---------------------------------------------------------------------------------
// The messages

Msg_Client_State :: struct {
	round:     u16,          // the round it is of (Msg_Map); another round's is dropped
	seq:       u32,          // this state's number, the client's count from 1
	base:      u32,          // the state it is a delta against, 0 for whole
	ack:       u32,          // the newest snapshot (its tick) the client has, 0 for none
	event_ack: u32,          // the newest of the server's words the client has heard
	life:      u8,           // the life the soldier is on here: the word of an older life is not taken
	owned:     game.Soldier, // the owned half, and the loadout, ride in a Soldier
	typing:    bool,         // the player is at the chat prompt: the dots over its head
	// then the client's own decisions since the server's acknowledgement (wire_write)
}

// The header and the half; `base` is the soldier the delta is against, nil for whole;
// in reading, the fields it holds that didn't change are taken from it. The words
// follow, written and read with wire_write and wire_read.
msg_client_state :: proc(b: ^Buffer, m: ^Msg_Client_State, base: ^game.Soldier) {
	net_u16(b, &m.round)
	net_u32(b, &m.seq)
	net_u32(b, &m.base)
	net_u32(b, &m.ack)
	net_u32(b, &m.event_ack)
	net_u8(b, &m.life)
	fields_serialize(b, SOLDIER_OWNED_FIELDS, &m.owned, base)
	fields_serialize(b, SOLDIER_LOADOUT_FIELDS, &m.owned, base)
	net_bool(b, &m.typing)
}

Snap_Word :: enum u8 {
	Gone,  // no soldier in the slot
	State, // the soldier's halves follow
	Same,  // nothing this time: keep stepping it
}

Msg_Snapshot :: struct {
	round:            u16, // the round it is of (Msg_Map); another round's is dropped
	tick:             u32, // the snapshot's number
	base:             u32, // the snapshot it is a delta against, 0 for whole
	client_ack:       u32, // the newest client state (its seq) the server has from this client
	client_event_ack: u32, // the newest of the client's words the server has heard
	match:            game.Round,
	word:             [game.MAX_PLAYERS]Snap_Word,
	soldiers:         [game.MAX_PLAYERS]game.Soldier,
	names:            [game.MAX_PLAYERS]Name, // sent with a soldier that goes whole
	thing_word:       [game.MAX_THINGS]Snap_Word,
	things:           [game.MAX_THINGS]game.Thing,
	// then the server's words since the client's acknowledgement (wire_write)
}

// What a snapshot is a delta against: the soldiers and things of the acknowledged
// snapshot and the words it carried; nil for whole. A slot the base did not carry (not
// State) goes whole, and a soldier that goes whole brings its name.
Snap_Base :: struct {
	soldiers:   ^[game.MAX_PLAYERS]game.Soldier,
	word:       ^[game.MAX_PLAYERS]Snap_Word,
	things:     ^[game.MAX_THINGS]game.Thing,
	thing_word: ^[game.MAX_THINGS]Snap_Word,
}

// The header, the round, the soldiers with their names, the things. The words follow,
// written and read with wire_write and wire_read_pending.
msg_snapshot :: proc(b: ^Buffer, m: ^Msg_Snapshot, base: ^Snap_Base) {
	net_u16(b, &m.round)
	net_u32(b, &m.tick)
	net_u32(b, &m.base)
	net_u32(b, &m.client_ack)
	net_u32(b, &m.client_event_ack)
	net_round(b, &m.match)
	for &word, i in m.word {
		net_enum(b, &word)
		if word != .State do continue
		against := &base.soldiers[i] if base != nil && base.word[i] == .State else nil
		fields_serialize(b, SOLDIER_SERVED_FIELDS, &m.soldiers[i], against)
		fields_serialize(b, SOLDIER_OWNED_FIELDS, &m.soldiers[i], against)
		if against == nil do net_string(b, &m.names[i]) // a soldier going whole brings its name
	}
	for &word, i in m.thing_word {
		net_enum(b, &word)
		if word != .State do continue
		against := &base.things[i] if base != nil && base.thing_word[i] == .State else nil
		fields_serialize(b, THING_FIELDS, &m.things[i], against)
	}
}

// The round, whole: its phase, its clock, its mode and the scores.
net_round :: proc(b: ^Buffer, round: ^game.Round) {
	phase: u32
	ended: game.Ended
	switch p in round.phase {
	case game.Playing: phase = 0
	case game.Paused:  phase = 1
	case game.Ended:   phase = 2; ended = p
	}
	net_range(b, &phase, 2)
	if phase == 2 {
		net_enum(b, &ended.winner)
		net_signed(b, &ended.countdown, 16)
	}
	net_signed(b, &round.time_left, 32)
	for &captures in round.captures do net_signed(b, &captures, 16)
	if b.reading {
		switch phase {
		case 0: round.phase = game.Playing{}
		case 1: round.phase = game.Paused{}
		case 2: round.phase = ended
		}
	}
}

// ---------------------------------------------------------------------------------
// The halves taken

// The owned half of `src` onto `dst`, the animations' speed set from the anims as the
// fields cannot.
soldier_take_owned :: proc(animations: ^res.Animations, dst, src: ^game.Soldier) {
	fields_copy(SOLDIER_OWNED_FIELDS, dst, src)
	dst.pose.legs.speed = animations[dst.pose.legs.id].speed
	dst.pose.body.speed = animations[dst.pose.body.id].speed
}

soldier_take_served :: proc(dst, src: ^game.Soldier) {
	fields_copy(SOLDIER_SERVED_FIELDS, dst, src)
}

// Whether the round stands still: paused, or over.
round_standing :: proc(round: ^game.Round) -> bool {
	_, playing := round.phase.(game.Playing)
	return !playing
}
