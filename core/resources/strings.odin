package resources

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf16"

// What the game says to the player in a match, a mod's `text` part (docs/srmod.md): the
// big words, the kill feed's and the console's lines, the scoreboard's and the HUD's
// words. text/strings.json says them by key, each a line of text with the placeholders
// its English has (%s a name, %d a number), in their order:
//
//   {"killed_by": "Killed by %s", "flag_returned_red": "Red Flag returned!"}
//
// A key a mod leaves out is Classic's, and one whose placeholders aren't its English's is
// passed over, logged, as it would print the wrong thing or nothing. Soldat 1 says the
// same in its txt/default.txt (and its txt/languages/*.txt), a line each by number,
// UTF-16: strings_from_soldat reads one, by each key's line (STRINGS[id].soldat).

STRINGS_FILE :: "strings.json" // in the text part

String_Id :: enum {
	// kills
	Killed_By,
	You_Killed,
	You_Killed_Yourself,
	Multikill_2, Multikill_3, Multikill_4, Multikill_5, Multikill_6, Multikill_7, Multikill_8, Multikill_9,
	Multikill_10, Multikill_11, Multikill_12, Multikill_13, Multikill_14, Multikill_15, Multikill_16, Multikill_17,
	// the flags
	You_Got_Red_Flag,
	You_Got_Blue_Flag,
	Red_Flag_Captured,
	Blue_Flag_Captured,
	Captured_Red_Flag,
	Captured_Blue_Flag,
	Red_Flag_Returned,
	Blue_Flag_Returned,
	Returned_Red_Flag,
	Returned_Blue_Flag,
	Flag_Dropped,
	Dropped_Flag,
	Red,
	Blue,
	// the teams' scores and the round's end
	Alpha_Scores,
	Bravo_Scores,
	Scores_For_Alpha,
	Scores_For_Bravo,
	Alpha_Team_Wins,
	Bravo_Team_Wins,
	Tie,
	Alpha_Wins,
	Bravo_Wins,
	Time_Left_Seconds,
	Time_Left_Minutes,
	// who came and went
	Joined_Game,
	Joined_Alpha,
	Joined_Bravo,
	Joined_Charlie,
	Joined_Delta,
	Joined_Spectators,
	Left_Game,
	Left_Alpha,
	Left_Bravo,
	Left_Charlie,
	Left_Delta,
	Left_Spectators,
	// the HUD
	Respawn_In,
	Game_Paused,
	Following,
	Free_Camera,
	Weapons_Menu_Disabled,
	Weapons_Menu_Active,
	Primary_Weapon,
	Secondary_Weapon,
	Select_Team,
	Escape_To_Game,
	Shot_Distance,
	Shot_Airtime,
	Shot_Ricochets,
	// the scoreboard
	Board_Time,
	Board_Players,
	Board_Points,
	Board_Deaths,
	Board_Ping,
	// votes
	Vote_Kick,
	Vote_Map,
	Vote_Voter,
	Vote_Reason,
	Vote_Keys,
	Vote_Reason_Prompt,
	Menu_Back,
	Menu_On,
	Menu_Kick,
	Menu_Ban,
	Menu_Select,
	// the round's end screen
	Summary_Tie,
	Summary_Alpha_Wins,
	Summary_Bravo_Wins,
	Summary_Player,
	Summary_Kills,
	Summary_Deaths,
	Summary_Captures,
	Summary_Accuracy,
	Summary_Headshots,
	Summary_Streak,
	Summary_Combat,
	Summary_Flags,
	Award_Top_Fragger,
	Award_Best_Accuracy,
	Award_Most_Headshots,
	Award_Deadliest_Aim,
	Award_Longest_Streak,
	Award_Most_Captures,
	Award_Longest_Carry,
	Award_Fastest_Capture,
}

// A line the game says: its key in strings.json, its English (Classic's), and where it is
// in Soldat 1's default.txt: "{1}" its line 1, "{96} %d {97}" made of two lines and what
// is between them; "" if Soldat 1 hasn't it.
String_Line :: struct {
	key:     string,
	english: string,
	soldat:  string,
}

@(rodata)
STRINGS := [String_Id]String_Line {
	.Killed_By             = {"killed_by", "Killed by %s", "{1}"},
	.You_Killed            = {"you_killed", "You killed %s", "{2}"},
	.You_Killed_Yourself   = {"you_killed_yourself", "You killed yourself", "{3}"},
	.Multikill_2           = {"multikill_2", "DOUBLE KILL", ""},
	.Multikill_3           = {"multikill_3", "TRIPLE KILL", ""},
	.Multikill_4           = {"multikill_4", "MULTI KILL", ""},
	.Multikill_5           = {"multikill_5", "MULTI KILL X2", ""},
	.Multikill_6           = {"multikill_6", "SERIAL KILL", ""},
	.Multikill_7           = {"multikill_7", "INSANE KILLS", ""},
	.Multikill_8           = {"multikill_8", "GIMME MORE!", ""},
	.Multikill_9           = {"multikill_9", "MASTA KILLA!", ""},
	.Multikill_10          = {"multikill_10", "MASTA KILLA!", ""},
	.Multikill_11          = {"multikill_11", "MASTA KILLA!", ""},
	.Multikill_12          = {"multikill_12", "STOP IT!!!!", ""},
	.Multikill_13          = {"multikill_13", "MERCY!!!!!!!!!!", ""},
	.Multikill_14          = {"multikill_14", "CHEATER!!!!!!!!", ""},
	.Multikill_15          = {"multikill_15", "Phased-plasma rifle in the forty watt range", ""},
	.Multikill_16          = {"multikill_16", "Hey, just what you see, pal", ""},
	.Multikill_17          = {"multikill_17", "just what you see, pal...", ""},
	.You_Got_Red_Flag      = {"you_got_red_flag", "You got the Red Flag!", "{20}"},
	.You_Got_Blue_Flag     = {"you_got_blue_flag", "You got the Blue Flag!", "{17}"},
	.Red_Flag_Captured     = {"red_flag_captured", "Red Flag captured!", "{21}"},
	.Blue_Flag_Captured    = {"blue_flag_captured", "Blue Flag captured!", "{18}"},
	.Captured_Red_Flag     = {"captured_red_flag", "%s captured the Red Flag", "{22}"},
	.Captured_Blue_Flag    = {"captured_blue_flag", "%s captured the Blue Flag", "{19}"},
	.Red_Flag_Returned     = {"red_flag_returned", "Red Flag returned!", "{13}"},
	.Blue_Flag_Returned    = {"blue_flag_returned", "Blue Flag returned!", "{15}"},
	.Returned_Red_Flag     = {"returned_red_flag", "%s returned the Red Flag", "{14}"},
	.Returned_Blue_Flag    = {"returned_blue_flag", "%s returned the Blue Flag", "{16}"},
	.Flag_Dropped          = {"flag_dropped", "%s Flag dropped!", "{730}"},
	.Dropped_Flag          = {"dropped_flag", "%s dropped the %s Flag", "{729}"},
	.Red                   = {"red", "Red", "{786}"},
	.Blue                  = {"blue", "Blue", "{787}"},
	.Alpha_Scores          = {"alpha_scores", "Alpha Team Scores!", "{6}"},
	.Bravo_Scores          = {"bravo_scores", "Bravo Team Scores!", "{8}"},
	.Scores_For_Alpha      = {"scores_for_alpha", "%s scores for Alpha Team", "{7}"},
	.Scores_For_Bravo      = {"scores_for_bravo", "%s scores for Bravo Team", "{9}"},
	.Alpha_Team_Wins       = {"alpha_team_wins", "Alpha Team Wins!", ""},
	.Bravo_Team_Wins       = {"bravo_team_wins", "Bravo Team Wins!", ""},
	.Tie                   = {"tie", "It's a tie", "{218}"},
	.Alpha_Wins            = {"alpha_wins", "Alpha team wins", "{56}"},
	.Bravo_Wins            = {"bravo_wins", "Bravo team wins", "{57}"},
	.Time_Left_Seconds     = {"time_left_seconds", "Time Left: %d seconds", "{96} %d {97}"},
	.Time_Left_Minutes     = {"time_left_minutes", "Time Left: %d minutes", "{96} %d {98}"},
	.Joined_Game           = {"joined_game", "%s has joined the game", "{140}"},
	.Joined_Alpha          = {"joined_alpha", "%s has joined alpha team", "{141}"},
	.Joined_Bravo          = {"joined_bravo", "%s has joined bravo team", "{142}"},
	.Joined_Charlie        = {"joined_charlie", "%s has joined charlie team", "{143}"},
	.Joined_Delta          = {"joined_delta", "%s has joined delta team", "{144}"},
	.Joined_Spectators     = {"joined_spectators", "%s has joined as spectator", "{610}"},
	.Left_Game             = {"left_game", "%s has left the game", "{240}"},
	.Left_Alpha            = {"left_alpha", "%s has left alpha team", "{241}"},
	.Left_Bravo            = {"left_bravo", "%s has left bravo team", "{242}"},
	.Left_Charlie          = {"left_charlie", "%s has left charlie team", "{243}"},
	.Left_Delta            = {"left_delta", "%s has left delta team", "{244}"},
	.Left_Spectators       = {"left_spectators", "%s has left spectators", "{617}"},
	.Respawn_In            = {"respawn_in", "Respawn in... %s", "{71}"},
	.Game_Paused           = {"game_paused", "Game paused", "{61}"},
	.Following             = {"following", "Following %s", "{77} %s"},
	.Free_Camera           = {"free_camera", "Free Camera", "{79}"},
	.Weapons_Menu_Disabled = {"weapons_menu_disabled", "Weapons menu disabled", "{85}"},
	.Weapons_Menu_Active   = {"weapons_menu_active", "Weapons menu active", "{86}"},
	.Primary_Weapon        = {"primary_weapon", "Primary Weapon:", "{69}"},
	.Secondary_Weapon      = {"secondary_weapon", "Secondary Weapon:", "{70}"},
	.Select_Team           = {"select_team", "Select Team:", "{76}"},
	.Escape_To_Game        = {"escape_to_game", "ESC - return to game", "{55}"},
	.Shot_Distance         = {"shot_distance", "DISTANCE: %sm", ""},
	.Shot_Airtime          = {"shot_airtime", "AIRTIME: %ss", ""},
	.Shot_Ricochets        = {"shot_ricochets", "RICOCHETS: %d", ""},
	.Board_Time            = {"board_time", "Time %s", "{62} %s"},
	.Board_Players         = {"board_players", "Players", "{63}"},
	.Board_Points          = {"board_points", "Points:", "{66}"},
	.Board_Deaths          = {"board_deaths", "Deaths:", "{67}"},
	.Board_Ping            = {"board_ping", "Ping:", "{68}"},
	.Vote_Kick             = {"vote_kick", "Kick", "{626}"},
	.Vote_Map              = {"vote_map", "Map", "{625}"},
	.Vote_Voter            = {"vote_voter", "Voter: %s", "{643} %s"},
	.Vote_Reason           = {"vote_reason", "Reason:%s", "{644}%s"},
	.Vote_Keys             = {"vote_keys", "F12 - Yes   F11 - No", "{627}"},
	.Vote_Reason_Prompt    = {"vote_reason_prompt", "Type reason for vote:", "{642}"},
	.Menu_Back             = {"menu_back", "<<<<", "{129}"},
	.Menu_On               = {"menu_on", ">>>>", "{130}"},
	.Menu_Kick             = {"menu_kick", "Kick", "{131}"},
	.Menu_Ban              = {"menu_ban", "Ban", "{132}"},
	.Menu_Select           = {"menu_select", "Select", "{133}"},
	.Summary_Tie           = {"summary_tie", "IT'S A TIE", ""},
	.Summary_Alpha_Wins    = {"summary_alpha_wins", "ALPHA TEAM WINS", ""},
	.Summary_Bravo_Wins    = {"summary_bravo_wins", "BRAVO TEAM WINS", ""},
	.Summary_Player        = {"summary_player", "PLAYER", ""},
	.Summary_Kills         = {"summary_kills", "K", ""},
	.Summary_Deaths        = {"summary_deaths", "D", ""},
	.Summary_Captures      = {"summary_captures", "CAP", ""},
	.Summary_Accuracy      = {"summary_accuracy", "ACC", ""},
	.Summary_Headshots     = {"summary_headshots", "HS", ""},
	.Summary_Streak        = {"summary_streak", "STRK", ""},
	.Summary_Combat        = {"summary_combat", "COMBAT", ""},
	.Summary_Flags         = {"summary_flags", "FLAGS", ""},
	.Award_Top_Fragger     = {"award_top_fragger", "Top Fragger", ""},
	.Award_Best_Accuracy   = {"award_best_accuracy", "Best Accuracy", ""},
	.Award_Most_Headshots  = {"award_most_headshots", "Most Headshots", ""},
	.Award_Deadliest_Aim   = {"award_deadliest_aim", "Deadliest Aim", ""},
	.Award_Longest_Streak  = {"award_longest_streak", "Longest Streak", ""},
	.Award_Most_Captures   = {"award_most_captures", "Most Captures", ""},
	.Award_Longest_Carry   = {"award_longest_carry", "Longest Carry", ""},
	.Award_Fastest_Capture = {"award_fastest_capture", "Fastest Capture", ""},
}

// The lines worn, each the chosen mod's, else Classic's, else its English; with the
// allocator they were loaded with. Free with strings_destroy.
Strings :: struct {
	lines: [String_Id]string,
}

// The key `key` names ("killed_by", in any case).
string_named :: proc(key: string) -> (id: String_Id, ok: bool) {
	for line, i in STRINGS do if strings.equal_fold(line.key, key) do return i, true
	return
}

// The lines `mod` says: Classic's text/strings.json, then the chosen mod's over it, each
// key its English where neither says it (or says it with the wrong placeholders).
strings_load :: proc(mod: Mod, allocator := context.allocator) -> (s: Strings) {
	lines: [String_Id]string
	for line, id in STRINGS do lines[id] = line.english
	packs := mod_packs(mod, .Text)
	#reverse for pack in packs { // Classic first, the chosen over it
		file, found := srmod_file(pack, .Text, STRINGS_FILE)
		if !found do continue
		text, read := mod_read(file, context.temp_allocator)
		if !read do continue
		said, _ := strings_read(text, mod_file_name(file))
		for line, id in said do if line != "" do lines[id] = line
	}
	for line, id in lines do s.lines[id] = strings.clone(line, allocator)
	return
}

strings_destroy :: proc(s: ^Strings, allocator := context.allocator) {
	for line in s.lines do delete(line, allocator)
	s^ = {}
}

// The line `id`, its placeholders filled with `args`, with the temp allocator.
strings_text :: proc(s: ^Strings, id: String_Id, args: ..any) -> string {
	line := s.lines[id] if s.lines[id] != "" else STRINGS[id].english
	if len(args) == 0 && !strings.contains_rune(line, '%') do return line
	return fmt.tprintf(line, ..args)
}

// A strings.json's lines, by key; "" for those it doesn't say, or says wrongly (another
// key's, not text, or other placeholders than its English's), each logged as `path`'s.
// False if it isn't JSON. With the temp allocator.
strings_read :: proc(text: []byte, path: string) -> (lines: [String_Id]string, ok: bool) {
	values: map[string]json.Value
	if json.unmarshal(text, &values, .JSON, context.temp_allocator) != nil {
		log.warnf("%s isn't JSON of keys and their lines: passed over", path)
		return
	}
	for key, value in values {
		id, known := string_named(key)
		if !known {
			log.warnf("%s: %s is no line the game says: passed over", path, key)
			continue
		}
		line, is_text := value.(json.String)
		if !is_text {
			log.warnf("%s: %s isn't text: passed over", path, key)
			continue
		}
		if problem := string_problem(id, line); problem != "" {
			log.warnf("%s: %s: %s; Classic's is said", path, key, problem)
			continue
		}
		lines[id] = line
	}
	return lines, true
}

// Why `line` can't be said for `id`: its placeholders aren't its English's, in their
// order; "" if it can.
string_problem :: proc(id: String_Id, line: string) -> string {
	want, has := placeholders(STRINGS[id].english), placeholders(line)
	if slice.equal(want, has) do return ""
	if len(want) == 0 do return "it has a placeholder (%s, %d) where none goes: write %% for a %"
	return fmt.tprintf("it must have %s, in that order", strings.join(want, " then ", context.temp_allocator))
}

// The placeholders of a line, in order ("%s", "%d"), by their letter; "%%" a % sign, none.
// With the temp allocator.
@(private = "file")
placeholders :: proc(line: string) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(line); i += 1 {
		if line[i] != '%' do continue
		j := i + 1
		for j < len(line) && strings.index_byte("+-# 0123456789.", line[j]) >= 0 do j += 1
		if j >= len(line) {
			append(&found, "%")
			break
		}
		if line[j] == '%' {
			i = j
			continue
		}
		append(&found, fmt.tprintf("%%%c", line[j]))
		i = j
	}
	return found[:]
}

// A strings.json of `lines` (those not "", in the game's order): with the temp allocator.
strings_json :: proc(lines: [String_Id]string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "{\n")
	count := 0
	for line in lines do if line != "" do count += 1
	n := 0
	for line, id in lines {
		if line == "" do continue
		n += 1
		quoted, _ := json.marshal(line, {spec = .JSON}, context.temp_allocator)
		fmt.sbprintf(&b, "  %q: %s%s\n", STRINGS[id].key, string(quoted), "," if n < count else "")
	}
	strings.write_string(&b, "}\n")
	return strings.to_string(b)
}

// Soldat 1's txt/default.txt, or one of its txt/languages/*.txt: a line each by number,
// UTF-16 (else UTF-8), as the lines the game says, each by its Soldat 1 line (STRINGS'
// `soldat`); "" for each it hasn't, can't say (its placeholders aren't the game's), or
// says as the game's English does. With the temp allocator.
strings_from_soldat :: proc(data: []byte) -> (lines: [String_Id]string) {
	numbered := soldat_lines(data)
	for line, id in STRINGS {
		if line.soldat == "" do continue
		b := strings.builder_make(context.temp_allocator)
		whole := true
		rest := line.soldat
		for len(rest) > 0 {
			open := strings.index_byte(rest, '{')
			if open < 0 {
				strings.write_string(&b, rest)
				break
			}
			strings.write_string(&b, rest[:open])
			close := strings.index_byte(rest[open:], '}')
			if close < 0 do break
			n, is_number := strconv.parse_int(rest[open + 1:][:close - 1])
			if !is_number || n < 1 || n > len(numbered) {
				whole = false
				break
			}
			strings.write_string(&b, strings.trim_space(numbered[n - 1]))
			rest = rest[open + close + 1:]
		}
		said := strings.to_string(b)
		if !whole || strings.trim_space(said) == "" || said == line.english || string_problem(id, said) != "" do continue
		lines[id] = said
	}
	return
}

// A Soldat 1 text file's lines, in order: UTF-16 little-endian (as Soldat 1 writes them,
// its byte-order mark first), big-endian with its mark, else UTF-8. With the temp
// allocator.
@(private = "file")
soldat_lines :: proc(data: []byte) -> []string {
	text: string
	switch {
	case len(data) >= 2 && data[0] == 0xFF && data[1] == 0xFE, len(data) >= 2 && data[0] == 0xFE && data[1] == 0xFF:
		big := data[0] == 0xFE
		units := make([]u16, (len(data) - 2) / 2, context.temp_allocator)
		for &u, i in units {
			a, b := u16(data[2 + 2 * i]), u16(data[3 + 2 * i])
			u = a << 8 | b if big else b << 8 | a
		}
		out := make([]byte, len(units) * 4, context.temp_allocator)
		n := utf16.decode_to_utf8(out, units)
		text = string(out[:n])
	case len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF:
		text = string(data[3:])
	case:
		text = string(data)
	}
	lines := make([dynamic]string, context.temp_allocator)
	rest := text
	for line in strings.split_lines_iterator(&rest) do append(&lines, strings.trim_right(line, "\r"))
	return lines[:]
}
