package resources

import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import "../utils"

// Soldat 1's custom interfaces: the HUD's layout and pictures, each a folder or a .sint
// (a zip of one) in interfaces/, the game's own when none is worn
// (graphics.interface). As the original's custom-interfaces/<name>/ (InterfaceGraphics.pas,
// GameRendering.pas):
//
//   setup.sif   the layout: the TInterface record written whole, 240 bytes, little-endian,
//               each field at its natural alignment (Interface_Setup, sif_read)
//   *.bmp/.png  any of the pictures the original takes from one (INTERFACE_PICTURES), at
//               its root; one it hasn't is the mods' own
//   mod.ini     [SCALE], as a mod's, the pictures' pixels to a unit; 1 where it doesn't say
//
// An interface without a setup.sif is no interface: the game's own is worn, as the
// original falls back to its default.

INTERFACES_DIR :: "interfaces"
INTERFACE_EXTENSION :: ".sint"
INTERFACE_SETUP_FILE :: "setup.sif"
INTERFACE_SETUP_SIZE :: 240

// The pictures of interface-gfx a custom interface may have its own of, by their names
// there: the original's CUSTOM_FIRST to CUSTOM_LAST.
@(rodata)
INTERFACE_PICTURES := [?]string {
	"cursor", "health", "ammo", "jet", "health-bar", "jet-bar", "reload-bar", "back", "overlay",
	"nade", "noflag", "flag", "cluster-nade", "dot", "fire-bar", "fire-bar-r", "vest-bar",
	"menucursor", "arrow", "title-l", "title-r",
}

// How a bar shows its share: as a number ("75%"), or as its picture cut across or down.
Bar_Style :: enum u8 {
	Text       = 0,
	Horizontal = 1,
	Vertical   = 2,
}

// The parts of the HUD an interface shows.
Interface_Part :: enum {
	Health,
	Ammo,
	Vest,
	Jet,
	Nades,
	Bullets,
	Weapon,
	Fire,
	Team,
	Ping,
	Status,
}
Interface_Parts :: bit_set[Interface_Part]

// A picture's place, in the 640 by 480 layout, and its turn, degrees about its top-left.
Interface_Icon :: struct {
	at:     [2]i32,
	rotate: i32,
}

// A bar's place, its size (which the original keeps but draws by its picture's), how it
// shows its share, and its turn. The grenades are a bar too, their style placing them in
// a row or a column; they have no turn.
Interface_Bar :: struct {
	at:     [2]i32,
	size:   [2]i32,
	style:  Bar_Style,
	rotate: i32,
}

// The layout, setup.sif's: the original's TInterface, field for field.
Interface_Setup :: struct {
	alpha:       u8, // the HUD's pictures' and texts' alpha
	shown:       Interface_Parts,
	health_icon: Interface_Icon,
	health_bar:  Interface_Bar,
	ammo_icon:   Interface_Icon,
	ammo_bar:    Interface_Bar,
	jet_icon:    Interface_Icon,
	jet_bar:     Interface_Bar,
	vest_bar:    Interface_Bar,
	nades:       Interface_Bar,
	bullets:     [2]i32, // the rounds left, a text
	weapon:      [2]i32, // the weapon's name
	fire_icon:   Interface_Icon, // the fire bar's own place and turn, its frame's not (sic)
	fire_bar:    Interface_Bar,  // the fire bar's frame's place and turn, and the bar's size and style (sic)
	team_box:    [2]i32,
	ping:        [2]i32,
	status:      [2]i32,
}

// The game's own layout, the original's LoadDefaultInterfaceData.
@(rodata)
INTERFACE_DEFAULT := Interface_Setup {
	alpha       = 255,
	shown       = ~Interface_Parts{},
	health_icon = {at = {5, 439}},
	health_bar  = {at = {45, 449}, size = {115, 9}, style = .Horizontal},
	ammo_icon   = {at = {275, 439}},
	ammo_bar    = {at = {352, 449}, size = {120, 9}, style = .Horizontal},
	jet_icon    = {at = {480, 439}},
	jet_bar     = {at = {520, 449}, size = {115, 9}, style = .Horizontal},
	vest_bar    = {at = {45, 459}, size = {115, 9}, style = .Horizontal},
	nades       = {at = {308, 462}, size = {10, 10}, style = .Horizontal},
	bullets     = {348, 451},
	weapon      = {285, 454},
	fire_icon   = {at = {409, 464}},
	fire_bar    = {at = {402, 464}, size = {57, 4}, style = .Horizontal},
	team_box    = {575, 330},
	ping        = {600, 18},
	status      = {575, 421},
}

// The places across the view that the parts are kept beside as it widens: each bar,
// text and the grenades as far from its anchor as the layout has them, the anchor spread
// across the view with it (the original's relinfo).
// What each part is kept beside: an icon, or the layout's corner.
Interface_Anchoring :: struct {
	health, jet, ammo, fire, nades: Hud_Anchor,
}

Interface_Anchors :: struct {
	health, jet, ammo, fire, nades: [2]f32,
}

// An interface worn: its files, its layout, and how its parts are drawn.
Interface :: struct {
	name:    string, // "" for the game's own
	custom:  bool,   // one of interfaces/, worn: else the game's own
	layer:   Mod_Layer, // its folder or its .sint, the pictures at its root
	setup:   Interface_Setup,
	anchoring: Interface_Anchoring, // what each part is anchored to
	anchors: Interface_Anchors, // and where that is
}

// The game's own interface: its own layout, its pictures the mods'.
interface_default :: proc() -> (iface: Interface) {
	iface.setup = INTERFACE_DEFAULT
	iface.anchoring = anchoring_of(&iface)
	iface.anchors = anchors_of(&iface)
	return
}

// The interface `name` in `dir`, its folder, else its .sint: its layout read, its
// pictures found there as they are asked for. The game's own, logged, if it isn't there
// or its setup.sif can't be read; and for "". Free with interface_close.
interface_open :: proc(dir, name: string, allocator := context.allocator) -> (iface: Interface) {
	context.allocator = allocator
	if name == "" do return interface_default()
	layer, found := interface_layer(dir, name)
	if !found {
		log.warnf("no interface %s in %s/: the game's own is worn", name, dir)
		return interface_default()
	}
	iface = {name = strings.clone(name), custom = true, layer = layer}
	setup, ok := setup_of(&iface.layer)
	if !ok {
		log.warnf("the interface %s has no setup.sif to read: the game's own is worn", name)
		interface_close(&iface)
		return interface_default()
	}
	iface.setup = setup
	config, _ := mod_config_read(&iface.layer, default_scale = 1)
	iface.layer.config = new_clone(config)
	iface.layer.own_config = true
	iface.anchoring = anchoring_of(&iface)
	iface.anchors = anchors_of(&iface)
	return

	setup_of :: proc(layer: ^Mod_Layer) -> (setup: Interface_Setup, ok: bool) {
		file := layer_file(layer, 0, INTERFACE_SETUP_FILE) or_return
		data := mod_read(file, context.temp_allocator) or_return
		return interface_setup_read(data)
	}
}

interface_close :: proc(iface: ^Interface, allocator := context.allocator) {
	context.allocator = allocator
	if iface.layer.config != nil {
		mod_config_destroy(iface.layer.config)
		free(iface.layer.config)
	}
	layer_close(&iface.layer)
	delete(iface.name)
	iface^ = {}
}

// The interface's own picture `name` of interface-gfx ("health.png"), found as a mod's
// are, a .png of it first, then a .bmp; and its pixels to a unit, by its mod.ini. None
// for the game's own, and for a picture the original takes from no interface.
interface_picture :: proc(iface: ^Interface, name: string, listings: ^utils.Dir_Listings = nil) -> (file: Mod_File, scale: f32, found: bool) {
	if iface == nil || !iface.custom do return
	stem := strings.to_lower(strings.trim_suffix(name, ".png"), context.temp_allocator)
	slice.contains(INTERFACE_PICTURES[:], stem) or_return
	file = layer_find(&iface.layer, INTERFACE_LAYER, "", name, ".png", listings) or_return
	key := strings.to_lower(file.path[strings.last_index_any(file.path, "/\\") + 1:], context.temp_allocator)
	scale = iface.layer.config.scale.default
	if value, has := iface.layer.config.scale.paths[key]; has && value > 0 do scale = value
	if scale <= 0 do scale = 1
	return file, scale, true
}

// The layer a picture of an interface is said to be of: none of the mods'.
INTERFACE_LAYER :: -2

// The interfaces in `dir`, by name: each folder and .sint, a folder before a .sint of its
// name, which it hides. With the temp allocator.
interfaces_list :: proc(dir: string) -> []string {
	names := make([dynamic]string, context.temp_allocator)
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return nil
	for entry in entries {
		name := entry.name
		if strings.has_prefix(name, ".") do continue
		if entry.type != .Directory {
			if !strings.has_suffix(strings.to_lower(name, context.temp_allocator), INTERFACE_EXTENSION) do continue
			name = name[:len(name) - len(INTERFACE_EXTENSION)]
		}
		if !slice.contains(names[:], name) do append(&names, name)
	}
	slice.sort(names[:])
	return names[:]
}

// setup.sif's bytes as the layout; false if there are too few of them.
interface_setup_read :: proc(data: []byte) -> (setup: Interface_Setup, ok: bool) {
	if len(data) < INTERFACE_SETUP_SIZE do return
	sif := (^Sif)(raw_data(data))^
	setup.alpha = sif.alpha
	for part in Interface_Part do if sif.shown[part] != 0 do setup.shown += {part}
	setup.health_icon = icon_of(sif.health_icon, sif.health_icon_rotate)
	setup.health_bar = bar_of(sif.health_bar)
	setup.ammo_icon = icon_of(sif.ammo_icon, sif.ammo_icon_rotate)
	setup.ammo_bar = bar_of(sif.ammo_bar)
	setup.jet_icon = icon_of(sif.jet_icon, sif.jet_icon_rotate)
	setup.jet_bar = bar_of(sif.jet_bar)
	setup.vest_bar = bar_of(sif.vest_bar)
	setup.nades = {at = pair(sif.nades), size = pair(sif.nades_size), style = Bar_Style(sif.nades_style)}
	setup.bullets = pair(sif.bullets)
	setup.weapon = pair(sif.weapon)
	setup.fire_icon = icon_of(sif.fire_icon, sif.fire_icon_rotate)
	setup.fire_bar = bar_of(sif.fire_bar)
	setup.team_box = pair(sif.team_box)
	setup.ping = pair(sif.ping)
	setup.status = pair(sif.status)
	for bar in ([?]^Interface_Bar{&setup.health_bar, &setup.ammo_bar, &setup.jet_bar, &setup.vest_bar, &setup.nades, &setup.fire_bar}) {
		if u8(bar.style) > u8(max(Bar_Style)) do bar.style = .Horizontal // as the original, which draws any but these as a bar
	}
	return setup, true
}

// The layout as setup.sif's bytes, which the original reads as it is: with the temp
// allocator.
interface_setup_write :: proc(setup: Interface_Setup) -> []byte {
	sif: Sif
	sif.alpha = setup.alpha
	for part in Interface_Part do sif.shown[part] = 1 if part in setup.shown else 0
	sif.health_icon, sif.health_icon_rotate = le(setup.health_icon.at), i32le(setup.health_icon.rotate)
	sif.health_bar = sif_bar(setup.health_bar)
	sif.ammo_icon, sif.ammo_icon_rotate = le(setup.ammo_icon.at), i32le(setup.ammo_icon.rotate)
	sif.ammo_bar = sif_bar(setup.ammo_bar)
	sif.jet_icon, sif.jet_icon_rotate = le(setup.jet_icon.at), i32le(setup.jet_icon.rotate)
	sif.jet_bar = sif_bar(setup.jet_bar)
	sif.vest_bar = sif_bar(setup.vest_bar)
	sif.nades, sif.nades_size, sif.nades_style = le(setup.nades.at), le(setup.nades.size), u8(setup.nades.style)
	sif.bullets = le(setup.bullets)
	sif.weapon = le(setup.weapon)
	sif.fire_icon, sif.fire_icon_rotate = le(setup.fire_icon.at), i32le(setup.fire_icon.rotate)
	sif.fire_bar = sif_bar(setup.fire_bar)
	sif.team_box = le(setup.team_box)
	sif.ping = le(setup.ping)
	sif.status = le(setup.status)
	data := make([]byte, INTERFACE_SETUP_SIZE, context.temp_allocator)
	(^Sif)(raw_data(data))^ = sif
	return data
}

// ---------------------------------------------------------------------------------
// setup.sif, byte for byte: the original's TInterface as Delphi and Free Pascal lay it
// out, each Integer at a multiple of 4, a Byte or a Boolean anywhere, so three bytes
// pad each bar's style before its turn and the grenades' before the rounds' place.

@(private = "file")
Sif :: struct #packed {
	alpha:              u8,
	shown:              [Interface_Part]u8, // Health, Ammo, Vest, Jet, Nades, Bullets, Weapon, Fire, Team, Ping, Status
	health_icon:        [2]i32le,
	health_icon_rotate: i32le,
	health_bar:         Sif_Bar,
	ammo_icon:          [2]i32le,
	ammo_icon_rotate:   i32le,
	ammo_bar:           Sif_Bar,
	jet_icon:           [2]i32le,
	jet_icon_rotate:    i32le,
	jet_bar:            Sif_Bar,
	vest_bar:           Sif_Bar,
	nades:              [2]i32le,
	nades_size:         [2]i32le,
	nades_style:        u8,
	_:                  [3]u8,
	bullets:            [2]i32le,
	weapon:             [2]i32le,
	fire_icon:          [2]i32le,
	fire_icon_rotate:   i32le,
	fire_bar:           Sif_Bar,
	team_box:           [2]i32le,
	ping:               [2]i32le,
	status:             [2]i32le,
}

@(private = "file")
Sif_Bar :: struct #packed {
	at:     [2]i32le,
	size:   [2]i32le,
	style:  u8,
	_:      [3]u8,
	rotate: i32le,
}

#assert(size_of(Sif) == INTERFACE_SETUP_SIZE)

@(private = "file")
pair :: proc(v: [2]i32le) -> [2]i32 {
	return {i32(v.x), i32(v.y)}
}

@(private = "file")
le :: proc(v: [2]i32) -> [2]i32le {
	return {i32le(v.x), i32le(v.y)}
}

@(private = "file")
icon_of :: proc(at: [2]i32le, rotate: i32le) -> Interface_Icon {
	return {at = pair(at), rotate = i32(rotate)}
}

@(private = "file")
bar_of :: proc(b: Sif_Bar) -> Interface_Bar {
	return {at = pair(b.at), size = pair(b.size), style = Bar_Style(b.style), rotate = i32(b.rotate)}
}

@(private = "file")
sif_bar :: proc(b: Interface_Bar) -> Sif_Bar {
	return {at = le(b.at), size = le(b.size), style = u8(b.style), rotate = i32le(b.rotate)}
}

// ---------------------------------------------------------------------------------

// What each part is anchored to, as the original's LoadInterfaceData has it: the game's
// own, each bar by its icon and the fire bar and the grenades by the ammo's. A custom
// one's go by the icons it has pictures of, the original's way: each by its own icon if
// it has its picture, and the fire bar and the grenades by the last of the health's, the
// jet's and the ammo's that it has; by none, the layout's corner, if it has none of them.
@(private = "file")
anchoring_of :: proc(iface: ^Interface) -> (anchoring: Interface_Anchoring) {
	if !iface.custom do return {health = .Health, jet = .Jet, ammo = .Ammo, fire = .Ammo, nades = .Ammo}
	has :: proc(iface: ^Interface, name: string) -> bool {
		_, found := layer_find(&iface.layer, INTERFACE_LAYER, "", name, ".png")
		return found
	}
	all := Hud_Anchor.Corner
	if has(iface, "health.bmp") do all = .Health
	if has(iface, "jet.bmp") do all = .Jet
	if has(iface, "ammo.bmp") do all = .Ammo
	anchoring = {health = all, jet = all, ammo = all, fire = all, nades = all}
	if has(iface, "health.bmp") do anchoring.health = .Health
	if has(iface, "jet.bmp") do anchoring.jet = .Jet
	if has(iface, "ammo.bmp") do anchoring.ammo = .Ammo
	return
}

// Where each part's anchor is, in the layout.
@(private = "file")
anchors_of :: proc(iface: ^Interface) -> Interface_Anchors {
	a := &iface.anchoring
	s := &iface.setup
	return {
		health = anchor_at(s, a.health),
		jet    = anchor_at(s, a.jet),
		ammo   = anchor_at(s, a.ammo),
		fire   = anchor_at(s, a.fire),
		nades  = anchor_at(s, a.nades),
	}
}

// Where `anchor` is in the layout of `setup`: its icon's place, or the corner's.
anchor_at :: proc(setup: ^Interface_Setup, anchor: Hud_Anchor) -> [2]f32 {
	switch anchor {
	case .Corner: return {}
	case .Health: return f32s(setup.health_icon.at)
	case .Ammo:   return f32s(setup.ammo_icon.at)
	case .Jet:    return f32s(setup.jet_icon.at)
	}
	return {}
}

@(private = "file")
f32s :: proc(v: [2]i32) -> [2]f32 {
	return {f32(v.x), f32(v.y)}
}

// The interface `name` in `dir`: its folder, its root where its setup.sif is, two
// folders down at most; else its .sint, its root the same.
@(private = "file")
interface_layer :: proc(dir, name: string) -> (layer: Mod_Layer, found: bool) {
	folder := utils.temp_path(dir, name)
	if os.is_dir(folder) do return {name = strings.clone(name), dir = strings.clone(marker_folder(folder, INTERFACE_SETUP_FILE))}, true
	path := strings.concatenate({folder, INTERFACE_EXTENSION}, context.temp_allocator)
	if !os.is_file(path) {
		// any case of the extension
		for entry in os.read_all_directory_by_path(dir, context.temp_allocator) or_else nil {
			if strings.equal_fold(entry.name, strings.concatenate({name, INTERFACE_EXTENSION}, context.temp_allocator)) {
				path = utils.temp_path(dir, entry.name)
			}
		}
		if !os.is_file(path) do return
	}
	a := archive_open_at(path, INTERFACE_SETUP_FILE) or_return
	return {name = strings.clone(name), archive = a}, true
}


// ---------------------------------------------------------------------------------
// Brought in from a Soldat 1

// The custom interfaces of the Soldat 1 folders `dirs` (an install, a mod of its mods/),
// each in its custom-interfaces/ as a folder or a .sint, each made a .srmod of its own in
// `mods_dir`: its hud (its setup.sif as layout.json, its anchors and alignment as Soldat
// 1 works them out, written down; and the HUD's pictures of its own) and its icons (the
// rest of its pictures), each picture brought from its scale to SRMOD_SCALE, see-through
// where it was green. Named as it was, but for what a mod's name can't have (made `_`);
// one by a name a mod has already, one 1.7.1 ships with as it came, and the original's
// own Default, left as they are.
// The names made, with the temp allocator.
interfaces_import :: proc(dirs: []string, mods_dir: string) -> []string {
	made := make([dynamic]string, context.temp_allocator)
	for dir in dirs {
		from := utils.temp_path(dir, "custom-interfaces")
		entries, err := os.read_all_directory_by_path(from, context.temp_allocator)
		if err != nil do continue
		for entry in entries {
			title := entry.name
			if entry.type != .Directory {
				if !strings.has_suffix(strings.to_lower(title, context.temp_allocator), INTERFACE_EXTENSION) do continue
				title = title[:len(title) - len(INTERFACE_EXTENSION)]
			}
			if title == "" || strings.has_prefix(title, ".") || strings.equal_fold(title, "default") do continue
			if entry.type == .Directory && folder_is_stock(entry.fullpath) do continue // one 1.7.1 ships with, untouched: nobody's
			name := mod_name_from(title)
			if name == "" || mod_exists(mods_dir, name) || slice.contains(made[:], name) do continue
			if interface_import(from, title, mods_dir, name) do append(&made, name)
		}
	}
	return made[:]
}

// The interface `title` of `from` as the .srmod `name` in `mods_dir`. False if it has
// no setup.sif, or can't be written.
@(private = "file")
interface_import :: proc(from, title, mods_dir, name: string) -> bool {
	iface := interface_open(from, title, context.temp_allocator)
	defer interface_close(&iface, context.temp_allocator)
	if !iface.custom do return false
	entries := make(map[string][]byte, context.temp_allocator)
	layout := hud_layout_of(iface.setup, iface.anchoring, custom = true)
	entries[strings.concatenate({PART_NAMES[.Hud], "/", HUD_LAYOUT_FILE}, context.temp_allocator)] = transmute([]byte)hud_layout_text(layout)
	for stem in INTERFACE_PICTURES {
		file, scale, found := interface_picture(&iface, strings.concatenate({stem, ".png"}, context.temp_allocator))
		if !found do continue
		data := mod_read(file, context.temp_allocator) or_continue
		texture := texture_decode(data, COLOR_KEY, context.temp_allocator) or_continue
		texture = texture_rescale(texture, SRMOD_SCALE / scale)
		part := Part.Hud if slice.contains(HUD_PICTURES[:], stem) else .Icons
		entries[strings.concatenate({PART_NAMES[part], "/", stem, ".png"}, context.temp_allocator)] = texture_png(texture)
	}
	return srmod_write(mods_dir, name, fmt.tprintf("%s interface", title), fmt.tprintf("Soldat 1's custom interface %s, its HUD's layout and pictures.", title), entries)
}

// A mod's name made of `title`: what a name can't have (srmod_name_ok) made `_`, at most
// SRMOD_NAME_MAX; Classic's name with _interface after it; "" if nothing is left.
mod_name_from :: proc(title: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]u8)strings.trim_space(title) {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
			strings.write_byte(&b, c)
		case:
			strings.write_byte(&b, '_')
		}
		if strings.builder_len(b) == SRMOD_NAME_MAX do break
	}
	name := strings.to_string(b)
	if strings.equal_fold(name, MOD_CLASSIC) do name = strings.concatenate({name, "_interface"}, context.temp_allocator) // Classic's own name, which no other may have
	return name if srmod_name_ok(name) else ""
}
