package bots

import "../game"
import res "../resources"
import "../utils"

// Walking the map's waypoints, with nobody in sight: the nearest one is taken up, the
// next picked from its connections, and its keys pressed; a waypoint that says to wait
// is waited at; standing still too long is being stuck, and a jump.
walk_waypoints :: proc(b: ^Bots, br: ^Brain, g: ^game.Game, me: game.Soldier_Id, run_away: bool) {
	world := &g.world
	polymap := world.polymap
	s := &world.soldiers[me]
	weapon := &s.arsenal.primary
	c := &br.keys
	difficulty := b.settings.difficulty
	if br.go_thing do return

	radius: f32 = 350.0 if br.current_waypoint == 0 else WAYPOINT_SEEK_RADIUS
	k := find_closest(polymap, s.body.pos, radius, br.current_waypoint)
	br.old_waypoint = br.current_waypoint

	if br.next_waypoint == 0 do br.next_waypoint = 1
	// the team's path; the other team's with the flag, which leads home
	br.path_num = i32(s.team)
	if holding_flag(world, s) do br.path_num = 2 if s.team == .Alpha else 1 if s.team == .Bravo else br.path_num

	if k > 0 && (br.path_num == i32(waypoint_at(polymap, k).path) || br.current_waypoint == 0) do br.current_waypoint = k

	if br.current_waypoint <= 0 || br.current_waypoint >= len(polymap.waypoints) do return
	cur := waypoint_at(polymap, br.current_waypoint)
	if br.old_waypoint != br.current_waypoint { // arrived: the next, one of its connections
		to := 0
		if len(cur.connections) > 0 do to = int(cur.connections[roll(br, len(cur.connections))])
		if to > 0 && to < len(polymap.waypoints) {
			br.next_waypoint = to
			br.aim = waypoint_at(polymap, to).pos // face it
		}
	}
	next := waypoint_at(polymap, br.next_waypoint)
	c^ -= MOVE_KEYS
	if next.left do c^ += {.Left}
	if next.right do c^ += {.Right}
	if next.up do c^ += {.Jump}
	if next.down do c^ += {.Crouch}
	if next.jet do c^ += {.Jet}

	// a waypoint that says to wait, or to camp; not on the way home with the flag
	if s.carrying.held == nil {
		a, n := cur.action, br.one_place_count
		if a == 1 || (a == 2 && n < 60) || (a == 3 && n < 300) || (a == 4 && n < 600) || (a == 5 && n < 900) || (a == 6 && n < 1200) {
			c^ -= MOVE_KEYS
			if br.profile.camping > 0 && n > 180 do c^ += {.Crouch}
		}
	}

	// running away, fire back at whoever is shooting
	if who, has := br.pissed_off.?; run_away && has {
		o := &world.soldiers[who]
		br.aim.x = f32(utils.round_half_even(o.body.pos.x))
		br.aim.y = f32(utils.round_half_even(o.body.pos.y - 1.75 * 100.0 / weapon_speed(g, weapon.weapon) - f32(br.accuracy) + f32(roll(br, int(br.accuracy)))))
		c^ += {.Fire}
	}

	if br.last_waypoint == br.current_waypoint {
		br.waypoint_time += 1
	} else {
		br.waypoint_time = 0
	}
	br.last_waypoint = br.current_waypoint

	// standing in one place: stuck?
	if cur.action == 0 {
		if (.Left in c^ || .Right in c^) && .Crouch not_in c^ {
			if utils.length(s.body.pos - s.body.old_pos) < 3.0 {
				br.one_place_count += 1
			} else {
				br.one_place_count = 0
			}
		} else {
			br.one_place_count = 0
		}
	} else {
		br.one_place_count += 1
	}
	if cur.action == 0 && br.one_place_count > 90 { // stuck: jump
		if .Left in c^ && .Right in c^ do c^ -= {.Right}
		c^ += {.Jump}
	}

	// the secondary back to the primary
	if difficulty < 201 &&
	   (weapon.weapon == .USSOCOM || weapon.weapon == .Punch || weapon.weapon == .Knife || weapon.weapon == .Chainsaw || weapon.weapon == .LAW) &&
	   s.arsenal.secondary.weapon != .Punch {
		c^ += {.Change}
	}
	// reload while it is quiet
	if difficulty < 201 && weapon.ammo < 4 && g.resources.weapons[weapon.weapon].stats.ammo > 3 do c^ += {.Reload}
	// get up
	if roll(br, 150) == 0 && (s.pose.body.id == .Prone || s.pose.body.id == .Prone_Move) do c^ += {.Prone}
}

// The waypoint the map numbers `i`; a blank for a number off the map, as the original
// reads one.
waypoint_at :: proc(polymap: ^res.Poly_Map, i: int) -> res.Waypoint {
	if i > 0 && i < len(polymap.waypoints) do return polymap.waypoints[i]
	return {}
}

// TWaypoints.FindClosest: the first active waypoint within `radius`, other than `current`;
// 0 for none.
find_closest :: proc(polymap: ^res.Poly_Map, p: utils.Vec2, radius: f32, current: int) -> int {
	for i in 1 ..< len(polymap.waypoints) {
		waypoint := &polymap.waypoints[i]
		if !waypoint.active || i == current do continue
		if utils.length(p - waypoint.pos) < radius do return i
	}
	return 0
}
