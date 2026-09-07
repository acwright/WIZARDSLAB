#!/usr/bin/env python3
"""Play the game with a script and check what the piece actually did.

`make smoke` proves a cartridge does not hang. This proves it plays: it boots
the AC6502 DEBUG build paused, advances it one frame at a time with the
joystick held wherever the test wants it, and reads PieceCol / PieceRow /
PieceA-C and the board straight out of RAM after each frame. Nothing here
looks at a picture, so an assertion is about a number and not about a pixel.

    make DEBUG=1
    cd AC6502 && cl65 -t none -g --asm-define WL_DEBUG=1 -C AC6502-16K.cfg \
        -Wl --dbgfile,/tmp/wl.dbg -o /tmp/wl.crt WizardsLab.asm
    python3 tools/playtest.py

The -g build is only for the symbols: /tmp/wl.dbg is where every address below
comes from, so nothing has to guess at a BSS offset. The cartridge the
emulator runs is the ordinary DEBUG=1 one.

Joystick side "b" is joystick 1 (VIA port B, ReadJoystick1) — side "a" is the
other port and the game does not read it.

Run it from the repository root. Exits non-zero if anything failed.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

PORT, TOKEN = 8770, "wizardslab"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CART = os.path.join(ROOT, "AC6502", "WizardsLab.crt")
DBGFILE = os.environ.get("WL_DBGFILE", "/tmp/wl.dbg")

syms = {}
for line in open(DBGFILE):
    m = re.match(r'sym\s+id=\d+,name="([^"]+)".*?,val=(0x[0-9a-fA-F]+)', line)
    if m:
        syms[m.group(1)] = int(m.group(2), 16)

proc = subprocess.Popen(
    ["6502", "run", "--headless", "--console", "video", "--pause",
     "--cart", CART,
     "--debug", "--debug-port", str(PORT), "--debug-token", TOKEN,
     "--timeout", "600s", "--quiet"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def rpc(method, params=None):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method,
                       "params": params or {}}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/rpc", data=body,
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Bearer {TOKEN}"})
    r = json.loads(urllib.request.urlopen(req, timeout=30).read())
    if "error" in r:
        raise RuntimeError(f"{method}: {r['error']}")
    return r["result"]

def peek(name):
    d = rpc("mem.read", {"space": "cpu", "address": syms[name], "length": 1})["data"]
    return base64.b64decode(d)[0]

def poke(name, value):
    rpc("mem.write", {"space": "cpu", "address": syms[name],
                      "data": base64.b64encode(bytes([value])).decode()})

def board():
    d = rpc("mem.read", {"space": "cpu", "address": syms["Board"], "length": 160})["data"]
    return base64.b64decode(d)

for _ in range(80):
    try:
        rpc("session.info"); break
    except Exception:
        time.sleep(0.25)


def frames(n=1, held=()):
    """Advance n game frames with `held` on the stick the whole time.

    One frame is one trip round GameLoop, and the stop is at the top of it —
    the main loop about to wait for vblank, with the previous frame's logic
    finished. Running a fixed number of CYCLES instead would drift: a frame
    whose logic overruns vblank (a cascade scan is most of a frame on its own)
    takes two video frames, and a peek timed by cycles then lands in the
    middle of the game's own work and reads a state it is halfway through
    writing. Counting loop iterations is also what the game's own timers
    count, which is what SPEC 14's durations are in.
    """
    rpc("input.joystick", {"side": "b", "buttons": list(held)})
    for _ in range(n):
        rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})

fails = []
def check(label, got, want):
    ok = got == want
    if not ok:
        fails.append(label)
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: got {got}, want {want}")

def shift_frames(direction, n=34):
    """Hold one direction from a fresh press and report which frames moved."""
    frames(3)                                   # release, so the press is fresh
    moved, prev = [], peek("PieceCol")
    for f in range(1, n + 1):
        frames(1, [direction])
        now = peek("PieceCol")
        if now != prev:
            moved.append(f)
            prev = now
    return moved, prev

# Get into play. DEBUG skips the title, so a piece is already falling.
frames(30)
check("GameState is PLAY", peek("GameState"), 1)
check("PlayState is FALLING", peek("PlayState"), 0)
check("spawn column", peek("PieceCol"), 2)

print("\nDAS left (SPEC 11.3: fire at once, then 12 frames, then every 4)")
moved, col = shift_frames("left")
check("frames that moved", moved, [1, 13])       # 2 -> 1 -> 0; the
                                                 #   repeat at 17 hits the wall
check("stopped at column 0", col, 0)

print("\nDAS right, the same delays, out to the other wall")
moved, col = shift_frames("right")
check("frames that moved", moved, [1, 13, 17, 21, 25])
check("stopped at column 5", col, 5)

print("\nrotate: (A,B,C) -> (B,C,A), edge only — no auto-repeat")
frames(3)
a, b, c = peek("PieceA"), peek("PieceB"), peek("PieceC")
frames(1, ["up"])
check("A becomes B", peek("PieceA"), b)
check("B becomes C", peek("PieceB"), c)
check("C becomes A", peek("PieceC"), a)
frames(40, ["up"])
check("40 more frames of held UP change nothing",
      (peek("PieceA"), peek("PieceB"), peek("PieceC")), (b, c, a))
frames(3)
frames(1, ["up"])
check("released and pressed again does rotate", peek("PieceA"), c)

print("\nrotate reverse on FIRE: (A,B,C) -> (C,A,B)")
frames(3)
a, b, c = peek("PieceA"), peek("PieceB"), peek("PieceC")
frames(1, ["a"])
check("A becomes C", peek("PieceA"), c)
check("B becomes A", peek("PieceB"), a)
check("C becomes B", peek("PieceC"), b)

print("\nsoft drop: 3 frames a row against gravity's 48 at level 1")
frames(3)
r0 = peek("PieceRow")
frames(12, ["down"])
check("four rows in 12 frames", peek("PieceRow") - r0, 4)
r0 = peek("PieceRow")
frames(48)
check("gravity alone is one row in 48 frames", peek("PieceRow") - r0, 1)

print("\nlock delay: 16 frames on the floor, and a move resets it 4 times")
while peek("PlayState") == 0:                   # drop to the floor
    frames(1, ["down"])
check("landing enters PLAY_LOCKING", peek("PlayState"), 1)
frames(15)
check("still locking after 15 frames", peek("PlayState"), 1)
frames(1)
check("locked on the 16th", peek("PlayState"), 5)   # PLAY_ARE

print("\n...and the reset allowance is spent, not unlimited")
while peek("PlayState") != 1:                   # next piece, down to the floor
    frames(1, ["down"])
resets = 0
for _ in range(6):                              # try to reset six times
    frames(1, ["left"] if resets % 2 == 0 else ["right"])
    frames(2)
    if peek("PlayState") == 1:
        resets += 1
check("LockResets stops at LOCK_RESET_MAX", peek("LockResets"), 4)

print("\nthe pile, and the floor under it")
frames(900)
bd = board()
check("floor sentinels intact", all(v == 255 for v in bd[128:160]), True)
check("side sentinels intact",
      all(bd[r * 8 + 6] == 255 and bd[r * 8 + 7] == 255 for r in range(20)), True)
occupied = sorted(i for i, v in enumerate(bd[:128]) if v not in (0, 255))
print("  occupied cells:", occupied)
check("pieces have stacked up", len(occupied) >= 6, True)
check("every occupied cell is a legal tile",
      all(0x40 <= bd[i] <= 0x77 for i in occupied), True)


# =============================================================================
#   P3 — matching, removal, gravity and chains
# =============================================================================
#   The board is written straight into RAM and the cascade machinery kicked
#   into a scan, so a test is a board and an expected board rather than a
#   sequence of moves that has to arrive at one. Every colour group is one
#   tile apart (SPEC 4.2), so the tiles below are potions unless a test wants
#   a glyph.

RED, YELLOW, GREEN, CYAN, BLUE, PURPLE = 0x40, 0x48, 0x50, 0x58, 0x60, 0x68
WILD = 0x70                                     # The prism, colour group 6

PLAY_FALLING, PLAY_LOCKING, PLAY_GRAVITY, PLAY_ARE = 0, 1, 4, 5
WELL_X, WELL_Y = 1, 4                           # Panel-relative (SPEC 12.2)


def set_board(cells):
    """Write a whole board: {(row, col): tile}, sentinels included."""
    b = bytearray(160)
    for r in range(16):
        b[r * 8 + 6] = b[r * 8 + 7] = 0xFF      # The two wall columns
    for i in range(16 * 8, 160):
        b[i] = 0xFF                             # The four wall rows
    for (r, c), t in cells.items():
        b[r * 8 + c] = t
    rpc("mem.write", {"space": "cpu", "address": syms["Board"],
                      "data": base64.b64encode(bytes(b)).decode()})


def tiles(bd):
    """{(row, col): tile} for everything the playfield holds."""
    return {(i // 8, i % 8): bd[i] for i in range(128) if bd[i] not in (0, 0xFF)}


def kick():
    """Send the cascade into a scan with no piece involved.

    PLAY_GRAVITY with the row cursor spent and nothing moved is exactly the
    state PlayGravity settles out of, so the next frame runs cascade step 1
    against whatever the board holds — the same entry PieceLock uses, minus
    the piece.
    """
    poke("PieceDirty", 0)
    poke("ChainStep", 0)                        # PlayGravity increments it
    poke("GravIdx", 0xFF)
    poke("GravMoved", 0)
    poke("AnimTimer", 1)
    poke("PlayState", PLAY_GRAVITY)


def redraw():
    """Put the whole well on the screen, the way leaving PAUSE does.

    A board written straight into RAM is not on the screen: nothing marked it.
    RedrawIdx is the cursor RenderBoard sets, and it feeds the dirty ring at
    whatever rate the flush drains it (D12), so wait for it to run out.
    """
    poke("RedrawIdx", 0)
    for _ in range(30):
        frames(1)
        if peek("RedrawIdx") == 0xFF:
            return
    raise RuntimeError("the board redraw never finished")


def cascade(cells, limit=400):
    """Run one whole cascade over `cells`; return what it left and what it did.

    RunCount is read every frame and the first non-zero one kept: it belongs
    to whichever step is running, and the last step of a cascade always finds
    nothing and leaves it at zero.
    """
    set_board(cells)
    kick()
    runs, used = 0, 0
    while used < limit:
        frames(1)
        used += 1
        if runs == 0:
            runs = peek("RunCount")
        if peek("PlayState") == PLAY_ARE:
            break
    return tiles(board()), runs, peek("ChainStep"), used


def resting(left):
    """True if nothing is floating: every tile is on the floor or on a tile."""
    return all(r == 15 or (r + 1, c) in left for (r, c) in left)


print("\nmatching: three in a line clears, in all four directions (SPEC 6.1)")
for name, cells in (
        ("horizontal", {(15, 0): RED, (15, 1): RED, (15, 2): RED}),
        ("vertical",   {(13, 0): YELLOW, (14, 0): YELLOW, (15, 0): YELLOW}),
        ("diagonal",   {(13, 0): GREEN, (14, 1): GREEN, (15, 2): GREEN}),
        ("anti-diag",  {(13, 2): CYAN, (14, 1): CYAN, (15, 0): CYAN})):
    left, runs, chain, used = cascade(cells)
    check(f"{name} three clears", left, {})
    check(f"{name} is one run", runs, 1)

print("\n...and two is not a run")
left, runs, chain, used = cascade({(15, 0): RED, (15, 1): RED})
check("two of a colour survive", left, {(15, 0): RED, (15, 1): RED})
check("no runs found", runs, 0)
check("the cascade stops at step 1", chain, 1)

print("\na run of four is ONE run of four, not two of three (SPEC 6.1)")
left, runs, chain, used = cascade({(15, c): RED for c in range(4)})
check("all four go", left, {})
check("counted once", runs, 1)

print("\ncolour matches, glyph does not (SPEC 4.1)")
left, runs, chain, used = cascade(
    {(15, 0): RED + 0, (15, 1): RED + 1, (15, 2): RED + 4})   # potion, fireball, star
check("a red potion, a red fireball and a red star are one run", left, {})
check("one run", runs, 1)

print("\na hole breaks the run, not the row")
left, runs, chain, used = cascade(
    {(15, 0): BLUE, (15, 2): RED, (15, 3): RED, (15, 4): RED})
check("the run past the hole is still found", (15, 2) in left, False)
check("the lone tile is untouched", left, {(15, 0): BLUE})

print("\noverlapping runs clear once and count twice (SPEC 6.1)")
left, runs, chain, used = cascade(
    {(15, 0): RED, (15, 1): RED, (15, 2): RED, (13, 0): RED, (14, 0): RED})
check("all five cells go", left, {})
check("two runs, sharing a corner", runs, 2)

print("\nwildcards (SPEC 6.3)")
left, runs, chain, used = cascade({(15, 0): RED, (15, 1): RED, (15, 2): WILD})
check("a prism closes a red run", left, {})

left, runs, chain, used = cascade({(15, 0): WILD, (15, 1): WILD, (15, 2): WILD})
check("three prisms are a run of their own", left, {})

left, runs, chain, used = cascade(
    {(15, 0): RED, (15, 1): RED, (15, 2): WILD, (13, 2): BLUE, (14, 2): BLUE})
check("one prism closes a red run AND a blue one", left, {})
check("both runs counted", runs, 2)

print("\ngravity: what was above a clear falls into it (SPEC 8 step 8)")
left, runs, chain, used = cascade(
    {(15, 0): RED, (15, 1): RED, (15, 2): RED, (14, 0): YELLOW, (13, 0): GREEN})
check("the stack landed on the floor", left, {(15, 0): YELLOW, (14, 0): GREEN})

print("\n...one row every FALL_FRAMES, and not faster (SPEC 14)")
set_board({(15, 0): RED, (15, 1): RED, (15, 2): RED, (11, 0): YELLOW})
kick()
moved, was = [], 11
for f in range(1, 40):
    frames(1)
    here = [r for (r, c), t in tiles(board()).items() if t == YELLOW]
    if here and here[0] != was:
        moved.append(f)
        was = here[0]
check("it fell all four rows", was, 15)
check("two frames a row, every row",
      [b - a for a, b in zip(moved, moved[1:])], [2, 2, 2])

print("\ncascades: a fall that makes a new run keeps going (SPEC 8 step 9)")
left, runs, chain, used = cascade(
    {(15, 0): RED, (15, 1): RED, (15, 2): RED,          # goes first...
     (14, 0): YELLOW, (13, 1): YELLOW, (14, 2): YELLOW})  # ...leaving three
check("the second run cleared too", left, {})
check("chain reached 2 steps", chain, 3)                # settles on the third

print("\nthe real path: a locking piece completes a run")
set_board({(15, 3): PURPLE, (15, 4): PURPLE})
poke("PieceCol", 5)
poke("PieceRow", 13)
poke("PieceA", GREEN)
poke("PieceB", CYAN)
poke("PieceC", PURPLE)                          # ...which lands on row 15
poke("LockResets", 0)
poke("LockTimer", 1)
poke("PlayState", PLAY_LOCKING)
frames(1)
check("the lock ran a cascade step", peek("RunCount"), 1)
used = 1
while peek("PlayState") != PLAY_ARE and used < 400:
    frames(1)
    used += 1
left = tiles(board())
check("the run the piece completed is gone, its other two cells fell",
      left, {(14, 5): GREEN, (15, 5): CYAN})

print("\na heavy fall reaches the SCREEN, not just the board")
#   The dirty ring holds 64 cells and a falling well can change more than that
#   in one row, so BoardGravityStep stops when the ring is full and resumes
#   next frame (D12). This is the test that says so: a full well, a clear at
#   the bottom of it, and then the VDP's own name table read back and compared
#   with the board. A dropped mark is a cell that never gets marked again, so
#   it would show here and nowhere else.
VRAM_NAMES, PANEL_X, PANEL_Y = 0x1400, 5, 0
full = {}
palette = [RED, YELLOW, GREEN, CYAN, BLUE, PURPLE]
for r in range(2, 16):
    for c in range(6):
        full[(r, c)] = palette[(r + 2 * c) % 6]     # No run anywhere in it
for c in range(6):
    full[(15, c)] = RED                             # ...except this one, which
                                                    #   drops all six columns
set_board(full)
redraw()                                            # The planted board is only
                                                    #   in RAM until this
kick()
used = 0
while used < 400:
    frames(1)
    used += 1
    if peek("PlayState") == PLAY_ARE:
        break
vram = base64.b64decode(rpc("mem.read", {"space": "vram", "address": VRAM_NAMES,
                                         "length": 32 * 24})["data"])
bd = board()
screen = {}
for r in range(16):
    for c in range(6):
        v = vram[(PANEL_Y + WELL_Y + r) * 32 + PANEL_X + WELL_X + c]
        if v:
            screen[(r, c)] = v
print(f"  ({used} frames for a full well to clear a row, fall and settle)")
check("the cascade terminated", used < 400, True)
check("nothing floats", resting(tiles(bd)), True)
check("no cell of the well differs between the board and the screen",
      sorted(set(screen.items()) ^ set(tiles(bd).items())), [])

print("\nnothing is ever left floating, and the walls stay put")
left, runs, chain, used = cascade({
    (10, 0): RED,    (10, 1): YELLOW, (10, 2): GREEN, (10, 3): CYAN,
    (11, 0): YELLOW, (11, 1): GREEN,  (11, 2): CYAN,  (11, 3): RED,
    (12, 0): GREEN,  (12, 1): CYAN,   (12, 2): RED,   (12, 3): YELLOW,
    (13, 0): RED,    (13, 1): RED,    (13, 2): RED,   (13, 3): BLUE,
    (14, 0): BLUE,   (14, 1): PURPLE, (14, 2): BLUE,  (14, 3): PURPLE,
    (15, 0): PURPLE, (15, 1): BLUE,   (15, 2): PURPLE, (15, 3): BLUE})
check("the cascade terminated", used < 400, True)
check("nothing floats", resting(left), True)
bd = board()
check("floor sentinels intact", all(v == 255 for v in bd[128:160]), True)
check("side sentinels intact",
      all(bd[r * 8 + 6] == 255 and bd[r * 8 + 7] == 255 for r in range(20)), True)

print()
print(f"{len(fails)} FAILED: {fails}" if fails else "all checks passed")
proc.terminate()
sys.exit(1 if fails else 0)
