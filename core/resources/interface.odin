package resources

import "../utils"

// Soldat 1.7's interface layout, stored as a packed little-endian TInterface in
// interface-gfx/setup.sif. Coordinates are in the original 640 by 480 layout.
Interface_Layout :: struct {
	alpha: i32,
	health, ammo, vest, jet, nades, bullets, weapon, fire, team, ping, status: bool,
	health_icon, health_bar, ammo_icon, ammo_bar, jet_icon, jet_bar: [2]f32,
	fire_icon, fire_bar, nades_at, bullets_at, weapon_at: [2]f32,
	team_box, status_at: [2]f32,
}

interface_default :: proc() -> Interface_Layout {
	return {
		alpha = 255,
		health = true, ammo = true, vest = true, jet = true, nades = true,
		bullets = true, weapon = true, fire = true, team = true, ping = true, status = true,
		health_icon = {5, 439}, health_bar = {45, 449},
		ammo_icon = {275, 439}, ammo_bar = {352, 449},
		jet_icon = {480, 439}, jet_bar = {520, 449},
		fire_icon = {402, 464}, fire_bar = {409, 464},
		nades_at = {308, 462}, bullets_at = {348, 451}, weapon_at = {285, 454},
		team_box = {575, 330}, status_at = {575, 421},
	}
}

// Read the fields used by this HUD from a Soldat setup.sif. Its byte-sized flags
// precede 32-bit integers; the positions in TInterface are interleaved with sizes,
// rotations and alignment bytes, which are skipped here. A malformed file leaves
// the default layout intact.
interface_read :: proc(mod: Mod) -> Interface_Layout {
	layout := interface_default()
	file, found := mod_file(mod, "interface-gfx/setup.sif")
	if !found do return layout
	data, ok := mod_read(file, context.temp_allocator)
	if !ok || len(data) < 240 do return layout
	r := utils.Reader{data = data}
	layout.alpha = i32(utils.read(&r, u8))
	layout.health = utils.read(&r, u8) != 0
	layout.ammo = utils.read(&r, u8) != 0
	layout.vest = utils.read(&r, u8) != 0
	layout.jet = utils.read(&r, u8) != 0
	layout.nades = utils.read(&r, u8) != 0
	layout.bullets = utils.read(&r, u8) != 0
	layout.weapon = utils.read(&r, u8) != 0
	layout.fire = utils.read(&r, u8) != 0
	layout.team = utils.read(&r, u8) != 0
	layout.ping = utils.read(&r, u8) != 0
	layout.status = utils.read(&r, u8) != 0
	read_pos :: proc(r: ^utils.Reader) -> [2]f32 {
		return {f32(utils.read(r, i32le)), f32(utils.read(r, i32le))}
	}
	skip_ints :: proc(r: ^utils.Reader, n: int) { utils.skip(r, n * 4) }
	layout.health_icon = read_pos(&r); skip_ints(&r, 1)
	layout.health_bar = read_pos(&r); skip_ints(&r, 2); utils.skip(&r, 4); skip_ints(&r, 1)
	layout.ammo_icon = read_pos(&r); skip_ints(&r, 1)
	layout.ammo_bar = read_pos(&r); skip_ints(&r, 2); utils.skip(&r, 4); skip_ints(&r, 1)
	layout.jet_icon = read_pos(&r); skip_ints(&r, 1)
	layout.jet_bar = read_pos(&r); skip_ints(&r, 2); utils.skip(&r, 4); skip_ints(&r, 1)
	// Vest bar
	skip_ints(&r, 5); utils.skip(&r, 4)
	layout.nades_at = read_pos(&r); skip_ints(&r, 2); utils.skip(&r, 4)
	layout.bullets_at = read_pos(&r)
	layout.weapon_at = read_pos(&r)
	layout.fire_icon = read_pos(&r); skip_ints(&r, 1)
	layout.fire_bar = read_pos(&r); skip_ints(&r, 2); utils.skip(&r, 4); skip_ints(&r, 1)
	layout.team_box = read_pos(&r)
	skip_ints(&r, 2) // Ping
	layout.status_at = read_pos(&r)
	return layout
}
