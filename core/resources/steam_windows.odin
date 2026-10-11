#+build windows
package resources

import "core:strings"
import win "core:sys/windows"

// Where Steam is, as Windows has it written: the user's Steam's SteamPath, and the
// machine's InstallPath; none it hasn't. With the temp allocator.
steam_registry :: proc() -> []string {
	found := make([dynamic]string, context.temp_allocator)
	read :: proc(key: win.HKEY, sub, value: string) -> (path: string, ok: bool) {
		buf: [1024]u16
		size := win.DWORD(size_of(buf))
		if win.RegGetValueW(key, win.utf8_to_wstring(sub, context.temp_allocator), win.utf8_to_wstring(value, context.temp_allocator), win.RRF_RT_REG_SZ, nil, &buf[0], &size) != 0 do return
		text, err := win.utf16_to_utf8(buf[:size / 2], context.temp_allocator)
		if err != nil do return
		path = strings.trim_right_null(text)
		path, _ = strings.replace_all(path, "\\", "/", context.temp_allocator)
		return path, path != ""
	}
	if path, ok := read(win.HKEY_CURRENT_USER, `Software\Valve\Steam`, "SteamPath"); ok do append(&found, path)
	if path, ok := read(win.HKEY_LOCAL_MACHINE, `SOFTWARE\WOW6432Node\Valve\Steam`, "InstallPath"); ok do append(&found, path)
	if path, ok := read(win.HKEY_LOCAL_MACHINE, `SOFTWARE\Valve\Steam`, "InstallPath"); ok do append(&found, path)
	return found[:]
}
