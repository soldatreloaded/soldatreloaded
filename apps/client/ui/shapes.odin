package ui

import "core:math"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Flat shapes in units, as the C menu draws them: triangles in flat or blended colours,
// straight alpha. A hairline is one window pixel.

hairline :: proc(ui: ^Ui) -> f32 {
	return 1 / ui.scale
}

rect :: proc(ui: ^Ui, x0, y0, x1, y1: f32, color: rl.Color) {
	quad(ui, {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}, {color, color, color, color})
}

// A box with its corners rounded by `r`: a cross of three quads and a fan at each
// corner, none overlapping, so a see-through colour stays even.
rrect :: proc(ui: ^Ui, x, y, w, h, radius: f32, color: rl.Color) {
	r := min(radius, min(w, h) / 2)
	if r < 0.75 {
		rect(ui, x, y, x + w, y + h, color)
		return
	}
	rect(ui, x + r, y, x + w - r, y + h, color)
	rect(ui, x, y + r, x + r, y + h - r, color)
	rect(ui, x + w - r, y + r, x + w, y + h - r, color)
	SEGMENTS :: 6
	cx := [4]f32{x + r, x + w - r, x + w - r, x + r}
	cy := [4]f32{y + r, y + r, y + h - r, y + h - r}
	start := [4]f32{math.PI, 1.5 * math.PI, 0, 0.5 * math.PI}
	begin(ui, 4 * SEGMENTS * 3)
	for c in 0 ..< 4 {
		for s in 0 ..< SEGMENTS {
			a0 := start[c] + 0.5 * math.PI * f32(s) / SEGMENTS
			a1 := start[c] + 0.5 * math.PI * f32(s + 1) / SEGMENTS
			vertex(ui, {cx[c], cy[c]}, color)
			vertex(ui, {cx[c] + r * math.cos(a0), cy[c] + r * math.sin(a0)}, color)
			vertex(ui, {cx[c] + r * math.cos(a1), cy[c] + r * math.sin(a1)}, color)
		}
	}
	end()
}

circle :: proc(ui: ^Ui, x, y, r: f32, color: rl.Color) {
	rrect(ui, x - r, y - r, 2 * r, 2 * r, r, color)
}

// A box with its corners rounded by `r`: `fill` inside a hairline of `border`.
box_r :: proc(ui: ^Ui, x, y, w, h, r: f32, fill, border: rl.Color) {
	b := hairline(ui)
	rrect(ui, x, y, w, h, r, border)
	rrect(ui, x + b, y + b, w - 2 * b, h - 2 * b, r - b, fill)
}

// A control's box: the corners RADIUS, as every control's are.
box :: proc(ui: ^Ui, x, y, w, h: f32, fill, border: rl.Color) {
	box_r(ui, x, y, w, h, RADIUS, fill, border)
}

// A line one window pixel thick, across from `x0` to `x1` at `y`.
rule :: proc(ui: ^Ui, x0, x1, y: f32, color: rl.Color) {
	rect(ui, x0, y, x1, y + hairline(ui), color)
}

// A straight line `thickness` units wide from `a` to `b`.
line :: proc(ui: ^Ui, a, b: rl.Vector2, thickness: f32, color: rl.Color) {
	d := b - a
	length := math.sqrt(d.x * d.x + d.y * d.y)
	if length <= 0 do return
	side := rl.Vector2{-d.y, d.x} / length * (thickness / 2)
	quad(ui, {a + side, b + side, b - side, a - side}, {color, color, color, color})
}

// A small triangle pointing down (a list's box, a column sorted downwards) or up.
chevron :: proc(ui: ^Ui, x, y, size: f32, down: bool, color: rl.Color) {
	h := size * 0.6
	begin(ui, 3)
	if down {
		vertex(ui, {x - size / 2, y - h / 2}, color)
		vertex(ui, {x + size / 2, y - h / 2}, color)
		vertex(ui, {x, y + h / 2}, color)
	} else {
		vertex(ui, {x - size / 2, y + h / 2}, color)
		vertex(ui, {x, y - h / 2}, color)
		vertex(ui, {x + size / 2, y + h / 2}, color)
	}
	end()
}

// A padlock, for a server that asks a password: 7 by 9 units from `x, y`.
padlock :: proc(ui: ^Ui, x, y: f32, color: rl.Color) {
	rect(ui, x + 1, y, x + 6, y + 1, color)
	rect(ui, x + 1, y + 1, x + 2, y + 4, color)
	rect(ui, x + 5, y + 1, x + 6, y + 4, color)
	rrect(ui, x, y + 4, 7, 5, 1, color)
}

// A quad from `a` along one edge to `b` along the other: across, `a` on the left;
// else `a` at the top.
shade :: proc(ui: ^Ui, x0, y0, x1, y1: f32, a, b: rl.Color, across: bool) {
	if across {
		quad(ui, {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}, {a, b, b, a})
	} else {
		quad(ui, {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}, {a, a, b, b})
	}
}

// A glow: `color` at the middle, fading to nothing at `r`.
glow :: proc(ui: ^Ui, cx, cy, r: f32, color: rl.Color) {
	SEGMENTS :: 32
	rim := with_alpha(color, 0)
	begin(ui, SEGMENTS * 3)
	for s in 0 ..< SEGMENTS {
		a0 := 2 * math.PI * f32(s) / SEGMENTS
		a1 := 2 * math.PI * f32(s + 1) / SEGMENTS
		vertex(ui, {cx, cy}, color)
		vertex(ui, {cx + r * math.cos(a0), cy + r * math.sin(a0)}, rim)
		vertex(ui, {cx + r * math.cos(a1), cy + r * math.sin(a1)}, rim)
	}
	end()
}

// Four corners, each its own colour, in order round the quad.
quad :: proc(ui: ^Ui, corners: [4]rl.Vector2, colors: [4]rl.Color) {
	begin(ui, 6)
	for k in ([6]int{0, 1, 2, 0, 2, 3}) do vertex(ui, corners[k], colors[k])
	end()
}

// Triangles in flat colour: the white texture under them, whatever was drawn before.
@(private = "file")
begin :: proc(ui: ^Ui, vertices: i32) {
	rlgl.CheckRenderBatchLimit(vertices)
	rlgl.SetTexture(rlgl.GetTextureIdDefault())
	rlgl.Begin(rlgl.TRIANGLES)
}

@(private = "file")
end :: proc() {
	rlgl.End()
	rlgl.SetTexture(0)
}

@(private = "file")
vertex :: proc(ui: ^Ui, at: rl.Vector2, color: rl.Color) {
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	rlgl.Vertex2f(at.x * ui.scale, at.y * ui.scale)
}
