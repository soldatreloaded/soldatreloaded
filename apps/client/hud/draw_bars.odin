package hud

import sa "core:container/small_array"
import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import sim "../../../core/game"
import res "../../../core/resources"
import "../draw"
import "../ui"

// Along the bottom: health, the ammo and the reload, the wait between shots, the jets
// and the grenades, each a bar beside its icon; the rounds left and the weapon's name;
// my place, my kills and the limit. The team box with the scores and the flags away
// from home. The original's RenderInterface and RenderPlayerInterfaceTexts, laid out as
// the interface worn says (res.Interface_Setup, art.layout): the game's own, or a Soldat
// 1 custom interface's setup.sif, in the 640 by 480 layout's units. Each icon is placed
// across the view as it widens; each bar, text and the grenades kept as far from its
// anchor (art.anchors) as the layout has them. A bar shows its share as its picture cut
// across or down, or as a number; turned as the layout says, about its top-left. The
// vest's bar, the cluster grenades and the ping's dot have no place in this game: an
// interface's are kept, and drawn by none.

// The bars and their icons.
draw_bars :: proc(u: ^ui.Ui, art: ^Art, mine: ^Mine) {
	p := &art.pictures
	s := &art.layout
	a := &art.anchors
	tint := WHITE
	tint.a = s.alpha
	// the game's own fills its bars from their left; a custom one, but for the reload's
	// and the fire's, from their right (the original's IntAlign)
	from_left := !art.custom

	if .Health in s.shown {
		icon(u, p[.Health], s.health_icon, tint)
		bar(u, p[.Health_Bar], a.health, s.health_bar, mine.health / sim.DEFAULT_HEALTH, from_left, tint)
	}
	if .Ammo in s.shown {
		icon(u, p[.Ammo], s.ammo_icon, tint)
		if share, shown := mine.ammo_bar.?; shown {
			reloading := mine.ammo == 0
			bar(u, p[.Reload_Bar], a.ammo, s.ammo_bar, share, true if reloading else from_left, tint)
		}
	}
	if .Fire in s.shown {
		// the frame where the layout's fire bar is, and the bar where its fire icon is (sic)
		at := aligned(u, anchored(u, a.fire, f32s(s.fire_bar.at)))
		picture(u, p[.Fire_Bar_Frame], at, tint, angle = math.to_radians(f32(s.fire_bar.rotate)))
		fire := s.fire_bar
		fire.at, fire.rotate = s.fire_icon.at, s.fire_icon.rotate
		bar(u, p[.Fire_Bar], a.fire, fire, mine.fire_bar, false, tint)
	}
	if jets, has_jets := mine.jets.?; has_jets && .Jet in s.shown {
		icon(u, p[.Jet], s.jet_icon, tint)
		bar(u, p[.Jet_Bar], a.jet, s.jet_bar, jets, from_left, tint)
	}

	// the grenades on the belt, one each, in a row or up a column
	if .Nades in s.shown && s.nades.style != .Text {
		nade := p[.Nade]
		base := anchored(u, a.nades, f32s(s.nades.at))
		for j in 1 ..= mine.grenades {
			step := f32(j)
			at := base + {nade.size.x * step, 0} if s.nades.style == .Horizontal else base + {0, nade.size.y * (6 - step)}
			picture(u, nade, aligned(u, at), tint)
		}
	}
}

// The rounds left and the weapon's name, alive, and the bars the layout shows as numbers;
// and always my place, my kills against the leader's, and the limit.
draw_bar_texts :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	s := &art.layout
	a := &art.anchors
	mine := &data.mine
	if !mine.dead {
		white := with_alpha(WHITE, int(s.alpha))
		if .Health in s.shown && s.health_bar.style == .Text {
			percent(u, a.health, s.health_bar.at, mine.health / sim.DEFAULT_HEALTH, white)
		}
		if share, shown := mine.ammo_bar.?; shown && .Ammo in s.shown && s.ammo_bar.style == .Text && mine.ammo == 0 {
			percent(u, a.ammo, s.ammo_bar.at, share, white) // the reload's share done
		}
		if jets, has_jets := mine.jets.?; has_jets && .Jet in s.shown && s.jet_bar.style == .Text {
			percent(u, a.jet, s.jet_bar.at, jets, white)
		}
		if .Nades in s.shown && s.nades.style == .Text {
			write(u, fmt.tprintf("%d", mine.grenades), anchored(u, a.nades, f32s(s.nades.at)), MENU_FONT, white)
		}
		// the game's own puts the rounds and the name to the left of their places; a
		// custom one, to the right (the original's IntAlign)
		right := !art.custom
		if .Bullets in s.shown {
			at := anchored(u, a.ammo, f32s(s.bullets))
			rounds := fmt.tprintf("%d", mine.ammo)
			if right do at.x -= text_width(u, rounds, MENU_FONT)
			write(u, rounds, at, MENU_FONT, with_alpha(ROUNDS_COLOR, int(s.alpha)))
		}
		if .Weapon in s.shown && named(mine.weapon) {
			at := anchored(u, a.ammo, f32s(s.weapon))
			name := data.weapon_names[mine.weapon]
			if right do at.x -= text_width(u, name, WEAPONS_FONT)
			write(u, name, at, WEAPONS_FONT, with_alpha(WEAPON_COLOR, int(s.alpha)))
		}
	}

	if .Status not_in s.shown do return
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	place := 0
	for id, i in ranks {
		if id == data.me do place = i + 1
	}
	at := [2]f32{f32(s.status.x) * wide(u), f32(s.status.y)}
	if place > 0 do write(u, fmt.tprintf("%d/%d", place, len(ranks)), at, SMALL_FONT, with_alpha(PLACE_COLOR, int(s.alpha)))
	kills := data.players[data.me].kills
	standing: string
	if place == 1 && len(ranks) > 1 {
		lead := kills - data.players[ranks[1]].kills
		standing = fmt.tprintf("%d (%s%d)", kills, "+" if lead > 0 else "", lead)
	} else {
		behind := kills - data.players[ranks[0]].kills if len(ranks) > 0 else 0
		standing = fmt.tprintf("%d (%d)", kills, behind)
	}
	write(u, standing, at + {0, 10}, SMALL_FONT, with_alpha(KILLS_COLOR, int(s.alpha)))
	write(u, fmt.tprintf("%d", data.limit), at + {0, 20}, SMALL_FONT, with_alpha(LIMIT_COLOR, int(s.alpha)))
}

// A box with each team's flag shown where it is away from its base.
draw_team_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	s := &art.layout
	if .Team not_in s.shown do return
	place := f32s(s.team_box)
	box(u, art, {place.x * wide(u), place.y, 57, 88}, u8(int(s.alpha) * 56 / 100))
	at := [2]f32{align(u, (place.x + 4) * wide(u)), align(u, place.y + 5)}
	if !data.flags_home[.Alpha] do picture(u, art.pictures[.No_Flag], at, {255, 0, 0, s.alpha})
	if !data.flags_home[.Bravo] do picture(u, art.pictures[.No_Flag], {align(u, at.x + 31), at.y}, {0, 0, 255, s.alpha})
}

// And in it, the teams' captures, the leader's first.
draw_team_scores :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	s := &art.layout
	if .Team not_in s.shown do return
	order := [2]res.Team{.Alpha, .Bravo}
	if data.captures[.Bravo] > data.captures[.Alpha] do order = {.Bravo, .Alpha}
	for team, i in order {
		at := [2]f32{f32(s.team_box.x) * wide(u) + 2, f32(s.team_box.y) + 25 + 40 * f32(i)}
		write(u, fmt.tprintf("%d", data.captures[team]), at, MENU_FONT, with_alpha(team_text_color(team), int(s.alpha)))
	}
}

@(private = "file") WHITE :: rl.Color{255, 255, 255, 255}
@(private = "file") ROUNDS_COLOR :: rl.Color{242, 244, 40, 255}
@(private = "file") WEAPON_COLOR :: rl.Color{255, 245, 177, 255}
@(private = "file") PLACE_COLOR :: rl.Color{88, 255, 90, 255}
@(private = "file") KILLS_COLOR :: rl.Color{255, 55, 50, 255}
@(private = "file") LIMIT_COLOR :: rl.Color{114, 120, 255, 255}

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

// Where `place` is, in the layout beside `anchor`: as far from it as there, the anchor
// spread across the view.
@(private = "file")
anchored :: proc(u: ^ui.Ui, anchor, place: [2]f32) -> [2]f32 {
	return {anchor.x * wide(u) + place.x - anchor.x, place.y}
}

@(private = "file")
aligned :: proc(u: ^ui.Ui, at: [2]f32) -> [2]f32 {
	return {align(u, at.x), align(u, at.y)}
}

@(private = "file")
f32s :: proc(v: [2]i32) -> [2]f32 {
	return {f32(v.x), f32(v.y)}
}

// An icon at its place across the view, turned as the layout says.
@(private = "file")
icon :: proc(u: ^ui.Ui, image: draw.Sprite, place: res.Interface_Icon, tint: rl.Color) {
	at := f32s(place.at)
	picture(u, image, aligned(u, anchored(u, at, at)), tint, angle = math.to_radians(f32(place.rotate)))
}

// The original's RenderBar: the bar's image cut to the `share` of it, beside `anchor`,
// turned about its top-left. Across, growing from its left, or from its right shrinking
// toward its left; down, growing up from its bottom, or its top shown shrinking toward
// its bottom, as the original draws them. Nothing for a bar shown as a number.
@(private = "file")
bar :: proc(u: ^ui.Ui, image: draw.Sprite, anchor: [2]f32, layout: res.Interface_Bar, share: f32, from_left: bool, tint: rl.Color) {
	if layout.style == .Text do return
	p := clamp(share, 0, 1)
	place := f32s(layout.at)
	at := [2]f32{align(u, anchor.x * wide(u)) + place.x - anchor.x, align(u, anchor.y) + place.y - anchor.y}
	part: rl.Rectangle
	switch {
	case layout.style == .Vertical && from_left:
		part = {0, 1 - p, 1, p}
		at.y += image.size.y * (1 - p)
	case layout.style == .Vertical:
		part = {0, 0, 1, p}
		at.y += image.size.y * (1 - p)
	case from_left:
		part = {0, 0, p, 1}
	case:
		part = {1 - p, 0, p, 1}
	}
	picture(u, image, at, tint, angle = math.to_radians(f32(layout.rotate)), part = part)
}

// A bar shown as a number: its share, a whole percent, at its place beside `anchor`.
@(private = "file")
percent :: proc(u: ^ui.Ui, anchor: [2]f32, place: [2]i32, share: f32, color: rl.Color) {
	write(u, fmt.tprintf("%d%%", int(clamp(share, 0, 1) * 100)), anchored(u, anchor, f32s(place)), MENU_FONT, color)
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
