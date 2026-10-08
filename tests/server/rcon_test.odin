package server_test

import "core:log"
import tcp "core:net"
import "core:strings"
import "core:testing"
import "core:time"

import net "../../core/network"
import res "../../core/resources"
import "../../apps/server"

// Rcon as an admin tool or telnet speaks it, over a real TCP connection on the loopback:
// greeted, a wrong password answered and hung up on; the right one, and the commands
// said with it in the same packet, run as the console's admin commands are, their
// answers sent back; the console's own (quit) aren't rcon's. The join password set and
// cleared, and never said back; a line no admin command takes handed to the script.
@(test)
rcon :: proc(t: ^testing.T) {
	PASSWORD :: "secret"
	testing.expect(t, net.net_init())
	defer net.net_shutdown()
	sv := new(server.Server)
	defer free(sv)
	config: res.Server_Config
	testing.expect(t, open_server(sv, &config))
	defer server.server_destroy(sv)
	r := new(server.Rcon)
	defer free(r)
	if !testing.expect(t, server.rcon_open(r, "127.0.0.1", PORT), "rcon listens on the game's port number, over TCP") do return
	defer server.rcon_close(r)
	logger := context.logger
	context.logger = log.create_multi_logger(logger, server.rcon_logger(r))
	defer log.destroy_multi_logger(context.logger)

	Admin :: struct {
		socket: tcp.TCP_Socket,
		heard:  strings.Builder,
	}
	connect :: proc(t: ^testing.T) -> (a: Admin, ok: bool) {
		socket, err := tcp.dial_tcp_from_endpoint({tcp.IP4_Loopback, PORT})
		if !testing.expectf(t, err == nil, "an admin connects: %v", err) do return
		tcp.set_blocking(socket, false)
		return {socket = socket, heard = strings.builder_make(context.temp_allocator)}, true
	}
	send :: proc(a: ^Admin, text: string) {
		tcp.send_tcp(a.socket, transmute([]u8)text)
	}
	// the server pumped until the admin has heard `want`, or has been hung up on
	hear :: proc(sv: ^server.Server, r: ^server.Rcon, a: ^Admin, want: string) -> (heard, closed: bool) {
		for _ in 0 ..< 300 {
			server.rcon_pump(r, sv, PASSWORD, time.duration_seconds(time.tick_since({})))
			buf: [1024]u8
			n, err := tcp.recv_tcp(a.socket, buf[:])
			if err == nil && n > 0 do strings.write_bytes(&a.heard, buf[:n])
			if strings.contains(strings.to_string(a.heard), want) do return true, false
			if err != nil && err != .Would_Block || err == nil && n == 0 do return false, true
			time.sleep(5 * time.Millisecond)
		}
		return
	}

	// a wrong password: answered, and hung up on
	wrong, wrong_ok := connect(t)
	if !wrong_ok do return
	defer tcp.close(wrong.socket)
	heard, _ := hear(sv, r, &wrong, "Admin Connection Established.")
	testing.expect(t, heard, "an admin is greeted")
	send(&wrong, "guess\r\n")
	heard, _ = hear(sv, r, &wrong, "Invalid password.")
	testing.expect(t, heard, "a wrong password is answered")
	_, closed := hear(sv, r, &wrong, "never said")
	testing.expect(t, closed, "and hung up on")

	// the right one, and a command in the same packet
	a, ok := connect(t)
	if !ok do return
	defer tcp.close(a.socket)
	send(&a, PASSWORD + "\n/pause\n")
	heard, _ = hear(sv, r, &a, "Game paused")
	testing.expect(t, heard && strings.contains(strings.to_string(a.heard), "Welcome"), "the right password lets the admin in, and its command is answered")
	testing.expect(t, server.server_paused(sv), "the game is paused from rcon")
	send(&a, "unpause\r\nkick nobody\r\n") // the '/' is the admin's to give or not
	heard, _ = hear(sv, r, &a, "No player nobody.")
	testing.expect(t, heard && !server.server_paused(sv), "commands without their '/', each answered")
	send(&a, "quit\n")
	heard, _ = hear(sv, r, &a, "No command quit")
	testing.expect(t, heard, "the console's own aren't rcon's")
	send(&a, "help\n")
	heard, _ = hear(sv, r, &a, "/kick")
	testing.expect(t, heard, "help lists the admin commands")

	// the join password: set, refused when it couldn't be typed, and cleared; never said back
	send(&a, "password gather42\n")
	heard, _ = hear(sv, r, &a, "The join password is set.")
	testing.expect(t, heard && server.server_password(sv) == "gather42", "rcon sets the join password")
	send(&a, "password two words\n")
	heard, _ = hear(sv, r, &a, "at most 32 letters")
	testing.expect(t, heard && server.server_password(sv) == "gather42", "one with a space is refused")
	send(&a, "password\n")
	heard, _ = hear(sv, r, &a, "The join password is cleared.")
	testing.expect(t, heard && server.server_password(sv) == "", "and clears it")
	testing.expect(t, !strings.contains(strings.to_string(a.heard), "gather42"), "the password is never said back, nor in the log")

	// a line no admin command takes goes to the script, which answers it or doesn't
	@(static) script_heard: [dynamic]string
	sv.hooks.rcon = proc(user: rawptr, text: string) -> bool {
		append(&script_heard, strings.clone(text, context.temp_allocator))
		return text == "gather start 7"
	}
	send(&a, "gather start 7\nnothing here\n")
	heard, _ = hear(sv, r, &a, "No command nothing")
	testing.expect(t, heard && len(script_heard) == 2 && script_heard[0] == "gather start 7", "the script hears what the server has no command for")
	testing.expect(t, !strings.contains(strings.to_string(a.heard), "No command gather"), "and what it answers isn't refused")
	delete(script_heard)
}
