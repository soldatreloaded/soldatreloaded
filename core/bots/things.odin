package bots

import "../game"
import res "../resources"
import "../utils"

// What draws a bot off its path: a flag, a kit it needs, a knife; in sight and near.
// A thing's interest is what a bot writes: counted down while bots go for it lying
// loose, so one nobody can reach is given up on.
look_for_things :: proc(b: ^Bots, br: ^Brain, g: ^game.Game, me: game.Soldier_Id, run_away: bool) {
	world := &g.world
	polymap := world.polymap
	s := &world.soldiers[me]
	c := &br.keys

	see_thing := false
	look := head_of(g, s)
	look.y -= 4.0
	for &th, i in world.things {
		if see_thing do break
		if th.kind == .None || is_soldier(th.holder, me) do continue
		knife := th.kind == .Weapon && th.weapon == .Knife
		wanted :=
			game.thing_is_flag(th.kind) ||
			knife ||
			(th.kind == .Medical_Kit && s.vitals.health < game.DEFAULT_HEALTH) ||
			(th.kind == .Grenade_Kit && s.arsenal.grenades < world.rules.max_grenades)
		if !wanted do continue
		start := utils.Vec2{th.points[1].x, th.points[1].y - 5.0}
		hit, blocked := res.ray_cast(polymap, look, start, SEE_DISTANCE)
		if blocked || hit.distance >= DIST_FAR do continue

		see_thing = true
		my_flag := game.thing_is_flag(th.kind) && int(th.kind) == int(s.team)
		mine := team_flag(world, s.team)
		// not my own flag at home, unless I carry theirs: then it is where I score
		if my_flag && th.in_base {
			see_thing = false
			if held, has := s.carrying.held.?; has && int(held) != i && is_soldier(world.things[held].holder, me) do see_thing = true
		}
		// not their flag while mine is away
		if flag, has := mine.?; !my_flag && has && !world.things[flag].in_base do see_thing = false
		// not their flag at home from afar
		if !my_flag && game.thing_is_flag(th.kind) && th.in_base && hit.distance > DIST_CLOSE do see_thing = false
		// hurt and a medikit close: take it
		if th.kind == .Medical_Kit && s.vitals.health < HURT_HEALTH && hit.distance < DIST_VERY_CLOSE do see_thing = true
		// not a kit while running with the flag
		if game.thing_is_kit(th.kind) && run_away do see_thing = false
		if knife do see_thing = true

		if !see_thing do continue
		if th.holder == nil do th.interest -= 1
		if th.interest > 0 {
			if b.settings.chat && game.thing_is_flag(th.kind) && roll(br, 400 * int(br.chat_freq)) == 0 do bot_say(b, me, "Flag!")
			br.go_thing = true
			go_to_thing(br, g, me, game.Thing_Id(i))
		} else {
			br.go_thing = false
		}
		if knife && s.arsenal.primary.weapon == .Punch && br.profile.favourite == .Knife { // my knife, back
			c^ -= {.Fire}
			br.target = 0
			br.go_thing = true
			go_to_thing(br, g, me, game.Thing_Id(i))
		}
	}
	if !see_thing do br.go_thing = false
}

// GoToThing: walk to a thing, by whichever of its two top points is nearer.
go_to_thing :: proc(br: ^Brain, g: ^game.Game, me: game.Soldier_Id, thing: game.Thing_Id) {
	world := &g.world
	s := &world.soldiers[me]
	th := &world.things[thing]
	c := &br.keys
	m := s.body.pos
	p1, p2 := th.points[0], th.points[1]
	t := p2
	if p2.x > p1.x && m.x < p2.x do t = p2
	if p2.x > p1.x && m.x > p1.x do t = p1
	if p2.x < p1.x && m.x < p1.x do t = p1
	if p2.x < p1.x && m.x > p2.x do t = p2
	if th.holder != nil do t.y += 5.0

	if t.x >= m.x {
		c^ += {.Right}
	} else if t.x < m.x {
		c^ += {.Left}
	}

	// following a teammate carrying the flag: keep behind it, jet as it does
	if holder, held := th.holder.?; held && team_flag(world, s.team) != nil {
		carrier := &world.soldiers[holder]
		if s.team == carrier.team && !th.in_base {
			dist_x := check_distance(m.x, t.x)
			if dist_x == DIST_TOO_CLOSE || dist_x == DIST_VERY_CLOSE {
				c^ -= {.Left, .Right}
				c^ += {.Crouch}
			}
			c^ -= {.Jet}
			if .Jet in carrier.controls.buttons do c^ += {.Jet}
		}
	}

	dist_y := check_distance(m.y, t.y)
	if dist_y >= DIST_VERY_CLOSE && m.y > t.y do c^ += {.Jet}
}
