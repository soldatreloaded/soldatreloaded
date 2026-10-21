package client_test

import sa "core:container/small_array"
import "core:testing"

import sim "../../core/game"

// A regenerating polygon heals, as OpenSoldat's HandleSpecialPolyTypes does: 2 health
// every twelfth tick to a wounded soldier on it, by the server, up to its fullest and no
// further; with the regenerate's sound everywhere, and no kill feed or aim's kick of it.
@(test)
regenerating_polygon_heals :: proc(t: ^testing.T) {
	g := new(sim.Game); defer free(g)
	testing.expect(t, sim.game_init(g, sim.DEFAULT_GAME_SETTINGS, authority = true))
	defer sim.game_destroy(g)
	testing.expect(t, sim.game_start_round(g, "ctf_Ash", seed = 1))
	for &polygon in g.polymap.polygons do if polygon.type == .Normal do polygon.type = .Regenerates
	sim.soldier_place(g, 0, .Alpha, remote = false)
	commands: [sim.MAX_PLAYERS]sim.Command
	for _ in 0 ..< 60 do sim.game_tick(g, &commands) // landed on the ground
	s := &g.world.soldiers[0]
	testing.expect(t, s.body.on_ground, "standing on it")

	s.vitals.health = 100
	effects, heals := 0, 0
	for _ in 0 ..< 120 {
		sim.game_tick(g, &commands)
		for event in sa.slice(&g.output.events) {
			if e, is := event.(sim.Polygon_Effect); is && e.polygon == .Regenerates do effects += 1
		}
		for ruling in sa.slice(&g.output.rulings) {
			if d, is := ruling.(sim.Damage); is && d.target == 0 && d.amount < 0 do heals += 1
		}
	}
	testing.expectf(t, heals == 10 && s.vitals.health == 120, "2 a twelfth tick: %d heals, health %v", heals, s.vitals.health)
	testing.expect_value(t, effects, 10)

	s.vitals.health = sim.DEFAULT_HEALTH - 1
	for _ in 0 ..< 60 do sim.game_tick(g, &commands)
	testing.expect_value(t, s.vitals.health, f32(sim.DEFAULT_HEALTH)) // to its fullest, no further
}
