package game

import res "../resources"
import "../utils"

// The idle antics and the taunts (Control.pas, the IDLE block of ControlSprite). Standing
// still long enough a soldier chews tobacco and spits, lights a cigar, wipes its brow or
// scratches; by chat a player asks for those and the rest (/tabac, /smoke, /takeoff,
// /victory, /piss, /mercy, /pwn, and the community's cheers past the original's:
// /breakdown, /dab, /yeah). The server picks the idle antic, and relays every ask
// as a numbered antic (antics.asked). The machine runs on the soldier's own animations
// wherever it is stepped: its owner's run is the one that counts, the others' keep the
// sparks in step. The sounds are read off the animations; the sparks go out as Antic.

LONGER_IDLE_TIME :: 60 * 30 // a lit cigar is smoked this long

// The antics, as antics.idle_antic numbers them (the original's IdleRandom).
ANTIC_TOBACCO :: 0
ANTIC_CIGAR :: 1
ANTIC_WIPE :: 2
ANTIC_GROIN :: 3
ANTIC_TAKE_OFF :: 4
ANTIC_VICTORY :: 5
ANTIC_PISS :: 6
ANTIC_MERCY :: 7
ANTIC_PWN :: 8
ANTIC_BREAKDOWN :: 9 // the community's cheers, past the original's: a taunt each
ANTIC_DAB :: 10
ANTIC_YEAH :: 11

// The taunts a player asks for in the chat, by the antic each is (CommandPlayerCommand);
// none for the idle antics no one asks for.
@(rodata)
TAUNT_NAMES := [?]string {
	ANTIC_TOBACCO   = "tabac",
	ANTIC_CIGAR     = "smoke",
	ANTIC_WIPE      = "",
	ANTIC_GROIN     = "",
	ANTIC_TAKE_OFF  = "takeoff",
	ANTIC_VICTORY   = "victory",
	ANTIC_PISS      = "piss",
	ANTIC_MERCY     = "mercy",
	ANTIC_PWN       = "pwn",
	ANTIC_BREAKDOWN = "breakdown",
	ANTIC_DAB       = "dab",
	ANTIC_YEAH      = "yeah",
}

// The taunt `name` asked of the soldier, by whoever decides its antics (the server, or
// Offline Play): its machine runs it as it next stands. A mercy costs a kill. False if
// there is no taunt by that name; a dead or absent soldier asks for nothing, and is
// answered true.
soldier_taunt :: proc(soldier: ^Soldier, name: string) -> bool {
	for taunt, i in TAUNT_NAMES {
		if taunt == "" || taunt != name do continue
		if !soldier.active || soldier.vitals.dead do return true
		soldier.antics.asked = i8(i)
		soldier.antics.asked_count += 1
		if i == ANTIC_MERCY && soldier.tally.kills > 0 do soldier.tally.kills -= 1
		return true
	}
	return false
}

// One tick of the soldier's antics; `armed` as soldier_update's, for the mercy's shot.
soldier_antics :: proc(world: ^World, resources: ^Resources, id: Soldier_Id, authority: ^Authority, out: ^Tick_Output, armed: bool) {
	soldier := &world.soldiers[id]
	animations := resources.animations
	body, legs := &soldier.pose.body, &soldier.pose.legs
	antics := &soldier.antics
	dir := f32(soldier.body.direction)

	// an ask of the server's, taken once: what the original does to the sprite on the
	// server (IdleRandom := n; IdleTime := 1), done here where the soldier is played
	if antics.seen_count != antics.asked_count {
		antics.seen_count = antics.asked_count
		antics.idle_antic = antics.asked
		antics.idle_time = 1
	}

	// the clock runs down while standing still, and on through an antic's longer wait; as
	// it runs out the server picks one of the four idle antics, and asks it of the owner
	still := body.id == .Stand && legs.id == .Stand && !soldier.vitals.dead && antics.idle_time > 0
	if still || antics.idle_time > DEFAULT_IDLE_TIME {
		antics.idle_time -= 1
	} else {
		antics.idle_time = DEFAULT_IDLE_TIME
	}
	if authority != nil && antics.idle_time == 1 && antics.idle_antic < 0 {
		antics.idle_time = 0
		antics.idle_antic = i8(rng_below(&world.rng, 4))
		antics.asked = antics.idle_antic
		antics.asked_count += 1
		antics.seen_count = antics.asked_count
	}

	switch antics.idle_antic {
	case ANTIC_TOBACCO: // a chew, and the spit when the clock next runs out
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Smoke)
			antics.idle_time = DEFAULT_IDLE_TIME
		}
		if body.id == .Smoke && body.frame == 17 do body.frame += 1 // (the chew is heard as 17 is stepped over)
		if !soldier.vitals.dead && antics.idle_time == 1 && body.id != .Smoke && legs.id == .Stand {
			joints := soldier_pose(animations, soldier, soldier.body.pos)
			antic(out, id, .Spit, joints[11], hands_aim_direction(&joints) * 2.0, 1, 245)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_CIGAR: // out of the pocket (1, 2), lit with a match (3 to 5), smoked (6, 7), thrown away (8)
		if soldier.vitals.dead do break
		if antics.idle_time == 0 {
			switch antics.cigar {
			case 0:
				if body.id == .Stand { // 1
					res.animation_switch(animations, body, .Cigar)
					antics.idle_time = DEFAULT_IDLE_TIME
				}
			case 5:
				if body.id != .Smoke && body.id != .Cigar { // broken off between 2 and 5: from the top
					antics.cigar = 0
					res.animation_switch(animations, body, .Cigar)
					antics.idle_time = DEFAULT_IDLE_TIME
				}
			case 10:
				if body.id != .Smoke { // 6
					res.animation_switch(animations, body, .Smoke)
					antics.idle_time = DEFAULT_IDLE_TIME
				}
			}
		}
		if body.id == .Cigar && body.frame == 37 && antics.cigar == 5 { // 3: the hand goes back for the match
			res.animation_switch(animations, body, .Stand)
			res.animation_switch(animations, body, .Cigar)
		}
		if body.id == .Cigar && body.frame == 9 && antics.cigar == 5 do body.frame += 1 // 4: the match (heard)
		if body.id == .Cigar && body.frame == 26 {
			joints := soldier_pose(animations, soldier, soldier.body.pos)
			if antics.cigar == 5 { // 5: lit
				antics.cigar = 10
				antic(out, id, .Cigar_Puff, joints[11] + utils.Vec2{dir * 4, 0}, {0, -0.7}, 1, 65)
				antic(out, id, .Match, joints[14], {dir / 2, 0.15}, 1, 245)
				body.frame += 1
				antics.idle_time = LONGER_IDLE_TIME
			} else if antics.cigar == 0 { // 2: in the mouth
				antics.cigar = 5
				body.frame += 1
			}
		}
		if body.id == .Smoke && (body.frame == 17 || body.frame == 37) { // 7: a puff
			joints := soldier_pose(animations, soldier, soldier.body.pos)
			antic(out, id, .Cigar_Puff, joints[11] + utils.Vec2{dir * 4, 0}, {0, -0.7}, 1, 65)
			body.frame += 1
		}
		if body.id == .Smoke && body.frame == 38 { // 8: the stub flicked away
			joints := soldier_pose(animations, soldier, soldier.body.pos)
			antics.cigar = 0
			antic(out, id, .Cigar_Throw, joints[14], {dir / 1.5, 0.1}, 1, 245)
			body.frame += 1
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_WIPE:
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Wipe)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_GROIN:
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Groin)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_TAKE_OFF: // the helmet off from the first frame, back on from the tenth
		if antics.idle_time == 0 {
			if antics.helmet == 1 do res.animation_switch(animations, body, .Take_Off)
			if antics.helmet == 2 do res.animation_switch(animations, body, .Take_Off, 10)
			antics.idle_time = DEFAULT_IDLE_TIME
		}
		if antics.helmet == 1 {
			if body.id == .Take_Off && body.frame == 15 {
				antics.helmet = 2
				body.frame += 1
			}
		} else if antics.helmet == 2 {
			if body.id == .Take_Off && body.frame == 22 {
				res.animation_switch(animations, body, .Stand)
				antics.idle_antic = -1
			}
			if body.id == .Take_Off && body.frame == 15 {
				antics.helmet = 1
				body.frame += 1
			}
		}

	case ANTIC_VICTORY: // (the roar is heard as it begins)
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Victory)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_PISS: // the stream through the animation, in three strengths, as sparks
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Piss)
			antics.idle_time = DEFAULT_IDLE_TIME
		}
		if body.id == .Piss {
			f := body.frame
			speed: f32
			odds, life: u8
			switch {
			case f > 8 && f < 22:  speed, odds, life = 1.3, 2, 165
			case f > 21 && f < 34: speed, odds, life = 1.9, 3, 120
			case f > 33 && f < 35: speed, odds, life = 1.3, 4, 120
			}
			if odds != 0 {
				joints := soldier_pose(animations, soldier, soldier.body.pos)
				stream := utils.normalize(joints[19] - soldier.controls.aim) * -speed
				antic(out, id, .Piss, joints[19], stream, odds, life)
			}
			if f == 37 do antics.idle_antic = -1
		}

	case ANTIC_MERCY: // armed by the first ask, done on the second (CanMercy)
		if antics.idle_time == 0 {
			if antics.can_mercy {
				weapon := soldier.arsenal.primary.weapon
				if long_barrelled(weapon) {
					res.animation_switch(animations, body, .Mercy2)
					res.animation_switch(animations, legs, .Mercy2)
				} else if weapon != .Minigun {
					res.animation_switch(animations, body, .Mercy)
					res.animation_switch(animations, legs, .Mercy)
				}
				antics.idle_time = DEFAULT_IDLE_TIME
				antics.can_mercy = false
			} else {
				antics.idle_antic = -1
				antics.can_mercy = true
			}
		}
		if (body.id == .Mercy || body.id == .Mercy2) && body.frame == 20 {
			body.frame += 1
			antics.idle_antic = -1
		}

	case ANTIC_PWN:
		if antics.idle_time == 0 {
			res.animation_switch(animations, body, .Own)
			res.animation_switch(animations, legs, .Own)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}

	case ANTIC_BREAKDOWN, ANTIC_DAB, ANTIC_YEAH: // as the victory, silent
		if antics.idle_time == 0 {
			cheer: res.Animation_Id = .Breakdown if antics.idle_antic == ANTIC_BREAKDOWN else .Dab if antics.idle_antic == ANTIC_DAB else .Yeah
			res.animation_switch(animations, body, cheer)
			antics.idle_time = DEFAULT_IDLE_TIME
			antics.idle_antic = -1
		}
	}

	// The mercy's shot and the death it asks for, at the animation's 20th frame (its owner
	// fires; the original's client then sends /kill, and the server wounds it for 150, torn
	// apart when bare-handed). Read off the animation rather than the antic, once a run of
	// it, so the server, which has the owner's animation but not its antic's course, gives
	// the wound whichever frame it first sees past the 20th.
	mercy := body.id == .Mercy || body.id == .Mercy2
	if mercy && body.frame >= 20 && !antics.mercy_shot {
		antics.mercy_shot = true
		if armed do soldier_fire(world, resources, id, out)
		weapon := soldier.arsenal.primary.weapon
		amount: f32 = 3423.0 if weapon == .Punch else 150.0
		emit(out, Hit{shooter = id, target = id, weapon = weapon, amount = amount, pos = soldier.body.pos})
	}
	if !mercy do antics.mercy_shot = false

	// The guns the mercy is done with the muzzle under the chin (Mercy2) rather than at
	// the temple (Mercy).
	long_barrelled :: proc(weapon: res.Weapon) -> bool {
		#partial switch weapon {
		case .M79, .Minimi, .Spas12, .LAW, .Chainsaw, .Barrett, .Minigun:
			return true
		}
		return false
	}
}

@(private = "file")
antic :: proc(out: ^Tick_Output, id: Soldier_Id, kind: Antic_Kind, pos, velocity: utils.Vec2, odds, life: u8) {
	emit(out, Antic{soldier = id, kind = kind, pos = pos, velocity = velocity, odds = odds, life = life})
}
