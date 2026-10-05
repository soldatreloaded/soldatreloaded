package hud

// What is drawn over the world: health, ammo, jets and the reload bar, the kill feed and
// big messages, the scoreboard and stats, the console, the minimap, teammates' names,
// and the in-game menus (escape, team, weapons).
//
// It keeps the C client's split of logic from drawing. What the HUD shows of the game is
// a frame's facts, a plain Hud_Data the match builds from the world each frame. What it
// remembers from tick to tick, the kills and messages, is fed from each tick's rulings
// and events (Feed). The menus are logic alone, turning the cursor, clicks and number
// keys into Menu_Actions the match carries out (Menus). The drawing reads those three,
// never the game, a file for each thing drawn.
//
//   hud.odin              the HUD's state, and the order it is drawn in
//   data.odin             Hud_Data, the facts of a frame
//   feed.odin             the kill feed, big messages, console lines and my stats, fed each tick
//   menus.odin            the escape, team and weapons menus: their buttons, and choosing
//   art.odin              the interface's images and lettering, and drawing them
//   draw_bars.odin        health, ammo, fire, jets, grenades; my numbers; the team box
//   draw_cursor.odin      the crosshair, the menus' pointer, my arrow
//   draw_feed.odin        the big message, kill feed, console, respawn count, FPS, last shot
//   draw_scoreboard.odin  the scoreboard, my weapon stats, who won
//   draw_minimap.odin     the minimap
//   draw_names.odin       teammates' names, out of view or always
//   draw_menus.odin       the menus
//
// Online adds to it in these places: the chat and its input, and the big console, with
// the console (fed into the Feed, drawn in draw_feed.odin); the kick and map windows,
// menus beside the escape menu (menus.odin, whose tables already name their buttons);
// the vote's box and the radio menu, a draw file each, what they show in Hud_Data; the
// typing indicator over who is typing, styled by Hud_Data.typing (interface.typing); the
// ping, in Player.
//
// Uses: ui, draw. From the C client: render/interface.c, ui/menus.c, ui/feed.c,
// ui/consoles.c, ui/hud_data.h.

import rl "vendor:raylib"

import res "../../../core/resources"
import "../draw"
import "../ui"

// What the HUD keeps: the match owns it.
Hud :: struct {
	art:        Art,
	feed:       Feed,
	menus:      Menus,
	scoreboard: bool, // the frags menu: F1, and up while a round's scores stand
	stats:      bool, // my weapon stats: F2
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
	escape, team := .Escape in menus.open, .Team in menus.open
	defer rl.EndBlendMode()

	draw_big_message(u, feed)
	if playing {
		draw_bars(u, art, mine)
		if !menus_any_open(menus) && !mine.dead do draw_crosshair(u, art, data)
		draw_my_arrow(u, art, data)
	}
	draw_kill_icons(u, art, feed, data.kill_log, hud.scoreboard)
	if data.minimap do draw_minimap(u, art, minimap, data)
	board_bottom: f32
	if hud.scoreboard do board_bottom = draw_scoreboard_box(u, art, data)
	draw_menu_boxes(u, art, menus, data)
	draw_team_box(u, art, data)

	if me.active do draw_bar_texts(u, data)
	draw_team_scores(u, data)
	if data.ended && hud.scoreboard && players(data) > 1 do draw_round_end(u, data, board_bottom)
	if data.paused do draw_paused(u)
	if hud.stats do draw_stats(u, art, feed, data, hud.scoreboard)
	if hud.scoreboard do draw_scoreboard(u, data)
	draw_console(u, feed, hud.scoreboard || hud.stats || team)
	if playing do draw_respawn(u, art, mine)
	draw_kill_feed(u, feed, data.kill_log, hud.scoreboard)
	if data.player_names do draw_names(u, data)
	if !mine.dead && !team && !escape do draw_under_cursor(u, data)
	if data.info do draw_info(u, data)
	draw_shot(u, feed, data.seconds)

	draw_menus(u, art, menus, data, hud.scoreboard || hud.stats)
	if menus_any_open(menus) || mine.dead do draw_pointer(u, art, data)
}

// How many are in the game.
@(private = "file")
players :: proc(data: ^Hud_Data) -> (count: int) {
	for &player in data.players do count += int(player.active)
	return
}
