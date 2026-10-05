package bots

import "core:log"
import "core:strings"

import "../game"
import res "../resources"
import "../utils"

// A .bot file (data/bots), in the original's format: a [BOT] section of Key=Value
// lines. What one says.

Profile :: struct {
	name:              utils.Short_String(24), // a name, as the wire carries one
	look:              game.Look,
	favourite:         res.Weapon, // the primary it spawns with (Favourite_Weapon, by the weapon's name)
	secondary:         res.Weapon, // Secondary_Weapon: 0 the USSOCOM, 1 the knife, 2 the chainsaw, 3 the LAW
	friend:            utils.Short_String(24), // a player it never fires at
	accuracy:          i32, // the spread of its aim, in units; more is worse
	shoot_dead:        bool, // Shoot_Dead: fires on a corpse a while
	grenade_frequency: i32, // one in this many ticks, with a target near
	camping:           i32, // Camping: crouches and lies in wait
	chat_frequency:    i32, // Chat_Frequency: how rarely it talks (more is rarer)
	chat_kill:         utils.Short_String(128), // a line of chat each, as the wire carries one
	chat_dead:         utils.Short_String(128),
	chat_low_health:   utils.Short_String(128),
	chat_see_enemy:    utils.Short_String(128),
	chat_winning:      utils.Short_String(128),
}

// A .bot file; false (and says so in the log) if it can't be read or names no weapon.
profile_load :: proc(path: string, weapons: ^[res.Weapon]game.Weapon_Info) -> (profile: Profile, ok: bool) {
	data := utils.read_file(path, context.temp_allocator) or_return
	p := Profile {
		favourite         = .Punch,
		secondary         = .USSOCOM,
		accuracy          = 20,
		grenade_frequency = 100,
		chat_frequency    = 10,
		look = {
			shirt = {255, 255, 255, 255},
			pants = {255, 255, 255, 255},
			skin  = {230, 180, 120, 255},
			hair  = {0, 0, 0, 255},
			jet   = {0xFF, 0xBD, 0x24, 255}, // DEFAULT_JETCOLOR, as a bot's is
		},
	}
	found_weapon := false
	in_bot := false
	text := string(data)
	for line in utils.next_line(&text) {
		if len(line) > 0 && line[0] == '[' {
			in_bot = strings.has_prefix(line, "[BOT]")
			continue
		}
		if !in_bot do continue
		key, equals, value := strings.partition(line, "=")
		if equals == "" do continue
		switch key {
		case "Name":              utils.short_string_set(&p.name, value)
		case "Color1":            p.look.shirt = parse_color(value, false)
		case "Color2":            p.look.pants = parse_color(value, false)
		case "Skin_Color":        p.look.skin = parse_color(value, true)
		case "Hair_Color":        p.look.hair = parse_color(value, false)
		case "Favourite_Weapon":
			p.favourite = weapon_by_name(weapons, value)
			found_weapon = p.favourite != .Punch || value == "Hands"
		case "Secondary_Weapon":  p.secondary = res.Weapon(int(res.Weapon.USSOCOM) + int(clamp(atoi(value), 0, 3)))
		case "Friend":            utils.short_string_set(&p.friend, value)
		case "Accuracy":          p.accuracy = atoi(value)
		case "Shoot_Dead":        p.shoot_dead = atoi(value) == 1
		case "Grenade_Frequency": p.grenade_frequency = atoi(value)
		case "Camping":           p.camping = atoi(value)
		case "Hair":              p.look.hair_style = res.Hair_Style(clamp(atoi(value), 0, 4))
		case "Headgear":
			h := atoi(value) // 0 nothing, 2 the hat, anything else the helmet
			p.look.head_style = .None if h == 0 else .Hat if h == 2 else .Helmet
		case "Chain":             p.look.chain_style = res.Chain_Style(clamp(atoi(value), 0, 2))
		case "Chat_Frequency":    p.chat_frequency = atoi(value)
		case "Chat_Kill":         utils.short_string_set(&p.chat_kill, value)
		case "Chat_Dead":         utils.short_string_set(&p.chat_dead, value)
		case "Chat_Lowhealth":    utils.short_string_set(&p.chat_low_health, value)
		case "Chat_SeeEnemy":     utils.short_string_set(&p.chat_see_enemy, value)
		case "Chat_Winning":      utils.short_string_set(&p.chat_winning, value)
		}
	}
	if !found_weapon { // the original gives up on a bot whose weapon it doesn't know
		log.errorf("bots: %s names no weapon", path)
		return {}, false
	}
	if p.name.length == 0 do utils.short_string_set(&p.name, "Bot")
	return p, true
}

// Every .bot under <data_dir>/bots that reads, sorted by file name. Free with `delete`.
profiles_load :: proc(data_dir: string, weapons: ^[res.Weapon]game.Weapon_Info, allocator := context.allocator) -> []Profile {
	dir := utils.temp_path(data_dir, "bots")
	names := utils.list_files(dir, ".bot", context.temp_allocator)
	profiles := make([dynamic]Profile, 0, len(names), allocator)
	for name in names {
		path := utils.temp_path(dir, strings.concatenate({name, ".bot"}, context.temp_allocator))
		if profile, ok := profile_load(path, weapons); ok do append(&profiles, profile)
	}
	return profiles[:]
}

// One of them at random, for a bot nobody named: the original's RandomBot, which never
// picks "Boogie Man" (it takes "Sniper" instead). None with none.
profile_random :: proc(profiles: []Profile, rng: ^game.Rng) -> (^Profile, bool) {
	if len(profiles) == 0 do return nil, false
	pick := &profiles[game.rng_below(rng, len(profiles))]
	name := utils.short_string_text(&pick.name)
	if name == "Boogie Man" || name == "Dummy" {
		for &profile in profiles {
			if utils.short_string_text(&profile.name) == "Sniper" do return &profile, true
		}
	}
	return pick, true
}

// A Delphi colour as the files write it, "$00BBGGRR": the original's ReadConfColor
// turns it round; its ReadConfMagicColor (the skin's) takes the bytes as they are.
@(private = "file")
parse_color :: proc(text: string, magic: bool) -> utils.Rgba {
	v := parse_hex(text[1:] if strings.has_prefix(text, "$") else text)
	lo, mid, hi := u8(v & 0xFF), u8((v >> 8) & 0xFF), u8((v >> 16) & 0xFF)
	return {hi, mid, lo, 255} if magic else {lo, mid, hi, 255}
}

// The weapon of a name, as the table spells it; the hands for one it doesn't know.
@(private = "file")
weapon_by_name :: proc(weapons: ^[res.Weapon]game.Weapon_Info, name: string) -> res.Weapon {
	for info, weapon in weapons {
		if info.name == name do return weapon
	}
	return .Punch
}

// C's atoi, which the original's numbers were read with: leading whitespace, a sign,
// then digits; 0 for none.
@(private = "file")
atoi :: proc(text: string) -> i32 {
	s := strings.trim_left_space(text)
	negative := false
	if len(s) > 0 && (s[0] == '-' || s[0] == '+') {
		negative = s[0] == '-'
		s = s[1:]
	}
	v: i32
	for ch in s {
		if ch < '0' || ch > '9' do break
		v = v * 10 + i32(ch - '0')
	}
	return -v if negative else v
}

// C's strtoul in base 16: leading whitespace, an optional 0x, then hex digits.
@(private = "file")
parse_hex :: proc(text: string) -> u32 {
	s := strings.trim_left_space(text)
	if strings.has_prefix(s, "0x") || strings.has_prefix(s, "0X") do s = s[2:]
	v: u32
	for ch in s {
		digit: u32
		switch {
		case ch >= '0' && ch <= '9': digit = u32(ch - '0')
		case ch >= 'a' && ch <= 'f': digit = u32(ch - 'a' + 10)
		case ch >= 'A' && ch <= 'F': digit = u32(ch - 'A' + 10)
		case:                        return v
		}
		v = v * 16 + digit
	}
	return v
}
