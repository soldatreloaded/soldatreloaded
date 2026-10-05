package resources

import "core:log"
import "core:mem"
import "core:strings"

import "../utils"

// A map: a .pms file from data/maps. Its triangles (polygons) in a grid of sectors,
// colliders, spawn points, the bots' waypoints, and the scenery the client draws; and
// the questions the game asks of it: which polygons are near a point, whether a line
// is blocked, whether a point is inside the solid. Ported from OpenSoldat's MapFile.pas
// and PolyMap.pas.

MAX_POLYGONS :: 5000
MAX_SECTORS :: 25 // a map's sectors reach this many either side of the centre
MAX_PROPS :: 500
MAX_SPAWNPOINTS :: 255
MAX_COLLIDERS :: 128
MAX_WAYPOINTS :: 5000
MAX_WAYPOINT_CONNECTIONS :: 20

// The sectors a ray cast looks through, either side of the centre, whatever the map's.
RAY_CAST_SECTORS :: 35

// The teams as the map knows them: whose a team polygon is, whose a spawn point. The
// game's soldiers wear this same enum.
Team :: enum i32 {
	None,
	Alpha,
	Bravo,
	Charlie,
	Delta,
	Spectator,
}

Polygon_Type :: enum u8 {
	Normal                 = 0,
	Only_Bullets           = 1,
	Only_Player            = 2,
	Doesnt                 = 3,
	Ice                    = 4,
	Deadly                 = 5,
	Bloody_Deadly          = 6,
	Hurts                  = 7,
	Regenerates            = 8,
	Lava                   = 9,
	Red_Bullets            = 10,
	Red_Player             = 11,
	Blue_Bullets           = 12,
	Blue_Player            = 13,
	Yellow_Bullets         = 14,
	Yellow_Player          = 15,
	Green_Bullets          = 16,
	Green_Player           = 17,
	Bouncy                 = 18,
	Explodes               = 19,
	Hurts_Flaggers         = 20,
	Only_Flaggers          = 21,
	Not_Flaggers           = 22,
	Non_Flagger_Collides   = 23,
	Background             = 24,
	Background_Transition  = 25,
}

Polygon :: struct {
	vertices:   [3]utils.Vec2,
	colors:     [3]utils.Rgba,
	uvs:        [3]utils.Vec2,
	normals:    [3]utils.Vec2, // of the edges, normalized; normals[k] is edge k -> k+1's
	bounciness: f32,
	type:       Polygon_Type,
}

Spawnpoint :: struct {
	active: bool,
	pos:    utils.Vec2,
	kind:   Spawn_Kind,
}

// What a spawn point is for: a soldier of any team or of one, or a thing.
Spawn_Kind :: enum i32 {
	General        = 0,
	Alpha          = 1,
	Bravo          = 2,
	Charlie        = 3,
	Delta          = 4,
	Alpha_Flag     = 5,
	Bravo_Flag     = 6,
	Grenade_Kit    = 7,
	Medical_Kit    = 8,
	Cluster_Kit    = 9,
	Vest_Kit       = 10,
	Flamer_Kit     = 11,
	Berserk_Kit    = 12,
	Predator_Kit   = 13,
	Yellow_Flag    = 14,
	Bow            = 15,
	Stationary_Gun = 16,
}

Collider :: struct {
	active: bool,
	pos:    utils.Vec2,
	radius: f32,
}

// A piece of scenery placed by the map's author. Only drawn: nothing collides with it.
Prop :: struct {
	scenery:  int, // 1-based index into Poly_Map.scenery, 0 for none
	width:    i32,
	height:   i32,
	pos:      utils.Vec2,
	rotation: f32,
	scale:    utils.Vec2,
	alpha:    u8,
	color:    utils.Rgba,
	level:    Prop_Level,
}

Prop_Level :: enum u8 {
	Behind_Map,
	Behind_Players,
	In_Front,
}

// A point of the path net the map's author laid for the bots. They are numbered from
// 1, as their connections refer to them, with 0 for none: waypoints[0] is a blank.
Waypoint :: struct {
	active:      bool,
	pos:         utils.Vec2,
	left, right: bool,
	up, down:    bool,
	jet:         bool,
	path:        u8, // the team whose bots follow it, 0 any
	action:      u8, // 0 none, 1 stop and camp, 2-6 wait 1, 5, 10, 15 or 20 seconds
	connections: []i32,
}

Poly_Map :: struct {
	name:                string,
	texture:             string,
	sky_top:             utils.Rgba,
	sky_bottom:          utils.Rgba,
	jet_fuel:            i32, // at the start of a life
	grenade_packs:       u8,
	medikits:            u8,
	weather:             u8,
	steps:               u8,
	polygons:            []Polygon,
	background_polygons: []u16, // the indices of the Background and Background_Transition ones
	sector_size:         i32,
	sector_reach:        i32, // sectors either side of the centre: the grid is (2n+1) square
	sectors:             [][]u16, // polygon indices; see sector_polygons
	spawnpoints:         []Spawnpoint,
	waypoints:           []Waypoint,
	colliders:           []Collider,
	props:               []Prop,
	scenery:             []string, // image names, which props refer to by 1-based index
	allocator:           mem.Allocator,
}

Map_Error :: enum {
	None,
	Too_Many_Polygons,
	Bad_Sectors,
	Too_Many_Props,
	Too_Many_Colliders,
	Too_Many_Spawnpoints,
	Too_Many_Waypoints,
}

// ---------------------------------------------------------------------------------
// The file, as it lies on disk: little-endian, packed.

@(private = "file")
Pms_Header :: struct #packed {
	version:       i32le,
	name:          utils.Short_String(38),
	texture:       utils.Short_String(24),
	sky_top:       utils.Bgra,
	sky_bottom:    utils.Bgra,
	jet_fuel:      i32le,
	grenade_packs: u8,
	medikits:      u8,
	weather:       u8,
	steps:         u8,
	random_id:     i32le,
}

@(private = "file")
Pms_Vertex :: struct #packed {
	x, y, z, rhw: f32le,
	color:        utils.Bgra,
	u, v:         f32le,
}

@(private = "file")
Pms_Polygon :: struct #packed {
	vertices: [3]Pms_Vertex,
	normals:  [3][3]f32le, // x, y, z; the third's length is the polygon's bounciness
	type:     Polygon_Type,
}

@(private = "file")
Pms_Prop :: struct #packed {
	active:   bool,
	_:        u8,
	style:    u16le,
	width:    i32le,
	height:   i32le,
	x, y:     f32le,
	rotation: f32le,
	scale_x:  f32le,
	scale_y:  f32le,
	alpha:    u8,
	_:        [3]u8,
	color:    utils.Bgra,
	level:    u8,
	_:        [3]u8,
}

@(private = "file")
Pms_Scenery :: struct #packed {
	name:      utils.Short_String(50),
	timestamp: i32le,
}

@(private = "file")
Pms_Collider :: struct #packed {
	active: bool,
	_:      [3]u8,
	x, y:   f32le,
	radius: f32le,
}

@(private = "file")
Pms_Spawnpoint :: struct #packed {
	active: bool,
	_:      [3]u8,
	x, y:   i32le,
	kind:   i32le,
}

@(private = "file")
Pms_Waypoint :: struct #packed {
	active:           bool,
	_:                [3]u8,
	id:               i32le, // the editor's own numbering, which nothing reads
	x, y:             i32le,
	left, right:      bool,
	up, down:         bool,
	jet:              bool,
	path:             u8,
	action:           u8,
	_:                [5]u8,
	connection_count: i32le,
	connections:      [MAX_WAYPOINT_CONNECTIONS]i32le,
}

#assert(size_of(Pms_Polygon) == 121)
#assert(size_of(Pms_Prop) == 44)
#assert(size_of(Pms_Waypoint) == 112)

// ---------------------------------------------------------------------------------
// Loading

// A .pms file's bytes. On an error nothing is left allocated.
map_parse :: proc(data: []byte, allocator := context.allocator) -> (m: Poly_Map, err: Map_Error) {
	context.allocator = allocator
	m.allocator = allocator
	defer if err != nil {
		map_destroy(&m)
	}

	r := utils.Reader{data = data}
	header := utils.read(&r, Pms_Header)
	m.name = strings.clone(utils.short_string_text(&header.name))
	m.texture = strings.clone(utils.short_string_text(&header.texture))
	m.sky_top = utils.rgba_from_bgra(header.sky_top)
	m.sky_bottom = utils.rgba_from_bgra(header.sky_bottom)
	m.jet_fuel = 119 * i32(header.jet_fuel) / 100 // the original's "quickfix" scaling
	m.grenade_packs = header.grenade_packs
	m.medikits = header.medikits
	m.weather = header.weather
	m.steps = header.steps

	read_polygons(&r, &m) or_return
	read_sectors(&r, &m) or_return
	read_props_and_scenery(&r, &m) or_return
	read_colliders(&r, &m) or_return
	read_spawnpoints(&r, &m) or_return
	read_waypoints(&r, &m) or_return
	return m, nil
}

// <data_dir>/maps/<name>.pms. False, with the reason logged, if it can't be read.
map_load :: proc(data_dir, name: string, allocator := context.allocator) -> (m: Poly_Map, ok: bool) {
	path := utils.temp_path(data_dir, "maps", strings.concatenate({name, ".pms"}, context.temp_allocator))
	data := utils.read_file(path, context.temp_allocator) or_return

	err: Map_Error
	m, err = map_parse(data, allocator)
	if err != nil {
		log.errorf("cannot load the map %s: %v", path, err)
		return {}, false
	}
	return m, true
}

map_destroy :: proc(m: ^Poly_Map) {
	context.allocator = m.allocator
	delete(m.name)
	delete(m.texture)
	delete(m.polygons)
	delete(m.background_polygons)
	for sector in m.sectors {
		delete(sector)
	}
	delete(m.sectors)
	delete(m.spawnpoints)
	for waypoint in m.waypoints {
		delete(waypoint.connections)
	}
	delete(m.waypoints)
	delete(m.colliders)
	delete(m.props)
	for name in m.scenery {
		delete(name)
	}
	delete(m.scenery)
	m^ = {}
}

// A count read from the file, refused when it is negative or past `limit`.
@(private = "file")
read_count :: proc(r: ^utils.Reader, limit: int) -> (count: int, ok: bool) {
	count = int(utils.read(r, i32le))
	return count, count >= 0 && count <= limit
}

@(private = "file")
read_polygons :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	count, ok := read_count(r, MAX_POLYGONS)
	if !ok {
		return .Too_Many_Polygons
	}
	m.polygons = make([]Polygon, count)
	background := make([dynamic]u16)

	for &polygon, i in m.polygons {
		pms := utils.read(r, Pms_Polygon)
		for vertex, k in pms.vertices {
			polygon.vertices[k] = {f32(vertex.x), f32(vertex.y)}
			polygon.colors[k] = utils.rgba_from_bgra(vertex.color)
			polygon.uvs[k] = {f32(vertex.u), f32(vertex.v)}
		}
		for normal, k in pms.normals {
			n := utils.Vec2{f32(normal.x), f32(normal.y)}
			polygon.normals[k] = utils.normalize(n)
			if k == 2 {
				polygon.bounciness = utils.length(n)
			}
		}
		polygon.type = pms.type
		if polygon.type == .Background || polygon.type == .Background_Transition {
			append(&background, u16(i))
		}
	}
	m.background_polygons = background[:]
	return nil
}

@(private = "file")
read_sectors :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	m.sector_size = i32(utils.read(r, i32le))
	m.sector_reach = i32(utils.read(r, i32le))
	if m.sector_reach < 0 || m.sector_reach > MAX_SECTORS || m.sector_size <= 0 {
		return .Bad_Sectors
	}

	side := 2 * int(m.sector_reach) + 1
	m.sectors = make([][]u16, side * side)
	for &sector in m.sectors {
		count := int(utils.read(r, u16le))
		if count > MAX_POLYGONS {
			return .Bad_Sectors
		}
		indices := make([dynamic]u16, 0, count)
		for _ in 0 ..< count {
			index := int(utils.read(r, u16le)) - 1 // the file's are 1-based
			if index >= 0 && index < len(m.polygons) {
				append(&indices, u16(index))
			}
		}
		sector = indices[:]
	}
	return nil
}

@(private = "file")
read_props_and_scenery :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	prop_count, props_ok := read_count(r, MAX_PROPS)
	if !props_ok {
		return .Too_Many_Props
	}
	props := make([dynamic]Prop, 0, prop_count)
	for _ in 0 ..< prop_count {
		pms := utils.read(r, Pms_Prop)
		// The original hides inactive props, those on a level past the last, and those
		// naming no scenery.
		if !pms.active || pms.level > u8(max(Prop_Level)) || pms.style == 0 {
			continue
		}
		append(&props, Prop {
			scenery  = int(pms.style),
			width    = i32(pms.width),
			height   = i32(pms.height),
			pos      = {f32(pms.x), f32(pms.y)},
			rotation = f32(pms.rotation),
			scale    = {f32(pms.scale_x), f32(pms.scale_y)},
			alpha    = pms.alpha,
			color    = utils.rgba_from_bgra(pms.color),
			level    = Prop_Level(pms.level),
		})
	}
	m.props = props[:]

	scenery_count, scenery_ok := read_count(r, MAX_PROPS)
	if !scenery_ok {
		return .Too_Many_Props
	}
	m.scenery = make([]string, scenery_count)
	for &name in m.scenery {
		pms := utils.read(r, Pms_Scenery)
		name = strings.clone(utils.short_string_text(&pms.name))
	}
	for &prop in m.props {
		if prop.scenery > scenery_count {
			prop.scenery = 0
		}
	}
	return nil
}

@(private = "file")
read_colliders :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	count, ok := read_count(r, MAX_COLLIDERS)
	if !ok {
		return .Too_Many_Colliders
	}
	m.colliders = make([]Collider, count)
	for &collider in m.colliders {
		pms := utils.read(r, Pms_Collider)
		collider = {pms.active, {f32(pms.x), f32(pms.y)}, f32(pms.radius)}
	}
	return nil
}

@(private = "file")
read_spawnpoints :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	count, ok := read_count(r, MAX_SPAWNPOINTS)
	if !ok {
		return .Too_Many_Spawnpoints
	}
	m.spawnpoints = make([]Spawnpoint, count)
	for &spawnpoint in m.spawnpoints {
		pms := utils.read(r, Pms_Spawnpoint)
		x, y := i32(pms.x), i32(pms.y)
		far_out := abs(x) >= 2_000_000 || abs(y) >= 2_000_000
		spawnpoint = {pms.active && !far_out, {f32(x), f32(y)}, Spawn_Kind(pms.kind)}
	}
	return nil
}

@(private = "file")
read_waypoints :: proc(r: ^utils.Reader, m: ^Poly_Map) -> Map_Error {
	count, ok := read_count(r, MAX_WAYPOINTS)
	if !ok {
		return .Too_Many_Waypoints
	}
	m.waypoints = make([]Waypoint, count + 1)
	for &waypoint in m.waypoints[1:] {
		pms := utils.read(r, Pms_Waypoint)
		connections := make([]i32, clamp(int(pms.connection_count), 0, MAX_WAYPOINT_CONNECTIONS))
		for &connection, i in connections {
			connection = i32(pms.connections[i])
			if connection < 0 || int(connection) > count {
				connection = 0 // a connection to nowhere
			}
		}
		waypoint = {
			active      = pms.active,
			pos         = {f32(pms.x), f32(pms.y)},
			left        = pms.left,
			right       = pms.right,
			up          = pms.up,
			down        = pms.down,
			jet         = pms.jet,
			path        = pms.path,
			action      = pms.action,
			connections = connections,
		}
	}
	return nil
}

// ---------------------------------------------------------------------------------
// Queries

// The polygons in sector (x, y), counted from the centre; none outside the map's grid.
sector_polygons :: proc(m: ^Poly_Map, x, y: int) -> []u16 {
	n := int(m.sector_reach)
	if x < -n || x > n || y < -n || y > n {
		return nil
	}
	return m.sectors[(x + n) * (2 * n + 1) + (y + n)]
}

// The sector `pos` is in, as soldier collision looks: the outermost ring of sectors,
// and anything past it, holds no polygons.
polygons_near :: proc(m: ^Poly_Map, pos: utils.Vec2) -> []u16 {
	x := utils.round_half_even(pos.x / f32(m.sector_size))
	y := utils.round_half_even(pos.y / f32(m.sector_size))
	n := int(m.sector_reach)
	if x <= -n || x >= n || y <= -n || y >= n {
		return nil
	}
	return sector_polygons(m, x, y)
}

// Whether `p` is inside the triangle, by which side of each edge it is on.
point_in_polygon :: proc(p: utils.Vec2, polygon: ^Polygon) -> bool {
	a, b, c := polygon.vertices[0], polygon.vertices[1], polygon.vertices[2]
	ap := p - a
	side_ab := (b.x - a.x) * ap.y - (b.y - a.y) * ap.x > 0
	side_ac := (c.x - a.x) * ap.y - (c.y - a.y) * ap.x > 0
	if side_ac == side_ab {
		return false
	}
	side_bc := (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x) > 0
	return side_bc == side_ab
}

// Whether `p` is inside the triangle, by its edges' normals.
point_in_polygon_edges :: proc(p: utils.Vec2, polygon: ^Polygon) -> bool {
	for k in 0 ..< 3 {
		if dot(polygon.normals[k], p - polygon.vertices[k]) < 0 {
			return false
		}
	}
	return true
}

// The edge of the polygon nearest `pos`: its normal, its distance and its index.
closest_edge :: proc(polygon: ^Polygon, pos: utils.Vec2) -> (normal: utils.Vec2, distance: f32, edge: int) {
	v := polygon.vertices
	d1 := utils.point_line_distance(v[0], v[1], pos)
	d2 := utils.point_line_distance(v[1], v[2], pos)
	d3 := utils.point_line_distance(v[2], v[0], pos)

	edge, distance = 0, d1
	if d2 < d1 {
		edge, distance = 1, d2
	}
	if d3 < d2 && d3 < d1 {
		edge, distance = 2, d3
	}
	return polygon.normals[edge], distance, edge
}

// Where segment a-b crosses an edge of the polygon, if it does.
segment_crosses_polygon :: proc(a, b: utils.Vec2, polygon: ^Polygon) -> (hit: utils.Vec2, ok: bool) {
	between :: proc(v, end1, end2: f32) -> bool {
		return v > min(end1, end2) && v < max(end1, end2)
	}

	for i in 0 ..< 3 {
		p := polygon.vertices[i]
		q := polygon.vertices[(i + 1) % 3]
		segment_vertical := b.x == a.x
		edge_vertical := q.x == p.x

		switch {
		case segment_vertical && edge_vertical:
			continue
		case segment_vertical:
			slope := (q.y - p.y) / (q.x - p.x)
			hit = {a.x, slope * a.x + (p.y - slope * p.x)}
			if between(hit.x, p.x, q.x) && between(hit.y, a.y, b.y) {
				return hit, true
			}
		case edge_vertical:
			slope := (b.y - a.y) / (b.x - a.x)
			hit = {p.x, slope * p.x + (a.y - slope * a.x)}
			if between(hit.y, p.y, q.y) && between(hit.x, a.x, b.x) {
				return hit, true
			}
		case:
			segment_slope := (b.y - a.y) / (b.x - a.x)
			edge_slope := (q.y - p.y) / (q.x - p.x)
			if segment_slope == edge_slope {
				continue
			}
			segment_offset := a.y - segment_slope * a.x
			edge_offset := p.y - edge_slope * p.x
			hit.x = (edge_offset - segment_offset) / (segment_slope - edge_slope)
			hit.y = segment_slope * hit.x + segment_offset
			if between(hit.x, p.x, q.x) && between(hit.x, a.x, b.x) {
				return hit, true
			}
		}
	}
	return {}, false
}

// What a ray is cast for, which decides the polygons that stop it.
Ray_Filter :: struct {
	player: bool,
	flag:   bool, // carrying one
	bullet: bool,
	team:   Team,
}

DEFAULT_RAY_FILTER :: Ray_Filter{bullet = true}

Ray_Hit :: struct {
	distance: f32,
	point:    utils.Vec2,
	polygon:  int, // -1 when the ray was too long to cast
}

// Whether segment a-b is blocked, and where first. A ray longer than `max_distance` counts
// as blocked, at a huge distance. When it is not blocked, `hit.distance` is its length.
ray_cast :: proc(m: ^Poly_Map, a, b: utils.Vec2, max_distance: f32, filter := DEFAULT_RAY_FILTER) -> (hit: Ray_Hit, blocked: bool) {
	hit = {distance = utils.length(a - b), polygon = -1}
	if hit.distance > max_distance {
		hit.distance = 9_999_999
		return hit, true
	}

	size := f32(m.sector_size)
	low_x := utils.round_half_even(min(a.x, b.x) / size)
	low_y := utils.round_half_even(min(a.y, b.y) / size)
	high_x := utils.round_half_even(max(a.x, b.x) / size)
	high_y := utils.round_half_even(max(a.y, b.y) / size)
	if low_x > RAY_CAST_SECTORS || high_x < -RAY_CAST_SECTORS || low_y > RAY_CAST_SECTORS || high_y < -RAY_CAST_SECTORS {
		return hit, false
	}
	low_x, low_y = max(low_x, -RAY_CAST_SECTORS), max(low_y, -RAY_CAST_SECTORS)
	high_x, high_y = min(high_x, RAY_CAST_SECTORS), min(high_y, RAY_CAST_SECTORS)

	for x in low_x ..= high_x {
		for y in low_y ..= high_y {
			for index in sector_polygons(m, x, y) {
				polygon := &m.polygons[index]
				if !stops_ray(polygon.type, filter) {
					continue
				}
				if point_in_polygon(a, polygon) {
					return {0, a, int(index)}, true
				}
				if point, crosses := segment_crosses_polygon(a, b, polygon); crosses {
					return {utils.length(point - a), point, int(index)}, true
				}
			}
		}
	}
	return hit, false
}

@(private = "file")
stops_ray :: proc(type: Polygon_Type, f: Ray_Filter) -> bool {
	#partial switch type {
	case .Red_Bullets:          return f.team == .Alpha && f.bullet
	case .Red_Player:           return f.team == .Alpha && f.player
	case .Blue_Bullets:         return f.team == .Bravo && f.bullet
	case .Blue_Player:          return f.team == .Bravo && f.player
	case .Yellow_Bullets:       return f.team == .Charlie && f.bullet
	case .Yellow_Player:        return f.team == .Charlie && f.player
	case .Green_Bullets:        return f.team == .Delta && f.bullet
	case .Green_Player:         return f.team == .Delta && f.player
	case .Only_Flaggers:        return f.flag && f.player
	case .Not_Flaggers:         return !f.flag && f.player
	case .Non_Flagger_Collides: return f.flag && f.player && f.bullet
	case .Only_Bullets:         return f.bullet
	case .Only_Player:          return f.player
	case .Doesnt, .Background, .Background_Transition: return false
	}
	return true
}

// Whether `pos` is inside the solid, as a muzzle or a grenade thrown from there would be,
// and the push that would take it out of the polygon it is in.
inside_solid :: proc(m: ^Poly_Map, pos: utils.Vec2, carrying_flag: bool) -> (push: utils.Vec2, inside: bool) {
	for index in polygons_near(m, pos) {
		polygon := &m.polygons[index]
		#partial switch polygon.type {
		case .Only_Bullets, .Only_Player, .Doesnt, .Background, .Background_Transition,
		     .Red_Player, .Blue_Player, .Yellow_Player, .Green_Player:
			continue
		case .Only_Flaggers, .Not_Flaggers, .Non_Flagger_Collides:
			if !carrying_flag {
				continue
			}
		}
		if point_in_polygon(pos, polygon) {
			normal, distance, _ := closest_edge(polygon, pos)
			return normal * (1.5 * distance), true
		}
	}
	return {}, false
}

// Whether a bullet fired by `team` collides with a polygon of this type.
bullet_collides :: proc(type: Polygon_Type, team: Team) -> bool {
	#partial switch type {
	case .Red_Bullets:    return team == .Alpha
	case .Blue_Bullets:   return team == .Bravo
	case .Yellow_Bullets: return team == .Charlie
	case .Green_Bullets:  return team == .Delta
	case .Red_Player, .Blue_Player, .Yellow_Player, .Green_Player, .Non_Flagger_Collides:
		return false
	}
	return true
}

// Whether anything but a bullet, on `team`, collides with a polygon of this type.
object_collides :: proc(type: Polygon_Type, team: Team) -> bool {
	#partial switch type {
	case .Red_Player:    return team == .Alpha
	case .Blue_Player:   return team == .Bravo
	case .Yellow_Player: return team == .Charlie
	case .Green_Player:  return team == .Delta
	case .Red_Bullets, .Blue_Bullets, .Yellow_Bullets, .Green_Bullets, .Non_Flagger_Collides:
		return false
	}
	return true
}

@(private = "file")
dot :: proc(a, b: utils.Vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}
