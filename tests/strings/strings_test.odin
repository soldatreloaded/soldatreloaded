package strings_test

// What the game says (core/resources/strings.odin): Classic's text/strings.json as the
// game's English; a mod's lines over Classic's, a key it leaves out Classic's and one with
// the wrong placeholders passed over; Soldat 1's default.txt read, UTF-16 as it writes it,
// line by line into the game's keys; and made a mod's text by the importer.
//
//   odin test tests/strings

import "core:os"
import "core:strings"
import "core:testing"

import res "../../core/resources"
import "../../core/utils"

scratch :: proc(t: ^testing.T, name: string) -> string {
	dir := utils.temp_path(os.get_env("TEMP", context.temp_allocator) if ODIN_OS == .Windows else "/tmp", strings.concatenate({"soldatreloaded_strings_test_", name}, context.temp_allocator))
	os.remove_all(dir)
	testing.expect(t, os.make_directory_all(dir) == nil, "a scratch folder")
	return dir
}

write :: proc(path: string, data: string) {
	os.make_directory_all(path[:strings.last_index_byte(path, '/')])
	utils.write_file(path, transmute([]byte)data)
}

// `lines` as Soldat 1 writes a text file: UTF-16 little-endian, its mark first, a CRLF
// after each line.
utf16_file :: proc(lines: []string) -> string {
	out := make([dynamic]byte, context.temp_allocator)
	append(&out, 0xFF, 0xFE)
	for line in lines {
		for r in strings.concatenate({line, "\r\n"}, context.temp_allocator) {
			assert(r < 0x10000)
			append(&out, u8(r & 0xFF), u8(r >> 8))
		}
	}
	return string(out[:])
}

// Classic's strings.json is the game's English, every key, so a mod made from it has
// them all to change.
@(test)
classic_says_english :: proc(t: ^testing.T) {
	data, read := utils.read_file("assets/mods/classic/text/strings.json", context.temp_allocator)
	if !testing.expect(t, read, "Classic's strings.json") do return
	lines, ok := res.strings_read(data, "classic")
	testing.expect(t, ok, "it is JSON")
	for line, id in res.STRINGS do testing.expectf(t, lines[id] == line.english, "%s: %q, not %q", line.key, lines[id], line.english)
	english: [res.String_Id]string
	for line, id in res.STRINGS do english[id] = line.english
	as_checked_out, _ := strings.replace_all(string(data), "\r\n", "\n", context.temp_allocator) // CRLF where git makes it so
	testing.expect_value(t, as_checked_out, res.strings_json(english))
}

// A line's placeholders must be its English's, in their order: a name kept where it goes,
// a %% a % sign.
@(test)
placeholders :: proc(t: ^testing.T) {
	testing.expect_value(t, res.string_problem(.Killed_By, "Von %s getötet."), "")
	testing.expect(t, res.string_problem(.Killed_By, "Killed!") != "", "the name dropped")
	testing.expect(t, res.string_problem(.Killed_By, "%s killed %s") != "", "a name too many")
	testing.expect(t, res.string_problem(.Time_Left_Seconds, "%s seconds left") != "", "a number for a name")
	testing.expect_value(t, res.string_problem(.Time_Left_Seconds, "%d seconds, 100%% sure"), "")
	testing.expect(t, res.string_problem(.Tie, "50% off") != "", "a lone % where none goes")
	testing.expect_value(t, res.string_problem(.Dropped_Flag, "%s lost the %s flag"), "")

	s := res.Strings{}
	for line, id in res.STRINGS do s.lines[id] = line.english
	testing.expect_value(t, res.strings_text(&s, .Killed_By, "100%Pro"), "Killed by 100%Pro")
	testing.expect_value(t, res.strings_text(&s, .Time_Left_Minutes, 3), "Time Left: 3 minutes")
}

// A mod's text over Classic's: the lines it says, its own; a key it leaves out, a key no
// line has, one with the wrong placeholders and one that isn't text, Classic's.
@(test)
worn :: proc(t: ^testing.T) {
	dir := scratch(t, "worn")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "classic", "mod.json"), `{"format": 1, "name": "classic", "version": "1.0.0", "parts": ["text"]}`)
	write(utils.temp_path(dir, "classic", "text", "strings.json"), `{"tie": "A draw", "killed_by": "Classic killed by %s"}`)
	write(utils.temp_path(dir, "Loud", "mod.json"), `{"format": 1, "name": "Loud", "version": "1.0.0", "parts": ["text"]}`)
	write(utils.temp_path(dir, "Loud", "text", "strings.json"), `{"KILLED_BY": "FRAGGED BY %s", "you_killed": "Got one", "game_paused": 7, "nonsense": "x"}`)

	logger := context.logger
	context.logger.lowest_level = .Error // the warnings for Loud's mistakes are expected
	classic := res.mod_make(dir)
	defer res.mod_destroy(&classic)
	plain := res.strings_load(classic)
	defer res.strings_destroy(&plain)
	choice: [res.Part]string
	choice[.Text] = "Loud"
	loud_mod := res.mod_make(dir, choice)
	defer res.mod_destroy(&loud_mod)
	loud := res.strings_load(loud_mod)
	defer res.strings_destroy(&loud)
	context.logger = logger

	testing.expect(t, plain.lines[.Tie] == "A draw" && plain.lines[.Killed_By] == "Classic killed by %s" && plain.lines[.Game_Paused] == "Game paused", "Classic's, and English where it says none")
	testing.expect_value(t, res.strings_text(&loud, .Killed_By, "Pro"), "FRAGGED BY Pro")
	testing.expect_value(t, loud.lines[.You_Killed], "You killed %s") // its own without the name: passed over
	testing.expect_value(t, loud.lines[.Game_Paused], "Game paused")
	testing.expect_value(t, loud.lines[.Tie], "A draw") // it leaves it out: Classic's
}

// Soldat 1's default.txt, UTF-16, a line each by number: each key its line (or lines),
// "" where it says what the game's English does or can't be said; and its 1.7.1 English,
// where the install is here, saying nothing the game's doesn't.
@(test)
from_soldat :: proc(t: ^testing.T) {
	numbered := make([]string, 800, context.temp_allocator)
	for &line, i in numbered do line = "unused"
	numbered[0] = "Von %s getötet."
	numbered[1] = "%d gone" // You killed %s: the wrong placeholder
	numbered[2] = "You killed yourself" // as the game's English
	numbered[95] = "Zeit:"
	numbered[96] = "Sekunden"
	numbered[785] = "Rot"
	lines := res.strings_from_soldat(transmute([]byte)utf16_file(numbered))
	testing.expect_value(t, lines[.Killed_By], "Von %s getötet.")
	testing.expect_value(t, lines[.You_Killed], "")
	testing.expect_value(t, lines[.You_Killed_Yourself], "")
	testing.expect_value(t, lines[.Time_Left_Seconds], "Zeit: %d Sekunden")
	testing.expect_value(t, lines[.Red], "Rot")
	testing.expect_value(t, lines[.Multikill_2], "") // no line of Soldat 1's
	testing.expect_value(t, lines[.Joined_Game], "") // "unused" has no name: can't be said

	utf8_lines := res.strings_from_soldat(transmute([]byte)string("Killed by %s\r\nDu: %s\r\n"))
	testing.expect_value(t, utf8_lines[.You_Killed], "Du: %s")

	if stock, read := os.read_entire_file("C:/Soldat/txt/default.txt", context.temp_allocator); read == nil {
		english := res.strings_from_soldat(stock)
		for line, id in english do testing.expectf(t, line == "", "1.7.1's own %s says %q, not the game's %q", res.STRINGS[id].key, line, res.STRINGS[id].english)
	}
}

// The text editor's save: a mod's words written as its text/strings.json, its mod.json
// listing its text part then, and read back as it is worn; a line that drops its
// placeholder refused, nothing written.
@(test)
saved :: proc(t: ^testing.T) {
	dir := scratch(t, "saved")
	defer os.remove_all(dir)
	write(utils.temp_path(dir, "classic", "mod.json"), `{"format": 1, "name": "classic", "version": "1.0.0", "parts": ["text"]}`)
	write(utils.temp_path(dir, "classic", "text", "strings.json"), `{}`)
	testing.expect_value(t, res.mod_new(dir, "My_Text"), "")
	lines: [res.String_Id]string
	lines[.Killed_By] = "Erledigt von %s"
	lines[.Tie] = "Unentschieden"
	testing.expect_value(t, res.mod_text_write(dir, "My_Text", lines), "")
	mod, why, ok := res.srmod_open(utils.temp_path(dir, "My_Text"))
	testing.expectf(t, ok && mod.parts == {.Text} && len(mod.problems) == 0, "its text part, listed (%s)", why)
	res.srmod_close(&mod)
	testing.expect_value(t, res.mod_text_write(dir, "My_Text", lines), "") // again: listed once

	choice: [res.Part]string
	choice[.Text] = "My_Text"
	worn := res.mod_make(dir, choice)
	defer res.mod_destroy(&worn)
	said := res.strings_load(worn)
	defer res.strings_destroy(&said)
	testing.expect(t, said.lines[.Killed_By] == "Erledigt von %s" && said.lines[.Tie] == "Unentschieden" && said.lines[.You_Killed] == "You killed %s", "its lines, and Classic's where it says none")

	lines[.Killed_By] = "Erledigt"
	testing.expect(t, res.mod_text_write(dir, "My_Text", lines) != "", "a line without its name refused")
	data, _ := utils.read_file(utils.temp_path(dir, "My_Text", "text", "strings.json"), context.temp_allocator)
	testing.expect(t, strings.contains(string(data), "Erledigt von %s"), "and nothing written")
}

// A Soldat 1 mod's txt/default.txt made its text/strings.json by the importer, the lines
// that differ alone; its other txt/ files left out.
@(test)
imported :: proc(t: ^testing.T) {
	dir := scratch(t, "imported")
	defer os.remove_all(dir)
	mods := utils.temp_path(dir, "mods")
	write(utils.temp_path(mods, "classic", "mod.json"), `{"format": 1, "name": "classic", "version": "1.0.0", "parts": ["text"]}`)
	classic := res.mod_make(mods)
	defer res.mod_destroy(&classic)
	mod := utils.temp_path(dir, "Soldat", "mods", "Deutsch")
	numbered := []string{"Von %s getötet.", "You killed %s", "You killed yourself"}
	write(utils.temp_path(mod, "txt", "default.txt"), utf16_file(numbered))
	write(utils.temp_path(mod, "txt", "weaponnames.txt"), "Wüstenadler")
	write(utils.temp_path(mod, "sfx", "shot.wav"), "bang")
	result := res.mod_import({mod}, mods, "Deutsch", classic, options = {whole = true})
	if !testing.expectf(t, result.problem == "", "imported (%s)", result.problem) do return
	data, read := utils.read_file(utils.temp_path(mods, "Deutsch", "text", "strings.json"), context.temp_allocator)
	testing.expect(t, read, "its text's strings.json")
	lines, _ := res.strings_read(data, "Deutsch")
	testing.expect(t, lines[.Killed_By] == "Von %s getötet." && lines[.You_Killed] == "", "the line that differs, and no other")
	testing.expect(t, !os.exists(utils.temp_path(mods, "Deutsch", "text", "weaponnames.txt")), "no other of txt/")
}
