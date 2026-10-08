package opensoldat

import "../../core/game"
import res "../../core/resources"

// What is played: two soldiers a gap apart on an alpha spawn point, alpha's soldier 0
// on the left, each aiming at the other's chest, pressing what `press` says on each tick
// (counted from 0). The C comparison's scenarios (tests/compare/scenarios.odin), as far
// as they move and fight: none that turns on the dice OpenSoldat and the port roll
// differently (an idle antic, where a soldier comes back to life), or on the things.
Scenario :: struct {
	name:     string,
	map_name: string,
	gap:      f32,
	weapons:  [2]res.Weapon,
	ticks:    int,
	press:    proc(tick: int) -> [2]game.Buttons,
}

@(rodata)
SCENARIOS := [?]Scenario {
	// moving
	{"stand", "ctf_Ash", 120, {.AK74, .AK74}, 300, press_nothing},
	{"run_right", "ctf_Ash", 120, {.AK74, .AK74}, 240, run_right},
	{"run_left", "ctf_Ash", 120, {.AK74, .AK74}, 240, run_left},
	{"jump", "ctf_Ash", 120, {.AK74, .AK74}, 240, jump},
	{"crouch", "ctf_Ash", 120, {.AK74, .AK74}, 180, crouch},
	{"prone", "ctf_Ash", 120, {.AK74, .AK74}, 180, prone},
	{"jet", "ctf_Ash", 120, {.AK74, .AK74}, 240, jet},
	{"run_and_jet", "ctf_Ash", 120, {.AK74, .AK74}, 600, run_and_jet},
	{"prone_crawl", "ctf_Ash", 120, {.AK74, .AK74}, 700, prone_crawl},
	{"rolls", "ctf_Ash", 120, {.AK74, .AK74}, 700, rolls},
	// the guns
	{"change", "ctf_Ash", 120, {.AK74, .Minigun}, 480, change},
	{"fire_ak74", "ctf_Ash", 120, {.AK74, .AK74}, 360, fire},
	{"fire_mp5", "ctf_Ash", 120, {.MP5, .AK74}, 360, fire},
	{"fire_eagles", "ctf_Ash", 120, {.Desert_Eagles, .AK74}, 360, fire},
	{"fire_spas", "ctf_Ash", 120, {.Spas12, .AK74}, 240, fire},
	{"fire_ruger", "ctf_Ash", 200, {.Ruger77, .AK74}, 360, fire},
	{"fire_barrett", "ctf_Ash", 200, {.Barrett, .AK74}, 360, fire},
	{"fire_m79", "ctf_Ash", 200, {.M79, .AK74}, 240, fire},
	{"fire_minimi", "ctf_Ash", 120, {.Minimi, .AK74}, 360, fire},
	{"fire_minigun", "ctf_Ash", 80, {.Minigun, .AK74}, 600, fire},
	{"fire_law", "ctf_Ash", 250, {.LAW, .AK74}, 480, fire_law},
	{"reload", "ctf_Ash", 120, {.AK74, .AK74}, 480, reload},
	{"grenade", "ctf_Ash", 150, {.AK74, .AK74}, 360, throw_grenade},
	{"stab", "ctf_Ash", 14, {.Knife, .AK74}, 300, fire},
	{"chainsaw", "ctf_Ash", 14, {.Chainsaw, .AK74}, 300, fire},
	{"punch", "ctf_Ash", 14, {.Punch, .AK74}, 300, fire},
	// both at once
	{"duel", "ctf_Ash", 160, {.AK74, .MP5}, 900, duel},
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

// A few shots, then a reload by hand before the clip is out, then firing it dry.
reload :: proc(tick: int) -> [2]game.Buttons {
	t := tick - SETTLE
	switch {
	case t < 0:   return {}
	case t < 30:  return {{.Fire}, {}}
	case t == 40: return {{.Reload}, {}}
	case t > 200: return {{.Fire}, {}}
	}
	return {}
}

throw_grenade :: proc(tick: int) -> [2]game.Buttons {
	return {tick >= SETTLE && tick < SETTLE + 30 ? {.Throw} : {}, {}}
}

// The LAW fires only kneeling.
fire_law :: proc(tick: int) -> [2]game.Buttons {
	if tick < SETTLE do return {}
	first: game.Buttons = {.Crouch}
	if tick >= SETTLE + 30 do first += {.Fire}
	return {first, {}}
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
