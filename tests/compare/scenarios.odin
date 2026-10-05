package compare

import "../../core/game"
import res "../../core/resources"

// What is played: two soldiers a gap apart, alpha's soldier 0 on the left, each aiming
// at the other's chest, pressing what `press` says on each tick (counted from 0). Ordered
// roughly as the port goes: standing and moving first, then fighting.
Scenario :: struct {
	name:     string,
	map_name: string,
	gap:      f32,
	weapons:  [2]res.Weapon,
	ticks:    int,
	press:    proc(tick: int) -> [2]game.Buttons,
	collide:  bool, // bullets and blasts knock dropped guns and kits about
	setup:    Setup,
}

// What else a scenario sets up, the same in both games: mirrors Setup in reference.c.
Setup :: struct {
	placed:  b32, // the soldiers at `at`, not soldier 0 on an alpha spawn point and 1 a gap to its right
	at:      [2][2]f32,
	health:  [2]f32, // 0 leaves it full
	flag:    game.Thing_Kind, // that flag moved, pole first, to `flag_at`
	_:       [3]u8,
	flag_at: [2]f32,
}

@(rodata)
SCENARIOS := [?]Scenario {
	{"stand", "ctf_Ash", 120, {.AK74, .AK74}, 300, press_nothing, false, {}},
	{"run_right", "ctf_Ash", 120, {.AK74, .AK74}, 240, run_right, false, {}},
	{"run_left", "ctf_Ash", 120, {.AK74, .AK74}, 240, run_left, false, {}},
	{"jump", "ctf_Ash", 120, {.AK74, .AK74}, 240, jump, false, {}},
	{"crouch", "ctf_Ash", 120, {.AK74, .AK74}, 180, crouch, false, {}},
	{"prone", "ctf_Ash", 120, {.AK74, .AK74}, 180, prone, false, {}},
	{"jet", "ctf_Ash", 120, {.AK74, .AK74}, 240, jet, false, {}},
	{"run_and_jet", "ctf_Ash", 120, {.AK74, .AK74}, 600, run_and_jet, false, {}},
	{"prone_crawl", "ctf_Ash", 120, {.AK74, .AK74}, 700, prone_crawl, false, {}},
	{"rolls", "ctf_Ash", 120, {.AK74, .AK74}, 700, rolls, false, {}},
	{"change", "ctf_Ash", 120, {.AK74, .Minigun}, 480, change, false, {}},
	{"idle_antics", "ctf_Ash", 120, {.AK74, .Ruger77}, 3600, press_nothing, false, {}},
	{"fire_ak74", "ctf_Ash", 120, {.AK74, .AK74}, 360, fire, false, {}},
	{"fire_spas", "ctf_Ash", 120, {.Spas12, .AK74}, 240, fire, false, {}},
	{"fire_barrett", "ctf_Ash", 200, {.Barrett, .AK74}, 360, fire, false, {}},
	{"fire_m79", "ctf_Ash", 200, {.M79, .AK74}, 240, fire, false, {}},
	{"grenade", "ctf_Ash", 150, {.AK74, .AK74}, 360, throw_grenade, false, {}},
	{"duel", "ctf_Ash", 160, {.AK74, .MP5}, 900, duel, false, {}},
	{"ctf_duel", "ctf_Ash", 200, {.Minimi, .Ruger77}, 1200, duel, false, {}},
	{"fire_minigun", "ctf_Ash", 80, {.Minigun, .AK74}, 600, fire, false, {}},
	{"fire_law", "ctf_Ash", 250, {.LAW, .AK74}, 480, fire_law, false, {}},
	{"stab", "ctf_Ash", 14, {.Knife, .AK74}, 600, fire, false, {}},
	{"chainsaw", "ctf_Ash", 14, {.Chainsaw, .AK74}, 600, fire, false, {}},
	{"punch", "ctf_Ash", 14, {.Punch, .AK74}, 600, fire, false, {}},
	{"throw_knife", "ctf_Ash", 60, {.Knife, .AK74}, 480, drop, false, {}},
	{"throw_gun", "ctf_Ash", 120, {.AK74, .AK74}, 480, drop, false, {}},
	{"suicide", "ctf_Ash", 120, {.AK74, .AK74}, 600, suicide, false, {}},
	{"kill_respawn", "ctf_Ash", 150, {.Barrett, .AK74}, 900, fire, false, {}},
	{"brawl", "ctf_Ash", 40, {.Spas12, .AK74}, 1500, brawl, false, {}},
	{"brawl_ash", "ctf_Ash", 60, {.M79, .Minimi}, 1500, brawl, false, {}},
	{"brawl_collide", "ctf_Ash", 40, {.Spas12, .AK74}, 1500, brawl, true, {}},
	{"throw_knife_far", "ctf_Ash", 150, {.Knife, .AK74}, 480, drop, false, {}},
	{"knife_spawn_throw", "ctf_Ash", 120, {.Knife, .AK74}, 480, knife_spawn_throw, false, {}},
	{"knife_through_corpse", "ctf_Ash", 30, {.Knife, .AK74}, 480, knife_through_corpse, false, {}},
	{"ctf_capture", "ctf_Ash", 0, {.AK74, .AK74}, 300, press_nothing, false, {placed = true, at = {{-1090, -100}, {1060, -100}}, flag = .Bravo_Flag, flag_at = {-1085, -81}}}, // bravo's flag at alpha's: grabbed and captured
	{"ctf_return", "ctf_Ash", 0, {.AK74, .AK74}, 700, ctf_return, false, {placed = true, at = {{-770, 60}, {-1085, -100}}}},
	{"ctf_throw", "ctf_Ash", 0, {.AK74, .AK74}, 1900, ctf_throw, false, {placed = true, at = {{1060, -100}, {-1085, -100}}}},
	{"kits", "ctf_Dropdown", 0, {.AK74, .AK74}, 600, kits, false, {placed = true, at = {{714, 280}, {600, 280}}, health = {40, 0}}},
	{"gun_pickup", "ctf_Ash", 50, {.AK74, .Punch}, 1800, gun_pickup, false, {}},
	{"parachute", "ctf_Dropdown", 120, {.AK74, .AK74}, 900, parachute, false, {}}, // the alpha spawn point is high
}

press_nothing :: proc(tick: int) -> [2]game.Buttons {
	return {}
}

// Settled first: two seconds standing, then the scenario's own presses.
SETTLE :: 120

run_right :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE ? {.Right} : {}, {}}
}

run_left :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE ? {.Left} : {}, {}}
}

jump :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE && tick % 40 < 10 ? {.Jump} : {}, {}}
}

crouch :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE ? {.Crouch} : {}, {}}
}

prone :: proc(tick: int) -> [2]game.Buttons {
	return {tick == SETTLE ? {.Prone} : {}, {}}
}

jet :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE ? {.Jet} : {}, {}}
}

run_and_jet :: proc(tick: int) -> [2]game.Buttons {
	if tick < SETTLE do return {}
	first: game.Buttons = {.Right} if (tick / 90) % 2 == 0 else {.Left}
	if tick % 70 < 25 do first += {.Jet}
	if tick % 50 == 0 do first += {.Jump}
	return {first, {.Left} if tick % 120 < 60 else {}}
}

// Down, crawling back and forth, up again; down and up with a jump; down and out with a
// roll.
prone_crawl :: proc(tick: int) -> [2]game.Buttons {
	t := tick - SETTLE
	switch {
	case t < 0:                                return {}
	case t == 0 || t == 100 || t == 200 || t == 260 || t == 360: return {{.Prone}, {}}
	case t > 30 && t < 70:                     return {{.Left}, {}}
	case t >= 70 && t < 95:                    return {{.Right}, {}}
	case t > 262 && t < 300:                   return {{.Jump}, {}}
	case t > 400 && t < 430:                   return {{.Crouch, .Right}, {}}
	}
	return {}
}

// Rolls out of a run, forward and back, jumped out of; a backflip off a side jump; left
// and right held together.
rolls :: proc(tick: int) -> [2]game.Buttons {
	t := tick - SETTLE
	switch {
	case t < 0:              return {}
	case t < 30:             return {{.Right}, {}}
	case t < 60:             return {{.Right, .Crouch}, {}}
	case t >= 80 && t < 110:  return {{.Left}, {}}
	case t >= 110 && t < 140: return {{.Left, .Crouch}, {}}
	case t >= 200 && t < 205: return {{.Left, .Jump}, {}}
	case t >= 205 && t < 230: return {{.Left, .Jump, .Jet}, {}}
	case t >= 300 && t < 315: return {{.Left, .Crouch}, {}}
	case t >= 315 && t < 330: return {{.Left, .Crouch, .Jump}, {}}
	case t >= 400 && t < 440: return {{.Left, .Right}, {}}
	case t >= 440 && t < 460: return {{.Left, .Right, .Jump}, {}}
	}
	return {}
}

// The guns changed, and back.
change :: proc(tick: int) -> [2]game.Buttons {
	t := tick - SETTLE
	return {t == 0 || t == 150 ? {.Change} : {}, t == 60 ? {.Change} : {}}
}

fire :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE ? {.Fire} : {}, {}}
}

throw_grenade :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE && tick < SETTLE + 30 ? {.Throw} : {}, {}}
}

// Both fight: firing, moving, reloading.
duel :: proc(tick: int) -> [2]game.Buttons {
	if tick < SETTLE do return {}
	a: game.Buttons = {.Fire}
	b: game.Buttons = {.Fire}
	if (tick / 60) % 3 == 0 do a += {.Right}
	if (tick / 45) % 4 == 1 do b += {.Left}
	if tick % 100 < 15 do b += {.Jet}
	if tick % 300 == 0 do a += {.Reload}
	return {a, b}
}

// The LAW fires only kneeling.
fire_law :: proc(tick: int) -> [2]game.Buttons {
	if tick < SETTLE do return {}
	first: game.Buttons = {.Crouch}
	if tick >= SETTLE + 30 do first += {.Fire}
	return {first, {}}
}

// The drop key held: the gun thrown, or the knife, at its strongest.
drop :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE && tick < SETTLE + 40 ? {.Drop} : {}, {}}
}

// A knife thrown at once, and fire pressed while it is being thrown, under spawn
// protection; then the same once the protection is gone.
knife_spawn_throw :: proc(tick: int) -> [2]game.Buttons {
	switch {
	case tick < 3:                    return {{.Drop}, {}}
	case tick < 40:                   return {{.Fire}, {}}
	case tick >= 200 && tick < 203: return {{.Drop}, {}}
	case tick >= 203 && tick < 240: return {{.Fire}, {}}
	}
	return {}
}

// Soldier 1 kills itself, and soldier 0 throws its knife into the corpse.
knife_through_corpse :: proc(tick: int) -> [2]game.Buttons {
	switch {
	case tick == SETTLE:                         return {{}, {.Suicide}}
	case tick >= SETTLE + 40 && tick < SETTLE + 80: return {{.Drop}, {}}
	}
	return {}
}

suicide :: proc(tick: int) -> [2]game.Buttons {
	return {tick == SETTLE ? {.Suicide} : {}, {}}
}

// Fighting close: both firing, a grenade wound up and thrown now and then among the
// bodies, the dead shot and blown about, and up again.
brawl :: proc(tick: int) -> [2]game.Buttons {
	if tick < SETTLE do return {}
	t := tick - SETTLE
	a: game.Buttons = {.Fire}
	b: game.Buttons = {.Fire}
	if t % 200 >= 100 && t % 200 < 130 do a = {.Throw}
	if (t / 50) % 4 == 1 do b += {.Left}
	if t % 150 < 10 do b += {.Jump}
	return {a, b}
}

// ---------------------------------------------------------------------------------
// The things

// Bravo grabs alpha's flag and runs off with it; alpha shoots it dead, and walks to the
// flag where it fell to send it home.
ctf_return :: proc(tick: int) -> [2]game.Buttons {
	a, b: game.Buttons
	if tick >= 100 && tick < 200 do b = {.Right}
	if tick >= 260 && tick < 400 do a = {.Fire}
	if tick >= 420 && tick < 560 do a = {.Left}
	return {a, b}
}

// Bravo grabs alpha's flag, runs off with it and throws it, and goes; the flag lies its
// time and goes home.
ctf_throw :: proc(tick: int) -> [2]game.Buttons {
	b: game.Buttons
	if tick >= 100 && tick < 160 do b = {.Right}
	if tick == 160 do b = {.Flag_Throw}
	if tick > 160 && tick < 200 do b = {.Left}
	return {{}, b}
}

// Hurt and a grenade short, among the kits: a grenade kit and a medikit taken, the medikit
// beside it left to the cooldown; shot, and that one taken once the cooldown is over.
kits :: proc(tick: int) -> [2]game.Buttons {
	return {{}, {.Fire} if tick >= 200 && tick < 215 else {}}
}

// The gun thrown to an empty-handed soldier, who takes it up and throws it away again,
// where it lies its time.
gun_pickup :: proc(tick: int) -> [2]game.Buttons {
	a, b: game.Buttons
	if tick >= SETTLE && tick < SETTLE + 40 do a = {.Drop}
	if tick >= 400 && tick < 440 do b = {.Drop}
	return {a, b}
}

// Dead, and placed again high over the map: the parachute comes down and lies.
parachute :: proc(tick: int) -> [2]game.Buttons {
	return {{.Suicide} if tick == SETTLE else {}, {}}
}
