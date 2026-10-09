package draw

import "core:math"

import res "../../../core/resources"
import sim "../../../core/game"

// The weapons a soldier carries, drawn on its points as its parts are: the primary in
// the hands (from point 16 toward 15; the knife along the forearm, 16 toward 20), with
// its muzzle flash the tick a shot goes off; the secondary slung across the back (5
// toward 10). Their art is weapons-gfx/<file>.png, mirrored <file>-2.png. From the C
// client's render/gostek.c.

@(private = "file")
Weapon_Art :: struct {
	id:           string, // the original's: mod.ini's [GOSTEK] pins it as Primary_<id> held,
	                      // Secondary_<id> slung and Primary_<id>_Fire its flash
	file:         string,
	in_hands:     [2]f32, // its center, held
	on_back:      [2]f32, // and slung
	flash:        string, // the muzzle flash
	flash_center: [2]f32, // past the muzzle, so its x is negative
	forearm:      bool,   // held along the forearm rather than toward the other hand
	unslung:      bool,   // never shown on the back
}

@(private = "file", rodata)
WEAPON_ART := #partial [res.Weapon]Weapon_Art {
	.Desert_Eagles = {id = "Deagles", file = "deserteagle", in_hands = {0.1, 0.8}, on_back = {0.3, 0.5}, flash = "eagles-fire", flash_center = {-0.5, 1.0}},
	.MP5           = {id = "Mp5", file = "mp5", in_hands = {0.15, 0.6}, on_back = {0.3, 0.3}, flash = "mp5-fire", flash_center = {-0.65, 0.85}},
	.AK74          = {id = "Ak74", file = "ak74", in_hands = {0.15, 0.5}, on_back = {0.3, 0.25}, flash = "ak74-fire", flash_center = {-0.37, 0.8}},
	.Steyr_AUG     = {id = "Steyr", file = "steyraug", in_hands = {0.2, 0.6}, on_back = {0.3, 0.5}, flash = "steyraug-fire", flash_center = {-0.24, 0.75}},
	.Spas12        = {id = "Spas", file = "spas12", in_hands = {0.1, 0.6}, on_back = {0.3, 0.3}, flash = "spas12-fire", flash_center = {-0.2, 0.9}},
	.Ruger77       = {id = "Ruger", file = "ruger77", in_hands = {0.1, 0.7}, on_back = {0.3, 0.3}, flash = "ruger77-fire", flash_center = {-0.35, 0.85}},
	.M79           = {id = "M79", file = "m79", in_hands = {0.1, 0.7}, on_back = {0.3, 0.35}, flash = "m79-fire", flash_center = {-0.4, 0.8}},
	.Barrett       = {id = "Barrett", file = "barretm82", in_hands = {0.15, 0.7}, on_back = {0.3, 0.35}, flash = "barret-fire", flash_center = {-0.15, 0.8}},
	.Minimi        = {id = "Minimi", file = "m249", in_hands = {0.15, 0.6}, on_back = {0.3, 0.35}, flash = "m249-fire", flash_center = {-0.2, 0.9}},
	.Minigun       = {id = "Minigun", file = "minigun", in_hands = {0.05, 0.5}, on_back = {0.2, 0.5}, flash = "minigun-fire", flash_center = {-0.2, 0.45}},
	.USSOCOM       = {id = "Socom", file = "colt1911", in_hands = {0.2, 0.55}, on_back = {0.3, 0.5}, flash = "colt1911-fire", flash_center = {-0.24, 0.85}},
	.Chainsaw      = {id = "Chainsaw", file = "chainsaw", in_hands = {0.25, 0.5}, on_back = {0.25, 0.5}, flash = "chainsaw-fire", flash_center = {-0.2, 0.5}},
	.LAW           = {id = "Law", file = "law", in_hands = {0.1, 0.6}, on_back = {0.3, 0.45}, flash = "law-fire", flash_center = {-0.2, 0.8}},
	.Knife         = {id = "Knife", file = "knife", in_hands = {-0.1, 0.6}, forearm = true, unslung = true},
}

// Where a weapon is pinned, as the mod.ini of the mod its image is from has it, else as
// WEAPON_ART does.
@(private = "package")
Weapon_Anchors :: struct {
	in_hands, on_back, flash: [2]f32,
}

@(private = "package")
weapons_load :: proc(source: Source, art: ^Gostek_Art) {
	for weapon_art, weapon in WEAPON_ART {
		if weapon_art.file == "" do continue
		art.weapons[weapon][0] = sprite_load(source, concat("weapons-gfx/", weapon_art.file, ".png"))
		art.weapons[weapon][1] = sprite_load(source, concat("weapons-gfx/", weapon_art.file, "-2.png"))
		if weapon_art.flash != "" {
			art.flashes[weapon] = sprite_load(source, concat("weapons-gfx/", weapon_art.flash, ".png"))
		}
		gun := art.weapons[weapon][0]
		art.held[weapon] = {
			in_hands = anchor_of(source, gun, concat("Primary_", weapon_art.id), weapon_art.in_hands),
			on_back  = anchor_of(source, gun, concat("Secondary_", weapon_art.id), weapon_art.on_back),
			flash    = anchor_of(source, art.flashes[weapon], concat("Primary_", weapon_art.id, "_Fire"), weapon_art.flash_center),
		}
	}
}

// Where a sprite is pinned, by the original's id for it: as the mod.ini of the mod it came
// from says ([GOSTEK]), else `default`.
@(private = "package")
anchor_of :: proc(source: Source, sprite: Sprite, id: string, default: [2]f32) -> [2]f32 {
	if sprite.layer < 0 || sprite.layer >= len(source.mod.layers) do return default
	return res.mod_anchor(source.mod.layers[sprite.layer].config, id, default)
}

@(private = "package")
draw_slung_weapon :: proc(art: ^Gostek_Art, soldier: ^sim.Soldier, points: ^Points, facing_left: bool) {
	weapon := soldier.arsenal.secondary.weapon
	weapon_art := WEAPON_ART[weapon]
	if weapon_art.file == "" || weapon_art.unslung do return
	draw_weapon(art, points, weapon, 5, 10, art.held[weapon].on_back, facing_left)
}

// The primary, and its flash the tick it fires.
@(private = "package")
draw_held_weapon :: proc(art: ^Gostek_Art, soldier: ^sim.Soldier, points: ^Points, facing_left: bool) {
	weapon := soldier.arsenal.primary.weapon
	weapon_art := WEAPON_ART[weapon]
	if weapon_art.file == "" do return
	draw_weapon(art, points, weapon, 16, 20 if weapon_art.forearm else 15, art.held[weapon].in_hands, facing_left)

	flash := art.flashes[weapon]
	if !soldier.arsenal.fired || flash.image.texture.id == 0 do return
	hand, aim := points[16 - 1], points[15 - 1]
	scale: [2]f32 = {1, -1} if facing_left else {1, 1}
	draw_sprite(flash, hand + {0, 1}, art.held[weapon].flash * flash.size, scale, angle_to(hand, aim), WHITE)
}

// The weapon pinned on point `p1` and turned toward `p2`, as a part is. Facing left it is
// its mirrored image, or, without one, its own turned over.
@(private = "file")
draw_weapon :: proc(art: ^Gostek_Art, points: ^Points, weapon: res.Weapon, p1, p2: int, center: [2]f32, facing_left: bool) {
	mirrored := facing_left
	sprite := art.weapons[weapon][1 if mirrored else 0]
	if sprite.image.texture.id == 0 {
		sprite = art.weapons[weapon][0]
		mirrored = false
	}
	center, scale := center, [2]f32{1, 1}
	if mirrored {
		center.y = 1 - center.y
	} else if facing_left {
		scale.y = -1
	}
	from, to := points[p1 - 1], points[p2 - 1]
	draw_sprite(sprite, from + {0, 1}, center * sprite.size, scale, angle_to(from, to), WHITE)
}

// The direction from one point to another, in radians.
@(private = "package")
angle_to :: proc(from, to: [2]f32) -> f32 {
	return math.atan2(to.y - from.y, to.x - from.x)
}
