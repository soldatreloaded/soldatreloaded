#+build !windows
package online

import "core:os"

// The system's machine-id, where systemd or D-Bus keep it.
machine_id :: proc(allocator := context.allocator) -> (id: string, ok: bool) {
	for path in ([?]string{"/etc/machine-id", "/var/lib/dbus/machine-id"}) {
		data, err := os.read_entire_file(path, allocator)
		if err == nil do return string(data), true
	}
	return
}
