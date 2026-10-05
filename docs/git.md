# Git

## Commit messages

	type(scope): what the change is

Lower case after the colon, no full stop, short enough to read down a log. The subject
says what the change *is*, not what was done to the files: `feat(net): interpolate
others, number own bullets, drop guessed knockback`, not `updated netcode files`.

The types:

- `feat` — something the game or the tools can now do.
- `fix` — behaviour that was wrong and now is not.
- `refactor` — the same behaviour, arranged differently.
- `perf` — the same behaviour, faster or smaller on the wire.
- `docs` — the readme, docs/, the comments that carry reasoning.
- `test` — tests, and the tools that run them.
- `build` — the flags, the packaging, the workflows and their actions (`.github/`).
- `chore` — everything else: files in, files out, housekeeping.

The scope is the part of the tree the change lands in, named as the tree names it: a
package (`client`, `server`, `game`, `net`, `bots`, `resources`, `utils`, `sandbox`,
`launcher`), a part of one (`weapons`, `console`, `hud`, `anim`, `polymap`), or a part
of the install (`config`, `data`, `mods`, `scripts`), and `readme`, `docs`, `tests`,
`ci`. Leave it out when the change is the whole repo's.

### The body

A subject is enough for a small change. Anything that changes how the game behaves gets
a body, and the body is for the *why*: what was wrong, what rule the new code follows,
and what it measured. The netcode only makes sense as a series of arguments, and those
arguments live in the log. From the history:

> **fix(server): drop duplicate queued commands and advance tick during replay**
>
> A resent command was found in the queue and inserted again anyway, so the server
> applied commands several times over and every prediction was a few ticks off. The
> replay now advances the world tick per command, as the server will, so what reads
> the tick (jet fuel) predicts the same.

Numbers belong there too. A change to the netcode says what it measured, on what line,
so the next person can tell whether they made it better or worse.

Nothing is co-authored to a tool. A commit-msg hook strips those trailers if one
arrives.

## Branches

- `main` is the line of work. It builds and its tests pass.
- Work small enough to land in one go lands on `main`. Work that is not gets a branch
  named after its commit type: `feat/po-editor`, `fix/burst-bullets`.
- A branch merges with its history rather than squashed. The bodies of those commits
  are the reasoning, and squashing throws it away.
- Anything else is deleted once it has been merged or abandoned. A stale branch that
  nobody will say is stale costs more than it stores.

## Releases

Tags are `vMAJOR.MINOR.PATCH`, annotated, on `main`. Nothing is released yet; the first
will be `v0.1.0`.

While the major is 0:

- MINOR for anything a player would notice: a mode, a menu, a weapon, an editor.
- PATCH for fixes and for work nobody can see.

The wire decides the rest. A Hello carries the layout of the state and a build that
does not match is refused, so any release that changes the protocol will not talk to
the one before it. Say so in the tag's message, every time.

A tag with a suffix (`v0.2.0-rc.1`) is a pre-release: built and published like any
other, for testing, but the updater does not move to it and Discord is not told.

### Making one

```bash
git tag -a v0.1.0
```

```bash
git push origin v0.1.0
```

The tag's message is the release's notes, so write it for players to read. Pushing the
tag runs `.github/workflows/release.yml`, each step only if the one before succeeded:

1. **test**: `ci.yml`, the same as on every push to `main` and every pull request: the
   programs build and the tests pass, on Windows and Linux.
2. **package**: `.github/actions/package`, for the game on Windows and Linux and the
   server on Linux.
3. **publish**: a GitHub release named after the tag, its notes the tag's message,
   with every package and manifest attached.
4. **discord**: `discord.yml` posts the release to the channel behind the
   `DISCORD_WEBHOOK` secret (a webhook URL, set under the repository's Settings →
   Secrets and variables → Actions). It can be run by hand from the Actions tab to
   announce a release again.

A tag whose tests fail releases nothing; delete it, fix, and tag again.

### What a release ships

Each package is a program and the part of `assets/` it reads, unpacked flat so that the
install's root is the zip's:

| Package | Holds |
|---|---|
| `soldatreloaded-<version>-<platform>.zip` | `soldatreloaded(.exe)`, `soldatreloaded-launcher(.exe)`, `data/`, `mods/default/` |
| `soldatreloaded-server-<version>-linux.zip` | `soldatreloaded-server`, `data/`, `scripts/` |

Both hold `license.md`, `version.txt`, and their own manifest as `manifest.json`. Players
start the launcher, which brings the install up to the newest release and starts the
game. The game has no use for the server's scripts and the server draws nothing, so
neither carries the other's. The game is released for Windows and Linux; the server,
for those who host, for Linux alone. A server runs on Windows built from the source,
as it is developed.

A player installs nothing: each program carries its libraries inside it, and asks the
system only for what every machine has (the C library; on Linux, X11 and OpenGL). The
setup action builds what Odin doesn't have as a static library from pinned sources
(ENet, and curl on mbedTLS, for Linux), and the package action fails a release whose
programs would look for any of them, or for the Visual C++ runtime, on a player's
machine.

No config ships. The game and the server each make theirs at the install's root, with
the defaults, where it is missing (`client.config.json`, `server.config.json`); a
server's bans, mutes and weapons live in its config. So unpacking a release over an
install leaves them as they are.

`.github/actions/package` is where a package is made: what goes in it, and the manifest.

### The manifest

Beside each zip is its manifest, `<package>.manifest.json`: every file of the install
but the manifest itself, by its path, size and SHA-256, sorted by path. The install
keeps a copy as `manifest.json`.

```json
{
  "name": "soldatreloaded",
  "version": "0.1.0",
  "platform": "windows",
  "archive": "soldatreloaded-0.1.0-windows.zip",
  "files": [
    {"path": "data/anims/barret.poa", "size": 36550, "sha256": "35b33f7b…"},
    …
  ]
}
```

It is what the launcher (`apps/launcher`) keeps an install by, from three things: the
newest release's manifest, the files on disk, and the install's `manifest.json`. A file
the newest release lists that is missing or differs on disk is brought out of that
release's zip; a file the install's manifest lists that the newest doesn't was dropped,
and is deleted. So an update brings what changed and repairs what is damaged. What no
manifest lists is the player's and never touched: the configs, any mod beside
`mods/default/`, demos, and the scripts a server's owner writes beside the examples.

The launcher follows GitHub's latest release, the newest that is published and not a
pre-release.
