package sound

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"

// What each event and ruling of a tick sounds like: the play sites of Sprites.pas,
// Bullets.pas and Things.pas, by way of the C client's audio_event.

GRENADE_EFFECT_DISTANCE :: 38.0 // a blast this near me rings my ears
GRENADE_EFFECT_TIME :: 320 // ticks they ring
CORPSE_CRACK_FALL :: 2.5 // a body falling this fast onto the map cracks
CORPSE_CRACK_LANDINGS :: 3 // on its first landings only
HEAD :: utils.Vec2{0, 12} // above a soldier's place, where its head is heard

// A weapon's shot (TSprite.Fire). The knife, the fists and the chainsaw make none when
// they fire: their swings and the chainsaw's loop follow the animation.
@(private = "file", rodata)
FIRE_SOUNDS := #partial [res.Weapon]string {
	.Desert_Eagles   = "deserteagle-fire.wav",
	.MP5             = "mp5-fire.wav",
	.AK74            = "ak74-fire.wav",
	.Steyr_AUG       = "steyraug-fire.wav",
	.Spas12          = "spas12-fire.wav",
	.Ruger77         = "ruger77-fire.wav",
	.M79             = "m79-fire.wav",
	.Barrett         = "barretm82-fire.wav",
	.Minimi          = "m249-fire.wav",
	.Minigun         = "minigun-fire.wav",
	.USSOCOM         = "colt1911-fire.wav",
	.LAW             = "law.wav",
	.Frag_Grenade    = "grenade-throw.wav",
}

// A kit taken; a gun is "takegun.wav".
@(private = "file", rodata)
KIT_SOUNDS := #partial [sim.Thing_Kind]string {
	.Medical_Kit = "takemedikit.wav",
	.Grenade_Kit = "pickupgun.wav",
}

// The far versions of a shot or blast (Sound.pas FPlaySound), for battle_effects.
@(private = "file", rodata)
DISTANT_GUNS := [?]string{"dist-gun1.wav", "dist-gun2.wav", "dist-gun3.wav", "dist-gun4.wav"}
@(private = "file", rodata)
GUNS_HEARD_FAR := [?]string {
	"ak74-fire.wav", "m249-fire.wav", "ruger77-fire.wav", "spas12-fire.wav", "deserteagle-fire.wav",
	"steyraug-fire.wav", "barretm82-fire.wav", "minigun-fire.wav", "colt1911-fire.wav",
}

@(private = "file", rodata)
WALL_HITS := [?]string{"ric.wav", "ric2.wav", "ric3.wav", "ric4.wav"}
@(private = "file", rodata)
RICOCHETS := [?]string{"ric5.wav", "ric6.wav", "ric7.wav"}
@(private = "file", rodata)
HIT_ARGS := [?]string{"hit-arg.wav", "hit-arg2.wav", "hit-arg3.wav"}
@(private = "file", rodata)
DEATHS := [?]string{"death.wav", "death2.wav", "death3.wav"}
@(private = "file", rodata)
CLOTH := [?]string{"flag.wav", "flag2.wav"}
@(private = "file", rodata)
KIT_FALLS := [?]string{"kit-fall.wav", "kit-fall2.wav"}

event_sounds :: proc(s: ^Sound, event: sim.Event, world: ^sim.World, me: sim.Soldier_Id) {
	#partial switch e in event {
	case sim.Fired:
		play_at(s, FIRE_SOUNDS[e.weapon], e.pos)
	case sim.Explosion:
		explosion_sounds(s, e, world, me)
	case sim.Grenade_Bounce:
		play_at(s, "grenade-bounce.wav", e.pos)
	case sim.Ricochet:
		play_at(s, pick(s, RICOCHETS[:]), e.pos)
	case sim.Wall_Hit:
		play_at(s, pick(s, WALL_HITS[:]), e.pos)
	case sim.Collider_Hit:
		play_at(s, "colliderhit.wav", e.pos)
		play_at(s, pick(s, WALL_HITS[:]), e.pos)
	case sim.Blood:
		target := &world.soldiers[e.target]
		switch {
		case target.vitals.dead: play_at(s, "dead-hit.wav", e.pos)
		case:                    play_at(s, pick(s, HIT_ARGS[:]), e.pos)
		}
	case sim.Corpse_Landed:
		// the thud of a body landing, and the crack of bones on a hard one; the cracks
		// stop as the body settles, so a corpse rolling to a stop does not rattle on
		play_at(s, "bodyfall.wav", e.pos)
		if e.fall > CORPSE_CRACK_FALL && e.landings < CORPSE_CRACK_LANDINGS do play_at(s, "bonecrack.wav", e.pos)
	case sim.Polygon_Effect:
		#partial switch e.polygon {
		case .Hurts:       play_at(s, "arg.wav", e.pos)
		case .Lava:        play_at(s, "lava.wav", e.pos)
		case .Regenerates: play_at(s, "regenerate.wav", e.pos)
		case .Explodes:    play_at(s, "explosion-erg.wav", e.pos)
		case .Bouncy:      play_at(s, "bounce.wav", e.pos)
		}
	case sim.Flag_Drop:
		// heard by the dropper's team, where it fell (the original plays it flat)
		if world.soldiers[e.soldier].team == world.soldiers[me].team do play_at(s, "infilt-point.wav", e.pos)
	case sim.Antic:
		// the spit, and the puff of smoke that lights the cigar or is drawn on it
		at := world.soldiers[e.soldier].body.pos
		#partial switch e.kind {
		case .Spit:       play_at(s, "spit.wav", at)
		case .Cigar_Puff: play_at(s, "smoke.wav", at)
		}
	case sim.Thing_Hit:
		// a landing, or (part 0 of a kit) cloth flapping
		#partial switch e.thing {
		case .Alpha_Flag, .Bravo_Flag, .Parachute: play_at(s, pick(s, CLOTH[:]), e.pos)
		case .Weapon:                              play_at(s, "weaponhit.wav", e.pos)
		case:
			if e.part != 0 do play_at(s, pick(s, KIT_FALLS[:]), e.pos)
		}
	}
}

// The blast by its kind, and the cry of everyone alive within it. One next to me rings
// my ears, with explosion_effects.
@(private = "file")
explosion_sounds :: proc(s: ^Sound, e: sim.Explosion, world: ^sim.World, me: sim.Soldier_Id) {
	mine := &world.soldiers[me]
	if s.explosions && mine.active && mine.vitals.health > -50 && utils.length(e.pos - mine.body.pos) < GRENADE_EFFECT_DISTANCE {
		s.ringing = GRENADE_EFFECT_TIME
		sound_flat(s, "hum.wav")
	}
	name := "explosion-erg.wav"
	#partial switch e.weapon {
	case .M79:          name = "m79-explosion.wav"
	case .Frag_Grenade: name = "grenade-explosion.wav"
	}
	play_at(s, name, e.pos)
	for &soldier in world.soldiers {
		if !soldier.active || soldier.vitals.dead || soldier.team == .Spectator do continue
		if utils.length(soldier.body.pos - e.pos) < e.radius do play_at(s, "explosion-erg.wav", soldier.body.pos)
	}
}

ruling_sounds :: proc(s: ^Sound, ruling: sim.Ruling, world: ^sim.World, me: sim.Soldier_Id) {
	#partial switch r in ruling {
	case sim.Kill:
		kill_sounds(s, r, world, me)
	case sim.Respawn:
		// one's own at the listener: the original's is at MySprite, its listener, and this
		// tick's listener may still be the soldier watched while it was dead
		if r.target == me do sound_flat(s, "wermusic.wav")
		else do play_at(s, "spawn.wav", r.pos)
	case sim.Pickup:
		at := world.soldiers[r.soldier].body.pos
		play_at(s, "takegun.wav" if r.kind == .Weapon else KIT_SOUNDS[r.kind], at)
	// The flag's: a capture and a return are heard wherever you are, flat, as the
	// original's, but a return only when my team's player made it (a spectator hears every
	// player's): not the enemy's, and not a flag timed out back to its base. The players
	// asked for it, a departure. The grab is from where it happened.
	case sim.Flag_Grab:
		play_at(s, "capture.wav", world.soldiers[r.soldier].body.pos)
	case sim.Flag_Return:
		by, returned := r.returner.?
		mine := world.soldiers[me].team
		if returned && (mine == .Spectator || world.soldiers[by].team == mine) do sound_flat(s, "capture.wav")
	case sim.Flag_Capture:
		sound_flat(s, "ctf.wav")
	}
}

// TSprite.Die and the kill message: the death by how bad it was.
@(private = "file")
kill_sounds :: proc(s: ^Sound, kill: sim.Kill, world: ^sim.World, me: sim.Soldier_Id) {
	head := kill.pos - HEAD
	health := world.soldiers[kill.target].vitals.health
	headshot := kill.part == 12
	headchop := health <= sim.HEADCHOP_DEATH_HEALTH || (headshot && kill.weapon == .Ruger77)
	switch {
	case health <= sim.BRUTAL_DEATH_HEALTH:
		play_at(s, "bryzg.wav", head)
	case headchop:
		if headshot && (kill.weapon == .Barrett || kill.weapon == .Ruger77) {
			if kill.weapon == .Barrett do play_at(s, "bryzg.wav", head)
			if kill.killer == me do sound_flat(s, "boomheadshot.wav")
		}
		play_at(s, "headchop.wav", head)
	case:
		play_at(s, pick(s, DEATHS[:]), kill.pos)
	}
	reserved_stop(s, &s.reserved[kill.target][.Reload])
	if kill.target == me do sound_flat(s, "playerdeath.wav")
}

// A shot's or blast's far sample, or none.
distant_sample :: proc(s: ^Sound, name: string) -> string {
	switch name {
	case "m79-explosion.wav":
		return "dist-m79.wav"
	case "grenade-explosion.wav":
		return "dist-grenade.wav"
	}
	for gun in GUNS_HEARD_FAR {
		if name == gun do return pick(s, DISTANT_GUNS[:])
	}
	return ""
}
