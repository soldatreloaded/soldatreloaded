package demo

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import sim "../../../core/game"
import network "../../../core/network"
import "../../../core/utils"

// A demo read back, record by record: its packets for the line to hear, its frame marks
// for what they began to be taken, its ticks for mine to be played.

// A tick of mine, as recorded.
Tick :: struct {
	using head: Tick_Head,
	self:       sim.Soldier, // its owned half, loadout, look, typing, bink and life, as the tick left it
}

Tick_Head :: struct {
	view:    u32,         // the tick on show, as the view clock had it
	command: sim.Command, // my command
	cursor:  utils.Vec2,  // my cursor, in the view's units, for the camera
	present: bool,        // my soldier was in the game: `self` holds it
}

// The next record: a packet's bytes (good until the player closes), a frame mark, or a
// tick. Nil at the end of the file, or at a record cut short or that can't be read.
Next :: union {
	[]u8,
	Frame,
	^Tick,
}

Frame :: struct {}

Player :: struct {
	data:   []u8, // the whole file; nil while not playing
	at:     int,
	header: Header, // its ticks counted, if the file didn't say
	tick:   u32,    // ticks played
	name:   string, // the file's, without its directory or extension
	next:   Tick,   // the tick last read
}

// The demo at `path`, read whole. False, with why, if it can't be played.
player_open :: proc(p: ^Player, path: string) -> (error: string, ok: bool) {
	player_close(p)
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil do return fmt.tprintf("There is no demo at %s.", path), false
	header, read := header_read(data)
	if read != .Ok {
		delete(data)
		if read == .Not_Demo do return fmt.tprintf("%s is not a demo.", path), false
		return fmt.tprintf("%s was recorded by another version of the game.", path), false
	}
	p^ = {data = data, at = HEADER_SIZE, header = header, name = strings.clone(filepath.stem(path))}
	if header.ticks == 0 { // cut short: counted
		for at := HEADER_SIZE; at + 3 <= len(data); {
			n := int(get_u16(data[at + 1:]))
			if at + 3 + n > len(data) do break
			if Record_Kind(data[at]) == .Tick do p.header.ticks += 1
			at += 3 + n
		}
	}
	return "", true
}

player_playing :: proc(p: ^Player) -> bool {
	return p.data != nil
}

player_next :: proc(p: ^Player) -> Next {
	for p.data != nil && p.at + 3 <= len(p.data) {
		kind := Record_Kind(p.data[p.at])
		n := int(get_u16(p.data[p.at + 1:]))
		if p.at + 3 + n > len(p.data) do break
		body := p.data[p.at + 3:][:n]
		p.at += 3 + n
		#partial switch kind {
		case .Packet:
			return body
		case .Frame:
			return Frame{}
		case .Tick:
			b := network.buffer_reader(body)
			p.next = {}
			tick_serialize(&b, &p.next)
			if !network.buffer_done(&b) do return nil
			p.tick += 1
			return &p.next
		}
		// a kind a later version wrote: passed over
	}
	return nil
}

// Back to the start, for a seek backward: the world is made again from its first Map.
player_rewind :: proc(p: ^Player) {
	p.at = HEADER_SIZE
	p.tick = 0
}

player_close :: proc(p: ^Player) {
	delete(p.data)
	delete(p.name)
	p^ = {}
}

// ---------------------------------------------------------------------------------
// A tick on the wire, both ways

@(private = "file")
TICK_FIELDS: network.Field_Table

@(init, private = "file")
tick_fields_init :: proc "contextless" () {
	context = runtime.default_context()
	TICK_FIELDS = network.fields_of(Tick_Head, "")
}

@(private = "package")
tick_serialize :: proc(b: ^network.Buffer, t: ^Tick) {
	network.fields_serialize(b, TICK_FIELDS, &t.head, nil)
	if !t.present do return
	s := &t.self
	network.net_u8(b, &s.vitals.life)
	network.fields_serialize(b, network.SOLDIER_OWNED_FIELDS, s, nil)
	network.fields_serialize(b, network.SOLDIER_LOADOUT_FIELDS, s, nil)
	network.fields_serialize(b, network.LOOK_FIELDS, &s.player.look, nil)
	network.net_bool(b, &s.player.typing)
	network.net_u16(b, &s.aim.hit_spray)
}
