package http

// HTTPS through libcurl (vendor:curl), for every program that makes a request: the
// server's lobby and its scripts, and the launcher. Curl is started once, and each
// request's handle is made to trust what it should (secure): on Windows curl trusts what
// the system trusts; on Linux it is built on mbedTLS, which knows no certificates of its
// own, so it is given the distribution's bundle (ca_bundle_*.odin).
//
// A program with more to ask than `get` (a method, a body, a thread of its own) makes
// its own handle, and calls start and secure on it as get does.

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"

import curl "vendor:curl"

// Curl's global state made ready, once, from any thread.
start :: proc() {
	@(static) once: sync.Once
	sync.once_do(&once, proc() {curl.global_init(curl.GLOBAL_DEFAULT)})
}

// A request's handle made to trust what it should.
secure :: proc(handle: ^curl.CURL) {
	when ODIN_OS == .Windows {
		// Schannel fails outright where a revocation list can't be reached (behind some
		// proxies).
		curl.easy_setopt(handle, .SSL_OPTIONS, c.long(curl.SSLOPT_REVOKE_BEST_EFFORT))
	}
	if bundle := ca_bundle(); bundle != nil do curl.easy_setopt(handle, .CAINFO, bundle)
}

// The body at `url`, following redirects, made with `allocator`. False for no answer,
// or an answer with an error status. `agent` is what the request says it is.
get :: proc(url: string, agent: cstring, allocator := context.allocator) -> (body: []byte, ok: bool) {
	start()
	handle := curl.easy_init()
	if handle == nil do return nil, false
	defer curl.easy_cleanup(handle)

	received := make([dynamic]byte, allocator)
	curl.easy_setopt(handle, .URL, strings.clone_to_cstring(url, context.temp_allocator))
	curl.easy_setopt(handle, .USERAGENT, agent)
	curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
	curl.easy_setopt(handle, .FAILONERROR, c.long(1))
	curl.easy_setopt(handle, .CONNECTTIMEOUT, c.long(10))
	curl.easy_setopt(handle, .NOSIGNAL, c.long(1))
	curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(receive))
	curl.easy_setopt(handle, .WRITEDATA, &received)
	secure(handle)

	if curl.easy_perform(handle) != .E_OK {
		delete(received)
		return nil, false
	}
	return received[:], true
}

@(private = "file")
receive :: proc "c" (data: [^]byte, one: c.size_t, n: c.size_t, user: rawptr) -> c.size_t {
	context = runtime.default_context() // the append uses the array's own allocator
	append((^[dynamic]byte)(user), ..data[:n])
	return n
}
