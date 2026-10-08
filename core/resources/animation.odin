package resources

import "core:strconv"

import "../utils"

// The gostek's keyframe animations, one .poa file each in data/anims. The soldier's
// movement is driven by which animation plays and its frame number, so these are
// gameplay data, not only looks. Frame numbers are 1-based, as the original's tuning
// constants count them. Ported from Anims.pas.

MAX_ANIMATION_FRAMES :: 40
MAX_ANIMATION_POINTS :: 20

// The scale the .poa files are loaded at.
ANIMATION_SCALE :: 3.0

Animation_Id :: enum {
	Stand,
	Run,
	Run_Back,
	Jump,
	Jump_Side,
	Fall,
	Crouch,
	Crouch_Run,
	Reload,
	Throw,
	Recoil,
	Small_Recoil,
	Shotgun,
	Clip_Out,
	Clip_In,
	Slide_Back,
	Change,
	Throw_Weapon,
	Weapon_None,
	Punch,
	Barret,
	Roll,
	Roll_Back,
	Crouch_Run_Back,
	Cigar,
	Match,
	Smoke,
	Wipe,
	Groin,
	Piss,
	Mercy,
	Mercy2,
	Take_Off,
	Prone,
	Victory,
	Aim,
	Hands_Up_Aim,
	Prone_Move,
	Get_Up,
	Aim_Recoil,
	Hands_Up_Recoil,
	Melee,
	Own,
	Breakdown,
	Dab,
	Yeah,
}

// Where an animation's keyframes are, and how it plays: the ticks each frame is held
// for, and whether it starts over at the end or stays on its last frame.
Animation_Info :: struct {
	file:  string,
	speed: i32,
	loops: bool,
}

@(rodata)
ANIMATION_INFO := [Animation_Id]Animation_Info {
	.Stand           = {"stoi.poa", 3, true},
	.Run             = {"biega.poa", 1, true},
	.Run_Back        = {"biegatyl.poa", 1, true},
	.Jump            = {"skok.poa", 1, false},
	.Jump_Side       = {"skokwbok.poa", 1, false},
	.Fall            = {"spada.poa", 1, false},
	.Crouch          = {"kuca.poa", 1, false},
	.Crouch_Run      = {"kucaidzie.poa", 2, true},
	.Reload          = {"laduje.poa", 2, false},
	.Throw           = {"rzuca.poa", 1, false},
	.Recoil          = {"odrzut.poa", 1, false},
	.Small_Recoil    = {"odrzut2.poa", 1, false},
	.Shotgun         = {"shotgun.poa", 1, false},
	.Clip_Out        = {"clipout.poa", 3, false},
	.Clip_In         = {"clipin.poa", 3, false},
	.Slide_Back      = {"slideback.poa", 2, true},
	.Change          = {"change.poa", 1, false},
	.Throw_Weapon    = {"wyrzuca.poa", 1, false},
	.Weapon_None     = {"bezbroni.poa", 3, false},
	.Punch           = {"bije.poa", 1, false},
	.Barret          = {"barret.poa", 9, false},
	.Roll            = {"skokdolobrot.poa", 1, false},
	.Roll_Back       = {"skokdolobrottyl.poa", 1, false},
	.Crouch_Run_Back = {"kucaidzietyl.poa", 2, true},
	.Cigar           = {"cigar.poa", 3, false},
	.Match           = {"match.poa", 3, false},
	.Smoke           = {"smoke.poa", 4, false},
	.Wipe            = {"wipe.poa", 4, false},
	.Groin           = {"krocze.poa", 2, false},
	.Piss            = {"szcza.poa", 8, false},
	.Mercy           = {"samo.poa", 3, false},
	.Mercy2          = {"samo2.poa", 3, false},
	.Take_Off        = {"takeoff.poa", 2, false},
	.Prone           = {"lezy.poa", 1, false},
	.Victory         = {"cieszy.poa", 3, false},
	.Aim             = {"celuje.poa", 2, false},
	.Hands_Up_Aim    = {"gora.poa", 2, false},
	.Prone_Move      = {"lezyidzie.poa", 2, true},
	.Get_Up          = {"wstaje.poa", 1, false},
	.Aim_Recoil      = {"celujeodrzut.poa", 1, false},
	.Hands_Up_Recoil = {"goraodrzut.poa", 1, false},
	.Melee           = {"kolba.poa", 1, false},
	.Own             = {"rucha.poa", 3, false},
	// the community's cheers, past the original's
	.Breakdown       = {"cieszy_breakdown.poa", 3, false},
	.Dab             = {"cieszy_dab.poa", 3, false},
	.Yeah            = {"cieszy_yeah.poa", 3, false},
}

// Where each of the skeleton's points is in one frame. Point n of the file is index n-1.
Animation_Frame :: [MAX_ANIMATION_POINTS]utils.Vec2

// One .poa file.
Animation :: struct {
	frames:      [MAX_ANIMATION_FRAMES]Animation_Frame,
	frame_count: i32,
	speed:       i32,
	loops:       bool,
}

// Every animation. Large (about 280 KB): load it once and share it.
Animations :: [Animation_Id]Animation

// A .poa file's text: for each point its number, then its x, y (depth, unused in 2D)
// and z, a line each; NEXTFRAME between frames; ENDFILE at the end.
animation_parse :: proc(text: string, info: Animation_Info) -> (animation: Animation) {
	animation.frame_count = 1
	animation.speed = info.speed
	animation.loops = info.loops

	text := text
	for tag in utils.next_line(&text) {
		if tag == "ENDFILE" {
			break
		}
		if tag == "NEXTFRAME" {
			if animation.frame_count == MAX_ANIMATION_FRAMES {
				break
			}
			animation.frame_count += 1
			continue
		}
		x := next_coordinate(&text)
		_ = next_coordinate(&text) // y: depth
		z := next_coordinate(&text)

		point, _ := strconv.parse_int(tag)
		if point >= 1 && point <= MAX_ANIMATION_POINTS {
			frame := &animation.frames[animation.frame_count - 1]
			frame[point - 1] = {-ANIMATION_SCALE * x / 1.1, -ANIMATION_SCALE * z}
		}
	}
	return
}

// Every animation, from <data_dir>/anims. False, with the file that failed logged, if
// one can't be read. Free with `free`.
animations_load :: proc(data_dir: string, allocator := context.allocator) -> (animations: ^Animations, ok: bool) {
	animations = new(Animations, allocator)
	for info, id in ANIMATION_INFO {
		text, read := utils.read_file(utils.temp_path(data_dir, "anims", info.file), context.temp_allocator)
		if !read {
			free(animations, allocator)
			return nil, false
		}
		animations[id] = animation_parse(string(text), info)
	}
	return animations, true
}

// The keyframe at an animation's 1-based frame number.
animation_frame :: proc(animation: ^Animation, frame: i32) -> ^Animation_Frame {
	return &animation.frames[clamp(frame, 1, MAX_ANIMATION_FRAMES) - 1]
}

// ---------------------------------------------------------------------------------
// Playing an animation: a soldier's legs and body each have one of these, simulated
// and sent over the network.

Animation_State :: struct {
	id:    Animation_Id,
	frame: i32, // 1-based
	count: i32, // ticks into the frame
	speed: i32,
}

// One tick of an animation: on to the next frame once this one has been held its time.
animation_advance :: proc(animations: ^Animations, state: ^Animation_State) {
	state.count += 1
	if state.count != state.speed {
		return
	}
	state.count = 0
	state.frame += 1

	animation := &animations[state.id]
	if state.frame > animation.frame_count {
		state.frame = 1 if animation.loops else animation.frame_count
	}
}

// Starts an animation at `frame`, whatever was playing.
animation_start :: proc(animations: ^Animations, state: ^Animation_State, id: Animation_Id, frame: i32 = 1) {
	state^ = {id = id, frame = frame, speed = animations[id].speed}
}

// Starts an animation unless it is already playing.
animation_switch :: proc(animations: ^Animations, state: ^Animation_State, id: Animation_Id, frame: i32 = 1) {
	if state.id != id {
		animation_start(animations, state, id, frame)
	}
}

// A coordinate line of a .poa or .po file. Parsed as f64 and narrowed, so the points
// round exactly as they do in the C game.
next_coordinate :: proc(text: ^string) -> f32 {
	line, _ := utils.next_line(text)
	number, _ := strconv.parse_f64(line)
	return f32(number)
}
