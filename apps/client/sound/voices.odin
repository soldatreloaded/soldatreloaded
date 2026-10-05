package sound

import "core:math"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"

MAX_VOICES :: 256 // the original's sources: 128 free and four per soldier
MAX_DISTANCE :: 750.0 // a sound this far from the listener is silent (SOUND_MAXDIST)
METER_LENGTH :: 2000.0 // world units to OpenAL's meters, for the pan (SOUND_METERLENGTH)
LOOP_CHUNK :: 4096 // frames a loop's stream is fed at a time; it holds two
LOOP_HELD :: 8 // ticks a loop plays on unrefreshed, so a late refresh doesn't gap it

// The original's looping sources (Sound.pas: SFX_ROCKETZ, SFX_CHAINSAW_R), and the wind,
// kept up every tick as they are.
@(rodata)
LOOPS := [?]string{"rocketz.wav", "chainsaw-r.wav", "sfx_wind.wav"}

// A wav, decoded, and made a raylib sound; no frames when it couldn't be read.
Sample :: struct {
	name:   string,
	sound:  rl.Sound,
	frames: [][2]f32, // the bank's: a loop is fed from them
	rate:   int,
}

// A voice: a sample playing, through an alias of its own, or, a loop, a stream fed
// from its frames.
Voice :: struct {
	sample:   Sample, // no name: free
	alias:    rl.Sound,
	alias_of: rawptr, // the sample buffer the alias shares, kept for the next play of it
	stream:   rl.AudioStream,
	loop:     bool,
	cursor:   int, // a loop's next frame
	held:     int, // a loop's ticks left unrefreshed
	paused:   bool,
	started:  u32,
}

// A voice a soldier keeps for one purpose; it is theirs while the play it started is on.
Reserved :: struct {
	voice:   int, // index + 1 into the voices; 0 for none
	started: u32,
}

// The layout of Sprites.pas.
Soldier_Voice :: enum {
	Reload,
	Jets,
	Gattling,
	Gattling2,
}

// ---------------------------------------------------------------------------------
// Samples

// A sample by file name in sfx/, read and made a raylib sound the first time it is
// asked for. False if it couldn't be read, which the bank reports once.
sample_get :: proc(s: ^Sound, name: string) -> (Sample, bool) {
	if sample, known := s.samples[name]; known do return sample, len(sample.frames) > 0
	decoded := res.sounds_get(&s.bank, name)
	sample := Sample{name = strings.clone(name), frames = decoded.frames, rate = decoded.sample_rate}
	if len(sample.frames) > 0 {
		sample.sound = rl.LoadSoundFromWave({
			frameCount = u32(len(sample.frames)),
			sampleRate = u32(sample.rate),
			sampleSize = 32,
			channels   = 2,
			data       = raw_data(sample.frames),
		})
	}
	s.samples[sample.name] = sample
	return sample, len(sample.frames) > 0
}

@(private = "file")
is_loop :: proc(name: string) -> bool {
	for loop in LOOPS {
		if name == loop do return true
	}
	return false
}

// ---------------------------------------------------------------------------------
// Placing

// Gain and pan for a sound at `at`, and whether it is within earshot. The pan is what
// OpenAL gave the original, the source at (dx, dy, -1000) meters heard along x: -1 left,
// 1 right, raylib's. Ringing ears fade everything but the ringing itself (`muffled`
// false), as the original's do. A distant sample fades the other way: loudest at the
// edge of the range, and on past it.
place :: proc(s: ^Sound, at: utils.Vec2, distant, muffled: bool) -> (gain, pan: f32, heard: bool) {
	d := at - s.listener
	dist := utils.length(d) / MAX_DISTANCE
	if distant do dist = dist - 1 if dist > 1 else 1 - 2 * dist
	if muffled && s.ringing > 0 do dist += (1 - dist) * math.sqrt(f32(s.ringing) / 280)
	if dist > 1 do return 0, 0, false
	gain = clamp(s.volume * (1 - dist), 0, 1)
	m := d / METER_LENGTH
	z := f32(-1000.0 / METER_LENGTH)
	pan = m.x / math.sqrt(m.x * m.x + m.y * m.y + z * z)
	return gain, pan, true
}

// ---------------------------------------------------------------------------------
// Playing

// Sound.pas FPlaySound: a one-shot at `at`. Past half the range a shot or blast also
// plays its distant sample, which has its own fade.
play_at :: proc(s: ^Sound, name: string, at: utils.Vec2, distant := false) {
	if !s.ready || name == "" do return
	if s.battle && !distant && utils.length(at - s.listener) > MAX_DISTANCE / 2 {
		if far := distant_sample(s, name); far != "" do play_at(s, far, at, true)
	}
	gain, pan, heard := place(s, at, distant, name != "hum.wav")
	if !heard do return
	sample, ok := sample_get(s, name)
	if !ok do return
	voice_start(s, voice_take(s), sample, gain, pan)
}

// A soldier's reserved voice, or the wind's: refreshed while it plays, started with
// `name` when it isn't. Out of earshot a playing one goes silent and plays on, as the
// original's source does, and none is started.
reserved_play :: proc(s: ^Sound, r: ^Reserved, name: string, at: utils.Vec2) {
	if !s.ready || name == "" do return
	gain, pan, heard := place(s, at, false, true)
	sample, ok := sample_get(s, name)
	if !ok {
		reserved_stop(s, r)
		return
	}
	playing := reserved_playing(s, r) && !s.voices[r.voice - 1].paused
	if !playing && !heard do return
	if !playing {
		v := voice_take(s)
		voice_start(s, v, sample, gain, pan)
		r^ = {voice = v + 1, started = s.voices[v].started}
	}
	voice := &s.voices[r.voice - 1]
	voice_place(voice, gain, pan)
	voice.held = LOOP_HELD
}

reserved_stop :: proc(s: ^Sound, r: ^Reserved) {
	if reserved_playing(s, r) do voice_end(&s.voices[r.voice - 1])
	r^ = {}
}

// SetSoundPaused: pauses only a playing voice, resumes only a paused one.
reserved_pause :: proc(s: ^Sound, r: ^Reserved, paused: bool) {
	if !reserved_playing(s, r) do return
	voice := &s.voices[r.voice - 1]
	if voice.paused == paused do return
	voice.paused = paused
	switch {
	case voice.loop && paused: rl.PauseAudioStream(voice.stream)
	case voice.loop:           rl.ResumeAudioStream(voice.stream)
	case paused:               rl.PauseSound(voice.alias)
	case:                      rl.ResumeSound(voice.alias)
	}
}

@(private = "file")
reserved_playing :: proc(s: ^Sound, r: ^Reserved) -> bool {
	if r.voice == 0 do return false
	voice := &s.voices[r.voice - 1]
	return voice.started == r.started && voice_playing(voice)
}

// ---------------------------------------------------------------------------------
// Voices

// A free voice, or the oldest playing one that isn't a loop: a loop plays on from one
// start, so it is always the oldest, and is taken only when all else is newer.
@(private = "file")
voice_take :: proc(s: ^Sound) -> int {
	oldest, oldest_loop := -1, -1
	for &voice, v in s.voices {
		if !voice_playing(&voice) do return v
		if voice.loop {
			if oldest_loop < 0 || voice.started < s.voices[oldest_loop].started do oldest_loop = v
		} else if oldest < 0 || voice.started < s.voices[oldest].started {
			oldest = v
		}
	}
	return oldest if oldest >= 0 else oldest_loop
}

@(private = "file")
voice_start :: proc(s: ^Sound, v: int, sample: Sample, gain, pan: f32) {
	voice := &s.voices[v]
	voice_end(voice)
	s.plays += 1
	voice.sample = sample
	voice.started = s.plays
	voice.loop = is_loop(sample.name)
	if voice.loop {
		voice.stream = rl.LoadAudioStream(u32(sample.rate), 32, 2)
		voice.cursor = 0
		voice.held = LOOP_HELD
		loop_feed(voice)
		voice_place(voice, gain, pan)
		rl.PlayAudioStream(voice.stream)
		return
	}
	if voice.alias_of != sample.sound.buffer {
		if voice.alias_of != nil do rl.UnloadSoundAlias(voice.alias)
		voice.alias = rl.LoadSoundAlias(sample.sound)
		voice.alias_of = sample.sound.buffer
	}
	voice_place(voice, gain, pan)
	rl.PlaySound(voice.alias)
}

@(private = "file")
voice_place :: proc(voice: ^Voice, gain, pan: f32) {
	if voice.loop {
		rl.SetAudioStreamVolume(voice.stream, gain)
		rl.SetAudioStreamPan(voice.stream, pan)
	} else {
		rl.SetSoundVolume(voice.alias, gain)
		rl.SetSoundPan(voice.alias, pan)
	}
}

@(private = "file")
voice_playing :: proc(voice: ^Voice) -> bool {
	if voice.sample.name == "" do return false
	if voice.loop do return true
	return voice.paused || rl.IsSoundPlaying(voice.alias)
}

// The voice stopped and free; a one-shot's alias is kept for its sample's next play.
voice_end :: proc(voice: ^Voice) {
	if voice.sample.name == "" do return
	if voice.loop {
		rl.StopAudioStream(voice.stream)
		rl.UnloadAudioStream(voice.stream)
		voice.stream = {}
	} else {
		rl.StopSound(voice.alias)
	}
	voice.sample = {}
	voice.loop = false
	voice.paused = false
}

voice_unload :: proc(voice: ^Voice) {
	voice_end(voice)
	if voice.alias_of != nil do rl.UnloadSoundAlias(voice.alias)
	voice^ = {}
}

// A loop's stream given the sample's next frames for each part of it that has played,
// round and round with no gap.
loop_feed :: proc(voice: ^Voice) {
	frames := voice.sample.frames
	for rl.IsAudioStreamProcessed(voice.stream) {
		chunk: [LOOP_CHUNK][2]f32
		for &frame in chunk {
			frame = frames[voice.cursor]
			voice.cursor = (voice.cursor + 1) % len(frames)
		}
		rl.UpdateAudioStream(voice.stream, &chunk, LOOP_CHUNK)
	}
}

// Every tick: a loop nobody has refreshed for LOOP_HELD ticks is over.
loops_age :: proc(s: ^Sound) {
	for &voice in s.voices {
		if !voice.loop do continue
		voice.held -= 1
		if voice.held <= 0 do voice_end(&voice)
	}
}
