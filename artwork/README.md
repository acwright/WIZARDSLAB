artwork/
========

The editor projects the tiles and screens are drawn in. These are working
files, not build inputs — nothing here is assembled. The build reads `data/`,
and getting art from here to there is one command:

```sh
make artwork          # import; also rewrites WizardsLab.vic20
make artwork-check    # fail if data/ is behind the master
```

| File | Editor | Mode |
|---|---|---|
| `WizardsLab.tms9918` | [TMS9918-EDITOR](https://github.com/acwright/TMS9918-EDITOR) | Graphics I, 32 × 24 |
| `WizardsLab.vic20` | [VIC-EDITOR](https://github.com/acwright/VIC-EDITOR) | Hires, 22 × 23, unexpanded |

**The TMS9918 project is the master.** Draw in it and nowhere else.

The 22 × 24 panel only fits on a 24-row screen, so it is laid out there and
everything else is derived: the VIC-20's screens are the same panel with row 23
clipped, and the C64's are the master's 32 columns centred on 40 with its own
outermost margin column carried out to the edges. Both projects open by
double-click in the desktop builds.

> **`WizardsLab.vic20` is generated.** `make artwork` overwrites its charset
> and both its screens from the master. Open it to *look* at the VIC-20's
> colours; anything you draw in it is gone at the next import. Keeping the two
> in step by hand is what the import exists to avoid.

## Draw the tiles in TMS9918-EDITOR

The TMS9918 pattern format and the Commodore character format are the same
bytes — 256 characters, 8 each, MSB leftmost. **So the tileset is drawn once,
in Graphics I, and all three machines use the import verbatim.**

Graphics I is the mode to draw it in because it is the one that *enforces* the
rule the whole tile map is built on: colour is assigned per group of eight
consecutive patterns, not per cell. Tiles 64–111 are the six potion colours,
one group each, and every glyph of a colour lives inside its group. If the art
reads correctly there, it reads correctly everywhere.

`make artwork` checks the project's 32 group colours against
`data/tilecolor-tms9918.inc` and tells you if they have drifted. The `.inc` is
the authority — recolouring a group in the editor changes the preview, not the
game.

## What VIC-EDITOR is for

Checking that the six potion colours read against black in the VIC's eight
hi-res colours, and that the panel still works with row 23 gone. Its settings
already match `VIC20-16K.cfg`: character base `$1400`, screen base `$1E00`,
unexpanded, black screen and border, 22 × 23, 256 characters.

**You should not need a C64 editor at all**, and there is no C64 project. The
C64 uses the same tileset and the same derived panel; its colours come from
`data/tilecolor-c64.inc`, which is hand-authored from the spec.

## The layout the import expects

`tools/import-artwork.py` reads two screens by name, **`Play`** and **`Title`**,
both 32 × 24, and one 256-character charset. Beyond that it makes no assumption
about what is drawn — it never names a tile, so the margins, the shelf and the
field are all the artist's. What it does check:

- the charset is 256 × 8 and both screens are the right size;
- the colour groups match `data/tilecolor-tms9918.inc`;
- the well interior (panel cols 1–6, rows 4–19) and the three NEXT cells are
  empty. **Anything left in them is reported, not removed.** Sample tiles in
  the well are useful while designing and harmless in the shipped image — code
  draws over the whole well on entering PLAY — but the import says so every
  time, so it is a choice rather than an accident.

## Then

```sh
make && make smoke
```

`make smoke` boots all three headless and leaves a screenshot beside the two
Commodore cartridges.
