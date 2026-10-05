package lists_test

// The server's lists (server/lists): bans and mutes by address and hardware ID, admins by
// address, kept in their files and read back the same; a ban lifts at its time; the old
// line formats still read. The files go under the OS's temp directory.
//
//   odin test tests/lists

import sa "core:container/small_array"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "../../core/utils"
import "../../server/lists"

// A fresh, empty directory for a test's files, under the OS's temp directory.
scratch :: proc(t: ^testing.T, name: string) -> string {
	temp, err := os.temp_directory(context.temp_allocator)
	testing.expectf(t, err == nil, "the temp directory: %v", err)
	dir := utils.temp_path(temp, "soldatreloaded_lists_test", name)
	os.remove_all(dir)
	os.make_directory_all(dir)
	return dir
}

// A list's file as a test lays it down.
write :: proc(dir, file, text: string) {
	utils.write_file(utils.temp_path(dir, file), transmute([]byte)text)
}

ban_text :: proc(b: ^lists.Ban) -> (name, reason, hwid: string) {
	return utils.short_string_text(&b.name), utils.short_string_text(&b.reason), utils.short_string_text(&b.hwid)
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
files_round_trip :: proc(t: ^testing.T) {
	dir := scratch(t, "round_trip")
	defer os.remove_all(dir)
	write(dir, "admins.txt", "// the owner's\nadmin 10.0.0.7 \"Boss\"\n")

	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	c, _ := lists.address_parse("10.0.0.7")

	l, again, fresh: lists.Lists
	lists.lists_load(&l, dir)
	testing.expect(t, sa.len(l.admins) == 1 && lists.lists_admin(&l, c) && !lists.lists_admin(&l, a), "admins.txt is read: the owner's admin, by address")
	testing.expect(t, utils.file_exists(utils.temp_path(dir, "banlist.txt")) && utils.file_exists(utils.temp_path(dir, "mutelist.txt")), "the lists that weren't there are made, so an owner finds them")

	// a first start: every list made, the owner's admins.txt a template that lists nobody
	fresh_dir := utils.temp_path(dir, "fresh")
	lists.lists_load(&fresh, fresh_dir)
	testing.expect(t, utils.file_exists(utils.temp_path(fresh_dir, "banlist.txt")) && utils.file_exists(utils.temp_path(fresh_dir, "mutelist.txt")) && utils.file_exists(utils.temp_path(fresh_dir, "admins.txt")), "a first start makes all three lists")
	lists.lists_load(&fresh, fresh_dir)
	testing.expect(t, sa.len(fresh.bans) == 0 && sa.len(fresh.mutes) == 0 && sa.len(fresh.admins) == 0, "and read back, they list nobody")

	now := time.to_unix_seconds(time.now())
	lists.lists_ban(&l, a, "", 0, "Major", "Cheating \"a lot\"")
	lists.lists_ban(&l, b, "", now + 600, "Minor", "Spam")
	lists.lists_mute(&l, b, "", "Minor")
	_, a_banned := lists.lists_banned(&l, a, "", now)
	_, b_banned := lists.lists_banned(&l, b, "", now)
	_, c_banned := lists.lists_banned(&l, c, "", now)
	testing.expect(t, a_banned && b_banned && !c_banned, "banned are the two banned")
	testing.expect(t, lists.lists_muted(&l, b, "") && !lists.lists_muted(&l, a, ""), "and muted the one muted")

	// the lines as the C server writes them, so its files and this one's are the same
	banlist, _ := utils.read_file(utils.temp_path(dir, "banlist.txt"), context.temp_allocator)
	mutelist, _ := utils.read_file(utils.temp_path(dir, "mutelist.txt"), context.temp_allocator)
	testing.expect(t, strings.contains(string(banlist), "\nban 1.2.3.4 - 0 \"Major\" \"Cheating 'a lot'\"\n"), "a ban's line is the C server's")
	testing.expect(t, strings.contains(string(mutelist), "\nmute 5.6.7.8 - \"Minor\"\n"), "and a mute's")
	testing.expect(t, strings.has_prefix(string(banlist), "// The bans:"), "under the file's own header")

	lists.lists_load(&again, dir)
	major, major_found := lists.lists_banned(&again, a, "", now)
	testing.expect(t, sa.len(again.bans) == 2 && sa.len(again.mutes) == 1 && major_found, "the files read back the same lists")
	if major_found {
		name, reason, _ := ban_text(major)
		testing.expect(t, major.expires == 0 && name == "Major" && reason == "Cheating 'a lot'", "a quote in a reason kept as an apostrophe")
	}
	testing.expect(t, lists.lists_muted(&again, b, ""), "and the mute")
	_, b_still := lists.lists_banned(&again, b, "", now + 601)
	testing.expect(t, !b_still && sa.len(again.bans) == 1, "a ban lifts at its time, and is dropped")
	testing.expect(t, lists.lists_unban(&again, a, ""), "unban lifts one for ever")
	_, a_still := lists.lists_banned(&again, a, "", now)
	testing.expect(t, !a_still && !lists.lists_unban(&again, a, ""), "and it is gone")
	testing.expect(t, lists.lists_unmute(&again, b, "") && !lists.lists_muted(&again, b, ""), "unmute takes the mute off")
	lists.lists_load(&l, dir)
	testing.expect(t, sa.len(l.bans) == 0 && sa.len(l.mutes) == 0 && sa.len(l.admins) == 1, "and the files say so after (admins untouched)")
}

@(test)
by_the_machine :: proc(t: ^testing.T) {
	dir := scratch(t, "machine")
	defer os.remove_all(dir)
	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	c, _ := lists.address_parse("10.0.0.7")
	nine, _ := lists.address_parse("9.9.9.9")
	now := time.to_unix_seconds(time.now())

	l: lists.Lists
	lists.lists_load(&l, dir)

	// the console's banip: an address for thirty minutes, with its reason
	lists.lists_ban(&l, nine, "", now + 30 * 60, "", "bad")
	ban, found := lists.lists_banned(&l, nine, "", now)
	testing.expect(t, found, "banip bans the address")
	if found {
		_, reason, _ := ban_text(ban)
		testing.expect(t, ban.expires - now > 29 * 60 && reason == "bad", "for thirty minutes, with its reason")
	}
	_, found = lists.lists_banned(&l, nine, "", now)
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
	banlist, _ := utils.read_file(utils.temp_path(dir, "banlist.txt"), context.temp_allocator)
	testing.expect(t, strings.contains(string(banlist), "\nban - 0A1B2C3D4E5 0 \"\" \"cheating\"\n") && strings.contains(string(banlist), "\nban 1.2.3.4 BBBBBBBBBBB 0 \"Both\" \"both\"\n"), "written with - for the address a ban doesn't name")

	read: lists.Lists
	lists.lists_load(&read, dir)
	_, r1 := lists.lists_banned(&read, 0, "0A1B2C3D4E5", now)
	_, r2 := lists.lists_banned(&read, a, "", now)
	_, r3 := lists.lists_banned(&read, 0, "BBBBBBBBBBB", now)
	testing.expect(t, sa.len(read.bans) == 2 && r1 && r2 && r3 && lists.lists_muted(&read, 0, "CCCCCCCCCCC") && !lists.lists_muted(&read, c, ""), "the files keep the hardware IDs, - for an address a ban doesn't name")

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
	lists.lists_load(&l, "")
	lists.lists_ban(&l, a, "", 0, "Major", "Cheating")
	lists.lists_mute(&l, a, "", "Major")
	_, banned := lists.lists_banned(&l, a, "", 1)
	testing.expect(t, banned && lists.lists_muted(&l, a, "") && !lists.lists_admin(&l, a), "with no directory the lists are kept in memory")
	testing.expect(t, !utils.file_exists("banlist.txt") && !utils.file_exists("/banlist.txt"), "and nothing is written")
}

@(test)
old_lines_read_by_address :: proc(t: ^testing.T) {
	dir := scratch(t, "old")
	defer os.remove_all(dir)
	a, _ := lists.address_parse("1.2.3.4")
	b, _ := lists.address_parse("5.6.7.8")
	now := time.to_unix_seconds(time.now())
	write(dir, "banlist.txt", "ban 1.2.3.4 0 \"Major\" \"Cheating\"\nban 5.6.7.8 9999999999 \"Minor\"\n")
	write(dir, "mutelist.txt", "mute 1.2.3.4 \"Major\"\n")

	old: lists.Lists
	lists.lists_load(&old, dir)
	was, was_found := lists.lists_banned(&old, a, "", now)
	testing.expect(t, sa.len(old.bans) == 2 && was_found, "an old banlist.txt reads the same, by address")
	if was_found {
		name, reason, hwid := ban_text(was)
		testing.expect(t, was.expires == 0 && name == "Major" && reason == "Cheating" && hwid == "", "with its time, name and reason, and no hardware ID")
	}
	_, b_found := lists.lists_banned(&old, b, "", now)
	testing.expect(t, b_found, "and the other")
	testing.expect(t, lists.lists_muted(&old, a, "") && utils.short_string_text(&sa.get_ptr(&old.mutes, 0).name) == "Major", "an old mutelist.txt too")

	// the newer lines, with - for what an entry doesn't name, and comments and blank lines
	write(dir, "banlist.txt", "// a comment\n\n  ban - 0A1B2C3D4E5 0 \"Ghost\" \"no address\"  // trailing\nban 1.2.3.4 - 0 \"Major\" \"Cheating\"\nnonsense 1.2.3.4\nban - - 0 \"Nobody\" \"\"\n")
	lists.lists_load(&old, dir)
	_, ghost := lists.lists_banned(&old, 0, "0A1B2C3D4E5", now)
	_, major := lists.lists_banned(&old, a, "", now)
	testing.expect(t, sa.len(old.bans) == 2 && ghost && major, "a line naming nobody, a comment, and another verb are passed over")
}
