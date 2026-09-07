#!/usr/bin/env python3
"""Play the same game on all three machines and check they end up identical.

`make playtest` proves the rules on the AC6502, where memory can be read and
written a byte at a time. This proves the OTHER TWO run the same code to the
same answer: one headless game each, no input, played to game over, with the
well compared cell for cell against the AC6502's board and against each other.

It is a real test of the shared logic and not just of the renderer, because a
game played to game over locks five pieces and therefore runs five match scans,
five removals and five falls. Anything in match.asm, cascade.asm or board.asm
that behaved differently on a 6502 in a Commodore would show up as a different
pile — the piece sequence is the same on all three (one seed, one LFSR), so the
pile is a function of nothing but the rules.

    make crosscheck

The AC6502 is read straight out of RAM over the debug protocol. The Commodores
are read off their screenshots with tools/read-screen.py, which is why the well
is compared and not the board: a screenshot is all VICE gives us, and the well
IS the board (SPEC 3.3 — the board byte is the tile index).

Run it from the repository root. Exits non-zero if the three disagree.
"""
import base64
import json
import os
import subprocess
import sys
import re
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

read_screen = import_module("read-screen").read_screen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT, TOKEN = 8771, "wizardslab"
DBGFILE = os.environ.get("WL_DBGFILE", "/tmp/wl.dbg")

BOARD_W, BOARD_H, STRIDE = 6, 16, 8
WELL_X, WELL_Y = 1, 4                       # Panel-relative (SPEC 12.2)
PANEL_X = {"VIC20": 0, "C64": 9}            # SPEC 12.4

# Long enough for five pieces to fall thirteen rows at level 1 and for the
# sixth spawn to be blocked. After that the game is frozen on the game-over
# screen, so anything longer lands in the same place — the check does not
# depend on stopping the three machines at the same instant.
COMMODORE_CYCLES = "90000000"
AC6502_CYCLES = 90000000                    # The same game, the same length


def ac6502_board():
    """Boot the AC6502 DEBUG cartridge, play to game over, return the board."""
    syms = {}
    for line in open(DBGFILE):
        m = re.match(r'sym\s+id=\d+,name="([^"]+)".*?,val=(0x[0-9a-fA-F]+)', line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)

    proc = subprocess.Popen(
        ["6502", "run", "--headless", "--console", "video", "--pause",
         "--cart", os.path.join(ROOT, "AC6502", "WizardsLab.crt"),
         "--debug", "--debug-port", str(PORT), "--debug-token", TOKEN,
         "--timeout", "600s", "--quiet"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def rpc(method, params=None):
        body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                           "params": params or {}}).encode()
        req = urllib.request.Request(
            f"http://127.0.0.1:{PORT}/rpc", data=body,
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {TOKEN}"})
        r = json.loads(urllib.request.urlopen(req, timeout=60).read())
        if "error" in r:
            raise RuntimeError(f"{method}: {r['error']}")
        return r["result"]

    try:
        for _ in range(80):
            try:
                rpc("session.info")
                break
            except Exception:
                time.sleep(0.25)
        # In big chunks, not a frame at a time: nothing here is timing the
        # game, it only wants the frozen well at the end of it.
        for _ in range(AC6502_CYCLES // 3000000):
            rpc("exec.runCycles", {"cycles": 3000000})
            state = rpc("mem.read", {"space": "cpu",
                                     "address": syms["GameState"],
                                     "length": 1})["data"]
            if base64.b64decode(state)[0] == 3:      # STATE_GAMEOVER
                break
        state = rpc("mem.read", {"space": "cpu", "address": syms["GameState"],
                                 "length": 1})["data"]
        board = rpc("mem.read", {"space": "cpu", "address": syms["Board"],
                                 "length": 160})["data"]
        return base64.b64decode(state)[0], base64.b64decode(board)
    finally:
        proc.terminate()


def commodore_well(plat, target, shot):
    """Run one Commodore headless to game over and read its well off the screen."""
    emu = {"VIC20": "xvic", "C64": "x64sc"}[plat]
    cart = ["-cartA", f"{target}-blk5.crt", "-cart6", f"{target}-blk3.crt"] \
        if plat == "VIC20" else ["-cart16", f"{target}.crt"]
    subprocess.run([emu, "-console", "-warp", "-limitcycles", COMMODORE_CYCLES,
                    *cart, "-exitscreenshot", shot],
                   cwd=os.path.join(ROOT, plat),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    path = os.path.join(plat, shot)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        sys.exit(f"crosscheck: {plat} wrote no screenshot — it did not boot")
    _, grid, _ = read_screen(path)
    x0 = PANEL_X[plat] + WELL_X
    return [row[x0:x0 + BOARD_W] for row in grid[WELL_Y:WELL_Y + BOARD_H]]


def board_well(board):
    return [list(board[r * STRIDE:r * STRIDE + BOARD_W]) for r in range(BOARD_H)]


def show(well):
    for r, row in enumerate(well):
        print("   %2d  " % r + " ".join("  ." if v == 0 else "%3d" % v
                                        for v in row))


def main():
    os.chdir(ROOT)
    state, board = ac6502_board()
    wells = {"AC6502": board_well(board)}
    print(f"AC6502: up to {AC6502_CYCLES} cycles, GameState {state}"
          f" ({'GAMEOVER' if state == 3 else 'still playing'})")
    for plat, target in (("VIC20", "WizardsLab"), ("C64", "WizardsLab")):
        wells[plat] = commodore_well(plat, target, "WizardsLab-crosscheck.png")
        print(f"{plat}: {COMMODORE_CYCLES} cycles, well read off the screen")

    print("\nthe well, as the AC6502 has it in RAM:")
    show(wells["AC6502"])

    fails = []
    if state != 3:
        fails.append("the AC6502 game did not reach game over — "
                     "AC6502_CYCLES is too small to compare a frozen well")
    for plat in ("VIC20", "C64"):
        if wells[plat] != wells["AC6502"]:
            fails.append(f"{plat}'s well differs from the AC6502's")
            print(f"\n{plat} has:")
            show(wells[plat])

    tiles = sum(1 for row in wells["AC6502"] for v in row if v)
    if tiles < 9:
        fails.append("fewer than three pieces landed; the run proves nothing")

    print()
    if fails:
        for f in fails:
            print("FAIL " + f)
        sys.exit(1)
    print("all three machines played the same game to the same well")


if __name__ == "__main__":
    main()
