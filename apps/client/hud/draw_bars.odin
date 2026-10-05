package hud

import sa "core:container/small_array"
import "core:fmt"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../draw"
import "../ui"

// Along the bottom: health, the ammo and the reload, the wait between shots, the jets
// and the grenades, each a bar beside its icon; the rounds left and the weapon's name;
// my place, my kills and the limit. The team box with the scores and the flags away
// from home. The original's RenderInterface and RenderPlayerInterfaceTexts, as its
// default interface lays them out.

// The default interface (LoadDefaultInterfaceData), in the layout's units: each icon's
// place, anchored across the view; each bar's and text's beside its icon, which it
// keeps whatever the view's width.
@(private = "file") HEALTH_ICON :: [2]f32{5, 439}
@(private = "file") HEALTH_BAR :: [2]f32{45, 449}
@(private = "file") AMMO_ICON :: [2]f32{275, 439}
@(private = "file") AMMO_BAR :: [2]f32{352, 449}
@(private = "file") FIRE_FRAME :: [2]f32{402, 464}
@(private = "file") FIRE_BAR :: [2]f32{409, 464}
@(private = "file") NADES :: [2]f32{308, 462}
@(private = "file") ROUNDS :: [2]f32{348, 451} // right-aligned
@(private = "file") WEAPON_NAME :: [2]f32{285, 454} // right-aligned
@(private = "file") JET_ICON :: [2]f32{480, 439}
@(private = "file") JET_BAR :: [2]f32{520, 449}
@(private = "file") STATUS :: [2]f32{575, 421}
@(private = "file") TEAM_BOX :: [2]f32{575, 330}

@(private = "file") WHITE :: rl.Color{255, 255, 255, 255}
@(private = "file") ROUNDS_COLOR :: rl.Color{242, 244, 40, 255}
@(private = "file") WEAPON_COLOR :: rl.Color{255, 245, 177, 255}
@(private = "file") PLACE_COLOR :: rl.Color{88, 255, 90, 255}
@(private = "file") KILLS_COLOR :: rl.Color{255, 55, 50, 255}
@(private = "file") LIMIT_COLOR :: rl.Color{114, 120, 255, 255}

// The bars and their icons.
draw_bars :: proc(u: ^ui.Ui, art: ^Art, mine: ^Mine) {
	p := &art.pictures
	picture(u, p[.Health], aligned(u, anchored(u, HEALTH_ICON, HEALTH_ICON)), WHITE)
	bar(u, p[.Health_Bar], HEALTH_ICON, HEALTH_BAR, mine.health / sim.DEFAULT_HEALTH)

	picture(u, p[.Ammo], aligned(u, anchored(u, AMMO_ICON, AMMO_ICON)), WHITE)
	if share, shown := mine.ammo_bar.?; shown do bar(u, p[.Reload_Bar], AMMO_ICON, AMMO_BAR, share)
	picture(u, p[.Fire_Bar_Frame], aligned(u, anchored(u, AMMO_ICON, FIRE_FRAME)), WHITE)
	bar(u, p[.Fire_Bar], AMMO_ICON, FIRE_BAR, mine.fire_bar, from_left = false)

	if jets, has_jets := mine.jets.?; has_jets {
		picture(u, p[.Jet], aligned(u, anchored(u, JET_ICON, JET_ICON)), WHITE)
		bar(u, p[.Jet_Bar], JET_ICON, JET_BAR, jets)
	}

	// the grenades on the belt, one each
	nade := p[.Nade]
	for j in 1 ..= mine.grenades {
		at := anchored(u, AMMO_ICON, NADES) + {nade.size.x * f32(j), 0}
		picture(u, nade, aligned(u, at), WHITE)
	}
}

// The rounds left and the weapon's name, alive; and always my place, my kills against
// the leader's, and the limit.
draw_bar_texts :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	mine := &data.mine
	if !mine.dead {
		at := anchored(u, AMMO_ICON, ROUNDS)
		rounds := fmt.tprintf("%d", mine.ammo)
		write(u, rounds, {at.x - text_width(u, rounds, MENU_FONT), at.y}, MENU_FONT, ROUNDS_COLOR)
		if named(mine.weapon) {
			at = anchored(u, AMMO_ICON, WEAPON_NAME)
			name := data.weapon_names[mine.weapon]
			write(u, name, {at.x - text_width(u, name, WEAPONS_FONT), at.y}, WEAPONS_FONT, WEAPON_COLOR)
		}
	}

	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	place := 0
	for id, i in ranks {
		if id == data.me do place = i + 1
	}
	at := [2]f32{STATUS.x * wide(u), STATUS.y}
	if place > 0 do write(u, fmt.tprintf("%d/%d", place, len(ranks)), at, SMALL_FONT, PLACE_COLOR)
	kills := data.players[data.me].kills
	standing: string
	if place == 1 && len(ranks) > 1 {
		lead := kills - data.players[ranks[1]].kills
		standing = fmt.tprintf("%d (%s%d)", kills, "+" if lead > 0 else "", lead)
	} else {
		behind := kills - data.players[ranks[0]].kills if len(ranks) > 0 else 0
		standing = fmt.tprintf("%d (%d)", kills, behind)
	}
	write(u, standing, at + {0, 10}, SMALL_FONT, KILLS_COLOR)
	write(u, fmt.tprintf("%d", data.limit), at + {0, 20}, SMALL_FONT, LIMIT_COLOR)
}

// A box with each team's flag shown where it is away from its base.
draw_team_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	box(u, art, {TEAM_BOX.x * wide(u), TEAM_BOX.y, 57, 88}, FULL_BOX_ALPHA)
	at := [2]f32{align(u, (TEAM_BOX.x + 4) * wide(u)), align(u, TEAM_BOX.y + 5)}
	if !data.flags_home[.Alpha] do picture(u, art.pictures[.No_Flag], at, {255, 0, 0, 255})
	if !data.flags_home[.Bravo] do picture(u, art.pictures[.No_Flag], {align(u, at.x + 31), at.y}, {0, 0, 255, 255})
}

// And in it, the teams' captures, the leader's first.
draw_team_scores :: proc(u: ^ui.Ui, data: ^Hud_Data) {
	order := [2]res.Team{.Alpha, .Bravo}
	if data.captures[.Bravo] > data.captures[.Alpha] do order = {.Bravo, .Alpha}
	for team, i in order {
		at := [2]f32{TEAM_BOX.x * wide(u) + 2, TEAM_BOX.y + 25 + 40 * f32(i)}
		write(u, fmt.tprintf("%d", data.captures[team]), at, MENU_FONT, team_text_color(team))
	}
}

// The teams' own colours in the HUD's texts.
team_text_color :: proc(team: res.Team) -> rl.Color {
	#partial switch team {
	case .Alpha:   return {255, 0, 0, 255}
	case .Bravo:   return {0, 0, 255, 255}
	case .Charlie: return {0xDF, 0xDF, 0x53, 0xFF}
	case .Delta:   return {0x53, 0xDF, 0x53, 0xFF}
	}
	return {0xC3, 0xC3, 0xC3, 0xF1}
}

// Where `place` is, in the layout beside `icon`: as far from the icon as there, the icon
// anchored across the view.
@(private = "file")
anchored :: proc(u: ^ui.Ui, icon, place: [2]f32) -> [2]f32 {
	return {icon.x * wide(u) + place.x - icon.x, place.y}
}

@(private = "file")
aligned :: proc(u: ^ui.Ui, at: [2]f32) -> [2]f32 {
	return {align(u, at.x), align(u, at.y)}
}

// The original's RenderBar: the bar's image cut to the `share` of it, growing from its
// left, or from its right shrinking toward its left.
@(private = "file")
bar :: proc(u: ^ui.Ui, image: draw.Sprite, icon, place: [2]f32, share: f32, from_left := true) {
	p := clamp(share, 0, 1)
	at := [2]f32{align(u, icon.x * wide(u)) + place.x - icon.x, align(u, icon.y) + place.y - icon.y}
	part := rl.Rectangle{0, 0, p, 1} if from_left else rl.Rectangle{1 - p, 0, p, 1}
	picture(u, image, at, WHITE, part = part)
}

// The weapons whose names are shown: not a fist or the grenades.
@(private = "file")
named :: proc(weapon: res.Weapon) -> bool {
	#partial switch weapon {
	case .Punch, .Frag_Grenade, .Thrown_Knife:
		return false
	}
	return true
}
