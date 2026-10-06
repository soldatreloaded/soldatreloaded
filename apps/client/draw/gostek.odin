package draw

import "core:math"

import res "../../../core/resources"
import sim "../../../core/game"
import "../../../core/utils"

// The gostek, a soldier's art: sprites pinned to its skeleton's points, one table of
// parts drawn in its order (GostekGraphics.pas, by way of the C client's
// render/gostek.c). Each part sits on one point, turned to face another, placed so its
// own point `center` (0 to 1 across the image) lands on the first. Some stretch along
// their length; most have a mirrored image for facing left, and an image of their own
// for the second team. The wounds (ranny/) follow the part each covers, and show as the
// health runs low.
//
// Its look is the player's: the shirt, the pants, the skin and the hair in their
// colours, its style (the male, as the original's, in gostek-gfx itself; the female,
// waifu, rat and furry, which the original hasn't, each in its own folder under it), and
// its hair, headgear and chain. The hair and the headgear are every style's, in
// gostek-gfx itself as the original's, one file per style; the rat and the furry wear
// only army, punk and Mr. T, and no headgear. So an original mod's gostek-gfx dresses
// the male, his hair and his headgear as it is. The chain and the
// dreadlocks hang from the points 21 to 24, which the simulation swings. The cigar shows
// while one is in the mouth, and the helmet or the hat sits in the hand while the brow
// is wiped or it is taken off.

Gostek_Art :: struct {
	// by style, part, team (the second's image) and mirrored; a part every style wears
	// the same (part_shared) is the male's alone
	parts:   [res.Gostek][len(PARTS)][2][2]Sprite,
	weapons: [res.Weapon][2]Sprite, // [mirrored]
	flashes: [res.Weapon]Sprite,
}

@(private = "file")
Part :: struct {
	file:    string,
	dir:     string, // the folder under the mod it is read from; the style's when empty
	p1, p2:  int,    // the points it is pinned on and turned toward, the original's 1-based numbering
	center:  [2]f32,
	flex:    f32,    // over 0: it stretches along its length, by the length over this, to half again at most
	flip:    bool,   // it has a mirrored image, "<file>2", for facing left
	team:    bool,   // it has the second team's image, under team2/
	color:   Part_Color,
	shown:   Part_Shown,
	grip:    bool,   // the held weapon goes just before it, so the arm wraps the grip
	nade:    int,    // the nth grenade on the belt, shown while that many are carried
	hair:    res.Hair_Style, // shown for this hair style
	dread:   int,    // the nth dreadlock, hanging from the head's top toward point 24
	head:    res.Head_Style, // shown for this headgear
	grabbed: bool,   // the headgear in the hand rather than on the head
	chain:   res.Chain_Style, // shown for this chain
}

@(private = "file")
Part_Color :: enum {
	None, // the art's own
	Shirt,
	Pants,
	Skin,
	Hair,
	Head_Blood, // the face's wound
	Cigar,      // grey until it is lit
}

@(private = "file")
Part_Shown :: enum {
	Always,
	Standing, // a foot: hidden while the jets burn
	Jetting,  // the jet's foot in its place
	Wounded,  // a wound, as the health runs low
	Cigar,    // while a cigar is in the mouth
}

@(private = "file", rodata)
STYLE_DIRS := [res.Gostek]string {
	.Male   = "", // gostek-gfx itself, as the original's
	.Female = "female",
	.Waifu  = "waifu",
	.Rat    = "rat",
	.Furry  = "furry",
}

// In the order they are drawn.
@(private = "file", rodata)
PARTS := [?]Part {
	// the helmet or the hat in the left hand, while the brow is wiped or it comes off:
	// behind everything, as the original draws them
	{file = "helm", p1 = 15, p2 = 19, center = {0, 0.5}, flip = true, team = true, color = .Shirt, head = .Helmet, grabbed = true},
	{file = "kap", p1 = 15, p2 = 19, center = {0.1, 0.4}, flip = true, team = true, color = .Shirt, head = .Hat, grabbed = true},
	{file = "helm3", p1 = 15, p2 = 19, center = {0, 0.5}, flip = true, team = true, color = .Shirt, head = .Waifu, grabbed = true},
	{file = "udo", p1 = 6, p2 = 3, center = {0.2, 0.5}, flex = 5, flip = true, team = true, color = .Pants},
	{file = "ranny/udo", p1 = 6, p2 = 3, center = {0.2, 0.5}, flex = 5, flip = true, team = true, shown = .Wounded},
	{file = "stopa", p1 = 2, p2 = 18, center = {0.35, 0.35}, flip = true, team = true, shown = .Standing},
	{file = "lecistopa", p1 = 2, p2 = 18, center = {0.35, 0.35}, flip = true, team = true, shown = .Jetting},
	{file = "noga", p1 = 3, p2 = 2, center = {0.15, 0.55}, flip = true, team = true, color = .Pants},
	{file = "ranny/noga", p1 = 3, p2 = 2, center = {0.15, 0.55}, flip = true, team = true, shown = .Wounded},
	{file = "ramie", p1 = 11, p2 = 14, center = {0, 0.5}, flip = true, team = true, color = .Shirt},
	{file = "ranny/ramie", p1 = 11, p2 = 14, center = {0, 0.5}, flip = true, team = true, shown = .Wounded},
	{file = "reka", p1 = 14, p2 = 15, center = {0, 0.5}, flex = 5, team = true, color = .Shirt},
	{file = "ranny/reka", p1 = 14, p2 = 15, center = {0, 0.5}, flex = 5, flip = true, team = true, shown = .Wounded},
	{file = "dlon", p1 = 15, p2 = 19, center = {0, 0.4}, flip = true, team = true, color = .Skin},
	{file = "udo", p1 = 5, p2 = 4, center = {0.2, 0.65}, flex = 5, flip = true, team = true, color = .Pants},
	{file = "ranny/udo", p1 = 5, p2 = 4, center = {0.2, 0.65}, flex = 5, flip = true, team = true, shown = .Wounded},
	{file = "stopa", p1 = 1, p2 = 17, center = {0.35, 0.35}, flip = true, team = true, shown = .Standing},
	{file = "lecistopa", p1 = 1, p2 = 17, center = {0.35, 0.35}, flip = true, team = true, shown = .Jetting},
	{file = "noga", p1 = 4, p2 = 1, center = {0.15, 0.55}, flip = true, team = true, color = .Pants},
	{file = "ranny/noga", p1 = 4, p2 = 1, center = {0.15, 0.55}, flip = true, team = true, shown = .Wounded},
	{file = "klata", p1 = 10, p2 = 11, center = {0.1, 0.3}, flip = true, team = true, color = .Shirt},
	{file = "ranny/klata", p1 = 10, p2 = 11, center = {0.1, 0.3}, flip = true, team = true, shown = .Wounded},
	{file = "biodro", p1 = 5, p2 = 6, center = {0.25, 0.6}, flip = true, team = true, color = .Shirt},
	{file = "ranny/biodro", p1 = 5, p2 = 6, center = {0.25, 0.6}, flip = true, team = true, shown = .Wounded},
	{file = "morda", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Skin},
	{file = "ranny/morda", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Head_Blood, shown = .Wounded},
	// The hair, the headgear and the chain, in the original's order. A helmet or a hat
	// covers every hair style but Mr. T's.
	{file = "hair3", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Hair, hair = .Mr_T},
	{file = "helm", p1 = 9, p2 = 12, center = {-0.1, 0.52}, flip = true, team = true, color = .Shirt, head = .Helmet},
	{file = "kap", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Shirt, head = .Hat},
	{file = "helm3", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Shirt, head = .Waifu},
	{file = "hair1", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Hair, hair = .Dreadlocks},
	{file = "dred", p1 = 23, p2 = 24, center = {0, 1.22}, team = true, color = .Hair, hair = .Dreadlocks, dread = 1},
	{file = "dred", p1 = 23, p2 = 24, center = {0.1, 0.5}, team = true, color = .Hair, hair = .Dreadlocks, dread = 2},
	{file = "dred", p1 = 23, p2 = 24, center = {0.04, -0.3}, team = true, color = .Hair, hair = .Dreadlocks, dread = 3},
	{file = "dred", p1 = 23, p2 = 24, center = {0, -0.9}, team = true, color = .Hair, hair = .Dreadlocks, dread = 4},
	{file = "dred", p1 = 23, p2 = 24, center = {-0.2, -1.35}, team = true, color = .Hair, hair = .Dreadlocks, dread = 5},
	{file = "hair2", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Hair, hair = .Punk},
	{file = "hair4", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Hair, hair = .Normal},
	// the waifu's: her fringe's bangs sit a little right on everyone, so it is anchored in
	{file = "hair5", p1 = 9, p2 = 12, center = {0.03, 0.65}, flip = true, team = true, color = .Hair, hair = .Fringe},
	{file = "hair6", p1 = 9, p2 = 12, center = {0, 0.5}, flip = true, team = true, color = .Hair, hair = .Bob},
	{file = "lancuch", p1 = 10, p2 = 22, center = {0.1, 0.5}, team = true, chain = .Dog_Tags},
	{file = "lancuch", p1 = 11, p2 = 22, center = {0.1, 0.5}, team = true, chain = .Dog_Tags},
	{file = "metal", p1 = 22, p2 = 21, center = {0.5, 0.7}, flip = true, team = true, chain = .Dog_Tags},
	{file = "zlotylancuch", p1 = 10, p2 = 22, center = {0.1, 0.5}, team = true, chain = .Gold_Chain},
	{file = "zlotylancuch", p1 = 11, p2 = 22, center = {0.1, 0.5}, team = true, chain = .Gold_Chain},
	{file = "zloto", p1 = 22, p2 = 21, center = {0.5, 0.5}, flip = true, team = true, chain = .Gold_Chain},
	{file = "cygaro", p1 = 9, p2 = 12, center = {-0.125, 0.4}, flip = true, team = true, color = .Cigar, shown = .Cigar},
	// The belt, between the hips. The original pins all five to the same spot, so a
	// soldier carrying more shows no more; the count is still the original's.
	{file = "frag-grenade", dir = "weapons-gfx", p1 = 5, p2 = 6, center = {0.5, 0.1}, nade = 1},
	{file = "frag-grenade", dir = "weapons-gfx", p1 = 5, p2 = 6, center = {0.5, 0.1}, nade = 2},
	{file = "frag-grenade", dir = "weapons-gfx", p1 = 5, p2 = 6, center = {0.5, 0.1}, nade = 3},
	{file = "frag-grenade", dir = "weapons-gfx", p1 = 5, p2 = 6, center = {0.5, 0.1}, nade = 4},
	{file = "frag-grenade", dir = "weapons-gfx", p1 = 5, p2 = 6, center = {0.5, 0.1}, nade = 5},
	{file = "ramie", p1 = 10, p2 = 13, center = {0, 0.6}, flip = true, team = true, color = .Shirt, grip = true},
	{file = "ranny/ramie", p1 = 10, p2 = 13, center = {-0.1, 0.5}, flip = true, team = true, shown = .Wounded},
	{file = "reka", p1 = 13, p2 = 16, center = {0, 0.6}, flex = 5, team = true, color = .Shirt},
	{file = "ranny/reka", p1 = 13, p2 = 16, center = {0, 0.6}, flex = 5, flip = true, team = true, shown = .Wounded},
	{file = "dlon", p1 = 16, p2 = 20, center = {0, 0.5}, flip = true, team = true, color = .Skin},
}

NADE_ALPHA :: 0.75 // the belt's grenades, as the original draws them (ALPHA_NADES)
SPAWN_PROTECTED_ALPHA :: 153

// Every style's parts and the weapons' art.
gostek_load :: proc(art: ^Gostek_Art, source: Source) {
	for style in res.Gostek {
		for &part, i in PARTS {
			if style != .Male && part_shared(part) do continue
			for team in 0 ..< (2 if part.team else 1) {
				for mirrored in 0 ..< (2 if part.flip else 1) {
					art.parts[style][i][team][mirrored] = sprite_load(source, part_path(part, style, team == 1, mirrored == 1), flat = part.nade > 0)
				}
			}
		}
	}
	weapons_load(source, art)
}

// What a soldier wears and does as it is drawn, which says which parts show.
@(private = "file")
Outfit :: struct {
	look:       sim.Look,
	jetting:    bool,
	wounds:     u8, // how strongly the wounds show; 0 not at all
	cigar:      bool,
	grenades:   int, // on the belt
	grabbed:    bool, // the headgear in the hand
	capped:     bool, // the headgear on
	hair_shown: bool,
}

// A soldier on its figure's points, in the shirt it wears (its team's). `grenade_color`
// puts the belt's grenades in a flat colour of the player's choosing; nil leaves them as
// the art has them.
@(private = "package")
draw_gostek :: proc(art: ^Gostek_Art, soldier: ^sim.Soldier, figure: ^Figure, shirt: utils.Rgba, grenade_color: Maybe(utils.Rgba)) {
	points := &figure.points
	facing_left := soldier.body.direction != 1
	team := 1 if soldier.team == .Bravo || soldier.team == .Delta else 0
	outfit := outfit_of(soldier, figure.corpse)
	style := outfit.look.gostek

	draw_slung_weapon(art, soldier, points, facing_left) // across the back, behind the body

	for &part, i in PARTS {
		if part.grip do draw_held_weapon(art, soldier, points, facing_left)
		if !part_shown(part, outfit) do continue

		mirrored := facing_left && part.flip
		sprite := art.parts[.Male if part_shared(part) else style][i][team if part.team else 0][1 if mirrored else 0]
		if sprite.image.texture.id == 0 do continue

		p1, p2 := points[part.p1 - 1], points[part.p2 - 1]
		along := p2 - p1
		angle := math.atan2(along.y, along.x)
		center := part.center
		if figure.corpse && part.p2 == 12 {
			p1 = p2 // a corpse's face hangs from the head, so a cut head rolls off with it
			center.x = 1
		}
		scale := [2]f32{1, 1}
		if facing_left && part.flip {
			center.y = 1 - part.center.y
		} else if facing_left {
			scale.y = -1
		}
		if part.dread > 0 {
			// each dreadlock's root is its center, in its own size, turned with the head;
			// from there it hangs toward point 24, each a little longer than the last
			head := points[11] - points[8]
			turn := math.atan2(head.y, head.x) - math.PI / 2
			dir: f32 = -1 if facing_left else 1
			root := [2]f32{-part.center.y * sprite.size.y * dir, part.center.x * sprite.size.x}
			c, s := math.cos(turn), math.sin(turn)
			p1 += {root.x * c - root.y * s, root.x * s + root.y * c}
			center = {0, 0.5}
			scale.x = 0.75 + 0.25 / 5 * f32(part.dread - 1)
		} else if part.flex > 0 {
			scale.x = min(1.5, utils.length(along) / part.flex)
		}

		tint := part_color(part.color, outfit.look, shirt, soldier)
		if part.shown == .Wounded do tint.a = outfit.wounds
		at := p1 + {0, 1}
		if part.nade > 0 {
			if color, flat := grenade_color.?; flat {
				// flat and solid, but with the body's alpha, so they fade with it
				draw_sprite_flat(sprite, at, center * sprite.size, scale, angle, {color.r, color.g, color.b, tint.a})
				continue
			}
			tint.a = u8(NADE_ALPHA * f32(tint.a))
		}
		draw_sprite(sprite, at, center * sprite.size, scale, angle, tint)
	}
}

@(private = "file")
outfit_of :: proc(soldier: ^sim.Soldier, corpse: bool) -> (outfit: Outfit) {
	outfit.look = soldier.player.look
	outfit.jetting = !corpse && soldier_jetting(soldier)
	outfit.wounds = wound_alpha(soldier.vitals.health)
	outfit.cigar = soldier.antics.cigar == 5 || soldier.antics.cigar == 10
	// what is carried, less the one already in the hand while a throw runs; none, if the
	// throw is an empty one (a part without a grenade is the 0th: never hidden)
	body := soldier.pose.body
	outfit.grenades = max(0, int(soldier.arsenal.grenades) - (1 if body.id == .Throw else 0))
	// the headgear: in the hand past the fourth frame of a wipe or a take-off; the hair
	// shows under none but Mr. T's, and once it is off. The rat and the furry never wear
	// any, whatever an old config says.
	outfit.grabbed = (body.id == .Wipe || body.id == .Take_Off) && body.frame > 4
	furred := outfit.look.gostek == .Rat || outfit.look.gostek == .Furry
	outfit.capped = outfit.look.head_style != .None && soldier.antics.helmet == 1 && !furred
	outfit.hair_shown = outfit.grabbed || !outfit.capped || outfit.look.hair_style == .Mr_T
	return
}

@(private = "file")
part_shown :: proc(part: Part, outfit: Outfit) -> bool {
	switch part.shown {
	case .Always:
	case .Standing: if outfit.jetting do return false
	case .Jetting:  if !outfit.jetting do return false
	case .Wounded:  if outfit.wounds == 0 do return false
	case .Cigar:    if !outfit.cigar do return false
	}
	look := outfit.look
	furred := look.gostek == .Rat || look.gostek == .Furry
	if part.nade > outfit.grenades do return false // a corpse keeps its belt, as the original leaves it
	if part.hair != .Army {
		if furred && part.hair != .Punk && part.hair != .Mr_T do return false
		if part.hair != look.hair_style || !outfit.hair_shown do return false
	}
	if part.head != .None {
		if furred || part.head != look.head_style || !outfit.capped || part.grabbed != outfit.grabbed do return false
	}
	if part.chain != .None && part.chain != look.chain_style do return false
	return true
}

// The jets burn while they are held and have fuel left.
@(private = "package")
soldier_jetting :: proc(soldier: ^sim.Soldier) -> bool {
	return .Jet in soldier.controls.buttons && soldier.body.jet_fuel > 0
}

// The shirt, worn over the player's own: the team's (the original's ApplyShirtColorFromTeam).
shirt_worn :: proc(soldier: ^sim.Soldier) -> utils.Rgba {
	#partial switch soldier.team {
	case .Alpha:   return {210, 15, 5, 255}
	case .Bravo:   return {21, 31, 217, 255}
	case .Charlie: return {210, 210, 5, 255}
	case .Delta:   return {5, 210, 5, 255}
	}
	return {140, 140, 148, 255}
}

// None above 90 health, then stronger the lower it goes; a corpse's is its health at
// death, and after.
@(private = "file")
wound_alpha :: proc(health: f32) -> u8 {
	if health > 90 do return 0
	return u8(clamp(200 - math.round(health), 0, 255))
}

// A part's colour from the player's look, faded while the spawn protection lasts.
@(private = "file")
part_color :: proc(color: Part_Color, look: sim.Look, shirt: utils.Rgba, soldier: ^sim.Soldier) -> (tint: utils.Rgba) {
	switch color {
	case .None:       tint = WHITE
	case .Shirt:      tint = shirt
	case .Pants:      tint = look.pants
	case .Skin:       tint = look.skin
	case .Hair:       tint = look.hair
	case .Head_Blood: tint = {172, 169, 168, 255}
	case .Cigar:      tint = {97, 97, 97, 255} if soldier.antics.cigar == 5 else WHITE
	}
	tint.a = SPAWN_PROTECTED_ALPHA if soldier.vitals.cease_fire >= 0 else 255
	return
}

// A part every style wears the same, loaded once, as the male's.
@(private = "file")
part_shared :: proc(part: Part) -> bool {
	return part.dir != "" || part.hair != .Army || part.head != .None
}

// Where a part's image is, as the original keeps it (gfx.inc): the male's, the hair and
// the headgear in gostek-gfx itself; the other styles', which the original hasn't, in a
// folder each under it; a part of its own folder's (the belt's grenades) there. The
// second team's in team2/ under that.
@(private = "file")
part_path :: proc(part: Part, style: res.Gostek, team2, mirrored: bool) -> string {
	suffix := "2.png" if mirrored else ".png"
	if part.dir != "" do return utils.temp_path(part.dir, concat(part.file, suffix))
	dir := "gostek-gfx" if style == .Male || part_shared(part) else concat("gostek-gfx/", STYLE_DIRS[style])
	if team2 do dir = concat(dir, "/team2")
	return utils.temp_path(dir, concat(part.file, suffix))
}
