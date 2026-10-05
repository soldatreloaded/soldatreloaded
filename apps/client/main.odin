package main

// The client: one screen at a time, the main menu or a game, each its own package.
// The loop reads input, updates the screen, draws it, and switches screens when the
// screen asks. It also loads the configs at the start and saves them at the end, keeps
// the window as the config has it as that changes, and keeps the sound, which outlives
// the screens: a match plays into it, as the menu will.
// Discord presence (interface.discord, the C client's net/discord.c) comes later, pumped
// from this loop.
//
//   menu    the main menu                        match   being in a game
//   draw    the world, drawn                     hud     what is drawn over it
//   ui      fonts and widgets                    sound   the game's sounds
//   input   keys and mouse into commands         net     the connection to a server
//   demo    recording and playing back games
//
// It runs from the install's root, where data/ and mods/ are: assets/ in this
// repository, the unpacked folder in a release. It keeps its settings there in
// client.config.json (core/resources/clientconfig.odin), and what Local Play hosts with
// in server.config.json (core/resources/serverconfig.odin), which a server beside it
// reads too.
//
//   cd assets && odin run ../apps/client

import "core:log"

import rl "vendor:raylib"

import sim "../../core/game"
import res "../../core/resources"
import "match"
import "menu"
import "sound"
import "ui"

CONFIG_PATH :: "client.config.json"
HOST_CONFIG_PATH :: "server.config.json"
MODS_DIR :: "mods"

TICK_SECONDS :: 1.0 / sim.TICK_RATE
MAX_FRAME :: 0.25 // seconds: a stall never turns into a burst of ticks
MAX_FPS_LOWEST :: 10 // graphics.max_fps is kept within these
MAX_FPS_HIGHEST :: 1000

Client :: struct {
	config:      ^res.Client_Config,
	host:        ^res.Server_Config, // what Local Play hosts with
	mod:         res.Mod,
	ui:          ui.Ui,
	sound:       sound.Sound,
	window:      Window, // as it was last made
	screen:      Screen,
	accumulator: f64, // seconds not yet ticked
}

// What the window shows; none once the client is closing. Each screen is large (a match
// holds the world, its art and its bots), so it lives on the heap and is switched by
// pointer.
Screen :: union {
	^menu.Menu,
	^match.Match,
}

main :: proc() {
	context.logger = log.create_console_logger(.Info, {.Level, .Time})

	client: Client
	client.config = res.client_config_load(CONFIG_PATH)
	client.host = res.server_config_load(HOST_CONFIG_PATH)
	client.mod = res.mod_make(MODS_DIR, client.config.graphics.mod)
	window_open(&client.window, &client.config.graphics)
	rl.InitAudioDevice()
	sound.sound_init(&client.sound, client.mod)
	ui.ui_init(&client.ui, client.mod)
	client.screen = menu_open(&client, menu.FIRST_MAP)

	for client.screen != nil && !rl.WindowShouldClose() {
		window_follow(&client.window, &client.config.graphics)
		ui.ui_begin(&client.ui)
		sound.sound_configure(&client.sound, client.config)
		update(&client, rl.GetFrameTime())
		sound.sound_update(&client.sound)
		// Discord presence will be pumped here, while client.config.interface.discord
		rl.BeginDrawing()
		draw(&client)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	screen_switch(&client, nil)
	ui.ui_destroy(&client.ui)
	sound.sound_destroy(&client.sound)
	rl.CloseAudioDevice()
	rl.CloseWindow()
	config_save(client.config, client.host)
	res.mod_destroy(&client.mod)
	res.server_config_destroy(client.host)
	res.client_config_destroy(client.config)
}

// The screen's frame, and the screen it asks for in its place. The menu doesn't tick;
// a match is given the ticks the frame owes.
update :: proc(client: ^Client, dt: f32) {
	switch screen in client.screen {
	case ^menu.Menu:
		switch request in menu.menu_update(screen) {
		case menu.Play:
			playing := new(match.Match)
			if match.match_start(playing, request.maps, client.host, client.config, client.mod, &client.sound) {
				screen_switch(client, playing)
			} else {
				free(playing)
			}
		case menu.Quit:
			screen_switch(client, nil)
		}
	case ^match.Match:
		ticks := ticks_owed(client, dt)
		switch _ in match.match_update(screen, client.config, &client.sound, ticks, tick_fraction(client), dt) {
		case match.Leave:
			screen_switch(client, menu_open(client, screen.map_name))
		}
	}
}

draw :: proc(client: ^Client) {
	switch screen in client.screen {
	case ^menu.Menu:   menu.menu_draw(screen, &client.ui)
	case ^match.Match: match.match_draw(screen, &client.ui, client.config)
	}
}

// The main menu, its local play on `last_map`.
menu_open :: proc(client: ^Client, last_map: string) -> Screen {
	m := new(menu.Menu)
	menu.menu_init(m, client.config, client.host, client.mod, last_map)
	return m
}

// The screen closed and `next` shown in its place, its time starting now.
screen_switch :: proc(client: ^Client, next: Screen) {
	switch screen in client.screen {
	case ^menu.Menu:
		menu.menu_destroy(screen)
		free(screen)
	case ^match.Match:
		match.match_end(screen)
		free(screen)
		sound.sound_silence(&client.sound) // its jets and reloads end with it
	}
	client.screen = next
	client.accumulator = 0
}

// How many ticks this frame owes: a whole tick comes out per tick, and the rest waits
// for the next frame.
ticks_owed :: proc(client: ^Client, dt: f32) -> int {
	client.accumulator = min(client.accumulator + f64(dt), MAX_FRAME)
	ticks := int(client.accumulator / TICK_SECONDS)
	client.accumulator -= f64(ticks) * TICK_SECONDS
	return ticks
}

// How far into the next tick the frame is, 0 to 1: how far the world is drawn from the
// last tick toward it.
tick_fraction :: proc(client: ^Client) -> f32 {
	return f32(client.accumulator / TICK_SECONDS)
}

// ---------------------------------------------------------------------------------
// The window

// The window's settings as they were last applied.
Window :: struct {
	mode:   res.Window_Mode,
	size:   [2]i32, // windowed
	vsync:  bool,
	fps:    i32, // the frames a second at most; 0 for no limit
}

// The window as the config has it: its size and mode, and how fast it is drawn.
window_open :: proc(window: ^Window, graphics: ^res.Graphics_Settings) {
	flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .MSAA_4X_HINT}
	if graphics.vsync do flags += {.VSYNC_HINT}
	rl.SetConfigFlags(flags)
	rl.InitWindow(graphics.screen_width, graphics.screen_height, "Soldat Reloaded")
	rl.SetExitKey(.KEY_NULL) // Escape is the screens'
	window^ = {mode = .Windowed, size = {graphics.screen_width, graphics.screen_height}, vsync = graphics.vsync, fps = -1}
	window_follow(window, graphics)
}

// The window changed to what the config has now, where it differs from what was made:
// the mode, the size while windowed, vsync and the frame rate's limit, as the C client
// applies them, at once.
window_follow :: proc(window: ^Window, graphics: ^res.Graphics_Settings) {
	size := [2]i32{graphics.screen_width, graphics.screen_height}
	if graphics.window_mode != window.mode {
		switch window.mode { // out of the one it was in
		case .Windowed:
		case .Fullscreen: rl.ToggleFullscreen()
		case .Borderless: rl.ToggleBorderlessWindowed()
		}
		switch graphics.window_mode { // into the one asked for
		case .Windowed:
			window_size(size)
		case .Fullscreen: // the display's own resolution, whatever the window's size was
			monitor := rl.GetCurrentMonitor()
			rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
			rl.ToggleFullscreen()
		case .Borderless:
			rl.ToggleBorderlessWindowed()
		}
		window.mode = graphics.window_mode
		window.size = size
	} else if size != window.size {
		if window.mode == .Windowed do window_size(size)
		window.size = size
	}
	if graphics.vsync != window.vsync {
		if graphics.vsync do rl.SetWindowState({.VSYNC_HINT})
		else do rl.ClearWindowState({.VSYNC_HINT})
		window.vsync = graphics.vsync
	}
	fps := clamp(graphics.max_fps, MAX_FPS_LOWEST, MAX_FPS_HIGHEST) if graphics.fps_limit else 0
	if fps != window.fps {
		rl.SetTargetFPS(fps)
		window.fps = fps
	}
}

// Windowed at `size`, in the middle of its display.
window_size :: proc(size: [2]i32) {
	rl.SetWindowSize(size.x, size.y)
	monitor := rl.GetCurrentMonitor()
	rl.SetWindowPosition((rl.GetMonitorWidth(monitor) - size.x) / 2, (rl.GetMonitorHeight(monitor) - size.y) / 2)
}

config_save :: proc(config: ^res.Client_Config, host: ^res.Server_Config) {
	if !res.client_config_save(config, CONFIG_PATH) do log.errorf("could not write %s", CONFIG_PATH)
	if !res.server_config_save(host, HOST_CONFIG_PATH) do log.errorf("could not write %s", HOST_CONFIG_PATH)
}
