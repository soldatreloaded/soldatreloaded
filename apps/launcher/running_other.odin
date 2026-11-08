#+build !windows
package launcher

import "core:os"

// The game made to close (close_game): SIGKILL.
force_close :: proc(process: os.Process) -> bool {
	return os.process_kill(process) == nil
}

same_path :: proc(a, b: string) -> bool {
	return a == b
}

// A program just written let run: on macOS a file that came over the network is
// quarantined, and macOS won't open one it can't verify (this game is not signed) until
// the player allows it in Privacy & Security; a program the launcher writes isn't
// downloaded by the system's reckoning, but should it carry the mark, it is taken off,
// so a player who allowed the game once needn't again after each update. Elsewhere
// there is no such mark.
unquarantine :: proc(path: string) {
	when ODIN_OS == .Darwin {
		process, err := os.process_start({command = {"/usr/bin/xattr", "-d", "com.apple.quarantine", path}})
		if err != nil do return
		_, _ = os.process_wait(process)
	}
}
