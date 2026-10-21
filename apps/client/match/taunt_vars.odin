package match

import sa "core:container/small_array"
import "core:fmt"
import "core:strings"

import sim "../../../core/game"
import res "../../../core/resources"
import "../../../core/utils"
import "../hud"

// A taunt's variables filled in (hud.TAUNT_VARS): {name} by its value as the key says
// it, {{name}} by the value in capitals, each between hud.VAR_OPEN and hud.VAR_CLOSE so
// the console colours it. A name that isn't a variable is left as it is, braces and all.

// `text` with its variables filled in. For this frame.
taunt_fill :: proc(match: ^Match, text: string) -> string {
	if strings.index_byte(text, '{') < 0 do return text
	b := strings.builder_make(context.temp_allocator)
	rest := text
	for rest != "" {
		open := strings.index_byte(rest, '{')
		if open < 0 {
			strings.write_string(&b, rest)
			break
		}
		strings.write_string(&b, rest[:open])
		rest = rest[open:]
		caps := strings.has_prefix(rest, "{{")
		from := 2 if caps else 1
		close := strings.index(rest[from:], "}}" if caps else "}")
		value, known := "", false
		if close >= 0 do value, known = taunt_var(match, rest[from:][:close])
		if !known { // not a variable: its brace as written, and on past it
			strings.write_byte(&b, '{')
			rest = rest[1:]
			continue
		}
		if caps do value = strings.to_upper(value, context.temp_allocator)
		strings.write_rune(&b, hud.VAR_OPEN)
		strings.write_string(&b, value)
		strings.write_rune(&b, hud.VAR_CLOSE)
		rest = rest[from + close + from:]
	}
	return strings.to_string(b)
}

// A variable's value by its name, as it stands now; false if there's none by that name.
@(private = "file")
taunt_var :: proc(match: ^Match, name: string) -> (value: string, known: bool) {
	game := match.game
	world := &game.world
	me := &world.soldiers[match.me]
	team, enemy := taunt_teams(me.team)
	mine, theirs := game.round.captures[team], game.round.captures[enemy]
	switch name {
	case "time_left":
		seconds := max(game.round.time_left, 0) / sim.TICK_RATE
		return fmt.tprintf("%d:%02d", seconds / 60, seconds % 60), true
	case "caps_difference":
		return fmt.tprintf("%+d", mine - theirs) if mine != theirs else "0", true
	case "score":      return fmt.tprintf("%d-%d", mine, theirs), true
	case "team_caps":  return fmt.tprintf("%d", mine), true
	case "enemy_caps": return fmt.tprintf("%d", theirs), true
	case "cap_limit":  return fmt.tprintf("%d", game.settings.capture_limit), true
	case "my_caps":    return fmt.tprintf("%d", me.tally.flags), true
	case "kills":      return fmt.tprintf("%d", me.tally.kills), true
	case "deaths":     return fmt.tprintf("%d", me.tally.deaths), true
	case "kd":
		return fmt.tprintf("%.2f", f32(me.tally.kills) / f32(max(me.tally.deaths, 1))), true
	case "killer":     return named(utils.short_string_text(&match.killer)), true
	case "victim":     return named(utils.short_string_text(&match.victim)), true
	case "health":
		return fmt.tprintf("%d", int(max(me.vitals.health, 0) * 100 / sim.DEFAULT_HEALTH + 0.5)) if !me.vitals.dead else "0", true
	case "weapon":     return game.resources.weapons[me.arsenal.primary.weapon].name, true
	case "name":       return soldier_names(match)[match.me], true
	case "team":       return hud.team_name(team), true
	case "enemy_team": return hud.team_name(enemy), true
	case "map":
		return match.map_name if match.mode == .Offline else utils.short_string_text(&match.line.map_name), true
	case "server":
		if match.mode != .Offline && match.line.hostname.length > 0 do return utils.short_string_text(&match.line.hostname), true
		return "Soldat Reloaded", true
	case "players":
		count := 0
		for &soldier in world.soldiers do count += int(soldier.active)
		return fmt.tprintf("%d", count), true
	case "ping":       return fmt.tprintf("%d", me.player.ping), true
	case "time":       return time_of_day(match.zone), true
	}
	return "", false

	named :: proc(name: string) -> string {
		return name if name != "" else "nobody"
	}
}

// My team and the one against it, for the captures: alpha's view of it when I'm on no
// team's side.
@(private = "file")
taunt_teams :: proc(mine: res.Team) -> (team, enemy: res.Team) {
	#partial switch mine {
	case .Bravo:   return .Bravo, .Alpha
	case .Charlie: return .Charlie, .Delta
	case .Delta:   return .Delta, .Charlie
	}
	return .Alpha, .Bravo
}

// The tick's kills, for {killer} and {victim}: who killed me, whom I killed (not myself).
taunt_kills_seen :: proc(match: ^Match, names: ^[sim.MAX_PLAYERS]string) {
	for ruling in sa.slice(&match.game.output.rulings) {
		kill := ruling.(sim.Kill) or_continue
		if kill.killer == kill.target do continue
		if kill.target == match.me do match.killer = utils.short_string(hud.LINE_TEXT, names[kill.killer])
		if kill.killer == match.me do match.victim = utils.short_string(hud.LINE_TEXT, names[kill.target])
	}
}

// A name kept for {killer} and {victim}: the match's field named hud hides the package
// inside Match.
Name_Text :: hud.Line_Text
