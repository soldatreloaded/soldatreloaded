package client_test

import sa "core:container/small_array"
import "core:testing"

import "../../apps/client/hud"
import "../../core/game"
import "../../core/utils"

// The kill feed's count is the server's, as the Kill carries it (issue 12). The killer's
// tally here is the snapshot's, which the word of a kill can come before or after: a kill
// heard after the snapshot that counted it said that count and one more, and after a
// snapshot a kill behind, the last kill's count again. Two kills in a row, 53 then 54,
// read 53 and 53.
@(test)
kill_feed_counts :: proc(t: ^testing.T) {
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = false))
	defer game.game_destroy(g)
	testing.expect(t, game.game_start_round(g, "ctf_Ash", seed = 1))
	for i in 1 ..= 3 {
		game.apply_ruling(&g.world, &g.resources, game.Respawn{
			target = game.Soldier_Id(i), life = 1, team = .Alpha if i == 1 else .Bravo, primary = .AK74, secondary = .Knife,
			pos = game.spawn_point(g.world.polymap, .Alpha if i == 1 else .Bravo, &g.world.rng),
		})
	}
	names: [game.MAX_PLAYERS]string
	names[1], names[2], names[3] = "gov", "Anna", "Kebab"
	feed: hud.Feed
	feed.kill_length = 10
	killer := &g.world.soldiers[1]

	said :: proc(g: ^game.Game, feed: ^hud.Feed, names: ^[game.MAX_PLAYERS]string, kill: game.Kill) -> string {
		game.world_hear(&g.world, game.Ruling(kill), g.world.tick)
		commands: [game.MAX_PLAYERS]game.Command
		game.game_tick(g, &commands)
		hud.feed_tick(feed, g, names, 0)
		line := sa.get(feed.kills, sa.len(feed.kills) - (2 if kill.killer != kill.target else 1)) // the killer's, over the victim's
		return utils.short_string_text(&line.text)
	}
	killer.tally.kills = 53 // the snapshot, already counting the kill whose word comes now
	testing.expect_value(t, said(g, &feed, &names, game.Kill{killer = 1, target = 2, weapon = .AK74, kills = 53}), "gov (53)")
	testing.expect_value(t, killer.tally.kills, 53)
	killer.tally.kills = 53 // a snapshot from before the next kill
	testing.expect_value(t, said(g, &feed, &names, game.Kill{killer = 1, target = 3, weapon = .AK74, kills = 54}), "gov (54)")
	testing.expect_value(t, killer.tally.kills, 54)
	killer.tally.kills = 52 // one from before the last, come late
	testing.expect_value(t, said(g, &feed, &names, game.Kill{killer = 1, target = 1, weapon = .AK74, kills = 53}), "gov (53)") // a suicide: one less
}

// With kill_hide_mine, my own kills and deaths (and my self-kill) stay out of the kill
// feed, the big words about them still said; everyone else's are in it as before.
@(test)
kill_feed_hides_mine :: proc(t: ^testing.T) {
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = false))
	defer game.game_destroy(g)
	testing.expect(t, game.game_start_round(g, "ctf_Ash", seed = 1))
	for i in 1 ..= 3 {
		game.apply_ruling(&g.world, &g.resources, game.Respawn{
			target = game.Soldier_Id(i), life = 1, team = .Alpha if i == 1 else .Bravo, primary = .AK74, secondary = .Knife,
			pos = game.spawn_point(g.world.polymap, .Alpha if i == 1 else .Bravo, &g.world.rng),
		})
	}
	names: [game.MAX_PLAYERS]string
	names[1], names[2], names[3] = "gov", "Anna", "Kebab"
	feed: hud.Feed
	feed.kill_length = 10
	feed.kill_hide_mine = true
	me :: game.Soldier_Id(1)

	heard :: proc(g: ^game.Game, feed: ^hud.Feed, names: ^[game.MAX_PLAYERS]string, kill: game.Kill) {
		game.world_hear(&g.world, game.Ruling(kill), g.world.tick)
		commands: [game.MAX_PLAYERS]game.Command
		game.game_tick(g, &commands)
		hud.feed_tick(feed, g, names, me)
	}
	heard(g, &feed, &names, game.Kill{killer = me, target = 2, weapon = .AK74, kills = 1})
	testing.expect_value(t, sa.len(feed.kills), 0)
	testing.expect(t, feed.big.ticks > 0, "the big words about my kill still said")
	heard(g, &feed, &names, game.Kill{killer = 3, target = me, weapon = .AK74, kills = 1})
	heard(g, &feed, &names, game.Kill{killer = me, target = me, weapon = .AK74, kills = 0})
	testing.expect_value(t, sa.len(feed.kills), 0)
	heard(g, &feed, &names, game.Kill{killer = 2, target = 3, weapon = .AK74, kills = 1})
	testing.expect_value(t, sa.len(feed.kills), 2) // another's kill, the killer's line and the victim's
	line := sa.get(feed.kills, 0)
	testing.expect_value(t, utils.short_string_text(&line.text), "Anna (1)")
}

// The referee counts the kill into the Kill: the killer's kills with it, a suicide's one
// less, never below none.
@(test)
kill_counted_in_ruling :: proc(t: ^testing.T) {
	g := new(game.Game)
	defer free(g)
	testing.expect(t, game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = true))
	defer game.game_destroy(g)
	testing.expect(t, game.game_start_round(g, "ctf_Ash", seed = 1))
	game.soldier_place(g, 1, .Alpha, remote = false)
	game.soldier_place(g, 2, .Bravo, remote = false)
	g.world.soldiers[1].tally.kills = 5
	commands: [game.MAX_PLAYERS]game.Command
	for slot in ([]game.Soldier_Id{1, 2}) {
		game.world_ask_kill(&g.world, slot, false)
		game.game_tick(g, &commands)
		found := false
		for ruling in sa.slice(&g.output.rulings) {
			kill := ruling.(game.Kill) or_continue
			found = true
			testing.expect_value(t, kill.kills, 4 if slot == 1 else 0)
			testing.expect_value(t, g.world.soldiers[slot].tally.kills, kill.kills)
		}
		testing.expect(t, found, "a Kill ruled")
	}
}
