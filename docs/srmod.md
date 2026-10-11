# .srmod: Soldat Reloaded's mods

A design, not yet built. It replaces the mods of now (folders and `.smod`s laid out as
Soldat 1's, stacked) and the custom interfaces of `interfaces/`. How Soldat 1 does it,
which this is measured against and imports from, is [soldat1-mods.md](soldat1-mods.md).

## Why

Soldat 1's mods grew a piece at a time, and it shows. One mod at a time. Each image
carries its own scale, from one of three `mod.ini`s that never fall back to one another,
so a mod without one is drawn 4.5 times too big or too small depending on its age. The
HUD's layout is a memory dump in a file of its own, and its interfaces half live in mods
and half beside them. A mod's contents are whatever is in it: nothing says what it changes.

Ours inherited most of that, and added stacking: any number of mods on, in an order, each
file the top one's. That lets a sound mod and an art mod be worn together, but a player
can't say *the soldier from this one, the sounds from that one*, and a mod that changes
one gun's art and one sound is worn whole or not at all.

## What it is

- **One file**: `<name>.srmod`, a zip, is a mod. Sharing a mod is sharing the file.
- **Parts**: a mod is made of parts, each a folder of it: the soldier, the weapons, the
  HUD, the sounds, and the rest (below). It has any of them, and says which.
- **Choosing**: the player picks, part by part, which mod it comes from: the soldier from
  one, the weapons from another, the sounds from a third. Each part is Classic's until
  another is picked. There is no order and no stacking.
- **Falling back**: a file the chosen mod's part hasn't is Classic's. A mod can change
  one gun's art and nothing else, and it is worn for that gun.
- **One scale**: every image is 4.5 pixels to a unit, Classic's and every mod's. No
  `mod.ini`, nothing to get wrong: a mod's art is the right size because it is.
- **Looks and sounds only**: a mod never changes how the game plays. Animations,
  skeletons, maps and weapons' numbers are `data/`'s, the same for everyone in a game
  (design.md); a mod hasn't them.

## The file

A zip, stored or deflated, its files at its root:

```
mod.json
preview.png        optional: the Mods page's and the catalogue's picture, 16:9
soldier/
weapons/
hud/
sounds/
...                any of the parts
LICENSE.txt, ...   optional: credits and licences, read by nobody but people
```

**mod.json**:

```json
{
  "format": 1,
  "name": "NoNameMod",
  "title": "No Name Mod",
  "version": "1.0.0",
  "author": "Calp",
  "description": "Soldat simplified for professional gaming: plain, clean art.",
  "licence": "Free to modify and to share, crediting Calp.",
  "source": "calp@selfkill.com",
  "parts": ["soldier", "weapons", "effects", "objects"]
}
```

`format` is this layout's version, for the game to refuse one it doesn't know. `name` is
the file's name: letters, digits, `-` and `_`, at most 32. `title` is what it is shown as,
at most 48, `name` if none. `version` is three numbers. `parts` is what it changes; the
game checks it against the folders, and a part listed without its folder, or a folder not
listed, is the mod's mistake, said on the Mods page. The rest are the catalogue's
`about.json`'s fields of now, unchanged.

A mod being made is the same, unpacked: a folder in `mods/`, `mods/<name>/mod.json` and its
parts beside it. The game reads a folder as it reads a `.srmod`; the Mods page packs one
into the other to share it.

Which a mod is says whose it is to change, and nothing in `mod.json` does (a flag there
would travel with the file, and a mod handed on would say it was its new owner's). **A
folder** is a mod being made: the Mods page edits its `mod.json` (its title, version,
description and the rest) and packs it. **A `.srmod`** is packed, installed from the
catalogue or handed over: worn as it is, read only; **Unpack to edit** makes it a folder,
to change and pack again under a version of its own.

## The parts

| Part | Folder | What is in it | From Soldat 1's |
|---|---|---|---|
| `soldier` | `soldier/` | the soldier's parts, each with its mirrored `…2.png`; `team2/`, `ranny/` (wounds), the hair and headgear; our own styles, `female/`, `waifu/`, `rat/`, `furry/`, and haircuts; `pivots.json` | `gostek-gfx/`, `[GOSTEK]` (the body's) |
| `weapons` | `weapons/` | the guns held and dropped, their clips, shells, bullets and flashes; `icons/`, each gun's icon in the kill feed and the weapons menu; `pivots.json` | `weapons-gfx/`, `interface-gfx/guns/`, `[GOSTEK]` (the guns') |
| `effects` | `effects/` | blood, smoke, sparks, explosions, flames | `sparks-gfx/` |
| `objects` | `objects/` | things on the map; `textures/`, the flags' cloth and the kits | `objects-gfx/`, `textures/objects/` |
| `hud` | `hud/` | `layout.json`, and the pictures it places: the health, ammo and jet icons, their bars, the fire bar and its frame, the grenade, the vest bar | `custom-interfaces/<name>/` |
| `icons` | `icons/` | the rest of the HUD's and menus' art: the crosshair, the menu cursor, the arrow over me, the boxes' ground, the flags, the scoreboard's and minimap's marks, the title | `interface-gfx/` but the guns and the HUD's |
| `sounds` | `sounds/` | the sounds, `.wav`, `.ogg` or `.mp3`, by the game's names; `radio/` | `sfx/` |
| `textures` | `textures/` | the maps' polygon textures, by the names maps give them; `edges/` | `textures/` |
| `scenery` | `scenery/` | the maps' props, by the names maps give them | `scenery-gfx/`, which Soldat 1 never let a mod change |
| `fonts` | `fonts/` | the HUD's two fonts, and `font.ini`: which, their widths and sizes, as now | `txt/font.ini` and its `.ttf`s (ours) |

Within a part, files keep Soldat 1's names (`klata.png`, `ak74-clip.png`, `health-bar.png`):
every mod made so far, every tutorial and Classic itself use them, and an import is then a
move from one folder to another.

**Why these parts.** Each is something a player would want from one mod and not another,
and nothing in one depends on another's files. The soldier's pivots are the soldier's art's
and the guns' pivots the guns', so each travels with its art: the soldier from one mod and
the weapons from another still sit right. The HUD's layout places bars beside icons whose
frames are drawn into them (soldat1-mods.md), so the layout and the pictures it places are
one part, `hud`, and the art no layout places is another, `icons`. The gun icons are the
weapons', so a mod's guns and its icons of them come together.

## Images

- **PNG**, with alpha. Opaque pure green is see-through too, as in Soldat 1 (and black
  for the 15 smoke and spark images keyed so), so its art works as it is: the game keys it
  out as it loads. (An import turns it into alpha once, so a mod made is plain PNGs.)
- **4.5 pixels to a unit**, for every image whose size is its own: the soldier, the guns,
  the effects, the objects, the HUD and the icons; the world and the HUD both being laid out
  in units, a unit one pixel of the original 640 by 480. Classic is already so; nothing of
  it changed but its crosshair (it was 10), resized once.
- **Any resolution** for the art whose size the map sets: scenery (each prop's size is in
  the map), polygon textures and the flags' cloth (their coordinates are). The edges'
  textures are 4.5 too: their width stands for 90 units of an edge, their height is its
  thickness. Classic's, which Soldat 1 drew a pixel to a unit, were made 4.5 times as big;
  one an odd number of pixels thick is a tenth of a unit thicker for it.
- **Limits**, as now: a soldier's part at most 16 by 16 units, a gun's body 64 by 64;
  bigger is shrunk to fit, and the Mods page says so.
- **Mirrored images** (`klata2.png`) are the same size as their originals.

**pivots.json**, in `soldier/` and `weapons/`: where each image is pinned to the
skeleton, as fractions of its width and height, by Soldat 1's ids; only those that differ
from Classic's.

```json
{"Chest": [0.1, 0.3], "Head_Dmg": [0, 0.5]}
```

## The HUD

`hud/layout.json` is setup.sif made readable, and explicit where the original guessed:

```json
{
  "alpha": 255,
  "health": {"shown": true, "icon": {"at": [5, 439]},
             "bar": {"at": [45, 449], "style": "across", "fill": "from_left", "anchor": "health"}},
  "ammo":   {...},
  "bullets": {"shown": true, "at": [348, 451], "align": "right", "anchor": "ammo"},
  "team_box": {"shown": true, "at": [575, 330]},
  ...
}
```

Positions in the 640 by 480 layout, turns in degrees. A bar's `style` is `across`, `down`
or `number`; its `fill` which way it grows. Each part says what it is `anchor`ed to as the
view widens (an icon, or `none` for the screen's corner) and texts how they are aligned:
the original worked both out from which pictures an interface had and whether it was
custom at all (soldat1-mods.md), which an import resolves once and writes down, and the
editor shows and changes. A part a layout leaves out is Classic's layout's.

The interface editor (stage 2 of the custom interfaces) edits this file, and can still
write a `setup.sif` for Soldat 1 from it.

## Choosing

The client config's `graphics.parts`, a mod by part; a part not named is Classic's:

```json
"parts": {"soldier": "NoNameMod", "weapons": "NoNameMod", "sounds": "RemasteredSounds", "hud": "micro1"}
```

The Mods page lists each mod with its parts, each part turned on from it or not; turning a
part on from one mod turns it off from whichever had it. **Use all** turns on every part a
mod has. A mod on for no part is installed and does nothing.

A file is looked for in the chosen mod's part, then in Classic's: by its path within the
part, in any case. A missing pivot is Classic's; a missing key of `layout.json` or
`font.ini` is Classic's.

## Classic

The game's own look and sound, `mods/classic/`, laid out as a `.srmod` unpacked: its
`mod.json` and every part, whole. It is what every part falls back to, so it has every
file the game draws or plays. It can't be removed or chosen against itself.

## Bringing mods in

**From Soldat 1** (the Mods page's **From your Soldat 1**, as now), making `.srmod`s, which
are then mods like any other. Soldat 1.7.1 never used `.smod`s (OpenSoldat's), so there is
no importer of them. Soldat 1 was modded two ways, and the importer takes both:

- **Over the game's own files**: art and sounds copied over the install's `gostek-gfx/`,
  `sfx/` and the rest. Each file of the install's own folders is weighed against 1.7.1 as
  it shipped (`data/soldat-1.7.1.txt`, each file's size and CRC), as the importer does now,
  and what differs is the player's.
- **In `mods/`**: each loose folder of `mods/<name>/`, as `-mod <name>` wore it, over the
  install's own as Soldat wore it.

And the install's custom interfaces, the ten it shipped with and any added. Then:

- Each image's Soldat 1 scale, as Soldat 1 works it out: its `mod.ini`'s, by its path,
  then its folder, then `DefaultScale`, else 1 (soldat1-mods.md). An image at another
  scale than 4.5 is resized to it: up by a whole number with each pixel kept sharp, then
  down to 4.5 smoothed, so old pixel art stays crisp at 4.5 times.
- `.bmp` to `.png`, its colour key to alpha (green; black for the 15 images keyed so).
- `[GOSTEK]` split into the soldier's and the weapons' `pivots.json`, only what differs from
  Classic's.
- Only what differs from Soldat 1.7.1 as it shipped, and from Classic, goes in, as now.
- Each custom interface is a `.srmod` of its own, its `hud` (its `setup.sif` as
  `layout.json`, anchors and alignment resolved) and its `icons` (its cursor, arrow and
  the rest of its 21 pictures), named after it. The ten stock ones too: they shipped with
  1.7.1, but they aren't Classic's, and a player will want them.
- Left out: maps, animations, `txt/` but the weapons' names (if the game shows them),
  anything else no part holds; listed for the player.

**`.smod`s of now** (the catalogue's three, and any a player made or installed): the game
no longer wears them. The catalogue's are converted once, by a tool of the mods
repository's (below), not by the game. One in a player's `mods/` is listed as an old mod,
to get again from the catalogue or remake.

## The catalogue

soldatreloaded-mods keeps a mod as its folder, as now, but laid out as a `.srmod`
unpacked, `mod.json` in place of `about.json`. Publishing packs each new version as
`<name>.srmod` and writes the index, `mods.json` on the `index` release, where it is now:
`"format": 2`, each entry as now plus its `parts`, so the game can show what a mod changes
before it is installed, and its `preview` if it has one.

The game of 0.19 and before reads the index only if its format is 1: format 2, it says the
index isn't one it reads, and installs nothing, so it never takes a `.srmod` for a
`.smod`. Its catalogue is gone until it updates, which the launcher does; the mods it has
installed it keeps wearing.

The three mods there now (Competitive, NoNameMod, RemasteredSounds) are converted once by
a script of the mods repository's (their `mod.ini`'s scales read as the game reads them now,
their old-sized art found by its images' size, as now; `txt/font.ini` and its `.ttf`s as
`fonts`), checked by eye, and published as their next minor versions.

`scripts/check.sh` checks what the game does: `mod.json`, the parts against the folders,
PNG only, files a part holds, the size limit (150 MB), the soldier's and guns' sizes.

## Building it

1. **The format**: `mod.json`, the parts, reading a `.srmod` or its folder, finding a file
   by part with Classic under it; `layout.json` read and written; pivots. Tests for each.
2. **Classic** relaid as a `.srmod` folder; its crosshair and edges resized to 4.5;
   the game drawing from it as before, checked pixel for pixel (the HUD, the soldier, a map).
3. **Choosing**: `graphics.parts`; the Mods page by part. The game wears `.srmod`s.
4. **The importer from Soldat 1**, interfaces included: art over the install's own files,
   its `mods/` folders, its custom interfaces. Tested on the real thing: a 1.7.1 install,
   one with art copied over its own, its `mods/classic`, its ten interfaces.
5. **The catalogue**: the three mods converted by the mods repository's script;
   publishing `.srmod`s and `mods.json` at format 2; the game reading it.
6. **The interface editor**, on `layout.json`.
7. **Pack and share**: the Mods page's **New mod** making a `.srmod` folder, and **Pack**
   making the file.

The custom interfaces of now (`interfaces/`, `graphics.interface`) become `hud` parts in
step 3; their reading of `setup.sif` and the HUD's drawing stay, the importer's and the
game's.

## Open

- **Weapons' names**: whether a mod may rename the guns, as Soldat 1's
  `txt/weaponnames.txt` does (`weapons`'s, if so).
- **Our soldier's styles**: a mod for Soldat 1 dresses the male alone, and the other
  styles wear its art where they look as the male does. Whether `soldier` may be partial
  per style, or each style is a part of its own.
- **Servers**: a server can't make players wear a mod (nothing here plays differently).
  Whether one may suggest one, offered as the player joins.
