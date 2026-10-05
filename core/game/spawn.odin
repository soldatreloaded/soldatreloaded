package game

import res "../resources"
import "../utils"

// Where a soldier of a team is placed: one of the team's spawn points, picked at random,
// else one of the general ones. The origin when the map has neither.
spawn_point :: proc(polymap: ^res.Poly_Map, team: res.Team, rng: ^Rng) -> utils.Vec2 {
	want := res.Spawn_Kind(team) // a team's spawn points are numbered as the team
	for _ in 0 ..< 2 {
		count := 0
		for spawnpoint in polymap.spawnpoints {
			if spawnpoint.active && spawnpoint.kind == want do count += 1
		}
		if count > 0 {
			pick := rng_below(rng, count)
			for spawnpoint in polymap.spawnpoints {
				if !(spawnpoint.active && spawnpoint.kind == want) do continue
				if pick == 0 do return spawnpoint.pos
				pick -= 1
			}
		}
		want = .General
	}
	return {}
}
