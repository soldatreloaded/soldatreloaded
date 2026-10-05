# Porting the game from C

`core/game` is a port of the C game's simulation (`apps/shared/game` in
[soldatreloaded](../../bettersoldat), at commit `428713d`). It must play **exactly** as
the C game does: the same numbers, bit for bit, tick after tick. It does not keep the C
game's structure: the logic is ported line by line, into the organization described in
`core/game/world.odin`.

It plays capture the flag only, and has less than the C game: no deathmatch, no rope, no
bonus kits (flamer, predator, berserker, vest, cluster), no flamer, bows or stationary
gun, no cluster grenades. What it keeps plays as the C game plays it.

## Checking it: tests/compare

```
tests/compare/build.sh          # the C game at 428713d, built into tests/compare/build/reference.lib
odin run tests/compare          # every scenario, in both games, compared every tick
odin run tests/compare -- jump  # only the scenarios whose name contains "jump"
```

Each scenario is played by both games on the same commands; after every tick both worlds
are probed (`Probe` in `main.odin`, `ref_probe` in `reference.c`) and the first field that
differs is reported, with the tick. A port of a system is done when the scenarios that
exercise it pass. Add scenarios (`scenarios.odin`) for what the existing ones don't reach,
and probe fields (on both sides) for state they don't show.

The scenarios play on ctf maps and leave the C game's extras off, as its defaults have
them. The port numbers what it kept of the C game's weapons, bullet styles, things and
animations in the same order, closed up; `ref_probe` gives the C ids the port's numbers
(`port_id`, with the dropped ids listed once in `reference.c`).

## Where the C code goes

| C | Odin |
|---|---|
| `entities.h` types | `soldier.odin`, `bullet.odin`, `thing.odin`, `corpse.odin`, `weapon.odin` |
| `soldier.c`, `movement.c`, `soldier_collision.c`, `pose.c`, `antics.c`, `combat.c` | `soldier.odin` and files beside it named for what they do: `soldier_movement.odin`, `soldier_collision.odin`, `soldier_pose.odin`, `soldier_antics.odin`, `soldier_combat.odin` |
| `bullet.c`, `bullet_collision.c`, `explosion.c` | `bullet.odin`, `bullet_collision.odin`, `explosion.odin` |
| `thing.c`, `flag.c`, `kit.c`, `dropped_gun.c`, `parachute.c` | `thing.odin`, `flag.odin`, `kit.odin`, `dropped_gun.odin`, `parachute.odin` |
| `ragdoll.c` | `corpse.odin` |
| `weapons.c` | `weapon.odin` |
| `damage.c` | the decision in `referee.odin`; the effect (`soldier_hurt`, `soldier_kill`) in `soldier.odin` |
| `spawn.c` | `spawn.odin` |
| `rand.c` | `rng.odin` (done) |
| `history.c` | `referee.odin` |
| `game.c` (match) | `round.odin` |
| `event.c`, the passes' mail | gone: see below |
| `resources/*`, `utils/*` | `core/resources`, `core/utils` (done) |

## The rules

**Ported line by line.** Same arithmetic in the same order, f32 throughout, the same
calls to the random generators in the same order. `round_half_even` for the C game's
`round_half_even`. Where an expression's order of operations decides the rounding, keep
it. The harness catches what this misses.

**Entities call each other directly.** The C passes talk through events (the mail): a
soldier asks for a shot with `EVENT_SHOT`, and the bullets pass makes it. Here the soldier
calls `bullet_fire`. This keeps the C game's timing as long as the call lands where the
C pass would have consumed the request: a request to a pass still to come this tick is
done when that kind's turn comes this tick, one to a pass already run waits for next
tick. Where a direct call would change the timing, queue it on the entity it is for (a
field on that entity, or on `World`), consumed when that kind updates.

**Decisions are the referee's.** What the C game does only `if (w->authority)` is a
decision, and goes through `referee.odin`:
- Where the C game decides **in place** (in the middle of a pass), call the referee
  **in place**: a `judge_…` procedure taking the `^Authority`, which does nothing when it
  is nil. This keeps the random numbers it rolls in their place in the tick.
- Where the C game decides in a **later pass** (the wounds pass, the things pass's mail),
  the entity emits an event and `judge` decides when that pass would have run, in the
  order that pass would have taken them.
- A decision is carried out by `rule`: recorded as a `Ruling` and applied with
  `apply_ruling`, which calls the entity procedure that does it. Add rulings as needed;
  keep them to what changes health, lives, possession and the score, and what comes and
  goes (a dropped gun laid down, a kit spawned).

**What every machine does stays in the entities.** Knockback, the disturbed aim, physics,
animation: the C game does these with or without authority, and so does the port.

**Events are only for showing.** Shots, impacts, sparks, sounds: what the C game emits
for the client. Nothing in the simulation reads them, except `judge` reading the ones it
decides on.

**Style.** As `core/resources` and the existing `core/game` files: Odin's naming
(`Ada_Case` types, `snake_case` procedures), comments that say what a thing is or why,
in the code's own voice; no comment that only restates the code. Entity procedures are
`<entity>_<verb>`. Fixed-size arrays only, no allocation in a tick. `Maybe(Thing_Id)`
where the C game has "index + 1, 0 for none". `bit_set` for flags. Keep files to one
idea; split a long one by what its parts do.

## The wire and the server

The C game's `apps/shared/network` is `core/network`, and `apps/server` is `apps/server`,
the hosted game and the program around it in one package. They are not compared tick by tick; their
tests are `tests/network`, `tests/server` (real sockets on the loopback, run with
`-define:ODIN_TEST_THREADS=1`), `tests/bots`, `tests/lists`, `tests/lobby` and
`tests/script`.

| C | Odin |
|---|---|
| `network/buffer.c` | `core/network/buffer.odin` |
| `network/netfield.c`, `fields.c` | `core/network/fields.odin`: the tables are read from the `net` tags on `Soldier` and `Thing` |
| `network/message.c`, `network.h` | `core/network/message.odin` |
| `network/wire.c` | `core/network/wire.odin`: the words are `game.Word` (`core/game/word.odin`) |
| `network/stream.c` | `core/network/stream.odin`, `stream_server.odin`, `stream_client.odin` |
| `network/transport.c`, `query.c` | `core/network/transport.odin`, `query.odin` |
| `server/host.c`, `connections.c`, `rounds.c` | `apps/server/`, one package with the executable, one file to an idea: `server.odin`, `players.odin`, `line.odin`, `chat.odin`, `votes.odin`, `admin.odin`, `flood.odin`, `rounds.odin`, `maps.odin` |
| `server/bots.c`, `lists.c`, `lobby.c`, `script.c` | `core/bots`, `apps/server/lists`, `apps/server/lobby`: packages of their own, which know nothing of the line; the script is the server package's own (`apps/server/script.odin`, `api.odin`, `events.odin`) |
| `server/main.c`, `host_cvars.c`, `stdin_reader.c` | `apps/server/main.odin`, `console.odin`: the console is a handful of commands over `server.config.json` (`core/resources/server_config.odin`), not cvars |
| `server/weapons_ini.c` | `core/resources/weapons.odin`: a server's weapons are `server.config.json`'s `weapons`, and the console's `weapon` changes them as it runs |

**Word from another machine.** What the C game's passes heard through the mailbox
(`game_hear`) is a `game.Word` given to `world_hear`, done at the turn the C pass would
have taken it (`heard_apply` in `world_step`). An owner's decisions leave the tick as
events (`Shot_Fired`, `Gun_Thrown`, `Flag_Thrown`), which the wire collects; the
server's decisions are its rulings.
