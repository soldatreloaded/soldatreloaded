package menu

import res "../../../core/resources"
import "../ui"

// The settings, a tab each: what is drawn (graphics.odin), the sound (sounds.odin), the
// mouse and the pointers, and the interface. The tab last looked at is the
// one the page opens on, the game's menu or the one over a match, till the game closes.

Settings_Tab :: enum {
	Graphics,
	Sound,
	Mouse,
	Interface,
}

@(private = "file", rodata)
SETTINGS_TAB_NAMES := [len(Settings_Tab)]string { // by Settings_Tab
	"Graphics",
	"Sound",
	"Mouse",
	"Interface",
}

@(private = "file")
settings_tab: Settings_Tab // the one last looked at, for the game's life

@(private = "file", rodata)
TYPING_NAMES := [?]string{"Off", "Dots", "Typing..."}

@(private = "file", rodata)
KILL_LOG_PLACES := [?]string{"Top right", "Lower right", "Top left"}

@(private = "file", rodata)
TIME_LEFT_PLACES := [?]string{"None", "Top center", "Top right", "Both"}

page_settings :: proc(menu: ^Menu) {
	k := &menu.kit
	settings_tab = Settings_Tab(ui.tabs(k, SETTINGS_TAB_NAMES[:], int(settings_tab)))
	ui.gap(k, 8)
	switch settings_tab {
	case .Graphics:  tab_graphics(menu)
	case .Sound:     tab_sound(menu)
	case .Mouse:     tab_mouse(menu)
	case .Interface: tab_interface(menu)
	}
}

@(private = "file")
tab_mouse :: proc(menu: ^Menu) {
	k := &menu.kit
	config := menu.config
	ui.section(k, "MOUSE")
	ui.slider(k, "Sensitivity", &config.controls.sensitivity, res.SENSITIVITY_LOWEST, res.SENSITIVITY_HIGHEST, 0.1, "%.2f")
	ui.section(k, "POINTERS")
	ui.color_row(k, "Menu cursor colour", &config.graphics.cursor_color)
	ui.slider(k, "Menu cursor size", &config.graphics.cursor_size, 50, 200, 10, "%d%%")
	ui.color_row(k, "Crosshair colour", &config.graphics.crosshair_color)
	ui.slider(k, "Crosshair size", &config.graphics.crosshair_size, 50, 200, 10, "%d%%")
}

@(private = "file")
tab_interface :: proc(menu: ^Menu) {
	k := &menu.kit
	config := menu.config
	ui.section(k, "NAMES")
	ui.toggle(k, "Player names", &config.interface.player_names)
	ui.toggle(k, "Teammates' names always", &config.interface.team_names)
	ui.color_row(k, "Teammate name colour", &config.interface.name_color)
	ui.color_row(k, "Flag carrier name colour", &config.interface.carrier_color)
	ui.enum_select(k, "Typing indicator", &config.interface.typing, TYPING_NAMES[:])
	ui.slider(k, "Typing indicator size", &config.interface.typing_size, 50, 200, 10, "%d%%")
	ui.color_row(k, "Taunt variable colour", &config.interface.taunt_var_color)
	ui.section(k, "KILL LOG")
	ui.slider(k, "Kill log length", &config.interface.kill_log_length, 0, 50, 2, "%d lines")
	ui.enum_select(k, "Kill log position", &config.interface.kill_log_position, KILL_LOG_PLACES[:])
	ui.toggle(k, "Hide your kills and deaths", &config.interface.kill_log_hide_mine)
	// each empty keeps the team's own colour, as the kill log has always coloured it
	ui.color_row(k, "Your kills and deaths", &config.interface.kill_color_mine)
	ui.color_row(k, "Your teammates", &config.interface.kill_color_team)
	ui.color_row(k, "The enemy", &config.interface.kill_color_enemy)
	ui.color_row(k, "Self-kills", &config.interface.kill_color_self)
	ui.section(k, "HUD")
	ui.toggle(k, "Scale interface", &config.interface.scale_interface)
	ui.toggle(k, "Minimap", &config.interface.minimap)
	ui.toggle(k, "Mute from scoreboard", &config.interface.scoreboard_mute)
	ui.enum_select(k, "Show time left", &config.interface.time_left_position, TIME_LEFT_PLACES[:])
	ui.toggle(k, "Show local time", &config.interface.local_time)
	ui.color_row(k, "Time colour", &config.interface.time_color)
	ui.toggle(k, "Show FPS", &config.interface.show_fps)
	ui.toggle(k, "Show ping", &config.interface.show_ping)
	ui.toggle(k, "Show packet loss", &config.interface.show_loss)
	ui.toggle(k, "Show jitter", &config.interface.show_jitter)
	ui.color_row(k, "Stats colour", &config.interface.stats_color)
	ui.section(k, "MUTING")
	ui.toggle(k, "Allow taunts from muted players", &config.mutes.allow_taunts)
	ui.toggle(k, "Allow radio from muted players", &config.mutes.allow_radio)
	ui.section(k, "CAMERA")
	ui.toggle(k, "Follow scoped shot", &config.graphics.track_shot)
	ui.toggle(k, "Others' fire shakes the screen", &config.graphics.screen_shake)
	if !config.graphics.screen_shake do ui.toggle(k, "Others' minigun fire shakes the screen", &config.graphics.minigun_shake) // with all of it on, the minigun's is in it
	ui.section(k, "DISCORD")
	ui.toggle(k, "Show on Discord", &config.interface.discord)
}
