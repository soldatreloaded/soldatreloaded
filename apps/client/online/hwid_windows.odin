#+build windows
package online

import win "core:sys/windows"

// The install's MachineGuid, from the 64-bit registry whatever the program is built as.
@(private = "file")
RRF_SUBKEY_WOW6464KEY :: 0x00010000

machine_id :: proc(allocator := context.allocator) -> (id: string, ok: bool) {
	guid: [128]u16
	size := win.DWORD(size_of(guid))
	key: cstring16 = `SOFTWARE\Microsoft\Cryptography`
	value: cstring16 = "MachineGuid"
	if win.RegGetValueW(win.HKEY_LOCAL_MACHINE, key, value, win.RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nil, &guid, &size) != 0 do return
	text, err := win.wstring_to_utf8(win.wstring(&guid[0]), -1, allocator)
	return text, err == nil
}
