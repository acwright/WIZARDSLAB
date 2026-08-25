#!/usr/bin/env python3
"""
Generate the placeholder artwork binaries in data/.

Everything this script writes is PLACEHOLDER and is meant to be overwritten by
a Binary export from TMS9918-EDITOR or VIC-EDITOR. It exists so the project
builds and runs on all three machines before any real art is drawn.

    python3 tools/make-placeholders.py

See data/README.md for which editor export replaces which file.
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, os.pardir, "data")

# ---------------------------------------------------------------------------
# Tile map (SPEC.md Appendix A)
# ---------------------------------------------------------------------------
BLANK = 0
BAR_H, BAR_V = 1, 2
COR_TL, COR_TR, COR_BL, COR_BR = 3, 4, 5, 6

FONT_BASE = 16                       # group 2..6, 40 glyphs
FONT_ORDER = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.x!-"

COLOR_BASE = 0x40                    # potion colour groups start here
GLYPH_POTION, GLYPH_FIRE, GLYPH_BOLT = 0, 1, 2
GLYPH_BOMB, GLYPH_STAR, GLYPH_GLOW = 3, 4, 6
WILD_BASE = 0x70
STONE = 0x78                         # group 15, game-over petrify


def tile_for(ch):
    return FONT_BASE + FONT_ORDER.index(ch.upper())


# ---------------------------------------------------------------------------
# 5x7 placeholder font, rows given as 5-bit strings, drawn into bits 6..2
# ---------------------------------------------------------------------------
FONT5x7 = {
    "0": "01110 10001 10011 10101 11001 10001 01110",
    "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111",
    "3": "11111 00010 00100 00010 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010",
    "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110",
    "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110",
    "9": "01110 10001 10001 01111 00001 00010 01100",
    "A": "01110 10001 10001 11111 10001 10001 10001",
    "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110",
    "D": "11100 10010 10001 10001 10001 10010 11100",
    "E": "11111 10000 10000 11110 10000 10000 11111",
    "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111",
    "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110",
    "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101",
    "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110",
    "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110",
    "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001",
    "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100",
    "Z": "11111 00001 00010 00100 01000 10000 11111",
    ".": "00000 00000 00000 00000 00000 01100 01100",
    "x": "00000 10001 01010 00100 01010 10001 00000",
    "!": "00100 00100 00100 00100 00100 00000 00100",
    "-": "00000 00000 00000 11111 00000 00000 00000",
}


def glyph5x7(spec):
    """Five-bit rows -> eight pattern bytes, centred in bits 6..2."""
    rows = [int(r, 2) << 2 for r in spec.split()]
    return bytes(rows + [0])


# ---------------------------------------------------------------------------
# 8x8 placeholder shapes, one character per pixel: '#' set, '.' clear
# ---------------------------------------------------------------------------
def shape(*rows):
    return bytes(int(r.replace(".", "0").replace("#", "1"), 2) for r in rows)


SHAPES = {
    "blank":  shape("........", "........", "........", "........",
                    "........", "........", "........", "........"),
    "bar_h":  shape("........", "........", "########", "########",
                    "########", "########", "........", "........"),
    "bar_v":  shape("..####..", "..####..", "..####..", "..####..",
                    "..####..", "..####..", "..####..", "..####.."),
    "cor_tl": shape("........", "........", "..######", "..######",
                    "..####..", "..####..", "..####..", "..####.."),
    "cor_tr": shape("........", "........", "######..", "#####...",
                    "..####..", "..####..", "..####..", "..####.."),
    "cor_bl": shape("..####..", "..####..", "..####..", "..####..",
                    "..######", "..######", "........", "........"),
    "cor_br": shape("..####..", "..####..", "..####..", "..####..",
                    "######..", "#####...", "........", "........"),
    "joint":  shape("..####..", "..####..", "########", "########",
                    "########", "########", "..####..", "..####.."),
    # Potion: a stoppered vial. The baseline every colour group is built on.
    "potion": shape("..####..", "..####..", ".######.", "########",
                    "########", "########", ".######.", "..####.."),
    # Fireball: the only round glyph.
    "fire":   shape("...##...", "..####..", ".######.", "########",
                    "########", ".######.", "..####..", "........"),
    # Bolt: the only diagonal glyph.
    "bolt":   shape("....###.", "...###..", "..###...", ".######.",
                    "..###...", ".###....", "###.....", "##......"),
    # Bomb: round like the fireball, so it sits lower and carries a fuse.
    "bomb":   shape("......##", ".....##.", "..###...", ".#####..",
                    "#######.", "#######.", ".#####..", "..###..."),
    # Star: the only radially symmetric glyph.
    "star":   shape("...##...", "...##...", "########", ".######.",
                    "..####..", ".##..##.", "##....##", "........"),
    # Glow: the potion silhouette, filled out. "Brighter", not "different".
    "glow":   shape("########", "########", "########", "########",
                    "########", "########", "########", "########"),
    # Prism: faceted diamond, always white.
    "prism":  shape("...##...", "..####..", ".###.##.", "###...##",
                    "###...##", ".###.##.", "..####..", "...##..."),
    "stone":  shape("########", "#..##..#", "########", "##..##..",
                    "########", "..##..##", "########", "#..##..#"),
    "hatch":  shape("#...#...", ".#...#..", "..#...#.", "...#...#",
                    "#...#...", ".#...#..", "..#...#.", "...#...#"),
    "box":    shape("########", "#......#", "#......#", "#......#",
                    "#......#", "#......#", "#......#", "########"),
    "shard1": shape("#..#..#.", ".#...#..", "#..#..#.", "..#..#..",
                    "#..#..#.", ".#...#..", "#..#..#.", "..#..#.."),
    "shard2": shape("........", "..#..#..", ".#....#.", "........",
                    "........", ".#....#.", "..#..#..", "........"),
}


def build_tileset():
    """2048 bytes: 256 patterns x 8, laid out per SPEC.md Appendix A."""
    tiles = [SHAPES["blank"]] * 256

    # Group 0 (0-7) — well frame, white
    for i, name in enumerate(["blank", "bar_h", "bar_v", "cor_tl",
                              "cor_tr", "cor_bl", "cor_br", "joint"]):
        tiles[i] = SHAPES[name]

    # Group 1 (8-15) — accents, reserved for art
    for i in range(8, 16):
        tiles[i] = SHAPES["blank"]

    # Groups 2-6 (16-55) — font
    for i, ch in enumerate(FONT_ORDER):
        tiles[FONT_BASE + i] = glyph5x7(FONT5x7[ch])

    # Group 7 (56-63) — VFX
    tiles[56] = SHAPES["shard1"]   # shatter 1
    tiles[57] = SHAPES["shard2"]   # shatter 2
    tiles[58] = SHAPES["glow"]     # blast
    tiles[59] = SHAPES["bar_h"]    # beam H
    tiles[60] = SHAPES["bar_v"]    # beam V
    tiles[61] = SHAPES["joint"]    # beam cross
    tiles[62] = SHAPES["star"]     # sparkle
    tiles[63] = SHAPES["bolt"]     # arrow

    # Groups 8-13 (64-111) — the six potion colours, identical patterns
    for color in range(6):
        base = COLOR_BASE + color * 8
        tiles[base + GLYPH_POTION] = SHAPES["potion"]
        tiles[base + GLYPH_FIRE] = SHAPES["fire"]
        tiles[base + GLYPH_BOLT] = SHAPES["bolt"]
        tiles[base + GLYPH_BOMB] = SHAPES["bomb"]
        tiles[base + GLYPH_STAR] = SHAPES["star"]
        tiles[base + GLYPH_GLOW] = SHAPES["glow"]

    # Group 14 (112-119) — wild
    tiles[WILD_BASE + GLYPH_POTION] = SHAPES["prism"]
    tiles[WILD_BASE + GLYPH_GLOW] = SHAPES["glow"]

    # Group 15 (120-127) — stone / rubble
    tiles[STONE + 0] = SHAPES["stone"]
    tiles[STONE + 1] = SHAPES["shard1"]

    # Groups 16-31 (128-255) — artwork. Hatched so unreplaced art is obvious.
    for i in range(128, 256):
        tiles[i] = SHAPES["hatch"]

    return b"".join(tiles)


# ---------------------------------------------------------------------------
# Static screens (SPEC.md section 12)
# ---------------------------------------------------------------------------
PANEL_W, PANEL_H = 22, 23
PLATFORMS = {
    # name        cols rows  panel_x panel_y  colour_ram
    "ac6502": (32, 24, 5, 0, False),
    "vic20":  (22, 23, 0, 0, True),
    "c64":    (40, 25, 9, 1, True),
}


class Panel:
    """A 22x23 grid in panel-relative coordinates."""

    def __init__(self):
        self.cells = [[BLANK] * PANEL_W for _ in range(PANEL_H)]

    def put(self, x, y, tile):
        if 0 <= x < PANEL_W and 0 <= y < PANEL_H:
            self.cells[y][x] = tile

    def text(self, x, y, s):
        for i, ch in enumerate(s):
            if ch != " ":
                self.put(x + i, y, tile_for(ch))

    def frame(self, x0, y0, x1, y1):
        for x in range(x0 + 1, x1):
            self.put(x, y0, BAR_H)
            self.put(x, y1, BAR_H)
        for y in range(y0 + 1, y1):
            self.put(x0, y, BAR_V)
            self.put(x1, y, BAR_V)
        self.put(x0, y0, COR_TL)
        self.put(x1, y0, COR_TR)
        self.put(x0, y1, COR_BL)
        self.put(x1, y1, COR_BR)


def play_panel():
    p = Panel()
    p.text(5, 0, "WIZARDS LAB")          # title rule
    p.frame(0, 2, 7, 19)                 # well: interior cols 1-6, rows 3-18
    p.text(9, 3, "SCORE")
    p.text(9, 6, "HIGH")
    p.text(9, 9, "LEVEL")
    p.text(9, 12, "NEXT")
    p.frame(10, 13, 12, 17)              # next viewer, tile column 11
    return p


def title_panel():
    p = Panel()
    p.frame(0, 0, 21, 22)
    p.text(5, 4, "WIZARDS LAB")
    p.text(6, 10, "PRESS FIRE")
    p.text(4, 18, "PLACEHOLDER ART")
    return p


def render(panel, platform):
    cols, rows, px, py, _ = PLATFORMS[platform]
    grid = [[BLANK] * cols for _ in range(rows)]
    for y in range(PANEL_H):
        for x in range(PANEL_W):
            gy, gx = py + y, px + x
            if 0 <= gy < rows and 0 <= gx < cols:
                grid[gy][gx] = panel.cells[y][x]
    return bytes(t for row in grid for t in row)


WHITE = 1


def write(name, blob):
    path = os.path.join(DATA, name)
    with open(path, "wb") as f:
        f.write(blob)
    print(f"  {name:34s} {len(blob):6d} bytes")


def main():
    os.makedirs(DATA, exist_ok=True)
    print("Writing placeholder data:")
    write("tileset.bin", build_tileset())

    for screen, panel in (("play", play_panel()), ("title", title_panel())):
        for platform, (cols, rows, _, _, has_color) in PLATFORMS.items():
            write(f"screen-{screen}-{platform}.bin", render(panel, platform))
            if has_color:
                write(f"screen-{screen}-{platform}-color.bin",
                      bytes([WHITE]) * (cols * rows))


if __name__ == "__main__":
    main()
