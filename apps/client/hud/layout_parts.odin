package hud

import "core:fmt"
import "core:math"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../ui"

// The HUD's parts as the HUD editor (the menu's) places them: where each is drawn, as
// draw_bars and draw_bar_texts draw it, and the layout with one of them moved. An icon
// moved takes along what is anchored to it, as it would as the view widens.

Hud_Part :: enum {
	Health_Icon,
	Health_Bar,
	Ammo_Icon,
	Ammo_Bar,
	Bullets,
	Weapon,
	Nades,
	Fire_Frame,
	Fire_Bar,
	Jet_Icon,
	Jet_Bar,
	Team_Box,
	Status,
}

HUD_PART_NAMES := [Hud_Part]string {
	.Health_Icon = "Health icon",
	.Health_Bar  = "Health bar",
	.Ammo_Icon   = "Ammo icon",
	.Ammo_Bar    = "Ammo bar",
	.Bullets     = "Rounds left",
	.Weapon      = "Weapon name",
	.Nades       = "Grenades",
	.Fire_Frame  = "Fire bar frame",
	.Fire_Bar    = "Fire bar",
	.Jet_Icon    = "Jets icon",
	.Jet_Bar     = "Jets bar",
	.Team_Box    = "Team box",
	.Status      = "Place and kills",
}

// Where `part` is drawn on the view, in units, with `data`'s numbers; its picture's
// box, turned as it is turned.
part_box :: proc(u: ^ui.Ui, art: ^Art, data: ^Hud_Data, part: Hud_Part) -> rl.Rectangle {
	l := &art.layout
	p := &art.pictures
	switch part {
	case .Health_Icon: return icon_box(u, art, .Health, l.health.icon)
	case .Ammo_Icon:   return icon_box(u, art, .Ammo, l.ammo.icon)
	case .Jet_Icon:    return icon_box(u, art, .Jet, l.jet.icon)
	case .Health_Bar:  return bar_box(u, art, .Health_Bar, l.health.bar)
	case .Ammo_Bar:    return bar_box(u, art, .Reload_Bar, l.ammo.bar)
	case .Jet_Bar:     return bar_box(u, art, .Jet_Bar, l.jet.bar)
	case .Fire_Bar:    return bar_box(u, art, .Fire_Bar, l.fire.bar)
	case .Fire_Frame:
		at := anchored(u, anchor_of(l, l.fire.bar.anchor), f32s(l.fire.frame.at))
		return turned_box(at, p[.Fire_Bar_Frame].size, l.fire.frame.rotate, art.opaque[.Fire_Bar_Frame])
	case .Nades:
		base := anchored(u, anchor_of(l, l.nades.anchor), f32s(l.nades.at))
		n := f32(max(data.mine.grenades, 1))
		size, o := p[.Nade].size, art.opaque[.Nade]
		if o.width <= 0 do o = {0, 0, 1, 1}
		switch l.nades.style {
		case .Number: return words_box(u, base, fmt.tprintf("%d", data.mine.grenades), MENU_FONT, .Left)
		case .Across: return {base.x + size.x * (1 + o.x), base.y + size.y * o.y, size.x * (n - 1 + o.width), size.y * o.height}
		case .Down:   return {base.x + size.x * o.x, base.y + size.y * (6 - n + o.y), size.x * o.width, size.y * (n - 1 + o.height)}
		}
	case .Bullets:
		return text_box(u, l, l.bullets, fmt.tprintf("%d", data.mine.ammo), MENU_FONT)
	case .Weapon:
		return text_box(u, l, l.weapon, data.weapon_names[data.mine.weapon], WEAPONS_FONT)
	case .Team_Box:
		return {f32(l.team_box.at.x) * wide(u), f32(l.team_box.at.y), 57, 88}
	case .Status:
		return {f32(l.status.at.x) * wide(u), f32(l.status.at.y), text_width(u, "88 (+88)", SMALL_FONT), 20 + line_height(u, SMALL_FONT)}
	}
	return {}
}

// Whether `part` is shown: its group's switch (a gauge's icon and bar are shown together).
part_shown :: proc(l: ^res.Hud_Layout, part: Hud_Part) -> ^bool {
	switch part {
	case .Health_Icon, .Health_Bar: return &l.health.shown
	case .Ammo_Icon, .Ammo_Bar:     return &l.ammo.shown
	case .Jet_Icon, .Jet_Bar:       return &l.jet.shown
	case .Fire_Frame, .Fire_Bar:    return &l.fire.shown
	case .Nades:                    return &l.nades.shown
	case .Bullets:                  return &l.bullets.shown
	case .Weapon:                   return &l.weapon.shown
	case .Team_Box:                 return &l.team_box.shown
	case .Status:                   return &l.status.shown
	}
	return nil
}

// `part`'s bar, if it is one.
part_bar :: proc(l: ^res.Hud_Layout, part: Hud_Part) -> ^res.Hud_Bar {
	#partial switch part {
	case .Health_Bar: return &l.health.bar
	case .Ammo_Bar:   return &l.ammo.bar
	case .Jet_Bar:    return &l.jet.bar
	case .Fire_Bar:   return &l.fire.bar
	}
	return nil
}

// `part`'s text, if it is one.
part_text :: proc(l: ^res.Hud_Layout, part: Hud_Part) -> ^res.Hud_Text {
	#partial switch part {
	case .Bullets: return &l.bullets
	case .Weapon:  return &l.weapon
	}
	return nil
}

// What `part` is kept beside as the view widens; nil for an icon, the team box and the
// status, which are spread across it themselves. The fire bar's frame is the bar's.
part_anchor :: proc(l: ^res.Hud_Layout, part: Hud_Part) -> ^res.Hud_Anchor {
	if bar := part_bar(l, part); bar != nil do return &bar.anchor
	if text := part_text(l, part); text != nil do return &text.anchor
	#partial switch part {
	case .Nades:      return &l.nades.anchor
	case .Fire_Frame: return &l.fire.bar.anchor
	}
	return nil
}

// How `part` is turned, in degrees, if it can be.
part_rotate :: proc(l: ^res.Hud_Layout, part: Hud_Part) -> ^i32 {
	if bar := part_bar(l, part); bar != nil do return &bar.rotate
	#partial switch part {
	case .Health_Icon: return &l.health.icon.rotate
	case .Ammo_Icon:   return &l.ammo.icon.rotate
	case .Jet_Icon:    return &l.jet.icon.rotate
	case .Fire_Frame:  return &l.fire.frame.rotate
	}
	return nil
}

// Whether `part` is spread across the view as it widens, itself: an icon, the team box,
// the status. A step of the layout's is a step of the view's this much wider (wide).
part_spreads :: proc(part: Hud_Part) -> bool {
	#partial switch part {
	case .Health_Icon, .Ammo_Icon, .Jet_Icon, .Team_Box, .Status: return true
	}
	return false
}

// `start` with `part` moved `by` units on the view `u`: an icon, the team box and the
// status, which are spread across the view, by that much of the layout's 640; an icon
// taking along what is anchored to it.
part_moved :: proc(u: ^ui.Ui, start: res.Hud_Layout, part: Hud_Part, by: [2]f32) -> res.Hud_Layout {
	l := start
	d := [2]i32{i32(math.round(by.x)), i32(math.round(by.y))}
	spread := [2]i32{i32(math.round(by.x / wide(u))), d.y}
	switch part {
	case .Health_Icon:
		l.health.icon.at += spread
		carry(&l, .Health, spread)
	case .Ammo_Icon:
		l.ammo.icon.at += spread
		carry(&l, .Ammo, spread)
	case .Jet_Icon:
		l.jet.icon.at += spread
		carry(&l, .Jet, spread)
	case .Health_Bar, .Ammo_Bar, .Jet_Bar, .Fire_Bar:
		part_bar(&l, part).at += d
	case .Bullets, .Weapon:
		part_text(&l, part).at += d
	case .Nades:      l.nades.at += d
	case .Fire_Frame: l.fire.frame.at += d
	case .Team_Box:   l.team_box.at += spread
	case .Status:     l.status.at += spread
	}
	return l

	carry :: proc(l: ^res.Hud_Layout, anchor: res.Hud_Anchor, by: [2]i32) {
		for bar in ([]^res.Hud_Bar{&l.health.bar, &l.ammo.bar, &l.jet.bar, &l.fire.bar}) {
			if bar.anchor == anchor do bar.at += by
		}
		if l.fire.bar.anchor == anchor do l.fire.frame.at += by
		if l.nades.anchor == anchor do l.nades.at += by
		if l.bullets.anchor == anchor do l.bullets.at += by
		if l.weapon.anchor == anchor do l.weapon.at += by
	}
}

@(private = "file")
icon_box :: proc(u: ^ui.Ui, art: ^Art, picture: Picture, place: res.Hud_Icon) -> rl.Rectangle {
	at := f32s(place.at)
	return turned_box(anchored(u, at, at), art.pictures[picture].size, place.rotate, art.opaque[picture])
}

@(private = "file")
bar_box :: proc(u: ^ui.Ui, art: ^Art, picture: Picture, bar: res.Hud_Bar) -> rl.Rectangle {
	anchor := anchor_of(&art.layout, bar.anchor)
	if bar.style == .Number do return words_box(u, anchored(u, anchor, f32s(bar.at)), "100%", MENU_FONT, .Left)
	place := f32s(bar.at)
	return turned_box({anchor.x * wide(u) + place.x - anchor.x, place.y}, art.pictures[picture].size, bar.rotate, art.opaque[picture])
}

@(private = "file")
text_box :: proc(u: ^ui.Ui, l: ^res.Hud_Layout, place: res.Hud_Text, words: string, font: Lettering) -> rl.Rectangle {
	return words_box(u, anchored(u, anchor_of(l, place.anchor), f32s(place.at)), words, font, place.align)
}

@(private = "file")
words_box :: proc(u: ^ui.Ui, at: [2]f32, words: string, font: Lettering, align: res.Hud_Align) -> rl.Rectangle {
	w := text_width(u, words, font)
	return {at.x - w if align == .Right else at.x, at.y, w, line_height(u, font)}
}

// The box about what is drawn of a picture `size` big with its top-left at `at`, turned
// `degrees` about it: its `opaque` share (Art's), the whole of it if none is known.
@(private = "file")
turned_box :: proc(at, size: [2]f32, degrees: i32, opaque: rl.Rectangle) -> rl.Rectangle {
	o := opaque if opaque.width > 0 else {0, 0, 1, 1}
	angle := math.to_radians(f32(degrees))
	c, s := math.cos(angle), math.sin(angle)
	across, downward := [2]f32{c, s}, [2]f32{-s, c}
	from := at + across * o.x * size.x + downward * o.y * size.y
	along, down := across * o.width * size.x, downward * o.height * size.y
	lo, hi := from, from
	for corner in ([3][2]f32{from + along, from + down, from + along + down}) {
		lo = {min(lo.x, corner.x), min(lo.y, corner.y)}
		hi = {max(hi.x, corner.x), max(hi.y, corner.y)}
	}
	return {lo.x, lo.y, max(hi.x - lo.x, 4), max(hi.y - lo.y, 4)}
}
