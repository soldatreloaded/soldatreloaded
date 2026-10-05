package match

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"
import "../draw"
import "../hud"
import "../input"
import "../sound"

// The match's side of the HUD: what it is told of the world each frame (hud_data); the
// keys that open its menus, the keys an open menu takes, and the menus' choices carried
// out; the weapons menu's own comings and goings; the scoreboard at a round's end. From
// the C client's main.c: hud_data_build, cmd_menu, menu_event, apply_menu_action and the
// limbo.

CURSOR_REACH :: 15 // CURSORSPRITE_DISTANCE: how near the cursor names a player
MOVING :: sim.Buttons{.Left, .Right, .Jump, .Crouch, .Prone, .Jet, .Fire, .Throw} // moving shuts the weapons menu

// When the weapons menu comes up by itself (NetworkClientSprite.pas): at my first life
// of a round, and a second after each death, unless its key shut it while I was dead.
// Picking a primary, or moving, shuts it.
Limbo :: struct {
	locked:   bool,       // shut by its key while dead: it stays shut, through the spawn, until opened again
	placed:   bool,       // my first life of the round has begun
	was_dead: bool,       // as of the tick before
	died_at:  Maybe(u32), // the tick I died, while the menu waits to come up
}

// What the HUD shows of the world this frame.
hud_data :: proc(match: ^Match, config: ^res.Client_Config) -> (data: hud.Hud_Data) {
	game := match.game
	world := &game.world
	round := &game.round
	settings := &game.settings

	data.time_left = round.time_left / sim.TICK_RATE
	data.limit = settings.capture_limit
	data.captures = round.captures
	for &home in data.flags_home do home = true
	for &thing in world.things {
		if team := flag_team(thing.kind); team != .None do data.flags_home[team] = thing.in_base && thing.holder == nil
	}
	_, data.paused = round.phase.(sim.Paused)
	_, data.ended = round.phase.(sim.Ended)

	names := soldier_names(match, config)
	for &soldier, id in world.soldiers {
		if !soldier.active do continue
		figure := &match.frame.figures[id]
		data.players[id] = {
			active = true,
			name   = names[id],
			team   = soldier.team,
			dead   = soldier.vitals.dead,
			bot    = soldier.player.bot,
			flag   = carries_flag(world, &soldier),
			kills  = soldier.tally.kills,
			deaths = soldier.tally.deaths,
			flags  = soldier.tally.flags,
			ping   = i32(soldier.player.ping),
			shirt  = rl.Color(draw.shirt_worn(&soldier)),
			head   = figure.points[7 - 1],
			top    = figure.points[12 - 1],
		}
	}
	data.me = ME
	me := &world.soldiers[ME]
	data.mine = mine(game, me)
	data.loadout = me.loadout
	for info, weapon in game.resources.weapons do data.weapon_names[weapon] = info.name

	data.camera = match.camera.pos
	data.view = match.camera.view
	data.cursor = match.input.cursor
	data.under_cursor, data.friend = under_cursor(match, &names)

	interface := &config.interface
	graphics := &config.graphics
	data.minimap = interface.minimap
	data.info = interface.info
	data.player_names = interface.player_names
	data.team_names = interface.team_names
	data.typing = interface.typing
	data.kill_log = interface.kill_log_position
	data.crosshair = {rl.Color(graphics.crosshair_color), f32(clamp(graphics.crosshair_size, 50, 200)) / 100}
	data.pointer = {rl.Color(graphics.cursor_color), f32(clamp(graphics.cursor_size, 50, 200)) / 100}
	data.fps = rl.GetFPS()
	data.seconds = rl.GetTime()
	return
}

// The menus told where the cursor is and how wide the view, each frame before they are
// read.
menus_follow :: proc(match: ^Match) {
	menus := &match.hud.menus
	menus.cursor = match.input.cursor
	menus.width = match.camera.view.x
}

// The keys an open menu took this frame: a click, or a number key. True if what they
// chose is to leave.
menu_keys :: proc(match: ^Match, config: ^res.Client_Config, sounds: ^sound.Sound, keys: input.Menu_Keys) -> (leave: bool) {
	menus := &match.hud.menus
	action: hud.Menu_Action
	if keys.click {
		action = hud.menus_click(menus, chosen = true) // offline a primary is always chosen
	} else if digit, pressed := keys.digit.?; pressed {
		action = hud.menus_number_key(menus, digit, keys.ctrl)
	}
	return menu_choice(match, config, sounds, action)
}

// What a menu's choice does, with the original's click. True if it is to leave.
@(private = "file")
menu_choice :: proc(match: ^Match, config: ^res.Client_Config, sounds: ^sound.Sound, action: hud.Menu_Action) -> (leave: bool) {
	if action == nil do return false
	sound.sound_flat(sounds, "menuclick.wav")
	me := &match.game.world.soldiers[ME]
	// the weapons are the next spawn's, and this life's too if I haven't moved since it began
	now := !me.vitals.dead && me.body.spawn_still
	switch a in action {
	case hud.Leave:
		return true
	case hud.Pick_Primary:
		config.player.primary_weapon = a.weapon
		me.loadout.primary = a.weapon
		if now do me.arsenal.primary = sim.weapon_state(&match.game.resources, a.weapon)
	case hud.Pick_Secondary:
		config.player.secondary_weapon = a.weapon
		me.loadout.secondary = a.weapon
		if now do me.arsenal.secondary = sim.weapon_state(&match.game.resources, a.weapon)
	case hud.Pick_Team:
		if a.team != me.team do match.team_asked = a.team
	case hud.Menu_Changed:
	}
	return false
}

// A bound key's action: the menus' keys, and the interface's toggles.
act :: proc(match: ^Match, config: ^res.Client_Config, action: string) {
	menus := &match.hud.menus
	switch action {
	case "escmenu":               hud.menus_show(menus, .Escape, .Escape not_in menus.open)
	case "teammenu":              hud.menus_show(menus, .Team, .Team not_in menus.open)
	case "weaponsmenu":           weapons_menu_key(match)
	case "fragsmenu":             hud.hud_toggle_scoreboard(&match.hud)
	case "statsmenu":             hud.hud_toggle_stats(&match.hud)
	case "toggle ui_minimap":     config.interface.minimap = !config.interface.minimap
	case "toggle ui_info":        config.interface.info = !config.interface.info
	case "toggle ui_playernames": config.interface.player_names = !config.interface.player_names
	}
}

// The weapons menu's key (ControlGame.pas): dead, it opens and shuts the menu, and shut
// that way it stays shut through the spawn. Alive it never opens it: it shuts one left
// open, and locks or unlocks it until the next death.
@(private = "file")
weapons_menu_key :: proc(match: ^Match) {
	menus := &match.hud.menus
	me := &match.game.world.soldiers[ME]
	if .Escape in menus.open || !me.active || me.team == .Spectator do return
	if me.vitals.dead {
		hud.menus_show(menus, .Weapons, .Weapons not_in menus.open)
		match.limbo.locked = .Weapons not_in menus.open
	} else {
		armed := me.arsenal.primary.weapon != .Punch && me.arsenal.secondary.weapon != .Punch
		if .Weapons in menus.open && !armed do return
		hud.menus_show(menus, .Weapons, false)
		match.limbo.locked = !match.limbo.locked
	}
	hud.console_say(&match.hud.feed, hud.GAME_COLOR, "Weapons menu disabled" if match.limbo.locked else "Weapons menu active")
}

// After each tick, on my command in it: the weapons menu up at my first life and a
// second after I die, while the round is played; down as I move.
limbo_tick :: proc(match: ^Match, command: sim.Command) {
	limbo := &match.limbo
	menus := &match.hud.menus
	world := &match.game.world
	me := &world.soldiers[ME]
	if !me.active || me.team == .Spectator do return

	dead := me.vitals.dead
	if dead && !limbo.was_dead {
		limbo.died_at = world.tick
	} else if !dead {
		limbo.died_at = nil
	}
	first_life := !limbo.placed && !dead
	limbo.placed = true
	died_at, dying := limbo.died_at.?
	_, playing := match.game.round.phase.(sim.Playing)
	due := first_life || (dying && world.tick - died_at >= sim.TICK_RATE)
	if due && playing && !limbo.locked && menus.open & {.Weapons, .Escape} == {} {
		hud.menus_show(menus, .Weapons, true)
		limbo.died_at = nil
	}
	if .Weapons in menus.open && !dead && command.buttons & MOVING != {} do hud.menus_show(menus, .Weapons, false)
	limbo.was_dead = dead
}

// The round over (ClientHandleMapChange): its scores stand on the scoreboard, the stats
// and the weapons menu gone.
hud_round_ended :: proc(match: ^Match) {
	match.hud.scoreboard = true
	match.hud.stats = false
	hud.menus_show(&match.hud.menus, .Weapons, false)
}

// A new round: the last one's scoreboard down, and the weapons menu's comings and
// goings begun again.
hud_new_round :: proc(match: ^Match) {
	match.hud.scoreboard = false
	match.hud.stats = false
	match.limbo = {}
	match.team_asked = nil
}

// My soldier's state for the bars.
@(private = "file")
mine :: proc(game: ^sim.Game, me: ^sim.Soldier) -> (mine: hud.Mine) {
	gun := me.arsenal.primary
	info := &game.resources.weapons[gun.weapon]
	mine = {
		dead       = me.vitals.dead,
		health     = me.vitals.health,
		weapon     = gun.weapon,
		ammo       = gun.ammo,
		fire_bar   = share(gun.fire_count, info.stats.fire_interval),
		grenades   = me.arsenal.grenades,
		inaccuracy = f32(me.aim.hit_spray) + sim.movement_inaccuracy(&game.resources, me) * 100,
		protected  = me.vitals.cease_fire,
		respawn    = me.vitals.respawn_counter,
	}
	// the clip's share left; emptied, the reload's share done, but for the shotgun's,
	// which loads a shell at a time
	if gun.ammo > 0 {
		mine.ammo_bar = share(gun.ammo, info.stats.ammo)
	} else if gun.weapon != .Spas12 {
		mine.ammo_bar = 1 - share(gun.reload_count, info.stats.reload_time)
	}
	if game.world.polymap.jet_fuel > 0 do mine.jets = share(me.body.jet_fuel, game.world.polymap.jet_fuel)
	return

	share :: proc(part, whole: i32) -> f32 {
		return f32(part) / f32(whole) if whole > 0 else 0
	}
}

// The player the cursor is on (UpdateFrame.pas): one standing, or a teammate, or anyone
// while I or they are dead; named, a teammate with its health.
@(private = "file")
under_cursor :: proc(match: ^Match, names: ^[sim.MAX_PLAYERS]string) -> (name: string, friend: bool) {
	world := &match.game.world
	me := &world.soldiers[ME]
	if !me.active do return
	aim := draw.camera_to_world(match.camera, match.input.cursor)
	for &soldier, id in world.soldiers {
		if sim.Soldier_Id(id) == ME || !soldier.active || soldier.team == .Spectator do continue
		teammate := soldier.team == me.team
		if !(soldier.controls.stance == .Stand || teammate || me.vitals.dead || soldier.vitals.dead) do continue
		if utils.length(aim - soldier.body.pos) >= CURSOR_REACH do continue
		if teammate {
			return fmt.tprintf("%s %d%%", names[id], int(math.round(soldier.vitals.health / sim.DEFAULT_HEALTH * 100))), true
		}
		return names[id], false
	}
	return
}

@(private = "file")
carries_flag :: proc(world: ^sim.World, soldier: ^sim.Soldier) -> bool {
	held := soldier.carrying.held.? or_return
	return flag_team(world.things[held].kind) != .None
}

@(private = "file")
flag_team :: proc(kind: sim.Thing_Kind) -> res.Team {
	#partial switch kind {
	case .Alpha_Flag: return .Alpha
	case .Bravo_Flag: return .Bravo
	}
	return .None
}
