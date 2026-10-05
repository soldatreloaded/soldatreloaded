#+build windows
package script

import "core:sync"
import win "core:sys/windows"

// Lua is lua54.dll here (vendor:lua/5.4), and the server is linked to load it late, when
// a script is first opened: a server with no script starts without it, and one whose
// script finds no Lua says so and plays on. It is looked for as Windows looks for any
// library, beside the server first; then where Odin keeps it, for a build run from the
// source, as the tests are.
@(extra_linker_flags = "/DELAYLOAD:lua54.dll")
foreign import delayimp "system:delayimp.lib"

@(default_calling_convention = "system")
foreign delayimp {
	// Every import from the library bound now, so none is left to fail on its first call.
	__HrLoadAllImportsForDll :: proc(dll: cstring) -> i32 ---
}

@(private = "file")
lua_once: sync.Once

@(private = "file")
lua_found: bool

// Whether Lua is there to run a script with.
lua_library :: proc() -> bool {
	sync.once_do(&lua_once, proc() {
		library := win.LoadLibraryW(win.L("lua54.dll"))
		if library == nil do library = win.LoadLibraryW(win.utf8_to_wstring(ODIN_ROOT + "vendor/lua/5.4/windows/lua54.dll"))
		lua_found = library != nil && __HrLoadAllImportsForDll("lua54.dll") >= 0
	})
	return lua_found
}
