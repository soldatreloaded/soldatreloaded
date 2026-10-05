#+build !windows
package server

// Lua is linked into the server here (vendor:lua/5.4): always there.
lua_library :: proc() -> bool {
	return true
}
