package main

// The client: one screen at a time, the main menu or a game, each its own package.
// The loop reads input, updates the screen, draws it, and switches screens when the
// screen asks. Before the first, while the client starts, it shows the loading screen
// (menu/loading.odin). It also loads the configs at the start and saves them at the
// end, keeps the window as the config has it as that changes, and keeps what outlives
// the screens:
// the sound, which a match plays into; the line to a server, which the menu opens and a
// match plays on, polled here each frame; the server browser's list; and what Discord
// shows I'm playing (online/discord.odin), pumped each frame. Over a match, the escape
// menu's Settings brings up the main menu's settings pages (settings_open), the match
// playing on under them.
//
//   menu    the main menu                        match   being in a game
//   draw    the world, drawn                     hud     what is drawn over it
//   ui      fonts and widgets                    sound   the game's sounds
//   input   keys and mouse into commands         online  the line to a server, the browser
//   demo    recording and playing back games
//
// It runs from the install's root, where data/ and mods/ are: assets/ in this
// repository, the unpacked folder in a release. It keeps its settings there in
// client.config.mjson (core/resources/client_config.odin), Offline Play's among them.
//
//   cd assets && odin run ../apps/client

import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"

import rl "vendor:raylib"

import sim "../../core/game"
import network "../../core/network"
import res "../../core/resources"
import "../../core/utils"
import "match"
import "menu"
import "input"
import "online"
import "sound"
import "ui"

CONFIG_PATH :: "client.config.mjson"
OLD_CONFIG_PATH :: "client.config.json" // the JSON config of before, read once if the MJSON isn't there

TICK_SECONDS :: 1.0 / sim.TICK_RATE
MAX_FRAME :: 0.25 // seconds: a stall never turns into a burst of ticks

Client :: struct {
	config:        ^res.Client_Config,
	mod:           res.Mod,
	ui:            ui.Ui,
	sound:         sound.Sound,
	window:        Window, // as it was last made
	screen:        Screen,
	accumulator:   f64, // seconds not yet ticked
	line:          online.Line, // the line to a server, or a demo's
	browser:       online.Browser, // the server browser's list
	catalog:       online.Catalog, // the mods' catalogue, and the mod being installed from it
	settings:      ^menu.Menu, // the settings over a match, while they are up (the escape menu's Settings)
	last_map:      string, // Offline Play's last, which the menu offers again
	discord:       online.Discord, // the pipe to the Discord app here
	showing:       Maybe(Showing), // what Discord was last shown (discord_update), none before the first
	showing_since: i64, // and since when, Unix seconds
}

// What Discord shows I'm doing.
Showing :: enum {
	Menu,
	Offline,
	Online,
	Demo,
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

	// started by a join link clicked (online/link.odin): wherever the system started it,
	// the game runs from its install, where data/ and its config are
	link, linked := link_arg()
	if linked {
		if dir, err := os.get_executable_directory(context.temp_allocator); err == nil do os.set_working_directory(dir)
	}

	client: Client
	client.config = res.client_config_load(CONFIG_PATH, OLD_CONFIG_PATH)
	client.mod = res.mod_make(res.MODS_DIR, res.part_choices(client.config.graphics.parts))
	client.last_map = strings.clone(menu.FIRST_MAP)
	if !online.line_init(&client.line) do log.error("ENet wouldn't start: there is no playing online")
	window_open(&client.window, &client.config.graphics)
	ui.ui_init(&client.ui, client.mod) // first: the loading screen is written in its faces
	for step, i in START_STEPS {
		loading_show(&client, step.doing, f32(i) / len(START_STEPS))
		step.run(&client)
	}
	screenshots_collect() // any left where the game runs, from before
	// a release's game is the system's for join links, from wherever it is installed now;
	// a build from the source leaves them to the release
	if menu.VERSION != "dev" && !online.link_register() do log.warn("join links won't open the game: it couldn't be made their handler")
	if linked {
		if target, ok := online.link_target(link); ok {
			connect(&client, target)
		} else {
			log.warnf("not a join link the game takes: %s", link)
		}
	}

	for client.screen != nil && !rl.WindowShouldClose() {
		window_follow(&client.window, &client.config.graphics)
		ui.ui_begin(&client.ui)
		sound.sound_configure(&client.sound, client.config)
		update(&client, rl.GetFrameTime())
		sound.sound_update(&client.sound)
		discord_update(&client)
		// raylib took one of its own on F12 as the last frame ended, which isn't wanted
		if rl.IsKeyPressed(.F12) do screenshot_discard()
		if input.bound_pressed(client.config, "minimize") do rl.MinimizeWindow() // to the taskbar; the taskbar or Alt+Tab brings it back
		shot := input.bound_pressed(client.config, "screenshot")
		rl.BeginDrawing()
		draw(&client)
		rl.EndDrawing()
		if shot do screenshot_take()
		free_all(context.temp_allocator)
	}

	screen_switch(&client, nil)
	online.discord_close(&client.discord)
	online.browser_close(&client.browser)
	online.catalog_close(&client.catalog)
	online.line_shutdown(&client.line)
	ui.ui_destroy(&client.ui)
	sound.sound_destroy(&client.sound)
	rl.CloseAudioDevice()
	rl.CloseWindow()
	config_save(client.config)
	delete(client.last_map)
	res.mod_destroy(&client.mod)
	res.client_config_destroy(client.config)
}

// ---------------------------------------------------------------------------------
// Starting

// The join link the game was started with, as its argument; none for a start of any other
// kind.
link_arg :: proc() -> (link: string, ok: bool) {
	for arg in os.args[1:] do if online.link_is(arg) do return arg, true
	return
}

// What starting takes once the window is open, in order: the steps slow enough to be
// waited on, each shown on the loading screen as it runs.
Start_Step :: struct {
	doing: string, // what the loading screen says while it runs
	run:   proc(client: ^Client),
}

@(rodata)
START_STEPS := [?]Start_Step {
	{"Starting the sound", start_sound}, // the audio device alone takes a second
	{"Loading the menu", start_menu},
}

start_sound :: proc(client: ^Client) {
	rl.InitAudioDevice()
	sound.sound_init(&client.sound, client.mod)
}

start_menu :: proc(client: ^Client) {
	screen_switch(client, menu_open(client))
}

// One frame of the loading screen, saying what is being done, `share` of the way there.
// The window holds it while the step that follows runs.
loading_show :: proc(client: ^Client, doing: string, share: f32) {
	ui.ui_begin(&client.ui)
	rl.BeginDrawing()
	menu.loading_draw(&client.ui, doing, share)
	rl.EndDrawing()
	free_all(context.temp_allocator)
}

// ---------------------------------------------------------------------------------
// The screens

// The line first, with what it brings going into the game on screen; then the screen's
// frame, and the screen it asks for in its place. The menu doesn't tick; a match is
// given the ticks the frame owes, at its pace.
update :: proc(client: ^Client, dt: f32) {
	online.line_poll(&client.line, line_game(client))
	switch screen in client.screen {
	case ^menu.Menu:
		online.browser_pump(&client.browser)
		online.catalog_pump(&client.catalog)
		switch request in menu.menu_update(screen) {
		case menu.Play:
			playing := new(match.Match)
			if match.match_start(playing, request.maps, client.config, client.mod, &client.sound) {
				screen_switch(client, playing)
			} else {
				free(playing)
			}
		case menu.Connect:
			connect(client, request.address)
		case menu.Disconnect:
			online.line_disconnect(&client.line)
		case menu.Play_Demo:
			demo_play(client, request.name)
		case menu.Refresh:
			online.browser_refresh(&client.browser, client.config.network.lobby)
		case menu.Use_Mod:
			mod_use(client, request.parts)
		case menu.Back: // the settings over a game's alone
		case menu.Quit:
			screen_switch(client, nil)
		}
		// a server has taken me, and its map is in hand: the game on it
		if _, still := client.screen.(^menu.Menu); still && online.line_live(&client.line) && online.line_has_map(&client.line) {
			playing := new(match.Match)
			if match.match_join(playing, &client.line, client.config, client.mod, &client.sound) {
				screen_switch(client, playing)
			} else {
				free(playing)
				online.line_disconnect(&client.line)
			}
		}
	case ^match.Match:
		// the settings over it, if they are up, have the keys and the mouse; the match
		// plays on under them
		held := client.settings != nil
		if held do settings_update(client)
		ticks := ticks_owed(client, dt * f32(match.match_pace(screen)))
		switch request in match.match_update(screen, client.config, &client.sound, ticks, tick_fraction(client), dt, held) {
		case match.Open_Settings:
			settings_open(client)
		case match.Leave:
			leave(client)
		case match.Quit:
			leave(client)
			screen_switch(client, nil)
		case match.Connect:
			leave(client)
			connect(client, request.address)
		case match.Play_Demo:
			leave(client)
			demo_play(client, request.name)
		}
	}
	online.line_flush(&client.line) // what the ticks said goes out now, not a tick late
}

draw :: proc(client: ^Client) {
	switch screen in client.screen {
	case ^menu.Menu:   menu.menu_draw(screen, &client.ui)
	case ^match.Match:
		match.match_draw(screen, &client.ui, client.config)
		if client.settings != nil {
			ui.ui_fit(&client.ui, {0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) // the whole window, not the match's view
			menu.menu_draw(client.settings, &client.ui)
		}
	}
}

// The settings over the match (the main menu's own pages, in_game), from its escape
// menu: the mouse let go for them, as the main menu has it.
settings_open :: proc(client: ^Client) {
	if client.settings != nil do return
	client.settings = new(menu.Menu)
	menu.menu_init(client.settings, client.config, client.mod, client.last_map, &client.line, &client.browser, &client.catalog, in_game = true)
	cursor_follow(client.settings)
}

// The settings' frame: the keys and the mouse, and Back to game (or Escape) taken.
settings_update :: proc(client: ^Client) {
	#partial switch _ in menu.menu_update(client.settings) {
	case menu.Back:
		settings_close(client)
	}
}

// The settings closed, and saved now rather than as the game closes; the mouse the
// match's again.
settings_close :: proc(client: ^Client) {
	if client.settings == nil do return
	menu.menu_destroy(client.settings)
	free(client.settings)
	client.settings = nil
	config_save(client.config)
	cursor_follow(client.screen)
}

// The main menu, its Offline Play on the map played last.
menu_open :: proc(client: ^Client) -> Screen {
	m := new(menu.Menu)
	menu.menu_init(m, client.config, client.mod, client.last_map, &client.line, &client.browser, &client.catalog)
	return m
}

// Each part worn from the mod `parts` names for it ("" for Classic's; the names the
// request's, which it takes), from now on, and kept in the config: the faces, the sounds
// and the menu's art loaded again from them, the menu standing as it is. A match loads
// its own art as it starts.
mod_use :: proc(client: ^Client, parts: [res.Part]string) {
	choice := &client.config.graphics.parts
	for name, part in parts {
		if chosen := res.part_choice_of(choice, part); chosen != nil do chosen^ = strings.clone(name, virtual.arena_allocator(&client.config.arena))
		delete(name) // the request's, which the client takes
	}
	config_save(client.config)
	res.mod_destroy(&client.mod)
	client.mod = res.mod_make(res.MODS_DIR, res.part_choices(choice^))
	ui.ui_destroy(&client.ui)
	ui.ui_init(&client.ui, client.mod)
	sound.sound_destroy(&client.sound)
	sound.sound_init(&client.sound, client.mod)
	if m, is_menu := client.screen.(^menu.Menu); is_menu do menu.menu_mods_changed(m, client.mod)
	if client.settings != nil do menu.menu_mods_changed(client.settings, client.mod)
}

// The match over, whatever played it: its line closed, and the main menu back, on the
// map Offline Play last played.
leave :: proc(client: ^Client) {
	if playing, is_match := client.screen.(^match.Match); is_match && playing.mode == .Offline {
		delete(client.last_map)
		client.last_map = strings.clone(playing.map_name)
	}
	online.line_disconnect(&client.line)
	screen_switch(client, menu_open(client))
}

// The line to `target` (host:port, with /password after it if the server asks one: else
// the config's), saying who I am in the Hello: my name, the password to join with, my
// look, my secondary; no primary, which the weapons menu picks.
connect :: proc(client: ^Client, target: string) {
	config := client.config
	address, password, has_password := online.target_split(target)
	if !has_password do password = config.network.password
	hello := network.Msg_Hello {
		look      = match.look_of(config),
		primary   = .Punch,
		secondary = config.player.secondary_weapon,
	}
	utils.short_string_set(&hello.name, config.player.name)
	utils.short_string_set(&hello.password, password)
	online.line_connect(&client.line, address, hello)
}

// The demo `name` played, from the menu; why not, on the menu's demos page, if it can't be.
demo_play :: proc(client: ^Client, name: string) {
	playing := new(match.Match)
	if error, ok := match.match_play_demo(playing, &client.line, name, client.config, client.mod, &client.sound); ok {
		screen_switch(client, playing)
		return
	} else if m, is_menu := client.screen.(^menu.Menu); is_menu {
		menu.menu_demo_failed(m, error)
	}
	free(playing)
}

// The world the line's snapshots go into: the match's, while one plays on the line.
line_game :: proc(client: ^Client) -> ^sim.Game {
	playing, is_match := client.screen.(^match.Match)
	return playing.game if is_match && playing.mode != .Offline else nil
}

// The screen closed and `next` shown in its place, its time starting now, with the
// system cursor as it wants it.
screen_switch :: proc(client: ^Client, next: Screen) {
	settings_close(client) // the settings over a match go with it
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
	cursor_follow(next)
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
// Discord

// What Discord shows: the menus, or a match as match.discord_activity tells it; the time
// counted from when that began, not from each map, but in a round the time it has left.
discord_update :: proc(client: ^Client) {
	showing := Showing.Menu
	playing, is_match := client.screen.(^match.Match)
	if is_match {
		switch playing.mode {
		case .Offline: showing = .Offline
		case .Online:  showing = .Online
		case .Demo:    showing = .Demo
		}
	}
	if client.showing != showing {
		client.showing = showing
		client.showing_since = time.time_to_unix(time.now())
	}
	now := time.time_to_unix(time.now())
	a: online.Discord_Activity
	if is_match {
		a = match.discord_activity(playing, now, client.showing_since, menu.VERSION_LABEL)
		// a server on the lobby's list that asks no password: a Join game button to it
		if playing.mode == .Online {
			address := utils.short_string_text(&client.line.address)
			if online.browser_open_to_all(&client.browser, address) do utils.short_string_set(&a.join, address)
		}
		// the round's end as it was said, while it is where it was give or take the second
		// the clock is between: not said again for that
		if was := client.discord.want.ends; a.ends != 0 && was != 0 && abs(a.ends - was) <= 2 do a.ends = was
	} else {
		a = {since = client.showing_since}
		utils.short_string_set(&a.details, "In the menus")
		utils.short_string_set(&a.icon_text, fmt.tprintf("Soldat Reloaded %s", menu.VERSION_LABEL))
	}
	online.discord_set(&client.discord, a)
	online.discord_pump(&client.discord, rl.GetTime(), client.config.interface.discord)
}

// ---------------------------------------------------------------------------------
// The window

// The window's settings as they were last applied.
Window :: struct {
	mode:    res.Window_Mode,
	monitor: i32, // the display it is on
	size:    [2]i32, // windowed
	vsync:   bool,
	fps:     i32, // the frames a second at most; 0 for no limit
	topmost: bool, // over everything while focused, let go of when it loses focus
}

// The window as the config has it: its size and mode, and how fast it is drawn. It
// can't be resized by hand, as the original's can't: its size is the resolution's.
window_open :: proc(window: ^Window, graphics: ^res.Graphics_Settings) {
	flags := rl.ConfigFlags{.MSAA_4X_HINT}
	if graphics.vsync do flags += {.VSYNC_HINT}
	rl.SetConfigFlags(flags)
	// made small, the screen's size not known until it is, then sized and placed as the
	// config has it below: one made at a resolution chosen for fullscreen, larger than the
	// screen, would sit off it, its title bar above the top
	rl.InitWindow(min(graphics.screen_width, 800), min(graphics.screen_height, 600), "Soldat Reloaded")
	lock_keys_plain() // Caps Lock down while held, not while its lock is on
	when ODIN_OS != .Windows { // the badge as the window's icon; on Windows it is the executable's own
		icon := rl.LoadImage("data/icon.png")
		if icon.data != nil {
			rl.SetWindowIcon(icon)
			rl.UnloadImage(icon)
		}
	}
	rl.SetExitKey(.KEY_NULL) // Escape is the screens'
	window^ = {mode = .Windowed, monitor = -1, size = {-1, -1}, vsync = graphics.vsync, fps = -1} // nothing applied yet: all of it is
	window_follow(window, graphics)
}

// The window changed to what the config has now, where it differs from what was made:
// the mode, the display, the size while windowed, vsync and the frame rate's limit, as
// the C client applies them, at once. Fullscreen is a window without borders over the
// whole screen, at the display's own mode, so Alt+Tab is instant and nothing flickers;
// the resolution is the view's then, not the window's (draw/view.odin).
window_follow :: proc(window: ^Window, graphics: ^res.Graphics_Settings) {
	size := [2]i32{graphics.screen_width, graphics.screen_height}
	monitor := menu.display_of(graphics)
	if graphics.window_mode != window.mode || monitor != window.monitor || (window.mode == .Windowed && size != window.size) {
		switch graphics.window_mode {
		case .Windowed:   window_windowed(size, monitor)
		case .Fullscreen: window_fullscreen(monitor)
		}
		window.mode = graphics.window_mode
		window.monitor = monitor
		window.size = size
	}
	if graphics.vsync != window.vsync {
		if graphics.vsync do rl.SetWindowState({.VSYNC_HINT})
		else do rl.ClearWindowState({.VSYNC_HINT})
		window.vsync = graphics.vsync
	}
	fps := clamp(graphics.max_fps, menu.MAX_FPS_LOWEST, menu.MAX_FPS_HIGHEST) if graphics.fps_limit else 0
	if fps != window.fps {
		rl.SetTargetFPS(fps)
		window.fps = fps
	}
	// With graphics.topmost on, over every other window while it has focus, so a borderless
	// window stays above the taskbar as it is played; let go of the moment it loses focus,
	// so Alt+Tab brings the window switched to in front of it rather than trapping it
	// behind. Off (the default), an ordinary window that never forces itself on top.
	want := graphics.topmost && rl.IsWindowFocused()
	if want != window.topmost {
		if want do rl.SetWindowState({.WINDOW_TOPMOST})
		else do rl.ClearWindowState({.WINDOW_TOPMOST})
		window.topmost = want
	}
}

// Windowed at the size `wanted`, borderless and centred on the display `monitor`: no
// title bar or border, the size the player chose, in the middle of the screen (its top
// left kept on the display when the size is larger than the screen). The window has no
// title bar to catch and is always re-centred, so it isn't dragged; the view is the
// window's own, whatever its size (draw/view.odin).
window_windowed :: proc(wanted: [2]i32, monitor: i32) {
	screen := [2]i32{rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor)}
	size := [2]i32{max(wanted.x, 1), max(wanted.y, 1)}
	at := rl.GetMonitorPosition(monitor)
	when ODIN_OS == .Linux {
		if rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) do rl.ToggleBorderlessWindowed() // out of the fullscreen
	}
	rl.SetWindowState({.WINDOW_UNDECORATED}) // borderless, as the fullscreen window is
	rl.SetWindowSize(size.x, size.y)
	// centred on the display; clamped so a window larger than the screen keeps its top left on it
	x := max((screen.x - size.x) / 2, 0)
	y := max((screen.y - size.y) / 2, 0)
	rl.SetWindowPosition(i32(at.x) + x, i32(at.y) + y)
}

// Fullscreen. On Windows an ordinary window, undecorated and over the whole of its
// display, so it goes behind another as any window does: raylib's own fullscreen is
// GLFW's, which holds the window over every other there, even after Alt+Tab. On Linux
// such a window is still an ordinary one to the desktop, which keeps its panels and bars
// over it; only the window manager's fullscreen covers them, which raylib's borderless
// mode asks for, at the display's own mode, so nothing flickers. It covers the display
// the window is on, so the window is moved onto `monitor` first, out of the fullscreen
// if it was over another.
window_fullscreen :: proc(monitor: i32) {
	when ODIN_OS == .Linux {
		if rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) {
			if rl.GetCurrentMonitor() == monitor do return
			rl.ToggleBorderlessWindowed()
		}
		at := rl.GetMonitorPosition(monitor)
		rl.SetWindowPosition(i32(at.x), i32(at.y))
		rl.ToggleBorderlessWindowed()
	} else {
		at := rl.GetMonitorPosition(monitor)
		rl.SetWindowState({.WINDOW_UNDECORATED})
		rl.SetWindowPosition(i32(at.x), i32(at.y))
		rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
	}
}

// The system cursor as `screen` wants it. The menu draws its own pointer where the
// system's is, so the system's is free but hidden. A match keeps its own cursor, moved
// by the mouse's motion (input.odin), so the system's is hidden and held in the window:
// it can't wander onto another display or click outside the game.
//
// It is set here, once the screen before is gone, and not by the screens themselves: the
// next screen is made before the last is closed, so a screen's closing undid what the
// next had set.
cursor_follow :: proc(screen: Screen) {
	switch _ in screen {
	case ^menu.Menu:
		rl.EnableCursor() // let go, if a match held it
		rl.HideCursor()
	case ^match.Match:
		rl.DisableCursor()
	}
}

config_save :: proc(config: ^res.Client_Config) {
	if !res.client_config_save(config, CONFIG_PATH) do log.errorf("could not write %s", CONFIG_PATH)
}
