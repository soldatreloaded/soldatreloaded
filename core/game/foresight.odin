package game

import sa "core:container/small_array"

import res "../resources"

// What a client's own shots did, shown on its screen before the server says so. Its
// hits on the living are its claims (hit_claim.odin), which the server lands as they
// were seen; so a hit that would kill there kills here at once, the death, the feed and
// the sound, rather than a trip to the server and back later. The server's word of the
// death, when it comes, is the same death and shows nothing more; a death its word
// never confirms (a claim it turned down, another's kill first) is taken back.
//
// The wounds the client's claims gave that the target's health here, the server's, has
// not yet taken are owed: its health less them is what the next hit is reckoned
// against. Each Damage of mine the server tells of pays the oldest owed on that
// soldier, which is let go of once the snapshot its health came from is newer than the
// word: a snapshot lost or held back leaves the health older than the words heard. A
// wound never told of is forgotten after OWED_TICKS.

FORESEEN_HOLD :: 90  // ticks a death foreseen waits for the server's word, then is taken back
OWED_TICKS :: 90     // ticks a wound owed waits to be told of
OWED_MAX :: 16       // wounds owed a soldier at once, the oldest let go of past it

Foresight :: struct {
	deaths: [MAX_PLAYERS]Foreseen,
	owed:   [MAX_PLAYERS]sa.Small_Array(OWED_MAX, Owed),
	health: [MAX_PLAYERS]u32, // the tick of the snapshot each soldier's health here came from
	shown:  [SHOWN_KEPT]Shown_Hit, // the hits on the living this client showed of others' shots, round the ring
	shown_next: int,
}

// A death this client's own hit gave a soldier on its screen, the server's word of it to
// come.
Foreseen :: struct {
	set:       bool,
	life:      u8,  // the life it ended
	tick:      u32, // when
	killer:    Soldier_Id,
	weapon:    res.Weapon,
	part:      u8,
	confirmed: bool, // the server's snapshot has it dead: its word of the death is still to come
}

Owed :: struct {
	amount: f32,
	life:   u8,
	tick:   u32,
	paid:   u32, // the tick of the server's Damage that told of it; 0 for none yet
}

// A hit of this client's own on another soldier, on its screen: its wound owed, and a
// death foreseen if it kills.
foresee_hit :: proc(world: ^World, resources: ^Resources, hit: Hit, out: ^Tick_Output) {
	if hit.amount <= 0 || hit.target == hit.shooter || int(hit.target) >= MAX_PLAYERS do return
	shooter, target := &world.soldiers[hit.shooter], &world.soldiers[hit.target]
	if shooter.remote || !target.remote || !target.active || target.vitals.dead || !wounds(world, hit) do return
	f := &world.foresight
	owed := &f.owed[hit.target]
	for i := sa.len(owed^) - 1; i >= 0; i -= 1 {
		o := sa.get(owed^, i)
		in_health := o.paid != 0 && o.paid < f.health[hit.target] // a Damage said in a tick is in the snapshots after it
		forgotten := o.paid == 0 && world.tick - o.tick > OWED_TICKS
		if o.life != target.vitals.life || in_health || forgotten do sa.ordered_remove(owed, i)
	}
	health := target.vitals.health
	for o in sa.slice(owed) do health -= o.amount
	amount := hit_damage(world, hit)
	if sa.len(owed^) == OWED_MAX do sa.ordered_remove(owed, 0)
	sa.push_back(owed, Owed{amount = amount, life = target.vitals.life, tick = world.tick})
	if health - amount >= 1.0 do return

	// it kills: the death here now, as the server's Kill would be shown, its fire left out
	// (the server's roll)
	target.vitals.health = health - amount // the death's sounds go by how bad it was
	f.deaths[hit.target] = {set = true, life = target.vitals.life, tick = world.tick, killer = hit.shooter, weapon = hit.weapon, part = hit.part}
	rule(world, resources, Kill {
		killer    = hit.shooter,
		target    = hit.target,
		weapon    = hit.weapon,
		pos       = target.body.pos,
		part      = hit.part,
		impact    = hit.impact,
		distance  = hit.distance,
		airtime   = hit.airtime,
		ricochets = hit.ricochets,
	}, out)
	// but the flag it carried stays on the body for the server's word: let go here, its
	// snapshot would hand it back, and its kill let go of it again
	asked := sa.slice(&world.things_asked)
	for i := len(asked) - 1; i >= 0; i -= 1 {
		if let_go, is := asked[i].(Let_Go); is && let_go.soldier == hit.target {
			sa.ordered_remove(&world.things_asked, i)
			break
		}
	}
}

// The server's Damage of mine, on a client, said in `tick`, as the step begins: it pays
// the oldest wound owed that soldier not yet paid, before the step's own hits are
// reckoned; the wound is let go of once the soldier's health is from a snapshot as new.
foresee_paid :: proc(world: ^World, ruling: Ruling, tick: u32) {
	damage, is_damage := ruling.(Damage)
	if !is_damage || int(damage.target) >= MAX_PLAYERS || int(damage.attacker) >= MAX_PLAYERS || world.soldiers[damage.attacker].remote do return
	for &o in sa.slice(&world.foresight.owed[damage.target]) {
		if o.paid != 0 do continue
		o.paid = max(tick, 1)
		return
	}
}

// Soldier `id`'s health taken from the server's snapshot of `tick`, on a client.
foresee_health :: proc(world: ^World, id: Soldier_Id, tick: u32) {
	world.foresight.health[id] = tick
}

// A ruling from the server, on a client, before it is carried out: false if it is one
// already shown. Its Kill of a death
// foreseen is that death, shown already, unless another killed first: then the
// foreseen one is taken back and the server's shown.
foresee_ruling :: proc(world: ^World, resources: ^Resources, ruling: Ruling, out: ^Tick_Output) -> (carry_out: bool) {
	f := &world.foresight
	#partial switch r in ruling {
	case Kill:
		if int(r.target) >= MAX_PLAYERS do return true
		death := &f.deaths[r.target]
		if !death.set || death.life != world.soldiers[r.target].vitals.life do return true
		if r.killer == death.killer {
			death^ = {}
			return false
		}
		foresee_undo(world, r.target, out) // another's kill: the soldier lives again for the server's to land
		world.soldiers[r.target].vitals.dead = false
	case Respawn:
		if int(r.target) < MAX_PLAYERS {
			f.deaths[r.target] = {}
			sa.clear(&f.owed[r.target])
		}
	}
	return true
}

// A death foreseen held against the server's snapshot of soldier `id`, `heard`: true
// while the server hasn't yet killed it, so the snapshot is not taken and it stays dead
// here. Its snapshot dead, it is confirmed, its word still to come; another life, the
// foresight is over.
foresee_holds :: proc(world: ^World, id: Soldier_Id, heard: ^Soldier) -> bool {
	death := &world.foresight.deaths[id]
	if !death.set do return false
	if heard.vitals.life != death.life {
		death^ = {}
		return false
	}
	if heard.vitals.dead {
		death.confirmed = true
		return false
	}
	return !death.confirmed
}

// Each tick on a client: a death foreseen the server hasn't confirmed in FORESEEN_HOLD
// is taken back, and the soldier stands as the next snapshot has it.
foresee_tick :: proc(world: ^World, out: ^Tick_Output) {
	for &death, i in world.foresight.deaths {
		if !death.set || death.confirmed || world.tick - death.tick <= FORESEEN_HOLD do continue
		foresee_undo(world, Soldier_Id(i), out)
	}
}

// A death foreseen taken back: told, for the feed to take its line back.
@(private = "file")
foresee_undo :: proc(world: ^World, id: Soldier_Id, out: ^Tick_Output) {
	death := &world.foresight.deaths[id]
	killer := death.killer
	emit(out, Kill_Taken_Back{killer = killer, target = id, weapon = death.weapon, part = death.part})
	death^ = {}
	world.soldiers[id].tally.deaths = max(world.soldiers[id].tally.deaths - 1, 0)
	if world.soldiers[killer].tally.kills > 0 do world.soldiers[killer].tally.kills -= 1
}

// A death shown before the server's word that its word never confirmed: the soldier
// lives, and the feed takes back the line it gave the kill.
Kill_Taken_Back :: struct {
	killer: Soldier_Id,
	target: Soldier_Id,
	weapon: res.Weapon,
	part:   u8,
}

// Another's hit on the living, shown on a client by its own flight of the shot: the
// server's word of the same hit (Shot_Hit) shows no more blood.
Shown_Hit :: struct {
	set:    bool,
	owner:  Soldier_Id,
	shot:   u32,
	fired:  u32,
	target: Soldier_Id,
}

SHOWN_KEPT :: 64 // the hits shown remembered: far more than a round trip's

// Another's bullet met soldier `target` here, shown.
foresee_shown :: proc(world: ^World, bullet: ^Bullet, target: Soldier_Id) {
	f := &world.foresight
	f.shown[f.shown_next] = {set = true, owner = bullet.owner, shot = bullet.shot, fired = bullet.fired, target = target}
	f.shown_next = (f.shown_next + 1) % SHOWN_KEPT
}

// Whether this client showed that hit already, by its own flight of the shot.
foresee_was_shown :: proc(world: ^World, owner: Soldier_Id, shot, fired: u32, target: Soldier_Id) -> bool {
	for s in world.foresight.shown {
		if s.set && s.owner == owner && s.shot == shot && s.fired == fired && s.target == target do return true
	}
	return false
}
