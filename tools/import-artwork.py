#!/usr/bin/env python3
"""
Import the drawn artwork out of artwork/ and into data/.

`artwork/WizardsLab.tms9918` is the master (artwork/README.md): the tileset is
drawn there once, and the 22 x 24 panel is laid out there because 32 x 24 is
the only one of the three grids that holds all 24 rows. This script is the one
way art gets from there to the build, and it also keeps the VIC-EDITOR project
in step so the two never drift apart by hand.

    python3 tools/import-artwork.py           # import
    python3 tools/import-artwork.py --check   # verify only, exit 1 on drift

Written:

    data/tileset.bin                    2048   charset, verbatim
    data/screen-play-ac6502.bin          768   32 x 24, verbatim
    data/screen-title-ac6502.bin         768
    artwork/WizardsLab.vic20                   charset + both screens, clipped
    data/screen-play-vic20.bin           506   22 x 23, panel cols 5-26
    data/screen-play-vic20-color.bin     506
    data/screen-title-vic20.bin          506
    data/screen-title-vic20-color.bin    506
    data/screen-play-c64.bin            1000   40 x 25, panel cols 9-30
    data/screen-play-c64-color.bin      1000
    data/screen-title-c64.bin           1000
    data/screen-title-c64-color.bin     1000

The C64 has no editor project of its own. Its screens are the master's 32
columns centred on the wider grid — (40 - 32) / 2 = 4, which lands the panel
at PANEL_X 9 — with the master's own outermost margin column carried out to
the edges and repeated once as the spare course on row 24. So the margin is
still the artist's, not this script's: nothing here names a tile.

Colours are never taken from the editor. `data/tilecolor-*.inc` is the
authority (data/README.md); this script reads the VIC table out of it and
checks the TMS9918 project's 32 groups against the AC6502 table, so a group
recoloured in the editor and not in the .inc is caught here rather than on a
real machine.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, os.pardir, "data")
ARTWORK = os.path.join(HERE, os.pardir, "artwork")

MASTER = os.path.join(ARTWORK, "WizardsLab.tms9918")
VIC_PROJECT = os.path.join(ARTWORK, "WizardsLab.vic20")

# SPEC.md 12.1 / 12.4 — one panel, three grids. PANEL_Y is 0 everywhere.
PANEL_W, PANEL_H = 22, 24
TMS_COLS, TMS_ROWS = 32, 24
TMS_PANEL_X = 5
VIC_COLS, VIC_ROWS = 22, 23          # panel row 23 falls off the bottom
C64_COLS, C64_ROWS = 40, 25          # row 24 is one spare course of margin
C64_INSET = (C64_COLS - TMS_COLS) // 2

SCREENS = ("Play", "Title")

# SPEC.md 12.2 — cells code draws over. Anything left in them by the editor is
# a design aid, not artwork, and gets flagged rather than silently shipped.
WELL_COLS = range(1, 7)
WELL_ROWS = range(4, 20)
NEXT_CELLS = [(11, 16), (11, 17), (11, 18)]


class Drift(Exception):
    pass


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------
def load_master():
    with open(MASTER) as f:
        proj = json.load(f)

    charset = proj["charsets"][0]
    if len(charset) != 256 or any(len(c) != 8 for c in charset):
        raise Drift(f"{MASTER}: charset is not 256 x 8")

    screens = {s["name"]: s["cells"] for s in proj["screens"]}
    for name in SCREENS:
        if name not in screens:
            raise Drift(f"{MASTER}: no screen named {name!r}")
        if len(screens[name]) != TMS_COLS * TMS_ROWS:
            raise Drift(f"{MASTER}: screen {name!r} is not 32 x 24")

    groups = [(g["fg"] << 4) | g["bg"] for g in proj["colors"]["groups"]]
    return charset, screens, groups, proj["modifiedAt"]


def group_table(filename):
    """The 32 group colours out of a tilecolor .inc — `.res 8, $xx` per group.

    The .inc files are per-tile tables written as one 8-byte run per colour
    group, which is the same shape the editor stores. Parsing them keeps the
    colours single-sourced instead of copied into this script.
    """
    path = os.path.join(DATA, filename)
    with open(path) as f:
        found = re.findall(r"^\s*\.(?:res\s+8,|byte)\s*\$([0-9A-Fa-f]{2})",
                           f.read(), re.M)
    if len(found) != 32:
        raise Drift(f"{path}: expected 32 group entries, found {len(found)}")
    return [int(v, 16) for v in found]


# ---------------------------------------------------------------------------
# Deriving
# ---------------------------------------------------------------------------
def tileset(charset):
    return bytes(b for tile in charset for b in tile)


def vic_screen(cells):
    """The panel on the VIC's grid: cols 5-26, rows 0-22 (SPEC 12.4)."""
    return [cells[r * TMS_COLS + TMS_PANEL_X + c]
            for r in range(VIC_ROWS) for c in range(VIC_COLS)]


def c64_screen(cells):
    """The master's 32 columns centred on the C64's 40 (SPEC 12.4).

    The inset is 4, so the panel lands at column 9. The four columns either
    side of the master and the spare row 24 take the master's own edge column
    for that row, which is the outer margin the artist drew — brick on the
    play screen, backdrop on the title.
    """
    def at(r, x):
        return cells[r * TMS_COLS + min(max(x - C64_INSET, 0), TMS_COLS - 1)]
    grid = [[at(r, x) for x in range(C64_COLS)] for r in range(TMS_ROWS)]
    grid.append([at(TMS_ROWS - 1, 0)] * C64_COLS)
    return [t for row in grid for t in row]


def color_of(cells, table):
    return [table[t >> 3] & 0x0F for t in cells]


def design_aids(cells):
    """Cells inside regions code owns that the editor left something in."""
    left = []
    for y in WELL_ROWS:
        for x in WELL_COLS:
            t = cells[y * TMS_COLS + TMS_PANEL_X + x]
            if t:
                left.append((x, y, t))
    for x, y in NEXT_CELLS:
        t = cells[y * TMS_COLS + TMS_PANEL_X + x]
        if t:
            left.append((x, y, t))
    return left


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------
def rows(values, per_line, indent):
    pad = " " * indent
    lines = [pad + ", ".join(str(v) for v in values[i:i + per_line])
             for i in range(0, len(values), per_line)]
    return ",\n".join(lines)


def vic_project(charset, screens, colors, modified):
    """Rewrite the VIC-EDITOR project around the master's art.

    Everything outside the charset and the two screens — the id, the settings
    block that matches VIC20-16K.cfg — is left exactly as the editor wrote it,
    except `modifiedAt`, which takes the master's so the project says which
    version of the master it carries. The layout below matches the editor's own
    output so reopening the project and saving it produces no diff.
    """
    with open(VIC_PROJECT) as f:
        proj = json.load(f)

    proj["modifiedAt"] = modified
    proj["charset"] = [list(c) for c in charset]
    by_name = {s["name"]: s for s in proj["screens"]}
    for name in SCREENS:
        if name not in by_name:
            raise Drift(f"{VIC_PROJECT}: no screen named {name!r}")
        by_name[name]["cells"] = screens[name]
        by_name[name]["colors"] = colors[name]

    head = {k: v for k, v in proj.items() if k not in ("charset", "screens")}
    out = json.dumps(head, indent=2)[:-2].rstrip() + ",\n"

    out += '  "charset": [\n'
    out += ",\n".join("    [" + ", ".join(str(b) for b in c) + "]"
                      for c in proj["charset"])
    out += "\n  ],\n"

    out += '  "screens": [\n'
    blocks = []
    for s in proj["screens"]:
        block = "    {\n"
        block += '      "name": %s,\n' % json.dumps(s["name"])
        block += '      "cells": [\n%s\n      ],\n' % rows(s["cells"], VIC_COLS, 8)
        block += '      "colors": [\n%s\n      ]\n' % rows(s["colors"], VIC_COLS, 8)
        block += "    }"
        blocks.append(block)
    out += ",\n".join(blocks)
    out += "\n  ]\n}\n"
    return out


def emit(path, blob, check, report):
    binary = isinstance(blob, bytes)
    mode = "rb" if binary else "r"
    old = None
    if os.path.exists(path):
        with open(path, mode) as f:
            old = f.read()
    name = os.path.relpath(path, os.path.join(HERE, os.pardir))
    size = len(blob)
    if old == blob:
        report.append(f"  {name:36s} {size:6d}  unchanged")
        return False
    if check:
        report.append(f"  {name:36s} {size:6d}  STALE")
        return True
    with open(path, "wb" if binary else "w") as f:
        f.write(blob)
    report.append(f"  {name:36s} {size:6d}  written")
    return True


# ---------------------------------------------------------------------------
def main():
    check = "--check" in sys.argv[1:]
    charset, screens, groups, modified = load_master()

    warnings = []
    expected = group_table("tilecolor-tms9918.inc")
    if groups != expected:
        bad = [i for i in range(32) if groups[i] != expected[i]]
        warnings.append(
            "colour groups differ from data/tilecolor-tms9918.inc at "
            + ", ".join("group %d (editor $%02X, .inc $%02X)"
                        % (i, groups[i], expected[i]) for i in bad)
            + " — the .inc is the authority (data/README.md)")

    aids = design_aids(screens["Play"])
    if aids:
        warnings.append(
            "play screen has %d cell(s) left in the well and preview, which "
            "code draws over: %s%s" % (
                len(aids),
                ", ".join("(%d,%d)=$%02X" % a for a in aids[:6]),
                ", ..." if len(aids) > 6 else ""))

    vic_table = group_table("tilecolor-vic20.inc")
    vic_cells = {n: vic_screen(screens[n]) for n in SCREENS}
    vic_color = {n: color_of(vic_cells[n], vic_table) for n in SCREENS}

    c64_table = group_table("tilecolor-c64.inc")
    c64_cells = {n: c64_screen(screens[n]) for n in SCREENS}
    c64_color = {n: color_of(c64_cells[n], c64_table) for n in SCREENS}

    report = []
    stale = False
    stale |= emit(os.path.join(DATA, "tileset.bin"), tileset(charset),
                  check, report)
    for name in SCREENS:
        low = name.lower()
        stale |= emit(os.path.join(DATA, f"screen-{low}-ac6502.bin"),
                      bytes(screens[name]), check, report)
        stale |= emit(os.path.join(DATA, f"screen-{low}-vic20.bin"),
                      bytes(vic_cells[name]), check, report)
        stale |= emit(os.path.join(DATA, f"screen-{low}-vic20-color.bin"),
                      bytes(vic_color[name]), check, report)
        stale |= emit(os.path.join(DATA, f"screen-{low}-c64.bin"),
                      bytes(c64_cells[name]), check, report)
        stale |= emit(os.path.join(DATA, f"screen-{low}-c64-color.bin"),
                      bytes(c64_color[name]), check, report)
    stale |= emit(VIC_PROJECT,
                  vic_project(charset, vic_cells, vic_color, modified),
                  check, report)

    print("Importing artwork/WizardsLab.tms9918:")
    print("\n".join(report))
    for w in warnings:
        print(f"  note: {w}")
    if check and stale:
        print("\ndata/ is behind the artwork. Run: make artwork")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
