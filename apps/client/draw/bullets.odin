package draw

import "core:math"

import res "../../../core/resources"
import sim "../../../core/game"
import "../../../core/utils"

// The bullets in flight (TBullet.Render in Bullets.pas, by way of the C client's
// render/bullet_art.c). A round is its weapon's image ahead of where it is, stretched
// along its flight by its speed and facing the way it goes, with a fainter streak
// behind it as its trail.

BULLET_TRAIL :: 13.0  // a round is stretched by its speed over this
BULLET_LENGTH :: 21.0 // a shot run forward trails at most its run over this
BULLET_ALPHA :: 110

Bullet_Art :: struct {
	rounds: [res.Weapon]Sprite, // each weapon's; a weapon without one draws the USSOCOM's
	shapes: [Bullet_Shape]Sprite,
}

@(private = "file")
Bullet_Shape :: enum {
	Streak,
	Missile,
	Frag_Grenade,
	Knife,
	Knife_Left,
}

@(private = "file", rodata)
ROUND_FILES := #partial [res.Weapon]string {
	.Desert_Eagles = "eagles-bullet",
	.MP5           = "mp5-bullet",
	.AK74          = "ak74-bullet",
	.Steyr_AUG     = "steyraug-bullet",
	.Spas12        = "spas12-bullet",
	.Ruger77       = "ruger77-bullet",
	.M79           = "m79-bullet",
	.Barrett       = "barretm82-bullet",
	.Minimi        = "m249-bullet",
	.Minigun       = "minigun-bullet",
	.USSOCOM       = "colt-bullet",
	.LAW           = "missile",
}

@(private = "file", rodata)
SHAPE_FILES := [Bullet_Shape]string {
	.Streak       = "bullet",
	.Missile      = "missile",
	.Frag_Grenade = "frag-grenade",
	.Knife        = "knife",
	.Knife_Left   = "knife2",
}

bullets_load :: proc(source: Source) -> (art: Bullet_Art) {
	for file, weapon in ROUND_FILES {
		if file != "" do art.rounds[weapon] = sprite_find(source, "weapons-gfx", concat(file, ".png"))
	}
	for file, shape in SHAPE_FILES {
		art.shapes[shape] = sprite_find(source, "weapons-gfx", concat(file, ".png"), flat = shape == .Frag_Grenade)
	}
	return
}

// Every bullet in flight, `alpha` of the way from its last tick to its latest; and a
// shot run forward while its trail lasts, gone or not. With `trails`, the streaks
// behind them. `grenade_color` draws the grenades flat in that colour.
@(private = "package")
draw_bullets :: proc(art: ^Bullet_Art, world: ^sim.World, alpha: f32, grenade_color: Maybe(utils.Rgba), trails: bool) {
	for &bullet in world.bullets {
		if bullet.active || bullet.catch_up > 0 do draw_bullet(art, &bullet, alpha, grenade_color, trails)
	}
}

@(private = "file")
draw_bullet :: proc(art: ^Bullet_Art, bullet: ^sim.Bullet, alpha: f32, grenade_color: Maybe(utils.Rgba), trails: bool) {
	pos := between(bullet.old_pos, bullet.pos, alpha)
	timeout := f32(bullet.timeout) + 1 - alpha // counting down, it stands in for the age
	vel := bullet.velocity
	speed := utils.length(vel)
	heading := math.atan2(vel.y, vel.x)
	spin := timeout * -6 * math.RAD_PER_DEG
	off := [2]f32{-1 if vel.y > 0 else 1, 1 if vel.x > 0 else -1}

	streak := art.shapes[.Streak]
	own := art.rounds[bullet.weapon]
	if own.image.texture.id == 0 do own = art.rounds[.USSOCOM]
	if own.image.texture.id == 0 do own = streak

	switch bullet.style {
	case .Frag_Grenade:
		if trails && timeout < sim.GRENADE_TIMEOUT - 3 {
			draw_streak(streak, pos + off - {0, 3}, {speed / 3, 1}, heading, {100, 255, 100, 82})
		}
		draw_grenade(art.shapes[.Frag_Grenade], pos - {1, 4}, 0, grenade_color)
	case .M79:
		if timeout >= sim.BULLET_TIMEOUT - 2 do break
		draw_sprite(own, pos + {0, 1}, {}, {1, 1}, spin, {255, 255, 255, 252}) // only the M79's round tumbles
		if trails && timeout < sim.BULLET_TIMEOUT - 4 {
			draw_streak(streak, pos + off, {speed / 4, 1.3}, heading, {255, 255, 85, BULLET_ALPHA})
		}
	case .LAW:
		if timeout >= sim.BULLET_TIMEOUT - 2 do break
		draw_streak(art.shapes[.Missile], pos + vel, {1, 1}, heading, WHITE)
		if trails && timeout < sim.BULLET_TIMEOUT - 7 {
			draw_streak(streak, pos, {speed / 3, 1}, heading, {255, 255, 255, BULLET_ALPHA / 5})
		}
	case .Shotgun:
		if timeout >= sim.BULLET_TIMEOUT - 2 do break
		draw_streak(own, pos + vel, {1, 1}, heading, {255, 255, 255, 150})
		if trails && timeout < sim.BULLET_TIMEOUT - 3 {
			draw_streak(streak, pos, {speed / 9, 1}, heading, {255, 255, 255, BULLET_ALPHA / 5})
		}
	case .Thrown_Knife:
		turn := timeout / math.PI
		at := pos + vel + {4, 1}
		if vel.x >= 0 {
			draw_sprite(art.shapes[.Knife], at, {4, 1}, {1, 1}, -turn, WHITE)
		} else {
			draw_sprite(art.shapes[.Knife_Left], at, {4, 1}, {1, 1}, turn, WHITE)
		}
	case .Punch, .Knife: // a blow has nothing to show
	case .Plain:
		draw_round(own, bullet, pos, timeout, trails)
	}
}

// A plain round: its art ahead of it, as bright as it is strong and fast; and its
// trail, pink once it has hit someone.
@(private = "file")
draw_round :: proc(own: Sprite, bullet: ^sim.Bullet, pos: utils.Vec2, timeout: f32, trails: bool) {
	if timeout >= sim.BULLET_TIMEOUT - 2 do return
	vel := bullet.velocity
	speed := utils.length(vel)
	heading := math.atan2(vel.y, vel.x)
	stretch := speed / BULLET_TRAIL
	a := clamp(bullet.damage * stretch * stretch / 4.63 * 255, 50, 230)
	if bullet.catch_up < 1 do draw_streak(own, pos + vel, {stretch, 1}, heading, {255, 255, 255, u8(a)})
	// a shot heard and run forward: instead of the round, its art stretched back toward
	// where it was fired over the distance it skipped, shrinking as the run counts down;
	// fainter still once it is gone
	if bullet.catch_up > 0 {
		run := utils.length(pos - bullet.fired_from)
		length := run * min(1.0 / BULLET_LENGTH, (f32(bullet.catch_up + 2) / f32(bullet.catch_up_start)) / BULLET_TRAIL)
		faint := a / 6 if bullet.active else a / 4
		draw_streak(own, pos + vel, {length, 1}, heading, {255, 255, 255, u8(math.round(faint))})
	}
	if trails && timeout < sim.BULLET_TIMEOUT - 7 {
		if bullet.last_hit != nil {
			draw_streak(own, pos, {speed / 4, 1}, heading, {255, 222, 222, BULLET_ALPHA / 2})
		} else {
			draw_streak(own, pos, {speed / 3.5, 1}, heading, {255, 255, 255, BULLET_ALPHA / 2})
		}
	}
}

// A streak: its image's left edge at `at`, facing back the way it came, so it trails.
@(private = "file")
draw_streak :: proc(sprite: Sprite, at, scale: [2]f32, heading: f32, color: utils.Rgba) {
	draw_sprite(sprite, at, {}, scale, heading + math.PI, color)
}

// A thrown grenade or bomblet: its art, or flat in `color`.
@(private = "file")
draw_grenade :: proc(sprite: Sprite, at: [2]f32, angle: f32, color: Maybe(utils.Rgba)) {
	if flat, is_flat := color.?; is_flat {
		draw_sprite_flat(sprite, at, {}, {1, 1}, angle, flat)
	} else {
		draw_sprite(sprite, at, {}, {1, 1}, angle, WHITE)
	}
}
