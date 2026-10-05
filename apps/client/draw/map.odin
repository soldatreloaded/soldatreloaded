package draw

import "core:math"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import res "../../../core/resources"

// The map: its sky, its polygons and its scenery. From the C client's render/map_view.c.

// The polygons drawn behind everything (the map's background ones) or in front of the
// soldiers (the rest).
Polygon_Layer :: enum {
	Background,
	Terrain,
}

// Beyond the sky's gradient: the window cleared to its colour at the camera's side.
@(private = "package")
draw_sky_behind :: proc(polymap: ^res.Poly_Map, camera: Camera) {
	rl.ClearBackground(rl.Color(polymap.sky_bottom if camera.pos.y > 0 else polymap.sky_top))
}

// The sky's gradient, anchored in the world from top to bottom, about the origin, as the
// original's is, and as wide as the view: it scrolls with the camera up and down.
@(private = "package")
draw_sky :: proc(polymap: ^res.Poly_Map, camera: Camera) {
	d := f32(res.MAX_SECTORS) * max(f32(polymap.sector_size), math.ceil(0.5 * VIEW_HEIGHT / f32(res.MAX_SECTORS)))
	x0 := camera.pos.x - camera.view.x / 2
	x1 := camera.pos.x + camera.view.x / 2
	top, bottom := polymap.sky_top, polymap.sky_bottom
	top.a, bottom.a = 255, 255 // as the original forces them

	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.QUADS)
	vertex({x0, -d}, {}, top)
	vertex({x0, d}, {}, bottom)
	vertex({x1, d}, {}, bottom)
	vertex({x1, -d}, {}, top)
	rlgl.End()
	rlgl.SetTexture(0)
}

// The layer's polygons, each corner its own colour over the map's texture.
@(private = "package")
draw_polygons :: proc(art: ^Art, polymap: ^res.Poly_Map, layer: Polygon_Layer) {
	rlgl.SetTexture(art.map_texture.id if art.map_texture.id != 0 else rlgl.GetTextureIdDefault())
	for &polygon in polymap.polygons {
		if polygon_layer(polygon) != layer do continue
		rlgl.CheckRenderBatchLimit(3)
		rlgl.Begin(rlgl.TRIANGLES)
		for k in 0 ..< 3 {
			vertex(polygon.vertices[k], polygon.uvs[k], polygon.colors[k])
		}
		rlgl.End()
	}
	rlgl.SetTexture(0)
}

// The props on one level, each its scenery image on a quad. Those whose image the mod
// hasn't are left out.
@(private = "package")
draw_scenery :: proc(art: ^Art, polymap: ^res.Poly_Map, level: res.Prop_Level) {
	for &prop in polymap.props {
		if prop.level != level || prop.scenery == 0 do continue
		corners := prop_corners(prop)
		color := prop.color
		color.a = prop.alpha // the original's: the prop's own alpha, whatever its colour's says
		draw_quad(
			art.scenery[prop.scenery - 1],
			{corners[0], corners[3], corners[2], corners[1]},
			{{0, 0}, {0, 1}, {1, 1}, {1, 0}},
			{color, color, color, color},
		)
	}
}

@(private = "file")
polygon_layer :: proc(polygon: res.Polygon) -> Polygon_Layer {
	#partial switch polygon.type {
	case .Background, .Background_Transition: return .Background
	}
	return .Terrain
}

// A prop's corners, clockwise from its top-left, as the original's GfxMat3Transform
// places them: the prop's position is its top-left, its size the map's width and height
// times the scale (not the image's own size), turned about a pivot one unit below the
// position.
@(private = "file")
prop_corners :: proc(prop: res.Prop) -> (corners: [4][2]f32) {
	w, h := f32(prop.width), f32(prop.height)
	c, s := math.cos(-prop.rotation), math.sin(-prop.rotation)
	pivot := [2]f32{prop.pos.x + s, prop.pos.y - c + 1}
	for local, i in ([4][2]f32{{0, 0}, {w, 0}, {w, h}, {0, h}}) {
		x, y := local.x * prop.scale.x, local.y * prop.scale.y
		corners[i] = pivot + {c * x - s * y, s * x + c * y}
	}
	return
}
