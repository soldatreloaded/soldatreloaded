package online

// What the player is doing, shown on their Discord profile: "Playing Soldat Reloaded",
// the game's icon, and a line or two of where. Said to the Discord app running on this
// machine over its local pipe (Windows' \\.\pipe\discord-ipc-N, elsewhere a Unix socket
// of that name in the runtime directory: discord_windows.odin, discord_other.odin), as
// frames of JSON: a handshake with the game's application ID, then SET_ACTIVITY whenever
// what is shown changes. Nothing goes over the network from here, and nothing waits on
// Discord: with no app running the pipe isn't there, and it is looked for again every so
// often. The browser's Discord has no pipe, so it sees none of this. Discord clears what
// is shown when the pipe closes, as the game quits.
//
// The icon is the application's art asset named DISCORD_ICON, uploaded on Discord's
// Developer Portal under the application's Rich Presence, Art Assets.
//
// From the C client: net/discord.c.

import "core:encoding/endian"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:unicode/utf8"

import "../../../core/utils"

DISCORD_APP_ID :: "1555217040036339732"
DISCORD_ICON :: "logo"

@(private = "file")
RETRY_SECONDS :: 15 // with no app found, looked for again this often
@(private = "file")
SEND_GAP :: 5.0 // seconds between activities at least: Discord takes five in twenty
@(private = "file")
FRAME_HEADER :: 8 // opcode and length, each a little-endian u32
@(private = "file")
FRAME_MOST :: 2048 // a frame's JSON said, at most

@(private = "file")
Op :: enum u32 {
	Handshake,
	Frame,
	Close,
	Ping,
	Pong,
}

Discord_Text :: utils.Short_String(128) // a line shown

Discord_Activity :: struct {
	details: Discord_Text, // the first line, empty for none
	state:   Discord_Text, // the second, empty for none
	since:   i64, // the time it began, Unix seconds, for the "elapsed"; 0 for none
}

Discord :: struct {
	pipe:      Discord_Pipe, // closed while zero
	ready:     bool, // the handshake answered: activities are heard
	next_try:  f64, // when to look for the app again
	last_sent: f64, // when the last activity went, for Discord's rate limit
	want:      Discord_Activity, // what is to be shown
	dirty:     bool, // and not yet said
	incoming:  [8192]u8, // what has come back, a frame at a time
	in_len:    int,
	skipping:  int, // the rest of a frame too big to keep, thrown away as it comes
}

// What to show; said once it differs from what was, as soon as Discord will hear it.
discord_set :: proc(d: ^Discord, a: Discord_Activity) {
	if d.want == a do return
	d.want = a
	d.dirty = true
}

// Each frame: connecting, the replies, and what is to be said. `enabled` false closes
// the pipe, and with it what is shown.
discord_pump :: proc(d: ^Discord, now: f64, enabled: bool) {
	if !enabled {
		if pipe_is_open(&d.pipe) do disconnect(d)
		d.next_try = 0 // looked for at once when turned back on
		return
	}
	if !pipe_is_open(&d.pipe) {
		if now < d.next_try do return
		d.next_try = now + RETRY_SECONDS
		if !pipe_open(&d.pipe) do return
		if !send_frame(d, .Handshake, `{"v":1,"client_id":"` + DISCORD_APP_ID + `"}`) do return
		d.dirty = true
	}
	read_frames(d)
	if d.ready && d.dirty && now - d.last_sent >= SEND_GAP {
		if send_activity(d) {
			d.dirty = false
			d.last_sent = now
		}
	}
}

discord_close :: proc(d: ^Discord) {
	pipe_close(&d.pipe)
	d.ready = false
}

@(private = "file")
disconnect :: proc(d: ^Discord) {
	pipe_close(&d.pipe)
	d.ready = false
	d.in_len = 0
	d.skipping = 0
	d.dirty = true // what is wanted is said again to the next pipe
}

@(private = "file")
send_frame :: proc(d: ^Discord, op: Op, json: string) -> bool {
	frame: [FRAME_HEADER + FRAME_MOST]u8
	if len(json) > FRAME_MOST do return false
	endian.unchecked_put_u32le(frame[0:], u32(op))
	endian.unchecked_put_u32le(frame[4:], u32(len(json)))
	copy(frame[FRAME_HEADER:], json)
	if pipe_write(&d.pipe, frame[:FRAME_HEADER + len(json)]) do return true
	disconnect(d)
	return false
}

// `s` as a JSON string's contents onto `b`: quotes and controls escaped, and what isn't
// UTF-8 (a server's name in an old codepage) a '?', which Discord would refuse.
@(private = "file")
write_text :: proc(b: ^strings.Builder, s: string) {
	for i := 0; i < len(s); {
		r, width := utf8.decode_rune(s[i:])
		switch {
		case r == utf8.RUNE_ERROR && width <= 1:
			strings.write_byte(b, '?')
		case r == '"' || r == '\\':
			strings.write_byte(b, '\\')
			strings.write_byte(b, u8(r))
		case r < 0x20:
			fmt.sbprintf(b, "\\u%04x", r)
		case:
			strings.write_string(b, s[i:i + width])
		}
		i += max(width, 1)
	}
}

@(private = "file")
send_activity :: proc(d: ^Discord) -> bool {
	@(static) nonce: u32
	nonce += 1
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{"cmd":"SET_ACTIVITY","nonce":"%d","args":{"pid":%d,"activity":{`, nonce, process_id())
	// Discord refuses a line under two characters, so one so short goes unsaid
	lines := [?]struct {
		key:  string,
		text: string,
	}{{"details", utils.short_string_text(&d.want.details)}, {"state", utils.short_string_text(&d.want.state)}}
	for line in lines {
		if len(line.text) < 2 do continue
		fmt.sbprintf(&b, `"%s":"`, line.key)
		write_text(&b, line.text)
		strings.write_string(&b, `",`)
	}
	if d.want.since > 0 do fmt.sbprintf(&b, `"timestamps":{{"start":%d}},`, d.want.since)
	strings.write_string(&b, `"assets":{"large_image":"` + DISCORD_ICON + `","large_text":"Soldat Reloaded"}}}}`)
	return send_frame(d, .Frame, strings.to_string(b))
}

// A whole frame come back: the handshake's READY, an activity's answer, a ping, a close.
@(private = "file")
heard :: proc(d: ^Discord, op: Op, json: string) {
	#partial switch op {
	case .Frame:
		if !d.ready {
			d.ready = true // the handshake's answer: READY, the user's
			d.last_sent = -SEND_GAP
		} else if strings.contains(json, `"evt":"ERROR"`) {
			log.warnf("discord: %s", json)
		}
	case .Ping:
		send_frame(d, .Pong, json)
	case .Close: // the handshake refused, or the app closing
		log.warnf("discord: closed: %s", json)
		disconnect(d)
	}
}

@(private = "file")
read_frames :: proc(d: ^Discord) {
	for pipe_is_open(&d.pipe) {
		chunk: [2048]u8
		got := pipe_read(&d.pipe, chunk[:])
		if got < 0 {
			disconnect(d)
			return
		}
		if got == 0 do return
		rest := chunk[:got]
		for len(rest) > 0 && pipe_is_open(&d.pipe) {
			if d.skipping > 0 { // the rest of a frame too big to keep
				drop := min(len(rest), d.skipping)
				d.skipping -= drop
				rest = rest[drop:]
				continue
			}
			take := min(len(d.incoming) - d.in_len, len(rest))
			copy(d.incoming[d.in_len:], rest[:take])
			d.in_len += take
			rest = rest[take:]
			for d.in_len >= FRAME_HEADER && pipe_is_open(&d.pipe) {
				op := Op(endian.unchecked_get_u32le(d.incoming[0:]))
				size := int(endian.unchecked_get_u32le(d.incoming[4:]))
				if FRAME_HEADER + size > len(d.incoming) { // never kept: its header gone, the rest skipped
					d.skipping = FRAME_HEADER + size - d.in_len
					d.in_len = 0
					// still a READY or a close, if that is what it was, though unread
					if op == .Frame || op == .Close do heard(d, op, "")
					break
				}
				if d.in_len < FRAME_HEADER + size do break
				heard(d, op, string(d.incoming[FRAME_HEADER:][:size]))
				if !pipe_is_open(&d.pipe) do return
				d.in_len -= FRAME_HEADER + size
				copy(d.incoming[:], d.incoming[FRAME_HEADER + size:][:d.in_len])
			}
		}
	}
}
