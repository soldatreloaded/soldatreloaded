#+build windows
package menu

import "core:strings"
import win "core:sys/windows"

// Windows' own file dialog (IFileOpenDialog), over `owner`: picking a folder, or with
// `files` a file of those patterns. The path picked, with the context allocator; false if the player
// cancelled it.
pick_path :: proc(title: string, owner: rawptr, files: []string) -> (path: string, ok: bool) {
	win.CoInitializeEx(nil, .APARTMENTTHREADED)
	defer win.CoUninitialize()
	dialog: ^win.IFileOpenDialog
	if win.CoCreateInstance(win.CLSID_FileOpenDialog, nil, win.CLSCTX_INPROC_SERVER, win.IID_IFileOpenDialog, cast(^win.LPVOID)&dialog) < 0 do return
	defer dialog->Release()
	options: win.FILEOPENDIALOGOPTIONS
	dialog->GetOptions(&options)
	if files != nil {
		dialog->SetOptions(options | win.FOS_FILEMUSTEXIST | win.FOS_FORCEFILESYSTEM)
		types := [?]win.COMDLG_FILTERSPEC {
			{win.utf8_to_wstring(strings.join(files, " ", context.temp_allocator), context.temp_allocator), win.utf8_to_wstring(strings.join(files, ";", context.temp_allocator), context.temp_allocator)},
		}
		dialog->SetFileTypes(len(types), &types[0])
	} else {
		dialog->SetOptions(options | win.FOS_PICKFOLDERS | win.FOS_FORCEFILESYSTEM)
	}
	dialog->SetTitle(win.utf8_to_wstring(title, context.temp_allocator))
	if dialog->Show(win.HWND(owner)) < 0 do return // cancelled
	item: ^win.IShellItem
	if dialog->GetResult(&item) < 0 do return
	defer item->Release()
	name: win.LPWSTR
	if item->GetDisplayName(.FILESYSPATH, &name) < 0 do return
	defer win.CoTaskMemFree(name)
	text, err := win.wstring_to_utf8(win.wstring(name), -1)
	if err != nil do return
	return text, true
}
