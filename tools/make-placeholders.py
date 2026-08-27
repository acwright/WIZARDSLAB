#!/usr/bin/env python3
"""
Generate the placeholder artwork binaries in data/.

Everything this script writes is PLACEHOLDER. It exists so the project builds
and runs on all three machines before any real art is drawn, and it is how the
project was bootstrapped.

    python3 tools/make-placeholders.py            # nothing — see below
    python3 tools/make-placeholders.py --all      # everything, from scratch

**Every file in data/ is real artwork.** The tileset and all six screens,
the C64's included, come out of artwork/WizardsLab.tms9918 by way of
tools/import-artwork.py. So a plain run writes nothing at all, and --all
overwrites the real art with synthetic shapes — it is for starting over.

What this script earns its keep for is being a second, executable statement of
the tile map: the group assignments in build_tileset() track SPEC.md Appendix
A, so if the two disagree one of them is wrong.

See data/README.md for which import replaces which file.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, os.pardir, "data")
ARTWORK = os.path.join(HERE, os.pardir, "artwork")

# ---------------------------------------------------------------------------
# Tile map (SPEC.md Appendix A)
# ---------------------------------------------------------------------------
BLANK = 0
BAR_H, BAR_V = 1, 2
COR_TL, COR_TR, COR_BL, COR_BR = 3, 4, 5, 6

FONT_BASE = 16                       # group 2..6, 40 glyphs
FONT_ORDER = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.x!~"

COLOR_BASE = 0x40                    # potion colour groups start here
GLYPH_POTION, GLYPH_FIRE, GLYPH_BOLT = 0, 1, 2
GLYPH_BOMB, GLYPH_STAR, GLYPH_GLOW = 3, 4, 6
WILD_BASE = 0x70
PETRIFY_BASE = 0x78                  # group 15: petrified glyph +0..+4,
WALL_SHELF, WALL_BRICK = 0x7E, 0x7F  #   then the shelf and the brick fill


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
    ".": "00000 00000 01100 01100 00000 00000 00000",   # centred, not a period
    "x": "00000 10001 01010 00100 01010 10001 00000",
    "!": "00100 00100 00100 00100 00100 00000 00100",
    "~": "00000 00000 01001 10110 00000 00000 00000",
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
    # Removal: one ring opening outward. Frame 0 is the centred dot the font
    # carries as its full stop, so the sequence is dot -> ring -> ring -> gone.
    "ring1":  shape("........", "........", "...##...", "..#..#..",
                    "..#..#..", "...##...", "........", "........"),
    "ring2":  shape("........", "..#..#..", ".#....#.", "........",
                    "........", ".#....#.", "..#..#..", "........"),
    "ring3":  shape(".#....#.", "#......#", "........", "........",
                    "........", "........", "#......#", ".#....#."),
    "arrow_u": shape("...##...", "..####..", ".######.", "...##...",
                     "...##...", "...##...", "...##...", "...##..."),
    "arrow_d": shape("...##...", "...##...", "...##...", "...##...",
                     "...##...", ".######.", "..####..", "...##..."),
    "arrow_l": shape("........", "..#.....", ".##.....", "########",
                     "########", ".##.....", "..#.....", "........"),
    "arrow_r": shape("........", ".....#..", ".....##.", "########",
                     "########", ".....##.", ".....#..", "........"),
    # The PAUSE wash. Drawn once and used twice: white in group 0, grey in 1.
    "wash":   shape("........", ".#......", "...#..#.", "..#.#...",
                    "...#....", ".....#..", ".#..#.#.", ".....#.."),
    "shelf":  shape("........", "........", "########", "#.####.#",
                    "###.####", "........", "........", "........"),
}


def build_tileset():
    """2048 bytes: 256 patterns x 8, laid out per SPEC.md Appendix A."""
    tiles = [SHAPES["blank"]] * 256

    # Groups 0 and 1 (0-15) — the frame, twice. Byte for byte the same eight
    # slots, white in group 0 and grey in group 1, so frame_tile + 8 is the
    # quieter twin of any piece of frame (SPEC A.3).
    for i, name in enumerate(["blank", "bar_h", "bar_v", "cor_tl",
                              "cor_tr", "cor_bl", "cor_br", "wash"]):
        tiles[i] = tiles[i + 8] = SHAPES[name]

    # Groups 2-6 (16-55) — font
    for i, ch in enumerate(FONT_ORDER):
        tiles[FONT_BASE + i] = glyph5x7(FONT5x7[ch])

    # Group 7 (56-63) — VFX
    tiles[56] = SHAPES["ring1"]    # removal 1
    tiles[57] = SHAPES["ring2"]    # removal 2
    tiles[58] = SHAPES["ring3"]    # removal 3
    tiles[59] = SHAPES["bar_h"]    # beam H
    tiles[60] = SHAPES["bar_v"]    # beam V
    tiles[61] = SHAPES["joint"]    # beam cross
    tiles[62] = SHAPES["arrow_u"]
    tiles[63] = SHAPES["arrow_d"]

    # Groups 8-13 (64-111) — the six potion colours, identical patterns
    for color in range(6):
        base = COLOR_BASE + color * 8
        tiles[base + GLYPH_POTION] = SHAPES["potion"]
        tiles[base + GLYPH_FIRE] = SHAPES["fire"]
        tiles[base + GLYPH_BOLT] = SHAPES["bolt"]
        tiles[base + GLYPH_BOMB] = SHAPES["bomb"]
        tiles[base + GLYPH_STAR] = SHAPES["star"]
        tiles[base + GLYPH_GLOW] = SHAPES["glow"]

    # Group 14 (112-119) — the prism: four rotation frames, two blip-out
    # frames, then the two remaining arrows. There is no glow slot here; the
    # prism does not use the glow-then-shatter path (SPEC A.3).
    for i in range(4):
        tiles[WILD_BASE + i] = SHAPES["prism"]
    tiles[WILD_BASE + 4] = SHAPES["ring2"]     # blip out 1
    tiles[WILD_BASE + 5] = SHAPES["ring1"]     # blip out 2
    tiles[WILD_BASE + 6] = SHAPES["arrow_l"]
    tiles[WILD_BASE + 7] = SHAPES["arrow_r"]

    # Group 15 (120-127) — the petrified glyph set, then the wall
    for i, name in enumerate(["potion", "fire", "bolt", "bomb", "star"]):
        tiles[PETRIFY_BASE + i] = SHAPES[name]
    tiles[WALL_SHELF] = SHAPES["shelf"]
    tiles[WALL_BRICK] = SHAPES["stone"]

    # Groups 16-31 (128-255) — the title screen's magic field, one hatch in
    # sixteen colours. Nothing else reads these.
    for i in range(128, 256):
        tiles[i] = SHAPES["hatch"]

    return b"".join(tiles)


# ---------------------------------------------------------------------------
# Static screens (SPEC.md section 12)
# ---------------------------------------------------------------------------
# SPEC.md 12.1 — the panel is 22 x 24 and PANEL_Y is 0 everywhere. The VIC-20
# clips panel row 23; the C64 has one spare screen row below the panel.
PANEL_W, PANEL_H = 22, 24
MARGIN_BEVEL = 2                     # speckle columns between margin and panel
PLATFORMS = {
    # name        cols rows  panel_x panel_y  colour_ram
    "ac6502": (32, 24, 5, 0, False),
    "vic20":  (22, 23, 0, 0, True),
    "c64":    (40, 25, 9, 0, True),
}


class Panel:
    """A 22x24 grid in panel-relative coordinates."""

    def __init__(self, backdrop=BLANK):
        self.cells = [[backdrop] * PANEL_W for _ in range(PANEL_H)]

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

    def banner(self, y, s):
        """Centre a string in a full-width band, ~~ ornaments either side."""
        body = "~~ " + s + " ~~"
        self.text((PANEL_W - len(body)) // 2, y, body)


def play_panel():
    """SPEC.md 12.2, exactly."""
    p = Panel(BLANK)
    p.banner(1, "WIZARDS LAB")
    p.frame(0, 3, 7, 20)                 # well: interior cols 1-6, rows 4-19
    p.frame(9, 3, 21, 6)                 # SCORE
    p.text(13, 4, "SCORE")
    p.text(12, 5, "0000000")
    p.frame(9, 8, 21, 12)                # HIGH
    p.text(11, 9, "HIGHSCORE")
    p.text(12, 10, "0010000")
    p.text(14, 11, "L01")
    p.frame(9, 14, 13, 20)               # NEXT, unlabelled; tile column 11
    p.frame(15, 14, 21, 20)              # LEVEL
    p.text(16, 15, "LEVEL")
    p.text(18, 17, "0")                  # tens
    p.text(18, 18, "1")                  # units
    p.banner(22, "PAUSED")
    return p


def title_panel():
    p = Panel(BLANK)
    p.frame(0, 1, 21, 22)
    p.text(5, 4, "WIZARDS LAB")
    p.text(6, 10, "PRESS FIRE")
    p.text(4, 18, "PLACEHOLDER ART")
    return p


def panel_from_artwork(name):
    """The drawn panel, lifted out of the TMS9918 project.

    The panel is defined once, in TMS9918-EDITOR, on the one machine whose
    screen is exactly 24 rows tall (SPEC.md 12.1). Everything else is that
    same 22 x 24 block on a different grid — including the C64 screens this
    script still owns. Falls back to the synthesized placeholder when the
    project file is not there.
    """
    path = os.path.join(ARTWORK, "WizardsLab.tms9918")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        proj = json.load(f)
    px = PLATFORMS["ac6502"][2]
    for screen in proj["screens"]:
        if screen["name"].lower() != name:
            continue
        cells = screen["cells"]
        p = Panel()
        p.cells = [cells[r * 32 + px: r * 32 + px + PANEL_W]
                   for r in range(PANEL_H)]
        return p
    return None


def render(panel, platform):
    """Panel on the screen grid, margins filled with the wall (SPEC 12.5)."""
    cols, rows, px, py, _ = PLATFORMS[platform]
    grid = [[WALL_BRICK] * cols for _ in range(rows)]
    for y in range(rows):
        for x in range(cols):
            near = (px - MARGIN_BEVEL <= x < px
                    or px + PANEL_W <= x < px + PANEL_W + MARGIN_BEVEL)
            if near:
                grid[y][x] = BLANK
    for y in range(PANEL_H):
        for x in range(PANEL_W):
            gy, gx = py + y, px + x
            if 0 <= gy < rows and 0 <= gx < cols:
                grid[gy][gx] = panel.cells[y][x]
    return grid


def flat(grid):
    return bytes(t for row in grid for t in row)


# Tile group -> colour RAM, kept in step with data/tilecolor-*.inc
VIC_GROUP = [1, 1, 1, 1, 1, 1, 1, 1, 2, 7, 5, 3, 6, 4, 1, 2,
             1, 2, 5, 7, 6, 5, 2, 3, 7, 6, 4, 5, 2, 1, 1, 1]
C64_GROUP = [1, 15, 1, 1, 1, 1, 1, 1, 2, 7, 5, 3, 6, 4, 1, 2,
             15, 9, 12, 8, 11, 13, 10, 3, 7, 14, 4, 5, 2, 1, 15, 1]


def colors(grid, platform):
    table = VIC_GROUP if platform == "vic20" else C64_GROUP
    return bytes(table[t >> 3] for row in grid for t in row)


def write(name, blob):
    path = os.path.join(DATA, name)
    with open(path, "wb") as f:
        f.write(blob)
    print(f"  {name:34s} {len(blob):6d} bytes")


# Files tools/import-artwork.py owns. Only --all overwrites them, and today
# that is every file this script can write.
REAL_ART = ("tileset.bin", "screen-play-ac6502.bin", "screen-title-ac6502.bin",
            "screen-play-vic20.bin", "screen-play-vic20-color.bin",
            "screen-title-vic20.bin", "screen-title-vic20-color.bin",
            "screen-play-c64.bin", "screen-play-c64-color.bin",
            "screen-title-c64.bin", "screen-title-c64-color.bin")


def main():
    everything = "--all" in sys.argv[1:]
    os.makedirs(DATA, exist_ok=True)

    def guarded(name, blob):
        if name in REAL_ART and not everything:
            print(f"  {name:34s} skipped — real artwork, see data/README.md")
        else:
            write(name, blob)

    print("Writing placeholder data:")
    guarded("tileset.bin", build_tileset())

    for screen, fallback in (("play", play_panel), ("title", title_panel)):
        panel = panel_from_artwork(screen) or fallback()
        for platform, (_, _, _, _, has_color) in PLATFORMS.items():
            grid = render(panel, platform)
            guarded(f"screen-{screen}-{platform}.bin", flat(grid))
            if has_color:
                guarded(f"screen-{screen}-{platform}-color.bin",
                        colors(grid, platform))


if __name__ == "__main__":
    main()
