# Design

How the code is laid out, and the few rules that hold it together. Each subject that
needs more has its own document beside this one:

- [netcode.md](netcode.md): the model, the two streams, time, and what the server checks.
- [porting.md](porting.md): how the simulation is ported from the C game, and checked
  against it tick by tick.
- [scripting.md](scripting.md): the server's Lua API.
- [git.md](git.md): commits, branches and releases.

The code's own comments are the reference for each package: every package opens with
what it is and which file does what.

## The layers

```
apps/server    ─► core/network, core/bots, core/http
apps/client    ─► core/network, core/bots, core/http
apps/launcher  ─► core/http, core/resources

core/network   ─► core/game
core/http      ─► (curl)
core/bots      ─► core/game
core/game      ─► core/resources ─► core/utils
```

A package imports only those beneath it. Nothing in `core/` opens a window, plays a
sound or knows which program it is in; only `core/network` and `core/http` reach the
network.

| Package | What it is |
|---|---|
| `core/utils` | Files, geometry, colours, fixed-size strings: what everything needs and nothing owns. |
| `core/resources` | Everything read from disk, and nothing that plays: the configs, maps, animations, skeletons, weapons' numbers, bot profiles, mods, images, sounds and release manifests. It knows no `game` type. |
| `core/game` | The simulation: one world, stepped a tick at a time, the same on every machine. |
| `core/network` | The wire: messages, the two delta-compressed streams, the transport over ENet. |
| `core/bots` | Soldiers the game plays itself, the original's AI ported as it stands. |
| `core/http` | HTTPS through curl, started once and made to trust what it should, for the server's lobby and scripts and the launcher. |
| `apps/server` | The hosted game and the dedicated server around it, one package, with the `lists` and `lobby` packages beneath it. |
| `apps/client` | The game a player runs: a screen at a time, each screen and system a package of its own. |
| `apps/launcher` | What a player starts: it brings the install up to the newest release, then starts the game. |

## The install

Every program runs from the install's root, which is `assets/` in this repository and
the unpacked folder in a release:

```
data/        what the game plays by: maps, animations, skeletons, objects, bots
mods/        what it looks and sounds like: classic/, the game's own, and the player's beside it
scripts/     the server's Lua
*.config.mjson  the configs, made with their defaults where they are missing
weapons.ini     the server's weapons' numbers, as Soldat's are, made commented out where missing
manifest.json   the release the install was last brought up to, which the launcher keeps
```

**`data/` is the same for everyone in a game.** The soldiers' movement is driven by the
animations and the maps decide what is solid, so a difference here is a different game.
A server and its clients must agree on it.

**`mods/` is each player's own.** `mods/classic/` is the game's look and sound, which
ships with it and is kept by the launcher. Beside it, a player's own mods, each a folder
of `mods/`, which no update touches. A player picks one (the client config's
`graphics.mod`, on the Mods page), and each file is looked for in it first and in
Classic after, so a mod holds only what it changes: a mod can be one sound. Mods are
laid out as OpenSoldat's are, so one of theirs works as it is: its `mod.ini` says how big
its images are in the world and where the soldier's parts are pinned, and its
`txt/font.ini` what the HUD is written in.

**The configs are MJSON, and the struct is the file.** `client.config.mjson` and
`server.config.mjson` are `Client_Config` and `Server_Config`: each field a key, read over
the defaults, so a key the file lacks keeps its default and a file that isn't there is
made whole. MJSON is JSON as a person writes it: no braces around the whole, no commas,
keys bare, and comments. Each setting's comment in the file is its field's `jsoncomment`
tag, so the comment lives beside the field and the file explains itself; the file is
written whole from the struct, so a player's own comment doesn't last. A config of before,
`*.config.json`, is read once where the MJSON isn't there. A server keeps how it hosts,
the rotation, the bots, the admins, bans and mutes in its config, and its weapons'
numbers in `weapons.ini` beside it, as Soldat's has them, so a weapons mod made for
Soldat or OpenSoldat stands as it is. `assets/server.config.mjson` and `assets/weapons.ini`
are the files the server makes with its defaults (`tests/configs` keeps them so). Bot
profiles (`data/bots/*.json`) are read by the same code (`core/resources/config.odin`).
Colours are `"RRGGBB"`, enums their names in lower case.

## The simulation

`core/game` is a port of the C game's simulation, and must play exactly as it does, bit
for bit (porting.md). It is built from four ideas (`core/game/world.odin`):

- **World**: everything that is: soldiers, bullets, things, corpses.
- **Entities**: each a struct and what it does, a file each.
- **Events**: what happened in a step: shots, hits, touches, sparks.
- **Rulings**: what was decided because of it: damage, kills, pickups, captures.

`world_step` moves every entity, and they tell what happened as events. The machine with
**authority** judges the events into rulings (`referee.odin`), and `apply_ruling` carries
them out: the only place health, lives and possession change. A machine without
authority steps the same world and applies the rulings it is sent. The round
(`round.odin`) is the clock and the scores around it.

The rules that make this work:

- **Deterministic.** f32 arithmetic, randomness only from the world's and the soldiers'
  own generators, no globals and no I/O in a step.
- **No allocation in a step.** Every collection is a fixed-size array; a `World` is a
  plain value, and copying it snapshots it.
- **Events are only for showing.** The client draws and plays them; nothing in the
  simulation reads them except the referee deciding on them.

It plays capture the flag, and nothing else.

## One game, many hosts

A `game.Game` is the world, the round around it and, where this machine decides, the
authority. Who holds it is what makes each program what it is:

- **A server** has authority. Its players' commands come over the line, its bots'
  commands from `core/bots`, and it sends everyone the snapshots and its rulings.
- **The client offline** (Offline Play) has authority itself, and plays against bots on
  its own settings (the client config's `offline`): the game and the bots, no server.
- **The client online** has none: it steps the same world from the server's word.
  See netcode.md for how a player's own soldier is never corrected.
- **The tests and tools** have authority, and drive the world directly.

Bots are a source of commands like any client: they read the world as a client would,
and whoever hosts does with their commands what it does with a player's.

## The server

`apps/server` is one package: the hosted game (`server.odin`, with players, rounds,
votes, chat, flood control and the admin commands each in a file of their own), the Lua
script (`script.odin`, `api.odin`, `events.odin`), and the program around them
(`main.odin`, `console.odin`). `server_pump` is the whole of a tick. Its two subpackages
know nothing of it: `lists` keeps the bans, mutes and admins, and `lobby` lists the
server with the server browser.

The script hears the server through `Hooks` and acts on it through the server's own
procedures; scripting.md is its reference.

## The client

`apps/client/main.odin` is a loop over one screen at a time, the main menu or a match,
with what outlives the screens (the window, the configs, the sound, the line to a server
and the server browser's list) kept around them.
Each part is a package:

| Package | What it does |
|---|---|
| `menu` | The main menu: an immediate-mode UI that edits the configs in place and asks for a game, a server or a demo. |
| `match` | Being in a game, offline, online or a demo: builds my command each tick, steps the world, and hands what happened to the rest; the chat, the votes, the radio and watching. |
| `draw` | The world, drawn. Reads the world and never changes it; sprites are packed into atlases so a frame changes texture a handful of times. |
| `hud` | What is drawn over the world, from a plain `Hud_Data` the match builds each frame. |
| `sound` | The game's sounds, placed from where the camera listens, driven by the tick's events. |
| `input` | Keys and mouse made into a command through the player's binds. |
| `ui` | Fonts and widgets. |
| `online` | The line to a server: the join, the round's map (fetched when it isn't here), the streams, what the server says; and the server browser's list. |
| `demo` | Games recorded as they are played, and played back: what the server said, and my own part, tick by tick. |

The rule across them is the C client's: the logic decides, the drawing reads. Nothing
that draws changes the game, and the HUD and menus turn input into actions the match
carries out.

## The code

Odin's naming: `Ada_Case` types, `snake_case` procedures, entity procedures named
`<entity>_<verb>`. A file holds one idea and is named for it; a long one is split by
what its parts do. Comments say what a thing is, or why it is so, in the code's own
voice; none restates the code. `Maybe` for what may be missing, `bit_set` for flags,
fixed-size arrays where a tick runs.

The tests are under `tests/`, a package each, run from the repository's root; those
that read `data/` step into `assets/` first, as a program runs from its install. The
simulation's test is `tests/compare`, which plays it against the C game.
