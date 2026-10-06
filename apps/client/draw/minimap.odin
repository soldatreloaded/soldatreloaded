package draw

import "core:math"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import res "../../../core/resources"

// The map in small, for a corner of the HUD: the original's minimap, the sky and the
// polygons. Its picture spans MINIMAP_SPAN units of width and height together, the map's
// shape kept. It is drawn for the window's size, MINIMAP_SAMPLES times over and shrunk
// as it is shown so its edges come out smooth, and drawn again when the size changes.
// From the C client's render/map_view.c.

MINIMAP_SPAN :: 260
MINIMAP_SAMPLES :: 4

Minimap :: struct {
	target: rl.RenderTexture2D, // the picture, MINIMAP_SAMPLES times the pixels it is shown at
	image:  Atlas_Image,        // the picture as draw_quad takes it: a render target is upside down
	size:   [2]f32,             // in units
	scale:  f32,                // world units to units
	offset: [2]f32,             // the world's top-left, which is its top-left
	pixels: f32,                // the window's pixels to a unit it was drawn for
	sky:    Sky,                // and the sky it was drawn with
}

// The minimap of the map drawn with `art` under `sky`, for a window of `pixels` pixels to
// a unit: drawn now, unless it was already for that window and that sky.
minimap_fit :: proc(minimap: ^Minimap, art: ^Art, polymap: ^res.Poly_Map, pixels: f32, sky: Sky) {
	if minimap.pixels == pixels && minimap.sky == sky do return
	minimap_destroy(minimap)
	minimap.pixels = pixels
	minimap.sky = sky
	low, high := map_bounds(polymap)
	extent := high - low
	minimap.scale = MINIMAP_SPAN / (extent.x + extent.y)
	minimap.offset = low
	shown := [2]i32{i32(math.round(extent.x * minimap.scale * pixels)), i32(math.round(extent.y * minimap.scale * pixels))}
	if shown.x <= 0 || shown.y <= 0 do return
	minimap.size = {f32(shown.x), f32(shown.y)} / pixels

	minimap.target = rl.LoadRenderTexture(shown.x * MINIMAP_SAMPLES, shown.y * MINIMAP_SAMPLES)
	rl.BeginTextureMode(minimap.target)
	rl.ClearBackground(rl.BLANK)
	rl.BeginMode2D({target = low, zoom = minimap.scale * pixels * MINIMAP_SAMPLES})
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rlgl.DisableBackfaceCulling()
	draw_sky_beyond(sky, polymap, low, high)
	draw_sky(sky, polymap, {pos = low + extent / 2, view = extent})
	draw_polygons(art, polymap, .Background)
	draw_polygons(art, polymap, .Terrain)
	rl.EndBlendMode()
	rlgl.EnableBackfaceCulling()
	rl.EndMode2D()
	rl.EndTextureMode()

	// shown at a quarter of its size, the mipmaps average each pixel's samples
	rl.GenTextureMipmaps(&minimap.target.texture)
	rl.SetTextureFilter(minimap.target.texture, .TRILINEAR)
	minimap.image = {texture = minimap.target.texture, uv = {0, 1}, uv_size = {1, -1}}
}

minimap_destroy :: proc(minimap: ^Minimap) {
	if minimap.target.id != 0 do rl.UnloadRenderTexture(minimap.target)
	minimap^ = {}
}

// A point in the world on the minimap, in units from its top-left.
minimap_point :: proc(minimap: ^Minimap, world: [2]f32) -> [2]f32 {
	return (world - minimap.offset) * minimap.scale
}

// The box round every polygon; a view's worth about the origin for a map without any.
@(private = "file")
map_bounds :: proc(polymap: ^res.Poly_Map) -> (low, high: [2]f32) {
	if len(polymap.polygons) == 0 do return {-640, -480}, {640, 480}
	low, high = max(f32), min(f32)
	for &polygon in polymap.polygons {
		for v in polygon.vertices {
			low = {min(low.x, v.x), min(low.y, v.y)}
			high = {max(high.x, v.x), max(high.y, v.y)}
		}
	}
	return
}

// Past the ends of the sky's gradient, where a tall map reaches: its top colour above,
// its bottom colour below.
@(private = "file")
draw_sky_beyond :: proc(sky: Sky, polymap: ^res.Poly_Map, low, high: [2]f32) {
	d := f32(res.MAX_SECTORS) * max(f32(polymap.sector_size), math.ceil(0.5 * VIEW_HEIGHT / f32(res.MAX_SECTORS)))
	top, bottom := sky.top, sky.bottom
	if low.y < -d do rl.DrawRectangleRec({low.x, low.y, high.x - low.x, -d - low.y}, rl.Color(top))
	if high.y > d do rl.DrawRectangleRec({low.x, d, high.x - low.x, high.y - d}, rl.Color(bottom))
}
