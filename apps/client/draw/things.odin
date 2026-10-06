package draw

import "core:math"

import res "../../../core/resources"
import sim "../../../core/game"
import "../../../core/utils"

// The things (TThing.Render and TThing.PolygonsRender, by way of the C client's
// render/things_art.c). A flag's cloth is stretched over its skeleton's points, so it
// flutters with them, with a handle along the pole and a glow pulsing while it is home;
// a kit is its image over its box; a dropped gun hangs from its grip toward its muzzle;
// and a parachute is three ropes and a canopy in its owner's shirt.

Thing_Art :: struct {
	cloth:   Sprite, // grey, tinted to the team's
	kits:    [sim.Thing_Kind]Sprite,
	handle:  Sprite, // the flag's, along the pole
	glow:    Sprite, // the flag's at home
	guns:    [res.Weapon][2]Sprite, // dropped, [thrown facing left]
	canopy:  [2]Sprite,
	rope:    Sprite,
}

// The things are drawn at two depths, as the original's are: the sprites (the flag's
// pole and glow, the guns, the parachute) just in front of the soldiers, and the quads
// (the flags' cloth, the kits) in front of the sparks and the middle scenery too.
Thing_Pass :: enum {
	Sprites,
	Quads,
}

// The loose art of dropped guns: the art in hand, but the pistols', which have their own
// without the hand.
@(private = "file", rodata)
GUN_FILES := #partial [res.Weapon]string {
	.Desert_Eagles = "n-deserteagle",
	.MP5           = "mp5",
	.AK74          = "ak74",
	.Steyr_AUG     = "steyraug",
	.Spas12        = "spas12",
	.Ruger77       = "ruger77",
	.M79           = "m79",
	.Barrett       = "barretm82",
	.Minimi        = "m249",
	.Minigun       = "minigun",
	.USSOCOM       = "n-colt1911",
	.Knife         = "knife",
	.Chainsaw      = "chainsaw",
	.LAW           = "law",
}

@(private = "file", rodata)
KIT_FILES := #partial [sim.Thing_Kind]string {
	.Medical_Kit = "medikit",
	.Grenade_Kit = "grenadekit",
}

// The cloth's tints at its foot, its top and its free corner, so it reads as lit from one
// side.
@(private = "file", rodata)
CLOTH_TINTS := [2][3]utils.Rgba {
	{{173, 20, 20, 255}, {181, 20, 20, 255}, {148, 20, 20, 255}}, // alpha's
	{{5, 15, 173, 255}, {5, 15, 181, 255}, {5, 15, 148, 255}}, // bravo's
}

BLINK_TIMEOUT :: 300 // a flag or a gun about to go blinks through its last five seconds

things_load :: proc(source: Source) -> (art: Thing_Art) {
	key := res.COLOR_KEY
	art.cloth = sprite_load(source, "textures/objects/flag.bmp", key)
	for file, kind in KIT_FILES {
		if file != "" do art.kits[kind] = sprite_load(source, concat("textures/objects/", file, ".png"), key)
	}
	art.handle = sprite_load(source, "objects-gfx/flag.png", key)
	art.glow = sprite_load(source, "objects-gfx/ilum.png", key)
	for file, weapon in GUN_FILES {
		if file == "" do continue
		art.guns[weapon][0] = sprite_find(source, "weapons-gfx", concat(file, ".png"), key)
		art.guns[weapon][1] = sprite_find(source, "weapons-gfx", concat(file, "-2.png"), key)
	}
	art.canopy[0] = sprite_load(source, "gostek-gfx/para.png", key)
	art.canopy[1] = sprite_load(source, "gostek-gfx/para2.png", key)
	art.rope = sprite_load(source, "gostek-gfx/para-rope.png", res.BLACK_KEY)
	return
}

// One pass over the things, each `alpha` of the way from its last tick to its latest.
// `seconds` pulses the flags' glow.
@(private = "package")
draw_things :: proc(art: ^Thing_Art, game: ^sim.Game, pass: Thing_Pass, alpha: f32, seconds: f64) {
	for &thing in game.world.things {
		if thing.kind == .None || blinked_out(&thing) do continue
		p: [4]utils.Vec2
		for &point, k in p {
			point = between(thing.old_points[k], thing.points[k], alpha)
		}
		switch pass {
		case .Quads:
			if sim.thing_is_flag(thing.kind) {
				draw_flag_cloth(art, &thing, p)
			} else if sim.thing_is_kit(thing.kind) {
				// a kit's points are numbered from its bottom, so the box is drawn from the top pair
				draw_quad(art.kits[thing.kind].image, {p[2], p[3], p[0], p[1]}, {{0, 0}, {1, 0}, {1, 1}, {0, 1}}, {WHITE, WHITE, WHITE, WHITE})
			}
		case .Sprites:
			#partial switch thing.kind {
			case .Alpha_Flag, .Bravo_Flag: draw_flag_pole(art, &thing, p, seconds)
			case .Weapon:                  draw_dropped_gun(art, &thing, p)
			case .Parachute:               draw_parachute(art, game, &thing, p)
			}
		}
	}
}

// A flag or a dropped gun about to go flashes. Nothing else does: a kit lies on past its
// timeout, which runs on down.
@(private = "file")
blinked_out :: proc(thing: ^sim.Thing) -> bool {
	if !sim.thing_is_flag(thing.kind) && thing.kind != .Weapon do return false
	return thing.timeout < BLINK_TIMEOUT && thing.timeout % 6 < 3
}

// The pole's half-way point, where the cloth's lower corner hangs and the glow sits.
@(private = "file")
pole_half :: proc(p: [4]utils.Vec2) -> utils.Vec2 {
	return between(p[0], p[1], 0.5)
}

// The handle along the pole from its foot toward its tip, and the glow while it is home.
@(private = "file")
draw_flag_pole :: proc(art: ^Thing_Art, thing: ^sim.Thing, p: [4]utils.Vec2, seconds: f64) {
	draw_sprite(art.handle, p[0], {}, {1, 1}, angle_to(p[0], p[1]), WHITE)
	if thing.in_base {
		glow := abs(5 + 20 * math.sin(5.1 * f32(seconds)))
		draw_sprite(art.glow, pole_half(p) - {12.5, 12.5}, {}, {1, 1}, 0, {255, 255, 255, alpha_byte(glow)})
	}
}

// The cloth hangs from the pole's upper half: the tip, the half-way point, and the free
// edge's two points.
@(private = "file")
draw_flag_cloth :: proc(art: ^Thing_Art, thing: ^sim.Thing, p: [4]utils.Vec2) {
	tint := CLOTH_TINTS[0 if thing.kind == .Alpha_Flag else 1]
	draw_quad(art.cloth.image, {p[1], pole_half(p), p[3], p[2]}, {{0, 0}, {0, 1}, {1, 1}, {1, 0}}, {tint[0], tint[1], tint[0], tint[2]})
}

@(private = "file")
draw_dropped_gun :: proc(art: ^Thing_Art, thing: ^sim.Thing, p: [4]utils.Vec2) {
	sprite := art.guns[thing.weapon][1 if thing.flip else 0]
	if sprite.image.texture.id == 0 do sprite = art.guns[thing.weapon][0]
	draw_sprite(sprite, p[0] - {0, 1}, {0, 2}, {1, 1}, angle_to(p[0], p[1]), WHITE)
}

// Three ropes from the harness to the canopy's corners, then the canopy, until it is
// stretched past twice its size.
@(private = "file")
draw_parachute :: proc(art: ^Thing_Art, game: ^sim.Game, thing: ^sim.Thing, p: [4]utils.Vec2) {
	corners := [3]utils.Vec2{p[1], p[2], p[0]}
	for corner, i in corners {
		angle := angle_to(p[3], corner)
		if i == 1 do angle -= 5 * math.RAD_PER_DEG
		draw_sprite(art.rope, p[3] - {0, 0.55}, {0, art.rope.size.y / 2}, {1, 1}, angle, WHITE)
	}
	span := utils.length(p[1] - p[2]) / 45.83
	if span > 2 do return
	color := WHITE
	if owner, owned := thing.owner.?; owned {
		color = shirt_worn(&game.world.soldiers[owner])
		color.a = 255
	}
	draw_sprite(art.canopy[1], p[2], {}, {span, span}, angle_to(p[2], p[0]), color)
	draw_sprite(art.canopy[0], p[0], {}, {span, span}, angle_to(p[0], p[1]), color)
}
