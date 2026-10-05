package bots

import "core:fmt"

import "../game"
import res "../resources"
import "../utils"

// ControlBot: one tick of one bot's thinking. Who it can see decides whether it fights
// (decision.odin) or walks (waypoints.odin); then what it is drawn off by (things.odin),
// what it runs from, and the timeouts that free it when the path leads nowhere.

// The original's distances, on one axis (AI.pas).
DIST_AWAY :: 731
DIST_TOO_FAR :: 730
DIST_VERY_FAR :: 500
DIST_FAR :: 350
DIST_ROCK_THROW :: 180
DIST_CLOSE :: 95
DIST_VERY_CLOSE :: 55
DIST_TOO_CLOSE :: 35

WAYPOINT_TIMEOUT_SMALL :: game.TICK_RATE * 5 + 20 // Constants.pas
WAYPOINT_TIMEOUT_BIG :: game.TICK_RATE * 8
WAYPOINT_SEEK_RADIUS :: 21
HURT_HEALTH :: 25
FRAG_GRENADE_EXPLOSION_RADIUS :: f32(85)
SEE_DISTANCE :: f32(651) // how far a bot's ray reaches (Map.RayCast's MaxDist in ControlBot)
HEAD :: 11               // the skeleton's point 12, the original's LookPoint

// The keys that move: what a waypoint lays on a bot, and what a camping one lets go of.
MOVE_KEYS :: game.Buttons{.Left, .Right, .Jump, .Crouch, .Jet}

brain_think :: proc(b: ^Bots, br: ^Brain, g: ^game.Game, names: ^[game.MAX_PLAYERS]string, me: game.Soldier_Id) {
	world := &g.world
	polymap := world.polymap
	s := &world.soldiers[me]
	c := &br.keys
	difficulty := b.settings.difficulty

	// FreeControls: all but a grenade being wound up
	was_throwing := .Throw in c^
	c^ = {}
	if s.pose.body.id == .Throw && was_throwing do c^ += {.Throw}

	look := head_of(g, s)
	look.y -= 2.0

	// who can be seen: the closest enemy, from the head, through the map
	see_closest := false
	d := f32(999999)
	for &o, i in world.soldiers {
		if !o.active || game.Soldier_Id(i) == me || o.team == .Spectator do continue
		if is_friend(br, names, i) do continue
		fresh_corpse := o.vitals.dead && br.profile.shoot_dead && world.corpses[i].active && world.corpses[i].dead_time < 180
		if o.vitals.dead && !fresh_corpse do continue
		start := head_of(g, &o)
		if _, inside := res.inside_solid(polymap, start, false); inside do start.y += 6.0 // the ray's start not in the map
		hit, blocked := res.ray_cast(polymap, look, start, SEE_DISTANCE)
		if blocked do continue
		if d > hit.distance {
			br.target = game.Soldier_Id(i)
			if !o.vitals.dead do d = hit.distance
			see_closest = true
			if o.vitals.dead do c^ -= {.Throw, .Drop} // no grenades or knives at a corpse
			if o.team == s.team do see_closest = false
		}
	}

	// a grudge is never against itself, nor a teammate, whose hits don't wound
	if who, has := br.pissed_off.?; has {
		if who == me || world.soldiers[who].team == s.team do br.pissed_off = nil
	}
	if who, has := br.pissed_off.?; has { // whoever hit me, if I can see them
		o := &world.soldiers[who]
		_, blocked := res.ray_cast(polymap, look, head_of(g, o), SEE_DISTANCE)
		if o.active && !blocked {
			br.target = who
			see_closest = true
		} else {
			br.pissed_off = nil
		}
	}

	// with the flag and unhurt: run
	run_away := false
	if see_closest && holding_flag(world, s) && world.soldiers[br.target].carrying.held == nil {
		see_closest = false
		run_away = true
	}

	if !see_closest { // nobody in sight: the waypoints
		walk_waypoints(b, br, g, me, run_away)
	} else { // a target: fight it
		if br.current_waypoint != 0 && waypoint_at(polymap, br.current_waypoint).action == 0 do br.current_waypoint = 0
		simple_decision(b, br, g, me)
		if br.current_waypoint > 0 && s.carrying.held == nil && waypoint_at(polymap, br.current_waypoint).action == 1 { // camp
			c^ -= MOVE_KEYS
		}
		if b.settings.chat {
			if roll(br, 115 * int(br.chat_freq)) == 0 do bot_say(b, me, utils.short_string_text(&br.profile.chat_see_enemy))
			if roll(br, 790 * int(br.chat_freq)) == 0 {
				line: [128]u8
				name := "you"
				if names != nil && names[br.target] != "" do name = names[br.target]
				bot_say(b, me, fmt.bprintf(line[:], "Die %s!", name))
			}
		}
		br.waypoint_time = 0
	}

	look_for_things(b, br, g, me, run_away)

	// a grenade near: away from it
	if difficulty < 201 {
		for &bu in world.bullets {
			if !bu.active || bu.style != .Frag_Grenade do continue
			if utils.length(bu.pos - s.body.pos) >= FRAG_GRENADE_EXPLOSION_RADIUS * 1.4 do continue
			c^ -= {.Left, .Right}
			if bu.pos.x > s.body.pos.x {
				c^ += {.Left}
			} else {
				c^ += {.Right}
			}
		}
	}

	// the grenade goes once wound up
	if s.pose.body.id == .Throw && s.pose.body.frame > 35 do c^ -= {.Throw}

	br.waypoint_timeout_counter -= 1
	if br.waypoint_timeout_counter < 0 { // too long on the way: back to the last one, with a jump
		br.current_waypoint = br.old_waypoint
		br.waypoint_timeout_counter = WAYPOINT_TIMEOUT_SMALL
		c^ = {.Jump}
	}
	if br.waypoint_time > WAYPOINT_TIMEOUT_BIG { // a waypoint that leads nowhere: forget it
		c^ = {}
		br.current_waypoint = 0
		br.go_thing = false
		br.waypoint_time = 0
	}

	// a fall to break with the jets
	if s.body.velocity.y > 3.35 do br.fall_save = true
	if s.body.velocity.y < 1.35 do br.fall_save = false
	if br.fall_save do c^ += {.Jet}

	if b.settings.chat && roll(br, int(br.chat_freq) * 150) == 0 && is_soldier(top_scorer(world), me) {
		bot_say(b, me, utils.short_string_text(&br.profile.chat_winning))
	}

	if roll(br, 190) == 0 do br.pissed_off = nil

}

// ---------------------------------------------------------------------------------
// What the thinking reads

// Where a soldier looks from and is seen at.
head_of :: proc(g: ^game.Game, s: ^game.Soldier) -> utils.Vec2 {
	return game.soldier_pose(g.resources.animations, s, s.body.pos)[HEAD]
}

// The player in slot `i` is the profile's friend, by name.
is_friend :: proc(br: ^Brain, names: ^[game.MAX_PLAYERS]string, i: int) -> bool {
	if names == nil || names[i] == "" do return false
	friend := utils.short_string_text(&br.profile.friend)
	return friend != "" && names[i] == friend
}

// A bullet's speed out of the muzzle, which the aim leads by; never zero.
weapon_speed :: proc(g: ^game.Game, weapon: res.Weapon) -> f32 {
	speed := g.resources.weapons[weapon].stats.speed
	return speed if speed > 0.0 else 1.0
}

is_melee :: proc(weapon: res.Weapon) -> bool {
	return weapon == .Punch || weapon == .Knife || weapon == .Chainsaw
}

// The team's flag thing: the original's TeamFlag[team].
team_flag :: proc(world: ^game.World, team: res.Team) -> Maybe(game.Thing_Id) {
	kind: game.Thing_Kind
	#partial switch team {
	case .Alpha: kind = .Alpha_Flag
	case .Bravo: kind = .Bravo_Flag
	case:        return nil
	}
	for &thing, i in world.things {
		if thing.kind == kind do return game.Thing_Id(i)
	}
	return nil
}

holding_flag :: proc(world: ^game.World, s: ^game.Soldier) -> bool {
	held, has := s.carrying.held.?
	return has && game.thing_is_flag(world.things[held].kind)
}

// The player with the most kills: the original's SortedPlayers[1].
top_scorer :: proc(world: ^game.World) -> (best: Maybe(game.Soldier_Id)) {
	for &s, i in world.soldiers {
		if !s.active || s.team == .Spectator do continue
		if leader, has := best.?; !has || s.tally.kills > world.soldiers[leader].tally.kills do best = game.Soldier_Id(i)
	}
	return
}

is_soldier :: proc(id: Maybe(game.Soldier_Id), who: game.Soldier_Id) -> bool {
	some, has := id.?
	return has && some == who
}

// Clears left and right and presses the one toward `to` from `from`.
press_toward :: proc(c: ^game.Buttons, from, to: utils.Vec2) {
	c^ -= {.Left, .Right}
	if to.x > from.x {
		c^ += {.Right}
	} else if to.x < from.x {
		c^ += {.Left}
	}
}

// Clears left and right and presses the one away from `away` from `from`.
press_away :: proc(c: ^game.Buttons, from, away: utils.Vec2) {
	c^ -= {.Left, .Right}
	if away.x < from.x {
		c^ += {.Right}
	} else if away.x > from.x {
		c^ += {.Left}
	}
}
