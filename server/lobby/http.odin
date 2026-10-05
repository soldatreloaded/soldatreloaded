package lobby

// HTTPS, through libcurl (vendor:curl), as the launcher's http.c has it, cut to what
// the heartbeat needs: one request with a method and a JSON body, its answer's status
// and body back. On Windows curl trusts what the system trusts (Schannel); on Linux it
// is built on mbedTLS, which knows no certificates of its own, so the distribution's
// bundle is found and given to it.
//
// A request either runs here, on the caller's thread (the goodbye a stopping server
// waits for), or on a thread of its own (request_start), whose outcome the caller polls
// for and collects once it is done.

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"
import "core:thread"

import curl "vendor:curl"

ANSWER_MAX :: 1024 // bytes of an answer kept; the lobby's are a line
AGENT :: "soldatreloaded-server" // what the requests say they are

// What a request came to. Any answer is `ok`, an error page too: its status says what
// it was, and its body why. Not `ok` is no answer at all, and `error` says why.
Answer :: struct {
	ok:     bool,
	status: int,
	body:   [ANSWER_MAX]byte,
	size:   int,
	error:  [curl.ERROR_SIZE]byte, // NUL-terminated, in curl's words
}

answer_body :: proc(a: ^Answer) -> string {
	return string(a.body[:a.size])
}

answer_error :: proc(a: ^Answer) -> string {
	return string(cstring(&a.error[0]))
}

// --- curl ----------------------------------------------------------------------------

@(private = "file")
Http :: struct {
	started:   bool,
	ca_bundle: cstring, // the distribution's certificates (ca_bundle); nil for curl's own
}

@(private = "file")
http: Http

// Curl made ready, once; every request after this.
http_init :: proc() {
	if http.started do return
	http.started = true
	http.ca_bundle = ca_bundle()
	curl.global_init(curl.GLOBAL_DEFAULT)
}

// Any answer's body, an error page's too, as far as ANSWER_MAX (cut, not failed,
// past it).
@(private = "file")
answer_write :: proc "c" (data: [^]byte, one: c.size_t, n: c.size_t, user: rawptr) -> c.size_t {
	a := (^Answer)(user)
	take := min(int(n), ANSWER_MAX - a.size)
	if take > 0 {
		copy(a.body[a.size:], data[:take])
		a.size += take
	}
	return n
}

// A request with `method` ("POST", "DELETE") and a JSON `body` ("" for none), given up
// after `timeout` seconds; `ipv4` keeps it to IPv4. Runs here, until it is answered or
// given up.
http_request :: proc(method, url, body: string, ipv4: bool, timeout: int) -> (a: Answer) {
	fail :: proc(a: ^Answer, why: cstring) {
		n := copy(a.error[:len(a.error) - 1], string(why))
		a.error[n] = 0
	}
	handle := curl.easy_init()
	if handle == nil {
		fail(&a, "curl couldn't start")
		return
	}
	defer curl.easy_cleanup(handle)
	method_c := strings.clone_to_cstring(method, context.temp_allocator)
	url_c := strings.clone_to_cstring(url, context.temp_allocator)
	curl.easy_setopt(handle, .URL, url_c)
	curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
	curl.easy_setopt(handle, .MAXREDIRS, c.long(10))
	curl.easy_setopt(handle, .NOSIGNAL, c.long(1))
	curl.easy_setopt(handle, .CONNECTTIMEOUT, c.long(10))
	curl.easy_setopt(handle, .TIMEOUT, c.long(timeout))
	curl.easy_setopt(handle, .USERAGENT, cstring(AGENT))
	curl.easy_setopt(handle, .ERRORBUFFER, &a.error[0])
	when ODIN_OS == .Windows {
		// Schannel fails outright where a revocation list can't be reached (behind some
		// proxies); nothing of worth comes back from the lobby anyway.
		curl.easy_setopt(handle, .SSL_OPTIONS, c.long(curl.SSLOPT_REVOKE_BEST_EFFORT))
	}
	if http.ca_bundle != nil do curl.easy_setopt(handle, .CAINFO, http.ca_bundle)
	curl.easy_setopt(handle, .CUSTOMREQUEST, method_c)
	headers: ^curl.slist
	if body != "" {
		headers = curl.slist_append(nil, "Content-Type: application/json")
		body_c := strings.clone_to_cstring(body, context.temp_allocator)
		curl.easy_setopt(handle, .HTTPHEADER, headers)
		curl.easy_setopt(handle, .POSTFIELDS, body_c)
		curl.easy_setopt(handle, .POSTFIELDSIZE, c.long(len(body)))
	}
	defer curl.slist_free_all(headers)
	if ipv4 do curl.easy_setopt(handle, .IPRESOLVE, c.long(curl.IPRESOLVE_V4))
	curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(answer_write))
	curl.easy_setopt(handle, .WRITEDATA, &a)
	code := curl.easy_perform(handle)
	status: c.long
	curl.easy_getinfo(handle, .RESPONSE_CODE, &status)
	a.status = int(status)
	if code != .E_OK {
		// curl's error buffer says more than its code's name, when it says anything
		if a.error[0] == 0 do fail(&a, curl.easy_strerror(code))
		return
	}
	a.ok = true
	return
}

// --- a request on a thread of its own ------------------------------------------------

// A request under way on its own thread. `method`, `url` and `body` are the request's
// own copies, alive until request_finish. The thread writes `answer`, then `done`;
// `answer` is read after request_finish has joined it.
Request :: struct {
	method:    string,
	url:       string,
	body:      string,
	ipv4:      bool,
	timeout:   int,
	thread:    ^thread.Thread,
	allocator: runtime.Allocator, // the one the request and its strings came from
	answer:    Answer,
	done:      bool,
}

@(private = "file")
request_run :: proc(r: ^Request) {
	r.answer = http_request(r.method, r.url, r.body, r.ipv4, r.timeout)
	free_all(context.temp_allocator)
	sync.atomic_store_explicit(&r.done, true, .Release)
}

// `method` at `url` with `body`, started on its own thread; nil if no thread could be
// made. The request and its copies of the strings are made with `allocator`.
request_start :: proc(method, url, body: string, ipv4: bool, timeout: int, allocator := context.allocator) -> ^Request {
	r := new(Request, allocator)
	r.allocator = allocator
	r.method = strings.clone(method, allocator)
	r.url = strings.clone(url, allocator)
	r.body = strings.clone(body, allocator)
	r.ipv4 = ipv4
	r.timeout = timeout
	r.thread = thread.create_and_start_with_poly_data(r, request_run)
	if r.thread == nil {
		request_free(r)
		return nil
	}
	return r
}

// Whether the thread has its answer in, without waiting for it.
request_done :: proc(r: ^Request) -> bool {
	return sync.atomic_load_explicit(&r.done, .Acquire)
}

// The thread waited for and its answer given back; the request freed.
request_finish :: proc(r: ^Request) -> (a: Answer) {
	thread.join(r.thread)
	thread.destroy(r.thread)
	a = r.answer
	request_free(r)
	return
}

@(private = "file")
request_free :: proc(r: ^Request) {
	delete(r.method, r.allocator)
	delete(r.url, r.allocator)
	delete(r.body, r.allocator)
	free(r, r.allocator)
}
