package network

import sa "core:container/small_array"
import "core:fmt"

import "../game"

// Eats: hits my own bullets made on my screen that the server never awarded, counted to
// measure the line ("Measured, not believed", docs/netcode.md), never acted on.
//
// A hit is a Hit of mine with damage on another soldier alive here. The server's word of
// it is its Damage, me the attacker, that soldier the target, alive before it: taken by
// my oldest hit on that soldier still waiting. A hit waits as long as the shot's round
// trip and the view's lead behind the newest snapshot, and EAT_SLACK ticks more; left
// unmatched past that, it is an eat, put down to the first of what may have caused it:
//
// - the target died, or came back in another life, before the word was due;
// - the shot reached the server further behind its present than it keeps (HISTORY_TICKS)
//   or than it runs a heard shot forward (CATCH_UP_MAX): judged by my ping and the view's
//   lead, as the server would have it behind;
// - I showed the target from an older word, stepped on, not the snapshot of the tick on
//   show: lost, late or held back, so not as the server's frame of the tick had it;
// - none of these.
//
// A Damage of the server's of mine matched by no hit here waits EAT_EARLY ticks for one:
// the server's bullet can meet the soldier a tick or two before mine does, and its word
// come before my hit. Matched by none, it is one the server saw and I didn't.

EAT_SLACK :: 30
EAT_EARLY :: 15
EATS_PENDING :: 128
EATS_EARLY :: 32
EATS_RECENT :: 32

Eat_Cause :: enum u8 {
	Target_Gone,  // dead, or in another life, by the time the server's word was due
	History,      // the shot further behind than the server keeps
	Catch_Up,     // further behind than the server runs a heard shot forward
	Extrapolated, // the target shown from an older word stepped on
	Unexplained,  // none of these: the frame the server rewound to, or something else
}

@(rodata)
EAT_CAUSE_NAMES := [Eat_Cause]string {
	.Target_Gone  = "target gone",
	.History      = "past history",
	.Catch_Up     = "past catch-up",
	.Extrapolated = "extrapolated",
	.Unexplained  = "unexplained",
}

Eat_Stats :: struct {
	hits:    u32, // mine on others, on my screen
	awarded: u32, // of them, those the server's word came of
	eaten:   [Eat_Cause]u32,
	unseen:  u32, // the server's damage of mine that matched no hit here
}

// An eat, as it was put down: for whoever reads them (a test), the newest kept while
// there is room.
Eat :: struct {
	tick:   u32, // the tick on show it struck in
	target: game.Soldier_Id,
	cause:  Eat_Cause,
	behind: u32, // how far behind the server's present the shot was judged to reach it
}

Eats :: struct {
	stats:   Eat_Stats,
	pending: sa.Small_Array(EATS_PENDING, Eat_Pending), // oldest first
	early:   sa.Small_Array(EATS_EARLY, Eat_Early),     // the server's damage come before my hit, oldest first
	recent:  sa.Small_Array(EATS_RECENT, Eat),           // the reader's to clear
}

@(private = "file")
Eat_Early :: struct {
	target: game.Soldier_Id,
	due:    u32, // the last tick on show my hit may come in
}

@(private = "file")
Eat_Pending :: struct {
	using eat: Eat, // its cause what held as it struck, Unexplained if nothing did
	due:       u32, // the last tick on show the server's word may come in
	life:      u8,
}

// After my tick (client_stream_collect): my hits in it taken by the server's words of them
// come early, else put to wait; the server's words of damage heard in it taken by my hits
// waiting, the oldest first, else kept a while for a hit to come; and those waited out put
// down, as eaten or unseen. The hits go first: a bullet that strikes in the same tick here
// as the server struck it there has its damage heard in that tick too.
eats_tick :: proc(e: ^Eats, c: ^Client_Stream, g: ^game.Game, me: game.Soldier_Id) {
	v := g.world.tick - 1 // the tick just run: the one on show
	lead := c.newest - v if c.newest > v else 0
	behind := lead + u32(g.world.soldiers[me].player.ping) * game.TICK_RATE / 1000
	for event in sa.slice(&g.output.events) {
		hit, is_hit := event.(game.Hit)
		if !is_hit || hit.shooter != me || hit.target == me || hit.amount <= 0 do continue
		target := &g.world.soldiers[hit.target]
		if !target.active || target.vitals.dead do continue // a corpse shot at: no wound for the server to give
		e.stats.hits += 1
		early := false // the server's word of it come already
		for word, i in sa.slice(&e.early) {
			if word.target != hit.target do continue
			sa.ordered_remove(&e.early, i)
			e.stats.awarded += 1
			early = true
			break
		}
		if early do continue
		if sa.len(e.pending) == EATS_PENDING { // nothing waits this long but on a broken line
			e.stats.hits -= 1
			continue
		}
		cause := Eat_Cause.Unexplained
		switch {
		case behind > game.HISTORY_TICKS:          cause = .History
		case behind > game.CATCH_UP_MAX:           cause = .Catch_Up
		case c.word_applied[hit.target] < v:       cause = .Extrapolated
		}
		sa.push_back(&e.pending, Eat_Pending{eat = {tick = v, target = hit.target, cause = cause, behind = behind}, due = v + behind + EAT_SLACK, life = target.vitals.life})
	}

	for ruling in sa.slice(&g.output.rulings) {
		damage, is_damage := ruling.(game.Damage)
		if !is_damage || damage.attacker != me || damage.target == me || damage.health_before <= 0 do continue
		matched := false
		for waiting, i in sa.slice(&e.pending) {
			if waiting.target != damage.target do continue
			sa.ordered_remove(&e.pending, i)
			e.stats.awarded += 1
			matched = true
			break
		}
		if matched do continue
		if sa.len(e.early) == EATS_EARLY {
			e.stats.unseen += 1
			continue
		}
		sa.push_back(&e.early, Eat_Early{target = damage.target, due = v + EAT_EARLY})
	}
	for sa.len(e.early) > 0 && sa.get(e.early, 0).due < v {
		sa.ordered_remove(&e.early, 0)
		e.stats.unseen += 1
	}

	for sa.len(e.pending) > 0 && sa.get(e.pending, 0).due < v {
		waited := sa.get(e.pending, 0)
		sa.ordered_remove(&e.pending, 0)
		target := &g.world.soldiers[waited.target]
		if !target.active || target.vitals.dead || target.vitals.life != waited.life do waited.cause = .Target_Gone
		e.stats.eaten[waited.cause] += 1
		if sa.len(e.recent) < EATS_RECENT do sa.push_back(&e.recent, waited.eat)
	}
}

// All the eats, whatever their cause.
eats_total :: proc(s: Eat_Stats) -> (n: u32) {
	for count in s.eaten do n += count
	return
}

// "hits 120, awarded 115, eaten 3 (extrapolated 2, unexplained 1), unseen 1": for a log.
eats_said :: proc(s: Eat_Stats, allocator := context.temp_allocator) -> string {
	causes := ""
	for count, cause in s.eaten {
		if count == 0 do continue
		causes = fmt.aprintf("%s%s%s %d", causes, ", " if causes != "" else "", EAT_CAUSE_NAMES[cause], count, allocator = allocator)
	}
	waiting := s.hits - s.awarded - eats_total(s)
	return fmt.aprintf("hits %d, awarded %d, eaten %d%s, waiting %d, unseen %d", s.hits, s.awarded, eats_total(s),
		fmt.tprintf(" (%s)", causes) if causes != "" else "", waiting, s.unseen, allocator = allocator)
}
