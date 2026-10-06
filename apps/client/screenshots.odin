package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"

import "../../core/utils"

// Screenshots, in screenshots/. Raylib takes one as F12 is pressed, as it is built to, and
// writes it where the game runs, as screenshotNNN.png, counting from 000 each time the
// game starts, so each start's would overwrite the last's. Each is moved into
// screenshots/ as it is taken (and any left from before, as the game starts), numbered on
// from the last there: screenshot0001.png, screenshot0002.png, ...

SCREENSHOTS_DIR :: "screenshots"
SCREENSHOT_KEY :: "screenshot" // raylib's names', and ours'

// Raylib's screenshots where the game runs, each moved into screenshots/ under the next
// number there.
screenshots_collect :: proc() {
	taken := screenshot_files(".")
	if len(taken) == 0 do return
	os.make_directory_all(SCREENSHOTS_DIR)
	next := last_number(screenshot_files(SCREENSHOTS_DIR)) + 1
	for name in taken {
		to := utils.temp_path(SCREENSHOTS_DIR, fmt.tprintf("%s%04d.png", SCREENSHOT_KEY, next))
		if err := os.rename(name, to); err != nil {
			log.errorf("cannot move %s to %s: %v", name, to, err)
			continue
		}
		next += 1
	}
}

// The screenshots' files in `dir`, by name, oldest raylib number first.
@(private = "file")
screenshot_files :: proc(dir: string) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do return nil
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		lower := strings.to_lower(entry.name, context.temp_allocator)
		if entry.type == .Directory || !strings.has_prefix(lower, SCREENSHOT_KEY) || !strings.has_suffix(lower, ".png") do continue
		if _, numbered := screenshot_number(entry.name); numbered do append(&names, entry.name)
	}
	// raylib's numbers sort as their names do: three digits, padded
	for i in 1 ..< len(names) {
		for j := i; j > 0 && names[j] < names[j - 1]; j -= 1 do names[j], names[j - 1] = names[j - 1], names[j]
	}
	return names[:]
}

// The highest number among `names`; 0 for none.
@(private = "file")
last_number :: proc(names: []string) -> (last: int) {
	for name in names {
		if n, numbered := screenshot_number(name); numbered do last = max(last, n)
	}
	return
}

// The number in "screenshot<number>.png".
@(private = "file")
screenshot_number :: proc(name: string) -> (int, bool) {
	digits := name[len(SCREENSHOT_KEY):len(name) - len(".png")]
	if digits == "" do return 0, false
	return strconv.parse_int(digits, 10)
}
