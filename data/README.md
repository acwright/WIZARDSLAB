data/
=====

Artwork and lookup tables. One rule keeps the two apart:

| Extension | Origin | Edit it how |
|---|---|---|
| **`.bin`** | An editor's **Binary** export | Overwrite the file. Never hand-edit. |
| **`.inc`** | SPEC.md | Hand-edit. Never overwritten by an export. |

The assembly pulls the binaries in with `.incbin`, so replacing artwork is a
file copy — there is no label to keep in sync and nothing to paste.

**`tileset.bin` and the four AC6502 / VIC-20 screens are real artwork now** —
they came out of `artwork/`. The C64's four screen images are the same panel
on a 40 × 25 grid with placeholder margins.

`make data` (which runs `tools/make-placeholders.py`) rebuilds only the C64
screens, reading the panel straight out of `artwork/WizardsLab.tms9918`. **It
will not overwrite the real art**; `make-placeholders.py --all` regenerates
everything from scratch and throws that art away, which is only useful for
bootstrapping.

---

## One tileset, three machines

The TMS9918 pattern format and the Commodore character format are the same
thing: 256 characters, 8 bytes each, MSB leftmost, one bit per pixel. So
**`tileset.bin` is a single 2048-byte file that all three platforms use
verbatim.** Only the way a tile gets its colour differs, and that lives in the
`.inc` tables, not the artwork.

Which means: draw the tiles once, in **TMS9918-EDITOR**, in **Graphics I**
mode. That mode is the one that enforces the 8-patterns-per-colour-group rule
the whole tile map is built around (SPEC.md §4), so if the art works there it
works everywhere. The same goes for the screens: 32 × 24 is the only one of the
three grids that holds the whole 22 × 24 panel, so the panel is laid out there
too and the other two are derived from it. Use VIC-EDITOR to check the six
potion colours against black in the VIC's eight — you should not need a C64
editor at all.

---

## Files

### Tiles

| File | Bytes | Source |
|---|---|---|
| `tileset.bin` | 2048 | TMS9918-EDITOR ▸ Graphics I ▸ Export Character Set ▸ **Binary**, pattern table only |
| `tilecolor-tms9918.inc` | 32 | SPEC.md §4.3 — VDP colour table, `(fg << 4) \| bg` |
| `tilecolor-vic20.inc` | 256 | SPEC.md §4.3 — tile → colour RAM, values 0–7 only |
| `tilecolor-c64.inc` | 256 | SPEC.md §4.3 — tile → colour RAM, values 0–15 |

The two CBM tables are identical for tiles 0–127 except where the VIC has no
equivalent colour (there is no gray), and diverge freely in the artwork groups
(tiles 128–255).

> TMS9918-EDITOR can also export the colour table, but **do not** use it here —
> `tilecolor-tms9918.inc` is the authority and is what the AC6502 build
> includes. Set the group colours in the editor so the art previews correctly,
> then keep the two in step by hand. If they ever disagree, SPEC.md wins.

### Screens

Each screen is exported whole: panel frame, labels, and the margin artwork
either side of it, as one name-table image. Code only draws *over* it — the
well, the score and level digits, the preview, and the message band. Nothing
else on screen is drawn by code, which is why the layouts live here.

| File | Bytes | Source |
|---|---|---|
| `screen-play-ac6502.bin` | 768 | TMS9918-EDITOR ▸ Export Screen ▸ Binary (32 × 24) |
| `screen-title-ac6502.bin` | 768 | as above |
| `screen-play-vic20.bin` | 506 | VIC-EDITOR ▸ Export ▸ screen ▸ `screen_N` ▸ Binary (22 × 23) |
| `screen-play-vic20-color.bin` | 506 | VIC-EDITOR ▸ same export ▸ `colors_N` |
| `screen-title-vic20.bin` | 506 | as above |
| `screen-title-vic20-color.bin` | 506 | as above |
| `screen-play-c64.bin` | 1000 | 40 × 25 name table |
| `screen-play-c64-color.bin` | 1000 | 40 × 25 colour RAM |
| `screen-title-c64.bin` | 1000 | as above |
| `screen-title-c64-color.bin` | 1000 | as above |

Export the two segments to **separate files** — the game blits them as two
images. A `.prg` export packs them behind a load address and is not what this
build wants.

**Panel offsets.** The 22 × 24 panel is horizontally centred on each machine
and **top aligned on all three** (`PANEL_Y = 0`), so when you lay a screen out
in an editor, place it at:

| Platform | Screen | Panel origin | Vertical fit |
|---|---|---|---|
| AC6502 | 32 × 24 | column 5, row 0 | exact |
| VIC-20 | 22 × 23 | column 0, row 0 — the screen *is* the panel | panel row 23 is clipped |
| C64 | 40 × 25 | column 9, row 0 | screen row 24 is one spare course of margin |

The panel is drawn **once**, in TMS9918-EDITOR, because 32 × 24 is the only one
of the three grids that holds all 24 rows. Everything else is that block moved
sideways.

### Size note

The C64's four screen images are 4000 bytes of a 16 KB cartridge, and the
title screen only ever appears on one state. When ROM gets tight, RLE the
screen images — they are mostly runs of repeated stone and shelf tiles and
should compress about 4:1. That work is not done yet; the loader takes raw
images today.

---

## What the placeholder looks like

This is what `make-placeholders.py --all` puts down, and what the project
looked like before the artwork landed. A plain run no longer produces any of
it — the tileset and the AC6502 / VIC-20 screens are real now:

- A 5 × 7 font in tile groups 2–6, so score, level and labels are legible.
- Frame pieces in group 0.
- Six identical potion vials, one per colour group, plus a fireball, bolt,
  bomb and star that differ by gross silhouette — round, diagonal, round-with-
  a-fuse, radial — which is what SPEC.md §A.2 asks the real art to do.
- A white prism in group 14.
- **Diagonal hatching across tiles 128–255**, so unreplaced margin artwork is
  impossible to mistake for finished work.
