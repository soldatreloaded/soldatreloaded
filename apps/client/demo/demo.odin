package demo

// Demos: a game recorded to a .srdm file as it is played, and played back, paused, sped
// up and seeked.
//
// For now, the listing alone: the demos kept in demos/, for the main menu's page. The
// recording and the playing come with the network, whose messages a demo is.
//
// Uses: net. From the C client: net/demo.c.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

DEMOS_DIR :: "demos"
EXTENSION :: ".srdm"

// A demo in demos/. What the file's header says (the map, the recorder, the length) is
// read with the format, which comes with the recording; until then the file's own time
// says when it was made.
Listing :: struct {
	name:     string, // the file's, without the extension: what playing it takes
	recorded: string, // "YYYY-MM-DD HH:MM", local time
	time:     time.Time,
}

// The demos in demos/, newest first. Free with listings_destroy.
demo_list :: proc(allocator := context.allocator) -> []Listing {
	entries, err := os.read_all_directory_by_path(DEMOS_DIR, context.temp_allocator)
	if err != nil do return nil
	local, _ := timezone.region_load("local", context.temp_allocator)
	listings := make([dynamic]Listing, allocator)
	for entry in entries {
		if entry.type == .Directory || !strings.has_suffix(strings.to_lower(entry.name, context.temp_allocator), EXTENSION) do continue
		made := entry.modification_time
		append(&listings, Listing {
			name = strings.clone(entry.name[:len(entry.name) - len(EXTENSION)], allocator),
			recorded = date_text(made, local, allocator),
			time = made,
		})
	}
	slice.sort_by(listings[:], proc(a, b: Listing) -> bool {
		if a.time != b.time do return time.diff(a.time, b.time) < 0
		return a.name > b.name
	})
	return listings[:]
}

listings_destroy :: proc(listings: []Listing, allocator := context.allocator) {
	for listing in listings {
		delete(listing.name, allocator)
		delete(listing.recorded, allocator)
	}
	delete(listings, allocator)
}

@(private = "file")
date_text :: proc(t: time.Time, local: ^datetime.TZ_Region, allocator := context.allocator) -> string {
	utc, ok := time.time_to_datetime(t)
	if !ok do return strings.clone("-", allocator)
	at := utc
	if local != nil {
		if shifted, shifted_ok := timezone.datetime_to_tz(utc, local); shifted_ok do at = shifted
	}
	return fmt.aprintf("%04d-%02d-%02d %02d:%02d", at.year, at.month, at.day, at.hour, at.minute, allocator = allocator)
}
