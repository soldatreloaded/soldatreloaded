package server

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:thread"

import curl "vendor:curl"
import lua "vendor:lua/5.4"

import "../../core/http"

// `http`: a request made by the script runs on a thread of its own, through libcurl
// (started and made to trust what it should by core/http), so the game never waits on
// the web; its answer is handed to the script's callback from script_pump, on the
// server's thread.
//
//   http.request{url=, method=, body=, headers={}, timeout=}, callback(response)
//
// The response: {status=, body=, error=}; status 0 with an error when nothing came back.
// http.get and http.post are Lua, over request.

HTTP_RESPONSE_MAX :: 4 * 1024 * 1024 // past this an answer is cut
HTTP_DEFAULT_TIMEOUT :: 15           // seconds
HTTP_AGENT :: "soldatreloaded-server"

// A request under way. What it asks is its own, made before the thread starts; what
// came back is written by the thread, and read once `done`. All of it is on the heap,
// which the thread allocates from too.
Http_Job :: struct {
	url:      cstring,
	method:   cstring,
	body:     []u8,
	headers:  ^curl.slist,
	timeout:  int,
	callback: c.int, // a reference in the registry, or lua.NOREF
	thread:   ^thread.Thread,
	status:   int,
	response: [dynamic]u8,
	error:    [curl.ERROR_SIZE]u8, // NUL-terminated, in curl's words
	done:     bool,
}

@(private = "file")
http_lua := [?]lua.L_Reg{{"request", l_http_request}, {nil, nil}}

// The `http` global; http.get and http.post come with the prelude.
http_open :: proc(L: ^lua.State) {
	http.start()
	lua.createtable(L, 0, len(http_lua) - 1)
	lua.L_setfuncs(L, &http_lua[0], 0)
	lua.setglobal(L, "http")
}

// The rest of http, in Lua: get and post over request; a table given as post's body is
// sent as JSON.
HTTP_PRELUDE :: `
function http.get(url, callback, headers)
  return http.request({url = url, method = 'GET', headers = headers}, callback)
end
function http.post(url, body, content_type, callback)
  if type(body) == 'table' then body = json.encode(body); content_type = content_type or 'application/json' end
  return http.request({url = url, method = 'POST', body = body,
    headers = {['Content-Type'] = content_type or 'text/plain'}}, callback)
end
`

// http.request(request, callback): the request read, and its thread started. Everything
// it asks is read before anything is made, as a bad argument raises a Lua error, which
// leaves this function at once.
@(private = "file")
l_http_request :: proc "c" (L: ^lua.State) -> c.int {
	s := script_of(L)
	context = s.ctx
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	lua.settop(L, 2)
	lua.getfield(L, 1, "url")     // 3
	lua.getfield(L, 1, "method")  // 4
	lua.getfield(L, 1, "body")    // 5
	lua.getfield(L, 1, "timeout") // 6
	lua.getfield(L, 1, "headers") // 7
	url := to_string(L, 3)
	if url == "" do return c.int(lua.L_error(L, "http.request needs a url"))
	method := opt_string(L, 4, "GET")
	has_body := !lua.isnoneornil(L, 5)
	body := check_string(L, 5) if has_body else ""
	if has_body && method == "GET" do method = "POST"
	timeout := HTTP_DEFAULT_TIMEOUT
	if !lua.isnoneornil(L, 6) do timeout = clamp(int(lua.L_checknumber(L, 6)), 1, 300)

	heap := runtime.heap_allocator()
	job := new(Http_Job, heap)
	job.url = strings.clone_to_cstring(url, heap)
	job.method = strings.clone_to_cstring(method, heap)
	job.body = transmute([]u8)strings.clone(body, heap) if has_body else nil
	job.timeout = timeout
	job.callback = lua.NOREF
	if lua.istable(L, 7) {
		lua.pushnil(L)
		for lua.next(L, 7) != 0 {
			lua.pushvalue(L, -2) // the key as a string, without turning the one next() walks
			line := fmt.ctprintf("%s: %s", to_string(L, -1), to_string(L, -2))
			job.headers = curl.slist_append(job.headers, line)
			lua.pop(L, 2)
		}
	}
	if lua.isfunction(L, 2) {
		lua.pushvalue(L, 2)
		job.callback = lua.L_ref(L, lua.REGISTRYINDEX)
	}
	job.thread = thread.create_and_start_with_poly_data(job, http_run)
	if job.thread == nil {
		http_free(L, job)
		return c.int(lua.L_error(L, "the request's thread would not start"))
	}
	append(&s.jobs, job)
	return 0
}

// On the request's thread: the request made, and waited for.
@(private = "file")
http_run :: proc(job: ^Http_Job) {
	context.allocator = runtime.heap_allocator()
	status: c.long
	handle := curl.easy_init()
	if handle == nil {
		copy(job.error[:len(job.error) - 1], "curl could not start")
	} else {
		job.response = make([dynamic]u8)
		curl.easy_setopt(handle, .URL, job.url)
		curl.easy_setopt(handle, .CUSTOMREQUEST, job.method)
		if job.body != nil {
			curl.easy_setopt(handle, .POSTFIELDS, raw_data(job.body))
			curl.easy_setopt(handle, .POSTFIELDSIZE, c.long(len(job.body)))
		}
		if job.headers != nil do curl.easy_setopt(handle, .HTTPHEADER, job.headers)
		curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(http_write))
		curl.easy_setopt(handle, .WRITEDATA, job)
		curl.easy_setopt(handle, .TIMEOUT, c.long(job.timeout))
		curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
		curl.easy_setopt(handle, .MAXREDIRS, c.long(5))
		curl.easy_setopt(handle, .NOSIGNAL, c.long(1))
		curl.easy_setopt(handle, .USERAGENT, cstring(HTTP_AGENT))
		curl.easy_setopt(handle, .ERRORBUFFER, &job.error[0])
		http.secure(handle)
		code := curl.easy_perform(handle)
		if code == .E_OK {
			curl.easy_getinfo(handle, .RESPONSE_CODE, &status)
		} else if job.error[0] == 0 { // curl's buffer says more than its code's name, when it says anything
			copy(job.error[:len(job.error) - 1], string(curl.easy_strerror(code)))
		}
		curl.easy_cleanup(handle)
	}
	job.status = int(status)
	free_all(context.temp_allocator)
	sync.atomic_store_explicit(&job.done, true, .Release)
}

// What came back, kept as far as HTTP_RESPONSE_MAX: cut past it, but not failed.
@(private = "file")
http_write :: proc "c" (data: [^]byte, size: c.size_t, n: c.size_t, user: rawptr) -> c.size_t {
	context = runtime.default_context()
	job := (^Http_Job)(user)
	given := int(size * n)
	take := min(given, HTTP_RESPONSE_MAX - len(job.response))
	if take > 0 do append(&job.response, ..data[:take])
	return c.size_t(given)
}

// Whether the request's thread has its answer in, without waiting for it.
http_done :: proc(job: ^Http_Job) -> bool {
	return sync.atomic_load_explicit(&job.done, .Acquire)
}

// A finished request's answer to its callback, if it has one; the request freed.
http_answer :: proc(s: ^Script, job: ^Http_Job) {
	thread.join(job.thread)
	if job.callback != lua.NOREF {
		L := s.L
		lua.pushcfunction(L, traceback)
		base := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(job.callback))
		lua.createtable(L, 0, 3)
		lua.pushinteger(L, lua.Integer(job.status))
		lua.setfield(L, -2, "status")
		push_string(L, string(job.response[:]))
		lua.setfield(L, -2, "body")
		if job.error[0] != 0 {
			push_string(L, string(cstring(&job.error[0])))
			lua.setfield(L, -2, "error")
		}
		if lua.pcall(L, 1, 0, base) != c.int(lua.OK) do complain(s, "http callback: %s", to_string(L, -1))
		lua.settop(L, base - 1)
	}
	http_free(s.L, job)
}

// A request still out as the script ends: waited for, its answer dropped.
http_drop :: proc(L: ^lua.State, job: ^Http_Job) {
	thread.join(job.thread)
	http_free(L, job)
}

@(private = "file")
http_free :: proc(L: ^lua.State, job: ^Http_Job) {
	heap := runtime.heap_allocator()
	if L != nil && job.callback != lua.NOREF do lua.L_unref(L, lua.REGISTRYINDEX, job.callback)
	if job.thread != nil do thread.destroy(job.thread)
	curl.slist_free_all(job.headers)
	delete(job.url, heap)
	delete(job.method, heap)
	delete(job.body, heap)
	delete(job.response)
	free(job, heap)
}
