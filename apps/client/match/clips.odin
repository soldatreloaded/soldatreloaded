package match

import "core:strings"
import "core:time"

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"
import "../demo"

// Clips: the clip key saves the last demos.clip_seconds of the game as a demo. A demo
// can't begin at any byte of another (it begins with the round as the client had it,
// recorder_join), so a few recordings are kept in memory at once, a new one begun every
// clip_step and each let go once it is a step older than the clip: the clip is the one
// begun nearest to clip_seconds ago, so it runs from that long to a step longer. Online
// only, within a round: a new round lets them all go, as it ends a demo.

CLIP_SEGMENTS :: 8 // recordings kept at most: clip_step keeps them fewer

Clips :: struct {
	segments: [CLIP_SEGMENTS]Clip_Segment,
	round:    u16, // the line's round they are of
	ticks:    u32, // my ticks recorded, to time them by
}

Clip_Segment :: struct {
	recorder: demo.Recorder,
	began:    u32, // Clips.ticks as it began
}

// The ticks between one recording's start and the next: five seconds, but longer for a
// long clip, so no more than CLIP_SEGMENTS are kept.
@(private = "file")
clip_step :: proc(seconds: i32) -> u32 {
	return u32(max(5, seconds / (CLIP_SEGMENTS - 2))) * sim.TICK_RATE
}

@(private = "file")
clip_seconds :: proc(match: ^Match) -> i32 {
	s := match.config.demos.clip_seconds
	return 0 if s <= 0 else clamp(s, 10, res.CLIP_SECONDS_MAX)
}

// Each frame, after the line's packets, before their frame mark: the old recordings let
// go, a new one begun when a step has gone by, and the frame marked in each.
clips_follow :: proc(match: ^Match) {
	c := &match.clips
	n := match.line
	seconds := clip_seconds(match)
	if seconds == 0 || n.round == 0 || n.round != c.round {
		clips_drop(match)
		c.round = n.round
		if seconds == 0 || n.round == 0 do return
	}
	step := clip_step(seconds)
	keep := u32(seconds) * sim.TICK_RATE + step
	newest: Maybe(u32)
	for &s in c.segments {
		if !demo.recording(&s.recorder) do continue
		if c.ticks - s.began > keep {
			demo.recorder_close(&s.recorder)
			continue
		}
		newest = max(newest.? or_else 0, s.began)
	}
	if began, any := newest.?; !any || c.ticks - began >= step {
		slot := clip_free_slot(c)
		header := demo.Header{date = time.to_unix_seconds(time.now()), slot = u8(n.slot), map_name = n.map_name}
		utils.short_string_set(&header.name, match.config.player.name)
		demo.recorder_open_memory(&slot.recorder, header)
		demo.recorder_join(&slot.recorder, n)
		slot.began = c.ticks
	}
	for &s in c.segments do demo.recorder_frame(&s.recorder)
}

// A slot to begin a recording in: a free one, or the oldest's.
@(private = "file")
clip_free_slot :: proc(c: ^Clips) -> ^Clip_Segment {
	oldest: ^Clip_Segment
	for &s in c.segments {
		if !demo.recording(&s.recorder) do return &s
		if oldest == nil || s.began < oldest.began do oldest = &s
	}
	demo.recorder_close(&oldest.recorder)
	return oldest
}

// A message the line brought, into each recording.
clips_packet :: proc(match: ^Match, data: []u8) {
	for &s in match.clips.segments do demo.recorder_packet(&s.recorder, data)
}

// After my tick, my part of it, into each.
clips_tick :: proc(match: ^Match, view: u32, command: sim.Command) {
	me := &match.game.world.soldiers[match.me]
	for &s in match.clips.segments do demo.recorder_tick(&s.recorder, view, command, match.input.cursor, me if me.active else nil)
	match.clips.ticks += 1
}

// All let go: the round over, the line lost, the match ended.
clips_drop :: proc(match: ^Match) {
	for &s in match.clips.segments do demo.recorder_close(&s.recorder)
}

// clip: the last clip_seconds saved into demos/, as "clip_" and the date and the map.
clip_save :: proc(match: ^Match) {
	seconds := clip_seconds(match)
	if match.mode != .Online {
		client_say(match, "clip: join a game first")
		return
	}
	if seconds == 0 {
		client_say(match, "clip: clips are off (Demos, Clip length)")
		return
	}
	c := &match.clips
	want := u32(seconds) * sim.TICK_RATE
	// the youngest begun at least the clip's length ago; else, early in the round, the oldest
	picked: ^Clip_Segment
	for &s in c.segments {
		if !demo.recording(&s.recorder) do continue
		age, best := c.ticks - s.began, c.ticks - (picked.began if picked != nil else c.ticks)
		switch {
		case picked == nil:            picked = &s
		case age >= want && best < want: picked = &s // long enough, where the one picked isn't
		case age >= want:              if age < best do picked = &s // both long enough: the nearer the length
		case best < want:              if age > best do picked = &s // neither: the longer
		}
	}
	if picked == nil || picked.recorder.ticks == 0 {
		client_say(match, "clip: nothing to clip yet")
		return
	}
	name := strings.concatenate({"clip_", demo.default_name(utils.short_string_text(&match.line.map_name))}, context.temp_allocator)
	path := demo.demo_path(name)
	if !demo.recorder_save(&picked.recorder, path) {
		hud_warn(match, "Could not write the clip %s", path)
		return
	}
	client_say(match, "Clip saved: %s (%s)", path, demo.ticks_text(picked.recorder.ticks))
}
