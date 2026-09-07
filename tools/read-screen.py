#!/usr/bin/env python3
"""Recover a name table from an emulator screenshot.

`make smoke` leaves a PNG beside each Commodore cartridge. Looking at one tells
you the game drew *something*; this tells you exactly which tile is in which
cell, which is what an exit criterion can actually be checked against.

Cells are matched by their 8x8 bitmap against data/tileset.bin. The potion
groups share one bitmap per glyph and differ only in colour, so where a bitmap
is ambiguous the cell's foreground colour picks between the candidates, via the
platform's data/tilecolor-*.inc table.

    python3 tools/read-screen.py C64/WizardsLab-screenshot.png
    python3 tools/read-screen.py VIC20/WizardsLab-screenshot.png

The grid origin is found by search, so the emulator's border does not matter.
Run it from the repository root. Requires Pillow.
"""
import re
import sys
from collections import Counter

from PIL import Image

# Screenshot geometry per platform. xscale is how many screen pixels the
# emulator writes per source pixel horizontally — xvic doubles, x64sc does not.
PLATFORMS = {
    "VIC20": dict(cols=22, rows=23, xscale=2, colors="data/tilecolor-vic20.inc"),
    "C64":   dict(cols=40, rows=25, xscale=1, colors="data/tilecolor-c64.inc"),
}

# VICE's default (pepto) C64 palette.
PEPTO = {
    0: (0, 0, 0),        1: (255, 255, 255), 2: (129, 51, 56),    3: (117, 206, 200),
    4: (142, 60, 151),   5: (86, 172, 77),   6: (46, 44, 155),    7: (237, 241, 113),
    8: (142, 80, 41),    9: (85, 56, 0),     10: (196, 108, 113), 11: (74, 74, 74),
    12: (123, 123, 123), 13: (154, 226, 155), 14: (112, 109, 235), 15: (178, 178, 178),
}
# The VIC-I's hues, sampled from xvic's own output rather than a palette file,
# because that is what the screenshots are actually made of. Only 0-7 exist as
# a foreground in hi-res text mode (SPEC 2.1, C.2), so the table stops there
# and a cell can never be matched to a colour the VIC-20 cannot draw.
VIC = {0: (0, 0, 0),        1: (255, 255, 255), 2: (146, 68, 23),
       3: (174, 253, 255),  4: (185, 95, 124),  5: (135, 225, 196),
       6: (68, 54, 150),    7: (255, 255, 180)}


def read_tilecolor(path):
    """Parse a tilecolor-*.inc into a 256-entry list."""
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
    return out


def nearest(rgb, palette):
    return min(palette, key=lambda i: sum((a - b) ** 2 for a, b in zip(rgb, palette[i])))


def load_ink(path):
    """The image as rows of (isInk, rgb), which is all the matching needs."""
    im = Image.open(path).convert("RGB")
    px = im.load()
    ink, color = [], []
    for y in range(im.height):
        ink.append([px[x, y] != (0, 0, 0) for x in range(im.width)])
        color.append([px[x, y] for x in range(im.width)])
    return ink, color, im.width, im.height


def cell(ink, color, x0, y0, xscale):
    bits, fg = bytearray(), Counter()
    for r in range(8):
        row_i, row_c = ink[y0 + r], color[y0 + r]
        b = 0
        for c in range(8):
            x = x0 + c * xscale
            if row_i[x]:
                b |= 0x80 >> c
                fg[row_c[x]] += 1
        bits.append(b)
    return bytes(bits), (fg.most_common(1)[0][0] if fg else None)


def find_origin(ink, color, w, h, cols, rows, xscale, known):
    """The top-left of the character grid, by best fit against the tileset.

    Only origins that put a cell edge on the first inked pixel are tried, which
    is one cell's worth of candidates in each axis rather than the whole image.
    """
    cw, ch = 8 * xscale, 8
    left = min((x for y in range(h) for x in range(w) if ink[y][x]), default=0)
    top = min((y for y in range(h) if any(ink[y])), default=0)
    best = None
    for oy in {max(0, min(top - i, h - rows * ch)) for i in range(ch)}:
        for ox in {max(0, min(left - i * xscale, w - cols * cw)) for i in range(8)}:
            score = 0
            for r in range(rows):
                for c in range(cols):
                    bits = cell(ink, color, ox + c * cw, oy + r * ch, xscale)[0]
                    if any(bits):                 # An all-black region matches
                        score += 1 if bits in known else -4   # the blank tile
            if best is None or score > best[0]:   # everywhere, so only cells
                best = (score, ox, oy)            # with ink in them count
    return best[1], best[2]


def read_screen(path):
    """Recover a name table from a screenshot: rows of tile numbers, -1 unknown.

    Also importable — tools/crosscheck.py compares the well of one machine's
    screen against another's.
    """
    plat = next((p for p in PLATFORMS if p in path), None)
    if plat is None:
        sys.exit("read-screen: cannot tell which platform %r is; the path must "
                 "name one of %s" % (path, ", ".join(PLATFORMS)))
    cfg = PLATFORMS[plat]

    tiles = open("data/tileset.bin", "rb").read()
    bypat = {}
    for i in range(256):
        bypat.setdefault(tiles[i * 8:(i + 1) * 8], []).append(i)
    colortab = read_tilecolor(cfg["colors"])
    palette = VIC if plat == "VIC20" else PEPTO

    ink, color, w, h = load_ink(path)
    ox, oy = find_origin(ink, color, w, h, cfg["cols"], cfg["rows"],
                         cfg["xscale"], bypat)

    grid = []
    for r in range(cfg["rows"]):
        out = []
        for c in range(cfg["cols"]):
            bits, fg = cell(ink, color, ox + c * 8 * cfg["xscale"],
                            oy + r * 8, cfg["xscale"])
            cand = bypat.get(bits)
            if not cand:
                out.append(-1)
            elif len(cand) == 1 or fg is None:
                out.append(cand[0])
            else:
                want = nearest(fg, palette)
                match = [t for t in cand if colortab[t] == want]
                out.append(match[0] if match else cand[0])
        grid.append(out)
    return plat, grid, (ox, oy)


def main():
    path = sys.argv[1]
    plat, grid, origin = read_screen(path)
    cols = PLATFORMS[plat]["cols"]
    print("# %s  %d x %d, grid origin (%d,%d)"
          % (path, cols, PLATFORMS[plat]["rows"], origin[0], origin[1]))
    print("#    " + " ".join("%3d" % c for c in range(cols)))
    unknown = 0
    for r, row in enumerate(grid):
        unknown += sum(1 for v in row if v < 0)
        print("%2d  " % r + " ".join("  ?" if v < 0 else "%3d" % v for v in row))
    if unknown:
        print("# %d cell(s) matched no tile — the grid origin may be wrong"
              % unknown, file=sys.stderr)


if __name__ == "__main__":
    main()
