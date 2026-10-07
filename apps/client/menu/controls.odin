package menu

import "../ui"

// The keys: what each control does and the key that does it, by what it is for, in two
// columns where there is room. A click on a row, or Enter, waits for the next key.
// Under them, the flag thrown the old way, by jump and crouch together, and how the
// radio sits with the weapons menu.

@(private = "file")
Control :: struct {
	label, command: string,
}

@(private = "file", rodata)
CONTROLS := [?]Control {
	{"Left", "+left"}, {"Right", "+right"}, {"Jump", "+jump"}, {"Crouch", "+crouch"},
	{"Prone", "+prone"}, {"Jet", "+jet"}, {"Fire", "+fire"}, {"Throw grenade", "+throw"},
	{"Reload", "+reload"}, {"Change weapon", "+change"}, {"Throw weapon", "+drop"}, {"Throw flag", "+flagthrow"},
	{"Chat", "chat"}, {"Team chat", "teamchat"}, {"Command", "cmd"},
	{"Radio", "+radio"}, {"Weapons menu", "weaponsmenu"}, {"Team menu", "teammenu"}, {"Scoreboard", "fragsmenu"},
	{"Weapon stats", "statsmenu"}, {"Minimap", "toggle ui_minimap"},
}

// The groups, as runs of CONTROLS, and the column each goes in.
@(private = "file")
Control_Group :: struct {
	title:        string,
	first, count: int,
	column:       int,
}

@(private = "file", rodata)
CONTROL_GROUPS := [?]Control_Group {
	{"MOVEMENT", 0, 6, 0},
	{"COMBAT", 6, 6, 0},
	{"TALK", 12, 4, 1},
	{"MENUS", 16, 5, 1},
}

page_controls :: proc(menu: ^Menu) {
	k := &menu.kit
	x, w, top_y := k.x, k.w, k.y
	two := w >= 400
	col_w := (w - 20) / 2 if two else w
	ends := [2]f32{top_y, top_y}
	for group in CONTROL_GROUPS {
		column := group.column if two else 0
		k.x = x + f32(column) * (col_w + 20)
		k.w = col_w
		k.y = ends[column]
		ui.section(k, group.title)
		for i in group.first ..< group.first + group.count {
			control := CONTROLS[i]
			if key, rebound := ui.key_row(k, control.label, i, key_of(menu.config, control.command)); rebound {
				rebind(menu, key, control.command)
			}
		}
		ui.gap(k, 6)
		ends[column] = k.y
	}
	k.x, k.w = x, w
	k.y = max(ends[0], ends[1])
	ui.gap(k, 6)
	ui.toggle(k, "Legacy flag throw", &menu.config.controls.legacy_flag_throw) // jump and crouch together throw the flag
	ui.toggle(k, "Prioritize weapons menu over radio", &menu.config.radio.weapons_first) // both open, the number keys pick a weapon
	ui.toggle(k, "Auto close radio when weapons menu opens", &menu.config.radio.close_on_weapons)
}
