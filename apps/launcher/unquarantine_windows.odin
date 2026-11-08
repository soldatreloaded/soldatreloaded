#+build windows
package launcher

// Windows marks a downloaded file too (the Zone.Identifier stream), but opens a program
// so marked after one warning, and the launcher's files are its own: nothing to take off.
unquarantine :: proc(path: string) {
	_ = path
}
