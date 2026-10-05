package hud

import "core:math"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../../../core/utils"
import "../draw"
import "../ui"

// The interface's images (the mod's interface-gfx), the lettering the HUD is written in,
// and drawing both. Everything is placed in the view's units, 480 tall, as the original
// places its interface; the layout was made for a view 640 wide, and what is anchored
// across it is stretched to the view's width (wide). From the C client's
// render/interface.c and gfx/font.c.

ART_SIDE :: 2048 // pixels square, the interface's atlas: its images fit one page

Picture :: enum {
	Health,
	Ammo,
	Jet,
	Health_Bar,
	Reload_Bar,
	Jet_Bar,
	Fire_Bar,
	Fire_Bar_Frame,
	Nade,
	Cursor,
	Menu_Cursor,
	Arrow,
	Back, // the boxes' ground, stretched to any size
	No_Flag,
	Scroll,
	Small_Dot,
	Dead_Dot,
	Flag,
	Bot,
	Connection,
}

@(private = "file", rodata)
PICTURE_FILES := [Picture]string {
	.Health         = "health.png",
	.Ammo           = "ammo.png",
	.Jet            = "jet.png",
	.Health_Bar     = "health-bar.png",
	.Reload_Bar     = "reload-bar.png",
	.Jet_Bar        = "jet-bar.png",
	.Fire_Bar       = "fire-bar.png",
	.Fire_Bar_Frame = "fire-bar-r.png",
	.Nade           = "nade.png",
	.Cursor         = "cursor.png",
	.Menu_Cursor    = "menucursor.png",
	.Arrow          = "arrow.png",
	.Back           = "back.png",
	.No_Flag        = "noflag.png",
	.Scroll         = "scroll.png",
	.Small_Dot      = "smalldot.png",
	.Dead_Dot       = "deaddot.png",
	.Flag           = "flag.png",
	.Bot            = "bot.png",
	.Connection     = "connection.png",
}

// Each weapon's icon, for the kill feed, the weapons menu and the stats: the original's
// GFX_INTERFACE_GUNS_, and the grenade's own.
@(private = "file", rodata)
GUN_FILES := [res.Weapon]string {
	.Punch         = "guns/fist.png",
	.Desert_Eagles = "guns/1.png",
	.MP5           = "guns/2.png",
	.AK74          = "guns/3.png",
	.Steyr_AUG     = "guns/4.png",
	.Spas12        = "guns/5.png",
	.Ruger77       = "guns/6.png",
	.M79           = "guns/7.png",
	.Barrett       = "guns/8.png",
	.Minimi        = "guns/9.png",
	.Minigun       = "guns/0.png",
	.USSOCOM       = "guns/10.png",
	.Knife         = "guns/knife.png",
	.Chainsaw      = "guns/chainsaw.png",
	.LAW           = "guns/law.png",
	.Frag_Grenade  = "nade.png",
	.Thrown_Knife  = "guns/knife.png",
}

Art :: struct {
	book:     draw.Sprite_Book,
	pictures: [Picture]draw.Sprite,
	guns:     [res.Weapon]draw.Sprite,
}

art_load :: proc(art: ^Art, mod: res.Mod) {
	draw.sprite_book_open(&art.book, mod, ART_SIDE)
	for file, picture in PICTURE_FILES do art.pictures[picture] = interface_image(art, file)
	for file, weapon in GUN_FILES do art.guns[weapon] = interface_image(art, file)
}

art_destroy :: proc(art: ^Art) {
	draw.sprite_book_close(&art.book)
	art^ = {}
}

// An image of interface-gfx, by its path there: "health.png", "guns/1.png".
@(private = "file")
interface_image :: proc(art: ^Art, path: string) -> draw.Sprite {
	dir, name := "interface-gfx", path
	if slash := strings.last_index_byte(path, '/'); slash >= 0 {
		dir = strings.concatenate({dir, "/", path[:slash]}, context.temp_allocator)
		name = path[slash + 1:]
	}
	return draw.sprite_book_load(&art.book, dir, name)
}

// ---------------------------------------------------------------------------------
// Pictures

LAYOUT_WIDTH :: 640 // the view the layout was made for
STATUS_ALPHA :: 200 // ui_status_transparency: the pictures' and the boxes' alpha
BOX_ALPHA :: STATUS_ALPHA * 56 / 100
FULL_BOX_ALPHA :: 255 * 56 / 100 // the team box's, of the interface's own alpha
BACK_SIDE :: 64 // the Back picture's side, in units

// How much wider the view is than the layout's: what is anchored across it is placed
// this much further over.
wide :: proc(u: ^ui.Ui) -> f32 {
	return u.width / LAYOUT_WIDTH
}

// `v` units down to a whole window pixel, as the original aligns its pictures.
align :: proc(u: ^ui.Ui, v: f32) -> f32 {
	return math.floor(v * u.scale) / u.scale
}

// `sprite` with its top-left at `pos`, `scale` times its size, turned by `angle` about
// its top-left, in `color`. Only `part` of it, its share of the image across and down,
// as a bar shows the share it stands for.
picture :: proc(
	u: ^ui.Ui,
	sprite: draw.Sprite,
	pos: [2]f32,
	color: rl.Color,
	scale := [2]f32{1, 1},
	angle: f32 = 0,
	part := rl.Rectangle{0, 0, 1, 1},
) {
	if sprite.image.texture.id == 0 do return
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY) // the atlas is premultiplied, as the world's
	c, s := math.cos(angle), math.sin(angle)
	along := [2]f32{c, s} * sprite.size.x * scale.x * part.width
	down := [2]f32{-s, c} * sprite.size.y * scale.y * part.height
	// down the left first, as raylib winds a quad: the other way round is culled
	corners := [4][2]f32{pos, pos + down, pos + along + down, pos + along}
	for &corner in corners do corner *= u.scale
	left, top, right, bottom := part.x, part.y, part.x + part.width, part.y + part.height
	tint := utils.Rgba(color)
	draw.draw_quad(sprite.image, corners, {{left, top}, {left, bottom}, {right, bottom}, {right, top}}, {tint, tint, tint, tint})
}

// The boxes' ground over `rect`: the Back picture stretched to it.
box :: proc(u: ^ui.Ui, art: ^Art, rect: rl.Rectangle, alpha: u8 = BOX_ALPHA) {
	picture(u, art.pictures[.Back], {rect.x, rect.y}, {255, 255, 255, alpha}, {rect.width, rect.height} / BACK_SIDE)
}

// A flat rectangle.
fill :: proc(u: ^ui.Ui, rect: rl.Rectangle, color: rl.Color) {
	rl.EndBlendMode()
	rl.DrawRectangleRec(ui.pixels(u, rect), color)
}

// A pixel-tall line `length` units long: the original's DrawLine.
line :: proc(u: ^ui.Ui, pos: [2]f32, length: f32, color: rl.Color) {
	fill(u, {align(u, pos.x), align(u, pos.y), length, 1 / u.scale}, color)
}

with_alpha :: proc(color: rl.Color, alpha: int) -> rl.Color {
	return {color.r, color.g, color.b, u8(clamp(alpha, 0, 255))}
}

// ---------------------------------------------------------------------------------
// Lettering

// A face's size and stretch: the original's font styles (gfx/font.c's STYLE_SPECS), all
// of them in the mod's font. The size is the em, in units: the style's points as
// pixels (96 to 72) at the view's 480, sized with the window as the view is.
Lettering :: struct {
	size:    f32,
	stretch: f32, // as much wider than the font has it
}

POINT :: 96.0 / 72.0 // in units

MENU_FONT :: Lettering{12 * POINT, 1.5} // the menus, the HUD's numbers
SMALL_FONT :: Lettering{9 * POINT, 1.25} // the console, the status, most of the texts
SMALLEST_FONT :: Lettering{7 * POINT, 1.25}
WEAPONS_FONT :: Lettering{8 * POINT, 1.25} // the weapon's name, the kill feed
BIG_FONT :: Lettering{28 * POINT, 1.5} // the big messages

SHADOW :: rl.Color{0, 0, 0, 255}

// `str` at `pos`, its line's top there unless `vertical` says otherwise, over its shadow.
write :: proc(u: ^ui.Ui, str: string, pos: [2]f32, font: Lettering, color: rl.Color, shadow := SHADOW, vertical := ui.Vertical.Top) {
	ui.text(u, str, pos, font.size, color, font.stretch, shadow, vertical)
}

text_width :: proc(u: ^ui.Ui, str: string, font: Lettering) -> f32 {
	return ui.text_width(u, str, font.size, font.stretch)
}

// A line's height in `font`: its ascent and descent.
line_height :: proc(u: ^ui.Ui, font: Lettering) -> f32 {
	return ui.line_height(u, font.size)
}
