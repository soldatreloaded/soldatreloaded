# .srmod: Soldat Reloaded's mods

Being built: the format, Classic laid out as one, wearing mods by part, bringing them in
from Soldat 1 and from a zip, the HUD editor and the text editor are done (steps 1 to 4, 6
and 7, below); the game reads the catalogue at format 2, which the mods repository is yet
to publish (step 5). It replaces the mods of before (folders and `.smod`s laid out as
Soldat 1's, stacked), which the game no longer reads: a breaking change, those it finds put
aside (The mods of before, below). How Soldat 1 does
it, which this is measured against and imports from, is [soldat1-mods.md](soldat1-mods.md).

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

- **A folder**: `mods/<name>/` is a mod, to open and change as any folder. Sharing a mod
  is zipping its folder: a `.zip` (or `.srmod`, the same) handed over is unpacked into its
  folder as it comes in.
- **Parts**: a mod is made of parts, each a folder of it: the soldier, the weapons, the
  HUD, the sounds, the text, and the rest (below). It has any of them, and says which.
- **Choosing**: the player picks, part by part, which mod it comes from: the soldier from
  one, the weapons from another, the sounds from a third. Each part is Classic's until
  another is picked. There is no order and no stacking.
- **Falling back**: a file the chosen mod's part hasn't is Classic's. A mod can change
  one gun's art and nothing else, and it is worn for that gun.
- **Its own scale**: `mod.json` says how many pixels of its images make a unit (Classic's
  4.5, most of Soldat 1's 1), the whole mod's and any folder's or file's own, so art is
  kept as it was made and drawn as big as it should be. No `mod.ini`.
- **Looks, sounds and words only**: a mod never changes how the game plays. Animations,
  skeletons, maps and weapons' numbers are `data/`'s, the same for everyone in a game
  (design.md); a mod hasn't them.

## The folder

`mods/<name>/`, its files at its root:

```
mod.json
preview.png        optional: the Mods page's and the catalogue's picture, 16:9
soldier/
weapons/
hud/
sounds/
text/
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
  "parts": ["soldier", "weapons", "effects", "objects"],
  "scale": 1,
  "scales": {"weapons/icons": 4.5, "soldier/ranny": 2}
}
```

`format` is this layout's version, for the game to refuse one it doesn't know. `name` is
the folder's name: letters, digits, `-` and `_`, at most 32. `title` is what it is shown
as, at most 48, `name` if none. `version` is three numbers. `parts` is what it changes; the
game checks it against the folders, and a part listed without its folder, or a folder not
listed, is the mod's mistake, said on the Mods page. `scale` is its images' pixels to a
unit, 4.5 if it says none (Images, below); `scales` a part's, a folder's or a file's own,
by its path in the mod, the longest that holds an image winning. The rest are the
catalogue's `about.json`'s fields of before, unchanged.

The Mods page changes what `mod.json` says of a mod (its title, version, author,
description, licence and source) and its parts' scales, and makes a new mod: its folder,
and a `mod.json` of no part, to fill.

**Zipped**, a mod is a `.zip` (or `.srmod`, the same) of its folder, stored or deflated,
`mod.json` at its root or a folder or two down: what is handed over, and what the
catalogue serves. The game unpacks it into `mods/<name>/` (`mod_unpack`) as it comes in:
picked on the Mods page, dropped on the window, installed from the catalogue, or found in
`mods/` as the game starts (`mods_tidy`), which puts the zip aside in `mods/.old/`. One
without a `mod.json` is refused: nothing is converted. Asked for by its name, as the
catalogue asks, one whose `mod.json` says another is refused too, so an install never
takes another mod's place.

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
| `scenery` | `scenery/` | the maps' props, by the names maps give them: **Classic's alone**, as Soldat 1 never let a mod change it; a map's own come first | `scenery-gfx/`, left out of an import |
| `fonts` | `fonts/` | the HUD's two fonts, and `font.ini`: which, their widths and sizes, as now | `txt/font.ini` and its `fonts/` |
| `text` | `text/` | `strings.json`: what the game says in a match, by key (The text, below) | `txt/default.txt` |

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
- **At its mod's scale**, for every image whose size is its own: the soldier, the guns,
  the effects, the objects, the HUD and the icons, and the edges' textures (whose width
  stands for 90 units of an edge, their height its thickness). An image is its pixels over
  its scale in units, the world and the HUD both being laid out in units, a unit one pixel
  of the original 640 by 480: `mod.json`'s `scale`, else the longest of its `scales` that
  holds the image (`srmod_scale`). Classic's are 4.5; most of Soldat 1's 1, and its edges'
  always 1. A mod's art is kept as it was made, and the Mods page sets a part's scale, so
  one made at 2 is drawn as big as Classic's. A file Classic gives a mod's part is drawn at
  Classic's scale.
- **Any resolution** for the art whose size the map sets: scenery (each prop's size is in
  the map), polygon textures and the flags' cloth (their coordinates are). No scale is
  theirs.
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

**The HUD editor** edits this file. The Mods page opens it on any mod's HUD (**Edit HUD**
on its row, Classic's on its own): the HUD over the whole window as the game draws it,
with made-up numbers, each part outlined (as much of its picture as isn't see-through).
A part is picked by a click or from the panel's list, dragged or nudged with the arrows
(Shift by 10); an icon moved takes along what is anchored to it. The panel shows or
hides it, sets a bar's style and fill, a text's alignment, what it is kept beside, how
it is turned, and the whole HUD's opacity; Undo (Ctrl+Z), Reset, Save, Close (Escape,
twice with changes unsaved). There are no pictures to change in it: those of the HUD it
began from are kept.

Saved, a HUD is a mod of its own: `My HUD` (`My_HUD`, then `My_HUD_2`...), a `hud` part
alone, its `layout.json` and the pictures of the HUD it began from (at their scales), and
worn at once. Its description begins "Made in the HUD editor": opened on such a mod, the
editor saves over it. Writing a `setup.sif` for Soldat 1 from a layout is left for later.

## The text

`text/strings.json` is what the game says in a match: the kill messages and the big words,
the flags', the scores' and the round's end, who came and went, the HUD's, the
scoreboard's, the votes' and the end screen's words (`res.STRINGS`, about 120). Each by its
key, a line with the placeholders its English has, in their order (`%s` a name, `%d` a
number, `%%` a % sign):

```json
{"killed_by": "Von %s getötet.", "red_flag_returned": "Rote Fahne zurückerobert!"}
```

A key a mod leaves out is Classic's, and Classic's `strings.json` has them all, the game's
English. A line whose placeholders aren't its English's is passed over, logged, Classic's
said: it would print the wrong thing or nothing. The server's own lines (who came and went,
who was kicked, a map vote that found none) go by their key and the name in them, so each
client says them in the words it wears; their English goes too, for the server's log.

**The text editor** edits it: **Edit words** on a mod's page, or Classic's. Each line is
listed by what it is about and found by a search; the one picked is typed into, Classic's
beside it, and a line that would drop a placeholder isn't taken. **Read a Soldat 1
file...** brings in a `default.txt` or one of its `languages/*.txt`. Saved, the lines that
differ from Classic's are the mod's `strings.json`, and its text is worn; Classic's are
saved as a mod of their own, `My Text` (`My_Text`, then `My_Text_2`...). The fonts are
Latin-1: a language of other letters (Cyrillic, Greek, Chinese) shows boxes for them.

Soldat 1 says the same in `txt/default.txt`: UTF-16, a line each by number, 821 of them,
most its own menus' and config's. Each key says which of its lines it is ("{1}", or
"{96} %d {97}" made of two and what is between), and the importer and the editor read a
file of Soldat 1's so (`strings_from_soldat`), keeping the lines that differ from the
game's English.

## Choosing

The client config's `graphics.parts`, a mod by part; a part not named is Classic's:

```json
"parts": {"soldier": "NoNameMod", "weapons": "NoNameMod", "sounds": "RemasteredSounds", "hud": "micro1", "text": "Deutsch"}
```

The Mods page's **Configure Mods** lists Classic and each mod; beside the one picked, its
parts, each worn from it with a switch (and so from whichever wore it no longer), **Wear all
of it** and **Wear none of it**; its art's scale, the whole mod's and part by part; what its
`mod.json` says of it, changed and saved; and **Edit HUD**, **Edit words** and its folder.
A mod on for no part is installed and does nothing.

A file is looked for in the chosen mod's part, then in Classic's: by its path within the
part, in any case. A missing pivot is Classic's; a missing key of `layout.json`,
`font.ini` or `strings.json` is Classic's.

## Classic

The game's own look, sound and words, `mods/classic/`, laid out as any mod: its
`mod.json` and every part, whole. It is what every part falls back to, so it has every
file the game draws, plays or says. It can't be removed, changed, or chosen against itself.

## Bringing mods in

On the Mods page's **Install Mods**, beside the catalogue, three buttons:

- **Create**: an empty mod, `My_Mod` (then `My_Mod_2`...), its folder opened to fill, picked
  on Configure Mods to give it a title.
- **Import .srmod**: a `.srmod` picked in the system's dialog, which offers nothing else,
  unzipped into its folder as it is (The folder, above); one without a `mod.json` is
  refused, never converted. A `.srmod` or `.zip` dropped on the game's window, on either
  tab, is taken the same. A Soldat 1 mod comes in by Import S1 Mod, not zipped.
- **Import S1 Mod**: a folder of the player's Soldat 1 picked in the system's folder dialog
  (Windows' own; zenity, kdialog or osascript elsewhere), imported on a thread, its
  progress said beside the buttons (`soldat_import`).

The folder picked is told apart by what is in it and above it (`soldat_pick`):

- **The install**: the game's art folders (`gostek-gfx/`, `sfx/` and the like) beside a
  `mods/` or a `soldat.ini`, which no mod has. Everything in it is imported at once, a mod
  each, those imported before (a mod by their name there already) passed over:
  - **My S1 Mod**: the install's own folders whole, 1.7.1's art as it shipped and the
    player's changes over it, so Soldat 1's look can be worn here, part by part.
  - **Each mod** of `mods/<name>/` but those 1.7.1 ships with (`data/soldat-1.7.1.txt`,
    each file's size and CRC). Each is named for its folder (Soldat 1's own `classic`, the
    art of before 1.7, made `classic_s1`).
  - **Each custom interface**, the install's and its mods', but the ten 1.7.1 ships with
    as they came, `Default`, and any without a `setup.sif`.
- **A mod of its `mods/`**, or **an interface of its `custom-interfaces/`**: that alone,
  over the install it is in.
- **A mod alone**, its folders but no install about it: over the install found where
  Soldat is usually put (`C:\Soldat`, Program Files, Steam's libraries, and on Linux
  Wine's, Steam's, Flatpak's and Snap's), else over Classic, said so.

Under each mod goes the install's own folders whole, as Soldat 1 wore a mod over them, and
under each interface the install's HUD art and icons: a mod's art is shown among 1.7.1's,
not among Classic's redrawn. Whole means every file the game reads and every pivot, even
those that are Classic's as they are: Classic is ours, and changes, and a mod made from
Soldat 1 looks as it did there whatever becomes of it. Only what the game never reads is
left out. There is no choice about it. Then:

- Layered as Soldat 1 finds a file: the mod's first, then the install's (GR:393). A mod's
  `klata.bmp` replaces the install's `klata.png`, whichever the extension; within a folder
  a `.png` wins.

- Each image's Soldat 1 scale, as Soldat 1 works it out, from the `mod.ini` of the folder
  it came from: by its path, then its folder, then `DefaultScale`, else 1 (soldat1-mods.md);
  the edges' 1. So the install's art keeps its 4.5 (its cursor its 10), a mod's its own
  `mod.ini`'s, and a mod of before 1.7 without one its 1, side by side in one mod. Its pixels
  are kept as they were, and the mod's `mod.json` says the scales, as few as say them all
  (the most of them the mod's, and each folder's or file's that differs: `scales_compact`).
- `.bmp` to `.png`, its colour key to alpha (green; black for the 15 images keyed so).
- `[GOSTEK]` split into the soldier's and the weapons' `pivots.json`, only what differs from
  Classic's.
- `txt/default.txt` as `text/strings.json`, the lines that differ from the game's English;
  `txt/font.ini` and `fonts/` as `fonts`.
- Of the install's own folders, only what differs from Soldat 1.7.1 as it shipped, and from
  Classic, goes in, weighed by size before CRC and by size before pixels, so it is quick.
- Each custom interface is a mod of its own, its `hud` (its `setup.sif` as `layout.json`,
  anchors and alignment resolved) and its `icons` (its cursor, arrow and the rest of its 21
  pictures), named after it and titled "<name> interface". One 1.7.1 ships with, every file
  as it came, is left out.
- Left out: maps, scenery (Classic's alone), animations, `txt/` but `default.txt` and
  `font.ini`, anything else no part holds.

**The mods of before**: an `.smod`, or a folder in `mods/` without a `mod.json` laid out as
a Soldat 1 mod (`gostek-gfx/`, `sfx/`, `mod.ini`...), as this game wore them up to 0.27.
The game no longer reads them, nor converts them: a breaking change. As it starts, each it
finds is put aside in `mods/.old/` as it was, once, and the Mods page says so: a mod of
the catalogue is installed again from Install Mods, a player's own brought in with Import
S1 Mod.

## The catalogue

soldatreloaded-mods keeps a mod as its folder, laid out as above, `mod.json` in place of
`about.json`. Publishing zips each new version as `<name>.srmod` and writes the index,
`mods.json` on the `index` release: `"format": 2`, each entry as now plus its `parts`, so
the game can show what a mod changes before it is installed, and its `preview` if it has
one.

The game reads format 2 alone (`CATALOG_FORMAT`), showing each mod's parts on its row, and
installs a `.srmod` as it is, its `mod.json` saying the name the index gives it; an update
replaces the folder once the new one is whole. Until the repository publishes format 2,
Install Mods says the index isn't one the game reads.

`scripts/check.sh` checks what the game does: `mod.json`, the parts against the folders,
PNG only, files a part holds, the size limit (150 MB), the soldier's and guns' sizes.

## Building it

1. **The format**: `mod.json`, the parts, reading a mod's folder (or its zip, to unpack),
   finding a file by part with Classic under it; `layout.json` read and written; pivots;
   scales. Tests for each.
2. **Classic** relaid as a mod's folder; its crosshair and edges resized to 4.5 once; the
   game drawing from it as before, checked pixel for pixel (the HUD, the soldier, a map).
3. **Choosing**: `graphics.parts`; the Mods page by part.
4. **Bringing mods in**: the importer from Soldat 1, interfaces and words included, its art
   kept at its scales; zips unpacked; the mods of before put aside. Tested on the real
   thing: a 1.7.1 install, one with art copied over its own, its `mods/`, its interfaces,
   its languages.
5. **The catalogue**: the game reading `mods.json` at format 2: done. The repository's
   mods published as mods of now, and its index at format 2: to do.
6. **The HUD editor**, on `layout.json`: done.
7. **The text part and its editor**: done.

Soldat 1's custom interfaces are `hud` parts: their `setup.sif` is read by the importer,
which writes it as `layout.json`, and the HUD draws the layout as Soldat 1 draws theirs.

## Open

- **Weapons' names**: whether a mod may rename the guns, as Soldat 1's
  `txt/weaponnames.txt` does (`weapons`'s, if so).
- **Our soldier's styles**: a mod for Soldat 1 dresses the male alone, and the other
  styles wear its art where they look as the male does. Whether `soldier` may be partial
  per style, or each style is a part of its own.
- **Servers**: a server can't make players wear a mod (nothing here plays differently).
  Whether one may suggest one, offered as the player joins.
