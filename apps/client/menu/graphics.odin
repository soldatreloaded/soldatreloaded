package menu

import "core:fmt"

import "../ui"

// What is drawn: the window (its mode, its size, vsync and the frame rate's limit, which
// the client applies as they change), then the world's scenery, weather and trails, and
// the sky, the map's colours or two of the player's own.

@(private = "file", rodata)
WINDOW_NAMES := [?]string{"Windowed", "Fullscreen", "Borderless"}

@(private = "file", rodata)
RESOLUTIONS := [?][2]i32{{640, 480}, {800, 600}, {1024, 768}, {1280, 720}, {1280, 960}, {1600, 900}, {1920, 1080}, {2560, 1440}}

@(private = "file", rodata)
RATES := [?]i32{30, 60, 75, 120, 144, 165, 240, 360, 500}

@(private = "file", rodata)
SKY_NAMES := [?]string{"The map's", "My colours"}

page_graphics :: proc(menu: ^Menu) {
	k := &menu.kit
	graphics := &menu.config.graphics
	ui.section(k, "DISPLAY")
	ui.enum_select(k, "Window", &graphics.window_mode, WINDOW_NAMES[:])
	{
		// the presets, and the size set by hand when it is none of them
		size := [2]i32{graphics.screen_width, graphics.screen_height}
		names := make([dynamic]string, context.temp_allocator)
		current := -1
		for preset, i in RESOLUTIONS {
			append(&names, fmt.tprintf("%d x %d", preset.x, preset.y))
			if preset == size do current = i
		}
		if current < 0 {
			current = len(names)
			append(&names, fmt.tprintf("%d x %d", size.x, size.y))
		}
		if picked := ui.select_box(k, "Resolution", names[:], nil, current); picked >= 0 && picked < len(RESOLUTIONS) {
			graphics.screen_width, graphics.screen_height = RESOLUTIONS[picked].x, RESOLUTIONS[picked].y
		}
	}
	ui.toggle(k, "VSync", &graphics.vsync)
	{
		// the frame rate's limit: none, a preset, or the one set by hand
		limit := clamp(graphics.max_fps, 10, 1000) if graphics.fps_limit else 0
		names := make([dynamic]string, context.temp_allocator)
		values := make([dynamic]i32, context.temp_allocator)
		append(&names, "None")
		append(&values, 0)
		current := 0
		for rate in RATES {
			if rate == limit do current = len(values)
			append(&names, fmt.tprintf("%d FPS", rate))
			append(&values, rate)
		}
		if limit != 0 && current == 0 { // set by hand: shown as it is
			current = len(values)
			append(&names, fmt.tprintf("%d FPS", limit))
			append(&values, limit)
		}
		if picked := ui.select_box(k, "Frame rate limit", names[:], nil, current); picked >= 0 && picked != current {
			graphics.fps_limit = values[picked] != 0
			if values[picked] != 0 do graphics.max_fps = values[picked]
		}
	}
	ui.section(k, "WORLD")
	ui.toggle(k, "Background scenery", &graphics.scenery)
	ui.toggle(k, "Weather", &graphics.weather)
	ui.toggle(k, "Bullet trails", &graphics.trails)
	ui.section(k, "SKY")
	if picked := ui.select_box(k, "Sky", SKY_NAMES[:], nil, 1 if graphics.force_sky else 0); picked >= 0 {
		graphics.force_sky = picked == 1
	}
	if graphics.force_sky {
		ui.color_row(k, "Sky top", &graphics.forced_sky_top)
		ui.color_row(k, "Sky bottom", &graphics.forced_sky_bottom)
	}
}
