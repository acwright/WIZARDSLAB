#!/usr/bin/env python3
"""Build the itch.io page kit: the cover art, the gallery images and the zip.

    make itch

Everything here is made out of the game's own pixels. The cover and the
reagent card are drawn by blitting `data/tileset.bin` through
`data/tilecolor-c64.inc`, the same two files the C64 cartridge includes, so
the letterforms on the cover are the letterforms in the game and the six
potion colours are the six the machine actually draws. Nothing is redrawn in
an image editor and there is no second copy of the artwork to keep in sync:
redraw a tile in TMS9918-EDITOR, `make artwork`, `make itch`, and the cover
changes with it.

The palette is not pepto. It is sampled from `docs/c64-play.png` — the
committed screenshot — because the point of the cover is to match the pictures
next to it on the page, and those come out of VICE. See PALETTE below.

Outputs, all under itch/:

    images/cover.png           630x500, the size itch.io asks for
    images/background.png      a seamless brick tile for the page background
    images/screenshot-*.png    the docs/ screenshots, recentred on their own
                               character grid and scaled to each machine's
                               true pixel aspect
    images/reagent-card.png    what the five reagents do, in the game's font
    WizardsLab-cartridges.zip  the four ROMs, a README and the licence

itch/ITCH-PAGE.txt — every field of the itch.io form, the theme colours and
what each image is for — sits beside them and is hand-written. Nothing here
overwrites it.

Run from the repository root. Needs Pillow.
"""
import os
import re
import sys
import zipfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "itch")
IMAGES = os.path.join(OUT, "images")

# -----------------------------------------------------------------------------
#   The palette
# -----------------------------------------------------------------------------
#   Sampled from docs/c64-play.png and docs/c64-title.png rather than taken
#   from a palette file: those screenshots sit on the itch page beside this
#   cover, and a cover whose red is not the screenshots' red looks like a
#   different game. Twelve of the sixteen appear in the two PNGs. Brown (9)
#   and grey (12) never do — no tile the shipped screens draw is either — so
#   they are interpolated from their neighbours and are only ever reachable
#   through the magic field (SPEC A.3).
PALETTE = {
    0:  (0x00, 0x00, 0x00),   1:  (0xFF, 0xFF, 0xFF),
    2:  (0xA9, 0x47, 0x64),   3:  (0x8A, 0xE6, 0xCB),
    4:  (0x9A, 0x58, 0xB9),   5:  (0x72, 0xBD, 0x67),
    6:  (0x19, 0x49, 0xB4),   7:  (0xFF, 0xF8, 0x8D),
    8:  (0x97, 0x40, 0x00),   9:  (0x6A, 0x4C, 0x00),
    10: (0xE6, 0x86, 0xA3),   11: (0x62, 0x62, 0x62),
    12: (0x94, 0x94, 0x94),   13: (0xC6, 0xFF, 0xBA),
    14: (0x62, 0x91, 0xFB),   15: (0xCD, 0xCD, 0xCD),
}

# Tiles, by the names SPEC Appendix A gives them.
BLANK, SHELF, BRICK = 0, 126, 127
FONT_DIGIT_0, FONT_LETTER_A = 16, 26
FONT_DOT, FONT_TIMES, FONT_BANG, FONT_TILDE = 52, 53, 54, 55
POTION = {"red": 64, "yellow": 72, "green": 80,
          "cyan": 88, "blue": 96, "purple": 104}
GLYPH_POTION, GLYPH_FIRE, GLYPH_BOLT, GLYPH_BOMB, GLYPH_STAR = 0, 1, 2, 3, 4
PRISM = 112


def tile_char(c):
    """One character to its tile, the same translation strings.inc does."""
    if c == " ":
        return BLANK
    if "0" <= c <= "9":
        return FONT_DIGIT_0 + ord(c) - ord("0")
    if "A" <= c <= "Z":
        return FONT_LETTER_A + ord(c) - ord("A")
    return {".": FONT_DOT, "x": FONT_TIMES,
            "!": FONT_BANG, "~": FONT_TILDE}[c]


def load_tileset(path):
    """256 tiles, 8 bytes each, MSB leftmost — the format all three share."""
    raw = open(path, "rb").read()
    assert len(raw) == 2048, f"{path}: expected 2048 bytes, got {len(raw)}"
    return [raw[i * 8:i * 8 + 8] for i in range(256)]


def load_tilecolor(path):
    """Parse a tilecolor-*.inc into a 256-entry list of colour numbers."""
    out = []
    for line in open(path):
        line = line.split(";")[0]
        m = re.match(r"\s*\.res\s+(\d+)\s*,\s*\$([0-9A-Fa-f]+)", line)
        if m:
            out += [int(m.group(2), 16)] * int(m.group(1))
            continue
        m = re.match(r"\s*\.byte\s+(.+)", line)
        if m:
            for v in m.group(1).split(","):
                v = v.strip()
                if v.startswith("$"):
                    out.append(int(v[1:], 16))
                elif v.isdigit():
                    out.append(int(v))
    assert len(out) == 256, f"{path}: parsed {len(out)} entries, wanted 256"
    return out


TILES = load_tileset(os.path.join(ROOT, "data", "tileset.bin"))
TILECOLOR = load_tilecolor(os.path.join(ROOT, "data", "tilecolor-c64.inc"))


def blit(img, tile, x, y, scale, color=None):
    """Draw one tile at (x, y) in pixels, scale x, in its own colour."""
    rgb = PALETTE[TILECOLOR[tile] if color is None else color]
    px = img.load()
    rows = TILES[tile]
    for ry in range(8):
        bits = rows[ry]
        for rx in range(8):
            if not bits & (0x80 >> rx):
                continue
            for sy in range(scale):
                for sx in range(scale):
                    px[x + rx * scale + sx, y + ry * scale + sy] = rgb


def blit_text(img, s, x, y, scale, color=1):
    for i, c in enumerate(s):
        blit(img, tile_char(c), x + i * 8 * scale, y, scale, color)
    return len(s) * 8 * scale


def centred(img, s, y, scale, color=1):
    w = len(s) * 8 * scale
    blit_text(img, s, (img.width - w) // 2, y, scale, color)
    return w


def fill_tile(img, tile, x0, y0, x1, y1, scale, color=None):
    """Tile a rectangle, clipped to it — the wall and the shelf are one tile."""
    step = 8 * scale
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            cell = Image.new("RGB", (step, step), PALETTE[0])
            blit(cell, tile, 0, 0, scale, color)
            img.paste(cell.crop((0, 0, min(step, x1 - x), min(step, y1 - y))),
                      (x, y))


# -----------------------------------------------------------------------------
#   cover.png — 630 x 500, the size itch.io asks for
# -----------------------------------------------------------------------------
def cover():
    W, H = 630, 500
    img = Image.new("RGB", (W, H), PALETTE[0])

    # The wall the laboratory is built in — the play screen's own margin tile.
    wall = 8 * 3 * 2                                # two bricks at scale 3
    fill_tile(img, BRICK, 0, 0, wall, H, 3)
    fill_tile(img, BRICK, W - wall, 0, W, H, 3)
    # A shelf top and bottom, the plank the panel stands on (SPEC A.3).
    fill_tile(img, SHELF, 0, 0, W, 24, 3)
    fill_tile(img, SHELF, 0, H - 24, W, H, 3)

    centred(img, "WIZARDS", 86, 8)                  # 7 x 64 = 448 px
    centred(img, "LAB", 168, 8)

    # One of every glyph, one per colour: what the game is made of, in a row.
    row = [(POTION["red"] + GLYPH_FIRE), (POTION["yellow"] + GLYPH_BOLT),
           (POTION["green"] + GLYPH_BOMB), (POTION["cyan"] + GLYPH_STAR),
           (POTION["blue"] + GLYPH_POTION), PRISM]
    scale, step = 6, 8 * 6
    x = (W - len(row) * step) // 2
    for i, t in enumerate(row):
        blit(img, t, x + i * step, 268, scale)
    blit(img, FONT_TILDE, x - step, 268, scale, 1)
    blit(img, FONT_TILDE, x + len(row) * step, 268, scale, 1)

    centred(img, "MATCH THREE BY COLOUR", 344, 3, 15)
    centred(img, "SET THE REAGENTS OFF", 376, 3, 15)

    centred(img, "AC6502 . VIC 20 . C64", 428, 3, 7)

    img.save(os.path.join(IMAGES, "cover.png"))
    return "cover.png", img.size


# -----------------------------------------------------------------------------
#   background.png — the page's own wall
# -----------------------------------------------------------------------------
def background():
    """A seamless brick square for itch's page background. The tile repeats in
    both axes by construction, so any size works; 96 px is four bricks at the
    scale the cover uses, which reads as texture rather than as pattern."""
    step = 8 * 3
    img = Image.new("RGB", (step * 4, step * 4), PALETTE[0])
    fill_tile(img, BRICK, 0, 0, img.width, img.height, 3)
    # Knock it back: the page is a background, not a wall in front of the text.
    img = Image.blend(img, Image.new("RGB", img.size, PALETTE[0]), 0.55)
    img.save(os.path.join(IMAGES, "background.png"))
    return "background.png", img.size


# -----------------------------------------------------------------------------
#   reagent-card.png — the one rule worth knowing, as a picture
# -----------------------------------------------------------------------------
def reagent_card():
    rows = [
        (POTION["red"] + GLYPH_FIRE,   "FIREBALL", "CLEARS EVERY TILE OF ITS COLOUR"),
        (POTION["yellow"] + GLYPH_BOLT, "BOLT",    "CLEARS ITS WHOLE ROW AND COLUMN"),
        (POTION["green"] + GLYPH_BOMB, "BOMB",     "CLEARS THE 3 X 3 AROUND IT"),
        (POTION["cyan"] + GLYPH_STAR,  "STAR",     "DOUBLES THE CASCADE SCORE TO x8"),
        (PRISM,                        "PRISM",    "WILD ~ MATCHES ANY COLOUR"),
    ]
    W, H = 960, 640
    img = Image.new("RGB", (W, H), PALETTE[0])
    fill_tile(img, SHELF, 0, 0, W, 24, 3)
    fill_tile(img, SHELF, 0, H - 24, W, H, 3)

    centred(img, "THE ARCANE REAGENTS", 56, 4)
    centred(img, "TILES MATCH ON COLOUR", 120, 2, 15)
    centred(img, "THE GLYPH DECIDES WHAT HAPPENS WHEN THEY CLEAR", 152, 2, 15)

    y = 212
    for tile, name, effect in rows:
        blit(img, tile, 72, y - 8, 6)
        blit_text(img, name, 160, y, 3, TILECOLOR[tile])
        blit_text(img, effect, 384, y, 2, 15)
        y += 72

    centred(img, "A REAGENT CAUGHT IN A BLAST GOES OFF TOO", H - 64, 2, 7)
    img.save(os.path.join(IMAGES, "reagent-card.png"))
    return "reagent-card.png", img.size


# -----------------------------------------------------------------------------
#   The screenshots — recentred, aspect-corrected, upscaled
# -----------------------------------------------------------------------------
#   docs/ holds them at the emulators' own output size, and neither the framing
#   nor the proportions survive being put on a page as they are.
#
#   THE FRAMING. What VICE writes is its whole visible frame, and the machine's
#   screen does not sit in the middle of it — the VIC-20's in particular is up
#   and to the left, with the border eating the rest. That is the emulator's
#   captured region, not the cartridge's centring (the VIC-20 build sets its
#   own $9000/$9001, P0/D8). So the crop here is taken from the CHARACTER GRID
#   outward: tools/read-screen.py finds the grid origin by fitting the tileset,
#   and the frame is that grid plus one cell of border on all four sides. The
#   picture is then centred by construction on every machine, and any border
#   the emulator happened to leave is gone rather than lopsided.
#
#   THE PROPORTIONS. Neither machine has square pixels. The VIC-I's NTSC dot
#   clock is 4 x the 1.02 MHz system clock and the VIC-II's is 8 x, so a
#   VIC-20 pixel is exactly TWICE as wide as a C64 pixel, and a C64 pixel is
#   itself 0.75 as wide as it is tall on a 4:3 set. Hence PAR 0.75 and 1.5, and
#   hence the same (3, 4) here for both: xvic already doubles horizontally and
#   x64sc does not (read-screen.py's xscale), so that one pair of factors lands
#   each machine on its own aspect AND leaves the two at a common scale. An 8 x
#   8 cell comes out 24 x 32 on the C64 and 48 x 32 on the VIC-20 — which is
#   the real difference between the two machines' screens, 22 fat columns
#   against 40 thin ones, and the thing a pair of square-pixel shots hides.
#
#   Nearest neighbour and integer factors throughout: these are 8 x 8 tiles and
#   they should still look like 8 x 8 tiles.
SCALE = (3, 4)
BORDER_CELLS = 1

SHOTS = [
    ("c64-play.png",    "screenshot-1-c64-play.png",    "C64"),
    ("c64-title.png",   "screenshot-2-c64-title.png",   "C64"),
    ("vic20-play.png",  "screenshot-3-vic20-play.png",  "VIC20"),
    ("vic20-title.png", "screenshot-4-vic20-title.png", "VIC20"),
]


def screenshots():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    read_screen = __import__("importlib").import_module("read-screen")

    out = []
    for src, dst, plat in SHOTS:
        cfg = read_screen.PLATFORMS[plat]
        path = os.path.join(ROOT, "docs", src)
        _, _, (ox, oy) = read_screen.read_screen(path, plat)

        cw = 8 * cfg["xscale"]
        bx, by = BORDER_CELLS * cw, BORDER_CELLS * 8
        w, h = cfg["cols"] * cw + 2 * bx, cfg["rows"] * 8 + 2 * by

        # Paste rather than crop, so a frame that runs off the edge of the
        # emulator's own picture is padded with backdrop instead of shifting
        # the grid back off centre.
        im = Image.open(path).convert("RGB")
        framed = Image.new("RGB", (w, h), PALETTE[0])
        framed.paste(im, (bx - ox, by - oy))

        sx, sy = SCALE
        framed = framed.resize((w * sx, h * sy), Image.NEAREST)
        framed.save(os.path.join(IMAGES, dst))
        out.append((dst, framed.size))
    return out


# -----------------------------------------------------------------------------
#   The download
# -----------------------------------------------------------------------------
CARTS = [
    ("AC6502/WizardsLab.crt",       "WizardsLab-AC6502.crt"),
    ("C64/WizardsLab.crt",          "WizardsLab-C64.crt"),
    ("VIC20/WizardsLab-blk5.crt",   "WizardsLab-VIC20-blk5.crt"),
    ("VIC20/WizardsLab-blk3.crt",   "WizardsLab-VIC20-blk3.crt"),
]

ZIP_README = """\
WIZARDS LAB
===========

A falling-block match-three game for the AC6502, the Commodore VIC-20 and the
Commodore 64. One game, three 16 KB cartridges, written in 6502 assembly.

    https://github.com/acwright/WIZARDSLAB


WHAT IS IN THIS ZIP
-------------------

    WizardsLab-AC6502.crt        32 KB   AC6502
    WizardsLab-C64.crt           16 KB   Commodore 64
    WizardsLab-VIC20-blk5.crt     8 KB   Commodore VIC-20, code
    WizardsLab-VIC20-blk3.crt     8 KB   Commodore VIC-20, artwork

The VIC-20 needs BOTH of its files. Its 16 KB is two 8 KB blocks at different
addresses, so it ships as two ROMs -- BLK5 holds the code, BLK3 the artwork,
and the game will not boot without either.

These are RAW ROM IMAGES despite the .crt extension -- not VICE .crt container
files. VICE reads them fine with the flags below, which say what to do with
them. Dragging one onto a VICE window instead will fail, because that path
expects the container format. Convert with cartconv if you need one:

    cartconv -t normal -i WizardsLab-C64.crt -o WizardsLab-vice.crt


RUNNING IT
----------

VICE is at https://vice-emu.sourceforge.io/ ; the AC6502 emulator is at
https://github.com/acwright/6502-EMULATOR

    Commodore 64    x64sc -cart16 WizardsLab-C64.crt
    Commodore VIC-20    xvic -cartA WizardsLab-VIC20-blk5.crt \\
                             -cart6 WizardsLab-VIC20-blk3.crt
    AC6502          6502 run --cart WizardsLab-AC6502.crt


BURNING IT
----------

    AC6502      28C256 EEPROM or 27C256 EPROM
    VIC-20      two 27C64s, or one 27C128. One ROM per block: BLK5 at $A000,
                BLK3 at $6000. Most VIC-20 cartridge boards socket the two
                separately.
    C64         27C128 (16 KB). Pull EXROM and GAME both low so ROML $8000
                and ROMH $A000 map together.


CONTROLS
--------

                    Joystick        Keyboard
    Rotate          Up              W  or  cursor up
    Soft drop       Down            S  or  cursor down
    Move            Left / Right    A / D  or  cursor left / right
    Rotate back     Fire            Q  or  SPACE
    Pause           --              P
    Start           Fire            SPACE  or  RETURN

Joysticks are Atari 2600 compatible -- port 2 on the C64.


HOW IT PLAYS
------------

Pieces are vertical stacks of three vials in six colours. Steer them into the
well, rotate to reorder the three colours, and line up three or more of a
colour -- horizontally, vertically or diagonally. They react and vanish, and
whatever sat above them drops into new arrangements.

Among the potions fall the arcane reagents. THE ONE RULE WORTH KNOWING is that
tiles match on COLOUR, and the glyph on a tile only decides what happens when
it clears. A red potion, a red fireball and a red star are all "red" -- so
every reagent is aimed exactly like the potion it resembles, and you choose
when to set it off.

    FIREBALL    destroys every tile of its own colour, board wide
    BOLT        clears its whole row and column, up to 21 cells
    BOMB        clears the 3 x 3 around it
    STAR        doubles the whole cascade's score, up to x8
    PRISM       wildcard -- matches any colour

A reagent caught in another reagent's blast goes off too. That is where the
game lives.

Every 30 tiles removed advances a level; the fall speed ramps to level 16 and
holds. High score lives in RAM for the session -- it is a cartridge, so power
off is the end of it.


LICENCE
-------

MIT. See LICENSE. Source, and the full design document, at
https://github.com/acwright/WIZARDSLAB
"""


def zip_carts(version):
    name = f"WizardsLab-cartridges-{version}.zip"
    path = os.path.join(OUT, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, dst in CARTS:
            z.write(os.path.join(ROOT, src), dst)
        z.writestr("README.txt", ZIP_README)
        z.write(os.path.join(ROOT, "LICENSE"), "LICENSE.txt")
    return name, os.path.getsize(path)


def main():
    os.makedirs(IMAGES, exist_ok=True)
    version = (sys.argv[1] if len(sys.argv) > 1 else "v1.0")

    made = [cover(), background(), reagent_card()] + screenshots()
    for name, size in made:
        print(f"  itch/images/{name:32} {size[0]} x {size[1]}")
    name, size = zip_carts(version)
    print(f"  itch/{name:39} {size:,} bytes")


if __name__ == "__main__":
    main()
