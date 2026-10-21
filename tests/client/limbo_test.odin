package client_test

import "core:testing"

import "../../apps/client/match"
import "../../core/game"
import res "../../core/resources"

// Joined while the game is paused, and placed: the weapons menu comes up for my first
// life, as it does while the round is played, and not only once the game goes on (it
// never did, and I went on with my fists). Once the round is over it waits for the next.
@(test)
weapons_menu_while_paused :: proc(t: ^testing.T) {
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = true))
	defer game.game_destroy(g)
	testing.expect(t, game.game_start_round(g, "ctf_Ash", seed = 1))
	g.world.soldiers[0].loadout = {.Punch, .Knife}
	game.soldier_place(g, 0, .Alpha, remote = false)
	config := res.DEFAULT_CLIENT_CONFIG
	m := new(match.Match)
	defer free(m)
	m.mode = .Online
	m.game = g
	m.config = &config
	m.limbo.team_asked = true

	g.round.phase = game.Ended{countdown = game.ROUND_END_TICKS}
	match.limbo_tick(m)
	testing.expect(t, .Weapons not_in m.hud.menus.open, "not over the round's scores")

	g.round.phase = game.Paused{}
	match.limbo_tick(m)
	testing.expect(t, .Weapons in m.hud.menus.open, "up while paused, for my first life")
}

// Offline, watching till I pick a team: the team menu comes up, not the weapons. Placed
// on alpha, the weapons menu comes up for that first life; switched to bravo alive, it
// comes up again, the new team's first life (it didn't, and bravo went on unarmed).
@(test)
weapons_menu_on_team_change :: proc(t: ^testing.T) {
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = true))
	defer game.game_destroy(g)
	testing.expect(t, game.game_start_round(g, "ctf_Ash", seed = 1))
	g.world.soldiers[0].loadout = {.Punch, .Knife}
	game.soldier_place(g, 0, .Spectator, remote = false)
	config := res.DEFAULT_CLIENT_CONFIG
	m := new(match.Match)
	defer free(m)
	m.mode = .Offline
	m.game = g
	m.config = &config

	match.limbo_tick(m)
	testing.expect(t, .Team in m.hud.menus.open, "the team asked, watching at the start")
	testing.expect(t, .Weapons not_in m.hud.menus.open, "no weapons while watching")

	game.soldier_place(g, 0, .Alpha, remote = false)
	match.limbo_tick(m)
	testing.expect(t, .Weapons in m.hud.menus.open, "up for the first life on alpha")

	m.hud.menus.open -= {.Weapons} // a primary picked
	match.limbo_tick(m)
	game.soldier_place(g, 0, .Bravo, remote = false)
	match.limbo_tick(m)
	testing.expect(t, .Weapons in m.hud.menus.open, "up again for the first life on bravo")
}
