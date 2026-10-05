package hud

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"

// What the HUD shows of the game, a frame's facts: the round, everyone in it, my
// soldier, the view, and the settings that say what is shown. The match fills one each
// frame from the world; the drawing reads this and never the game. Plain data: the
// names point into the match's own, for the frame. From the C client's ui/hud_data.h.
Hud_Data :: struct {
	// the round
	time_left:    i32,  // seconds
	limit:        i32,  // the captures that win
	captures:     [res.Team]i32,
	flags_home:   [res.Team]bool, // each team's flag at its base, and nobody's
	paused:       bool,
	ended:        bool, // over, its scores standing until the next

	// everyone, me among them
	players:      [sim.MAX_PLAYERS]Player,
	me:           sim.Soldier_Id,
	mine:         Mine,
	loadout:      sim.Loadout, // what the weapons menu has chosen for my next spawn
	weapon_names: [res.Weapon]string,

	// the view
	camera:       [2]f32, // the view's middle, in the world
	view:         [2]f32, // its size: world units, which are the HUD's units
	cursor:       [2]f32, // the game's cursor, in units from the view's top-left
	under_cursor: string, // the player the cursor is on, a teammate with its health
	friend:       bool,   // and on my side

	// the settings
	minimap:      bool,
	info:         bool, // the FPS line
	player_names: bool,
	team_names:   bool, // teammates' names by them always, not only out of view
	typing:       res.Typing_Style, // over a player typing; drawn once online play brings chat
	kill_log:     res.Kill_Log_Position,
	crosshair:    Pointer_Look,
	pointer:      Pointer_Look, // the menus' cursor
	fps:          i32,
	seconds:      f64, // the clock what blinks and bobs goes by
}

Player :: struct {
	active: bool,
	name:   string,
	team:   res.Team,
	dead:   bool,
	bot:    bool,
	flag:   bool, // carrying the other team's
	kills:  i32,
	deaths: i32,
	flags:  i32, // captures
	ping:   i32, // ms; offline, nobody's
	shirt:  rl.Color, // as it is worn: its team's
	head:   [2]f32,   // where it is drawn, in the world: its head (the gostek's point 7)
	top:    [2]f32,   // and its helmet (point 12), which my arrow hangs over
}

// My soldier, for the bars and the numbers.
Mine :: struct {
	dead:       bool,
	health:     f32, // out of sim.DEFAULT_HEALTH
	weapon:     res.Weapon,
	ammo:       i32,
	ammo_bar:   Maybe(f32), // the clip's share left, or while it is empty the reload's share done
	fire_bar:   f32,        // the wait between shots, its share left
	jets:       Maybe(f32), // the fuel's share left; none on a map without jets
	grenades:   i32,
	inaccuracy: f32,  // how unsteady the aim is: the crosshair grows with it
	protected:  i32,  // ticks of spawn protection left; below 0 none
	respawn:    i32,  // ticks until I am placed again, dead
}

// How a cursor looks, as the config has it.
Pointer_Look :: struct {
	color: rl.Color,
	scale: f32, // its size, 1 the image's own
}
