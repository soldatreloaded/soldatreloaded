# Todo

What is left before this plays as the C game does, besides what porting.md leaves out on
purpose (deathmatch, the rope, the bonus kits, the flamer, the bows, the stationary gun).

Launcher
- Github workflows
- Static compile the libs on both windows and linux
- CLI based manifest updater
- Update itself first, alone, then restart, so a release is installed by its own launcher
- Stage the files and move them in last, so an interrupted update finishes next run
- Fetch only the changed files by HTTP range, falling back to the whole package
- A package hash in the manifest, and the download checked against it
- Leave a player's edits to seeded files alone (scripts/main.lua, the configs)
- Trust the installed manifest instead of hashing every file on every start
- Refuse manifest paths that leave the install (absolute, `..`)
- Remove folders a release no longer has
- Flags: --no-update, --update-only, --verify, --releases <url>; pass the rest to the game
- A window with progress, in the menu's look, when the work takes more than a glance

Client
- Get down client infrastructure first
- Discord presence, later

Shared
- game/
- cli/
- network/
- Review resources/
- Packed maps (.smap): listed, loaded, and sent to a player with their own art
- The round delta-compressed in the snapshot, as the soldiers are
- The weapons sent as a difference from the defaults

Server
- Explore scripting options
- Explore autoloading all lua scripts
- Settings changed while the server runs (the password, public, the rest), from the
  console and server.command
- The command line: more than -map and -port
- A main.lua made where there is none, and the C game's examples brought over
- server.mode(), if old scripts need it
- Soldat's .bot profiles read beside the JSON ones
- The install found from wherever the server is started
