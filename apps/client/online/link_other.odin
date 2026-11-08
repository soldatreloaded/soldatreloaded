#+build !windows
package online

import "core:os"
import "core:path/filepath"

// The scheme's handler elsewhere (Linux): a desktop entry in the user's applications
// (~/.local/share/applications) that runs this program, from its install, with the link,
// and that entry the scheme's default in the user's mimeapps.list (~/.config), as
// xdg-open and the browsers read them; for this user alone.

// This game made the handler, as it starts. False if it couldn't be, which only means
// links don't open it. On macOS none is made: a URL scheme there is an app bundle's to
// declare, and the game is a plain program.
link_register :: proc() -> bool {
	when ODIN_OS == .Darwin do return false
	exe, err := os.get_executable_path(context.temp_allocator)
	if err != nil do return false
	data, data_err := os.user_data_dir(context.temp_allocator)
	config, config_err := os.user_config_dir(context.temp_allocator)
	if data_err != nil || config_err != nil do return false
	return link_register_in(data, config, exe)
}

// The handler in `data`/applications and `config`/mimeapps.list, for `exe`.
link_register_in :: proc(data, config, exe: string) -> bool {
	apps, _ := filepath.join({data, "applications"}, context.temp_allocator)
	if os.make_directory_all(apps) != nil && !os.is_dir(apps) do return false
	entry, _ := filepath.join({apps, LINK_DESKTOP_FILE}, context.temp_allocator)
	if os.write_entire_file(entry, transmute([]u8)link_desktop_entry(exe, filepath.dir(exe))) != nil do return false
	if os.make_directory_all(config) != nil && !os.is_dir(config) do return false
	list_path, _ := filepath.join({config, "mimeapps.list"}, context.temp_allocator)
	list, _ := os.read_entire_file(list_path, context.temp_allocator) // none yet is empty
	return os.write_entire_file(list_path, transmute([]u8)link_mimeapps(string(list))) == nil
}
