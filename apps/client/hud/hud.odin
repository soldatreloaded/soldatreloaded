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

	// Scale_Interface off, each part drawn as big as in a 640 by 480 window, about the
	// point its place is kept by (zoom.odin): a corner, an edge's middle, an icon, the
	// cursor; what is over a soldier, each about its own. The end screen and a demo's bar,
	// this game's own, grow with the window still.
	by := shrink_of(u, data)
	menus.by = by
	middle := u.width / 2
	z: Zoom

	draw_world_texts(u, data) // of the world, under the rest
	z = zoom_around(u, {middle, BIG_MESSAGE_BASELINE}, by)
	draw_big_message(u, feed)
	zoom_end(z)
	draw_screen_texts(u, data)
	if show_bars do draw_bars(u, art, mine, by)
	if playing {
		if !menus_any_open(menus) && !mine.dead && !data.ended && !mute_board && aiming { // gone as the round ends, as the original's; the scoreboard shows the pointer instead, to click its mute signs
			z = zoom_around(u, data.cursor, by)
			draw_crosshair(u, art, data)
			zoom_end(z)
		}
		draw_my_arrow(u, art, data)
	}
	z = zoom_around(u, kill_feed_anchor(u, data), by)
	draw_kill_icons(u, art, feed, data.kill_log, kill_feed_top(data), hud.scoreboard)
	zoom_end(z)
	if data.minimap {
		z = zoom_around(u, MINIMAP_AT, by)
		draw_minimap(u, art, minimap, data)
		zoom_end(z)
	}
	board_bottom: f32
	if hud.scoreboard {
		z = zoom_around(u, board_anchor(u), by)
		board_bottom = draw_scoreboard_box(u, art, data)
		zoom_end(z)
	}
	draw_menu_boxes(u, art, menus, data)
	z = zoom_around(u, {45 * wide(u), 400}, by) // the vote's, and its box's
	draw_vote_box(u, art, data)
	zoom_end(z)
	draw_team_box(u, art, data)

	if me.active do draw_bar_texts(u, data)
	draw_team_scores(u, data)
	z = zoom_around(u, board_anchor(u), by) // who won, the pause's word, the stats and the scoreboard's, where the scoreboard is
	if data.ended && hud.scoreboard && players(data) > 1 do draw_round_end(u, data, board_bottom)
	if data.paused do draw_paused(u)
	if hud.stats do draw_stats(u, art, feed, data, hud.scoreboard)
	if hud.scoreboard do draw_scoreboard(u, data, board_bottom)
	zoom_end(z)
	z = zoom_around(u, {}, by)
	draw_console(u, feed, hud.scoreboard || hud.stats || team || (typing && .Weapons in menus.open), typing, data.prompt.scroll)
	zoom_end(z)
	if playing {
		z = zoom_around(u, {180 * wide(u), 0}, by)
		draw_respawn(u, art, mine)
		zoom_end(z)
	}
	z = zoom_around(u, {45 * wide(u), 400}, by)
	draw_vote(u, data)
	zoom_end(z)
	if data.radio.open && !escape {
		z = zoom_around(u, {5, 250}, by)
		draw_radio(u, art, data, hud.scoreboard || hud.stats)
		zoom_end(z)
	}
	if data.emotes.open && !escape {
		z = zoom_around(u, {middle, ui.VIEW_HEIGHT / 2}, by)
		draw_emote_wheel(u, art, data)
		zoom_end(z)
	}
	z = zoom_around(u, {5, PROMPT_BASELINE}, by)
	draw_prompt(u, data)
	zoom_end(z)
	z = zoom_around(u, kill_feed_anchor(u, data), by)
	draw_kill_feed(u, art, feed, data.kill_log, kill_feed_top(data), hud.scoreboard, typing)
	zoom_end(z)
	if me.active {
		draw_said(u, data)
		if data.health_bars do draw_health_bars(u, data)
		if data.player_names do draw_names(u, data)
	}
	if !mine.dead && !team && !escape && aiming {
		z = zoom_around(u, data.cursor, by)
		draw_under_cursor(u, data)
		zoom_end(z)
	}
	z = zoom_around(u, {middle, 430}, by)
	draw_watching(u, data)
	zoom_end(z)
	if data.clock && !hud.scoreboard && !hud.stats {
		z = zoom_around(u, {middle, 0}, by)
		draw_time_left(u, data, minimap)
		zoom_end(z)
	}
	z = zoom_around(u, {u.width, 0}, by) // the readouts and the clocks, along the top right
	draw_readouts(u, data)
	draw_clocks(u, data)
	zoom_end(z)
	z = zoom_around(u, {middle, 431}, by)
	draw_shot(u, feed, data.seconds)
	zoom_end(z)

	draw_menus(u, art, menus, data, hud.scoreboard || hud.stats)
	draw_demo_bar(u, hud, data) // a demo's player bar, under the pointer
	if menus_any_open(menus) || mine.dead || mute_board { // the scoreboard's mute signs are clicked
		z = zoom_around(u, data.cursor, by)
		draw_pointer(u, art, data)
		zoom_end(z)
	} else if demo_bar_shown(hud) do pointer_draw(u, art, data.mouse, data.pointer.color, data.pointer.scale) // the bar's, at the mouse
	if mute_board && !menus_any_open(menus) do scoreboard_mute_input(hud, u, data)
}

// What the kill feed is drawn about, unscaled: the side it keeps to, at its top.
@(private = "file")
kill_feed_anchor :: proc(u: ^ui.Ui, data: ^Hud_Data) -> [2]f32 {
	x := f32(5) if data.kill_log == .Top_Left else 600 * wide(u)
	return {x, kill_feed_top(data)}
}

// What the scoreboard, the stats and the pause's word are drawn about, unscaled: the top's
// middle, where they are centred.
board_anchor :: proc(u: ^ui.Ui) -> [2]f32 {
	return {u.width / 2, 0}
}

// How many are in the game.
@(private = "file")
players :: proc(data: ^Hud_Data) -> (count: int) {
	for &player in data.players do count += int(player.active)
	return
}
