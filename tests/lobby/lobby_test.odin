package lobby_test

// The heartbeat's pieces: the lobby's address, the JSON said to it, and what is read
// from its answers. The requests themselves need a lobby, and are tried against one by
// hand (the soldatreloaded-lobby repository's README).
//
//   odin test tests/lobby

import "core:testing"

import "../../apps/server/lobby"

@(test)
url :: proc(t: ^testing.T) {
	url, ok := lobby.lobby_url("https://lobby.example")
	testing.expect(t, ok && url == "https://lobby.example/v1/servers", "the servers' path on the lobby")
	url, ok = lobby.lobby_url("https://lobby.example//")
	testing.expect(t, ok && url == "https://lobby.example/v1/servers", "trailing slashes or not")
	_, ok = lobby.lobby_url("")
	testing.expect(t, !ok, "no lobby is refused")
}

@(test)
body :: proc(t: ^testing.T) {
	body, ok := lobby.lobby_body(23073, "")
	testing.expect(t, ok && body == "{\"port\":23073}", "a heartbeat says its port")
	body, ok = lobby.lobby_body(23073, "213.188.216.246")
	testing.expect(t, ok && body == "{\"port\":23073,\"address\":\"213.188.216.246\"}", "and the address it names")
	bad := [?]string{"1.2.3", "1.2.3.4.5", "256.1.1.1", "1.2.3.4 ", "a.b.c.d", "1..2.3", "0001.2.3.4", "\"},{\"x\":\"1"}
	for address in bad {
		_, ok = lobby.lobby_body(1, address)
		testing.expectf(t, !ok, "'%s' is not an IPv4 address", address)
	}
}

@(test)
answers :: proc(t: ^testing.T) {
	answer := "{\"address\":\"203.0.113.5\",\"port\":23073,\"heartbeat_seconds\":30}\n"
	testing.expect(t, lobby.lobby_interval(answer) == 30, "the interval the lobby asks for")
	as, ok := lobby.lobby_listed_as(answer)
	testing.expect(t, ok && as == "203.0.113.5:23073", "and what it lists")
	testing.expect(t, lobby.lobby_interval("{ \"heartbeat_seconds\" : 45 }") == 45, "spaces about the colon")
	_, ok = lobby.lobby_listed_as("")
	testing.expect(t, lobby.lobby_interval("the lobby could not reach 1.2.3.4:23073") == 0 && !ok, "an answer that isn't one says nothing")
}

// The pump's bookkeeping short of a request: what it refuses to send, and that a
// private server asks nothing of anyone.
@(test)
pump :: proc(t: ^testing.T) {
	l: lobby.Lobby
	lobby.lobby_init(&l)
	defer lobby.lobby_close(&l)
	settings := lobby.Settings{public = false, url = lobby.DEFAULT_URL, port = 23073}
	lobby.lobby_pump(&l, settings, 1)
	testing.expect(t, l.request == nil && l.told == "" && !l.listed, "a private server says nothing")
	settings.public = true
	settings.url = ""
	lobby.lobby_pump(&l, settings, 2)
	testing.expect(t, l.request == nil && l.told == "sv_lobby is not an address", "no lobby to speak to")
	testing.expect(t, l.next == 2 + lobby.DEFAULT_INTERVAL, "and not tried again before its time")
	settings.url = lobby.DEFAULT_URL
	settings.address = "not-an-address"
	lobby.lobby_pump(&l, settings, 2 + lobby.DEFAULT_INTERVAL)
	testing.expect(t, l.request == nil && l.told == "sv_lobby_ip must be an IPv4 address, as 1.2.3.4", "nor an address to list")
	settings.public = false
	lobby.lobby_pump(&l, settings, 3 + lobby.DEFAULT_INTERVAL)
	testing.expect(t, l.request == nil && l.goodbye == "", "nothing was sent, so there is no goodbye to say")
}
