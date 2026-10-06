package lists

import sa "core:container/small_array"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:strings"

import res "../../../core/resources"
import "../../../core/utils"

// The server's lists: who is banned (until when, as whom, why) and who is muted (their
// chat goes to nobody), by address and by the machine's hardware ID, so a new address
// alone lifts neither; and who may run the admin commands, by address. They are kept in
// server.config.mjson (`bans`, `mutes`, `admins`; core/resources/server_config.odin):
// the server writes the config as admins ban and unban, mute and unmute, and only reads
// the admins, which are the server's owner's to write.

MAX_BANS :: 256
MAX_MUTES :: 256
MAX_ADMINS :: 64

Name :: utils.Short_String(24)
Reason :: utils.Short_String(64)

Ban :: struct {
	host:    u32, // the address, as ENet has it; 0 for none
	hwid:    Hwid, // the machine's; empty for none
	expires: i64, // the Unix time it lifts at; 0 never
	name:    Name,
	reason:  Reason,
}

Entry :: struct {
	host: u32, // 0 for none
	hwid: Hwid, // empty for none; an admin is by address alone
	name: Name, // as they were known when listed
}

Lists :: struct {
	config: ^res.Server_Config, // where they are kept, by reference; nil for nowhere
	path:   string,             // the config's file, by reference; "" to keep them in memory alone
	bans:   sa.Small_Array(MAX_BANS, Ban),
	mutes:  sa.Small_Array(MAX_MUTES, Entry),
	admins: sa.Small_Array(MAX_ADMINS, Entry),
}

// The lists as `config` has them; as the bans and mutes change, put back in it and the
// config saved to `path`, unless that is "". The config and the path are kept, not
// copied: they must outlive the lists. An entry that names nobody, or names them by what
// isn't an address or a hardware ID, is logged and passed over.
lists_load :: proc(l: ^Lists, config: ^res.Server_Config, path: string) {
	l^ = {config = config, path = path}
	if config == nil do return
	for b in config.bans {
		host, hwid, ok := who_of(b.address, b.hwid)
		if !ok {
			log.warnf("the ban on %q %q names nobody: passed over", b.address, b.hwid)
			continue
		}
		ban := Ban{host = host, hwid = hwid, expires = b.expires}
		utils.short_string_set(&ban.name, b.name)
		utils.short_string_set(&ban.reason, b.reason)
		sa.append(&l.bans, ban)
	}
	for m in config.mutes {
		host, hwid, ok := who_of(m.address, m.hwid)
		if !ok {
			log.warnf("the mute on %q %q names nobody: passed over", m.address, m.hwid)
			continue
		}
		mute := Entry{host = host, hwid = hwid}
		utils.short_string_set(&mute.name, m.name)
		sa.append(&l.mutes, mute)
	}
	for a in config.admins {
		host, _, ok := who_of(a.address, "")
		if !ok {
			log.warnf("the admin %q isn't an address: passed over", a.address)
			continue
		}
		admin := Entry{host = host}
		utils.short_string_set(&admin.name, a.name)
		sa.append(&l.admins, admin)
	}
	if sa.len(l.bans) + sa.len(l.mutes) + sa.len(l.admins) > 0 {
		log.infof("%d bans, %d mutes and %d admins", sa.len(l.bans), sa.len(l.mutes), sa.len(l.admins))
	}
}

// A player is named by their address and their machine's hardware ID (either may be
// missing: host 0, hwid empty); an entry names them if it names either.

// The ban on them at `now` (Unix seconds), if any. One that has lifted is dropped.
lists_banned :: proc(l: ^Lists, host: u32, hwid: string, now: i64) -> (^Ban, bool) {
	i := 0
	for i < sa.len(l.bans) {
		b := sa.get_ptr(&l.bans, i)
		if !names(b.host, utils.short_string_text(&b.hwid), host, hwid) {
			i += 1
			continue
		}
		if b.expires == 0 || b.expires > now do return b, true
		sa.unordered_remove(&l.bans, i) // lifted; another may still name them
		save(l)
	}
	return nil, false
}

// Them banned until `expires` (0 for ever), replacing a ban that named them; saved.
lists_ban :: proc(l: ^Lists, host: u32, hwid: string, expires: i64, name: string, reason: string) {
	kept := hwid_of(hwid)
	id := utils.short_string_text(&kept)
	if host == 0 && id == "" do return // names nobody
	b: ^Ban
	bans := sa.slice(&l.bans)
	for &ban in bans {
		if names(ban.host, utils.short_string_text(&ban.hwid), host, id) {
			b = &ban
			break
		}
	}
	if b == nil {
		if len(bans) == MAX_BANS { // full: the one lifting soonest makes room
			soonest := 0
			for i in 1 ..< MAX_BANS {
				e := bans[i].expires
				if e != 0 && (bans[soonest].expires == 0 || e < bans[soonest].expires) do soonest = i
			}
			b = &bans[soonest]
		} else {
			sa.append(&l.bans, Ban{})
			b = sa.get_ptr(&l.bans, sa.len(l.bans) - 1)
		}
	}
	b^ = {host = host, expires = expires}
	utils.short_string_set(&b.hwid, id)
	utils.short_string_set(&b.name, name)
	utils.short_string_set(&b.reason, reason)
	save(l)
}

// Every ban that named them lifted. False if none did.
lists_unban :: proc(l: ^Lists, host: u32, hwid: string) -> bool {
	any := false
	i := 0
	for i < sa.len(l.bans) {
		b := sa.get_ptr(&l.bans, i)
		if !names(b.host, utils.short_string_text(&b.hwid), host, hwid) {
			i += 1
			continue
		}
		sa.unordered_remove(&l.bans, i)
		any = true
	}
	if any do save(l)
	return any
}

lists_muted :: proc(l: ^Lists, host: u32, hwid: string) -> bool {
	_, found := find(sa.slice(&l.mutes), host, hwid)
	return found
}

// Them muted as `name`, replacing a mute that named them; saved. Nothing for a mute
// naming nobody, or when the list is full.
lists_mute :: proc(l: ^Lists, host: u32, hwid: string, name: string) {
	kept := hwid_of(hwid)
	id := utils.short_string_text(&kept)
	if host == 0 && id == "" do return
	i, found := find(sa.slice(&l.mutes), host, id)
	if !found {
		if sa.len(l.mutes) == MAX_MUTES do return
		sa.append(&l.mutes, Entry{})
		i = sa.len(l.mutes) - 1
	}
	e := sa.get_ptr(&l.mutes, i)
	e^ = {host = host}
	utils.short_string_set(&e.hwid, id)
	utils.short_string_set(&e.name, name)
	save(l)
}

// Every mute that named them taken off. False if none did.
lists_unmute :: proc(l: ^Lists, host: u32, hwid: string) -> bool {
	any := false
	for {
		i, found := find(sa.slice(&l.mutes), host, hwid)
		if !found do break
		sa.unordered_remove(&l.mutes, i)
		any = true
	}
	if any do save(l)
	return any
}

lists_admin :: proc(l: ^Lists, host: u32) -> bool {
	if host == 0 do return false
	_, found := find(sa.slice(&l.admins), host, "")
	return found
}

// Whether an entry's address and hardware ID name the player with these: either, where
// both sides have it.
names :: proc(entry_host: u32, entry_hwid: string, host: u32, hwid: string) -> bool {
	if entry_host != 0 && host != 0 && entry_host == host do return true
	return entry_hwid != "" && hwid != "" && entry_hwid == hwid
}

// A hardware ID as the lists keep it: in capitals, empty if it isn't one.
hwid_of :: proc(hwid: string) -> Hwid {
	return hwid_parse(hwid) or_else Hwid{}
}

// The first entry naming them.
find :: proc(list: []Entry, host: u32, hwid: string) -> (index: int, found: bool) {
	for &e, i in list {
		if names(e.host, utils.short_string_text(&e.hwid), host, hwid) do return i, true
	}
	return -1, false
}

// An entry's address and hardware ID, each empty where it names none. False if either
// isn't one, or it names nobody.
who_of :: proc(address, hwid: string) -> (host: u32, id: Hwid, ok: bool) {
	if address != "" do host = address_parse(address) or_return
	if hwid != "" do id = hwid_parse(hwid) or_return
	return host, id, host != 0 || id.length > 0
}

// The bans and mutes put back in the config, and the config saved (but not over a file
// that couldn't be read: res.server_config_save); nothing when they are kept in memory
// alone. The lists they replace stay in the config's arena until it goes, a few bytes
// for each ban or mute.
save :: proc(l: ^Lists) {
	if l.config == nil || l.path == "" do return
	allocator := virtual.arena_allocator(&l.config.arena)
	text :: proc(s: ^$S, allocator: mem.Allocator) -> string {
		return strings.clone(utils.short_string_text(s), allocator)
	}

	bans := make([]res.Ban_Entry, sa.len(l.bans), allocator)
	for &b, i in sa.slice(&l.bans) {
		bans[i] = {
			address = address_text(b.host, allocator) if b.host != 0 else "",
			hwid    = text(&b.hwid, allocator),
			expires = b.expires,
			name    = text(&b.name, allocator),
			reason  = text(&b.reason, allocator),
		}
	}
	mutes := make([]res.Mute_Entry, sa.len(l.mutes), allocator)
	for &m, i in sa.slice(&l.mutes) {
		mutes[i] = {
			address = address_text(m.host, allocator) if m.host != 0 else "",
			hwid    = text(&m.hwid, allocator),
			name    = text(&m.name, allocator),
		}
	}
	l.config.bans, l.config.mutes = bans, mutes
	res.server_config_save(l.config, l.path)
}
