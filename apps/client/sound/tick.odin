package sound

import sa "core:container/small_array"

import sim "../../../core/game"
import "../../../core/utils"
import "../draw"

// Once per tick, after the game's and the sparks': where I listen from, then everything
// that sounded. `me` is my soldier, for what is mine (my death, my kills, my ears);
// `followed` is the soldier the camera follows, whose place the listener takes (the
// original's CameraFollowSprite: me alive, whom I watch dead), or nil for the free
// camera, which listens from the view's centre `camera`.
sound_tick :: proc(s: ^Sound, game: ^sim.Game, me: sim.Soldier_Id, followed: Maybe(sim.Soldier_Id), camera: utils.Vec2, sparks: ^draw.Sparks) {
	if !s.ready do return
	world := &game.world
	followed := followed
	if id, ok := followed.?; ok && !world.soldiers[id].active do followed = nil
	s.camera = camera
	s.listener = camera
	if id, ok := followed.?; ok do s.listener = world.soldiers[id].body.pos
	if s.ringing > -1 do s.ringing -= 1
	loops_age(s)

	// paused, the soldiers' voices stop (ClientHandleServerSyncMsg): a jet or a reload
	// would sound on for as long as the pause lasts; nothing new sounds till it ends
	if _, paused := game.round.phase.(sim.Paused); paused {
		for &voices in s.reserved {
			for &r in voices do reserved_stop(s, &r)
		}
		return
	}

	clock_sounds(s, &game.round)
	for event in sa.slice(&game.output.events) do event_sounds(s, event, world, me)
	for ruling in sa.slice(&game.output.rulings) do ruling_sounds(s, ruling, world, me)
	for id in 0 ..< sim.MAX_PLAYERS do soldier_sounds(s, game, sim.Soldier_Id(id))
	bullet_sounds(s, game, followed)
	for noise in sa.slice(&sparks.noises) do noise_sounds(s, noise)

	// the weather (WeatherEffects.pas): the wind, the one loop the original gives rain,
	// sandstorm and snow alike, from the camera, kept up by being played every tick
	weather := world.polymap.weather
	if weather >= 1 && weather <= 3 && s.weather {
		reserved_play(s, &s.wind, "sfx_wind.wav", s.camera)
	} else {
		reserved_stop(s, &s.wind)
	}
}

// The time-left beeps, closer together toward the end: every second of the last ten,
// every ten of the last minute, every minute of the last five, every five before.
@(private = "file")
clock_sounds :: proc(s: ^Sound, round: ^sim.Round) {
	if _, playing := round.phase.(sim.Playing); !playing do return
	t := round.time_left
	SECOND :: sim.TICK_RATE
	beep: bool
	switch {
	case t >= 1 && t <= 10 * SECOND:    beep = t % SECOND == 0
	case t > 10 * SECOND && t <= 60 * SECOND:   beep = t % (10 * SECOND) == 0
	case t > 60 * SECOND && t <= 300 * SECOND:  beep = t % (60 * SECOND) == 0
	case t > 300 * SECOND:                      beep = t % (300 * SECOND) == 0
	}
	if beep do sound_flat(s, "signal.wav")
}

// A whistle 25 ticks into any round's flight but a shotgun's, and a whizz the first time
// a bullet enters the box around the soldier the camera follows, unless it is that
// soldier's own; nothing whizzes past the free camera.
@(private = "file")
bullet_sounds :: proc(s: ^Sound, game: ^sim.Game, followed: Maybe(sim.Soldier_Id)) {
	for &bullet, i in game.world.bullets {
		if !bullet.active {
			s.whizzed[i] = false
			continue
		}
		if bullet.timeout == game.resources.weapons[bullet.weapon].timeout - 25 && bullet.style != .Shotgun {
			play_at(s, "bulletby.wav", bullet.pos)
		}
		listener, following := followed.?
		if s.whizzed[i] || !following || bullet.owner == listener || bullet.style == .Punch do continue
		d := bullet.pos - s.listener
		if d.x > -200 && d.x < 200 && d.y > -350 && d.y < 100 {
			play_at(s, pick(s, WHIZZES[:]), bullet.pos)
			s.whizzed[i] = true
		}
	}
}

// What the sparks sounded like: casings and clips landing, a body burning.
@(private = "file")
noise_sounds :: proc(s: ^Sound, noise: draw.Spark_Noise) {
	switch noise.kind {
	case .Shell:       play_at(s, pick(s, SHELLS[:]), noise.pos)
	case .Gauge_Shell: play_at(s, "gaugeshell.wav", noise.pos)
	case .Clip:        play_at(s, "clipfall.wav", noise.pos)
	case .On_Fire:     play_at(s, "onfire.wav", noise.pos)
	case .Fire_Crack:  play_at(s, "firecrack.wav", noise.pos)
	}
}

// One of a few samples, at random.
pick :: proc(s: ^Sound, names: []string) -> string {
	return names[sim.rng_below(&s.rng, len(names))]
}

@(private = "file", rodata)
WHIZZES := [?]string{"bulletby2.wav", "bulletby3.wav", "bulletby4.wav", "bulletby5.wav"}

@(private = "file", rodata)
SHELLS := [?]string{"shell.wav", "shell2.wav"}
