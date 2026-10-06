package match

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

import sim "../../../core/game"
import network "../../../core/network"
import res "../../../core/resources"
import "../../../core/utils"
import "../demo"
import "../online"
import "../sound"

// Demos, on the match's side. Online, the game recorded (record, or every round with
// demos.record_rounds): begun once the frame's packets are in, with the round as the
// client has it so far; every message the line brings from then on, a frame mark after
// each frame's, my part after each tick; ended by the next Map, as the original's map
// change ends it, or by the line lost. A demo played: the line is the demo's, its
// messages heard at its frames, my soldier its recorder's, stepped on its commands and
// put where it stood; at its pace (demo_fast), held (demo_pause), or taken to a tick
// (demo_tick), the ticks between run as fast as they go, unseen and unheard.

SEEK_BUDGET :: 25 * time.Millisecond // of a frame, a seek's ticks run; the window keeps answering

Playback :: struct {
	player:  ^demo.Player, // the match's own, while a demo plays
	tick:    demo.Tick,    // the tick on hand: my command and soldier
	ticked:  bool,         // `tick` holds the tick to run next
	paused:  bool,
	speed:   f32,          // times its own
	seeking: bool,         // running on, unseen and unheard, to `seek_to`
	seek_to: u32,
}

// What `record` asked, and whether this round has a demo begun.
Record_Asked :: struct {
	asked:          bool,
	name:           string, // its own; empty for the date and the map
	round_recorded: bool,   // a demo of this round was begun: record_rounds begins no other
}

// The demo `name` played in a new match's place, on the line `n` (its playback): its
// first messages heard up to the Map that makes its world. The reason, if it can't be.
match_play_demo :: proc(match: ^Match, n: ^online.Line, name: string, config: ^res.Client_Config, mod: res.Mod, sounds: ^sound.Sound) -> (error: string, ok: bool) {
	player := new(demo.Player)
	path := demo.demo_path(name)
	if error, ok = demo.player_open(player, path); !ok {
		free(player)
		return
	}
	header := &player.header
	map_name := utils.short_string_text(&header.map_name)
	if !online.line_map_present(map_name) { // its world couldn't be made: it isn't played
		demo.player_close(player)
		free(player)
		return fmt.tprintf("The demo's map %s is not here.", map_name), false
	}
	online.line_play(n, sim.Soldier_Id(header.slot))
	for !online.line_has_map(n) {
		#partial switch record in demo.player_next(player) {
		case []u8:
			online.line_feed(n, nil, record)
		case:
			demo.player_close(player)
			free(player)
			online.line_disconnect(n)
			return fmt.tprintf("%s has no game in it.", path), false
		}
	}
	if !match_join(match, n, config, mod, sounds, player) { // the match owns the player now, and let it go
		online.line_disconnect(n)
		return fmt.tprintf("The demo's map %s couldn't be loaded.", map_name), false
	}
	seconds := header.ticks / sim.TICK_RATE
	client_say(match, "Playing demo %s: %s on %s, %d:%02d", player.name, utils.short_string_text(&header.name), map_name, seconds / 60, seconds % 60)
	return "", true
}

// Before a tick of the demo: its records up to it, heard; false at the demo's end.
demo_tick_ready :: proc(match: ^Match) -> bool {
	p := &match.playback
	if p.ticked do return true
	for {
		switch record in demo.player_next(p.player) {
		case []u8:
			online.line_feed(match.line, match.game, record)
		case demo.Frame:
			if !take(match) do return false
		case ^demo.Tick:
			p.tick = record^
			p.ticked = true
			return true
		case nil:
			client_say(match, "Demo ended")
			return false
		}
	}
}

// My soldier as the demo's tick left it. It stepped on my command, so my shots flew as
// they flew; then its owned half is put back as it was, so it stands (or lies) where it
// stood whatever the steps made of it, and its look, loadout and typing are as recorded.
demo_apply_self :: proc(match: ^Match) {
	p := &match.playback
	p.ticked = false
	t := &p.tick
	s := &match.game.world.soldiers[match.me]
	if !t.present || !s.active do return
	s.player.look = t.self.player.look
	s.loadout = t.self.loadout
	s.player.typing = t.self.player.typing
	s.aim.hit_spray = t.self.aim.hit_spray // my aim as disturbed then: the next tick's shots spread as they did
	if t.self.vitals.life == s.vitals.life do network.soldier_take_owned(match.game.resources.animations, s, &t.self)
}

// The ticks of the demo that have run.
demo_at :: proc(match: ^Match) -> u32 {
	p := &match.playback
	return p.player.tick - (1 if p.ticked else 0)
}

// demo_pause, demo_fast, demo_tick <tick>, demo_tick_r <ticks>: held or let go, at eight
// times its speed or its own, taken to a tick (60 a second) or that many on or back.
demo_command :: proc(match: ^Match, word, rest: string) {
	if match.mode != .Demo do return
	p := &match.playback
	switch word {
	case "demo_pause":
		p.paused = !p.paused
	case "demo_fast":
		p.speed = 1 if p.speed > 1 else 8
	case "demo_tick", "demo_tick_r":
		n, is_number := strconv.parse_i64(unquoted(rest))
		if !is_number {
			usage(match, "%s <%s>", word, "ticks, minus for back" if word == "demo_tick_r" else "tick")
			return
		}
		from := i64(p.seek_to if p.seeking else demo_at(match))
		demo_seek(match, from + n if word == "demo_tick_r" else n)
	}
}

// Taken to tick `to`: on from here when it lies ahead, else from its start again, the
// world made anew from its first Map. The ticks between run in the frames that follow.
@(private = "file")
demo_seek :: proc(match: ^Match, to: i64) {
	p := &match.playback
	to := u32(clamp(to, 0, i64(p.player.header.ticks)))
	if to < demo_at(match) {
		demo.player_rewind(p.player)
		online.line_play(match.line, match.me)
		p.ticked = false
		if !demo_tick_ready(match) do return
	}
	p.seek_to = to
	p.seeking = p.seek_to > demo_at(match)
}

// A slice of the frame's time spent running the seek's ticks; it ends where it was
// taken to, or at the demo's end.
demo_seek_run :: proc(match: ^Match, sounds: ^sound.Sound) {
	p := &match.playback
	began := time.tick_now()
	for p.seeking && time.tick_since(began) < SEEK_BUDGET {
		if !demo_tick_ready(match) {
			p.seeking = false
			return
		}
		tick(match, match.config, sounds)
		if demo_at(match) >= p.seek_to do p.seeking = false
	}
}

// ---------------------------------------------------------------------------------
// Recording

// record [name]: the game joined, recorded from now until the round ends, into demos/.
record_ask :: proc(match: ^Match, name: string) {
	if match.mode != .Online {
		client_say(match, "record: join a game first")
		return
	}
	recording_stop(match)
	delete(match.record.name)
	match.record.name = strings.clone(unquoted(name))
	match.record.asked = true // begun once the frame's packets are in
}

// stop: the recording stopped, or the demo playing.
record_stop_asked :: proc(match: ^Match) {
	match.record.asked = false
	switch {
	case demo.recording(&match.recorder): recording_stop(match)
	case match.mode == .Demo:             match.request = Leave{}
	case:                                 client_say(match, "No demo is being recorded or played")
	}
}

// Each frame, after the line's packets: a demo begun as `record` asked, or by
// record_rounds once a round; stopped when the line is lost; the frame's packets marked
// as all in, before its ticks.
recording_follow :: proc(match: ^Match) {
	if match.mode != .Online do return
	r := &match.record
	n := match.line
	if !demo.recording(&match.recorder) && n.round != 0 && (r.asked || (match.config.demos.record_rounds && !r.round_recorded)) {
		recording_start(match, r.name if r.asked else "")
		r.asked = false
		r.round_recorded = true
	}
	if demo.recording(&match.recorder) && !online.line_live(n) do recording_stop(match)
	demo.recorder_frame(&match.recorder)
}

// After my tick, my part of it.
recording_tick :: proc(match: ^Match, view: u32, command: sim.Command) {
	if !demo.recording(&match.recorder) do return
	me := &match.game.world.soldiers[match.me]
	demo.recorder_tick(&match.recorder, view, command, match.input.cursor, me if me.active else nil)
}

recording_stop :: proc(match: ^Match) {
	r := &match.recorder
	if !demo.recording(r) do return
	path := strings.clone(r.path, context.temp_allocator)
	ticks := r.ticks
	demo.recorder_close(r)
	match.line.tap = nil
	client_say(match, "Demo saved: %s (%s)", path, demo.ticks_text(ticks))
}

// A demo of the round joined, from now: into demos/ as `name`, or as the date and the
// map with none.
@(private = "file")
recording_start :: proc(match: ^Match, name: string) {
	n := match.line
	map_name := utils.short_string_text(&n.map_name)
	path := demo.demo_path(name if name != "" else demo.default_name(map_name))
	header := demo.Header{date = time.to_unix_seconds(time.now()), slot = u8(n.slot)}
	utils.short_string_set(&header.name, match.config.player.name)
	header.map_name = n.map_name
	if !demo.recorder_open(&match.recorder, path, header) {
		hud_warn(match, "Could not write the demo %s", path)
		return
	}
	demo.recorder_join(&match.recorder, n)
	n.tap = recording_tap
	n.tap_user = match
	client_say(match, "Recording demo: %s", path)
}

// Every message the line brings, into the recording. A Map ends it: the round it was of
// is over, and record_rounds begins the next.
@(private = "file")
recording_tap :: proc(user: rawptr, data: []u8, kind: network.Msg_Kind) {
	match := cast(^Match)user
	#partial switch kind {
	case .Map:      recording_stop(match)
	case .Map_Part: // a map being fetched is no part of the game
	case:           demo.recorder_packet(&match.recorder, data)
	}
}
