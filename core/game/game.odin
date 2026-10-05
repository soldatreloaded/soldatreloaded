package game

import res "../resources"

// A game as one machine runs it: the world, the round around it, and, where this machine
// decides, the authority. The server has authority; so do Offline Play, tests and tools.
// A client has none: it steps the same world, applies the rulings the server sends, and
// takes its round from the snapshots.
//
// Its life:
//
//   game_init         once: the settings, the resources, the authority
//   game_start_round  for each map: the map, and a fresh world and round on it
//   game_tick         every tick, until round_over; then the next round

// What the game plays by: maps/, anims/ and objects/. Relative to the working directory,
// which is the install's root: assets/ in this repository, the unpacked folder in a release.
DATA_DIR :: "data"

Game :: struct {
	settings:  Game_Settings, // given to game_init, never changed
	resources: Resources,     // loaded by game_init, never changed
	polymap:   res.Poly_Map,  // this round's map, which world.polymap points at
	world:     World,         // everything that is
	round:     Round,         // the clock and the captures
	authority: ^Authority,    // the referee's memory; nil where this machine doesn't decide
	output:    Tick_Output,   // what the last tick produced: its events and rulings
}

// `authority` where this machine decides. False, with the reason logged, if the
// resources can't be loaded. Free with game_destroy.
game_init :: proc(game: ^Game, settings: Game_Settings, authority: bool) -> bool {
	game.settings = settings
	game.resources = resources_load(game.settings.weapons) or_return
	if authority {
		game.authority = new(Authority)
	}
	return true
}

// A new round on maps/<map_name>.pms: the last round's map let go, the world empty but for
// the map's things, the round's clock full. False, with the reason logged, if the map
// can't be loaded; the last round is left as it was.
game_start_round :: proc(game: ^Game, map_name: string, seed: u64) -> bool {
	polymap := res.map_load(DATA_DIR, map_name) or_return
	res.map_destroy(&game.polymap)
	game.polymap = polymap

	game.round = round_init(&game.settings)
	if game.authority != nil {
		game.authority.history = {} // the past was another map's
	}
	world_init(&game.world, &game.polymap, game.settings.gravity, seed)
	game.world.rules = round_rules(&game.round, &game.settings)
	things_place(&game.world, &game.resources)
	return true
}

// One tick: the world, judged as it goes where this machine decides; then the round.
game_tick :: proc(game: ^Game, commands: ^[MAX_PLAYERS]Command) {
	game.world.rules = round_rules(&game.round, &game.settings)
	world_step(&game.world, &game.resources, commands, &game.output, game.authority)

	if game.authority != nil {
		round_update(&game.round, &game.settings, &game.world, &game.resources, &game.output)
		history_record(&game.authority.history, &game.world)
	}
}

game_destroy :: proc(game: ^Game) {
	res.map_destroy(&game.polymap)
	resources_destroy(&game.resources)
	free(game.authority)
	game^ = {}
}

// ---------------------------------------------------------------------------------
// Resources

// The animations, the skeletons, and the weapons playing by `weapons`.
resources_load :: proc(weapons: res.Weapon_Table) -> (resources: Resources, ok: bool) {
	defer if !ok {
		resources_destroy(&resources)
	}
	resources.animations = res.animations_load(DATA_DIR) or_return
	resources.skeletons = res.skeletons_load(DATA_DIR) or_return
	resources.weapons = weapons_make(weapons)
	return resources, true
}

resources_destroy :: proc(resources: ^Resources) {
	free(resources.animations)
	res.skeletons_destroy(&resources.skeletons)
	resources^ = {}
}
