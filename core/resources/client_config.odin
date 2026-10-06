package resources

import "core:mem/virtual"

import "../utils"

// The game's own settings, client.config.json at the install's root (config.odin): your
// soldier, the window and the effects, the sound, the server to join, Offline Play, the
// radio's calls, your mutes and the keys. Read as the game starts (the file made with
// the defaults if it isn't there), written as it closes. A setting the file doesn't hold
// keeps its default.

Client_Config :: struct {
	player:    Player_Settings,
	controls:  Control_Settings,
	graphics:  Graphics_Settings,
	interface: Interface_Settings,
	sound:     Sound_Settings,
	network:   Network_Settings,
	demos:     Demo_Settings,
	offline:   Offline_Settings,  // a game against bots on this machine, alone
	radio:     Radio_Settings,    // the radio menu's calls, and the places each can name
	mutes:     Mute_Settings,     // the chat kept off your screen: kinds of it, and players by name
	binds:     map[string]string, // your keys: a key to a command; an empty command lets one of the game's own go (client_config_bind)

	arena:     virtual.Arena `json:"-"`, // everything the config's strings and binds are allocated in
	broken:    bool `json:"-"`,          // its file couldn't be read, so it is never written over
}

Player_Settings :: struct {
	name:             string,      // your name
	gostek:           Gostek,      // male, female, waifu, rat or furry
	shirt:            utils.Rgba,  // the shirt's colour, RRGGBB
	pants:            utils.Rgba,  // the pants' colour, RRGGBB
	skin:             utils.Rgba,  // the skin's colour, RRGGBB
	hair:             utils.Rgba,  // the hair's colour, RRGGBB
	jet:              utils.Rgba,  // the jet flame's colour, RRGGBB
	hair_style:       Hair_Style,  // army; the male's dreadlocks, punk, mr_t or normal; the waifu's fringe or bob. The rat and the furry wear only army, punk and mr_t.
	head_style:       Head_Style,  // none; the male's helmet or hat; the waifu's own. The rat and the furry wear none.
	chain_style:      Chain_Style, // none, dog_tags or gold_chain
	primary_weapon:   Weapon,      // the primary at the next spawn: desert_eagles to minigun
	secondary_weapon: Weapon,      // the secondary at the next spawn: ussocom, knife, chainsaw or law
}

Gostek :: enum {
	Male,
	Female,
	Waifu,
	Rat,
	Furry,
}

Hair_Style :: enum {
	Army,
	Dreadlocks,
	Punk,
	Mr_T,
	Normal,
	Fringe,
	Bob,
}

Head_Style :: enum {
	None,
	Helmet,
	Hat,
	Waifu,
}

Chain_Style :: enum {
	None,
	Dog_Tags,
	Gold_Chain,
}

Control_Settings :: struct {
	sensitivity:       f32,  // the mouse's speed
	legacy_flag_throw: bool, // jump and crouch held together (w+s) throw the flag too, as older versions did
}

Graphics_Settings :: struct {
	mod:               string,            // the mod in mods/ the game looks and sounds like, over mods/default/; empty for none. From the next start.
	screen_width:      i32,               // the window's width
	screen_height:     i32,               // the window's height
	window_mode:       Window_Mode,       // windowed, fullscreen or borderless
	vsync:             bool,              // wait for the display's refresh
	fps_limit:         bool,              // draw at most max_fps frames a second; false draws them as fast as they come
	max_fps:           i32,               // the frames drawn a second at most, while fps_limit is on
	scenery:           bool,              // the scenery behind the map; false leaves it out, the middle and front scenery stay
	trails:            bool,              // the streaks behind the bullets, grenades and rockets
	weather:           bool,              // the map's weather: its rain, sandstorm or snow, and the wind
	force_sky:         bool,              // the sky in forced_sky_top and forced_sky_bottom on every map instead of the map's own
	forced_sky_top:    utils.Rgba,        // the forced sky's colour at the top, RRGGBB
	forced_sky_bottom: utils.Rgba,        // the forced sky's colour at the bottom, RRGGBB
	grenade_color:     Maybe(utils.Rgba), // the grenades in this colour, RRGGBB, flat and solid; empty for their own art
	crosshair_color:   utils.Rgba,        // the aiming crosshair's colour, RRGGBB
	crosshair_size:    i32,               // the aiming crosshair's size, percent
	cursor_color:      utils.Rgba,        // the menu cursor's colour, RRGGBB
	cursor_size:       i32,               // the menu cursor's size, percent
	track_shot:        bool,              // the camera follows a Barrett shot fired scoped, until you stand up
}

Window_Mode :: enum {
	Windowed,
	Fullscreen,
	Borderless,
}

Interface_Settings :: struct {
	minimap:           bool,              // the minimap
	info:              bool,              // the FPS and ping line
	player_names:      bool,              // teammates' names at the screen's edge when out of view (everyone's, spectating), and your ping
	team_names:        bool,              // teammates' names by them always, not only at the screen's edge when out of view (with player_names)
	typing:            Typing_Style,      // over a player typing: off, dots (the original's) or typing, the word
	kill_log_length:   i32,               // the kill log's lines, two a kill, 0 to 50; 0 shows none
	kill_log_position: Kill_Log_Position, // where the kill log is: top_right (the original's), lower_right, or top_left, under the chat
	console_lines:     i32,               // how many console lines the HUD shows
	discord:           bool,              // Playing Soldat Reloaded on your Discord profile, with the map and the server, while the Discord app runs here
}

Typing_Style :: enum {
	Off,
	Dots,   // the original's
	Typing, // Typing...
}

Kill_Log_Position :: enum {
	Top_Right, // the original's
	Lower_Right,
	Top_Left, // under the chat
}

Sound_Settings :: struct {
	volume:            i32,  // 0 to 100
	battle_effects:    bool, // a far shot or blast also plays its distant sound
	explosion_effects: bool, // a blast next to you rings your ears and muffles the rest for a few seconds
}

Network_Settings :: struct {
	server:   string, // the server the main menu joins, host:port
	password: string, // the password the main menu joins with; empty for none
	lobby:    string, // the lobby the server browser asks for its list
	smooth:   i32,    // milliseconds a correction of another player is smoothed over; 0 snaps
	interp:   i32,    // ticks the others are shown behind the newest snapshot, at least, so jitter doesn't show; raised by itself while snapshots come late
}

Demo_Settings :: struct {
	record_rounds: bool, // a demo of every round joined, into demos/
}

// Offline Play: capture the flag against bots, on this machine and no other, with no
// server. Its limits, its bots and its maps.
Offline_Settings :: struct {
	time_limit:    i32,          // minutes a round lasts
	capture_limit: i32,          // the captures that win a round
	bots:          Bot_Settings, // the bots on each team, how well they play, whether they talk
	maps:          []string,     // the rotation, played in turn; none plays the last map again
}

Radio_Settings :: struct {
	call_1: Radio_Call,
	call_2: Radio_Call,
	call_3: Radio_Call,
}

Radio_Call :: struct {
	name:   string,
	places: [3]string,
}

// Your own mutes, on your screen alone: a server's are its admins'. A muted player's taunts
// and radio calls, said by a key and not typed, still come through, but for a
// spectator's while the spectators are muted.
Mute_Settings :: struct {
	everyone:   bool,     // everyone's chat
	team:       bool,     // your team's
	enemies:    bool,     // the other team's
	spectators: bool,     // the spectators', their taunts too
	players:    []string, // these players', by name in any case, until unmuted
}

LOBBY_URL :: "https://soldatreloaded-lobby.fly.dev"

@(rodata)
DEFAULT_CLIENT_CONFIG := Client_Config {
	player = {
		name             = "Major",
		gostek           = .Male,
		shirt            = {0x30, 0x42, 0x89, 255},
		pants            = {0xFF, 0x00, 0x00, 255},
		skin             = {0xE6, 0xB4, 0x78, 255},
		hair             = {0x00, 0x00, 0x00, 255},
		jet              = {0x00, 0x00, 0x8B, 255},
		hair_style       = .Dreadlocks,
		head_style       = .None,
		chain_style      = .None,
		primary_weapon   = .M79,
		secondary_weapon = .Knife,
	},
	controls = {sensitivity = 1.0},
	graphics = {
		screen_width      = 1600,
		screen_height     = 900,
		window_mode       = .Windowed,
		fps_limit         = true,
		max_fps           = 500,
		scenery           = true,
		trails            = true,
		weather           = true,
		forced_sky_top    = {0, 0, 0, 255},
		forced_sky_bottom = {0, 0, 0, 255},
		crosshair_color   = {255, 255, 255, 255},
		crosshair_size    = 100,
		cursor_color      = {255, 255, 255, 255},
		cursor_size       = 100,
		track_shot        = true,
	},
	interface = {
		player_names    = true,
		typing          = .Dots,
		kill_log_length = 15,
		console_lines   = 6,
		discord         = true,
	},
	sound = {volume = 18},
	network = {server = "127.0.0.1:23073", lobby = LOBBY_URL, smooth = 100},
	offline = {time_limit = 15, capture_limit = 10, bots = {difficulty = 100, chat = true}},
	radio = {
		call_1 = {"Enemy flagger", {"up!", "middle!", "down!"}},
		call_2 = {"Friendly flagger", {"up!", "middle!", "down!"}},
		call_3 = {"Enemy spotted", {"up!", "middle!", "down!"}},
	},
}

// The game's own keys.
@(rodata)
DEFAULT_BINDS := [?][2]string {
	{"a", "+left"},
	{"d", "+right"},
	{"w", "+jump"},
	{"s", "+crouch"},
	{"x", "+prone"},
	{"mouse2", "+jet"},
	{"mouse1", "+fire"},
	{"space", "+throw"},
	{"e", "+flagthrow"},
	{"r", "+reload"},
	{"q", "+change"},
	{"f", "+drop"},
	{"escape", "escmenu"},
	{"tab", "weaponsmenu"},
	{"m", "teammenu"},
	{"f1", "fragsmenu"},
	{"f2", "statsmenu"},
	{"f3", "toggle ui_minimap"},
	{"f4", "toggle r_swapeffect"},
	{"f5", "toggle ui_info"},
	{"f7", "toggle ui_playernames"},
	{"f9", "togglewindow"},
	{"f6", "demo_pause"},
	{"f8", "demo_fast"},
	{"leftarrow", "demo_tick_r -600"},
	{"rightarrow", "demo_tick_r 600"},
	{"v", "+radio"},
	{"t", "chat"},
	{"y", "teamchat"},
	{"slash", "cmd"},
	{"f12", "say /yes"},
	{"f11", "say /no"},
	{"alt+q", "say_team Cover me!"},
	{"alt+w", "say_team Follow me!"},
	{"alt+e", "say_team Enemy at our base!"},
	{"alt+r", "say_team Defend the flag!"},
	{"alt+t", "say_team Attack!"},
	{"alt+z", "say_team Help!"},
	{"alt+x", "say_team Got the flag!"},
	{"alt+c", "say_team Flag carrier down!"},
	{"alt+a", "say Nice one!"},
	{"alt+s", "say Sorry!"},
	{"alt+d", "say Thanks!"},
	{"alt+f", "say Damn!"},
	{"alt+g", "say Hi!"},
	{"alt+h", "say Bye!"},
}


// The defaults, and the file at `path` over them; the file made with the defaults if it
// isn't there. Free with client_config_destroy.
client_config_load :: proc(path: string) -> ^Client_Config {
	// The config is allocated inside its own arena, so one free takes all of it.
	config, _ := virtual.arena_growing_bootstrap_new_by_name(Client_Config, "arena")
	client_config_reset(config)
	switch config_read(path, config, virtual.arena_allocator(&config.arena)) {
	case .Read:
	case .Missing:
		client_config_save(config, path)
	case .Broken:
		client_config_reset(config) // what was read before it went wrong goes too
		config.broken = true
	}
	return config
}

// The command a key is bound to; none for a key the player has let go.
client_config_bind :: proc(config: ^Client_Config, key: string) -> (command: string, bound: bool) {
	command = config.binds[key] or_return
	return command, command != ""
}

// The config written to `path`, unless its file was broken. False, with the reason
// logged, if it can't be written.
client_config_save :: proc(config: ^Client_Config, path: string) -> bool {
	if config.broken do return true
	return config_write(path, config)
}

client_config_destroy :: proc(config: ^Client_Config) {
	// the config itself is in the arena, so it is destroyed from a copy: destroying it in
	// place would write to the arena after its memory is gone
	arena := config.arena
	virtual.arena_destroy(&arena)
}

// The config at its defaults, in its own arena.
@(private = "file")
client_config_reset :: proc(config: ^Client_Config) {
	arena := config.arena
	config^ = DEFAULT_CLIENT_CONFIG
	config.arena = arena

	config.binds = make(map[string]string, virtual.arena_allocator(&config.arena))
	for bind in DEFAULT_BINDS {
		config.binds[bind[0]] = bind[1]
	}
}
