package sandbox

// A quick look at the game: local play on one map, you and a few standing targets, drawn
// plainly with raylib. Not the client: no network, no menus, no art but the map's
// texture; soldiers are their skeletons. Run from assets/, as the game is:
//
//   odin run ../apps/sandbox                  ctf_Ash
//   odin run ../apps/sandbox -- ctf_Run       another map from data/maps
//
// A/D move, W jump, S crouch, X prone, right mouse jets, left mouse fires, Space throws a
// grenade, Q changes weapon, R reloads, F drops, E throws the flag, K kills yourself;
// 1 to 0 choose the primary for your next spawn. Esc quits.

import "core:fmt"
import "core:os"

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "../../core/game"
import res "../../core/resources"
import "../../core/utils"

ME :: game.Soldier_Id(0)
TARGETS :: 3
MODS_DIR :: "mods"

main :: proc() {
	map_name := os.args[1] if len(os.args) > 1 else "ctf_Ash"

	g := new(game.Game)
	defer free(g)
	if !game.game_init(g, game.DEFAULT_GAME_SETTINGS, authority = true) do os.exit(1)
	defer game.game_destroy(g)
	if !game.game_start_round(g, map_name, seed = 1) do os.exit(1)

	spawn(g, ME, .Alpha, .AK74)
	for i in 1 ..= TARGETS {
		spawn(g, game.Soldier_Id(i), .Bravo, .AK74)
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1280, 720, fmt.ctprintf("Soldat Reloaded sandbox: %s", map_name))
	defer rl.CloseWindow()
	rl.SetTargetFPS(game.TICK_RATE) // a tick a frame
	map_texture := load_map_texture(&g.polymap)
	defer rl.UnloadTexture(map_texture)

	camera := rl.Camera2D{}
	sequence: u32
	for !rl.WindowShouldClose() {
		me := &g.world.soldiers[ME]
		camera.offset = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())} / 2
		camera.zoom = f32(rl.GetScreenHeight()) / 480 // as much of the map as Soldat's 640x480 shows
		camera.target = me.body.pos

		choose_primary(me)
		commands: [game.MAX_PLAYERS]game.Command
		sequence += 1
		commands[ME] = {sequence = sequence, buttons = buttons(), aim = rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)}
		game.game_tick(g, &commands)

		rl.BeginDrawing()
		draw_sky(&g.polymap)
		rl.BeginMode2D(camera)
		draw_map(&g.polymap, map_texture)
		draw_world(g)
		rl.DrawCircleLinesV(commands[ME].aim, 4, rl.WHITE)
		rl.EndMode2D()
		draw_hud(g)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}

// A soldier placed on one of its team's spawn points, as the server places one.
spawn :: proc(g: ^game.Game, id: game.Soldier_Id, team: res.Team, primary: res.Weapon) {
	pos := game.spawn_point(g.world.polymap, team, &g.world.rng)
	game.apply_ruling(&g.world, &g.resources, game.Respawn{target = id, team = team, primary = primary, secondary = .USSOCOM, pos = pos})
}

buttons :: proc() -> (pressed: game.Buttons) {
	KEYS :: [?]struct {
		key:    rl.KeyboardKey,
		button: game.Button,
	} {
		{.A, .Left}, {.D, .Right}, {.W, .Jump}, {.S, .Crouch}, {.X, .Prone}, {.SPACE, .Throw},
		{.Q, .Change}, {.R, .Reload}, {.F, .Drop}, {.E, .Flag_Throw}, {.K, .Suicide},
	}
	for k in KEYS {
		if rl.IsKeyDown(k.key) do pressed += {k.button}
	}
	if rl.IsMouseButtonDown(.LEFT) do pressed += {.Fire}
	if rl.IsMouseButtonDown(.RIGHT) do pressed += {.Jet}
	return
}

// 1 to 0: the ten primaries, Desert Eagles to the Minigun, for the next spawn.
choose_primary :: proc(me: ^game.Soldier) {
	for i in 0 ..< 10 {
		key := rl.KeyboardKey(int(rl.KeyboardKey.ONE) + i) if i < 9 else rl.KeyboardKey.ZERO
		if rl.IsKeyPressed(key) do me.loadout.primary = res.Weapon(int(res.Weapon.Desert_Eagles) + i)
	}
}

// ---------------------------------------------------------------------------------
// Drawing

load_map_texture :: proc(polymap: ^res.Poly_Map) -> rl.Texture2D {
	mod := res.mod_make(MODS_DIR, "", context.temp_allocator)
	pixels, found := res.map_texture_load(mod, polymap)
	if !found do return {}
	defer res.texture_destroy(&pixels)
	image := rl.Image{data = raw_data(pixels.pixels), width = i32(pixels.width), height = i32(pixels.height), mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
	texture := rl.LoadTextureFromImage(image)
	rl.GenTextureMipmaps(&texture)
	rl.SetTextureFilter(texture, .TRILINEAR)
	rl.SetTextureWrap(texture, .REPEAT) // Soldat's polygon texture coordinates run past 0..1
	return texture
}

draw_sky :: proc(polymap: ^res.Poly_Map) {
	rl.DrawRectangleGradientV(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), color(polymap.sky_top), color(polymap.sky_bottom))
}

// The polygons, each corner its own colour over the map's texture.
draw_map :: proc(polymap: ^res.Poly_Map, texture: rl.Texture2D) {
	rlgl.DisableBackfaceCulling()
	rlgl.SetTexture(texture.id if texture.id != 0 else rlgl.GetTextureIdDefault())
	for &polygon in polymap.polygons {
		rlgl.CheckRenderBatchLimit(3)
		rlgl.Begin(rlgl.TRIANGLES)
		for k in 0 ..< 3 {
			c := polygon.colors[k]
			rlgl.Color4ub(c.r, c.g, c.b, c.a)
			rlgl.TexCoord2f(polygon.uvs[k].x, polygon.uvs[k].y)
			rlgl.Vertex2f(polygon.vertices[k].x, polygon.vertices[k].y)
		}
		rlgl.End()
	}
	rlgl.SetTexture(0)
}

draw_world :: proc(g: ^game.Game) {
	bones := g.resources.skeletons.gostek.constraints

	for &corpse in g.world.corpses {
		if !corpse.active do continue
		for bone in bones {
			rl.DrawLineEx(corpse.points[bone[0]], corpse.points[bone[1]], 1.5, rl.GRAY)
		}
	}
	for &soldier in g.world.soldiers {
		if !soldier.active || soldier.vitals.dead do continue
		joints := game.soldier_pose(g.resources.animations, &soldier, soldier.body.pos)
		for bone in bones {
			if bone[0] >= len(joints) || bone[1] >= len(joints) do continue
			rl.DrawLineEx(joints[bone[0]], joints[bone[1]], 2, team_color(soldier.team))
		}
	}
	for &thing in g.world.things {
		if thing.kind == .None do continue
		for k in 0 ..< thing.point_count {
			next := (k + 1) % thing.point_count
			rl.DrawLineEx(thing.points[k], thing.points[next], 2, thing_color(thing.kind))
		}
	}
	for &bullet in g.world.bullets {
		if bullet.active do rl.DrawLineEx(bullet.old_pos, bullet.pos, 1.5, rl.YELLOW)
	}
}

draw_hud :: proc(g: ^game.Game) {
	me := &g.world.soldiers[ME]
	weapon := g.resources.weapons[me.arsenal.primary.weapon]
	status := "dead" if me.vitals.dead else fmt.tprintf("health %.0f", me.vitals.health)
	lines := [?]string {
		fmt.tprintf("%s   %s %d   grenades %d   jets %d", status, weapon.name, me.arsenal.primary.ammo, me.arsenal.grenades, me.body.jet_fuel),
		fmt.tprintf("kills %d   deaths %d   next spawn: %s (1-0)", me.tally.kills, me.tally.deaths, g.resources.weapons[me.loadout.primary].name),
		fmt.tprintf("captures %d:%d   %d:%02d left   %d fps", g.round.captures[.Alpha], g.round.captures[.Bravo], g.round.time_left / (60 * game.TICK_RATE), g.round.time_left / game.TICK_RATE % 60, rl.GetFPS()),
	}
	for line, i in lines {
		rl.DrawText(fmt.ctprint(line), 12, 12 + i32(i) * 24, 20, rl.WHITE)
	}
}

color :: proc(c: utils.Rgba) -> rl.Color {
	return rl.Color(c)
}

team_color :: proc(team: res.Team) -> rl.Color {
	#partial switch team {
	case .Alpha: return {235, 70, 60, 255}
	case .Bravo: return {70, 120, 235, 255}
	}
	return {230, 230, 230, 255}
}

thing_color :: proc(kind: game.Thing_Kind) -> rl.Color {
	#partial switch kind {
	case .Alpha_Flag:  return {235, 70, 60, 255}
	case .Bravo_Flag:  return {70, 120, 235, 255}
	case .Medical_Kit: return rl.GREEN
	case .Grenade_Kit: return rl.ORANGE
	case .Weapon:      return rl.LIGHTGRAY
	}
	return rl.MAGENTA
}
