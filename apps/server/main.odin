package server

// The server, headless: a console around a hosted game (server.odin), and a loop that pumps
// it until it is told to stop. It reads its config, loads the map, listens on its port,
// gives everyone who says Hello a soldier, plays the bots asked for, ticks the world
// with authority, and stops on `quit` or Ctrl-C.
//
// It runs from the install's root (assets/ in this repository), as the client does, and
// keeps its files there:
//
//   server.config.mjson  how it hosts, the rotation, the bots, the admins, bans and
//                        mutes (core/resources/server_config.odin),
//                        written whole as it starts, so it shows every setting, and as
//                        the bans and mutes change
//   weapons.ini          the weapons' numbers, as Soldat's weapons.ini has them
//                        (core/resources/weapons.odin); made as it starts if it isn't
//                        there, each number commented out
//   scripts/             the Lua scripts, every .lua in the folder the config names
//                        (app_script.odin); none ship, and the folder may be missing
//
//   server [-map:<name>] [-port:<port>]
//
// What is typed at it, a line at a time, is a console command (console.odin).

import "base:runtime"
import "core:c/libc"
import "core:flags"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

import "../../core/game"
import net "../../core/network"
import res "../../core/resources"
import "lobby"

// The files, at the install's root, where the server runs: assets/ in this repository.
SERVER_CONFIG :: "server.config.mjson"
OLD_SERVER_CONFIG :: "server.config.json" // the JSON config of before, read once if the MJSON isn't there
WEAPONS_INI :: "weapons.ini"

SLEEP :: time.Millisecond // between passes of the loop, so it never spins flat out

Arguments :: struct {
	map_name: string `args:"name=map" usage:"the first round's map; else the rotation's first"`,
	port:     u16 `usage:"the UDP port to listen on, over server.config.mjson's"`,
	ip:       string `usage:"the address to listen on, over server.config.mjson's (on fly.io, fly-global-services')"`,
	hostname: string `usage:"the game's name, over server.config.mjson's"`,
	lobby_ip: string `usage:"the IPv4 address the lobby lists, over server.config.mjson's (on fly.io, the app's dedicated one)"`,
}

App :: struct {
	sv:      Server,
	config:  ^res.Server_Config,
	weapons: res.Weapon_Table, // the weapons as they stand: weapons.ini's, and the `weapon` lines since
	lobby:   lobby.Lobby,
	args:    Arguments, // the command line, over the config
	rcon:    Rcon,   // remote admins (rcon.odin); held by its address, as the log reaches it
	script:  Script, // held by its address while open
	quit:    bool,
}

@(private = "file")
interrupted: bool // Ctrl-C, or a kill

main :: proc() {
	context.logger = log.create_console_logger(.Info, {.Level, .Time})
	args: Arguments
	flags.parse_or_exit(&args, os.args)

	app := new(App)
	defer free(app)
	// what the server logs goes to its console, and to the admins on rcon
	context.logger = log.create_multi_logger(context.logger, rcon_logger(&app.rcon))
	defer log.destroy_multi_logger(context.logger)
	if !start(app, args) do os.exit(1)
	libc.signal(libc.SIGINT, on_interrupt)
	libc.signal(libc.SIGTERM, on_interrupt)
	stdin_start()

	// The line is heard before the ticks; each tick the players' soldiers step on their
	// last keys and the bots on their own minds, and a snapshot goes to everyone; the
	// line is flushed after (server_pump).
	last := time.tick_now()
	for !app.quit && !sync.atomic_load(&interrupted) {
		dt := time.duration_seconds(time.tick_lap_time(&last))
		for line in stdin_take() do console_execute(app, line)
		if !server_pump(&app.sv, dt) do app.quit = true
		app_pump(app)
		now := time.duration_seconds(time.tick_since({}))
		rcon_pump(&app.rcon, &app.sv, app.config.server.admin_password, now)
		lobby.lobby_pump(&app.lobby, lobby_settings(app), now)
		free_all(context.temp_allocator)
		time.sleep(SLEEP)
	}

	log.info("stopping")
	stop(app)
}

@(private = "file")
on_interrupt :: proc "c" (_: i32) {
	sync.atomic_store(&interrupted, true)
}

// The config and the files beside it, the network, the game hosted on them, and rcon.
@(private = "file")
start :: proc(app: ^App, args: Arguments) -> bool {
	app.args = args
	app.config = res.server_config_load(SERVER_CONFIG, OLD_SERVER_CONFIG)
	// its file whole, as it stands; the command line is the server's (Options), not the file's
	if !res.server_config_save(app.config, SERVER_CONFIG) do log.errorf("could not write %s", SERVER_CONFIG)
	app.weapons = weapons_load(WEAPONS_INI)

	if !net.net_init() {
		log.error("ENet wouldn't start")
		return false
	}
	options := Options {
		config      = app.config,
		config_path = SERVER_CONFIG,
		data_dir    = game.DATA_DIR,
		first_map   = args.map_name,
		port        = args.port,
		ip          = args.ip,
		hostname    = args.hostname,
		weapons     = app.weapons,
	}
	if !server_init(&app.sv, options) {
		net.net_shutdown()
		return false
	}
	app_start(app)
	lobby.lobby_init(&app.lobby)
	if app.config.server.rcon {
		if app.config.server.admin_password == "" do log.info("rcon: off, as there is no admin password")
		else do rcon_open(&app.rcon, server_ip(&app.sv), server_port(&app.sv))
	}
	return true
}

@(private = "file")
stop :: proc(app: ^App) {
	lobby.lobby_close(&app.lobby)
	rcon_close(&app.rcon)
	app_stop(app) // before the server it listens to
	server_destroy(&app.sv)
	net.net_shutdown()
	res.server_config_destroy(app.config)
}


// The weapons the server plays by: GatherWM's, and `path` over them. The file made, each
// number commented out, if it isn't there.
@(private = "file")
weapons_load :: proc(path: string) -> res.Weapon_Table {
	weapons := res.GATHER_WEAPONS
	if !os.exists(path) {
		if err := os.write_entire_file(path, transmute([]byte)res.weapons_ini_template()); err != nil do log.errorf("could not write %s: %v", path, err)
		return weapons
	}
	name, read := res.weapons_ini_read(path, &weapons)
	if !read {
		log.errorf("could not read %s: the weapons are GatherWM's", path)
	} else if weapons != res.GATHER_WEAPONS {
		log.infof("weapons mod %s", name if name != "" else path)
	}
	return weapons
}

@(private = "file")
lobby_settings :: proc(app: ^App) -> lobby.Settings {
	l := &app.config.lobby
	address := app.args.lobby_ip if app.args.lobby_ip != "" else l.ip
	return {public = l.public, url = l.url if l.url != "" else lobby.DEFAULT_URL, address = address, port = server_port(&app.sv)}
}

// ---------------------------------------------------------------------------------
// The console's input: a thread blocks on the standard input line by line, and the loop
// takes what has come. A thread rather than polling, because a console and a pipe are
// polled differently on each platform and a blocking read is the same everywhere.

STDIN_LINES :: 8

@(private = "file")
Stdin :: struct {
	lock:  sync.Mutex,
	lines: [dynamic]string, // read and not yet taken; a line that arrives while it is full is lost
}

@(private = "file")
stdin: Stdin

@(private = "file")
stdin_start :: proc() {
	stdin.lines = make([dynamic]string, runtime.default_allocator())
	thread_start(proc() {
		buf: [256]u8
		line := strings.builder_make(runtime.default_allocator())
		for {
			n, err := os.read(os.stdin, buf[:])
			if err != nil || n <= 0 do return
			for c in buf[:n] {
				switch c {
				case '\r':
				case '\n':
					sync.guard(&stdin.lock)
					if len(stdin.lines) < STDIN_LINES do append(&stdin.lines, strings.clone(strings.to_string(line), runtime.default_allocator()))
					strings.builder_reset(&line)
				case:
					strings.write_byte(&line, c)
				}
			}
		}
	})
}

// The lines waiting, oldest first, in the temp allocator.
@(private = "file")
stdin_take :: proc() -> []string {
	sync.guard(&stdin.lock)
	taken := make([]string, len(stdin.lines), context.temp_allocator)
	for line, i in stdin.lines {
		taken[i] = strings.clone(line, context.temp_allocator)
		delete(line, runtime.default_allocator())
	}
	clear(&stdin.lines)
	return taken
}
