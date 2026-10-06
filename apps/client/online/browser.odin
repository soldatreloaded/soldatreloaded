package online

import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "../../../core/http"
import network "../../../core/network"
import "../../../core/utils"

// The server browser's list: the lobby's servers (the client config's network.lobby),
// each asked the query (core/network's query.odin) what it is playing and how far away
// it is. The list comes over HTTPS on a thread of its own, so a frame never waits on
// the lobby; the queries go out together from one socket and their answers are taken as
// they come, each server asked again if it hasn't answered within a second, and given
// up on after three. What a server says is its own, now: the lobby only knows where it
// is. The main menu reads it and refreshes it; nothing here draws.

BROWSER_MAX :: 256
QUERY_RESEND :: 1.0 // seconds before a server is asked again
QUERY_TRIES :: 3    // and how many times, before it is given up on
LIST_PATH :: "/v1/servers.txt"
AGENT :: "soldatreloaded/" + #config(SOLDATRELOADED_VERSION, "dev") // what the client says it is to the web

Browser_State :: enum {
	Idle,     // never asked
	Fetching, // the lobby asked for its list
	Querying, // the servers asked what they are playing
	Done,     // everything that will answer has
	Failed,   // the lobby couldn't be reached; `error` says why
}

Browser_Server :: struct {
	address:  network.Query_Address,
	answered: bool,
	info:     network.Server_Info, // once answered
	ping:     int,                 // milliseconds, once answered
	nonce:    u32,                 // the query's
	sent:     f64,                 // when it was last asked
	asked:    int,                 // how many times
}

Browser :: struct {
	state:     Browser_State,
	error:     utils.Short_String(160),
	servers:   [BROWSER_MAX]Browser_Server, // in the lobby's order
	count:     int,
	answered:  int,
	socket:    network.Query_Socket, // the queries', while querying
	fetch:     ^Lobby_Fetch,         // the list on its way, while fetching
	refreshes: u32,                  // counted, so a reader can tell a new list from the last
}

// The list's request, on its thread: what it asks, and what came back once `done`.
@(private = "file")
Lobby_Fetch :: struct {
	thread: ^thread.Thread,
	done:   bool, // atomic: the thread's work is over, and what follows may be read
	url:    string,
	body:   []u8,
	ok:     bool,
}

// The list asked for anew from the lobby at `lobby_url`, everything known forgotten.
browser_refresh :: proc(b: ^Browser, lobby_url: string) {
	browser_stop(b)
	b.count, b.answered = 0, 0
	b.error = {}
	b.refreshes += 1
	base := strings.trim_right(strings.trim_space(lobby_url), "/")
	if base == "" {
		browser_fail(b, "there is no lobby to ask: network.lobby is empty")
		return
	}
	f := new(Lobby_Fetch)
	f.url = strings.concatenate({base, LIST_PATH})
	f.thread = thread.create_and_start_with_data(f, proc(data: rawptr) {
		f := (^Lobby_Fetch)(data)
		f.body, f.ok = http.get(f.url, AGENT)
		sync.atomic_store(&f.done, true)
	})
	b.fetch = f
	b.state = .Fetching
}

// Each frame: the list taken when it comes, the queries sent and resent, the answers read.
browser_pump :: proc(b: ^Browser) {
	now := seconds()
	if b.state == .Fetching && sync.atomic_load(&b.fetch.done) do list_take(b, now)
	if b.state != .Querying do return
	answers_take(b, now)
	waiting := false
	for &s in b.servers[:b.count] {
		if s.answered do continue
		if now - s.sent >= QUERY_RESEND && s.asked < QUERY_TRIES {
			network.query_ask(&b.socket, s.address, s.nonce)
			s.sent = now
			s.asked += 1
		}
		if s.asked < QUERY_TRIES || now - s.sent < QUERY_RESEND do waiting = true
	}
	if !waiting { // nobody else will answer
		b.state = .Done
		network.query_socket_close(&b.socket)
	}
}

browser_close :: proc(b: ^Browser) {
	browser_stop(b)
	b.state = .Idle
}

@(private = "file")
browser_stop :: proc(b: ^Browser) {
	if b.fetch != nil {
		fetch_free(b.fetch) // waits out the request: a refresh while fetching is rare
		b.fetch = nil
	}
	network.query_socket_close(&b.socket)
}

@(private = "file")
browser_fail :: proc(b: ^Browser, why: string) {
	b.state = .Failed
	utils.short_string_set(&b.error, why)
}

@(private = "file")
fetch_free :: proc(f: ^Lobby_Fetch) {
	thread.join(f.thread)
	thread.destroy(f.thread)
	delete(f.body)
	delete(f.url)
	free(f)
}

// The list has come: every server on it asked the query.
@(private = "file")
list_take :: proc(b: ^Browser, now: f64) {
	f := b.fetch
	b.fetch = nil
	defer fetch_free(f)
	if !f.ok {
		browser_fail(b, "the lobby didn't answer")
		return
	}
	list: [BROWSER_MAX]network.Query_Address
	b.count = network.query_parse_list(string(f.body), list[:])
	base := u32(time.tick_now()._nsec) * 2654435761
	for i in 0 ..< b.count {
		b.servers[i] = {address = list[i], nonce = base ~ (u32(i) * 0x9E3779B9), sent = -1e9}
	}
	if !network.query_socket_open(&b.socket) {
		browser_fail(b, "there is no socket to ask the servers with")
		return
	}
	b.state = .Querying if b.count > 0 else .Done
}

// Every answer waiting on the socket, each matched to the server that was asked.
@(private = "file")
answers_take :: proc(b: ^Browser, now: f64) {
	buf: [network.QUERY_REPLY_MAX + 16]u8
	for {
		from, data, ok := network.query_take(&b.socket, buf[:])
		if !ok do return
		for &s in b.servers[:b.count] {
			if s.answered || s.address.port != from.port || utils.short_string_text(&s.address.ip) != utils.short_string_text(&from.ip) do continue
			if info, read := network.query_read_reply(data, s.nonce); read {
				s.answered = true
				s.info = info
				s.ping = int((now - s.sent) * 1000 + 0.5)
				b.answered += 1
			}
			break
		}
	}
}

@(private = "file")
seconds :: proc() -> f64 {
	return time.duration_seconds(time.tick_since({}))
}
