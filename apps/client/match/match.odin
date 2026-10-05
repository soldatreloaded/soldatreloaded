package match

// Being in a game, a match: the world being played (core/game, imported as `sim`), the
// camera and spectating, dying and the weapons menu, chat. Each tick it builds my
// command, steps the world, and hands what happened to the drawing, the sound and the
// HUD. Offline, online and a demo differ only in where the other players come from.
//
// For now it is offline alone: this machine decides, I play against bots (core/bots, as a
// server plays them), on the limits and the bots of the config Local Play hosts with
// (server.config.json), and when a round is over the next starts on the next of its
// maps, or the same one again.
//
//   match.odin  the match's life, its frames and ticks, and the rounds
//   hud.odin    the HUD: its facts each frame, the keys its menus take and their choices
//               carried out, and when the weapons menu comes up by itself
//
// Uses: draw, hud, sound, input, net, demo. From the C client: most of main.c (tick,
// the camera, limbo, chat, votes, the HUD's data).

import sa "core:container/small_array"
import "core:strings"
import "core:time"

import ai "../../../core/bots"
import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"
import "../draw"
import "../hud"
import "../input"
import "../sound"
import "../ui"

ME :: sim.Soldier_Id(0) // the bots are the soldiers after me

Match :: struct {
	game:       ^sim.Game,
	maps:       []string, // its own copies, played in turn
	map_index:  int,
	map_name:   string, // the one being played, which the menu is given back
	bot_counts: res.Bot_Settings, // how many bots, on which teams
	mod:        res.Mod, // the art of each next map is the mod's
	art:        draw.Art,
	camera:     draw.Camera,
	sparks:     draw.Sparks,
	minimap:    draw.Minimap,
	before:     draw.Snapshot, // the world a tick ago, which a frame blends from
	frame:      draw.Frame,    // what is drawn: the world between its last two ticks
	input:      input.Input,
	sequence:   u32, // my last command's
	hud:        hud.Hud,
	limbo:      Limbo,
	team_asked: Maybe(res.Team), // chosen in the team menu, for the next tick to place me on
	bots:       ai.Bots,
	profiles:   []res.Bot_Profile, // data/bots, the bots are dressed from
}

// What the match asks of the client.
Request :: union {
	Leave,
}

// Back to the main menu.
Leave :: struct {}

// A match on `maps` (names under data/maps) in turn, the first first, as `host` has it:
// the limits and the bots. False, with the reason logged, if the game or the first map
// can't be loaded.
match_start :: proc(
	match: ^Match,
	maps: []string,
	host: ^res.Server_Config,
	config: ^res.Client_Config,
	mod: res.Mod,
	sounds: ^sound.Sound,
) -> bool {
	if len(maps) == 0 do return false
	match.game = new(sim.Game)
	if !sim.game_init(match.game, settings_from(host), authority = true) {
		free(match.game)
		return false
	}
	match.maps = make([]string, len(maps))
	for name, i in maps do match.maps[i] = strings.clone(name)
	match.map_name = match.maps[0]
	match.bot_counts = host.bots
	match.mod = mod
	draw.sparks_init(&match.sparks)
	hud.hud_init(&match.hud, mod)
	bots_join(match, host.bots)
	if !round_start(match, config) {
		match_end(match)
		return false
	}
	draw.art_load(&match.art, mod, &match.game.polymap)
	draw.camera_fit(&match.camera)
	match.camera.pos = match.game.world.soldiers[ME].body.pos
	input.input_start(&match.input, match.camera.view)
	shown(match, config, sounds) // the first round's placings
	return true
}

match_end :: proc(match: ^Match) {
	input.input_stop(&match.input)
	draw.minimap_destroy(&match.minimap)
	draw.art_destroy(&match.art)
	hud.hud_destroy(&match.hud)
	delete(match.profiles)
	sim.game_destroy(match.game)
	free(match.game)
	for name in match.maps do delete(name)
	delete(match.maps)
	match^ = {}
}

// How the game is played, as `host` says: its limits over the game's own settings, as a
// server hosting it would.
@(private = "file")
settings_from :: proc(host: ^res.Server_Config) -> sim.Game_Settings {
	s := sim.DEFAULT_GAME_SETTINGS
	if host.server.time_limit > 0 do s.time_limit = host.server.time_limit * 60 * sim.TICK_RATE
	if host.server.capture_limit > 0 do s.capture_limit = host.server.capture_limit
	return s
}

// A frame: my keys, and an open menu's; the ticks owed; the world `alpha` of the way
// into the next tick, and the camera after them.
match_update :: proc(match: ^Match, config: ^res.Client_Config, sounds: ^sound.Sound, ticks: int, alpha, dt: f32) -> Request {
	draw.camera_fit(&match.camera)
	menu := hud.menus_any_open(&match.hud.menus)
	actions := input.input_poll(&match.input, config, match.camera.view, menu)
	menus_follow(match)
	if menu && menu_keys(match, config, sounds, input.input_menu_keys(&match.input)) do return Leave{}
	for action in sa.slice(&actions) do act(match, config, action)

	for _ in 0 ..< ticks {
		tick(match, config, sounds)
	}

	draw.frame_build(&match.frame, &match.before, match.game, alpha)
	me := &match.game.world.soldiers[ME]
	draw.camera_follow(&match.camera, match.frame.figures[ME].pos, match.input.cursor, me.aim.distance, dt)
	return nil
}

match_draw :: proc(match: ^Match, u: ^ui.Ui, config: ^res.Client_Config) {
	draw.minimap_fit(&match.minimap, &match.art, &match.game.polymap, u.scale)
	draw.draw_world(&match.art, match.game, &match.frame, &match.sparks, match.camera, &config.graphics)
	data := hud_data(match, config)
	hud.hud_draw(u, &match.hud, &data, &match.minimap)
}

// One tick: the world stepped on everyone's commands, or, the last round over, the next
// begun; then what that made seen and heard.
@(private = "file")
tick :: proc(match: ^Match, config: ^res.Client_Config, sounds: ^sound.Sound) {
	mine: sim.Command
	if sim.round_over(&match.game.round) {
		next_round(match, config)
	} else {
		mine = step(match, config)
	}
	shown(match, config, sounds)
	limbo_tick(match, mine)
}

// The world a tick on, on my command and the bots'; then on the team I asked for, if I
// did. My command, which it ran.
@(private = "file")
step :: proc(match: ^Match, config: ^res.Client_Config) -> sim.Command {
	game := match.game
	commands: [sim.MAX_PLAYERS]sim.Command
	match.sequence += 1
	aim := draw.camera_to_world(match.camera, match.input.cursor)
	commands[ME] = input.input_take_command(&match.input, match.sequence, aim)
	names := soldier_names(match, config)
	ai.bots_commands(&match.bots, game, &names, &commands)
	draw.snapshot_take(&match.before, &game.world)
	sim.game_tick(game, &commands)
	ai.bots_hear(&match.bots, game)
	if team, asked := match.team_asked.?; asked {
		spawn(game, ME, team, game.world.soldiers[ME].loadout)
		match.team_asked = nil
	}
	return commands[ME]
}

// What the tick decided and did, seen and heard: the sparks, the sounds and the HUD's
// feed, from its events and rulings; and a round's end.
@(private = "file")
shown :: proc(match: ^Match, config: ^res.Client_Config, sounds: ^sound.Sound) {
	game := match.game
	draw.sparks_tick(&match.sparks, game)
	_, playing := game.round.phase.(sim.Playing)
	if config.graphics.weather && playing {
		draw.sparks_weather(&match.sparks, &game.polymap, match.camera, game.world.tick)
	}
	// heard from my soldier: there is no spectating yet, to follow another or the free camera
	sound.sound_tick(sounds, game, ME, ME, match.camera.pos, &match.sparks)
	names := soldier_names(match, config)
	match.hud.feed.console_length = int(config.interface.console_lines)
	match.hud.feed.kill_length = int(config.interface.kill_log_length)
	hud.feed_tick(&match.hud.feed, game, &names, ME)
	if ended, is_ended := game.round.phase.(sim.Ended); is_ended && ended.countdown == sim.ROUND_END_TICKS {
		hud_round_ended(match)
	}
}

// The next round, on the next of the maps, drawn with that map's art; or on the same
// map again.
@(private = "file")
next_round :: proc(match: ^Match, config: ^res.Client_Config) {
	next := (match.map_index + 1) % len(match.maps)
	if next == match.map_index {
		round_start(match, config)
		return
	}
	match.map_index = next
	match.map_name = match.maps[next]
	if !round_start(match, config) do return // tried again, on the map after, next tick
	draw.art_destroy(&match.art)
	draw.art_load(&match.art, match.mod, &match.game.polymap)
	draw.minimap_destroy(&match.minimap) // drawn again for the new map
}

// A new round on the match's map: me with my loadout, and the bots with theirs. They are
// placed as a tick's rulings, which the sparks and the sound then see as any tick's.
@(private = "file")
round_start :: proc(match: ^Match, config: ^res.Client_Config) -> bool {
	game := match.game
	kept := game.world.soldiers[ME].team // the team I was on, which I stay on
	sim.game_start_round(game, match.map_name, seed = u64(time.time_to_unix_nano(time.now()))) or_return
	sim.clear_output(&game.output)

	player := config.player
	me := &game.world.soldiers[ME]
	me.player.look = {
		gostek      = player.gostek,
		shirt       = player.shirt,
		pants       = player.pants,
		skin        = player.skin,
		hair        = player.hair,
		jet         = player.jet,
		hair_style  = player.hair_style,
		head_style  = player.head_style,
		chain_style = player.chain_style,
	}
	my_team := kept if kept == .Alpha || kept == .Bravo else .Alpha
	spawn(game, ME, my_team, {player.primary_weapon, player.secondary_weapon})
	// the bots by team, alpha's first; the slots after them are let go
	counts := match.bot_counts
	alpha := bot_count(counts.alpha)
	wanted := min(alpha + bot_count(counts.bravo), sim.MAX_PLAYERS - 1)
	for id in 1 ..< sim.MAX_PLAYERS {
		slot := sim.Soldier_Id(id)
		if id > wanted {
			ai.bots_detach(&match.bots, slot)
			continue
		}
		if !ai.bots_has(&match.bots, slot) {
			profile := ai.profile_random(match.profiles, &game.world.rng) or_break
			ai.bots_attach(&match.bots, slot, profile, game.world.rng.state + u64(id))
		}
		profile := &match.bots.brains[id].profile
		game.world.soldiers[id].player = {look = ai.profile_look(profile), bot = true}
		team: res.Team = .Alpha if id <= alpha else .Bravo
		spawn(game, slot, team, {profile.favourite, profile.secondary})
	}
	ai.bots_new_round(&match.bots)
	draw.snapshot_take(&match.before, &game.world) // a new round is a jump, not a journey
	hud_new_round(match)
	return true
}

// A soldier placed on one of its team's spawn points, as the server places one: a new
// life, ruled and recorded in the tick's output.
@(private = "file")
spawn :: proc(game: ^sim.Game, id: sim.Soldier_Id, team: res.Team, loadout: sim.Loadout) {
	respawn := sim.Respawn {
		target    = id,
		life      = game.world.soldiers[id].vitals.life + 1,
		team      = team,
		primary   = loadout.primary,
		secondary = loadout.secondary,
		pos       = sim.spawn_point(game.world.polymap, team, &game.world.rng),
	}
	sim.rule(&game.world, &game.resources, respawn, &game.output)
}

// The bots' brains at the config's skill, and the profiles of data/bots they are dressed
// from; each round seats as many as the config asks for (round_start). They don't chat
// yet: there is no chat offline to hear them in.
@(private = "file")
bots_join :: proc(match: ^Match, settings: res.Bot_Settings) {
	ai.bots_init(&match.bots, {difficulty = settings.difficulty, chat = settings.chat}, nil, nil)
	match.profiles = res.bot_profiles_load(sim.DATA_DIR)
}

@(private = "file")
bot_count :: proc(n: i32) -> int {
	return clamp(int(n), 0, sim.MAX_PLAYERS - 1)
}

// Everyone's name, which the bots go by to know their friends and tell their kills, and
// the HUD shows.
soldier_names :: proc(match: ^Match, config: ^res.Client_Config) -> (names: [sim.MAX_PLAYERS]string) {
	names[ME] = config.player.name
	for &brain, id in match.bots.brains {
		if brain.active do names[id] = utils.short_string_text(&brain.profile.name)
	}
	return
}
