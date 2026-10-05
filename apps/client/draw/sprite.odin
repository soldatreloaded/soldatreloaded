package draw

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

import rlgl "vendor:raylib/rlgl"

import res "../../../core/resources"
import "../../../core/utils"

// A sprite: one of the mod's images with its size in the world, drawn as a turned,
// scaled quad. The soldiers, the bullets, the things and the sparks are all sprites,
// their images packed into one atlas as they load (atlas.odin), so they draw in one go.
// How big an image is in the world is the mod's to say, in mod.ini's [SCALE] (the
// original's ScaleData): its pixels over its scale. From the C client's render/sprite.c
// and render/scale_data.c.

WHITE :: utils.Rgba{255, 255, 255, 255}

Sprite :: struct {
	image: Atlas_Image, // none where the mod hasn't the image: it draws nothing
	mask:  Atlas_Image, // its silhouette in white, for a sprite drawn in a flat colour
	size:  [2]f32,      // in world units
}

// How big the mod's images are: by a file's path ("interface-gfx/cursor.png=10"), else
// by its folder's, else the default (4.5 pixels to a unit).
Scales :: struct {
	default: f32,
	by_path: map[string]f32, // lowercase, with forward slashes, as the original keys them
}

DEFAULT_SCALE :: 4.5

// Where sprites are loaded from: the mod, and its scales; and the atlas they are packed
// into.
@(private = "package")
Source :: struct {
	mod:    res.Mod,
	scales: ^Scales,
	atlas:  ^Atlas,
}

// Sprites drawn over the world rather than in it, the HUD's: the mod's images packed into
// an atlas of their own and sized by its scales, as the world's are. Drawn with
// draw_quad, premultiplied as everything is (gpu.odin).
Sprite_Book :: struct {
	mod:    res.Mod,
	scales: Scales,
	atlas:  Atlas,
}

// A book whose atlas pages are `side` pixels square.
sprite_book_open :: proc(book: ^Sprite_Book, mod: res.Mod, side: i32) {
	book^ = {mod = mod, scales = scales_load(mod), atlas = {side = side}}
}

sprite_book_close :: proc(book: ^Sprite_Book) {
	scales_destroy(&book.scales)
	atlas_destroy(&book.atlas)
	book^ = {}
}

// An image in the mod's folder `dir`, found as the original finds one (sprite_find),
// green keyed out as the original's interface is. None if the mod hasn't it.
sprite_book_load :: proc(book: ^Sprite_Book, dir, name: string) -> Sprite {
	return sprite_find({book.mod, &book.scales, &book.atlas}, dir, name, res.COLOR_KEY)
}

// mod.ini's [SCALE]; everything at the default without one.
scales_load :: proc(mod: res.Mod) -> (scales: Scales) {
	scales.default = DEFAULT_SCALE
	text, read := utils.read_file(res.mod_file(mod, "mod.ini"), context.temp_allocator)
	if !read do return

	it := utils.ini_iterator(string(text))
	for entry in utils.ini_next(&it) {
		if !strings.equal_fold(entry.section, "SCALE") do continue
		value, is_number := strconv.parse_f32(entry.value)
		if !is_number || value <= 0 do continue
		if strings.equal_fold(entry.key, "DefaultScale") {
			scales.default = value
		} else {
			scales.by_path[scale_key(entry.key)] = value
		}
	}
	return
}

scales_destroy :: proc(scales: ^Scales) {
	for key in scales.by_path do delete(key)
	delete(scales.by_path)
	scales^ = {}
}

// The scale of the image at `path`, relative to the mod ("weapons-gfx/ak74.png").
scale_of :: proc(scales: ^Scales, path: string) -> f32 {
	key := scale_key(path, context.temp_allocator)
	if scale, found := scales.by_path[key]; found do return scale
	if slash := strings.last_index_byte(key, '/'); slash >= 0 {
		if scale, found := scales.by_path[key[:slash]]; found do return scale
	}
	return scales.default
}

// The image at `path` in the mod ("gostek-gfx/male/klata.png"). With `key`, pixels
// exactly that colour are see-through; with `flat`, it can also be drawn in a flat
// colour (draw_sprite_flat). None, drawing nothing, if it isn't there.
@(private = "package")
sprite_load :: proc(source: Source, path: string, key: Maybe(utils.Rgba) = nil, flat := false) -> Sprite {
	file := res.mod_file(source.mod, path)
	if !utils.file_exists(file) do return {} // a mirrored image some art hasn't, a style's part it leaves out
	return sprite_from(source, file, path, key, flat)
}

// An image in the mod's folder `dir` found as the original finds one: in any case,
// a .png first whatever `name`'s extension.
@(private = "package")
sprite_find :: proc(source: Source, dir, name: string, key: Maybe(utils.Rgba) = nil, flat := false) -> Sprite {
	file, found := res.mod_image(source.mod, dir, name)
	if !found do return {}
	return sprite_from(source, file, utils.temp_path(dir, name), key, flat)
}

// A quad turned by `angle` about `at` and scaled by `scale`, placed so its point
// `center` (in world units from its top-left, before the scale) lands on `at`: the
// original's DrawGostekSprite. A negative scale mirrors it.
@(private = "package")
draw_sprite :: proc(sprite: Sprite, at, center, scale: [2]f32, angle: f32, color: utils.Rgba) {
	draw_turned(sprite.image, sprite.size, at, center, scale, angle, color)
}

// The sprite's silhouette, every visible pixel `color`, flat and a little smaller; the
// art itself for a sprite loaded without one.
@(private = "package")
draw_sprite_flat :: proc(sprite: Sprite, at, center, scale: [2]f32, angle: f32, color: utils.Rgba) {
	if sprite.mask.texture.id == 0 {
		draw_sprite(sprite, at, center, scale, angle, color)
		return
	}
	draw_turned(sprite.mask, sprite.size, at, center, scale * 0.87, angle, color)
}

// An image stretched over four corners, each its own colour, `uvs` across the image from
// 0 to 1: every sprite, and the flags' cloth, the kits and the scenery over their points;
// and the HUD's pictures, in window pixels.
draw_quad :: proc(image: Atlas_Image, corners, uvs: [4][2]f32, colors: [4]utils.Rgba) {
	if image.texture.id == 0 do return
	rlgl.SetTexture(image.texture.id)
	rlgl.Begin(rlgl.QUADS)
	for k in 0 ..< 4 {
		vertex(corners[k], image.uv + uvs[k] * image.uv_size, colors[k])
	}
	rlgl.End()
	rlgl.SetTexture(0)
}

// Strings joined into a file's name, allocated with the temp allocator.
@(private = "package")
concat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

// "<stem><i + 1>.png": an animation's frame `i`, the files counted from 1.
@(private = "package")
frame_path :: proc(stem: string, i: int) -> string {
	return fmt.tprintf("%s%d.png", stem, i + 1)
}

@(private = "file")
draw_turned :: proc(image: Atlas_Image, size, at, center, scale: [2]f32, angle: f32, color: utils.Rgba) {
	c, s := math.cos(angle), math.sin(angle)
	along := [2]f32{c, s} * scale.x // the image's x axis in the world
	down := [2]f32{-s, c} * scale.y // and its y
	origin := at - along * center.x - down * center.y
	w, h := size.x, size.y
	draw_quad(
		image,
		{origin, origin + along * w, origin + along * w + down * h, origin + down * h},
		{{0, 0}, {1, 0}, {1, 1}, {0, 1}},
		{color, color, color, color},
	)
}

@(private = "file")
sprite_from :: proc(source: Source, file, path: string, key: Maybe(utils.Rgba), flat: bool) -> (sprite: Sprite) {
	image, loaded := res.texture_load(file, key, context.temp_allocator)
	if !loaded do return
	sprite.image = atlas_add(source.atlas, image)
	sprite.size = {f32(image.width), f32(image.height)} / scale_of(source.scales, path)
	if flat {
		for &pixel in image.pixels {
			pixel = {255, 255, 255, pixel.a}
		}
		sprite.mask = atlas_add(source.atlas, image)
	}
	return
}

@(private = "file")
scale_key :: proc(path: string, allocator := context.allocator) -> string {
	key, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
	return strings.to_lower(key, allocator)
}
