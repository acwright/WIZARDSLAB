artwork/
========

The editor projects the tiles and screens are drawn in. These are working
files, not build inputs — nothing here is assembled. The build reads
`data/`, and getting art from here to there is one **Binary** export per file
(see [data/README.md](../data/README.md)).

| File | Editor | Mode |
|---|---|---|
| `WizardsLab.tms9918` | [TMS9918-EDITOR](https://github.com/acwright/TMS9918-EDITOR) | Graphics I, 32 × 24 |
| `WizardsLab.vic20` | [VIC-EDITOR](https://github.com/acwright/VIC-EDITOR) | Hires, 22 × 23, unexpanded |

Both open by double-click in the desktop builds.

## Draw the tiles in TMS9918-EDITOR

The TMS9918 pattern format and the Commodore character format are the same
bytes — 256 characters, 8 each, MSB leftmost. **So the tileset is drawn once,
in Graphics I, and all three machines use the export verbatim.**

Graphics I is the mode to draw it in because it is the one that *enforces* the
rule the whole tile map is built on: colour is assigned per group of eight
consecutive patterns, not per cell. Tiles 64–111 are the six potion colours,
one group each, and every glyph of a colour lives inside its group. If the art
reads correctly there, it reads correctly everywhere.

Both projects are seeded with the current placeholder tileset and the panel
laid out at the right offset for their machine, so they open ready to draw
over rather than blank. The TMS9918 project's 32 colour groups are already set
to the SPEC.md §4.3 values.

## What VIC-EDITOR is for

Laying out the VIC-20 screens and checking that the six potion colours read
against black in the VIC's eight hi-res colours. Its settings are already
configured to match `VIC20-16K.cfg`: character base `$1400`, screen base
`$1E00`, unexpanded, black screen and border, 22 × 23, 256 characters.

Its charset is the same 2048 bytes as the TMS9918 project's, so **if you
redraw a tile in one, redraw it in the other** — or, more simply, draw in
TMS9918-EDITOR and paste the changed characters across through the byte box.

**You should not need a C64 editor at all.** The C64 uses the same tileset
file, and its colours come from `data/tilecolor-c64.inc`, which is
hand-authored from the spec rather than exported.

## Exporting

| From | Export | To |
|---|---|---|
| TMS9918 ▸ Character Set | Binary, pattern table | `data/tileset.bin` |
| TMS9918 ▸ Screen "Play" | Binary | `data/screen-play-ac6502.bin` |
| TMS9918 ▸ Screen "Title" | Binary | `data/screen-title-ac6502.bin` |
| VIC ▸ Screen "Play" | Binary, `screen_N` and `colors_N` separately | `data/screen-play-vic20.bin`, `…-color.bin` |
| VIC ▸ Screen "Title" | Binary, both segments | `data/screen-title-vic20.bin`, `…-color.bin` |

The C64's four screen images have no editor project yet — lay them out
however suits you and drop 40 × 25 name-table and colour-RAM binaries into
`data/`. The panel goes at column 9, row 1.

Then `make` and `make smoke` to see it.
