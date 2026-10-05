package lists_test

// The server's lists (apps/server/lists): bans and mutes by address and hardware ID, admins by
// address, kept in server.config.json (`bans`, `mutes`, `admins`) and read back the
// same; a ban lifts at its time; an entry naming nobody is passed over. The configs go
// under the OS's temp directory.
//
//   odin test tests/lists

import sa "core:container/small_array"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import res "../../core/resources"
import "../../core/utils"
import "../../apps/server/lists"

// A fresh, empty directory for a test's files, under the OS's temp directory.
scratch :: proc(t: ^testing.T, name: string) -> string {
	temp, err := os.temp_directory(context.temp_allocator)
	testing.expectf(t, err == nil, "the temp directory: %v", err)
	dir := utils.temp_path(temp, "soldatreloaded_lists_test", name)
	os.remove_all(dir)
	os.make_directory_all(dir)
	return dir
}

// A config's file as a test lays it down.
write :: proc(path, text: string) {
	utils.write_file(path, transmute([]byte)text)
}

ban_text :: proc(b: ^lists.Ban) -> (name, reason, hwid: string) {
	return utils.short_string_text(&b.name), utils.short_string_text(&b.reason), utils.short_string_text(&b.hwid)
}

// The config's bans' entry naming `address` and `hwid`, as the file has it.
config_ban :: proc(config: ^res.Server_Config, address, hwid: string) -> (res.Ban_Entry, bool) {
	for b in config.bans do if b.address == address && b.hwid == hwid do return b, true
	return {}, false
}

@(test)
addresses_and_hwids :: proc(t: ^testing.T) {
	a, a_ok := lists.address_parse("1.2.3.4")
	_, b_ok := lists.address_parse("5.6.7.8")
	_, bad1 := lists.address_parse("1.2.3")
	_, bad2 := lists.address_parse("one.two")
	_, bad3 := lists.address_parse("1.2.3.256")
	_, bad4 := lists.address_parse("1.2.3.4.")
	_, bad5 := lists.address_parse("1..3.4")
	testing.expect(t, a_ok && b_ok && !bad1 && !bad2 && !bad3 && !bad4 && !bad5, "addresses read as four numbers, nothing else")
	testing.expect_value(t, a, transmute(u32)[4]u8{1, 2, 3, 4}) // the bytes as ENet lays them
	testing.expect_value(t, lists.address_text(a), "1.2.3.4")
	zero, zero_ok := lists.address_parse("0.0.0.0")
	testing.expect(t, zero_ok && zero == 0, "the null address is ENet's 0")

	id, id_ok := lists.hwid_parse("0a1b2c3d4e5")
	_, short := lists.hwid_parse("0A1B2C3D4E")
	_, junk := lists.hwid_parse("0A1B2C3D4EZ")
	testing.expect(t, id_ok && utils.short_string_text(&id) == "0A1B2C3D4E5" && !short && !junk, "a hardware ID is eleven hex digits, kept in capitals")

	testing.expect_value(t, lists.whom_text(a, "0A1B2C3D4E5"), "1.2.3.4 0A1B2C3D4E5")
	testing.expect_value(t, lists.whom_text(0, "0A1B2C3D4E5"), "- 0A1B2C3D4E5")
	testing.expect_value(t, lists.whom_text(a, ""), "1.2.3.4 -")
}

@(test)
config_round_trip :: proc(t: ^testing.T) {
	dir := scratch(t, "round_trip")
	defer os.remove_all(dir)
	path := utils.temp_path(dir, "server.config.json")
	write(path, `{"server": {"hostname": "Kept"}, "admins": [{"address": "10.0.0.7", "name": "Boss"}]}`)

	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	c, _ := lists.address_parse("10.0.0.7")

	config := res.server_config_load(path)
	defer res.server_config_destroy(config)
	l: lists.Lists
	lists.lists_load(&l, config, path)
	testing.expect(t, sa.len(l.admins) == 1 && lists.lists_admin(&l, c) && !lists.lists_admin(&l, a), "the config's admins are read, by address")
	testing.expect(t, sa.len(l.bans) == 0 && sa.len(l.mutes) == 0, "and a config without bans or mutes lists nobody")

	now := time.to_unix_seconds(time.now())
	lists.lists_ban(&l, a, "", 0, "Major", "Cheating \"a lot\"")
	lists.lists_ban(&l, b, "", now + 600, "Minor", "Spam")
	lists.lists_mute(&l, b, "", "Minor")
	_, a_banned := lists.lists_banned(&l, a, "", now)
	_, b_banned := lists.lists_banned(&l, b, "", now)
	_, c_banned := lists.lists_banned(&l, c, "", now)
	testing.expect(t, a_banned && b_banned && !c_banned, "banned are the two banned")
	testing.expect(t, lists.lists_muted(&l, b, "") && !lists.lists_muted(&l, a, ""), "and muted the one muted")

	// the config in memory and its file both have them
	major_entry, major_kept := config_ban(config, "1.2.3.4", "")
	testing.expect(t, len(config.bans) == 2 && major_kept && major_entry.expires == 0 && major_entry.name == "Major" && major_entry.reason == "Cheating \"a lot\"", "a ban is put back in the config")
	testing.expect(t, len(config.mutes) == 1 && config.mutes[0].address == "5.6.7.8" && config.mutes[0].name == "Minor", "and a mute")
	text, _ := utils.read_file(path, context.temp_allocator)
	testing.expect(t, strings.contains(string(text), `"bans"`) && strings.contains(string(text), `"Spam"`), "and the config is saved as they change")

	again_config := res.server_config_load(path)
	defer res.server_config_destroy(again_config)
	testing.expect(t, again_config.server.hostname == "Kept" && len(again_config.admins) == 1, "the rest of the config is kept as it was")
	again: lists.Lists
	lists.lists_load(&again, again_config, path)
	major, major_found := lists.lists_banned(&again, a, "", now)
	testing.expect(t, sa.len(again.bans) == 2 && sa.len(again.mutes) == 1 && major_found, "the file reads back the same lists")
	if major_found {
		name, reason, _ := ban_text(major)
		testing.expect(t, major.expires == 0 && name == "Major" && reason == "Cheating \"a lot\"", "a quote in a reason kept")
	}
	testing.expect(t, lists.lists_muted(&again, b, ""), "and the mute")
	_, b_still := lists.lists_banned(&again, b, "", now + 601)
	testing.expect(t, !b_still && sa.len(again.bans) == 1, "a ban lifts at its time, and is dropped")
	testing.expect(t, lists.lists_unban(&again, a, ""), "unban lifts one for ever")
	_, a_still := lists.lists_banned(&again, a, "", now)
	testing.expect(t, !a_still && !lists.lists_unban(&again, a, ""), "and it is gone")
	testing.expect(t, lists.lists_unmute(&again, b, "") && !lists.lists_muted(&again, b, ""), "unmute takes the mute off")

	after := res.server_config_load(path)
	defer res.server_config_destroy(after)
	lists.lists_load(&l, after, path)
	testing.expect(t, sa.len(l.bans) == 0 && sa.len(l.mutes) == 0 && sa.len(l.admins) == 1, "and the file says so after (admins untouched)")
}

@(test)
by_the_machine :: proc(t: ^testing.T) {
	dir := scratch(t, "machine")
	defer os.remove_all(dir)
	path := utils.temp_path(dir, "server.config.json")
	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	c, _ := lists.address_parse("10.0.0.7")
	nine, _ := lists.address_parse("9.9.9.9")
	now := time.to_unix_seconds(time.now())

	config := res.server_config_load(path) // missing: made with the defaults
	defer res.server_config_destroy(config)
	testing.expect(t, utils.file_exists(path), "a missing config is made")
	l: lists.Lists
	lists.lists_load(&l, config, path)

	// the console's banip: an address for thirty minutes, with its reason
	lists.lists_ban(&l, nine, "", now + 30 * 60, "", "bad")
	ban, found := lists.lists_banned(&l, nine, "", now)
	testing.expect(t, found, "banip bans the address")
	if found {
		_, reason, _ := ban_text(ban)
		testing.expect(t, ban.expires - now > 29 * 60 && reason == "bad", "for thirty minutes, with its reason")
	}
	testing.expect(t, lists.lists_unban(&l, nine, ""), "and unban lifts it")
	_, found = lists.lists_banned(&l, nine, "", now)
	testing.expect(t, !found, "so they are no longer banned")

	// a ban or mute on a hardware ID holds at any address
	lists.lists_ban(&l, 0, "0a1b2c3d4e5", 0, "", "cheating")
	_, by_machine := lists.lists_banned(&l, b, "0A1B2C3D4E5", now)
	_, other_machine := lists.lists_banned(&l, b, "FFFFFFFFFFF", now)
	_, no_machine := lists.lists_banned(&l, b, "", now)
	testing.expect(t, by_machine && !other_machine && !no_machine, "banhw bars the machine from any address, and no other")
	lists.lists_ban(&l, 0, "1.2.3.4", 0, "", "")
	testing.expect_value(t, sa.len(l.bans), 1) // what isn't a hardware ID names nobody
	lists.lists_ban(&l, a, "BBBBBBBBBBB", 0, "Both", "both")
	_, by_address := lists.lists_banned(&l, a, "", now)
	_, elsewhere := lists.lists_banned(&l, c, "BBBBBBBBBBB", now)
	testing.expect(t, by_address && elsewhere && sa.len(l.bans) == 2, "a player's ban holds by their address and by their machine")
	lists.lists_mute(&l, 0, "CCCCCCCCCCC", "Quiet")
	testing.expect(t, lists.lists_muted(&l, c, "CCCCCCCCCCC") && !lists.lists_muted(&l, c, ""), "a mute by machine alone holds by it")
	_, machine_kept := config_ban(config, "", "0A1B2C3D4E5")
	_, both_kept := config_ban(config, "1.2.3.4", "BBBBBBBBBBB")
	testing.expect(t, machine_kept && both_kept, "kept in the config with an empty address where a ban doesn't name one, the hardware ID in capitals")

	read_config := res.server_config_load(path)
	defer res.server_config_destroy(read_config)
	read: lists.Lists
	lists.lists_load(&read, read_config, path)
	_, r1 := lists.lists_banned(&read, 0, "0A1B2C3D4E5", now)
	_, r2 := lists.lists_banned(&read, a, "", now)
	_, r3 := lists.lists_banned(&read, 0, "BBBBBBBBBBB", now)
	testing.expect(t, sa.len(read.bans) == 2 && r1 && r2 && r3 && lists.lists_muted(&read, 0, "CCCCCCCCCCC") && !lists.lists_muted(&read, c, ""), "the file keeps the hardware IDs")

	// a ban that named them by address and machine both lifts as one
	testing.expect(t, lists.lists_unban(&l, a, "BBBBBBBBBBB"), "unban by both lifts it")
	_, u1 := lists.lists_banned(&l, a, "", now)
	_, u2 := lists.lists_banned(&l, 0, "BBBBBBBBBBB", now)
	testing.expect(t, !u1 && !u2, "by address and machine both")
	testing.expect(t, lists.lists_unban(&l, 0, "0A1B2C3D4E5") && sa.len(l.bans) == 0, "and by the hardware ID")
	testing.expect(t, lists.lists_unmute(&l, 0, "CCCCCCCCCCC") && sa.len(l.mutes) == 0, "unmute by the hardware ID")

	// a ban replaces the one that named them
	lists.lists_ban(&l, a, "", 0, "First", "one")
	lists.lists_ban(&l, a, "DDDDDDDDDDD", now + 60, "Second", "two")
	second, second_found := lists.lists_banned(&l, 0, "DDDDDDDDDDD", now)
	testing.expect(t, sa.len(l.bans) == 1 && second_found, "banning them again replaces their ban")
	if second_found {
		name, _, hwid := ban_text(second)
		testing.expect(t, name == "Second" && hwid == "DDDDDDDDDDD" && second.host == a, "with the new one")
	}
}

@(test)
in_memory_alone :: proc(t: ^testing.T) {
	a, _ := lists.address_parse("1.2.3.4")
	l: lists.Lists
	lists.lists_load(&l, nil, "")
	lists.lists_ban(&l, a, "", 0, "Major", "Cheating")
	lists.lists_mute(&l, a, "", "Major")
	_, banned := lists.lists_banned(&l, a, "", 1)
	testing.expect(t, banned && lists.lists_muted(&l, a, "") && !lists.lists_admin(&l, a), "with no config the lists are kept in memory")

	// a config with no path: read from, never written
	dir := scratch(t, "memory")
	defer os.remove_all(dir)
	path := utils.temp_path(dir, "server.config.json")
	config := res.server_config_load(path)
	defer res.server_config_destroy(config)
	before, _ := utils.read_file(path, context.temp_allocator)
	kept: lists.Lists
	lists.lists_load(&kept, config, "")
	lists.lists_ban(&kept, a, "", 0, "Major", "Cheating")
	after, _ := utils.read_file(path, context.temp_allocator)
	_, kept_banned := lists.lists_banned(&kept, a, "", 1)
	testing.expect(t, kept_banned && len(config.bans) == 0 && string(before) == string(after), "and with no path, nothing is written")
}

@(test)
entries_naming_nobody :: proc(t: ^testing.T) {
	dir := scratch(t, "nobody")
	defer os.remove_all(dir)
	path := utils.temp_path(dir, "server.config.json")
	write(path, `{
		"bans": [
			{"address": "", "hwid": "0A1B2C3D4E5", "expires": 0, "name": "Ghost", "reason": "no address"},
			{"address": "1.2.3.4", "hwid": "", "expires": 0, "name": "Major", "reason": "Cheating"},
			{"address": "", "hwid": "", "expires": 0, "name": "Nobody", "reason": ""},
			{"address": "one.two", "hwid": "", "expires": 0, "name": "Typo", "reason": ""},
			{"address": "", "hwid": "XYZ", "expires": 0, "name": "Junk", "reason": ""}
		],
		"mutes": [{"address": "5.6.7.8", "hwid": "", "name": "Quiet"}, {"address": "", "hwid": "", "name": "Nobody"}],
		"admins": [{"address": "10.0.0.7", "name": "Boss"}, {"address": "not an address", "name": "Nobody"}]
	}`)
	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	c, _ := lists.address_parse("10.0.0.7")
	now := time.to_unix_seconds(time.now())

	config := res.server_config_load(path)
	defer res.server_config_destroy(config)
	l: lists.Lists
	lists.lists_load(&l, config, path)
	_, ghost := lists.lists_banned(&l, 0, "0A1B2C3D4E5", now)
	_, major := lists.lists_banned(&l, a, "", now)
	testing.expect(t, sa.len(l.bans) == 2 && ghost && major, "a ban naming nobody, or by what isn't an address or hardware ID, is passed over")
	testing.expect(t, sa.len(l.mutes) == 1 && lists.lists_muted(&l, b, ""), "and a mute")
	testing.expect(t, sa.len(l.admins) == 1 && lists.lists_admin(&l, c), "and an admin")
}

@(test)
broken_config_kept :: proc(t: ^testing.T) {
	dir := scratch(t, "broken")
	defer os.remove_all(dir)
	path := utils.temp_path(dir, "server.config.json")
	broken := `{"bans": [ not json`
	write(path, broken)
	a, _ := lists.address_parse("1.2.3.4")

	// the config's error is expected; the test runner fails a test that logs one
	logger := context.logger
	context.logger.lowest_level = .Fatal
	config := res.server_config_load(path)
	context.logger = logger
	defer res.server_config_destroy(config)
	l: lists.Lists
	lists.lists_load(&l, config, path)
	lists.lists_ban(&l, a, "", 0, "Major", "Cheating")
	_, banned := lists.lists_banned(&l, a, "", 1)
	text, _ := utils.read_file(path, context.temp_allocator)
	testing.expect(t, banned && string(text) == broken, "a config that couldn't be read is never written over; the ban holds in memory")
}
