# Soldat 1's mods, interfaces and scales

How Soldat 1 finds, layers and sizes its art, sounds and HUD layouts: the reference for
importing a Soldat 1 install or mod, and for designing our own mod format. Gathered from
three places, and each fact says which:

- **1.7.1**: a Soldat 1.7.1.1 install (`C:\Soldat` on the machine this was written on),
  its files measured. Its executable is packed, so its code can't be read.
- **OpenSoldat**: the open-sourced 1.8 code (`../opensoldat`, Pascal). File references
  are to it: GR `client/GameRendering.pas`, IG `client/InterfaceGraphics.pas`, MG
  `client/MapGraphics.pas`, GG `client/GostekGraphics.pas`.
- **The record**: the changelog (https://opensoldat.github.io/manual/changelog.html), the
  manual (https://opensoldat.github.io/manual/manual.html) and the wiki
  (https://wiki.soldat.pl/index.php/Mod.ini,
  https://wiki.soldat.pl/index.php/Creating_Modifications,
  https://wiki.soldat.pl/index.php/Third-Party_Tools).

## Versions

| | 1.7.1 | 1.8 / OpenSoldat |
|---|---|---|
| The base game | loose folders | `soldat.smod`, a zip (`fs_localmount` reads loose folders instead) |
| A mod | a loose folder, `mods/<name>/` | `mods/<name>.smod`, a zip; a loose folder is never read |
| Chosen by | `-mod <name>` (since 1.3.0); `Last_Mod=` in soldat.ini | the `fs_mod` setting, at start only |
| Mods at once | one | one (`ModDir` is a single path) |
| Interfaces | `custom-interfaces/<name>/`, in the main folder only | the same, or inside the mod; and `.sint` zips |
| Interface chosen by | Options, Visuals, Interface Style; `Interface=` in soldat.ini | the `ui_style` setting |
| Server checks the mod | no | `sv_pure`, by the `.smod`'s SHA1 |

Before mods had a folder of their own, some were installed over the base game's files,
and some still say to: an importer meets both.

## What a mod holds

A mod replaces the base game's files one at a time, by path; what it hasn't comes from
the base game. Nothing lists a mod's contents: it is what is in it.

| Folder | What it is | A mod's own? |
|---|---|---|
| `gostek-gfx/` | the soldier's parts; `ranny/` the damaged ones, `team2/` the second team's | yes |
| `weapons-gfx/` | the guns held and dropped, their clips, shells, bullets and muzzle flashes | yes |
| `sparks-gfx/` | effects; `explosion/` and `flames/` | yes |
| `objects-gfx/` | things on the map | yes |
| `textures/objects/` | the flags' cloth and the kits | yes |
| `interface-gfx/` | the HUD's and the menus' art; `guns/` the weapon icons | yes |
| `textures/` | the maps' polygon textures; `edges/` their edges | yes: the mod's wins even over the map's own |
| `sfx/` | sounds; `radio/` the radio's voices | yes |
| `txt/` | `weaponnames.txt`, the language files | yes |
| `anims/` | animations | OpenSoldat only (1.7.1 unconfirmed) |
| `mod.ini` | scales and the soldier's pivots (below) | yes |
| `custom-interfaces/` | HUD layouts (below) | OpenSoldat only |
| `scenery-gfx/` | map props | **no**: the map's own, then the base game's (MG:401-404); the manual says so too |
| `objects/*.po` | the soldier's skeleton | no |
| `maps/`, fonts | | no |

Folders below these (`gostek-gfx/ranny/`, `interface-gfx/guns/`) are fixed; there are no
others.

OpenSoldat's loadable art is listed in `shared/gfx.inc.in`: 121 soldier images, 105
weapon images, 67 sparks, 50 interface images and 11 objects, each with its path and its
colour key. Each is named `.bmp` there; a `.png` is found in its place (below).

## Image files

- **Formats**: decoded by their content, whatever their extension (stb_image: png, bmp,
  jpg, gif, animated gif). 1.4.0 already shipped pngs named `.bmp`.
- **Which file**: a `.png` of the name first, then the name as written (GR:338-355); so
  a `.png` beside a `.bmp` wins. Names are matched in any case. (1.4.0 had it the other way
  round, a `.bmp` first.)
- **Transparency**: a colour key, matched exactly, alpha too: opaque pure green
  (`FF00FF00`) for nearly everything, opaque black for 15 smoke and spark images
  (`para-rope`, `bigsmoke`, `spawnspark`, `explosion/smoke1-9`, and a few more). Applied to
  pngs as well, but not to animated gifs. Polygon textures have none; scenery and edges
  are keyed green. Everything is premultiplied after keying.
- **Sizes**: no power-of-two rule; images are packed into atlases, and one bigger than
  the GPU's largest texture is shrunk.

## Scale

**A unit** is one pixel of the original 640 by 480 screen: the world and the HUD are
laid out in them. **An image's scale** is its pixels to a unit, so it is drawn at its
pixels over its scale. The wiki: scale = the screen height it was made for / 480.

**Two eras.** Up to 1.6.x everything was small bitmaps, at 1. 1.7.0 (2016) made the
stock art high-resolution ("4K UHD soldier/weapon/objects/default interface/sceneries
graphics", "upscaled by 4.5x") at 4.5, which is 2160 / 480. Measured in 1.7.1: `ak74` is
84 by 28 in the stock art and 18 by 5 in the old (84 / 4.5 = 18.7); the cursor is 170 by
170 at 10, the old one 16 by 16. The 1.7.1 install keeps the old art as `mods/classic`
(its weapons, interface and object textures; 136 bmps), which has no `mod.ini`: so it is
drawn at 1.

**Where an image's scale comes from** (`GetImageScale`, GR:233-268): the `[SCALE]` of the
`mod.ini` of where the image came from, the base game's, the mod's, or an interface's:

1. the image's own path (`interface-gfx/cursor.png=10`), with the extension of the file
   actually found;
2. else its folder's (`gostek-gfx/ranny=2`), only its own, not one above;
3. else `DefaultScale`;
4. else **1**.

Keys are matched in any case, either way of slash, `.` the decimal point. There is no
falling back between `mod.ini`s: **a mod without one, or without `DefaultScale`, is at 1**,
not at the base game's 4.5. That is how a mod from before 1.7 still works, and the wiki
says so ("treated as old-style"); it also warns that a high-resolution mod without one
has HUGE soldiers and weapons.

**The stock values** (1.7.1's `mod.ini`, the same in OpenSoldat's base):

```ini
[SCALE]
DefaultScale=4.5
interface-gfx/title-l.png=1
interface-gfx/title-r.png=1
interface-gfx/cursor.png=10
```

**What the scale sizes**, and what it doesn't:

| Art | Sized by |
|---|---|
| soldier parts, guns held and dropped, sparks, bullets, `objects-gfx` | pixels / scale |
| the interface | pixels / scale; the bars' widths and heights in `setup.sif` are ignored, the picture's own used |
| map props (`scenery-gfx`) | the map: each prop's width and height in the `.pms`; the image's resolution is free |
| polygon textures (`textures/`) | the map's texture coordinates; resolution is free |
| flags and kits (`textures/objects/`) | stretched over their skeleton's points; resolution is free |
| edge textures (`textures/edges/`) | **their pixel height**, as units, the width stretched by the edge's length over 90: the one image whose pixels are units with no scale |

**Limits after scaling** (since 1.4.0, in units since 1.7.0): a soldier part at most 16 by
16, the gun bodies and a few others at most 64 by 64; bigger ones are shrunk to fit
(GR:1187-1278). 1.7.0 shrinks them where earlier versions stopped with an error.

**Loading smaller**: `r_optimizetextures` (1.7.0's `Optimize_Textures`, off by default)
shrinks images as they load to what the screen can show, and corrects the scale so the
drawn size is the same. It never enlarges.

## The soldier's pivots

`mod.ini`'s `[GOSTEK]` (since 1.7.0) places each soldier part and weapon image on the
skeleton: `<id>_CenterX` and `<id>_CenterY`, the point of the image pinned to the
skeleton, as fractions of its width and height (0 to 1, though values beyond are used:
a dreadlock at -1.35). The ids are OpenSoldat's `client/GostekGraphics.inc`, 131 of them:
`Left_Thigh`, `Chest`, `Head`, `Hair_Dreadlock1`, `Primary_Ak74`, `Primary_Ak74_Clip`,
`Primary_Ak74_Fire`, `Secondary_Mp5`, `Frag_Grenade1`... The base game's values load
first and a mod's replace them key by key (GR:184-201).

Being fractions, pivots don't change with the scale. Only the pivot can be moved: which
two skeleton points a part hangs between, whether it flexes or flips, are fixed. The
second team's parts share the first's pivots. An image's mirrored copy (`klata2.png`
for `klata.png`) should be the same size as it. A pivot more than 16 units beyond its
image is pulled back (GG:130-174).

1.7.0's betas kept scales in a `scale.ini` in each folder instead; there was never a
`gostek.ini`. An online pivot editor: http://urraka.github.io/soldat-gostek/.

## The HUD's art: interface-gfx

`interface-gfx/` is all of the HUD's and the menus' art, and the default interface's.
1.7.1 has 47 images:

- the HUD: `health`, `ammo`, `jet` (icons); `health-bar`, `jet-bar`, `reload-bar`,
  `vest-bar`, `fire-bar` and `fire-bar-r` (the fire bar's frame); `nade`, `cluster-nade`;
  `overlay`, the screen tinted while a bonus lasts
- the rest: `cursor` (the crosshair), `menucursor`, `sight`, `arrow` (over my head),
  `back` (the boxes' ground, 64 by 64 at 1: it is stretched by that), `flag`, `noflag`,
  `dot`, `smalldot`, `deaddot`, `star`, `bot`, `mute`, `prot`, `scroll`, `title-l`,
  `title-r`
- `guns/`: the 18 weapon icons, of the kill feed and the weapons menu

The icons carry their bars' empty frames: the bars are drawn into them. So 1.7.1's
`health.png` is 700 by 184 (155 by 41 units), the old classic interface's `health.bmp`
155 by 29.

## Custom interfaces

**A folder each**: `custom-interfaces/<name>/`, flat, holding:

- `setup.sif`, the layout (below); without one, "Could not find setup.sif" and the
  default interface
- any of 21 of `interface-gfx`'s images, at the folder's top: `cursor`, `health`, `ammo`,
  `jet`, `health-bar`, `jet-bar`, `reload-bar`, `back`, `overlay`, `nade`, `noflag`,
  `flag`, `cluster-nade`, `dot`, `fire-bar`, `fire-bar-r`, `vest-bar`, `menucursor`,
  `arrow`, `title-l`, `title-r` (GR:412-414, `CUSTOM_FIRST` to `CUSTOM_LAST`). One it
  hasn't is `interface-gfx`'s. The others (the gun icons, `sight`, `smalldot`...) are
  always `interface-gfx`'s: 1.7.1's micro1 ships `Deaddot`, `Smalldot` and `Star`, which
  OpenSoldat passes over.
- optionally a `mod.ini`, its `[SCALE]` keyed by the file's name (`health.bmp=2`); without
  one, 1

Names are in any case (predator's are `AMMO.BMP`, `Back.bmp`, `setup.SIF`). "Default", or
none, is the game's own interface. OpenSoldat also takes the folder zipped, as
`custom-interfaces/<name>.sint` (1.8 and later).

**Where they are**: 1.7.1 reads them from the main folder only ("Soldat only reads
interfaces in the primary Soldat directory", the wiki's modding guide; the install agrees:
its 10 are there, `mods/classic` has none). OpenSoldat reads the layout and the images from
`<mod>/custom-interfaces/<name>/` (IG:320-334, GR:432), which is the main folder's only
with no mod on; with a mod on, an interface must be inside it. Its `.sint`s are mounted
at the main folder's, so with a mod on they aren't found; and an interface's own
`mod.ini` is read from the main folder's, so one inside a mod is sized by the mod's
`mod.ini`, keyed `custom-interfaces/<name>/<file>`.

**1.7.1's stock interfaces**: cabbage, classic, lacey-v2, micro1, military, predator,
soldat style, storm, tech, text. All are bmps at 1 but micro1, which is high-resolution with
its own `mod.ini` at 4.5 (its `back` 288 by 288, 64 units). Predator hides icons with 1 by 1
images.

**setup.sif** is OpenSoldat's `TInterface` (IG:106-146) written whole, read with no size
or version check: 240 bytes, little-endian, each Integer at a multiple of 4 (Delphi's and
Free Pascal's default alignment), so 3 bytes pad each bar's style. All ten of 1.7.1's are
240 bytes (packed it would be 222). In order:

| Offset | Field |
|---|---|
| 0 | Alpha, a byte: the HUD's pictures' and texts' |
| 1-11 | shown, a byte each: Health, Ammo, Vest, Jet, Nades, Bullets, Weapon, Fire, Team, Ping, Status |
| 12 | HealthIco X, Y, Rotate |
| 24 | HealthBar X, Y, Width, Height, Pos (a byte, 3 padding), Rotate |
| 48 | AmmoIco X, Y, Rotate |
| 60 | AmmoBar, as HealthBar |
| 84 | JetIco X, Y, Rotate |
| 96 | JetBar, as HealthBar |
| 120 | VestBar, as HealthBar |
| 144 | Nades X, Y, Width, Height, Pos (a byte, 3 padding) |
| 164 | Bullets X, Y |
| 172 | Weapon X, Y |
| 180 | FireIco X, Y, Rotate |
| 192 | FireBar, as HealthBar |
| 216 | TeamBox X, Y |
| 224 | Ping X, Y |
| 232 | Status X, Y |

Positions are in the 640 by 480 layout; rotations in degrees, about the picture's
top-left. A bar's Pos is 0 a number ("75%"), 1 across, 2 down; the grenades' places them
in a row or a column. The fire bar is drawn crosswise: its frame (`fire-bar-r`) at
FireBar's place and turn, the bar itself at FireIco's place and turn, with FireBar's style.
The default interface's values are OpenSoldat's `LoadDefaultInterfaceData`
(IG:200-294). How each part is drawn, anchored as the screen widens, and aligned
otherwise for a custom interface is `apps/client/hud/draw_bars.odin`, which follows the
original's; `core/resources/interface.odin` reads and writes the file.

**Tools of the time**: "Soldat Interface Maker" (Michal Marcinkowski, bmps only) and
"Advanced Soldat Interface Maker" (SyavX,
https://forums.soldat.pl/index.php?topic=37906).

## Sounds and text

- **Sounds**: `sfx/`, `.wav` only (mono or stereo, 8 or 16 bit, or float), by 163 fixed
  names (OpenSoldat's `Sound.pas`), `radio/` among them; the base game's load first and a
  mod's replace them one by one. No sound config. Music is apart, in `music/`; `sfx/`
  also holds `.xm` and `.it` modules.
- **txt/**: `weaponnames.txt`, a weapon's shown name a line; the language files. The radio's
  menu (`radiomenu-default.ini`) is the base game's only.
- **Fonts**: the base game's, chosen and sized in the settings (`font_1_filename`,
  `font_menusize`...); no mod's.

## Not confirmed

- Whether 1.7.1 loads `anims/` from a mod.
- The scales third-party high-resolution mods used: the wiki's formula gives 2 for a
  960-line screen, 4.5 for 4K; none were surveyed.
