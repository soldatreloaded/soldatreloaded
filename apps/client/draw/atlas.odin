package draw

import rl "vendor:raylib"
import stbrp "vendor:stb/rect_pack"

import res "../../../core/resources"
import "../../../core/utils"

// An atlas: many images packed into one texture, so that what is drawn with them is
// drawn without a change of texture between them, one draw for the lot. Each image is
// ringed with a border of its own edge pixels, so the smoothing at its edge never takes
// in a neighbour's; drawn, it is its own pixels alone, as if it were a texture of its
// own. Images are packed as they are added, into the free room the earlier ones left;
// those that won't fit start another page.

ATLAS_SIDE :: 4096 // the largest page every GPU takes
ATLAS_BORDER :: 2  // pixels round each image, its edge's

Atlas :: struct {
	side:   i32,                   // its pages' width and height
	pages:  [dynamic]rl.Texture2D, // the last the one being filled
	packer: ^stbrp.Context,        // the last page's free room
	nodes:  []stbrp.Node,          // the packer's
}

// An image in an atlas: its page, and where on it the image's own pixels are, in
// texture coordinates.
Atlas_Image :: struct {
	texture: rl.Texture2D, // none for an image that wasn't there
	uv:      [2]f32,       // its top-left
	uv_size: [2]f32,
}

// The smallest page side, a power of two up to ATLAS_SIDE, that all of `images` pack
// into.
@(private = "package")
atlas_side_for :: proc(images: []res.Texture) -> i32 {
	rects := bordered_rects(images)
	nodes := make([]stbrp.Node, ATLAS_SIDE, context.temp_allocator)
	side: i32 = 64
	for ; side < ATLAS_SIDE; side *= 2 {
		packer: stbrp.Context
		stbrp.init_target(&packer, side, side, raw_data(nodes), side)
		if stbrp.pack_rects(&packer, raw_data(rects), i32(len(rects))) == 1 do break
	}
	return side
}

// One image packed in. None for an empty image.
@(private = "package")
atlas_add :: proc(atlas: ^Atlas, image: res.Texture) -> Atlas_Image {
	return atlas_add_all(atlas, {image}, context.temp_allocator)[0]
}

// Images packed in together, which packs them tighter than one at a time: the tallest
// go first. Each its place in the atlas, in their order; none for an empty image.
@(private = "package")
atlas_add_all :: proc(atlas: ^Atlas, images: []res.Texture, allocator := context.allocator) -> []Atlas_Image {
	added := make([]Atlas_Image, len(images), allocator)
	left := bordered_rects(images) // those not yet packed
	biggest := atlas.side
	for rect in left do biggest = max(biggest, i32(rect.w), i32(rect.h))
	for len(left) > 0 {
		if len(atlas.pages) == 0 do page_open(atlas, biggest)
		stbrp.pack_rects(atlas.packer, raw_data(left), i32(len(left)))
		page := atlas.pages[len(atlas.pages) - 1]
		kept := 0
		for rect in left {
			if rect.was_packed {
				added[rect.id] = image_upload(page, images[rect.id], rect)
			} else {
				left[kept] = rect
				kept += 1
			}
		}
		resize(&left, kept)
		// a new page as big as the biggest, which holds at least that one
		if kept > 0 do page_open(atlas, biggest)
	}
	return added
}

@(private = "package")
atlas_destroy :: proc(atlas: ^Atlas) {
	for page in atlas.pages do rl.UnloadTexture(page)
	delete(atlas.pages)
	delete(atlas.nodes)
	free(atlas.packer)
	atlas^ = {}
}

// A new page, see-through, `side` square, smoothed and clamped like any texture; the
// packing goes on on it.
@(private = "file")
page_open :: proc(atlas: ^Atlas, side: i32) {
	blank := rl.GenImageColor(side, side, rl.BLANK)
	page := rl.LoadTextureFromImage(blank)
	rl.UnloadImage(blank)
	rl.SetTextureFilter(page, .BILINEAR)
	rl.SetTextureWrap(page, .CLAMP)
	append(&atlas.pages, page)

	if atlas.packer == nil do atlas.packer = new(stbrp.Context)
	delete(atlas.nodes)
	atlas.nodes = make([]stbrp.Node, side)
	stbrp.init_target(atlas.packer, side, side, raw_data(atlas.nodes), side)
}

// The image at `rect` on the page, in its border.
@(private = "file")
image_upload :: proc(page: rl.Texture2D, image: res.Texture, rect: stbrp.Rect) -> Atlas_Image {
	rl.UpdateTextureRec(page, {f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}, raw_data(bordered(image)))
	page_size := [2]f32{f32(page.width), f32(page.height)}
	return {
		texture = page,
		uv      = {f32(rect.x) + ATLAS_BORDER, f32(rect.y) + ATLAS_BORDER} / page_size,
		uv_size = {f32(image.width), f32(image.height)} / page_size,
	}
}

// The image premultiplied, as every texture is (gpu.odin), in its border: its edge
// pixels repeated ATLAS_BORDER out on every side, and its corners into the corners.
@(private = "file")
bordered :: proc(image: res.Texture) -> []utils.Rgba {
	w, h := image.width + 2 * ATLAS_BORDER, image.height + 2 * ATLAS_BORDER
	pixels := make([]utils.Rgba, w * h, context.temp_allocator)
	for y in 0 ..< h {
		from_y := clamp(y - ATLAS_BORDER, 0, image.height - 1)
		for x in 0 ..< w {
			from_x := clamp(x - ATLAS_BORDER, 0, image.width - 1)
			pixels[y * w + x] = premultiply(image.pixels[from_y * image.width + from_x])
		}
	}
	return pixels
}

// Each image's room on a page, in its border, by its index in `images`; an empty image
// has none.
@(private = "file")
bordered_rects :: proc(images: []res.Texture) -> [dynamic]stbrp.Rect {
	rects := make([dynamic]stbrp.Rect, context.temp_allocator)
	for image, i in images {
		if len(image.pixels) == 0 do continue
		w, h := image.width + 2 * ATLAS_BORDER, image.height + 2 * ATLAS_BORDER
		append(&rects, stbrp.Rect{id = i32(i), w = stbrp.Coord(w), h = stbrp.Coord(h)})
	}
	return rects
}
