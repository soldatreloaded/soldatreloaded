package lobby

// The heartbeat: a dedicated server listing itself with the lobby (the
// soldatreloaded-lobby repository; docs/netcode.md, The query, and the lobby). While
// sv_public is on it says it is up as often as the lobby asks (half a minute), with its
// port, and the lobby asks it the query (core/network/query.odin) before it lists it. A
// server behind a proxy that sends from another address than players reach it on (Fly's
// fly-global-services) names the one they reach in sv_lobby_ip; without it the request
// goes over IPv4, since the lobby lists the address it is reached from and ENet is IPv4
// only.
//
// Each request runs on a thread of its own, so a slow lobby never holds up a tick, and
// what comes of it is logged when it changes rather than every half minute. A server
// leaving the list (sv_public turned off, or stopping) says so, unless it named its
// address: the lobby lets only time take that one off.

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"

// The lobby a server talks to unless sv_lobby names another; network.LOBBY_URL
// (core/network/query.odin), repeated here so the lobby needs none of the game.
DEFAULT_URL :: "https://soldatreloaded-lobby.fly.dev"

TIMEOUT :: 10         // seconds a heartbeat may take
GOODBYE_TIMEOUT :: 3  // and the goodbye, which a stopping server waits for
DEFAULT_INTERVAL :: 30.0
MIN_INTERVAL :: 10.0  // whatever the lobby says, never more often than this

// The server's part of it, from its cvars.
Settings :: struct {
	public:  bool,   // sv_public
	url:     string, // sv_lobby: the lobby's base address
	address: string, // sv_lobby_ip: the address to list; "" for the one the request comes from
	port:    u16,    // sv_port
}

Lobby :: struct {
	request:      ^Request, // the one in flight, or nil
	next:         f64,      // when the next heartbeat is due, on the pump's clock
	interval:     f64,      // seconds between heartbeats, as the lobby last said
	listed:       bool,     // the last heartbeat was taken
	told:         string,   // what was last logged, so it is logged once
	goodbye:      string,   // the lobby to say goodbye to, and how (lobby_url), while listed; "" for none
	goodbye_body: string,
	allocator:    runtime.Allocator, // what `told` and the goodbye are kept with
}

// --- the pieces ----------------------------------------------------------------------

// `base` with the servers' path: "https://x/" and "https://x" both give
// "https://x/v1/servers". False if there is no lobby in it.
lobby_url :: proc(base: string, allocator := context.temp_allocator) -> (string, bool) {
	trimmed := strings.trim_right(base, "/")
	if trimmed == "" do return "", false
	return strings.concatenate({trimmed, "/v1/servers"}, allocator), true
}

// Four numbers to 255, dotted, and nothing else.
is_ipv4 :: proc(s: string) -> bool {
	rest := s
	for part in 0 ..< 4 {
		digits := 0
		value := 0
		for digits < 4 && len(rest) > 0 && rest[0] >= '0' && rest[0] <= '9' {
			value = value * 10 + int(rest[0] - '0')
			digits += 1
			rest = rest[1:]
		}
		if digits == 0 || digits > 3 || value > 255 do return false
		if part < 3 {
			if len(rest) == 0 || rest[0] != '.' do return false
			rest = rest[1:]
		}
	}
	return len(rest) == 0
}

// The heartbeat's JSON: the port, and the address if one is named. False if the
// address is not an IPv4 address.
lobby_body :: proc(port: u16, address: string, allocator := context.temp_allocator) -> (string, bool) {
	if address == "" do return fmt.aprintf("{{\"port\":%d}}", port, allocator = allocator), true
	if !is_ipv4(address) do return "", false
	return fmt.aprintf("{{\"port\":%d,\"address\":\"%s\"}}", port, address, allocator = allocator), true
}

// What follows the value of "key" in a flat JSON object, past the colon and spaces;
// false if it isn't there.
@(private = "file")
json_value :: proc(json, key: string) -> (string, bool) {
	quoted := fmt.tprintf("\"%s\"", key)
	at := strings.index(json, quoted)
	if at < 0 do return "", false
	rest := strings.trim_left(json[at + len(quoted):], " \t\r\n")
	if len(rest) == 0 || rest[0] != ':' do return "", false
	return strings.trim_left(rest[1:], " \t\r\n"), true
}

// The number `s` begins with, as atoi reads it; 0 and false if it begins with none.
@(private = "file")
leading_int :: proc(s: string) -> (value: int, ok: bool) {
	for ch in s {
		if ch < '0' || ch > '9' do break
		value = value * 10 + int(ch - '0')
		ok = true
	}
	return
}

// The heartbeat interval the lobby's answer asks for, in seconds; 0 if it says none.
lobby_interval :: proc(reply: string) -> int {
	value, found := json_value(reply, "heartbeat_seconds")
	if !found do return 0
	return leading_int(value) or_else 0
}

// The address and port the lobby's answer lists the server as ("1.2.3.4:23073"); false
// if it says none.
lobby_listed_as :: proc(reply: string, allocator := context.temp_allocator) -> (string, bool) {
	address, has_address := json_value(reply, "address")
	port, has_port := json_value(reply, "port")
	if !has_address || !has_port || len(address) == 0 || address[0] != '"' do return "", false
	number, is_number := leading_int(port)
	if !is_number do return "", false
	end := strings.index_byte(address[1:], '"')
	if end < 0 do return "", false
	return fmt.aprintf("%s:%d", address[1:1 + end], number, allocator = allocator), true
}

// --- the heartbeat -------------------------------------------------------------------

// `told` and the goodbye are kept with `context.allocator`, until lobby_close.
lobby_init :: proc(l: ^Lobby) {
	l^ = {
		interval  = DEFAULT_INTERVAL,
		allocator = context.allocator,
	}
	http_init()
}

@(private = "file")
keep :: proc(l: ^Lobby, s: ^string, text: string) {
	if s^ != "" do delete(s^, l.allocator)
	s^ = strings.clone(text, l.allocator) if text != "" else ""
}

// A line in the log, unless it is what was told last.
@(private = "file")
tell :: proc(l: ^Lobby, text: string) {
	if l.told == text do return
	keep(l, &l.told, text)
	log.infof("lobby: %s", text)
}

// What the finished heartbeat came to.
@(private = "file")
heard :: proc(l: ^Lobby, a: ^Answer) {
	text: string
	if !a.ok {
		l.listed = false
		text = fmt.tprintf("can't be reached (%s); trying again", answer_error(a))
	} else if a.status == 200 {
		interval := lobby_interval(answer_body(a))
		if interval > 0 do l.interval = max(f64(interval), MIN_INTERVAL)
		as := lobby_listed_as(answer_body(a)) or_else "this server"
		text = fmt.tprintf("listed as %s", as)
		l.listed = true
	} else {
		// the lobby's own words: a 422 is a port it couldn't reach
		line := answer_body(a)
		if end := strings.index_any(line, "\r\n"); end >= 0 do line = line[:end]
		if len(line) > 160 do line = line[:160]
		text = fmt.tprintf("not listed: %s (%d)", line, a.status)
		l.listed = false
	}
	tell(l, text)
}

// Heartbeats while `s.public`, a goodbye once it isn't, and what came of the last
// request in the log. `now` is seconds on any steady clock. Never waits: a request
// still under way is looked in on next time.
lobby_pump :: proc(l: ^Lobby, s: Settings, now: f64) {
	if l.request != nil {
		if !request_done(l.request) do return
		heartbeat := l.request.method == "POST" // a goodbye's answer is nobody's business
		answer := request_finish(l.request)
		l.request = nil
		if heartbeat do heard(l, &answer)
	}
	if !s.public {
		if l.goodbye != "" { // taken off: say so, and nothing more until it is put back
			l.request = request_start("DELETE", l.goodbye, l.goodbye_body, true, TIMEOUT, l.allocator)
			keep(l, &l.goodbye, "")
			l.listed = false
			tell(l, "off the list")
		}
		l.next = now // put back on, it says so at once
		return
	}
	if now < l.next do return
	l.next = now + l.interval
	url, has_url := lobby_url(s.url)
	if !has_url {
		tell(l, "sv_lobby is not an address")
		return
	}
	body, has_body := lobby_body(s.port, s.address)
	if !has_body {
		tell(l, "sv_lobby_ip must be an IPv4 address, as 1.2.3.4")
		return
	}
	named := s.address != ""
	l.request = request_start("POST", url, body, !named, TIMEOUT, l.allocator)
	// the goodbye goes where the heartbeat went, from the address it came from; a named
	// address only time takes off
	if !named {
		keep(l, &l.goodbye, url)
		goodbye_body, _ := lobby_body(s.port, "")
		keep(l, &l.goodbye_body, goodbye_body)
	} else {
		keep(l, &l.goodbye, "")
	}
}

// The request in flight waited for, then the goodbye if listed, waited for a few
// seconds at most. What the lobby kept is freed.
lobby_close :: proc(l: ^Lobby) {
	if l.request != nil {
		request_finish(l.request)
		l.request = nil
	}
	if l.listed && l.goodbye != "" {
		a := http_request("DELETE", l.goodbye, l.goodbye_body, true, GOODBYE_TIMEOUT)
		if a.ok do log.info("lobby: off the list")
	}
	keep(l, &l.goodbye, "")
	keep(l, &l.goodbye_body, "")
	keep(l, &l.told, "")
	l.listed = false
}
