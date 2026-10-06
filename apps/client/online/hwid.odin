package online

import "core:crypto/sha2"
import "core:strings"

import network "../../../core/network"
import "../../../core/utils"

// This machine's hardware ID, said in the Hello for the server's bans and mutes: the
// system's own ID of the install, hashed with the game's salt so it is this game's
// alone, its first eleven hex digits in capitals. The C client's net/hwid.c, digit for
// digit, so a ban by hardware ID holds across the two. Empty where the system has none.

HWID_SALT :: "soldatreloaded hardware id 1:"

hwid :: proc() -> (id: network.Hwid) {
	machine, found := machine_id(context.temp_allocator)
	machine = strings.trim_right_space(machine)
	if !found || machine == "" do return

	digest: [sha2.DIGEST_SIZE_256]u8
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, transmute([]u8)string(HWID_SALT))
	sha2.update(&ctx, transmute([]u8)machine)
	sha2.final(&ctx, digest[:])

	HEX := "0123456789ABCDEF"
	digits: [11]u8
	for &digit, i in digits {
		b := digest[i / 2]
		digit = HEX[b >> 4 if i % 2 == 0 else b & 0xF]
	}
	utils.short_string_set(&id, string(digits[:]))
	return
}
