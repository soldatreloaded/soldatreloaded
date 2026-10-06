package match

import sa "core:container/small_array"

import sim "../../../core/game"
import "../draw"
import "../hud"
import "../input"

// The camera while I watch (LocalInput.pas, "change camera when dead"): as I die it stays
// on my body; joining as a spectator, with no body, it goes to the first player up. Then,
// with no weapons menu open, fire follows the next player and jet the one before, among
// those alive I may watch (my team's, unless I am a spectator); jump, or freecam, is the
// free camera, which the cursor pushes; and fire with nobody to follow is that too.
// Alive, the camera is mine again. A demo is watched from outside, by my own keys and at
// any time: fire and jet go round the players and its recorder, jump is the free camera.
//
// And a scoped Barrett shot of mine (the original's bullet Tracking): the camera rides
// it, five ticks ahead, until it is gone or I stand up (graphics.track_shot).

SPECTATOR_AIM_DIST :: 30 // the free camera's speed, by the cursor's offset from the middle
TRACK_LEAD :: 5 // ticks of its flight the camera keeps ahead of a tracked shot

Watch :: struct {
	follow:       Maybe(sim.Soldier_Id), // the player the camera follows; nil for me
	free:         bool,                  // or the free camera
	keys:         sim.Buttons,           // last tick's, so a press switches once
	was_watching: bool,                  // dead or a spectator as of the last tick
	tracking:     Maybe(u32),            // the shot of mine the camera rides, by its number
}

// After each tick, on the keys I pressed in it.
watch_tick :: proc(match: ^Match, mine: sim.Command) {
	w := &match.watch
	me := &match.game.world.soldiers[match.me]
	pressed := mine.buttons - w.keys
	w.keys = mine.buttons
	watching := me.active && (me.vitals.dead || me.team == .Spectator)
	switch {
	case match.mode == .Demo:
		if hud.menus_any_open(&match.hud.menus) do break
		if .Jump in pressed {
			camera_free(match)
		} else if pressed & {.Fire, .Jet} != {} && !camera_next(match, .Jet in pressed) {
			w.follow, w.free = nil, false
		}
	case watching:
		if !w.was_watching {
			w.follow, w.free = nil, false
			if me.team == .Spectator && !camera_next(match, false) do camera_free(match)
		} else if .Weapons not_in match.hud.menus.open && pressed & {.Jump, .Fire, .Jet} != {} {
			if .Jump in pressed {
				camera_free(match)
			} else if !camera_next(match, .Jet in pressed) {
				camera_free(match)
			}
			input.input_centre(&match.input) // the original's cursor goes back to the middle on a switch
		}
	case:
		w.follow, w.free = nil, false
	}
	w.was_watching = watching
}

// freecam: the free camera, for a player who is dead or watching, or a demo playing.
freecam :: proc(match: ^Match) {
	me := &match.game.world.soldiers[match.me]
	watching := me.active && (me.vitals.dead || me.team == .Spectator) && .Weapons not_in match.hud.menus.open
	if watching || match.mode == .Demo do camera_free(match)
}

// Whom the sound is heard from: whom the camera follows; nil for the free camera.
watched :: proc(match: ^Match) -> Maybe(sim.Soldier_Id) {
	if match.watch.free do return nil
	return match.watch.follow.? or_else match.me
}

// Whether my aim is scoped: the shot fired from it snaps the view back within the tick,
// so this is asked before it.
scoped_now :: proc(match: ^Match) -> bool {
	me := &match.game.world.soldiers[match.me]
	return me.active && !me.vitals.dead && me.aim.distance < sim.DEFAULT_AIM_DISTANCE
}

// After the tick: a Barrett shot of mine this tick, scoped before it, is followed, the
// newest if there are several; until it is gone or I stand up.
track_shot :: proc(match: ^Match, scoped: bool) {
	w := &match.watch
	if scoped && match.config.graphics.track_shot {
		for event in sa.slice(&match.game.output.events) {
			if fired, is_shot := event.(sim.Shot_Fired); is_shot && fired.shot.owner == match.me && fired.shot.weapon == .Barrett {
				w.tracking = fired.shot.number
			}
		}
	}
	shot, tracking := w.tracking.?
	if !tracking do return
	me := &match.game.world.soldiers[match.me]
	if !match.config.graphics.track_shot || !me.active || me.controls.stance == .Stand || my_shot(match, shot) == nil {
		w.tracking = nil
	}
}

// The camera's move at the end of a tick (UpdateFrame.pas): put ahead of the shot it
// rides, if it rides one (Bullets.pas, before the move); then pushed by the cursor while
// free, or chasing whom it follows where the tick left them and leading toward the
// cursor.
camera_tick :: proc(match: ^Match) {
	w := &match.watch
	camera := &match.camera
	followed := match.me
	if f, following := w.follow.?; following && match.game.world.soldiers[f].active do followed = f
	if shot, tracking := w.tracking.?; tracking {
		if bullet := my_shot(match, shot); bullet != nil do camera.pos = bullet.pos + bullet.velocity * TRACK_LEAD
	}
	cursor := cursor_aimed(match)
	if w.free {
		// still with the cursor in the middle: 10 either way, wider with a wider view
		ratio := camera.view.x / 640
		middle := cursor.x > 310 * ratio && cursor.x < 330 * ratio && cursor.y > 230 && cursor.y < 250
		if !middle do camera.pos += (cursor - camera.view / 2) / SPECTATOR_AIM_DIST
		return
	}
	soldier := &match.game.world.soldiers[followed]
	draw.camera_follow(camera, soldier.body.pos, cursor, soldier.aim.distance)
}

// The cursor the camera leads toward: a demo's recorder's own while the camera is on the
// recorder and no menu wants mine.
cursor_aimed :: proc(match: ^Match) -> [2]f32 {
	if recorders_cursor(match) do return match.playback.tick.cursor
	return match.input.cursor
}

// The cursor as drawn: as cursor_aimed, but mine between the last tick's start and now.
cursor_shown :: proc(match: ^Match) -> [2]f32 {
	if recorders_cursor(match) do return match.playback.tick.cursor
	return input.input_cursor_between(&match.input, match.frame.alpha)
}

@(private = "file")
recorders_cursor :: proc(match: ^Match) -> bool {
	w := &match.watch
	return match.mode == .Demo && w.follow == nil && !w.free && !hud.menus_any_open(&match.hud.menus)
}

// The next player to watch, from the one watched: alive, no spectator, and a teammate
// unless I am watching from outside (GetCameraTarget). False with nobody to watch. A
// demo's watcher is outside, and its recorder, alive or dead, is among those watched.
@(private = "file")
camera_next :: proc(match: ^Match, backwards: bool) -> bool {
	w := &match.watch
	soldiers := &match.game.world.soldiers
	me := &soldiers[match.me]
	demo := match.mode == .Demo
	outside := demo || me.team == .Spectator
	from := int(w.follow.? or_else match.me)
	for n in 1 ..= sim.MAX_PLAYERS {
		j := ((from + (-n if backwards else n)) % sim.MAX_PLAYERS + sim.MAX_PLAYERS) % sim.MAX_PLAYERS
		s := &soldiers[j]
		if sim.Soldier_Id(j) == match.me && demo && s.active && s.team != .Spectator {
			w.follow, w.free = nil, false
			return true
		}
		if sim.Soldier_Id(j) == match.me || !s.active || s.vitals.dead || s.team == .Spectator do continue
		if !outside && s.team != me.team do continue
		w.follow, w.free = sim.Soldier_Id(j), false
		return true
	}
	return false
}

@(private = "file")
camera_free :: proc(match: ^Match) {
	match.watch.follow, match.watch.free = nil, true
}

// My bullet `shot`, while it flies; nil once it is gone.
@(private = "file")
my_shot :: proc(match: ^Match, shot: u32) -> ^sim.Bullet {
	for &bullet in match.game.world.bullets {
		if bullet.active && bullet.owner == match.me && bullet.shot == shot do return &bullet
	}
	return nil
}
