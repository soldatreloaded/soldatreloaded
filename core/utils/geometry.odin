package utils

// The arithmetic is single precision on purpose: every machine must compute the same
// numbers, so nothing here may widen to f64.

import "core:math"
import "core:math/linalg"

// Arithmetic, comparison and swizzles (v.x, v.yx) come with the array type.
Vec2 :: [2]f32

length :: proc(v: Vec2) -> f32 {
	return linalg.length(v)
}

// Near-zero vectors normalize to zero rather than NaN, as OpenSoldat's do.
normalize :: proc(v: Vec2) -> Vec2 {
	l := length(v)
	if l < 0.001 && l > -0.001 {
		return {}
	}
	return v / l
}

// The distance from `p` to the infinite line through `a` and `b`.
point_line_distance :: proc(a, b, p: Vec2) -> f32 {
	d := b - a
	u := linalg.dot(p - a, d) / max(math.F32_MIN, linalg.dot(d, d))
	closest := a + d * u
	return length(closest - p)
}

// Pascal's Round(): halves go to the even neighbour. Sector lookups depend on it.
round_half_even :: proc(x: f32) -> int {
	whole := math.floor(x)
	fraction := x - whole
	i := int(whole)
	switch {
	case fraction > 0.5: return i + 1
	case fraction < 0.5: return i
	case:                return i if i % 2 == 0 else i + 1
	}
}

// Where segment start-end first meets a circle (Calc.pas LineCircleCollision): an end
// inside it is the point, the start first; otherwise the crossing nearer the start.
line_circle_collision :: proc(start, end, center: Vec2, radius: f32) -> (point: Vec2, ok: bool) {
	r2 := radius * radius
	if squared_distance(start, center) <= r2 do return start, true
	if squared_distance(end, center) <= r2 do return end, true

	points, n := line_circle_intersections(start, end, center, radius)
	if n == 0 do return {}, false
	point = points[0]
	if n == 2 && squared_distance(points[0], start) > squared_distance(points[1], start) do point = points[1]
	return point, true
}

@(private = "file")
squared_distance :: proc(a, b: Vec2) -> f32 {
	d := b - a
	return d.x * d.x + d.y * d.y
}

// Calc.pas IsLineIntersectingCircle: the line as y = ax + b (flipped to x = ay + b when
// steeper than 45 degrees), the circle solved against it, and the roots kept that lie on
// the segment.
@(private = "file")
line_circle_intersections :: proc(p1, p2, center: Vec2, radius: f32) -> (points: [2]Vec2, n: int) {
	p1, p2, center := p1, p2, center
	dx, dy := p2.x - p1.x, p2.y - p1.y
	if abs(dx) < 0.00001 && abs(dy) < 0.00001 do return

	flipped := abs(dy) > abs(dx)
	if flipped {
		p1, p2, center = p1.yx, p2.yx, center.yx
		dx, dy = dy, dx
	}

	a := dy / dx
	b := p1.y - a * p1.x
	a1 := a * a + 1.0
	b1 := 2.0 * (a * b - a * center.y - center.x)
	c1 := center.y * center.y - radius * radius + center.x * center.x - 2.0 * b * center.y + b * b
	delta := b1 * b1 - 4.0 * a1 * c1
	if delta < 0 do return

	min_x, max_x := min(p1.x, p2.x), max(p1.x, p2.x)
	min_y, max_y := min(p1.y, p2.y), max(p1.y, p2.y)
	root, a2 := math.sqrt(delta), 2.0 * a1
	for k in 0 ..< 2 {
		x := (-b1 + (-root if k == 0 else root)) / a2
		y := a * x + b
		if x >= min_x && x <= max_x && y >= min_y && y <= max_y {
			points[n] = {y, x} if flipped else {x, y}
			n += 1
		}
	}
	return
}
