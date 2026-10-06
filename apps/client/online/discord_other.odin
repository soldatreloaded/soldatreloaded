#+build !windows
package online

import "core:fmt"
import "core:strings"
import "core:sys/posix"

// The pipe to the Discord app, elsewhere: a Unix socket, connected, written whole, read
// without waiting, closed.

Discord_Pipe :: struct {
	fd:   posix.FD,
	open: bool,
}

@(private = "file")
PIPES :: 10 // discord-ipc-0 to 9: one per Discord app running, the first that answers

// The runtime directory as each of these says it, and in each the places a Flatpak's or
// a Snap's Discord makes its socket.
pipe_open :: proc(p: ^Discord_Pipe) -> bool {
	ENVS :: [?]cstring{"XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"}
	SUBDIRS :: [?]string{"", "app/com.discordapp.Discord/", "snap.discord/"}
	bases := make([dynamic]string, context.temp_allocator)
	for env in ENVS {
		if v := string(posix.getenv(env)); v != "" do append(&bases, v)
	}
	append(&bases, "/tmp")
	for base in bases {
		for subdir in SUBDIRS {
			for i in 0 ..< PIPES {
				path := fmt.tprintf("%s/%sdiscord-ipc-%d", strings.trim_right(base, "/"), subdir, i)
				addr := posix.sockaddr_un {
					sun_family = .UNIX,
				}
				if len(path) >= len(addr.sun_path) do continue
				copy(addr.sun_path[:], path)
				fd := posix.socket(.UNIX, .STREAM)
				if fd < 0 do return false
				if posix.connect(fd, (^posix.sockaddr)(&addr), size_of(addr)) == .OK {
					flags := transmute(posix.O_Flags)posix.fcntl(fd, .GETFL, 0)
					posix.fcntl(fd, .SETFL, flags + {.NONBLOCK})
					p^ = {fd = fd, open = true}
					return true
				}
				posix.close(fd)
			}
		}
	}
	return false
}

pipe_is_open :: proc(p: ^Discord_Pipe) -> bool {
	return p.open
}

pipe_close :: proc(p: ^Discord_Pipe) {
	if p.open do posix.close(p.fd)
	p^ = {}
}

pipe_write :: proc(p: ^Discord_Pipe, data: []u8) -> bool {
	rest := data
	for len(rest) > 0 {
		n := posix.send(p.fd, raw_data(rest), len(rest), {.NOSIGNAL})
		if n < 0 && posix.errno() == .EINTR do continue
		if n <= 0 do return false // full or gone: a frame is a few hundred bytes, so gone
		rest = rest[n:]
	}
	return true
}

// Bytes read into `out`, 0 for none waiting, -1 for the socket gone.
pipe_read :: proc(p: ^Discord_Pipe, out: []u8) -> int {
	n := posix.recv(p.fd, raw_data(out), len(out), {})
	if n > 0 do return int(n)
	if n < 0 {
		err := posix.errno()
		if err == .EAGAIN || err == .EWOULDBLOCK || err == .EINTR do return 0
	}
	return -1
}

process_id :: proc() -> int {
	return int(posix.getpid())
}
