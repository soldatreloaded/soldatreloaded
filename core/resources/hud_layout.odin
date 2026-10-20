package resources

import "core:encoding/json"
import "core:log"
import "core:strings"

// A mod's HUD layout, hud/layout.json (docs/srmod.md): Soldat 1's setup.sif
// (Interface_Setup) made readable, and explicit where the original worked things out as
// it drew. Each bar, text and the grenades say what they are anchored to as the view
// widens (an icon, or the layout's corner), which way each bar fills, and how each text
// is aligned: the original chose these by which pictures an interface had and whether it
// was custom at all. Positions are in the 640 by 480 layout, turns in degrees about the
// picture's top-left. A key a layout leaves out is Classic's layout's.

HUD_LAYOUT_FILE :: "layout.json"

// What a part is kept beside as the view widens: an icon, spread across the view with
// it; or the layout's corner, so the part stays where it is.
Hud_Anchor :: enum {
	Corner,
	Health,
	Ammo,
	Jet,
}

// How a bar shows its share: a number ("75%"), or its picture cut across or down. The
// grenades: their count, or a row of them, or a column.
Hud_Bar_Style :: enum {
	Number,
	Across,
	Down,
}

// Which way a bar fills: forward, growing from its left, or up from its bottom; backward,
// shrinking toward its left, or its top shown shrinking toward its bottom (the original's
// custom interfaces').
Hud_Fill :: enum {
	Forward,
	Backward,
}

// Where a text is at its place: starting there, or ending there.
Hud_Align :: enum {
	Left,
	Right,
}

Hud_Icon :: struct {
	at:     [2]i32,
	rotate: i32,
}

Hud_Bar :: struct {
	at:     [2]i32,
	size:   [2]i32, // kept as the original keeps it; the picture's own size is drawn
	style:  Hud_Bar_Style,
	fill:   Hud_Fill,
	rotate: i32,
	anchor: Hud_Anchor,
}

// An icon and its bar.
Hud_Gauge :: struct {
	shown: bool,
	icon:  Hud_Icon,
	bar:   Hud_Bar,
}

// The ammo's: its bar shows the clip, and the reload while it is empty, which fills its
// own way.
Hud_Ammo :: struct {
	shown:       bool,
	icon:        Hud_Icon,
	bar:         Hud_Bar,
	reload_fill: Hud_Fill,
}

// The wait between shots: a frame, and the bar in it, anchored as the bar is.
Hud_Fire :: struct {
	shown: bool,
	frame: Hud_Icon,
	bar:   Hud_Bar,
}

Hud_Vest :: struct {
	shown: bool,
	bar:   Hud_Bar,
}

Hud_Nades :: struct {
	shown:  bool,
	at:     [2]i32,
	size:   [2]i32,
	style:  Hud_Bar_Style, // their count, a row, or a column
	anchor: Hud_Anchor,
}

Hud_Text :: struct {
	shown:  bool,
	at:     [2]i32,
	align:  Hud_Align,
	anchor: Hud_Anchor,
}

// A part placed across the view as the view widens.
Hud_Place :: struct {
	shown: bool,
	at:    [2]i32,
}

Hud_Layout :: struct {
	alpha:    u8, // the HUD's pictures' and texts'
	health:   Hud_Gauge,
	ammo:     Hud_Ammo,
	jet:      Hud_Gauge,
	vest:     Hud_Vest,
	fire:     Hud_Fire,
	nades:    Hud_Nades,
	bullets:  Hud_Text, // the rounds left
	weapon:   Hud_Text, // the weapon's name
	team_box: Hud_Place,
	ping:     Hud_Place,
	status:   Hud_Place, // my place, my kills and the limit
}

// The game's own layout: the original's default interface.
hud_layout_default :: proc() -> Hud_Layout {
	return hud_layout_of(INTERFACE_DEFAULT, {health = .Health, jet = .Jet, ammo = .Ammo, fire = .Ammo, nades = .Ammo}, custom = false)
}

// A Soldat 1 layout as ours, its anchoring (Interface_Anchoring) and, `custom`, its
// alignment as the original works them out: written down.
hud_layout_of :: proc(setup: Interface_Setup, anchoring: Interface_Anchoring, custom: bool) -> (layout: Hud_Layout) {
	s := setup
	forward := Hud_Fill.Backward if custom else .Forward
	align := Hud_Align.Left if custom else .Right
	layout.alpha = s.alpha
	layout.health = {
		shown = .Health in s.shown,
		icon  = icon_from(s.health_icon),
		bar   = bar_from(s.health_bar, forward, anchoring.health),
	}
	layout.ammo = {
		shown       = .Ammo in s.shown,
		icon        = icon_from(s.ammo_icon),
		bar         = bar_from(s.ammo_bar, forward, anchoring.ammo),
		reload_fill = .Forward,
	}
	layout.jet = {
		shown = .Jet in s.shown,
		icon  = icon_from(s.jet_icon),
		bar   = bar_from(s.jet_bar, forward, anchoring.jet),
	}
	layout.vest = {shown = .Vest in s.shown, bar = bar_from(s.vest_bar, forward, anchoring.health)}
	// the frame at the fire bar's place and turn, the bar at the fire icon's (sic)
	fire := bar_from(s.fire_bar, .Backward, anchoring.fire)
	fire.at, fire.rotate = s.fire_icon.at, s.fire_icon.rotate
	layout.fire = {shown = .Fire in s.shown, frame = {at = s.fire_bar.at, rotate = s.fire_bar.rotate}, bar = fire}
	layout.nades = {shown = .Nades in s.shown, at = s.nades.at, size = s.nades.size, style = style_from(s.nades.style), anchor = anchoring.nades}
	layout.bullets = {shown = .Bullets in s.shown, at = s.bullets, align = align, anchor = anchoring.ammo}
	layout.weapon = {shown = .Weapon in s.shown, at = s.weapon, align = align, anchor = anchoring.ammo}
	layout.team_box = {shown = .Team in s.shown, at = s.team_box}
	layout.ping = {shown = .Ping in s.shown, at = s.ping}
	layout.status = {shown = .Status in s.shown, at = s.status}
	return

	icon_from :: proc(i: Interface_Icon) -> Hud_Icon {return {at = i.at, rotate = i.rotate}}
	style_from :: proc(s: Bar_Style) -> Hud_Bar_Style {
		switch s {
		case .Text:       return .Number
		case .Horizontal: return .Across
		case .Vertical:   return .Down
		}
		return .Across
	}
	bar_from :: proc(b: Interface_Bar, fill: Hud_Fill, anchor: Hud_Anchor) -> Hud_Bar {
		return {at = b.at, size = b.size, style = style_from(b.style), fill = fill, rotate = b.rotate, anchor = anchor}
	}
}

// Our layout as Soldat 1's setup.sif, for an interface to take back to it: what it can
// hold of it. Soldat 1 has no say in the anchors, the fills or the alignment, which it
// works out for itself.
hud_layout_setup :: proc(layout: Hud_Layout) -> (s: Interface_Setup) {
	l := layout
	s.alpha = l.alpha
	if l.health.shown do s.shown += {.Health}
	if l.ammo.shown do s.shown += {.Ammo}
	if l.vest.shown do s.shown += {.Vest}
	if l.jet.shown do s.shown += {.Jet}
	if l.nades.shown do s.shown += {.Nades}
	if l.bullets.shown do s.shown += {.Bullets}
	if l.weapon.shown do s.shown += {.Weapon}
	if l.fire.shown do s.shown += {.Fire}
	if l.team_box.shown do s.shown += {.Team}
	if l.ping.shown do s.shown += {.Ping}
	if l.status.shown do s.shown += {.Status}
	s.health_icon = {at = l.health.icon.at, rotate = l.health.icon.rotate}
	s.health_bar = bar_to(l.health.bar)
	s.ammo_icon = {at = l.ammo.icon.at, rotate = l.ammo.icon.rotate}
	s.ammo_bar = bar_to(l.ammo.bar)
	s.jet_icon = {at = l.jet.icon.at, rotate = l.jet.icon.rotate}
	s.jet_bar = bar_to(l.jet.bar)
	s.vest_bar = bar_to(l.vest.bar)
	s.nades = {at = l.nades.at, size = l.nades.size, style = style_to(l.nades.style)}
	s.bullets = l.bullets.at
	s.weapon = l.weapon.at
	s.fire_icon = {at = l.fire.bar.at, rotate = l.fire.bar.rotate}
	s.fire_bar = bar_to(l.fire.bar)
	s.fire_bar.at, s.fire_bar.rotate = l.fire.frame.at, l.fire.frame.rotate
	s.team_box = l.team_box.at
	s.ping = l.ping.at
	s.status = l.status.at
	return

	style_to :: proc(s: Hud_Bar_Style) -> Bar_Style {
		switch s {
		case .Number: return .Text
		case .Across: return .Horizontal
		case .Down:   return .Vertical
		}
		return .Horizontal
	}
	bar_to :: proc(b: Hud_Bar) -> Interface_Bar {
		return {at = b.at, size = b.size, style = style_to(b.style), rotate = b.rotate}
	}
}

// layout.json's text over `layout`, as a config is read: a key it leaves out, or holds a
// value its setting can't take, keeps what `layout` had, logged. `name` says where it
// came from. False if it isn't JSON at all, and `layout` as it was.
hud_layout_read :: proc(text: []byte, name: string, layout: ^Hud_Layout) -> bool {
	read := layout^
	result, _, _ := config_read_text(text, name, &read, context.temp_allocator)
	if result != .Read do return false
	layout^ = read
	return true
}

// The layout as layout.json's text, every key written: with the temp allocator.
hud_layout_text :: proc(layout: Hud_Layout) -> string {
	options := json.Marshal_Options {
		spec       = .JSON,
		pretty     = true,
		use_spaces = true,
		spaces     = 2,
	}
	b := strings.builder_make(context.temp_allocator)
	if err := json.marshal_to_builder(&b, layout, &options); err != nil {
		log.errorf("layout.json: %v", err)
		return ""
	}
	strings.write_byte(&b, '\n')
	return strings.to_string(b)
}

// The HUD's layout worn: the game's own, under Classic's layout.json, under the chosen
// mod's.
worn_layout :: proc(worn: ^Worn) -> (layout: Hud_Layout) {
	layout = hud_layout_default()
	over :: proc(layout: ^Hud_Layout, mod: ^Srmod) -> bool {
		file := srmod_file(mod, .Hud, HUD_LAYOUT_FILE) or_return
		text := mod_read(file, context.temp_allocator) or_return
		return hud_layout_read(text, mod_file_name(file), layout)
	}
	over(&layout, &worn.classic)
	if i := worn.chosen[.Hud]; i >= 0 do over(&layout, &worn.mods[i])
	return
}

// How the description of a mod the HUD editor made begins: one that begins so is the
// editor's, saved over as it is edited again.
HUD_EDITOR_MADE :: "Made in the HUD editor"

// The mod `name` made in `mods_dir`, over one by that name: a mod of a hud alone,
// `layout` its layout.json and `pictures` (srmod_part_files of the hud it was made from)
// beside it, each at its scale in `scales` (by the same path; SRMOD_SCALE if not there),
// `description` its own. False if it couldn't be written.
hud_mod_write :: proc(mods_dir, name, title, description: string, layout: Hud_Layout, pictures: map[string][]byte, scales: map[string]f32 = nil) -> bool {
	entries := make(map[string][]byte, context.temp_allocator)
	in_mod := make(map[string]f32, context.temp_allocator)
	for path, data in pictures {
		if strings.equal_fold(path, HUD_LAYOUT_FILE) do continue
		dest := strings.concatenate({PART_NAMES[.Hud], "/", path}, context.temp_allocator)
		entries[dest] = data
		if scale, has := scales[path]; has do in_mod[dest] = scale
	}
	entries[strings.concatenate({PART_NAMES[.Hud], "/", HUD_LAYOUT_FILE}, context.temp_allocator)] = transmute([]byte)hud_layout_text(layout)
	return srmod_write(mods_dir, name, title, description, entries, in_mod)
}

// The scale of each of `pictures` (srmod_part_files of the mod's hud), by the same path:
// with `allocator`.
hud_picture_scales :: proc(mod: ^Srmod, pictures: map[string][]byte, allocator := context.allocator) -> map[string]f32 {
	scales := make(map[string]f32, allocator)
	for path in pictures do scales[strings.clone(path, allocator)] = srmod_scale(mod, strings.concatenate({PART_NAMES[.Hud], "/", path}, context.temp_allocator))
	return scales
}
