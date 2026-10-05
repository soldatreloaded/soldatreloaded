package resources

import "core:log"
import "core:mem"
import "core:strings"

import "../utils"

// The game's sounds: .wav files in a mod's sfx/, decoded to stereo float frames at the
// rate they were recorded at. Converting them to the audio device's rate, placing and
// mixing them is the client's. Sounds are loaded the first time they are asked for.

// A sound decoded: each frame a left and a right sample, -1 to 1.
Sound :: struct {
	frames:      [][2]f32,
	sample_rate: int,
}

// Every sound asked for so far, by file name; a sound that couldn't be loaded is kept
// too, empty, so it is reported once.
Sounds :: struct {
	mod:       Mod,
	by_name:   map[string]Sound,
	allocator: mem.Allocator,
}

Wav_Error :: enum {
	None,
	Not_A_Wav,
	No_Format,
	No_Data,
	Unsupported_Format, // 8- or 16-bit PCM and Microsoft ADPCM, mono or stereo, are read
}

// ---------------------------------------------------------------------------------
// The file, as it lies on disk.

@(private = "file")
Riff_Header :: struct #packed {
	riff: [4]u8, // "RIFF"
	size: u32le,
	wave: [4]u8, // "WAVE"
}

@(private = "file")
Chunk_Header :: struct #packed {
	id:   [4]u8,
	size: u32le,
}

@(private = "file")
Wav_Encoding :: enum u16le {
	PCM      = 1,
	MS_ADPCM  = 2,
}

@(private = "file")
Wav_Format :: struct #packed {
	encoding:        Wav_Encoding,
	channels:        u16le,
	sample_rate:     u32le,
	byte_rate:       u32le,
	block_align:     u16le,
	bits_per_sample: u16le,
}

// What follows Wav_Format in an ADPCM file's format chunk, before its coefficients.
@(private = "file")
Adpcm_Format :: struct #packed {
	extra_size:        u16le,
	samples_per_block: u16le,
	coefficient_count: u16le,
}

// ---------------------------------------------------------------------------------
// Decoding

// A .wav file's bytes.
sound_decode :: proc(data: []byte, allocator := context.allocator) -> (sound: Sound, err: Wav_Error) {
	r := utils.Reader{data = data}
	header := utils.read(&r, Riff_Header)
	if string(header.riff[:]) != "RIFF" || string(header.wave[:]) != "WAVE" {
		return {}, .Not_A_Wav
	}

	format_chunk: []byte
	frame_count: Maybe(int) // the "fact" chunk's: how many of the frames are the sound's
	for r.position + size_of(Chunk_Header) <= len(data) {
		chunk := utils.read(&r, Chunk_Header)
		body := data[r.position:][:min(int(chunk.size), len(data) - r.position)]
		switch string(chunk.id[:]) {
		case "fmt ":
			format_chunk = body
		case "fact":
			fact := utils.Reader{data = body}
			frame_count = int(utils.read(&fact, u32le))
		case "data":
			if format_chunk == nil {
				return {}, .No_Format
			}
			sound = decode_samples(body, format_chunk, allocator) or_return
			// A compressed sound's last block is padded out past its end.
			if count, counted := frame_count.?; counted && count < len(sound.frames) {
				sound.frames = sound.frames[:count]
			}
			return sound, nil
		}
		utils.skip(&r, int(chunk.size) + int(chunk.size % 2)) // chunks are padded to even sizes
	}
	return {}, .No_Data
}

@(private = "file")
decode_samples :: proc(data, format_chunk: []byte, allocator := context.allocator) -> (sound: Sound, err: Wav_Error) {
	r := utils.Reader{data = format_chunk}
	format := utils.read(&r, Wav_Format)
	if format.channels != 1 && format.channels != 2 {
		return {}, .Unsupported_Format
	}
	sound.sample_rate = int(format.sample_rate)

	#partial switch format.encoding {
	case .PCM:
		switch format.bits_per_sample {
		case 8:  sound.frames = decode_pcm(data, int(format.channels), u8, allocator)
		case 16: sound.frames = decode_pcm(data, int(format.channels), i16le, allocator)
		case:    return {}, .Unsupported_Format
		}
	case .MS_ADPCM:
		sound.frames = decode_adpcm(data, &r, format, allocator) or_return
	case:
		return {}, .Unsupported_Format
	}
	return sound, nil
}

@(private = "file")
decode_pcm :: proc(data: []byte, channels: int, $Sample: typeid, allocator: mem.Allocator) -> [][2]f32 {
	frames := make([][2]f32, len(data) / (channels * size_of(Sample)), allocator)
	r := utils.Reader{data = data}
	for &frame in frames {
		for channel in 0 ..< channels {
			frame[channel] = pcm_sample(utils.read(&r, Sample))
		}
		if channels == 1 {
			frame[1] = frame[0]
		}
	}
	return frames
}

// 8-bit samples are unsigned around 128; 16-bit ones signed.
@(private = "file")
pcm_sample :: proc{pcm_sample_8, pcm_sample_16}

@(private = "file")
pcm_sample_8 :: proc(sample: u8) -> f32 {
	return f32(sample) / 128 - 1
}

@(private = "file")
pcm_sample_16 :: proc(sample: i16le) -> f32 {
	return f32(sample) / 32768
}

// Microsoft's ADPCM: blocks of 4-bit steps, each block starting afresh from a header
// per channel. `r` is the format chunk, read up to the ADPCM part.
@(private = "file")
decode_adpcm :: proc(data: []byte, r: ^utils.Reader, format: Wav_Format, allocator: mem.Allocator) -> (frames: [][2]f32, err: Wav_Error) {
	ADAPTATION := [16]i32{230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230}

	Channel_State :: struct {
		coefficients:     [2]i32,
		delta:            i32,
		sample1, sample2: i32, // the last two samples, newest first
	}

	adpcm := utils.read(r, Adpcm_Format)
	coefficients := utils.read_slice(r, [2]i16le, int(adpcm.coefficient_count), context.temp_allocator)
	channels := int(format.channels)
	block_size := int(format.block_align)
	samples_per_block := int(adpcm.samples_per_block)
	header_size := 7 * channels
	if block_size <= header_size || samples_per_block < 2 || len(coefficients) == 0 {
		return nil, .Unsupported_Format
	}

	decoded := make([dynamic][2]f32, 0, (len(data) / block_size + 1) * samples_per_block, allocator)
	for start := 0; start + header_size <= len(data); start += block_size {
		block := utils.Reader{data = data[start:][:min(block_size, len(data) - start)]}

		// Each channel's predictor, then its delta, then its last two samples.
		states: [2]Channel_State
		for c in 0 ..< channels {
			predictor := min(int(utils.read(&block, u8)), len(coefficients) - 1)
			states[c].coefficients = {i32(coefficients[predictor][0]), i32(coefficients[predictor][1])}
		}
		for c in 0 ..< channels do states[c].delta = i32(utils.read(&block, i16le))
		for c in 0 ..< channels do states[c].sample1 = i32(utils.read(&block, i16le))
		for c in 0 ..< channels do states[c].sample2 = i32(utils.read(&block, i16le))

		// The header's samples are the block's first two frames, the older first.
		append(&decoded, adpcm_frame(states, channels, 2), adpcm_frame(states, channels, 1))

		// Then a nibble a sample, the high one first, the channels taking turns.
		frame: [2]f32
		channel := 0
		for block.position < len(block.data) {
			byte := utils.read(&block, u8)
			for nibble in ([2]u8{byte >> 4, byte & 0x0f}) {
				s := &states[channel]
				step := i32(nibble) - 16 if nibble >= 8 else i32(nibble)
				predicted := (s.sample1 * s.coefficients[0] + s.sample2 * s.coefficients[1]) >> 8
				sample := clamp(predicted + step * s.delta, -32768, 32767)
				s.sample2, s.sample1 = s.sample1, sample
				s.delta = max((ADAPTATION[nibble] * s.delta) >> 8, 16)

				frame[channel] = f32(sample) / 32768
				channel += 1
				if channel == channels {
					if channels == 1 {
						frame[1] = frame[0]
					}
					append(&decoded, frame)
					channel = 0
				}
			}
		}
	}
	return decoded[:], nil
}

// The frame of a block header's first (1) or second (2) remembered sample.
@(private = "file")
adpcm_frame :: proc(states: [2]$T, channels, which: int) -> (frame: [2]f32) {
	for c in 0 ..< channels {
		frame[c] = f32(states[c].sample1 if which == 1 else states[c].sample2) / 32768
	}
	if channels == 1 {
		frame[1] = frame[0]
	}
	return
}

// ---------------------------------------------------------------------------------
// Loading

// A .wav file. False, with the reason logged, if it can't be read or decoded.
sound_load :: proc(path: string, allocator := context.allocator) -> (sound: Sound, ok: bool) {
	data := utils.read_file(path, context.temp_allocator) or_return
	err: Wav_Error
	sound, err = sound_decode(data, allocator)
	if err != nil {
		log.errorf("cannot decode the sound %s: %v", path, err)
		return {}, false
	}
	return sound, true
}

sound_destroy :: proc(sound: ^Sound, allocator := context.allocator) {
	delete(sound.frames, allocator)
	sound^ = {}
}

sounds_make :: proc(mod: Mod, allocator := context.allocator) -> Sounds {
	return {mod = mod, by_name = make(map[string]Sound, allocator), allocator = allocator}
}

// A sound by its file name in sfx/ ("shotgun.wav"), loaded the first time it is asked
// for. Empty, with no frames, if it can't be loaded.
sounds_get :: proc(sounds: ^Sounds, name: string) -> ^Sound {
	if name not_in sounds.by_name {
		sound, _ := sound_load(mod_file(sounds.mod, utils.temp_path("sfx", name)), sounds.allocator)
		sounds.by_name[strings.clone(name, sounds.allocator)] = sound
	}
	return &sounds.by_name[name]
}

sounds_destroy :: proc(sounds: ^Sounds) {
	for name, &sound in sounds.by_name {
		delete(name, sounds.allocator)
		sound_destroy(&sound, sounds.allocator)
	}
	delete(sounds.by_name)
	sounds^ = {}
}
