package game

// Where everyone was over the last second, kept by the machine with authority: a shot is
// judged against the soldiers as its shooter saw them, and a snapshot is sent as what
// changed since the tick its client last had.

HISTORY_TICKS :: 64

History :: struct {
	soldiers: [HISTORY_TICKS][MAX_PLAYERS]Soldier, // by tick, round the ring
	things:   [HISTORY_TICKS][MAX_THINGS]Thing,    // for the snapshots' deltas
	newest:   u32,
	count:    u32,
}

// The world as it stands, as the history's newest frame.
history_record :: proc(history: ^History, world: ^World) {
	frame := world.tick % HISTORY_TICKS
	history.soldiers[frame] = world.soldiers
	history.things[frame] = world.things
	history.newest = world.tick
	history.count = min(history.count + 1, HISTORY_TICKS)
}

// The soldiers as they were `ticks_ago`; nil if that is further back than is kept.
history_soldiers :: proc(history: ^History, ticks_ago: u32) -> ^[MAX_PLAYERS]Soldier {
	if ticks_ago >= history.count {
		return nil
	}
	return &history.soldiers[(history.newest - ticks_ago) % HISTORY_TICKS]
}

// The soldiers and the things as they stood at the end of `tick`, if it is still kept.
history_at :: proc(history: ^History, tick: u32) -> (soldiers: ^[MAX_PLAYERS]Soldier, things: ^[MAX_THINGS]Thing, ok: bool) {
	if tick > history.newest || history.newest - tick >= history.count {
		return
	}
	return &history.soldiers[tick % HISTORY_TICKS], &history.things[tick % HISTORY_TICKS], true
}
