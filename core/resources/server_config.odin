package resources

import "core:mem/virtual"

// How a dedicated server hosts its game, server.config.json at its install's root
// (config.odin). Read as it starts (the file made with the defaults if it isn't there),
// and written whole as it starts and as its bans and mutes change (apps/server/lists). A
// setting the file doesn't hold keeps its default. The game has none of it: Offline
// Play's settings are its own (client_config.odin).

Server_Config :: struct {
	server:  Host_Settings,
	maps:    []string,        // the rotation, played in turn; none plays every map under data/maps, the map again each round
	bots:    Bot_Settings,    // the bots the server fills the game with
	network: Flood_Settings,
	lobby:   Lobby_Settings,  // whether, and how, the server lists itself for the game's server browser
	admins:  []Admin_Entry,   // who may run the admin commands (apps/server/admin.odin), by address; the server only reads these
	bans:    []Ban_Entry,     // who is kept out; the server writes these as players are banned and unbanned
	mutes:   []Mute_Entry,    // whose chat reaches nobody; the server writes these as players are muted and unmuted
	weapons: Weapon_Settings, // every weapon's numbers (weapons.odin), by its name: "punch", "desert_eagles", …

	arena:   virtual.Arena `json:"-"`, // everything the config's strings are allocated in
	broken:  bool `json:"-"`,          // its file couldn't be read, so it is never written over
}

Host_Settings :: struct {
	hostname:       string, // the game's name, on the scoreboard
	port:           u16,    // the UDP port to listen on
	ip:             string, // the address to listen on; empty for every one
	password:       string, // the password to join; empty for none
	admin_password: string, // the password a player says with /login to be an admin until they leave; empty for none
	time_limit:     i32,    // minutes a round lasts
	capture_limit:  i32,    // the captures that win a round
	vote_percent:   i32,    // the percentage of players whose yes passes a vote
	script:         string, // the Lua script a dedicated server runs, if the file is there (docs/scripting.md)
}

Bot_Settings :: struct {
	alpha:      i32,  // bots on alpha
	bravo:      i32,  // bots on bravo
	difficulty: i32,  // 300 stupid, 200 poor, 100 normal, 50 hard, 10 impossible
	chat:       bool, // whether the bots talk
}

Flood_Settings :: struct {
	flooding_packets: i32, // messages in a second from one player that count as flooding (a client sends sixty)
	flood_warnings:   i32, // flood warnings before the player is kicked and barred for a quarter of an hour
}

Lobby_Settings :: struct {
	public: bool,   // a dedicated server lists itself with the lobby
	url:    string, // the lobby it lists itself with
	ip:     string, // the IPv4 address the lobby lists; empty for the one the server reaches it from
}

// The lists' entries (apps/server/lists). A player is named by their address ("1.2.3.4") and
// their machine's hardware ID (eleven hex digits): an entry names either, or both, and
// leaves the other empty.

Admin_Entry :: struct {
	address: string,
	name:    string, // as they were known when listed
}

Ban_Entry :: struct {
	address: string,
	hwid:    string,
	expires: i64,    // the Unix time it lifts at; 0 never
	name:    string, // the name it was given
	reason:  string,
}

Mute_Entry :: struct {
	address: string,
	hwid:    string,
	name:    string,
}

@(rodata)
DEFAULT_SERVER_CONFIG := Server_Config {
	server = {
		hostname      = "Soldat Reloaded server",
		port          = 23073,
		time_limit    = 15,
		capture_limit = 10,
		vote_percent  = 60,
		script        = "scripts/main.lua",
	},
	bots = {difficulty = 100, chat = true},
	network = {flooding_packets = 120, flood_warnings = 4},
	lobby = {url = LOBBY_URL},
	weapons = GATHER_WEAPONS,
}

// The defaults, and the file at `path` over them; the file made with the defaults if it
// isn't there. Free with server_config_destroy.
server_config_load :: proc(path: string) -> ^Server_Config {
	// The config is allocated inside its own arena, so one free takes all of it.
	config, _ := virtual.arena_growing_bootstrap_new_by_name(Server_Config, "arena")
	server_config_reset(config)
	switch config_read(path, config, virtual.arena_allocator(&config.arena)) {
	case .Read:
	case .Missing:
		server_config_save(config, path)
	case .Broken:
		server_config_reset(config) // what was read before it went wrong goes too
		config.broken = true
	}
	return config
}

// The config written to `path`, unless its file was broken. False, with the reason
// logged, if it can't be written.
server_config_save :: proc(config: ^Server_Config, path: string) -> bool {
	if config.broken do return true
	return config_write(path, config)
}

server_config_destroy :: proc(config: ^Server_Config) {
	// the config itself is in the arena, so it is destroyed from a copy: destroying it in
	// place would write to the arena after its memory is gone
	arena := config.arena
	virtual.arena_destroy(&arena)
}

// The config at its defaults, in its own arena.
@(private = "file")
server_config_reset :: proc(config: ^Server_Config) {
	arena := config.arena
	config^ = DEFAULT_SERVER_CONFIG
	config.arena = arena
}
