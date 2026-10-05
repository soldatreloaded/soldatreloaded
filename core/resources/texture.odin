package resources

import "core:log"

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

texture_destroy :: proc(texture: ^Texture, allocator := context.allocator) {
	delete(texture.pixels, allocator)
	texture^ = {}
}

// A map's texture, from the mod's textures/. False, logged, if it isn't there: the
// polygons are drawn untextured then.
map_texture_load :: proc(mod: Mod, m: ^Poly_Map, allocator := context.allocator) -> (texture: Texture, ok: bool) {
	path, found := mod_image(mod, "textures", m.texture)
	if !found {
		log.warnf("map texture '%s' not found; drawing the polygons untextured", m.texture)
		return
	}
	return texture_load(path, nil, allocator)
}

// A texture for each of a map's scenery names, from the mod's scenery-gfx/, in the
// map's order; an empty one where an image is missing, as maps often ship scenery of
// their own that the default mod hasn't got. Free with scenery_destroy.
scenery_load :: proc(mod: Mod, m: ^Poly_Map, allocator := context.allocator) -> []Texture {
	textures := make([]Texture, len(m.scenery), allocator)
	missing := 0
	for name, i in m.scenery {
		path, found := mod_image(mod, "scenery-gfx", name)
		if !found {
			missing += 1
			continue
		}
		textures[i], _ = texture_load(path, COLOR_KEY, allocator)
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
