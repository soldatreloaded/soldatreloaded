package menu

import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../ui"

// What is drawn: the window (its mode, the display it is on, its resolution, vsync and the frame rate's limit,
// which the client applies as they change), then the world's scenery, weather, trails
// and sky (the map's colours or two of the player's own), then the soldiers' animations.

@(private = "file", rodata)
WINDOW_NAMES := [?]string{"Windowed", "Fullscreen"}

// How the world fits a screen of another shape than the view's (res.Screen_Fit).
@(private = "file", rodata)
FIT_NAMES := [?]string{"Letterbox", "Zoom to fill"}

// The resolutions offered, those the mode allows on the screen (resolutions), and the
// screen's own besides.
@(private = "file", rodata)
RESOLUTIONS := [?][2]i32 {
	{640, 480}, {800, 600}, {1024, 768}, {1280, 960}, {1600, 1200}, // 4:3
	{1280, 1024}, // 5:4
	{1280, 800}, {1440, 900}, {1680, 1050}, {1920, 1200}, {2560, 1600}, // 16:10
	{1280, 720}, {1366, 768}, {1600, 900}, {1920, 1080}, {2560, 1440}, {3840, 2160}, // 16:9
}

@(private = "file")
Shape :: struct {
	name:   string,
	aspect: f32,
}

// The shapes a resolution is named by.
@(private = "file", rodata)
SHAPES := [?]Shape{{"4:3", 4.0 / 3}, {"5:4", 5.0 / 4}, {"16:10", 16.0 / 10}, {"16:9", 16.0 / 9}, {"21:9", 64.0 / 27}, {"32:9", 32.0 / 9}}

// The frame rate's limit, while it is on: the client holds graphics.max_fps within them.
MAX_FPS_LOWEST :: 60
MAX_FPS_HIGHEST :: 3000

@(private = "file", rodata)
SKY_NAMES := [?]string{"The map's", "My colours"}
// In res.Air_Style's and res.Fall_Style's order: the new clips first, then Soldat 1's.
@(private = "file", rodata)
AIR_STYLE_NAMES := [?]string{"Fluid", "Classic"}
@(private = "file", rodata)
FALL_STYLE_NAMES := [?]string{"Fluid", "Ballerina"}

tab_graphics :: proc(menu: ^Menu) {
	k := &menu.kit
	graphics := &menu.config.graphics
	ui.section(k, "DISPLAY")
	ui.enum_select(k, "Window", &graphics.window_mode, WINDOW_NAMES[:])
	if count := rl.GetMonitorCount(); count > 1 {
		names := make([]string, count, context.temp_allocator)
		for i in 0 ..< count do names[i] = monitor_name(i)
		if picked := ui.select_box(k, "Monitor", names, nil, int(display_of(graphics))); picked >= 0 {
			graphics.monitor = i32(picked)
		}
	}
	ui.enum_select(k, "Screen fit", &graphics.screen_fit, FIT_NAMES[:])
	{
		current := [2]i32{graphics.screen_width, graphics.screen_height}
		sizes := resolutions(graphics.window_mode, display_of(graphics))
		names := make([]string, len(sizes) + 1, context.temp_allocator)
		at := -1
		for size, i in sizes {
			names[i] = resolution_name(size)
			if size == current do at = i
		}
		names[len(sizes)] = "Custom..."
		// A size none of the list's is the player's own: Custom, its fields open on it.
		if at < 0 && !menu.custom_size.open do custom_size_open(menu, current)
		if picked := ui.select_box(k, "Resolution", names, nil, len(sizes) if menu.custom_size.open else at); picked >= 0 {
			if picked < len(sizes) {
				graphics.screen_width, graphics.screen_height = sizes[picked].x, sizes[picked].y
				menu.custom_size.open = false
			} else {
				custom_size_open(menu, current)
			}
		}
		if menu.custom_size.open do custom_size_row(menu)
	}
	ui.toggle(k, "Keep window on top", &graphics.topmost)
	ui.toggle(k, "VSync", &graphics.vsync)
	ui.toggle(k, "Limit frame rate", &graphics.fps_limit)
	if graphics.fps_limit do ui.slider(k, "Max frame rate", &graphics.max_fps, MAX_FPS_LOWEST, MAX_FPS_HIGHEST, 10, "%d FPS")
	ui.section(k, "WORLD")
	ui.toggle(k, "Background scenery", &graphics.scenery)
	ui.toggle(k, "Weather", &graphics.weather)
	ui.toggle(k, "Bullet trails", &graphics.trails)
	ui.toggle(k, "Show other players as the classic soldier", &graphics.original_soldiers) // every style but mine drawn as the male
	ui.toggle(k, "Render smooth polygons", &graphics.smooth_polygons) // no edge texture along their outsides
	if picked := ui.select_box(k, "Sky", SKY_NAMES[:], nil, 1 if graphics.force_sky else 0); picked >= 0 {
		graphics.force_sky = picked == 1
	}
	if graphics.force_sky {
		ui.color_row(k, "Sky top", &graphics.forced_sky_top)
		ui.color_row(k, "Sky bottom", &graphics.forced_sky_bottom)
	}
	ui.section(k, "ANIMATIONS") // drawn alone: the hitboxes stay Soldat 1's
	ui.enum_select(k, "Jump wind-up", &graphics.air_wind_up, AIR_STYLE_NAMES[:])
	ui.enum_select(k, "Rising", &graphics.air_rising, AIR_STYLE_NAMES[:])
	ui.enum_select(k, "Falling", &graphics.air_falling, FALL_STYLE_NAMES[:])
	ui.enum_select(k, "Jetting", &graphics.air_jetting, AIR_STYLE_NAMES[:])
	ui.enum_select(k, "Recoil", &graphics.air_recoil, AIR_STYLE_NAMES[:]) // on the ground too
}

// The resolutions offered on this screen, smallest first, and the screen's own; any
// other size is the player's own (Custom). A window may be any of them, however it fits
// the screen: it is the player's to choose (window_windowed keeps its title bar on the
// screen). Fullscreen may be drawn at up to twice the screen's size and shrunk to it,
// which smooths it further at a cost; shrunk further than half, the smooth scaling would
// skip pixels and shimmer.
@(private = "file")
resolutions :: proc(mode: res.Window_Mode, monitor: i32) -> [][2]i32 {
	screen := [2]i32{rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor)}
	largest := screen * 2
	sizes := make([dynamic][2]i32, context.temp_allocator)
	for size in RESOLUTIONS {
		if mode == .Windowed || (size.x <= largest.x && size.y <= largest.y) do append(&sizes, size)
	}
	if !slice.contains(sizes[:], screen) do append(&sizes, screen)
	slice.sort_by(sizes[:], proc(a, b: [2]i32) -> bool {return a.x < b.x || (a.x == b.x && a.y < b.y)})
	return sizes[:]
}

// The display the window is to be on: graphics.monitor, or the primary if there is no
// such display now (it was unplugged).
display_of :: proc(graphics: ^res.Graphics_Settings) -> i32 {
	return graphics.monitor if graphics.monitor >= 0 && graphics.monitor < rl.GetMonitorCount() else 0
}

// "1: DELL U2720Q (3840 x 2160)": the display's number from 1, its name and its size.
@(private = "file")
monitor_name :: proc(monitor: i32) -> string {
	name := string(rl.GetMonitorName(monitor))
	size := fmt.tprintf("%d x %d", rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
	if name == "" do return fmt.tprintf("%d (%s)", monitor + 1, size)
	return fmt.tprintf("%d: %s (%s)", monitor + 1, name, size)
}

// "1920 x 1080 (16:9)": the size, and the shape it is near enough, if any.
@(private = "file")
resolution_name :: proc(size: [2]i32) -> string {
	aspect := f32(size.x) / f32(size.y)
	for shape in SHAPES {
		if abs(aspect / shape.aspect - 1) < 0.02 do return fmt.tprintf("%d x %d (%s)", size.x, size.y, shape.name)
	}
	return fmt.tprintf("%d x %d", size.x, size.y)
}

// The Graphics tab's resolution of the player's own: its width and its height typed,
// and taken as Enter or Apply is pressed, not as each key is, since the window follows
// it at once.
Custom_Size :: struct {
	open:    bool,
	width:   string,
	height:  string,
	problem: string, // why what was typed wasn't taken; "" for nothing
}

CUSTOM_SIZE_LOWEST :: [2]i32{320, 240}
CUSTOM_SIZE_HIGHEST :: [2]i32{7680, 4320}

// The custom fields opened on `size`.
@(private = "file")
custom_size_open :: proc(menu: ^Menu, size: [2]i32) {
	c := &menu.custom_size
	c.open = true
	set_text(&c.width, fmt.tprintf("%d", size.x))
	set_text(&c.height, fmt.tprintf("%d", size.y))
	set_text(&c.problem, "")
}

// The typed resolution's row: the width's field, "x", the height's, Apply beside them,
// and why what was typed wasn't taken under it.
@(private = "file")
custom_size_row :: proc(menu: ^Menu) {
	k := &menu.kit
	c := &menu.custom_size
	r := ui.row(k, ui.ROW_H, true)
	if r.shown {
		ui.row_label(k, r, "Width x height")
		bw := ui.button_w(k, "Apply")
		xw := ui.width_of(k.ui, ui.BODY, "x") + 12
		w := (ui.ctrl_w(r) - bw - 6 - xw) / 2
		x, y := ui.ctrl_x(r), ui.ctrl_y(r)
		if typed, changed := ui.field_box(k, r.id, r.focused, x, y, w, &c.width, c.width, 5, "2560", false); changed {
			set_text(&c.width, typed)
		}
		ui.text_mid(k, ui.BODY, "x", x + w + 6, y + ui.CTRL_H / 2, ui.MUTED)
		hx := x + w + xw
		height_id := ui.nav_next(k) // the height's own stop for the keys, as Apply has
		height_focused := ui.nav_focused(k, height_id, y, ui.CTRL_H)
		ui.focus_ring(k, height_focused, hx, y, w, ui.CTRL_H, ui.RADIUS)
		if typed, changed := ui.field_box(k, height_id, height_focused, hx, y, w, &c.height, c.height, 5, "1080", false); changed {
			set_text(&c.height, typed)
		}
		if ui.button_at(k, hx + w + 6, y, bw, ui.CTRL_H, "Apply", true, false) do custom_size_take(menu)
	}
	if ui.edit_entered(k, &c.width) || ui.edit_entered(k, &c.height) do custom_size_take(menu)
	if c.problem != "" {
		p := ui.row(k, 18, false)
		if p.shown do ui.text_fit(k, ui.TINY, c.problem, p.x + 10, p.y + p.h / 2, p.w - 20, ui.WARN)
	}
}

// The typed resolution made the config's, if both are numbers within reason. A size of
// the list's then shows as it; any other opens the fields on it again (tab_graphics).
@(private = "file")
custom_size_take :: proc(menu: ^Menu) {
	c := &menu.custom_size
	width, width_ok := strconv.parse_int(strings.trim_space(c.width), 10)
	height, height_ok := strconv.parse_int(strings.trim_space(c.height), 10)
	lo, hi := CUSTOM_SIZE_LOWEST, CUSTOM_SIZE_HIGHEST
	switch {
	case !width_ok || !height_ok:
		set_text(&c.problem, "Type a width and a height, as 2560 and 1080.")
	case width < int(lo.x) || height < int(lo.y) || width > int(hi.x) || height > int(hi.y):
		set_text(&c.problem, fmt.tprintf("From %d x %d to %d x %d.", lo.x, lo.y, hi.x, hi.y))
	case:
		set_text(&c.problem, "")
		menu.config.graphics.screen_width, menu.config.graphics.screen_height = i32(width), i32(height)
		c.open = false
	}
}
