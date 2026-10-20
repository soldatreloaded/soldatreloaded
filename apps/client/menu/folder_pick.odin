package menu

import "core:sync"
import "core:thread"

// A folder, or a mod's file, asked of the player in the system's own dialog (pick_path,
// by platform), on a thread of its own, so the game draws on while the dialog is up.
// Started, then taken once it is done.
Folder_Pick :: struct {
	thread: ^thread.Thread,
	title:  string,
	owner:  rawptr, // the game's window, the dialog's owner: so it comes up over it
	file:   bool,   // a mod's file (MOD_FILE_PATTERNS), not a folder
	done:   bool,   // atomic: the dialog is closed, and `path` may be read
	path:   string, // the folder or file picked; "" if none was
}

// The files a mod comes in, as the file dialog offers them.
MOD_FILE_PATTERNS :: [?]string{"*.zip", "*.srmod", "*.smod"}

// The dialog up, titled `title`, over the window `owner`: for a folder, or with `file` a
// mod's file. Nothing if one is up already.
folder_pick_start :: proc(pick: ^Folder_Pick, title: string, owner: rawptr, file := false) {
	if pick.thread != nil do return
	pick.title, pick.owner, pick.file, pick.path = title, owner, file, ""
	sync.atomic_store(&pick.done, false)
	pick.thread = thread.create_and_start_with_data(pick, proc(data: rawptr) {
		p := (^Folder_Pick)(data)
		p.path, _ = pick_path(p.title, p.owner, p.file)
		sync.atomic_store(&p.done, true)
	})
}

// Whether the dialog is up.
folder_pick_busy :: proc(pick: ^Folder_Pick) -> bool {
	return pick.thread != nil
}

// The folder or file picked, once the dialog is closed: `taken`, and "" if none was. The
// path is the context allocator's: the caller takes it.
folder_pick_take :: proc(pick: ^Folder_Pick) -> (path: string, taken: bool) {
	if pick.thread == nil || !sync.atomic_load(&pick.done) do return
	thread.destroy(pick.thread)
	pick.thread = nil
	return pick.path, true
}
