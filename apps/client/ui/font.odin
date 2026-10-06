package ui

import "core:math"
import "core:strings"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import tt "vendor:stb/truetype"

import "../../../core/utils"

// The lettering, the C client's (gfx/font.c), which is the original's: a face of the
// mod's rasterized by stb_truetype at the very size and stretch each text is drawn at,
// its glyphs drawn pixel for pixel from a pen on a whole pixel, spaced by their
// advances, the face's kerning and the text's tracking. A size is the em, as the
// original sizes its fonts; a table of glyphs is made for each size and stretch in use,
// the least lately used let go when there are too many. Without the mod's face,
// raylib's own stands in.

FIRST_GLYPH :: 32
LAST_GLYPH :: 255 // ASCII and Latin-1; anything else is drawn as '?'
PAGE_SIZE :: 1024 // pixels square, the glyphs' textures
MAX_TABLES :: 24

Font :: struct {
	data:   []u8, // the font file; none without the mod's font
	info:   tt.fontinfo,
	tables: [dynamic]^Table, // the least lately used first
}

// The font at one size and stretch, with the glyphs it has drawn so far.
@(private = "file")
Table :: struct {
	pixels:  f32, // the em
	stretch: f32,
	scale:   [2]f32, // font units to pixels
	ascent:  f32,    // pixels
	descent: f32,
	glyphs:  [LAST_GLYPH - FIRST_GLYPH + 1]Glyph,
	pages:   [dynamic]Page,
}

@(private = "file")
Glyph :: struct {
	baked:   bool,
	page:    int, // -1 without an image: a space
	uv:      [2][2]f32,
	size:    [2]f32, // pixels
	offset:  [2]f32, // from the pen to the image's top-left
	advance: f32,
}

@(private = "file")
Page :: struct {
	texture: rl.Texture2D,
	pen:     [2]i32,
	row:     i32, // the tallest glyph in the row being filled
}

// The face in the file at `path`; none (no data) if it isn't there.
font_load :: proc(path: string) -> (font: Font) {
	data, read := utils.read_file(path)
	if !read do return
	if !tt.InitFont(&font.info, raw_data(data), tt.GetFontOffsetForIndex(raw_data(data), 0)) {
		delete(data)
		return
	}
	font.data = data
	return
}

font_unload :: proc(font: ^Font) {
	for table in font.tables do table_free(table)
	delete(font.tables)
	delete(font.data)
	font^ = {}
}

// `str` drawn from `pos` in window pixels, its line's top there: an `em` pixels tall,
// `stretch` times as wide, `tracking` ems more between each two letters; over `shadow` a
// pixel down and to the right, where it has any alpha. Premultiplied, as everything is
// drawn.
@(private = "package")
font_draw :: proc(font: ^Font, str: string, pos: [2]f32, em, stretch, tracking: f32, color, shadow: rl.Color) {
	if font.data == nil {
		rl.DrawTextEx(rl.GetFontDefault(), cstr(str), pos, em, em / 10, color)
		return
	}
	table := table_find(font, em, stretch)
	pen := [2]f32{math.floor(pos.x), math.floor(pos.y + table.ascent)}
	shade := shadow
	shade.a = u8(u32(shadow.a) * u32(color.a) / 255) // fading with the text
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	defer rl.EndBlendMode()
	at := [2]f32{}
	last: rune
	for c in str {
		if c == '\n' {
			at = {0, at.y + table.ascent + table.descent}
			last = 0
			continue
		}
		c := c if c >= FIRST_GLYPH && c <= LAST_GLYPH else '?'
		if last != 0 do at.x += f32(tt.GetCodepointKernAdvance(&font.info, last, c)) * table.scale.x + tracking * em
		glyph := glyph_get(font, table, c)
		corner := pen + at + glyph.offset
		if shade.a > 0 do glyph_draw(table, glyph, corner + 1, shade)
		glyph_draw(table, glyph, corner, color)
		at.x += glyph.advance
		last = c
	}
}

// How wide `str` is drawn, in pixels: to its last glyph's right edge.
@(private = "package")
font_width :: proc(font: ^Font, str: string, em, stretch, tracking: f32) -> f32 {
	if font.data == nil do return rl.MeasureTextEx(rl.GetFontDefault(), cstr(str), em, em / 10).x
	table := table_find(font, em, stretch)
	x, right: f32
	last: rune
	for c in str {
		c := c if c >= FIRST_GLYPH && c <= LAST_GLYPH else '?'
		if last != 0 do x += f32(tt.GetCodepointKernAdvance(&font.info, last, c)) * table.scale.x + tracking * em
		glyph := glyph_get(font, table, c)
		right = max(right, x + (glyph.offset.x + glyph.size.x if glyph.size.x > 0 else glyph.advance))
		x += glyph.advance
		last = c
	}
	return right
}

// The font's ascent and descent at an em, in pixels.
@(private = "package")
font_metrics :: proc(font: ^Font, em: f32) -> (ascent, descent: f32) {
	if font.data == nil do return em * 0.8, em * 0.2
	table := table_find(font, em, 1)
	return table.ascent, table.descent
}

// The table for an em and a stretch, made on first use.
@(private = "file")
table_find :: proc(font: ^Font, em, stretch: f32) -> ^Table {
	for table, i in font.tables {
		if abs(table.pixels - em) < 0.01 && table.stretch == stretch {
			ordered_remove(&font.tables, i) // the last used goes last
			append(&font.tables, table)
			return table
		}
	}
	if len(font.tables) == MAX_TABLES {
		table_free(font.tables[0])
		ordered_remove(&font.tables, 0)
	}
	table := new(Table)
	table.pixels, table.stretch = em, stretch
	table.scale.y = tt.ScaleForMappingEmToPixels(&font.info, em)
	table.scale.x = table.scale.y * stretch
	ascent, descent, gap: i32
	tt.GetFontVMetrics(&font.info, &ascent, &descent, &gap)
	table.ascent = f32(ascent) * table.scale.y
	table.descent = f32(abs(descent)) * table.scale.y
	append(&font.tables, table)
	return table
}

@(private = "file")
table_free :: proc(table: ^Table) {
	for page in table.pages do rl.UnloadTexture(page.texture)
	delete(table.pages)
	free(table)
}

// A glyph, rasterized into the table's pages the first time it is asked for.
@(private = "file")
glyph_get :: proc(font: ^Font, table: ^Table, c: rune) -> ^Glyph {
	glyph := &table.glyphs[c - FIRST_GLYPH]
	if glyph.baked do return glyph
	glyph^ = {baked = true, page = -1}

	index := tt.FindGlyphIndex(&font.info, c)
	advance, bearing, x0, y0, x1, y1: i32
	tt.GetGlyphHMetrics(&font.info, index, &advance, &bearing)
	tt.GetGlyphBitmapBox(&font.info, index, table.scale.x, table.scale.y, &x0, &y0, &x1, &y1)
	w, h := x1 - x0, y1 - y0
	glyph.advance = f32(advance) * table.scale.x
	glyph.offset = {f32(x0), f32(y0)}
	glyph.size = {f32(w), f32(h)}
	if w <= 0 || h <= 0 do return glyph

	page, room := page_with_room(table, w, h)
	if !room do return glyph
	alpha := make([]u8, w * h, context.temp_allocator)
	tt.MakeGlyphBitmap(&font.info, raw_data(alpha), w, h, w, table.scale.x, table.scale.y, index)
	pixels := make([]utils.Rgba, w * h, context.temp_allocator)
	for a, i in alpha do pixels[i] = {a, a, a, a} // white, premultiplied
	rl.UpdateTextureRec(page.texture, {f32(page.pen.x), f32(page.pen.y), f32(w), f32(h)}, raw_data(pixels))

	glyph.page = len(table.pages) - 1
	glyph.uv = {{f32(page.pen.x), f32(page.pen.y)} / PAGE_SIZE, {f32(page.pen.x + w), f32(page.pen.y + h)} / PAGE_SIZE}
	page.pen.x += w + 1
	page.row = max(page.row, h)
	return glyph
}

// The page a w by h glyph goes on, in its rows: the last, or a new one.
@(private = "file")
page_with_room :: proc(table: ^Table, w, h: i32) -> (page: ^Page, ok: bool) {
	if w + 2 > PAGE_SIZE || h + 2 > PAGE_SIZE do return
	if len(table.pages) > 0 {
		page = &table.pages[len(table.pages) - 1]
		if page.pen.x + w + 1 > PAGE_SIZE do page^ = {texture = page.texture, pen = {1, page.pen.y + page.row + 1}}
		if page.pen.y + h + 1 <= PAGE_SIZE do return page, true
	}
	blank := rl.GenImageColor(PAGE_SIZE, PAGE_SIZE, rl.BLANK)
	defer rl.UnloadImage(blank)
	texture := rl.LoadTextureFromImage(blank)
	rl.SetTextureFilter(texture, .POINT) // drawn pixel for pixel, as the original's pages
	append(&table.pages, Page{texture = texture, pen = {1, 1}})
	return &table.pages[len(table.pages) - 1], true
}

@(private = "file")
glyph_draw :: proc(table: ^Table, glyph: ^Glyph, at: [2]f32, color: rl.Color) {
	if glyph.page < 0 do return
	a := u32(color.a)
	c := [4]u8{u8(u32(color.r) * a / 255), u8(u32(color.g) * a / 255), u8(u32(color.b) * a / 255), color.a}
	uv0, uv1 := glyph.uv[0], glyph.uv[1]
	rlgl.CheckRenderBatchLimit(4)
	rlgl.SetTexture(table.pages[glyph.page].texture.id)
	rlgl.Begin(rlgl.QUADS)
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	rlgl.TexCoord2f(uv0.x, uv0.y)
	rlgl.Vertex2f(at.x, at.y)
	rlgl.TexCoord2f(uv0.x, uv1.y)
	rlgl.Vertex2f(at.x, at.y + glyph.size.y)
	rlgl.TexCoord2f(uv1.x, uv1.y)
	rlgl.Vertex2f(at.x + glyph.size.x, at.y + glyph.size.y)
	rlgl.TexCoord2f(uv1.x, uv0.y)
	rlgl.Vertex2f(at.x + glyph.size.x, at.y)
	rlgl.End()
	rlgl.SetTexture(0)
}

@(private = "file")
cstr :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}
