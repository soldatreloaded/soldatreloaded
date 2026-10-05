package menu

import "../ui"

// Join by address: the server's address and its password, and Connect. There is no
// network yet: Connect says so.

Join :: struct {
	connect_asked: bool, // Connect was pressed: the word on it shows beside it
}

NAME_MAX :: 23     // a player's name, as the wire carries it
PASSWORD_MAX :: 31 // a server's password
ADDRESS_MAX :: 63

page_join :: proc(menu: ^Menu) {
	k := &menu.kit
	network := &menu.config.network
	full_w := k.w
	k.w = min(full_w, 520) // the fields near their names
	ui.section(k, "SERVER")
	ui.text_row(k, "Address", &network.server, ADDRESS_MAX, "host:port", config_allocator(menu))
	ui.text_row(k, "Password", &network.password, PASSWORD_MAX, "if the server asks one", config_allocator(menu), secret = true)
	ui.gap(k, 6)
	if tip_y := k.y; tip_y + 40 < k.bottom {
		tip := "A server's address is its IP or name and its port, as 192.168.1.20:23073. Ctrl+V pastes."
		ui.text_wrap(k, ui.BODY, tip, k.x + 12, tip_y, k.w - 24, ui.MUTED)
	}

	k.w = full_w
	k.scrolling = false
	pressed, bx := big_button(menu, k.x + k.w, "CONNECT", true, false)
	if pressed do menu.join.connect_asked = true
	if menu.join.connect_asked do footer_text(menu, k.x, bx - k.x - 12, NOT_YET_ONLINE, ui.MUTED)
}
