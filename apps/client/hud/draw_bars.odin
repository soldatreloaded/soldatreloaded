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
// the hud worn's layout.json says (res.Hud_Layout, art.layout), in the 640 by 480
// layout's units. Each icon is placed across the view as it widens; each bar, text and
// the grenades kept as far from its anchor (an icon, or the layout's corner) as the
// layout has them. A bar shows its share as its picture cut across or down, filling
// forward or backward, or as a number; turned as the layout says, about its top-left.
// The vest's bar, the cluster grenades and the ping's dot have no place in this game: a
// layout's are kept, and drawn by none. Each part is drawn `by` as big about its anchor
// as it is laid out (zoom.odin): an icon about itself, what is placed beside an anchor
// about the anchor, as the original's interface unscaled keeps their distances in pixels.

// The bars and their icons, `by` as big as laid out (shrink_of).
draw_bars :: proc(u: ^ui.Ui, art: ^Art, mine: ^Mine, by: f32 = 1) {
	p := &art.pictures
	l := &art.layout
	tint := WHITE
	tint.a = l.alpha

	if l.health.shown {
		icon(u, p[.Health], l.health.icon, tint, by)
		bar(u, p[.Health_Bar], anchor_of(l, l.health.bar.anchor), l.health.bar, mine.health / sim.DEFAULT_HEALTH, l.health.bar.fill, tint, by)
	}
	if l.ammo.shown {
		icon(u, p[.Ammo], l.ammo.icon, tint, by)
		if share, shown := mine.ammo_bar.?; shown {
			fill := l.ammo.reload_fill if mine.ammo == 0 else l.ammo.bar.fill // emptied, the reload's
			bar(u, p[.Reload_Bar], anchor_of(l, l.ammo.bar.anchor), l.ammo.bar, share, fill, tint, by)
		}
	}
	if l.fire.shown {
		anchor := anchor_of(l, l.fire.bar.anchor)
		z := zoom_around(u, spread(u, anchor), by)
		picture(u, p[.Fire_Bar_Frame], aligned(u, anchored(u, anchor, f32s(l.fire.frame.at))), tint, angle = math.to_radians(f32(l.fire.frame.rotate)))
		zoom_end(z)
		bar(u, p[.Fire_Bar], anchor, l.fire.bar, mine.fire_bar, l.fire.bar.fill, tint, by)
	}
	if jets, has_jets := mine.jets.?; has_jets && l.jet.shown {
		icon(u, p[.Jet], l.jet.icon, tint, by)
		bar(u, p[.Jet_Bar], anchor_of(l, l.jet.bar.anchor), l.jet.bar, jets, l.jet.bar.fill, tint, by)
	}

	// the grenades on the belt, one each, in a row or up a column
	if l.nades.shown && l.nades.style != .Number {
		nade := p[.Nade]
		anchor := anchor_of(l, l.nades.anchor)
		base := anchored(u, anchor, f32s(l.nades.at))
		z := zoom_around(u, spread(u, anchor), by)
		for j in 1 ..= mine.grenades {
			step := f32(j)
			at := base + {nade.size.x * step, 0} if l.nades.style == .Across else base + {0, nade.size.y * (6 - step)}
			picture(u, nade, aligned(u, at), tint)
		}
		zoom_end(z)
	}
}

// The rounds left and the weapon's name, alive, and the bars the layout shows as numbers;
// and always the place, the kills against the leader's, and the limit of whoever I am
// watching (me, unless I follow a player).
draw_bar_texts :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	l := &art.layout
	mine := &data.mine
	by := shrink_of(u, data)
	if !mine.dead {
		white := with_alpha(WHITE, int(l.alpha))
		if l.health.shown && l.health.bar.style == .Number {
			percent(u, anchor_of(l, l.health.bar.anchor), l.health.bar.at, mine.health / sim.DEFAULT_HEALTH, white, by)
		}
		if share, shown := mine.ammo_bar.?; shown && l.ammo.shown && l.ammo.bar.style == .Number && mine.ammo == 0 {
			percent(u, anchor_of(l, l.ammo.bar.anchor), l.ammo.bar.at, share, white, by) // the reload's share done
		}
		if jets, has_jets := mine.jets.?; has_jets && l.jet.shown && l.jet.bar.style == .Number {
			percent(u, anchor_of(l, l.jet.bar.anchor), l.jet.bar.at, jets, white, by)
		}
		if l.nades.shown && l.nades.style == .Number {
			anchor := anchor_of(l, l.nades.anchor)
			z := zoom_around(u, spread(u, anchor), by)
			write(u, fmt.tprintf("%d", mine.grenades), anchored(u, anchor, f32s(l.nades.at)), MENU_FONT, white)
			zoom_end(z)
		}
		if l.bullets.shown do text(u, l, l.bullets, fmt.tprintf("%d", mine.ammo), MENU_FONT, ROUNDS_COLOR, by)
		if l.weapon.shown && named(mine.weapon) do text(u, l, l.weapon, data.weapon_names[mine.weapon], WEAPONS_FONT, WEAPON_COLOR, by)
	}

	if !l.status.shown do return
	ranked := rank_players(data)
	ranks := sa.slice(&ranked)
	place := 0
	for id, i in ranks {
		if id == data.viewed do place = i + 1
	}
	at := [2]f32{f32(l.status.at.x) * wide(u), f32(l.status.at.y)}
	z := zoom_around(u, at, by)
	defer zoom_end(z)
	if place > 0 do write(u, fmt.tprintf("%d/%d", place, len(ranks)), at, SMALL_FONT, with_alpha(PLACE_COLOR, int(l.alpha)))
	kills := data.players[data.viewed].kills
	standing: string
	if place == 1 && len(ranks) > 1 {
		lead := kills - data.players[ranks[1]].kills
		standing = fmt.tprintf("%d (%s%d)", kills, "+" if lead > 0 else "", lead)
	} else {
		behind := kills - data.players[ranks[0]].kills if len(ranks) > 0 else 0
		standing = fmt.tprintf("%d (%d)", kills, behind)
	}
	write(u, standing, at + {0, 10}, SMALL_FONT, with_alpha(KILLS_COLOR, int(l.alpha)))
	write(u, fmt.tprintf("%d", data.limit), at + {0, 20}, SMALL_FONT, with_alpha(LIMIT_COLOR, int(l.alpha)))
}

// A box with each team's flag shown where it is away from its base.
draw_team_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	l := &art.layout
	if !l.team_box.shown do return
	place := f32s(l.team_box.at)
	z := zoom_around(u, {place.x * wide(u), place.y}, shrink_of(u, data))
	defer zoom_end(z)
	box(u, art, {place.x * wide(u), place.y, 57, 88}, u8(int(l.alpha) * 56 / 100))
	at := [2]f32{align(u, (place.x + 4) * wide(u)), align(u, place.y + 5)}
	if !data.flags_home[.Alpha] do picture(u, art.pictures[.No_Flag], at, {255, 0, 0, l.alpha})
	if !data.flags_home[.Bravo] do picture(u, art.pictures[.No_Flag], {align(u, at.x + 31), at.y}, {0, 0, 255, l.alpha})
}

// And in it, the teams' captures, the leader's first.
draw_team_scores :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data) {
	l := &art.layout
	if !l.team_box.shown do return
	order := [2]res.Team{.Alpha, .Bravo}
	if data.captures[.Bravo] > data.captures[.Alpha] do order = {.Bravo, .Alpha}
	z := zoom_around(u, {f32(l.team_box.at.x) * wide(u), f32(l.team_box.at.y)}, shrink_of(u, data)) // the box's
	defer zoom_end(z)
	for team, i in order {
		at := [2]f32{f32(l.team_box.at.x) * wide(u) + 2, f32(l.team_box.at.y) + 25 + 40 * f32(i)}
		write(u, fmt.tprintf("%d", data.captures[team]), at, MENU_FONT, with_alpha(team_text_color(team), int(l.alpha)))
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

// Where `anchor` is in the layout: its icon's place, or the corner's.
@(private)
anchor_of :: proc(l: ^res.Hud_Layout, anchor: res.Hud_Anchor) -> [2]f32 {
	switch anchor {
	case .Corner: return {}
	case .Health: return f32s(l.health.icon.at)
	case .Ammo:   return f32s(l.ammo.icon.at)
	case .Jet:    return f32s(l.jet.icon.at)
	}
	return {}
}

// Where `place` is, in the layout beside `anchor`: as far from it as there, the anchor
// spread across the view.
@(private)
anchored :: proc(u: ^ui.Ui, anchor, place: [2]f32) -> [2]f32 {
	return {anchor.x * wide(u) + place.x - anchor.x, place.y}
}

// Where an anchor itself is, spread across the view: what what is placed beside it is
// drawn about, unscaled.
@(private = "file")
spread :: proc(u: ^ui.Ui, anchor: [2]f32) -> [2]f32 {
	return anchored(u, anchor, anchor)
}

@(private = "file")
aligned :: proc(u: ^ui.Ui, at: [2]f32) -> [2]f32 {
	return {align(u, at.x), align(u, at.y)}
}

@(private)
f32s :: proc(v: [2]i32) -> [2]f32 {
	return {f32(v.x), f32(v.y)}
}

// An icon at its place across the view, turned as the layout says, `by` as big about it.
@(private = "file")
icon :: proc(u: ^ui.Ui, image: draw.Sprite, place: res.Hud_Icon, tint: rl.Color, by: f32) {
	at := aligned(u, spread(u, f32s(place.at)))
	z := zoom_around(u, at, by)
	defer zoom_end(z)
	picture(u, image, at, tint, angle = math.to_radians(f32(place.rotate)))
}

// A text at its place beside its anchor, starting there or ending there, `by` as big
// about the anchor.
@(private = "file")
text :: proc(u: ^ui.Ui, l: ^res.Hud_Layout, place: res.Hud_Text, words: string, font: Lettering, color: rl.Color, by: f32) {
	anchor := anchor_of(l, place.anchor)
	z := zoom_around(u, spread(u, anchor), by)
	defer zoom_end(z)
	at := anchored(u, anchor, f32s(place.at))
	if place.align == .Right do at.x -= text_width(u, words, font)
	write(u, words, at, font, with_alpha(color, int(l.alpha)))
}

// The original's RenderBar: the bar's image cut to the `share` of it, beside `anchor`,
// turned about its top-left. Across, forward growing from its left, backward from its
// right shrinking toward its left; down, forward growing up from its bottom, backward its
// top shown shrinking toward its bottom, as the original draws them. Nothing for a bar
// shown as a number.
@(private = "file")
bar :: proc(u: ^ui.Ui, image: draw.Sprite, anchor: [2]f32, layout: res.Hud_Bar, share: f32, fill: res.Hud_Fill, tint: rl.Color, by: f32) {
	if layout.style == .Number do return
	p := clamp(share, 0, 1)
	place := f32s(layout.at)
	z := zoom_around(u, aligned(u, spread(u, anchor)), by)
	defer zoom_end(z)
	at := [2]f32{align(u, anchor.x * wide(u)) + place.x - anchor.x, align(u, anchor.y) + place.y - anchor.y}
	part: rl.Rectangle
	switch {
	case layout.style == .Down && fill == .Forward:
		part = {0, 1 - p, 1, p}
		at.y += image.size.y * (1 - p)
	case layout.style == .Down:
		part = {0, 0, 1, p}
		at.y += image.size.y * (1 - p)
	case fill == .Forward:
		part = {0, 0, p, 1}
	case:
		part = {1 - p, 0, p, 1}
	}
	picture(u, image, at, tint, angle = math.to_radians(f32(layout.rotate)), part = part)
}

// A bar shown as a number: its share, a whole percent, at its place beside `anchor`, `by`
// as big about it.
@(private = "file")
percent :: proc(u: ^ui.Ui, anchor: [2]f32, place: [2]i32, share: f32, color: rl.Color, by: f32) {
	z := zoom_around(u, spread(u, anchor), by)
	defer zoom_end(z)
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
