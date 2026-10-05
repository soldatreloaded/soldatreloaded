package hud

import sa "core:container/small_array"
import "core:math"

import rl "vendor:raylib"

import res "../../../core/resources"
import "../ui"

// The in-game menus: escape, team and weapons, the original's GameMenus. Each is a set of
// buttons in the view's units; the cursor is over one, and a click or its number key
// chooses it. What a choice means is handed back as a Menu_Action for the match to carry
// out: nothing here touches the game, and nothing draws (draw_menus.odin). From the C
// client's ui/menus.c.
//
// The escape menu's map and kick windows are online's, as is the team menu's spectating:
// their buttons are in the tables, never shown offline. The windows, when they come, are
// menus of their own here, opened by the escape menu's buttons.

Menu :: enum {
	Escape,
	Team,
	Weapons,
}

Menus :: struct {
	open:         bit_set[Menu],
	weapons_back: bool,   // the weapons menu was open as the escape menu opened, and comes back as it closes
	cursor:       [2]f32, // where the game's cursor is, in units
	width:        f32,    // the view's width, in units
}

// What a choice asks of the match. Nil when nothing was chosen.
Menu_Action :: union {
	Leave,
	Pick_Primary,
	Pick_Secondary,
	Pick_Team,
	Menu_Changed,
}

// Back to the main menu.
Leave :: struct {}

// The weapons for my next spawn; now, if I haven't moved since my last.
Pick_Primary :: struct {
	weapon: res.Weapon,
}

Pick_Secondary :: struct {
	weapon: res.Weapon,
}

Pick_Team :: struct {
	team: res.Team,
}

// A menu opened or closed, and nothing more: the click is used up.
Menu_Changed :: struct {}

// The escape menu's choices, by their number keys from 1.
Escape_Choice :: enum {
	Leave,
	Change_Map, // online: the map window
	Kick,       // online: the kick window
	Change_Team,
}

ESCAPE_SIZE :: [2]f32{300, 200}
PRIMARIES :: 10 // the weapons menu's first buttons; the secondaries follow
SECONDARIES :: 4

// A button where it is, and whether it is offered.
Button :: struct {
	rect:  rl.Rectangle,
	shown: bool,
}

Buttons :: sa.Small_Array(16, Button)

menus_any_open :: proc(menus: ^Menus) -> bool {
	return menus.open != {}
}

// Opens or closes a menu, as the original does: the escape menu hides the rest and
// brings the weapons menu back as it closes; the team menu hides the rest.
menus_show :: proc(menus: ^Menus, menu: Menu, show: bool) {
	switch menu {
	case .Escape:
		if show && .Weapons in menus.open do menus.weapons_back = true
		menus.open = {.Escape} if show else {}
		if !show && menus.weapons_back do menus.open += {.Weapons}
	case .Team:
		menus.open = {.Team} if show else menus.open - {.Team}
	case .Weapons:
		if show {
			menus.open += {.Weapons}
		} else {
			menus.open -= {.Weapons}
			menus.weapons_back = false
		}
	}
}

menus_close_all :: proc(menus: ^Menus) {
	menus.open = {}
	menus.weapons_back = false
}

// Where a menu's buttons are, and which are offered; by their index, which is what each
// menu's choices go by: the Escape_Choice, the team less one, the weapon less one.
menu_buttons :: proc(menus: ^Menus, menu: Menu) -> (buttons: Buttons) {
	switch menu {
	case .Escape:
		// each in its own row from the second, where the original has it, offered or not
		box := menu_box(menus, .Escape)
		for choice in Escape_Choice {
			row := f32(choice) + 1
			sa.append(&buttons, Button{{box.x + 5, box.y + 25 * row, 240, 25}, escape_offered(choice)})
		}
	case .Team:
		for team in res.Team.Alpha ..= res.Team.Spectator {
			sa.append(&buttons, Button{{40, 140 + 40 * f32(team), 215, 35}, team_offered(team)})
		}
	case .Weapons:
		for i in 0 ..< PRIMARIES + SECONDARIES {
			row := f32(i + 1 if i >= PRIMARIES else i) // a row's gap before the secondaries
			sa.append(&buttons, Button{{35, 154 + 18 * row, 235, 16}, true})
		}
	}
	return
}

// The box a menu is drawn in.
menu_box :: proc(menus: ^Menus, menu: Menu) -> rl.Rectangle {
	switch menu {
	case .Escape:  return {math.round((menus.width - ESCAPE_SIZE.x) / 2), math.round((ui.VIEW_HEIGHT - ESCAPE_SIZE.y) / 2), ESCAPE_SIZE.x, ESCAPE_SIZE.y}
	case .Team:    return {45, 140, 262, 250}
	case .Weapons: return {45, 140, 252, 210}
	}
	return {}
}

// The open menu's button the cursor is on, if any.
menus_hovered :: proc(menus: ^Menus) -> (menu: Menu, button: int, ok: bool) {
	for m in menus.open {
		buttons := menu_buttons(menus, m)
		for b, i in sa.slice(&buttons) {
			r := b.rect
			c := menus.cursor
			if b.shown && c.x > r.x && c.x < r.x + r.width && c.y > r.y && c.y < r.y + r.height do return m, i, true
		}
	}
	return
}

// A click where the cursor is. Beside the weapons menu, with a weapon already `chosen`,
// it closes the menu, as the original lets a player who left it open get on.
menus_click :: proc(menus: ^Menus, chosen: bool) -> Menu_Action {
	if menu, button, ok := menus_hovered(menus); ok do return choose(menus, menu, button)
	if chosen && .Weapons in menus.open {
		menus_show(menus, .Weapons, false)
		return Menu_Changed{}
	}
	return nil
}

// A number key: the weapons menu's primaries 1 to 0 (with Ctrl, its secondaries 1 to
// 4), the team menu's teams, the escape menu's choices.
menus_number_key :: proc(menus: ^Menus, digit: int, ctrl: bool) -> Menu_Action {
	switch {
	case .Weapons in menus.open:
		if ctrl do return choose(menus, .Weapons, PRIMARIES + digit - 1) if digit >= 1 && digit <= SECONDARIES else nil
		return choose(menus, .Weapons, 9 if digit == 0 else digit - 1)
	case .Team in menus.open:
		return choose(menus, .Team, digit - 1)
	case .Escape in menus.open:
		return choose(menus, .Escape, digit - 1)
	}
	return nil
}

// What a button does: the original's GameMenuAction.
@(private = "file")
choose :: proc(menus: ^Menus, menu: Menu, button: int) -> Menu_Action {
	buttons := menu_buttons(menus, menu)
	if button < 0 || button >= sa.len(buttons) || !sa.get(buttons, button).shown do return nil
	switch menu {
	case .Escape:
		switch Escape_Choice(button) {
		case .Leave:
			menus_close_all(menus)
			return Leave{}
		case .Change_Team:
			menus_show(menus, .Team, true)
			return Menu_Changed{}
		case .Change_Map, .Kick:
		}
	case .Team:
		menus_show(menus, .Team, false)
		return Pick_Team{res.Team(button + 1)}
	case .Weapons:
		weapon := res.Weapon(button + 1)
		if button >= PRIMARIES do return Pick_Secondary{weapon}
		menus_show(menus, .Weapons, false)
		return Pick_Primary{weapon}
	}
	return nil
}

// Offline the escape menu offers leaving and changing team.
@(private = "file")
escape_offered :: proc(choice: Escape_Choice) -> bool {
	switch choice {
	case .Leave, .Change_Team: return true
	case .Change_Map, .Kick:   return false
	}
	return false
}

// Alpha and bravo: charlie and delta are a four-team game's, spectating online's.
@(private = "file")
team_offered :: proc(team: res.Team) -> bool {
	return team == .Alpha || team == .Bravo
}
