package server

import "base:runtime"
import "core:log"
import "core:net"
import "core:strings"
import "core:sync"

// Remote admins (rcon), as OpenSoldat's admin server takes them, so its tools and a plain
// telnet both do: TCP on the game's port number, each connection greeted, its first line
// the admin password, and every line after it an admin command (admin.odin), the '/'
// before it as the admin likes. What the server logs from then on, the answers to the
// commands among it, goes to every admin logged in, a line ending "\r\n". A wrong
// password, or none within RCON_LOGIN_SECONDS, is answered and the connection closed.
//
// The listener and every connection are non-blocking, and pumped with the server
// between its ticks, so a command runs on the server's thread as the console's do. The
// log reaches the admins through a logger (rcon_logger) the server's own is joined
// with: any thread may log, so what it says waits under a lock for the next pump.
// OpenSoldat's SHUTDOWN and REFRESHX aren't taken: stopping the server is its console's
// (quit), and its status is the admin commands'.

RCON_MAX :: 8                // admins connected at once, logged in or not
RCON_LOGIN_SECONDS :: 5      // to say the password in
RCON_RATE :: 5               // connections taken a second, after a burst of RCON_BURST
RCON_BURST :: 10
RCON_LINE_MAX :: 1024        // a line longer is no admin's: the connection is closed
RCON_OUTPUT_MAX :: 256 * 1024 // unsent to an admin who doesn't read: the connection is closed
RCON_LOG_MAX :: 1024         // log lines waiting for the pump, at most; the oldest go

Rcon :: struct {
	listener:  net.TCP_Socket,
	listening: bool,
	admins:    [dynamic]Rcon_Admin,
	tokens:    f64, // connections that may be taken now (RCON_RATE, RCON_BURST)
	filled:    f64, // when the tokens were last counted
	lock:      sync.Mutex, // over `lines` and `heard`, which any thread's logging adds to
	lines:     [dynamic]string, // logged since the last pump, for the admins
	heard:     bool, // an admin is logged in: the log is kept for them (atomic)
}

Rcon_Admin :: struct {
	socket:  net.TCP_Socket,
	address: string,   // "1.2.3.4:5678", for the log
	authed:  bool,
	opened:  f64,      // when it connected, for the password's time
	input:   [dynamic]u8, // what has come and isn't a whole line yet
	output:  [dynamic]u8, // what is to go and hasn't
	closing: bool,     // closed once what it is owed has gone
}

// Listening on `port` (and `address`, an IPv4 address or a name that resolves to one, as
// the game's is; empty for every one). False, logged, if it can't.
rcon_open :: proc(r: ^Rcon, address: string, port: u16) -> bool {
	ip: net.Address = net.IP4_Any
	if address != "" {
		if parsed, ok := net.parse_ip4_address(address); ok {
			ip = parsed
		} else if resolved, err := net.resolve_ip4(address); err == nil {
			ip = resolved.address
		} else {
			log.errorf("rcon: %s isn't an IPv4 address or a name for one to listen on", address)
			return false
		}
	}
	socket, err := net.listen_tcp({address = ip, port = int(port)}, backlog = RCON_MAX)
	if err != nil {
		log.errorf("rcon: can't listen on TCP port %d: %v", port, err)
		return false
	}
	if net.set_blocking(socket, false) != nil {
		net.close(socket)
		log.errorf("rcon: can't listen on TCP port %d without blocking", port)
		return false
	}
	r.listener = socket
	r.listening = true
	r.lines = make([dynamic]string, runtime.heap_allocator()) // any thread may log into it
	r.tokens = RCON_BURST
	log.infof("rcon: listening on TCP port %d", port)
	return true
}

rcon_close :: proc(r: ^Rcon) {
	for &admin in r.admins do admin_close(&admin)
	delete(r.admins)
	if r.listening do net.close(r.listener)
	sync.guard(&r.lock)
	for line in r.lines do delete(line, runtime.heap_allocator())
	delete(r.lines)
	r^ = {}
}

// Between the server's ticks, `now` in seconds: the connections taken, what they said
// run (`password` the admin password, as the config has it now), and the log sent.
rcon_pump :: proc(r: ^Rcon, sv: ^Server, password: string, now: f64) {
	if !r.listening do return
	rcon_accept(r, now)
	for &admin in r.admins {
		if !admin.closing do admin_read(r, &admin, sv, password, now)
	}
	// what was logged, the answers above among it, to everyone logged in
	any_authed := false
	for &admin in r.admins do any_authed ||= admin.authed && !admin.closing
	sync.atomic_store(&r.heard, any_authed)
	{
		sync.guard(&r.lock)
		for line in r.lines {
			for &admin in r.admins {
				if admin.authed && !admin.closing do admin_say(&admin, line)
			}
			delete(line, runtime.heap_allocator())
		}
		clear(&r.lines)
	}
	for i := 0; i < len(r.admins); {
		admin := &r.admins[i]
		if admin_flush(admin) && !(admin.closing && len(admin.output) == 0) {
			i += 1
			continue
		}
		if admin.authed do log.infof("rcon: %s left", admin.address)
		admin_close(admin)
		unordered_remove(&r.admins, i)
	}
}

// A logger that keeps what is said for the admins logged in, to be joined with the
// server's own (log.create_multi_logger). `r` must stay where it is while it is used.
rcon_logger :: proc(r: ^Rcon) -> log.Logger {
	return {procedure = rcon_log, data = r, lowest_level = .Info}
}

@(private = "file")
rcon_log :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
	r := (^Rcon)(data)
	if !sync.atomic_load(&r.heard) do return
	sync.guard(&r.lock)
	if len(r.lines) >= RCON_LOG_MAX {
		delete(r.lines[0], runtime.heap_allocator())
		ordered_remove(&r.lines, 0)
	}
	append(&r.lines, strings.clone(text, runtime.heap_allocator())) // freed by the pump, on its own thread
}

// The connections waiting, taken while the rate and the room allow; the rest closed.
@(private = "file")
rcon_accept :: proc(r: ^Rcon, now: f64) {
	r.tokens = min(r.tokens + (now - r.filled) * RCON_RATE, RCON_BURST)
	r.filled = now
	for {
		socket, from, err := net.accept_tcp(r.listener)
		if err != nil do return // none waiting, or none to be had
		if r.tokens < 1 || len(r.admins) >= RCON_MAX || net.set_blocking(socket, false) != nil {
			net.close(socket)
			continue
		}
		r.tokens -= 1
		append(&r.admins, Rcon_Admin{socket = socket, address = strings.clone(net.endpoint_to_string(from)), opened = now})
		admin_say(&r.admins[len(r.admins) - 1], "Soldat Reloaded Admin Connection Established.")
	}
}

// What the admin sent, a line at a time: the password, then commands.
@(private = "file")
admin_read :: proc(r: ^Rcon, admin: ^Rcon_Admin, sv: ^Server, password: string, now: f64) {
	buf: [1024]u8
	for {
		n, err := net.recv_tcp(admin.socket, buf[:])
		if err == .Would_Block do break
		if err != nil || n == 0 { // gone
			admin.closing = true
			clear(&admin.output)
			return
		}
		append(&admin.input, ..buf[:n])
	}
	for {
		end := -1
		for c, i in admin.input {
			if c == '\n' {
				end = i
				break
			}
		}
		if end < 0 do break
		line := strings.trim_space(string(admin.input[:end]))
		admin_line(r, admin, sv, password, line)
		remove_range(&admin.input, 0, end + 1)
		if admin.closing do return
	}
	if len(admin.input) > RCON_LINE_MAX {
		admin.closing = true
		return
	}
	if !admin.authed && now - admin.opened > RCON_LOGIN_SECONDS {
		admin_say(admin, "Password request timed out.")
		admin.closing = true
	}
}

@(private = "file")
admin_line :: proc(r: ^Rcon, admin: ^Rcon_Admin, sv: ^Server, password: string, line: string) {
	if !admin.authed {
		if password == "" || line != password {
			admin_say(admin, "Invalid password.")
			admin.closing = true
			log.warnf("rcon: a wrong password from %s", admin.address)
			return
		}
		admin.authed = true
		sync.atomic_store(&r.heard, true) // what it asks next, in the same packet, is answered
		admin_say(admin, "Welcome, you are in command of the server now.")
		admin_say(admin, "/help lists the commands.")
		log.infof("rcon: %s logged in", admin.address)
		return
	}
	text := strings.trim_left(line, "/")
	if text == "" do return
	word, _ := next_word(text)
	log.infof("rcon %s: %s", admin.address, "password ..." if word == "password" else text) // every admin reads the log
	if admin_command(sv, Rcon_Caller{admin.address}, text) do return
	// what the server hasn't, a script's: a controller's word to it (the gather bot's)
	if sv.hooks.rcon != nil && sv.hooks.rcon(sv.hooks.user, text) do return
	log.infof("No command %s; /help lists them.", word)
}

// A line to the admin, as the log's are sent.
@(private = "file")
admin_say :: proc(admin: ^Rcon_Admin, text: string) {
	append(&admin.output, text)
	append(&admin.output, "\r\n")
}

// What the admin is owed, sent as far as it will go; false if the connection is lost,
// or the admin reads too little of it.
@(private = "file")
admin_flush :: proc(admin: ^Rcon_Admin) -> bool {
	if len(admin.output) == 0 do return true
	sent, err := net.send_tcp(admin.socket, admin.output[:])
	remove_range(&admin.output, 0, sent)
	if err != nil && err != .Would_Block do return false
	return len(admin.output) <= RCON_OUTPUT_MAX
}

@(private = "file")
admin_close :: proc(admin: ^Rcon_Admin) {
	net.close(admin.socket)
	delete(admin.address)
	delete(admin.input)
	delete(admin.output)
}
