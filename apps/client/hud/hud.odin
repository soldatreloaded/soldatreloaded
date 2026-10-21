package hud

// What is drawn over the world: health, ammo, jets and the reload bar, the kill feed and
// big messages, the scoreboard and stats, the console and the chat, the vote's box and
// the radio menu, the minimap, teammates' names, the line's quality and the demos'
// marks, and the in-game menus (escape, team, weapons, and the kick and map windows).
//
// It keeps the C client's split of logic from drawing. What the HUD shows of the game is
// a frame's facts, a plain Hud_Data the match builds from the world each frame. What it
// remembers from tick to tick, the kills, the messages and the console, is fed from each
// tick's rulings and events and by what the match says into it (Feed). The menus are
// logic alone, turning the cursor, clicks and number keys into Menu_Actions the match
// carries out (Menus). The drawing reads those three, never the game, a file for each
// thing drawn.
//
//   hud.odin              the HUD's state, and the order it is drawn in
//   data.odin             Hud_Data, the facts of a frame
//   feed.odin             the kill feed, big messages, the consoles and my stats, fed each tick
//   menus.odin            the in-game menus: their buttons, and choosing
//   art.odin              the interface's images and lettering, and drawing them
//   draw_bars.odin        health, ammo, fire, jets, grenades; my numbers; the team box
//   draw_cursor.odin      the crosshair, the menus' pointer, my arrow
//   draw_feed.odin        the big message, kill feed, console, respawn count, FPS, last shot
//   draw_chat.odin        the prompt, what is said over heads, the vote's box, the radio
//   draw_emotes.odin      the emote wheel
//   draw_status.odin      my ping, whom I watch, the time left, the demo recorded or played
//   draw_scoreboard.odin  the scoreboard, my weapon stats, who won
//   draw_minimap.odin     the minimap
//   draw_names.odin       teammates' names, out of view or always
//   draw_texts.odin       a server script's texts, in the world and on the screen
//   draw_menus.odin       the menus
//
// Uses: ui, draw. From the C client: render/interface.c, ui/menus.c, ui/feed.c,
// ui/consoles.c, ui/hud_data.h.

import rl "vendor:raylib"

import res "../../../core/resources"
import "../draw"
import "../ui"

VERSION :: #config(SOLDATRELOADED_VERSION, "dev") // the release build sets it

// What the HUD keeps: the match owns it.
Hud :: struct {
	art:        Art,
	feed:       Feed,
	menus:      Menus,
	scoreboard: bool, // the frags menu: F1, and up while a round's scores stand
	stats:      bool, // my weapon stats: F2
	mute:       Maybe(Mute_Target), // a click on the open scoreboard asking to mute; the match takes and clears it
	demo_bar:   Demo_Bar, // a demo's player bar
	demo_ask:   Demo_Ask, // what it asked this frame; the match takes and clears it
}

hud_init :: proc(hud: ^Hud, mod: res.Mod) {
	hud^ = {}
	art_load(&hud.art, mod)
}

hud_destroy :: proc(hud: ^Hud) {
	art_destroy(&hud.art)
	hud^ = {}
}

// The scoreboard and the stats share their place: one opens over the other, closing it.
// Neither opens over the escape menu.
hud_toggle_scoreboard :: proc(hud: ^Hud) {
	if .Escape in hud.menus.open do return
	hud.scoreboard = !hud.scoreboard
	if hud.scoreboard do hud.stats = false
}

hud_toggle_stats :: proc(hud: ^Hud) {
	if .Escape in hud.menus.open do return
	hud.stats = !hud.stats
	if hud.stats do hud.scoreboard = false
}

// The HUD over the world, in the original's order: the pictures first, then the texts
// over them, the menus over all and the pointer over the menus. `minimap` is the
// map's, drawn for this window.
hud_draw :: proc(u: ^ui.Ui, hud: ^Hud, data: ^Hud_Data, minimap: ^draw.Minimap) {
	art, feed, menus := &hud.art, &hud.feed, &hud.menus
	me, mine := &data.players[data.me], &data.mine
	playing := me.active && me.team != .Spectator
	// the bars are the viewed player's (data.mine): mine as I play, and in a demo whoever
	// I follow, even one I recorded as a spectator. The crosshair and arrow stay mine, for
	// a soldier I control, so neither shows in a demo
	viewed := &data.players[data.viewed]
	_, demoing := data.demo.?
	show_bars := playing || (demoing && viewed.active && viewed.team != .Spectator)
	escape, team := .Escape in menus.open, .Team in menus.open
	typing := data.prompt.mode != .None
	mute_board := hud.scoreboard && data.scoreboard_mute // the scoreboard open, its mute signs to click
	// the crosshair is the recorder's own in a demo, at its cursor as recorded: only while
	// the camera follows the recorder, not another player or the free camera, where it
	// would stand at my mouse
	aiming := !demoing || (data.follow == nil && !data.free_camera)
	defer rl.EndBlendMode()

	draw_world_texts(u, data) // of the world, under the rest
	draw_big_message(u, feed)
	draw_screen_texts(u, data)
	if show_bars do draw_bars(u, art, mine)
	if playing {
		if !menus_any_open(menus) && !mine.dead && !data.ended && !mute_board && aiming do draw_crosshair(u, art, data) // gone as the round ends, as the original's; the scoreboard shows the pointer instead, to click its mute signs
		draw_my_arrow(u, art, data)
	}
	draw_kill_icons(u, art, feed, data.kill_log, kill_feed_top(data), hud.scoreboard)
	if data.minimap do draw_minimap(u, art, minimap, data)
	summary := data.ended && players(data) > 1 // the end screen replaces the plain scoreboard
	board_bottom: f32
	if hud.scoreboard && !summary do board_bottom = draw_scoreboard_box(u, art, data)
	draw_menu_boxes(u, art, menus, data)
	draw_vote_box(u, art, data)
	draw_team_box(u, art, data)

	if me.active do draw_bar_texts(u, art, data)
	draw_team_scores(u, art, data)
	if summary do draw_round_summary(u, art, data)
	if data.paused do draw_paused(u)
	if hud.stats && !summary do draw_stats(u, art, feed, data, hud.scoreboard)
	if hud.scoreboard && !summary do draw_scoreboard(u, data, board_bottom)
	draw_console(u, feed, hud.scoreboard || hud.stats || team || (typing && .Weapons in menus.open), typing, data.prompt.scroll)
	if playing do draw_respawn(u, art, mine)
	draw_vote(u, data)
	if data.radio.open && !escape do draw_radio(u, art, data, hud.scoreboard || hud.stats)
	if data.emotes.open && !escape do draw_emote_wheel(u, art, data)
	draw_prompt(u, data)
	draw_kill_feed(u, art, feed, data.kill_log, kill_feed_top(data), hud.scoreboard, typing)
	if me.active {
		draw_said(u, data)
		if data.player_names do draw_names(u, data)
	}
	if !mine.dead && !team && !escape && aiming do draw_under_cursor(u, data)
	draw_watching(u, data)
	if data.clock && !hud.scoreboard && !hud.stats do draw_time_left(u, data, minimap)
	draw_readouts(u, data)
	draw_clocks(u, data)
	draw_shot(u, feed, data.seconds)

	draw_menus(u, art, menus, data, hud.scoreboard || hud.stats)
	draw_demo_bar(u, hud, data) // a demo's player bar, under the pointer
	if menus_any_open(menus) || mine.dead || mute_board do draw_pointer(u, art, data) // the scoreboard's mute signs are clicked
	else if demo_bar_shown(hud) do pointer_draw(u, art, data.mouse, data.pointer.color, data.pointer.scale) // the bar's, at the mouse
	if mute_board && !summary && !menus_any_open(menus) do scoreboard_mute_input(hud, u, data)
}

// How many are in the game.
@(private = "file")
players :: proc(data: ^Hud_Data) -> (count: int) {
	for &player in data.players do count += int(player.active)
	return
}
