#+build windows
package online

import "core:fmt"
import win "core:sys/windows"

// The pipe to the Discord app, on Windows: a named pipe, opened, written whole, read
// without waiting, closed.

Discord_Pipe :: struct {
	handle: win.HANDLE, // nil while closed
}

@(private = "file")
PIPES :: 10 // discord-ipc-0 to 9: one per Discord app running, the first that answers

pipe_open :: proc(p: ^Discord_Pipe) -> bool {
	for i in 0 ..< PIPES {
		name := win.utf8_to_wstring(fmt.tprintf(`\\.\pipe\discord-ipc-%d`, i), context.temp_allocator)
		h := win.CreateFileW(name, win.GENERIC_READ | win.GENERIC_WRITE, 0, nil, win.OPEN_EXISTING, 0, nil)
		if h != win.INVALID_HANDLE_VALUE {
			p.handle = h
			return true
		}
	}
	return false
}

pipe_is_open :: proc(p: ^Discord_Pipe) -> bool {
	return p.handle != nil
}

pipe_close :: proc(p: ^Discord_Pipe) {
	if p.handle != nil do win.CloseHandle(p.handle)
	p.handle = nil
}

pipe_write :: proc(p: ^Discord_Pipe, data: []u8) -> bool {
	wrote: win.DWORD
	return bool(win.WriteFile(p.handle, raw_data(data), win.DWORD(len(data)), &wrote, nil)) && int(wrote) == len(data)
}

// Bytes read into `out`, 0 for none waiting, -1 for the pipe gone.
pipe_read :: proc(p: ^Discord_Pipe, out: []u8) -> int {
	waiting: u32
	if !win.PeekNamedPipe(p.handle, nil, 0, nil, &waiting, nil) do return -1
	if waiting == 0 do return 0
	got: win.DWORD
	if !win.ReadFile(p.handle, raw_data(out), win.DWORD(min(int(waiting), len(out))), &got, nil) do return -1
	return int(got)
}

process_id :: proc() -> int {
	return int(win.GetCurrentProcessId())
}
