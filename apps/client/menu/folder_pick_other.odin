#+build !windows
package menu

import "core:os"
import "core:strings"

// The desktop's own folder dialog: zenity's (GNOME and most others), else kdialog's
// (KDE); macOS's, through osascript. The folder picked, with the context allocator; false
// if the player cancelled it, or there is no dialog to show.
pick_folder :: proc(title: string, owner: rawptr) -> (path: string, ok: bool) {
	commands := [?][]string {
		{"zenity", "--file-selection", "--directory", strings.concatenate({"--title=", title}, context.temp_allocator)},
		{"kdialog", "--getexistingdirectory", ".", "--title", title},
		{"osascript", "-e", strings.concatenate({`POSIX path of (choose folder with prompt "`, title, `")`}, context.temp_allocator)},
	}
	for command in commands {
		state, stdout, _, err := os.process_exec({command = command}, context.temp_allocator)
		if err != nil do continue // not here: the next
		if !state.success do return // cancelled
		picked := strings.trim_space(string(stdout))
		if picked == "" do return
		return strings.clone(picked), true
	}
	return
}
