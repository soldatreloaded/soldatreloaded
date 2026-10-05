package network

import "base:runtime"
import "core:strings"

import enet "vendor:ENet"

// The transport: ENet under the messages. Two channels, one unreliable for state and
// one reliable for news, and which a message takes is its kind's to say (RELIABLE). A
// Link is one end: a server listening for many, or a client with its one peer. Nothing
// here knows what the bytes mean; the messages (message.odin) do.
//
// ENet sends what it was given when it is next serviced or flushed; both ends flush at
// the end of their tick, so nothing waits a tick in the queue.

CHANNEL_UNRELIABLE :: 0
CHANNEL_RELIABLE :: 1
CHANNELS :: 2

Link :: struct {
	host: ^enet.Host,
	peer: ^enet.Peer, // a client's server; nil on a server
}

Peer :: ^enet.Peer

Event_Kind :: enum {
	None,
	Connect,
	Disconnect,
	Message,
}

// What net_poll found: who, and for a message its bytes and the kind read off its
// front (Invalid for a message too big or with nothing readable in front).
Event :: struct {
	kind: Event_Kind,
	peer: Peer,
	msg:  Msg_Kind,
	data: [MTU]u8,
	size: int,
}

// Once per program.
net_init :: proc() -> bool {
	return enet.initialize() == 0
}

net_shutdown :: proc() {
	enet.deinitialize()
}

// Listens on `port`, on every address when `ip` is empty, else on that one alone (an
// address, or a name to resolve: a host behind a UDP proxy that rewrites addresses
// answers from the one it was reached on).
net_listen :: proc(l: ^Link, ip: string, port: u16, max_peers: int) -> bool {
	address := enet.Address{host = enet.HOST_ANY, port = port}
	if ip != "" && enet.address_set_host(&address, strings.clone_to_cstring(ip, context.temp_allocator)) != 0 {
		l^ = {}
		return false
	}
	l^ = {host = enet.host_create(&address, uint(max_peers), CHANNELS, 0, 0)}
	return l.host != nil
}

net_connect :: proc(l: ^Link, address: string, port: u16) -> bool {
	l^ = {host = enet.host_create(nil, 1, CHANNELS, 0, 0)}
	if l.host == nil do return false
	to := enet.Address{port = port}
	if enet.address_set_host(&to, strings.clone_to_cstring(address, context.temp_allocator)) != 0 {
		net_close(l)
		return false
	}
	l.peer = enet.host_connect(l.host, &to, CHANNELS, 0)
	if l.peer == nil {
		net_close(l)
		return false
	}
	return true
}

// Tells the peer(s) goodbye and gives them a moment to hear it, then closes.
net_close :: proc(l: ^Link) {
	if l.host == nil do return
	for i in 0 ..< l.host.peerCount {
		p := &l.host.peers[i]
		if p.state == .CONNECTED do enet.peer_disconnect(p, 0)
	}
	// a few rounds for the goodbyes to go out and be answered
	e: enet.Event
	for _ in 0 ..< 10 {
		if enet.host_service(l.host, &e, 10) < 0 do break
		if e.type == .RECEIVE do enet.packet_destroy(e.packet)
	}
	net_answer_queries(l, nil, nil)
	enet.host_destroy(l.host)
	l^ = {}
}

// A message to a peer, on the channel its kind calls for. False if it couldn't be queued.
net_send :: proc(peer: Peer, kind: Msg_Kind, data: []u8) -> bool {
	if peer == nil || kind == .Invalid || len(data) > MTU do return false
	reliable := kind in RELIABLE
	packet := enet.packet_create(raw_data(data), uint(len(data)), {.RELIABLE} if reliable else {})
	if packet == nil do return false
	if enet.peer_send(peer, CHANNEL_RELIABLE if reliable else CHANNEL_UNRELIABLE, packet) != 0 {
		enet.packet_destroy(packet)
		return false
	}
	return true
}

// A message built from `m` and sent to `peer`; false if it didn't fit or couldn't go.
net_send_message :: proc(peer: Peer, kind: Msg_Kind, routine: proc(b: ^Buffer, m: ^$M), m: ^M) -> bool {
	buf: [MTU]u8
	bytes := build(buf[:], kind, routine, m)
	return bytes != nil && net_send(peer, kind, bytes)
}

// The next event, waiting up to `timeout_ms` for one. None when there is none.
net_poll :: proc(l: ^Link, e: ^Event, timeout_ms: u32) -> Event_Kind {
	e^ = {}
	if l.host == nil do return .None
	event: enet.Event
	if enet.host_service(l.host, &event, timeout_ms) <= 0 do return .None
	e.peer = event.peer
	#partial switch event.type {
	case .CONNECT:
		e.kind = .Connect
	case .DISCONNECT:
		e.kind = .Disconnect
	case .RECEIVE:
		e.kind = .Message
		if event.packet.dataLength <= MTU {
			e.size = int(event.packet.dataLength)
			copy(e.data[:e.size], event.packet.data[:e.size])
			b := buffer_reader(e.data[:e.size])
			kind: Msg_Kind
			msg_kind(&b, &kind)
			e.msg = kind if buffer_ok(&b) else .Invalid
		}
		enet.packet_destroy(event.packet)
	}
	return e.kind
}

// Sends what is queued now.
net_flush :: proc(l: ^Link) {
	if l.host != nil do enet.host_flush(l.host)
}

// A peer's address, as ENet has it, and its round trip in milliseconds.
peer_address :: proc(peer: Peer) -> u32 {
	return peer.address.host
}

peer_ping :: proc(peer: Peer) -> u16 {
	return u16(min(peer.roundTripTime, 65535))
}

// The peer told goodbye once what is queued for it has gone.
peer_disconnect_later :: proc(peer: Peer) {
	enet.peer_disconnect_later(peer, 0)
}

// ---------------------------------------------------------------------------------
// Queries

// A query (query.odin) arriving on the link's port is answered with what `answer`
// fills in, from whichever call into ENet receives it, and never reaches the peers.
// nil stops the answering, as net_close does. False if too many links answer already.
Query_Answer :: proc(user: rawptr, info: ^Server_Info)

net_answer_queries :: proc(l: ^Link, answer: Query_Answer, user: rawptr) -> bool {
	if l.host == nil do return false
	for &a in answering {
		if a.host == l.host do a = {}
	}
	l.host.intercept = nil
	if answer == nil do return true
	for &a in answering {
		if a.host != nil do continue
		a = {host = l.host, answer = answer, user = user}
		l.host.intercept = intercept
		return true
	}
	return false
}

// The links answering queries. ENet's intercept is told only the host, so the host is
// looked up here: a server answers on its one, and a test may open a few side by side.
@(private = "file")
Answering :: struct {
	host:   ^enet.Host,
	answer: Query_Answer,
	user:   rawptr,
}

@(private = "file")
answering: [4]Answering

// Every datagram the host receives, before ENet reads it: a query is answered and kept
// from ENet, and so is anything else with a query's front; the rest goes on.
@(private = "file")
intercept :: proc "c" (host: ^enet.Host, event: ^enet.Event) -> i32 {
	context = runtime.default_context()
	received := host.receivedData[:host.receivedDataLength]
	if !query_is_query(received) do return 0
	nonce, is_request := query_read_request(received)
	if !is_request do return 1
	for &a in answering {
		if a.host != host do continue
		info: Server_Info
		a.answer(a.user, &info)
		reply: [QUERY_REPLY_MAX]u8
		bytes := query_write_reply(reply[:], nonce, &info)
		if bytes != nil do datagram_send(host.socket, &host.receivedAddress, bytes)
		break
	}
	return 1
}

// One datagram on a plain socket, outside ENet's peers: a query or its reply. ENet's
// buffer is laid out as the platform's own (WSABUF on Windows, the length first; iovec
// elsewhere, the data first), which vendor:ENet declares data first everywhere, so it
// is laid out here.
datagram_send :: proc(socket: enet.Socket, to: ^enet.Address, bytes: []u8) -> bool {
	when ODIN_OS == .Windows {
		Platform_Buffer :: struct {
			length: uint,
			data:   rawptr,
		}
	} else {
		Platform_Buffer :: struct {
			data:   rawptr,
			length: uint,
		}
	}
	buffer := Platform_Buffer{data = raw_data(bytes), length = uint(len(bytes))}
	return enet.socket_send(socket, to, (^enet.Buffer)(&buffer), 1) == i32(len(bytes))
}

// One datagram received on a plain socket, into `buf`: its bytes, or nothing.
datagram_receive :: proc(socket: enet.Socket, from: ^enet.Address, buf: []u8) -> []u8 {
	when ODIN_OS == .Windows {
		Platform_Buffer :: struct {
			length: uint,
			data:   rawptr,
		}
	} else {
		Platform_Buffer :: struct {
			data:   rawptr,
			length: uint,
		}
	}
	buffer := Platform_Buffer{data = raw_data(buf), length = uint(len(buf))}
	n := enet.socket_receive(socket, from, (^enet.Buffer)(&buffer), 1)
	return buf[:n] if n > 0 else nil
}
