package draw

// The world drawn with raylib: the sky, the map's polygons and scenery, the soldiers'
// art on their skeletons, the bullets, the things and the sparks; the camera, and the
// world smoothed between ticks. Reads the world, never changes it.
//
// What it is drawn with, the textures, is loaded for each match (Art): the map's, its
// scenery packed into one atlas, and the mod's sprites packed into another, so a frame
// changes texture only a handful of times however much is in it. Each kind of entity is
// drawn by its own file. A frame is built between the last two ticks (smoothing.odin),
// and the sparks, the one part with a life of its own, are fed from each tick's events
// (sparks.odin).
//
// Uses: core/game, core/resources. From the C client: render/ (map_view, gostek,
// bullet_art, things_art, sparks, camera, render_state, render, sprite, textures,
// scale_data).

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import sim "../../../core/game"
import res "../../../core/resources"

// The textures a match is drawn with.
Art :: struct {
	map_texture:   rl.Texture2D,  // none where the mod hasn't the map's: the polygons are their colours alone
	scenery:       []Atlas_Image, // by the map's scenery index; none where the mod hasn't the image
	scenery_atlas: Atlas,         // the scenery's images
	sprite_atlas:  Atlas,         // every sprite's image
	scales:        Scales,        // how big the mod's images are
	gostek:        Gostek_Art,
	bullets:       Bullet_Art,
	things:        Thing_Art,
	sparks:        Spark_Art,
}

art_load :: proc(art: ^Art, mod: res.Mod, polymap: ^res.Poly_Map) {
	// a texture of its own: the polygons' texture coordinates run past 0..1, and it repeats
	if pixels, found := res.map_texture_load(mod, polymap); found {
		art.map_texture = texture_upload(pixels)
		res.texture_destroy(&pixels)
		rl.GenTextureMipmaps(&art.map_texture)
		rl.SetTextureFilter(art.map_texture, .TRILINEAR)
		rl.SetTextureWrap(art.map_texture, .REPEAT)
	}

	images := res.scenery_load(mod, polymap)
	defer res.scenery_destroy(images)
	art.scenery_atlas = {side = atlas_side_for(images)}
	art.scenery = atlas_add_all(&art.scenery_atlas, images)

	art.scales = scales_load(mod)
	art.sprite_atlas = {side = ATLAS_SIDE}
	source := Source{mod, &art.scales, &art.sprite_atlas}
	gostek_load(&art.gostek, source)
	art.bullets = bullets_load(source)
	art.things = things_load(source)
	art.sparks = sparks_load(source)

	// Mipmapped as the original's: the map's texture, above, without a bias, as the
	// original draws its polygons; the scenery and the sprites a touch sharp. The HUD's
	// art, the original's interface, has none.
	atlas_mipmap(&art.scenery_atlas)
	atlas_mipmap(&art.sprite_atlas)
}

art_destroy :: proc(art: ^Art) {
	rl.UnloadTexture(art.map_texture)
	delete(art.scenery)
	atlas_destroy(&art.scenery_atlas)
	atlas_destroy(&art.sprite_atlas)
	scales_destroy(&art.scales)
	art^ = {}
}

// The world as `camera` sees it in `frame`, over the whole window, as the graphics
// settings have it. The original's RenderFrame order: the sky and the polygons behind,
// the back scenery, the bullets behind the soldiers, the soldiers, the
// things' sprites in front of them, the sparks, the middle scenery, the flags' cloth and
// the kits over that, then the map's polygons and the front scenery over everything.
draw_world :: proc(art: ^Art, game: ^sim.Game, frame: ^Frame, sparks: ^Sparks, camera: Camera, graphics: ^res.Graphics_Settings) {
	polymap := &game.polymap
	seconds := rl.GetTime() // what pulses goes by it
	draw_sky_behind(polymap, camera)
	rl.BeginMode2D(camera_raylib(camera))
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rlgl.DisableBackfaceCulling() // a map's polygons and a mirrored sprite face either way
	defer {
		rl.EndBlendMode() // draws what is batched, before the culling comes back
		rlgl.EnableBackfaceCulling()
		rl.EndMode2D()
	}

	draw_sky(polymap, camera)
	draw_polygons(art, polymap, .Background)
	if graphics.scenery do draw_scenery(art, polymap, .Behind_Map)
	draw_bullets(&art.bullets, &game.world, frame.alpha, graphics.grenade_color, graphics.trails)
	draw_soldiers(art, game, frame, graphics.grenade_color)
	draw_things(&art.things, game, .Sprites, frame.alpha, seconds)
	draw_sparks(&art.sparks, sparks, frame.alpha)
	draw_scenery(art, polymap, .Behind_Players)
	draw_things(&art.things, game, .Quads, frame.alpha, seconds)
	draw_polygons(art, polymap, .Terrain)
	draw_scenery(art, polymap, .In_Front)
}
