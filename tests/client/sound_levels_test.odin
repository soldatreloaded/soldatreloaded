package client_test

import "core:os"
import "core:strings"
import "core:testing"

import "../../apps/client/sound"
import res "../../core/resources"

// Each kind of sound's level reaches what it covers: every group has samples the game
// ships, a sample plays at its group's level, one of no group as it is, and the levels are
// the config's percents, 0 to 200.
@(test)
sound_levels_played :: proc(t: ^testing.T) {
	covered: bit_set[res.Sound_Group]
	for dir in ([2]string{"mods/classic/sounds", "mods/classic/sounds/radio"}) {
		entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		testing.expectf(t, err == nil, "%s listed", dir)
		for entry in entries {
			if !strings.has_suffix(entry.name, ".wav") do continue
			name := entry.name if dir == "mods/classic/sounds" else strings.concatenate({"radio/", entry.name}, context.temp_allocator)
			if group, grouped := sound.sound_group(name); grouped do covered += {group}
		}
	}
	for group in res.Sound_Group do testing.expectf(t, group in covered, "%v has samples the game ships", group)

	config := res.DEFAULT_CLIENT_CONFIG
	levels := res.sound_levels(&config.sound.levels)
	levels[.AK74], levels[.Spawns], levels[.Menus] = 150, 300, -5
	s: sound.Sound
	sound.sound_configure(&s, &config)
	testing.expect(t, s.levels[.AK74] == 1.5 && s.levels[.Spawns] == 2 && s.levels[.Menus] == 0 && s.levels[.Jets] == 1, "percents, 0 to 200")
	testing.expect_value(t, sound.level(&s, {name = "ak74-fire.wav", group = .AK74}), f32(1.5))
	testing.expect_value(t, sound.level(&s, {name = "a-mods-own.wav"}), f32(1))
}
