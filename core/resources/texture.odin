package resources

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"

import stbi "vendor:stb/image"

import "../utils"

// An image decoded to straight (not premultiplied) RGBA pixels, row by row from the top:
// what the client uploads to the GPU, and the server never needs. PNG, BMP and GIF, the
// formats Soldat's art comes in.

Texture :: struct {
	width:  int,
	height: int,
	pixels: []utils.Rgba,
}

// Soldat's older art marks what is see-through with pure green rather than an alpha
// channel (the original's ApplyColorKey).
COLOR_KEY :: utils.Rgba{0, 255, 0, 255}

// And a few of its images (the smoke, the spawn's spark, the parachute's rope) black.
BLACK_KEY :: utils.Rgba{0, 0, 0, 255}

// An image file's bytes; any pixel exactly `color_key` made fully transparent.
texture_decode :: proc(data: []byte, color_key: Maybe(utils.Rgba) = nil, allocator := context.allocator) -> (texture: Texture, ok: bool) {
	width, height, channels: i32
	decoded := stbi.load_from_memory(raw_data(data), i32(len(data)), &width, &height, &channels, 4)
	if decoded == nil {
		return
	}
	defer stbi.image_free(decoded)

	texture = {int(width), int(height), make([]utils.Rgba, int(width) * int(height), allocator)}
	copy(texture.pixels, ([^]utils.Rgba)(decoded)[:len(texture.pixels)])

	if key, keyed := color_key.?; keyed {
		for &pixel in texture.pixels {
			if pixel == key {
				pixel = {}
			}
		}
	}
	return texture, true
}

// An image file. False, with the reason logged, if it can't be read or decoded.
texture_load :: proc(path: string, color_key: Maybe(utils.Rgba) = nil, allocator := context.allocator) -> (texture: Texture, ok: bool) {
	data := utils.read_file(path, context.temp_allocator) or_return
	texture, ok = texture_decode(data, color_key, allocator)
	if !ok {
		log.errorf("cannot decode the image %s: %s", path, stbi.failure_reason())
	}
	return
}

// An image found in a mod. False, with the reason logged, if it can't be read or decoded.
texture_load_file :: proc(file: Mod_File, color_key: Maybe(utils.Rgba) = nil, allocator := context.allocator) -> (texture: Texture, ok: bool) {
	data := mod_read(file, context.temp_allocator) or_return
	texture, ok = texture_decode(data, color_key, allocator)
	if !ok {
		log.errorf("cannot decode the image %s: %s", mod_file_name(file), stbi.failure_reason())
	}
	return
}

texture_destroy :: proc(texture: ^Texture, allocator := context.allocator) {
	delete(texture.pixels, allocator)
	texture^ = {}
}

// A map's texture, from textures/: the mod's, the map's own (`map_dirs`, map_image), or
// Classic's. False, logged, if it isn't there: the polygons are drawn untextured then.
map_texture_load :: proc(mod: Mod, m: ^Poly_Map, map_dirs: []string = nil, allocator := context.allocator) -> (texture: Texture, ok: bool) {
	file, found := map_image(mod, map_dirs, "textures", m.texture)
	if !found {
		log.warnf("map texture '%s' not found; drawing the polygons untextured", m.texture)
		return
	}
	return texture_load_file(file, nil, allocator)
}

// The texture a map's polygons' outer edges are drawn with (the original's smooth
// edges): its texture's own in textures/edges/ (the mod's, the map's own, Classic's), else
// edges/default, green keyed out. False, logged, if neither is there.
map_edge_texture_load :: proc(mod: Mod, m: ^Poly_Map, map_dirs: []string = nil, allocator := context.allocator) -> (texture: Texture, scale: f32, ok: bool) {
	file, found := map_image(mod, map_dirs, "textures/edges", m.texture)
	if !found do file, found = mod_image(mod, "textures/edges", "default.bmp")
	if !found {
		log.warn("no edge texture in textures/edges, nor its default; drawing no edges")
		return
	}
	texture, ok = texture_load_file(file, COLOR_KEY, allocator)
	return texture, mod_file_scale(file), ok
}

// A texture for each of a map's scenery names, from scenery-gfx/ (the mod's, the map's
// own, Classic's), in the map's order; an empty one where an image is missing, as a map
// may draw with scenery that neither it nor the mods have. Free with scenery_destroy.
scenery_load :: proc(mod: Mod, m: ^Poly_Map, map_dirs: []string = nil, allocator := context.allocator) -> []Texture {
	textures := make([]Texture, len(m.scenery), allocator)
	missing := 0
	for name, i in m.scenery {
		file, found := map_image(mod, map_dirs, "scenery-gfx", name)
		if !found {
			missing += 1
			continue
		}
		textures[i], _ = texture_load_file(file, COLOR_KEY, allocator)
	}
	if missing > 0 {
		log.warnf("%d of %d scenery images not found in scenery-gfx", missing, len(m.scenery))
	}
	return textures
}

scenery_destroy :: proc(textures: []Texture, allocator := context.allocator) {
	for &texture in textures {
		texture_destroy(&texture, allocator)
	}
	delete(textures, allocator)
}

// `texture` `by` times as big (each side rounded, a pixel at least), with the temp
// allocator. Up, it is first made a whole number of times as big, each pixel kept a
// sharp square, then brought down to the size smoothed: so old pixel art stays crisp,
// its edges a half pixel soft at most. Down, it is smoothed. The colours are weighted
// by their alpha, so what is see-through bleeds into nothing.
texture_rescale :: proc(texture: Texture, by: f32) -> Texture {
	w := max(int(math.round(f32(texture.width) * by)), 1)
	h := max(int(math.round(f32(texture.height) * by)), 1)
	if w == texture.width && h == texture.height do return texture
	from := texture
	if by > 1 {
		k := int(math.ceil(by))
		sharp := Texture{texture.width * k, texture.height * k, make([]utils.Rgba, texture.width * k * texture.height * k, context.temp_allocator)}
		for y in 0 ..< sharp.height {
			for x in 0 ..< sharp.width do sharp.pixels[y * sharp.width + x] = texture.pixels[(y / k) * texture.width + x / k]
		}
		from = sharp
		if from.width == w && from.height == h do return from
	}
	return texture_shrink(from, w, h)
}

// `from` brought down to `w` by `h`: each pixel the average of the part of `from` it
// covers, by how much of each pixel it covers, the colours weighted by their alpha. Our
// own rather than stb's resize, which raylib has inside it already, and the two can't be
// linked together.
@(private = "file")
texture_shrink :: proc(from: Texture, w, h: int) -> Texture {
	to := Texture{w, h, make([]utils.Rgba, w * h, context.temp_allocator)}
	sx, sy := f32(from.width) / f32(w), f32(from.height) / f32(h)
	for ty in 0 ..< h {
		y0, y1 := f32(ty) * sy, f32(ty + 1) * sy
		for tx in 0 ..< w {
			x0, x1 := f32(tx) * sx, f32(tx + 1) * sx
			r, g, b, a, covered: f32
			for y in int(y0) ..< min(int(math.ceil(y1)), from.height) {
				wy := min(y1, f32(y + 1)) - max(y0, f32(y))
				for x in int(x0) ..< min(int(math.ceil(x1)), from.width) {
					weight := (min(x1, f32(x + 1)) - max(x0, f32(x))) * wy
					p := from.pixels[y * from.width + x]
					alpha := f32(p.a) * weight
					r += f32(p.r) * alpha
					g += f32(p.g) * alpha
					b += f32(p.b) * alpha
					a += alpha
					covered += weight
				}
			}
			if a <= 0 || covered <= 0 do continue
			to.pixels[ty * w + tx] = {u8(math.round(r / a)), u8(math.round(g / a)), u8(math.round(b / a)), u8(math.round(a / covered))}
		}
	}
	return to
}

// `texture` as a PNG's bytes, its alpha kept: with the temp allocator.
texture_png :: proc(texture: Texture) -> []byte {
	out := make([dynamic]byte, context.temp_allocator)
	stbi.write_png_to_func(proc "c" (ctx: rawptr, data: rawptr, size: c.int) {
		context = runtime.default_context()
		context.allocator = context.temp_allocator
		append((^[dynamic]byte)(ctx), ..([^]byte)(data)[:size])
	}, &out, c.int(texture.width), c.int(texture.height), 4, raw_data(texture.pixels), c.int(texture.width * 4))
	return out[:]
}
