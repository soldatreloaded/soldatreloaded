package resources

// What a mod says of itself, mod.json in its directory (the mod's own, else the
// default's: mod_file), written as the configs are (config.odin). A key the file
// doesn't hold keeps its default; a mod without the file has them all.

MOD_CONFIG_FILE :: "mod.json"

Mod_Config :: struct {
	scale: Scale_Settings, // how big the mod's images are in the world (the original's [SCALE])
}

// An image's pixels to a unit in the world: by its path relative to the mod
// ("interface-gfx/cursor.png"), else by its folder's ("interface-gfx"), else `default`.
// Paths are matched without regard to case or which way their slashes lean.
Scale_Settings :: struct {
	default: f32,
	paths:   map[string]f32,
}

DEFAULT_MOD_SCALE :: 4.5

// The mod's mod.json, its strings and map allocated with `allocator`; the defaults if
// it hasn't one, or one that can't be read (logged). Free with mod_config_destroy.
mod_config_load :: proc(mod: Mod, allocator := context.allocator) -> (config: Mod_Config) {
	config.scale.default = DEFAULT_MOD_SCALE
	path := mod_file(mod, MOD_CONFIG_FILE)
	if config_read(path, &config, allocator) == .Broken {
		mod_config_destroy(&config, allocator) // what was read before it went wrong goes too
		config.scale.default = DEFAULT_MOD_SCALE
	}
	return
}

mod_config_destroy :: proc(config: ^Mod_Config, allocator := context.allocator) {
	for path in config.scale.paths do delete(path, allocator)
	delete(config.scale.paths)
	config^ = {}
}
