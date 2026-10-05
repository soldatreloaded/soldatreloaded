package draw

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import res "../../../core/resources"
import "../../../core/utils"

// What the GPU is given: the textures, the corners of what is drawn, and lines.
//
// Everything is drawn premultiplied, as the C client draws: the textures are
// premultiplied as they upload, each vertex's colour as it is given, and the world is
// blended with raylib's ALPHA_PREMULTIPLY. A pixel keyed out to nothing then fades to
// nothing at a sprite's edge, rather than to the black a straight blend smears in.

// A decoded image on the GPU as a texture of its own, premultiplied, smoothed and clamped
// at its edges; none for an empty one. Only the map's is: every other image is packed
// into an atlas (atlas.odin).
@(private = "package")
texture_upload :: proc(image: res.Texture) -> rl.Texture2D {
	if len(image.pixels) == 0 do return {}
	pixels := make([]utils.Rgba, len(image.pixels), context.temp_allocator)
	for pixel, i in image.pixels {
		pixels[i] = premultiply(pixel)
	}
	texture := rl.LoadTextureFromImage({
		data    = raw_data(pixels),
		width   = i32(image.width),
		height  = i32(image.height),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	})
	rl.SetTextureFilter(texture, .BILINEAR)
	rl.SetTextureWrap(texture, .CLAMP)
	return texture
}

// One corner of a quad or a triangle being drawn with rlgl.
@(private = "package")
vertex :: proc(pos, uv: [2]f32, color: utils.Rgba) {
	c := premultiply(color)
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	rlgl.TexCoord2f(uv.x, uv.y)
	rlgl.Vertex2f(pos.x, pos.y)
}

@(private = "package")
premultiply :: proc(c: utils.Rgba) -> utils.Rgba {
	a := u32(c.a)
	return {u8(u32(c.r) * a / 255), u8(u32(c.g) * a / 255), u8(u32(c.b) * a / 255), c.a}
}

// A colour's channel or its alpha worked out as a number, kept to what a byte holds.
@(private = "package")
alpha_byte :: proc(value: f32) -> u8 {
	return u8(clamp(value, 0, 255))
}
