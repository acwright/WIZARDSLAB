data/
=====

Artwork and lookup tables. One rule keeps the two apart:

| Extension | Origin | Edit it how |
|---|---|---|
| **`.bin`** | `make artwork` | Never edit. Redraw and re-import. |
| **`.inc`** | SPEC.md | Hand-edit. Never overwritten by an import. |

The assembly pulls the binaries in with `.incbin`, so replacing artwork is a
file copy — there is no label to keep in sync and nothing to paste.

**Every `.bin` here is real artwork, and every one of them is generated.** They
all come out of `artwork/WizardsLab.tms9918` — the master — by way of
`tools/import-artwork.py`:

```sh
make artwork          # master -> data/, and -> artwork/WizardsLab.vic20
make artwork-check    # exit 1 if anything here is behind the master
```

`tools/make-placeholders.py` is the bootstrap generator, for starting this
directory from nothing. It owns no file here: a plain run writes nothing, and
`--all` overwrites the real art with synthetic shapes. Its value now is as a
second, executable statement of the tile map — if it and SPEC.md Appendix A
disagree, one of them is wrong.

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
too and the other two are derived from it.

---

## Files

### Tiles

| File | Bytes | Source |
|---|---|---|
| `tileset.bin` | 2048 | The master's charset, verbatim |
| `tilecolor-tms9918.inc` | 32 | SPEC.md §4.3 — VDP colour table, `(fg << 4) \| bg` |
| `tilecolor-vic20.inc` | 256 | SPEC.md §4.3 — tile → colour RAM, values 0–7 only |
| `tilecolor-c64.inc` | 256 | SPEC.md §4.3 — tile → colour RAM, values 0–15 |

The two CBM tables are identical for tiles 0–127 except where the VIC has no
equivalent colour (there is no gray, so group 1 — the dim frame — renders the
same white as group 0 there), and diverge freely in groups 16–31.

> TMS9918-EDITOR can also export the colour table, but **do not** use it here —
> `tilecolor-tms9918.inc` is the authority and is what the AC6502 build
> includes. Set the group colours in the editor so the art previews correctly;
> `make artwork` will tell you if the two have drifted apart. If they ever
> disagree, SPEC.md wins.

### Screens

Each screen is exported whole: panel frame, labels, and the margin either side
of it, as one name-table image. Code only draws *over* it — the well, the score
and level digits, the preview, and the message band. Nothing else on screen is
drawn by code, which is why the layouts live here.

| File | Bytes | Derived how |
|---|---|---|
| `screen-play-ac6502.bin` | 768 | The master's 32 × 24 screen, verbatim |
| `screen-title-ac6502.bin` | 768 | as above |
| `screen-play-vic20.bin` | 506 | Master cols 5–26, rows 0–22 |
| `screen-play-vic20-color.bin` | 506 | The above through `tilecolor-vic20.inc` |
| `screen-title-vic20.bin` | 506 | as above |
| `screen-title-vic20-color.bin` | 506 | as above |
| `screen-play-c64.bin` | 1000 | Master centred on 40 × 25, edge column carried out |
| `screen-play-c64-color.bin` | 1000 | The above through `tilecolor-c64.inc` |
| `screen-title-c64.bin` | 1000 | as above |
| `screen-title-c64-color.bin` | 1000 | as above |

The two segments are separate files because the game blits them as two images.

**Panel offsets.** The 22 × 24 panel is horizontally centred on each machine
and **top aligned on all three** (`PANEL_Y = 0`):

| Platform | Screen | Panel origin | Vertical fit |
|---|---|---|---|
| AC6502 | 32 × 24 | column 5, row 0 | exact |
| VIC-20 | 22 × 23 | column 0, row 0 — the screen *is* the panel | panel row 23 is clipped |
| C64 | 40 × 25 | column 9, row 0 | screen row 24 is one spare course of margin |

### What the C64 derivation does

The C64 has no editor project. Its screens are the master's 32 columns placed
at an inset of `(40 − 32) / 2 = 4`, which lands the panel at column 9. The four
columns either side, and the spare row 24, take **the master's own edge column
for that row** — so the play screen extends its brick and the title screen
extends its black. Nothing in the importer names a tile; widen the wall in
TMS9918-EDITOR and the C64 widens with it.

### Size note

The C64's four screen images are 4000 bytes of a 16 KB cartridge, and the title
screen only ever appears on one state. The margin is two tiles (SPEC §12.5), so
these images are almost entirely long runs and should RLE well past the 4:1 the
ROM budget assumes. The loader takes raw images, and at 43% of 16 KB nothing
needs otherwise yet.

---

## What the placeholder is

`make-placeholders.py --all` puts down a complete, coherent tile map that is
legible and nothing more — enough for the game to be developed against with no
art at all:

- A 5 × 7 font in tile groups 2–6, so score, level and labels read.
- Frame pieces in group 0, copied into group 1 as the dim weight.
- Six identical potion vials, one per colour group, plus a fireball, bolt,
  bomb and star that differ by gross silhouette — round, diagonal, round-with-
  a-fuse, radial — which is what SPEC.md §A.2 asks of the real art.
- A white prism in group 14 and a petrified set in group 15.
- Diagonal hatching across tiles 128–255, matching the real artwork, because
  that range is the title screen's magic field (SPEC.md §13.1).
