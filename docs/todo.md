# Todo

- vDev as version?
- Move http to utils
- Discord presence
- Ship example server config, and switch to mjson for config with comments as struct tags & weapons.ini

- In game console
- Antics
- Add settings while playing game
- Cappy's issues list

# Phase 2

- The round delta-compressed in the snapshot, as the soldiers are
- The weapons sent as a difference from the defaults
- Explore autoloading all lua scripts
- Settings changed while the server runs (the password, public, the rest), from the
  console and server.command

- rcon for servers
- lobby server


----------

Where downloaded maps and their art go:

The map itself: when a server runs a map you don't have, its .pms is fetched into data/downloads/maps/<name>.pms. It's checked against the server's hash, and it never replaces a map the game ships with.
Scenery and textures: these are not downloaded at all. The server only sends the .pms, so a downloaded map draws with whatever art your mod or Classic already has:
missing scenery images are simply skipped;
a missing polygon texture leaves the polygons in plain colour;
a missing edge texture falls back to edges/default.

That's why the Yngwie maps' scenery had to go into Classic: anyone joining a server running a custom map whose art isn't in Classic sees it bare.

What OpenSoldat does: a map can carry its own art (the current_map/scenery-gfx/ and current_map/textures/ lookups in its MapGraphics.pas), and that art is checked before the base game's.

What I'd suggest:

On the server: the server would offer a map's scenery and textures alongside its .pms, from its data/ folder.
On the client: the client fetches what it's missing, hash-checked like the map, into data/downloads/maps/<name>/ (scenery-gfx/, textures/, textures/edges/).
Lookup order: images are then looked for in your mod, then the map's own art, then Classic.
