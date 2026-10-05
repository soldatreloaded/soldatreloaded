package bots

import "../game"
import res "../resources"
import "../utils"

// What a bot is told by its file (res.Bot_Profile, data/bots), as the game has it.

// The soldier it looks like: its colours and styles, with a bot's jet flame.
profile_look :: proc(profile: ^res.Bot_Profile) -> game.Look {
	return {
		shirt       = profile.shirt,
		pants       = profile.pants,
		skin        = profile.skin,
		hair        = profile.hair,
		jet         = {0xFF, 0xBD, 0x24, 255}, // DEFAULT_JETCOLOR, as a bot's is
		hair_style  = profile.hair_style,
		head_style  = profile.head_style,
		chain_style = profile.chain_style,
	}
}

// One of them at random, for a bot nobody named: the original's RandomBot, which never
// picks "Boogie Man" (it takes "Sniper" instead). None with none.
profile_random :: proc(profiles: []res.Bot_Profile, rng: ^game.Rng) -> (^res.Bot_Profile, bool) {
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
