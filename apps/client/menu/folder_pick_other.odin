#+build !windows
package menu

import "core:os"
import "core:strings"

// The desktop's own file dialog: zenity's (GNOME and most others), else kdialog's (KDE);
// macOS's, through osascript. Picking a folder, or with `files` a file of those patterns. The path
// picked, with the context allocator; false if the player cancelled it, or there is no
// dialog to show.
pick_path :: proc(title: string, owner: rawptr, files: []string) -> (path: string, ok: bool) {

	spaced := strings.join(files, " ", context.temp_allocator)
	folders := [?][]string {
		{"zenity", "--file-selection", "--directory", strings.concatenate({"--title=", title}, context.temp_allocator)},
		{"kdialog", "--getexistingdirectory", ".", "--title", title},
		{"osascript", "-e", strings.concatenate({`POSIX path of (choose folder with prompt "`, title, `")`}, context.temp_allocator)},
	}
	file_commands := [?][]string {
		{"zenity", "--file-selection", strings.concatenate({"--title=", title}, context.temp_allocator), strings.concatenate({"--file-filter=", spaced, " | ", spaced}, context.temp_allocator)},
		{"kdialog", "--getopenfilename", ".", spaced, "--title", title},
		{"osascript", "-e", strings.concatenate({`POSIX path of (choose file with prompt "`, title, `")`}, context.temp_allocator)},
	}
	for command in (file_commands[:] if files != nil else folders[:]) {
		state, stdout, _, err := os.process_exec({command = command}, context.temp_allocator)
		if err != nil do continue // not here: the next
		if !state.success do return // cancelled
		picked := strings.trim_space(string(stdout))
		if picked == "" do return
		return strings.clone(picked), true
	}
	return
}
