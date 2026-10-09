package menu

import "core:strings"

import "../../../core/utils"
import "../online"
import "../ui"

// Join by address: the server's address and its password in one field, as
// host:port/password (as the gather bot gives them), and Connect. While the line joins,
// the button gives it up, and the footer says how it goes: what the line last said, or
// how much of the server's map has come.

Join :: struct {
	connect_asked: bool, // Connect was pressed: what becomes of the line shows beside it
}

NAME_MAX :: 23     // a player's name, as the wire carries it
PASSWORD_MAX :: 31 // a server's password
ADDRESS_MAX :: 63
TARGET_MAX :: ADDRESS_MAX + 1 + PASSWORD_MAX // the two, a slash between

page_join :: proc(menu: ^Menu) {
	k := &menu.kit
	network := &menu.config.network
	full_w := k.w
	k.w = min(full_w, 520) // the fields near their names
	ui.section(k, "SERVER")
	// the config's address and password as one, split again as they are typed
	target := online.target_join(network.server, network.password)
	if typed, changed := ui.field_row(k, "Server", &menu.join, target, TARGET_MAX, "host:port/password"); changed {
		address, password, _ := online.target_split(typed)
		network.server = strings.clone(address, config_allocator(menu))
		network.password = strings.clone(password, config_allocator(menu))
	}
	ui.gap(k, 6)
	if tip_y := k.y; tip_y + 40 < k.bottom {
		tip := "A server's IP or name and its port, then its password after a slash if it asks one, as 192.168.1.20:23073/secret. Ctrl+V pastes."
		ui.text_wrap(k, ui.BODY, tip, k.x + 12, tip_y, k.w - 24, ui.MUTED)
	}

	k.w = full_w
	k.scrolling = false
	bx: f32
	if menu.line.state == .Off {
		pressed: bool
		pressed, bx = big_button(menu, k.x + k.w, "CONNECT", true, false)
		if pressed {
			menu.request = Connect{network.server if network.server != "" else "127.0.0.1"}
			menu.join.connect_asked = true
		}
	} else {
		pressed: bool
		pressed, bx = big_button(menu, k.x + k.w, "CANCEL", false, false)
		if pressed do menu.request = Disconnect{}
	}
	if menu.join.connect_asked do footer_text(menu, k.x, bx - k.x - 12, line_status(menu), ui.MUTED)
}

// How the line is doing, in a line: the map coming, or what it last said.
line_status :: proc(menu: ^Menu) -> string {
	n := menu.line
	if status := online.fetch_status(&n.fetch); status != "" do return status
	return utils.short_string_text(&n.status.text)
}
