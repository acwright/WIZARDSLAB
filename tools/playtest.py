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
import atexit
import base64
import json
import os
import re
import socket
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

def require_free_port(port):
    """Fail loudly if something is already listening on the debug port.

    A stale emulator left over from an earlier run keeps the port, the one
    started here dies with EADDRINUSE into /dev/null, and every rpc call below
    then talks to the OTHER machine — a different cartridge, hours of cycles
    in. It looks exactly like the game under test behaving impossibly, and it
    cost a whole debugging session once already.
    """
    s = socket.socket()
    s.settimeout(0.5)
    try:
        s.connect(("127.0.0.1", port))
    except OSError:
        return                                  # nothing listening — good
    finally:
        s.close()
    sys.exit(f"port {port} already has a listener — an emulator from an "
             f"earlier run is still alive. Kill it (lsof -nP -iTCP:{port}) "
             f"and try again.")


require_free_port(PORT)

proc = subprocess.Popen(
    ["6502", "run", "--headless", "--console", "video", "--pause",
     "--cart", CART,
     "--debug", "--debug-port", str(PORT), "--debug-token", TOKEN,
     "--timeout", "600s", "--quiet"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

atexit.register(proc.terminate)         # A test that raises used to leave the
                                        #   emulator holding the debug port,
                                        #   and the NEXT run then refused to
                                        #   start (require_free_port above).
                                        #   One broken assertion cost two runs.

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
COLOR_MASK, GLYPH_MASK = 0xF8, 0x07             # SPEC 4.2

PLAY_FALLING, PLAY_LOCKING, PLAY_GRAVITY, PLAY_ARE = 0, 1, 4, 5
PLAY_GLOW, PLAY_SHATTER = 2, 3
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


def kick(chain=1):
    """Send the cascade into a scan with no piece involved.

    PLAY_GRAVITY with the row cursor spent and nothing moved is exactly the
    state PlayGravity settles out of, so the next frame runs cascade step 1
    against whatever the board holds — the same entry PieceLock uses, minus
    the piece.

    `chain` is the depth the first step should run at. SPEC 9.1 and 9.2 pay by
    chain depth, and reaching depth 2 by playing means a first step whose
    gravity happens to make a second run — which is a whole extra board to get
    right for every value being checked. Planting the counter tests the tables
    and not the author's board design.
    """
    poke("PieceDirty", 0)
    poke("ChainStep", chain - 1)                 # PlayGravity increments it
    poke("GravIdx", 0xFF)
    poke("GravMoved", 0)
    poke("AnimTimer", 1)
    poke("CascadeLo", 0)                        # CascadeBegin would have done
    poke("CascadeMid", 0)                       #   these; entering at the
    poke("CascadeHi", 0)                        #   gravity end skips it, and a
    poke("StarCount", 0)                        #   stale accumulator would be
    poke("PlayState", PLAY_GRAVITY)             #   banked by the next settle


def redraw():
    """Put the whole well on the screen, the way leaving PAUSE does.

    A board written straight into RAM is not on the screen: nothing marked it.
    RedrawIdx is the cursor RenderBoard sets, and it feeds the dirty ring at
    whatever rate the flush drains it (D12), so wait for the cursor to run out
    AND for the ring behind it to empty. The cursor finishes a frame early —
    the last 24 cells it queued are still waiting — and a test that starts
    reading the screen there sees the well one frame before it is drawn.
    """
    poke("RedrawIdx", 0)
    for _ in range(30):
        frames(1)
        if peek("RedrawIdx") == 0xFF and peek("DirtyCount") == 0:
            return                              # Cursor spent AND ring drained
    raise RuntimeError("the board redraw never finished")


queue_left = []                                 # See the drain check in P5


def cascade(cells, limit=400, chain=1):
    """Run one whole cascade over `cells`; return what it left and what it did.

    RunCount is read every frame and the first non-zero one kept: it belongs
    to whichever step is running, and the last step of a cascade always finds
    nothing and leaves it at zero.

    Every cascade run through here also records whether the effect queue was
    left empty, because "the queue always drains" is a claim about all of them
    and not about one test (SPEC 7.2).
    """
    set_board(cells)
    kick(chain)
    runs, used = 0, 0
    while used < limit:
        frames(1)
        used += 1
        if runs == 0:
            runs = peek("RunCount")
        if peek("PlayState") == PLAY_ARE:
            break
    queue_left.append(peek("EffectQTail") - peek("EffectQHead"))
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

# =============================================================================
#   P4 — scoring, levels and speed
# =============================================================================
#   Every number below is read out of RAM or off the VDP's own name table and
#   compared with SPEC 9 and SPEC 10 arithmetic done here in Python. Nothing
#   is compared against a constant this file made up.

FONT_DIGIT_0 = 16                               # constants.inc
SCORE_X, SCORE_Y = 12, 5                        # Panel-relative (SPEC 12.2)
HIGH_X, HIGH_Y = 12, 10
HIGHLVL_X, HIGHLVL_Y = 15, 11
SCORE_DIGITS = 7
VRAM_NAMES, PANEL_X, PANEL_Y = 0x1400, 5, 0


def read(name, length):
    d = rpc("mem.read", {"space": "cpu", "address": syms[name],
                         "length": length})["data"]
    return base64.b64decode(d)


def unbcd(raw):
    """Packed BCD, low byte first, as an integer."""
    v = 0
    for byte in reversed(raw):
        v = v * 100 + (byte >> 4) * 10 + (byte & 0x0F)
    return v


def score():
    return unbcd(read("ScoreLo", 4))


def high():
    return unbcd(read("HighLo", 4))


def set_score(v):
    """Plant a score. The panel is not redrawn — the next bank does that."""
    raw = bytearray(4)
    for i in range(4):
        raw[i] = ((v // 10) % 10) * 16 + (v % 10)
        v //= 100
    rpc("mem.write", {"space": "cpu", "address": syms["ScoreLo"],
                      "data": base64.b64encode(bytes(raw)).decode()})


def set_high(v):
    raw = bytearray(4)
    for i in range(4):
        raw[i] = ((v // 10) % 10) * 16 + (v % 10)
        v //= 100
    rpc("mem.write", {"space": "cpu", "address": syms["HighLo"],
                      "data": base64.b64encode(bytes(raw)).decode()})
    poke("HighOwned", 0)
    poke("HighFlash", 0)


def panel(col, row, width):
    """What the VDP's name table holds across a run of panel cells."""
    vram = base64.b64decode(rpc("mem.read", {
        "space": "vram",
        "address": VRAM_NAMES + (PANEL_Y + row) * 32 + PANEL_X + col,
        "length": width})["data"])
    return list(vram)


def digits(col, row, width):
    """...read back as a number, or None if any cell is not a digit glyph."""
    cells = panel(col, row, width)
    if any(not (FONT_DIGIT_0 <= c < FONT_DIGIT_0 + 10) for c in cells):
        return None
    return int("".join(str(c - FONT_DIGIT_0) for c in cells))


def scored(cells, level=1, cleared=0, start=0, limit=400, chain=1):
    """Run one cascade over a planted board and report what it paid."""
    poke("Level", level)
    poke("TilesCleared", cleared)
    set_score(start)
    left, runs, ended, used = cascade(cells, limit, chain)
    return score(), runs, ended, left


# The high score is out of the way for the scoring tests: it is real and it
# fires on every bank once the score reaches it, and it has its own section
# below. 9999999 is the clamp, so nothing here can reach it.
set_high(9999999)

print("\nSPEC 9.7 example A — a plain three-in-a-row at chain 1")
got, runs, chain, left = scored({(15, c): RED for c in range(3)})
check("3 x TileValue[1] = 60, no bonuses", got, 60)
check("one run", runs, 1)

print("\nrun length bonus (SPEC 9.3): the run pays per tile AND per length")
for length, want in ((3, 3 * 20 + 0),
                     (4, 4 * 20 + 100),
                     (5, 5 * 20 + 300),
                     (6, 6 * 20 + 600)):
    got, runs, chain, left = scored({(15, c): RED for c in range(length)})
    check(f"a run of {length} pays {want}", got, want)

print("\n...and a run longer than 6 is a vertical one (SPEC 9.3 caps at 7+)")
got, runs, chain, left = scored({(r, 0): RED for r in range(9, 16)})
check("seven down a column pays 7 x 20 + 1000", got, 7 * 20 + 1000)

print("\nsimultaneous run bonus (SPEC 9.4) — the shared cell scores twice")
got, runs, chain, left = scored(
    {(15, 0): RED, (15, 1): RED, (15, 2): RED, (13, 0): RED, (14, 0): RED})
check("two runs found", runs, 2)
check("3x20 + 3x20 + MultiBonus[2] = 320", got, 3 * 20 + 3 * 20 + 200)

print("\nchain depth (SPEC 9.1) — the second step is worth 50 a tile, not 20")
got, runs, chain, left = scored(
    {(15, 0): RED, (15, 1): RED, (15, 2): RED,
     (14, 0): YELLOW, (13, 1): YELLOW, (14, 2): YELLOW})
check("the board is clear", left, {})
check("60 at chain 1 then 150 at chain 2", got, 3 * 20 + 3 * 50)

print("\nlevels (SPEC 10.1) — 30 tiles, surplus carries, +1000 for the level")
got, runs, chain, left = scored({(15, c): RED for c in range(3)}, cleared=29)
check("the level advanced", peek("Level"), 2)
check("the surplus carried over", peek("TilesCleared"), 2)
check("60 for the run and BONUS_LEVELUP for the level", got, 60 + 1000)

print("\n...at most one advance a step, however much goes at once")
block = {}
for r in range(4, 16):                          # 12 rows x 6 = 72 red tiles,
    for c in range(6):                          #   every one of them in a run
        block[(r, c)] = RED
got, runs, chain, left = scored(block, cleared=0, limit=900)
check("the board is clear", left, {})
check("one level, not two", peek("Level"), 2)
check("42 tiles of surplus carried", peek("TilesCleared"), 72 - 30)

print("\nthe score clamps at 9999999 and does not wrap (SPEC 9)")
got, runs, chain, left = scored({(15, c): RED for c in range(3)},
                                start=9999950)
check("9999950 + 60 clamps", got, 9999999)
got, runs, chain, left = scored({(15, c): RED for c in range(3)},
                                start=9999999)
check("...and stays there", got, 9999999)

print("\nsoft drop pays a point a row (SPEC 9.6)")
set_board({})
poke("Level", 1)
poke("TilesCleared", 0)
poke("PieceCol", 2)
poke("PieceRow", 0)
poke("GravityTimer", 48)
poke("PlayState", PLAY_FALLING)
set_score(0)
frames(3)                                       # release, so DOWN is fresh
r0 = peek("PieceRow")
frames(12, ["down"])
rows = peek("PieceRow") - r0
check("four rows in 12 frames", rows, 4)
check("one point each", score(), rows)
frames(48)
check("a row that fell at gravity's rate pays nothing", score(), rows)

print("\nthe panel shows what RAM holds, all seven digits, zero padded")
got, runs, chain, left = scored({(15, c): RED for c in range(3)})
frames(4)                                       # let the flush catch up
check("SCORE reads 0000060", panel(SCORE_X, SCORE_Y, SCORE_DIGITS),
      [FONT_DIGIT_0 + int(d) for d in "0000060"])
check("...and that is the number in RAM",
      digits(SCORE_X, SCORE_Y, SCORE_DIGITS), got)
got, runs, chain, left = scored({(15, c): RED for c in range(3)},
                                level=8, cleared=29)     # ...which levels up
frames(4)
check("the LEVEL box followed the advance, tens over units",
      panel(18, 17, 1) + panel(18, 18, 1),
      [FONT_DIGIT_0 + 0, FONT_DIGIT_0 + 9])

print("\nthe high score is taken live, the instant it is passed (SPEC 9.8)")
set_high(10000)                                 # HIGH_INIT, and HighOwned = 0
got, runs, chain, left = scored({(15, c): RED for c in range(3)},
                                level=12, start=9990)
check("the score passed it", got, 10050)
check("the high score followed it up", high(), 10050)
check("it carries the level it was set on, in BCD", peek("HighLevel"), 0x12)
check("the game owns it now", peek("HighOwned"), 1)
check("and the flash is running", peek("HighFlash"), 6)

print("\n...and it keeps tracking while the run holds it")
got, runs, chain, left = scored({(15, c): RED for c in range(3)},
                                level=7, start=got)
check("the high score moved with the score", high(), got)
check("...and so did its level", peek("HighLevel"), 0x07)
check("the fanfare and the flash were one-shot", peek("HighOwned"), 1)

print("\n...but a score below it leaves it alone")
before = high()
got, runs, chain, left = scored({(15, c): RED for c in range(3)}, start=0)
check("the high score stood", high(), before)

print("\nthe HIGH field flashes on the overtake, and ends up readable")
set_high(10000)
scored({(15, c): RED for c in range(3)}, start=9990)
frames(4)
lit = panel(HIGH_X, HIGH_Y, SCORE_DIGITS)
check("the digits are up", digits(HIGH_X, HIGH_Y, SCORE_DIGITS), 10050)
frames(13)                                      # 15 frames is half a blink
dark = panel(HIGH_X, HIGH_Y, SCORE_DIGITS)
check("half a blink later the field is blank", dark, [0] * SCORE_DIGITS)
for _ in range(120):                            # 6 half blinks of 15 frames
    frames(1)
    if peek("HighFlash") == 0:
        break
check("the flash ran itself out", peek("HighFlash"), 0)
frames(4)
check("and left the digits up", panel(HIGH_X, HIGH_Y, SCORE_DIGITS), lit)
set_high(9999999)

print("\ngravity (SPEC 10.2) — frames per row, read back off a real fall")
SPEED = {0: [48, 43, 38, 34, 30, 26, 23, 20, 17, 15, 13, 11, 9, 8, 7, 6],
         1: [40, 36, 32, 28, 25, 22, 19, 17, 14, 13, 11, 9, 8, 7, 6, 5]}
was_region = peek("Region")
set_board({})
poke("PlayState", PLAY_FALLING)
poke("PieceCol", 2)
for region, name in ((0, "NTSC"), (1, "PAL")):
    poke("Region", region)
    got = []
    for level in list(range(1, 17)) + [17, 99]:
        poke("Level", level)
        poke("PieceRow", 0)
        poke("GravityTimer", 1)                 # the next frame steps a row
        frames(1)                               #   and reloads the timer from
        got.append(peek("GravityTimer"))        #   ScoreGravity
    check(f"{name} levels 1-16", got[:16], SPEED[region])
    check(f"{name} caps at level 16 for 17 and 99", got[16:],
          [SPEED[region][15]] * 2)
poke("Region", was_region)

# =============================================================================
#   P5 — reagents
# =============================================================================
#   SPEC 7. Every expectation below is built out of the SPEC tables copied
#   here, so a test says "a run of three at chain one, plus what the fireball
#   took, plus its trigger bonus" rather than a number somebody typed.
#
#   The board in each case is planted so that exactly ONE run exists — an
#   accidental second one changes MultiBonus and every total after it — and so
#   that whatever survives cannot match once gravity has dropped it. Both are
#   checked, not assumed: `runs` and the leftover board are asserted every time.

TILE_VALUE = [20, 50, 100, 200, 300, 400, 500, 600]     # SPEC 9.1, chain - 1
EFFECT_VALUE = [30, 60, 120, 240, 350, 450, 550, 650]   # SPEC 9.2, chain - 1
LENGTH_BONUS = {3: 0, 4: 100, 5: 300, 6: 600, 7: 1000}  # SPEC 9.3
MULTI_BONUS = {1: 0, 2: 200, 3: 500, 4: 1000}           # SPEC 9.4
TRIGGER = {"fireball": 500, "bolt": 300, "bomb": 300, "prism": 400}   # SPEC 9.5

GLYPH_FIREBALL, GLYPH_BOLT, GLYPH_BOMB, GLYPH_STAR = 1, 2, 3, 4


def match_pts(length, chain=1, runs=1):
    """SPEC 8 step 2 for a single run."""
    return length * TILE_VALUE[chain - 1] + LENGTH_BONUS[length] + MULTI_BONUS[runs]


def effect_pts(cells, chain=1):
    """SPEC 8 step 4 — per cell an effect took."""
    return cells * EFFECT_VALUE[chain - 1]


print("\nSPEC 7.3 — a fireball takes every remaining tile of its own colour")
got, runs, chain, left = scored({
    (15, 0): RED, (15, 1): RED, (15, 2): RED + GLYPH_FIREBALL,
    (12, 4): RED, (10, 1): RED,                 # scattered, and no run of them
    (13, 3): BLUE, (11, 5): GREEN})             # another colour is not its business
check("one run", runs, 1)
check("the reds went board-wide, the rest fell", left,
      {(15, 3): BLUE, (15, 5): GREEN})
check("run + 2 blasted reds + the trigger bonus", got,
      match_pts(3) + effect_pts(2) + TRIGGER["fireball"])

print("\n...and a prism is immune to it (SPEC 7.4)")
#   Compared by COLOUR and not by tile, because from P6 on a prism sitting in
#   the well rotates and its board byte is WILD_BASE + 0..3 (SPEC 14). That is
#   not a weaker check: it is the same check the GAME makes, and getting it
#   wrong is exactly the bug P5 predicted — a rotating prism's low three bits
#   read as a bolt or a bomb, and the immunity is a colour test.
got, runs, chain, left = scored({
    (15, 0): RED, (15, 1): RED, (15, 2): RED + GLYPH_FIREBALL,
    (12, 0): RED, (12, 4): WILD})
check("the prism survived a red fireball, and it is the only cell left",
      list(left), [(15, 4)])
check("...and it is still a prism, whichever way it is facing",
      left.get((15, 4), 0) & COLOR_MASK, WILD)
check("nothing was paid for it", got,
      match_pts(3) + effect_pts(1) + TRIGGER["fireball"])

print("\n...two fireballs in one run each detonate, and the second finds nothing")
got, runs, chain, left = scored({
    (15, 0): RED + GLYPH_FIREBALL, (15, 1): RED + GLYPH_FIREBALL, (15, 2): RED,
    (12, 0): RED, (10, 2): RED, (8, 4): RED})
check("the board is clear", left, {})
check("three reds blasted once, two trigger bonuses paid", got,
      match_pts(3) + effect_pts(3) + 2 * TRIGGER["fireball"])

print("\nSPEC 7.4, the FIREBALL column — what a red fireball catches also fires")
FIRE_RUN = {(15, 0): RED, (15, 1): RED + GLYPH_FIREBALL, (15, 2): RED}
BASE = match_pts(3) + TRIGGER["fireball"]

got, runs, chain, left = scored({**FIRE_RUN, (12, 3): RED, (9, 4): CYAN})
check("a potion just goes", got, BASE + effect_pts(1))
check("...and the cell it could not reach fell", left, {(15, 4): CYAN})

got, runs, chain, left = scored(
    {**FIRE_RUN, (12, 3): RED + GLYPH_FIREBALL, (9, 4): CYAN})
check("a fireball fires, finds its colour gone, and still pays", got,
      BASE + effect_pts(1) + TRIGGER["fireball"])

got, runs, chain, left = scored(
    {**FIRE_RUN, (12, 3): RED + GLYPH_BOLT, (12, 5): GREEN, (9, 4): CYAN})
check("a bolt fires: the green in its row went too", left, {(15, 4): CYAN})
check("...and both effects were paid", got,
      BASE + effect_pts(2) + TRIGGER["bolt"])

got, runs, chain, left = scored(
    {**FIRE_RUN, (12, 3): RED + GLYPH_BOMB,
                      (11, 2): GREEN, (13, 4): BLUE, (9, 4): CYAN})
check("a bomb fires: both corners of its block went", left, {(15, 4): CYAN})
check("...and both effects were paid", got,
      BASE + effect_pts(3) + TRIGGER["bomb"])

got, runs, chain, left = scored(
    {**FIRE_RUN, (12, 3): RED + GLYPH_STAR, (9, 4): CYAN})
check("a star doubles the whole cascade, retroactively", got,
      (BASE + effect_pts(1)) * 2)

print("\nSPEC 7.3 — a bolt cuts its whole row and its whole column")
got, runs, chain, left = scored({
    (10, 2): RED, (10, 3): RED + GLYPH_BOLT, (10, 4): RED,
    (10, 0): BLUE, (10, 1): GREEN, (10, 5): CYAN,       # the rest of the row
    (12, 3): BLUE, (14, 3): GREEN, (15, 3): CYAN,       # the rest of the column
    (13, 1): PURPLE})                                   # neither, so it lives
check("one run", runs, 1)
check("the cross is gone and nothing else is", left, {(15, 1): PURPLE})
check("three tiles matched, six cut, one trigger bonus", got,
      match_pts(3) + effect_pts(6) + TRIGGER["bolt"])

print("\n...and two bolts in one run cut two crosses (SPEC 7.3)")
got, runs, chain, left = scored({
    (13, 2): RED + GLYPH_BOLT, (14, 2): RED, (15, 2): RED + GLYPH_BOLT,
    (13, 0): BLUE, (13, 1): GREEN, (13, 3): CYAN, (13, 4): BLUE, (13, 5): GREEN,
    (15, 0): CYAN, (15, 1): BLUE, (15, 3): GREEN, (15, 4): CYAN, (15, 5): BLUE,
    (14, 5): PURPLE})
check("one run", runs, 1)
check("BOTH rows went, and the tile in neither did not", left,
      {(15, 5): PURPLE})
check("three matched, ten cut, two trigger bonuses", got,
      match_pts(3) + effect_pts(10) + 2 * TRIGGER["bolt"])

print("\nSPEC 7.4, the BOLT column — a bolt removes a prism, and everything fires")
BOLT_RUN = {(15, 0): RED, (15, 1): RED + GLYPH_BOLT, (15, 2): RED}
BASE = match_pts(3) + TRIGGER["bolt"]

got, runs, chain, left = scored({**BOLT_RUN, (11, 1): BLUE, (8, 5): CYAN})
check("a potion in the column goes", got, BASE + effect_pts(1))
check("...and the tile out of reach fell", left, {(15, 5): CYAN})

got, runs, chain, left = scored(
    {**BOLT_RUN, (11, 1): BLUE + GLYPH_FIREBALL, (8, 4): BLUE, (8, 5): CYAN})
check("a blue fireball fires and takes the far blue", left, {(15, 5): CYAN})
check("...and pays for it", got,
      BASE + effect_pts(2) + TRIGGER["fireball"])

got, runs, chain, left = scored(
    {**BOLT_RUN, (11, 1): BLUE + GLYPH_BOLT, (11, 4): GREEN, (8, 5): CYAN})
check("a second bolt cuts its own row", left, {(15, 5): CYAN})
check("...and pays for it", got, BASE + effect_pts(2) + TRIGGER["bolt"])

got, runs, chain, left = scored(
    {**BOLT_RUN, (11, 1): BLUE + GLYPH_BOMB, (10, 2): GREEN, (8, 5): CYAN})
check("a bomb blows its own block", left, {(15, 5): CYAN})
check("...and pays for it", got, BASE + effect_pts(2) + TRIGGER["bomb"])

got, runs, chain, left = scored(
    {**BOLT_RUN, (11, 1): BLUE + GLYPH_STAR, (8, 5): CYAN})
check("a star caught by a bolt doubles the cascade", got,
      (BASE + effect_pts(1)) * 2)

got, runs, chain, left = scored({**BOLT_RUN, (11, 1): WILD, (8, 5): CYAN})
check("a prism is NOT immune to a bolt", left, {(15, 5): CYAN})
check("...and pays its flat bonus as well as its tile", got,
      BASE + effect_pts(1) + TRIGGER["prism"])

print("\nSPEC 7.3 — a bomb takes the 3 x 3 around it")
got, runs, chain, left = scored({
    (12, 2): RED, (13, 2): RED, (14, 2): RED + GLYPH_BOMB,
    (13, 1): BLUE, (13, 3): GREEN,
    (14, 1): GREEN, (14, 3): BLUE,
    (15, 1): CYAN, (15, 2): BLUE, (15, 3): CYAN,
    (12, 0): CYAN, (14, 5): PURPLE})            # outside the block
check("one run", runs, 1)
check("the block went and the two outside it fell", left,
      {(15, 0): CYAN, (15, 5): PURPLE})
check("three matched, seven blown", got,
      match_pts(3) + effect_pts(7) + TRIGGER["bomb"])

print("\n...clipped at the edges, and it does not reach past the wall")
got, runs, chain, left = scored({
    (0, 0): RED + GLYPH_BOMB, (0, 1): RED, (0, 2): RED,
    (1, 0): BLUE, (1, 1): GREEN})
check("the corner block went", left, {})
check("three matched, two blown — not nine", got,
      match_pts(3) + effect_pts(2) + TRIGGER["bomb"])
bd = board()
check("floor sentinels intact", all(v == 255 for v in bd[128:160]), True)
check("side sentinels intact",
      all(bd[r * 8 + 6] == 255 and bd[r * 8 + 7] == 255 for r in range(20)), True)

print("\nSPEC 7.4, the BOMB column")
BOMB_RUN = {(15, 0): RED, (15, 1): RED + GLYPH_BOMB, (15, 2): RED}
BASE = match_pts(3) + TRIGGER["bomb"]

got, runs, chain, left = scored({**BOMB_RUN, (14, 1): BLUE, (8, 5): CYAN})
check("a potion in the block goes", got, BASE + effect_pts(1))
check("...and the tile out of reach fell", left, {(15, 5): CYAN})

got, runs, chain, left = scored(
    {**BOMB_RUN, (14, 1): BLUE + GLYPH_FIREBALL, (8, 4): BLUE, (8, 5): CYAN})
check("a fireball caught by a bomb fires", left, {(15, 5): CYAN})
check("...and pays for it", got, BASE + effect_pts(2) + TRIGGER["fireball"])

got, runs, chain, left = scored(
    {**BOMB_RUN, (14, 1): BLUE + GLYPH_BOLT, (14, 5): GREEN, (8, 5): CYAN})
check("a bolt caught by a bomb fires", left, {(15, 5): CYAN})
check("...and pays for it", got, BASE + effect_pts(2) + TRIGGER["bolt"])

got, runs, chain, left = scored(
    {**BOMB_RUN, (14, 1): BLUE + GLYPH_BOMB, (13, 2): GREEN, (8, 5): CYAN})
check("a bomb caught by a bomb fires", left, {(15, 5): CYAN})
check("...and pays for it", got, BASE + effect_pts(2) + TRIGGER["bomb"])

got, runs, chain, left = scored(
    {**BOMB_RUN, (14, 1): BLUE + GLYPH_STAR, (8, 5): CYAN})
check("a star caught by a bomb doubles the cascade", got,
      (BASE + effect_pts(1)) * 2)

got, runs, chain, left = scored({**BOMB_RUN, (14, 1): WILD, (8, 5): CYAN})
check("a prism is not immune to a bomb either", left, {(15, 5): CYAN})
check("...and pays its flat bonus", got,
      BASE + effect_pts(1) + TRIGGER["prism"])

print("\na reagent removed by another reagent's effect fires (SPEC 7.2)")
got, runs, chain, left = scored({
    (15, 0): RED + GLYPH_BOMB, (15, 1): RED, (15, 2): RED,
    (14, 1): BLUE + GLYPH_BOLT,                 # in the bomb's block
    (14, 0): GREEN, (14, 3): CYAN, (14, 4): PURPLE, (14, 5): GREEN,
    (10, 1): YELLOW,                            # in the bolt's column
    (12, 4): BLUE})                             # in neither
check("the bomb's block and the bolt's cross both went", left, {(15, 4): BLUE})
check("match, then two bomb cells, then four bolt cells, both bonuses", got,
      match_pts(3) + effect_pts(2) + TRIGGER["bomb"]
                   + effect_pts(4) + TRIGGER["bolt"])

print("\nthe star multiplier, and its cap of x8 (SPEC 7.3, 9.6)")
for stars, want in ((1, 2), (2, 4), (3, 8)):
    cells = {(15, c): RED for c in range(3)}
    for c in range(stars):
        cells[(15, c)] = RED + GLYPH_STAR
    got, runs, chain, left = scored(cells)
    check(f"{stars} star(s) is x{want}", got, match_pts(3) * want)

got, runs, chain, left = scored(
    {(15, c): RED + GLYPH_STAR for c in range(4)})
check("four stars is still x8, not x16", got, match_pts(4) * 8)

print("\nthe prism's flat bonus, per prism cleared (SPEC 9.5)")
got, runs, chain, left = scored({(15, 0): RED, (15, 1): RED, (15, 2): WILD})
check("one prism closing a red run pays 400", got,
      match_pts(3) + TRIGGER["prism"])
got, runs, chain, left = scored({(15, c): WILD for c in range(3)})
check("three prisms pay three times", got,
      match_pts(3) + 3 * TRIGGER["prism"])

print("\nSPEC 9.7 example B — a red fireball in a run of 4 at chain 2")
#   Eight more reds, spread so that no three of them are contiguous in any of
#   the four directions: rows 15, 13, 11 and 9 are two apart, so nothing is
#   vertically or diagonally adjacent, and each row leaves a gap.
EX_B = {(15, 0): RED, (15, 1): RED, (15, 2): RED + GLYPH_FIREBALL, (15, 3): RED,
        (13, 0): RED, (13, 2): RED, (13, 4): RED,
        (11, 1): RED, (11, 3): RED, (11, 5): RED,
        (9, 0): RED, (9, 2): RED}
got, runs, chain, left = scored(EX_B, chain=2)
check("one run of four", runs, 1)
check("the board is clear", left, {})
check("200 + 100 + 0 + 480 + 500 = 1280", got,
      match_pts(4, chain=2) + effect_pts(8, chain=2) + TRIGGER["fireball"])
check("...which is the number SPEC 9.7 B prints", got, 1280)

print("\nSPEC 9.7 example C — a prism closing the run, and a star in the blast")
#   The run of four is closed by a prism, whose bonus is 400, and one of the
#   eight reds the fireball finds is a star. That is SPEC 9.7 C as written —
#   it used to say "one more step for another 400" and was changed here in P5,
#   because no step at chain 3 or deeper can pay exactly 400 (the cheapest run
#   there is 300 and the next is 500).
EX_C = dict(EX_B)
EX_C[(15, 3)] = WILD                            # the fourth cell of the run
EX_C[(13, 0)] = RED + GLYPH_STAR                # caught by the fireball
got, runs, chain, left = scored(EX_C, chain=2)
check("one run of four", runs, 1)
check("the board is clear", left, {})
check("(1280 + 400) x 2 = 3360", got,
      (match_pts(4, chain=2) + effect_pts(8, chain=2)
       + TRIGGER["fireball"] + TRIGGER["prism"]) * 2)
check("...which is the number SPEC 9.7 C prints", got, 3360)

print("\n...and the doubling reaches points scored BEFORE the star cleared")
EX_STAR = dict(EX_B)
EX_STAR[(13, 0)] = RED + GLYPH_STAR
got, runs, chain, left = scored(EX_STAR, chain=2)
check("example B, doubled whole", got, 1280 * 2)

print("\na reagent nobody removes does nothing (SPEC 7.2)")
got, runs, chain, left = scored({
    (15, 0): BLUE, (15, 1): GREEN, (15, 2): CYAN + GLYPH_FIREBALL,
    (15, 3): PURPLE})
check("no run, so nothing fired", runs, 0)
check("the board is untouched", left,
      {(15, 0): BLUE, (15, 1): GREEN, (15, 2): CYAN + GLYPH_FIREBALL,
       (15, 3): PURPLE})
check("and nothing scored", got, 0)

print("\nthe reagent roll, against a model of SPEC 5.2 and 5.3")
#   P2 checked the piece sequence against a model of the LFSR and found the
#   colours right — but the seed it checked dealt no reagent at all, so the
#   half of PieceGenerateNext that matters to P5 has never been read back
#   against the tables it is supposed to be using. This deals pieces in bulk
#   and compares every byte.
#
#   Pieces are dealt one a frame by re-entering PLAY_ARE: PlayAre spawns the
#   preview, rolls a new one and draws it (main.asm), and with the board empty
#   the spawn can never be blocked. Nothing is allowed to fall, so the well
#   stays empty and the loop can run as long as it likes.

LEVEL_BAND = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4]   # tables.inc
P_SPECIAL = [38, 56, 69, 82, 92]                                # SPEC 5.3
REAGENT_THRESHOLDS = [[77, 138, 195, 236], [77, 141, 192, 238],
                      [82, 146, 197, 238], [79, 141, 195, 238],
                      [79, 143, 199, 240]]
COLOR_BASE, NUM_COLORS = 0x40, 6


class Lfsr:
    """rng.asm: a 16-bit Galois LFSR with the $B400 taps, eight shifts a byte."""

    def __init__(self, lo, hi):
        self.lo, self.hi = lo, hi

    def byte(self):
        for _ in range(8):
            carry = self.lo & 1
            self.lo = ((self.lo >> 1) | ((self.hi & 1) << 7)) & 0xFF
            self.hi >>= 1
            if carry:
                self.hi ^= 0xB4
        return self.lo

    def below(self, limit):
        """RngRange: the HIGH byte of (random * limit), not a modulo."""
        return (self.byte() * limit) >> 8


def model_piece(rng, level):
    """SPEC 5.2 — three colours, then one roll for the whole piece."""
    cells = [COLOR_BASE + (rng.below(NUM_COLORS) << 3) for _ in range(3)]
    roll = rng.byte()
    band = LEVEL_BAND[min(level, 16) - 1]
    if roll >= P_SPECIAL[band]:
        return cells                            # No reagent this piece
    which = rng.below(3)
    kind = rng.byte()
    edge = REAGENT_THRESHOLDS[band]
    if kind < edge[0]:
        cells[which] |= GLYPH_FIREBALL
    elif kind < edge[1]:
        cells[which] |= GLYPH_BOLT
    elif kind < edge[2]:
        cells[which] |= GLYPH_BOMB
    elif kind < edge[3]:
        cells[which] |= GLYPH_STAR
    else:
        cells[which] = WILD                     # A prism discards its colour
    return cells


def deal(level, count):
    """Roll `count` pieces at `level`, and what the model says they should be."""
    set_board({})
    poke("Level", level)
    poke("PieceDirty", 0)
    rng = Lfsr(peek("RngLo"), peek("RngHi"))
    got, want = [], []
    for _ in range(count):
        poke("PlayState", PLAY_ARE)
        poke("AreTimer", 1)
        frames(1)
        got.append(list(read("NextA", 3)))
        want.append(model_piece(rng, level))
    return got, want


for level in (1, 5, 8, 11, 16):
    got, want = deal(level, 60)
    band = LEVEL_BAND[min(level, 16) - 1]
    carrying = [p for p in got if any(c & GLYPH_MASK or c == WILD for c in p)]
    check(f"level {level} (band {band}): 60 pieces, none of them differing "
          f"from the model",
          [i for i, (g, w) in enumerate(zip(got, want)) if g != w], [])
    check(f"...and at most one reagent in any of them (SPEC 5.2)",
          max(sum(1 for c in p if c & GLYPH_MASK or c == WILD) for p in got), 1)
    print(f"       ({len(carrying)} of 60 carried one; SPEC 5.3 says "
          f"{P_SPECIAL[band]}/256 = {100 * P_SPECIAL[band] // 256}%)")

print("\n...and every reagent the model and the machine agreed on was legal")
seen = set()
for level in (1, 5, 8, 11, 16):
    got, _ = deal(level, 120)
    for piece in got:
        for cell in piece:
            if cell == WILD:
                seen.add("prism")
            elif cell & GLYPH_MASK:
                seen.add({1: "fireball", 2: "bolt", 3: "bomb",
                          4: "star"}.get(cell & GLYPH_MASK, cell & GLYPH_MASK))
check("all five reagents came out of the roll", sorted(seen),
      ["bolt", "bomb", "fireball", "prism", "star"])
check("a prism is colour 6 and nothing else (SPEC 5.2)",
      all(c == WILD or (c & COLOR_MASK) != WILD
          for level in (1,) for p in deal(level, 30)[0] for c in p), True)

# =============================================================================
#   P6 — animation (SPEC 14, SPEC 8 step 5)
# =============================================================================
#   Every check below reads the VDP's own name table frame by frame, so what is
#   asserted is the tile a player would have been looking at on that frame and
#   not a flag the game set. A mark made by the logic on frame N reaches the
#   screen on frame N + 1 — the one frame of lag everything in the game has
#   (SPEC 12.6) — so the tracks below start with one frame of the board as it
#   was before the step.

GLOW_FRAMES = [6, 5]                            # tables.inc, by region
FLASH_FRAMES = [8, 7]
BANNER_FRAMES = [45, 38]
VFX_FRAMES, SHATTER_STEPS, BLIP_STEPS = 2, 3, 5
VFX_REMOVE1, VFX_REMOVE2, VFX_REMOVE3 = 56, 57, 58
VFX_BEAM_H, VFX_BEAM_V, VFX_BEAM_CROSS = 59, 60, 61
PRISM_BLIP, PRISM_SPIN_RATE, PRISM_SPIN_FRAMES = 0x74, 8, 4
FONT_DOT, FONT_TILDE, FONT_TIMES, FONT_LETTER_A = 52, 55, 53, 26
FONT_BANG = 54
GLYPH_GLOW, PETRIFY_BASE, TINT_NONE = 6, 120, 0x01
VRAM_COLORS = 0x2000                            # SPEC Appendix C.1


def well():
    """The whole 6 x 16 well, as the VDP's name table has it."""
    vram = base64.b64decode(rpc("mem.read", {
        "space": "vram", "address": VRAM_NAMES, "length": 32 * 24})["data"])
    return {(r, c): vram[(PANEL_Y + WELL_Y + r) * 32 + PANEL_X + WELL_X + c]
            for r in range(16) for c in range(6)}


def quiet():
    """Park the machine so a plant can be painted without the game touching it.

    PLAY_ARE with a long timer is the one sub-state that does nothing at all —
    no piece falls, no cascade runs, the well is left alone — and painting a
    board takes redraw() several frames. Without this, a cascade a previous
    test left half-finished carries straight on over the board the next one has
    just planted, and the screen read back is some way into an animation nobody
    asked for. It cost the first run of the prism blip-out test exactly that.
    """
    poke("PlayState", PLAY_ARE)
    poke("AreTimer", 200)
    poke("PieceDirty", 0)


def anim_run(cells, chain=1, limit=400, region=0):
    """Run one cascade over `cells`, recording the sub-state and the whole well
    after every frame.

    The prism's idle rotation is parked for the duration: it is on its own
    clock and would otherwise change a cell in the middle of a track for
    reasons that have nothing to do with the step being measured. It has its
    own test below.
    """
    poke("Region", region)
    quiet()
    set_board(cells)
    redraw()                                    # The plant is only in RAM
    kick(chain)
    poke("PrismTimer", 200)
    log = []
    for _ in range(limit):
        frames(1)
        log.append((peek("PlayState"), well()))
        if log[-1][0] == PLAY_ARE:
            break
    poke("Region", 0)
    return log


def track(log, cell):
    """The tiles one well cell showed, in order, as (tile, frames) pairs."""
    out = []
    for _, w in log:
        if out and out[-1][0] == w[cell]:
            out[-1][1] += 1
        else:
            out.append([w[cell], 1])
    return [tuple(e) for e in out]


def held(log, state):
    return [w for s, w in log if s == state]


print("\nSPEC 14 — a clear GLOWS and then SHATTERS, for the frames SPEC 14 says")
RUN3 = {(15, 0): RED, (15, 1): RED, (15, 2): RED}
for region, name in ((0, "NTSC"), (1, "PAL")):
    states = [s for s, _ in anim_run(RUN3, region=region)]
    check(f"{name}: the glow window is {GLOW_FRAMES[region]} frames",
          states.count(PLAY_GLOW), GLOW_FRAMES[region])
    check(f"{name}: the shatter is {SHATTER_STEPS * VFX_FRAMES} frames",
          states.count(PLAY_SHATTER), SHATTER_STEPS * VFX_FRAMES)
    check(f"{name}: no frame of the step is spent anywhere else",
          sorted(set(states)), [PLAY_GLOW, PLAY_SHATTER, PLAY_GRAVITY,
                                PLAY_ARE])

print("\n...and this is what the cell actually showed, tile by tile")
#   One assertion for the whole animation: the glow glyph of the cell's own
#   colour for the glow window, then the removal ring opening outward at
#   VFX_FRAMES a tile, then nothing. If any duration in SPEC 14 is wrong, or
#   the ring runs backwards, or a tile is skipped, this is what says so.
log = anim_run(RUN3)
tr = track(log, (15, 0))
check("board, then glow, then ring 1, 2, 3 (SPEC 14, Appendix A.3)", tr[:5],
      [(RED, 1), (RED + GLYPH_GLOW, GLOW_FRAMES[0]),
       (VFX_REMOVE1, VFX_FRAMES), (VFX_REMOVE2, VFX_FRAMES),
       (VFX_REMOVE3, VFX_FRAMES)])
check("...and then the cell is empty", tr[5][0], 0)
check("all three cells of the run animate together",
      all(track(log, (15, c))[:5] == tr[:5] for c in (1, 2)), True)

print("\nthe board is NOT touched until the shatter is over (SPEC 8 steps 5, 6)")
#   The whole phase rests on this: every frame above drew a glow, a beam or a
#   ring frame over a cell that still held its own tile, which is the only
#   reason the glow can be "of its own colour" at all.
quiet()
set_board(RUN3)
redraw()
kick()
poke("PrismTimer", 200)
still_there = []
for _ in range(40):
    frames(1)
    if peek("PlayState") in (PLAY_GLOW, PLAY_SHATTER):
        still_there.append(tiles(board()))
    elif still_there:
        break                                   # quiet() below parks the rest
check("the run is on the board for every frame of both windows",
      all(b == {(15, c): RED for c in range(3)} for b in still_there), True)
check("...which is all twelve of them", len(still_there),
      GLOW_FRAMES[0] + SHATTER_STEPS * VFX_FRAMES)

print("\nSPEC 14 — a marked prism sits the glow out and blips INWARD")
log = anim_run({(15, 0): RED, (15, 1): RED, (15, 2): WILD})
pri = track(log, (15, 2))
pot = track(log, (15, 0))
check("it holds its rotation frame through the whole glow window",
      pri[0], (WILD, 1 + GLOW_FRAMES[0]))
check("then the same ring, closing inward (SPEC A.3)", pri[1:6],
      [(PRISM_BLIP, VFX_FRAMES), (PRISM_BLIP + 1, VFX_FRAMES),
       (VFX_REMOVE2, VFX_FRAMES), (VFX_REMOVE1, VFX_FRAMES),
       (FONT_DOT, VFX_FRAMES)])
check("WILD_BASE + GLYPH_GLOW is never drawn — that tile is an arrow",
      any(w[(15, 2)] == WILD + GLYPH_GLOW for _, w in log), False)
check("the shatter window is the prism's, not the potions'",
      [s for s, _ in log].count(PLAY_SHATTER), BLIP_STEPS * VFX_FRAMES)
check("the potions beside it shatter as usual", pot[1:5],
      [(RED + GLYPH_GLOW, GLOW_FRAMES[0]), (VFX_REMOVE1, VFX_FRAMES),
       (VFX_REMOVE2, VFX_FRAMES), (VFX_REMOVE3, VFX_FRAMES)])
check("...and then wait, blank, while the prism finishes", pot[5][0], 0)

print("\nSPEC 14 — the bolt lays a beam down its whole row and column")
#   Checked on the LAST frame of the glow window rather than the first. A bolt
#   marks 21 cells and draws 22 more, which is more than one frame's flush
#   budget (SPEC 12.6), so the beam takes two frames to finish arriving — and
#   what matters is that it is whole while the window is up.
log = anim_run({(15, 0): RED, (15, 1): RED + GLYPH_BOLT, (15, 2): RED})
lit = held(log, PLAY_GLOW)[-1]
check("the bolt's own cell is the cross, drawn over its glow",
      lit[(15, 1)], VFX_BEAM_CROSS)
check("beam-H along every cell of the row, empty ones included",
      [lit[(15, c)] for c in range(6) if c != 1], [VFX_BEAM_H] * 5)
check("beam-V down every cell of the column",
      [lit[(r, 1)] for r in range(15)], [VFX_BEAM_V] * 15)
out = held(log, PLAY_SHATTER)[-1]
check("the cells the beam covered but nothing removed are put back",
      [out[(8, 1)], out[(15, 5)], out[(0, 1)]], [0, 0, 0])
check("...and the cells it did remove are on the ring, not on a beam",
      out[(15, 0)], VFX_REMOVE3)

print("\nSPEC 4.6 — the fireball's flash is ONE BYTE on this machine")
#   The colour of a tile here belongs to its 8-pattern group, not to the cell,
#   so every red tile on the board turns white with a single write to the VDP
#   colour table. Read back off the VDP, and compared with the value the table
#   held BEFORE the flash rather than with a constant this file made up.
base = base64.b64decode(rpc("mem.read", {
    "space": "vram", "address": VRAM_COLORS + (RED >> 3), "length": 1})["data"])[0]
quiet()
set_board({(15, 0): RED, (15, 1): RED, (15, 2): RED + GLYPH_FIREBALL,
           (10, 4): RED})
redraw()
kick()
poke("PrismTimer", 200)
tints, colors, glow_frames = [], [], 0
for _ in range(400):
    frames(1)
    st = peek("PlayState")
    if st == PLAY_GLOW:
        glow_frames += 1
        tints.append(peek("TintColor"))
        colors.append(base64.b64decode(rpc("mem.read", {
            "space": "vram", "address": VRAM_COLORS + (RED >> 3),
            "length": 1})["data"])[0])
    if st == PLAY_ARE:
        break
check("the flashing colour is the fireball's own", sorted(set(tints)), [RED])
check("the group's foreground nibble is white (15) for the whole window",
      sorted(set(colors)), [(base & 0x0F) | 0xF0])
check("...and its background nibble is left alone",
      sorted(set(colors))[0] & 0x0F, base & 0x0F)
check("the window is the flash's length, not the glow's (SPEC 14)",
      glow_frames, FLASH_FRAMES[0])
check("the colour table is put back afterwards", base64.b64decode(rpc(
    "mem.read", {"space": "vram", "address": VRAM_COLORS + (RED >> 3),
                 "length": 1})["data"])[0], base)
check("...and so is TintColor", peek("TintColor"), TINT_NONE)

print("\nSPEC 14 — a prism at rest is the only tile on the board that moves")
quiet()
set_board({(15, 0): WILD})
redraw()
poke("PlayState", PLAY_ARE)                     # Nothing else happening at all
poke("AreTimer", 200)
poke("PieceDirty", 0)
poke("PrismFrame", 0)
poke("PrismTimer", 1)
spin = []
for _ in range(4 * PRISM_SPIN_RATE):
    frames(1)
    t = board()[15 * 8]
    if spin and spin[-1][0] == t:
        spin[-1][1] += 1
    else:
        spin.append([t, 1])
check("it turns through its four frames, in order", [t for t, _ in spin],
      [WILD + 1, WILD + 2, WILD + 3, WILD])
check(f"one frame every {PRISM_SPIN_RATE}", sorted({n for _, n in spin}),
      [PRISM_SPIN_RATE])
facing = board()[15 * 8]                        # Read BEFORE the extra frame:
frames(1)                                       #   one more and it has turned
check("and the screen is showing it", well()[(15, 0)], facing)

print("\nSPEC 13.4 — the well petrifies from the floor up, into its own shapes")
stone = {(15, 0): RED, (15, 1): RED + GLYPH_BOMB, (14, 0): BLUE + GLYPH_STAR,
         (13, 0): WILD, (12, 3): GREEN + GLYPH_BOLT}
quiet()
set_board(stone)
redraw()
poke("GameState", 3)                            # STATE_GAMEOVER
poke("PetrifyRow", 15)                          # ...as AnimPetrifyBegin leaves
poke("AnimTimer", 2)                            #    it
rows = []
for _ in range(48):
    frames(1)
    rows.append(peek("PetrifyRow"))
    if rows[-1] == 0xFF:
        break
check("sixteen rows at 2 frames a row is 32 frames (SPEC 14)", len(rows), 32)
check("it works upward from the floor", rows[:5], [15, 14, 14, 13, 13])
left = tiles(board())
check("each cell sets as its own shape (SPEC A.3)", left,
      {(15, 0): PETRIFY_BASE + 0, (15, 1): PETRIFY_BASE + GLYPH_BOMB,
       (14, 0): PETRIFY_BASE + GLYPH_STAR, (13, 0): PETRIFY_BASE + 0,
       (12, 3): PETRIFY_BASE + GLYPH_BOLT})
frames(2)
check("...and the screen agrees, cell for cell",
      {k: v for k, v in well().items() if v}, left)
poke("GameState", 1)                            # Back to STATE_PLAY
poke("PieceDirty", 0)

print("\nSPEC 14 — the message band says what just happened")
BAND_Y = 22                                     # MSG_Y (SPEC 12.2)


def tile_str(text):
    """ASCII to tile numbers, the way strings.inc's TileStr macro does it."""
    out = []
    for ch in text:
        if ch == " ":
            out.append(0)
        elif ch.isdigit():
            out.append(FONT_DIGIT_0 + int(ch))
        elif "A" <= ch <= "Z":
            out.append(FONT_LETTER_A + ord(ch) - ord("A"))
        elif ch == "~":
            out.append(FONT_TILDE)
        elif ch == "x":
            out.append(FONT_TIMES)
        elif ch == "!":
            out.append(FONT_BANG)
        else:
            raise ValueError(ch)
    return out


def band(text):
    """The band's cells where a banner of this length would be centred."""
    return panel((22 - len(text)) // 2, BAND_Y, len(text))


poke("Level", 1)
poke("TilesCleared", 30 - 3)                    # LEVEL_TILES; this clear buys it
quiet()
set_board(RUN3)
redraw()
kick()
poke("PrismTimer", 200)
banner_at = None
for n in range(1, 400):
    frames(1)
    if banner_at is None and band("~~ LEVEL UP ~~") == tile_str("~~ LEVEL UP ~~"):
        banner_at = n
    if peek("PlayState") == PLAY_ARE:
        break
check("thirty tiles raises LEVEL UP in the band (SPEC 10.1, 14)",
      banner_at is not None, True)
check("...and the level went up with it", peek("Level"), 2)
gone = None
for n in range(1, BANNER_FRAMES[0] + 8):
    frames(1)
    if gone is None and band("~~ LEVEL UP ~~") != tile_str("~~ LEVEL UP ~~"):
        gone = n
check(f"it comes down BannerFrames later, not before",
      gone is not None and gone >= BANNER_FRAMES[0] - banner_at, True)
check("the band is blank again", band(" " * 18), [0] * 18)

print("\n...and a chain of two links says so (SPEC 8 SETTLE)")
#   Played, not planted: the reds clear, the blues fall into row 15 and only
#   THEN make a run. ChainStep counts the step that found nothing as well, so a
#   two-link chain ends at 3.
poke("TilesCleared", 0)
chained = {(15, 0): RED, (15, 1): RED, (15, 2): RED,
           (14, 0): BLUE, (14, 1): BLUE, (13, 2): BLUE}
quiet()
set_board(chained)
redraw()
kick()
poke("PrismTimer", 200)
for _ in range(400):
    frames(1)
    if peek("PlayState") == PLAY_ARE:
        break
check("two steps cleared, and the second was the fall's doing",
      peek("ChainStep"), 3)
for _ in range(4):                              # The settle queued the banner
    frames(1)                                   #   BEHIND the last of the
    if peek("DirtyCount") == 0:                 #   step's own removal marks,
        break                                   #   and a frame flushes at most
                                                #   DIRTY_FLUSH_MAX cells
                                                #   (SPEC 12.6) — so the band
                                                #   can land a frame after the
                                                #   settle that asked for it
check("the band reads CHAIN x2", band("~~ CHAIN x2 ~~"),
      tile_str("~~ CHAIN x2 ~~"))
check("the board is empty", tiles(board()), {})

print("\n...and a single clear does not raise one (SPEC 8 SETTLE — chain >= 2)")
frames(BANNER_FRAMES[0] + 2)                    # Let the chain banner run out
poke("PlayState", PLAY_ARE)                     #   first — a piece spawns and
poke("AreTimer", 200)                           #   falls in those 47 frames,
poke("PieceDirty", 0)                           #   and the redraw below paints
check("the chain banner came down on its own", band(" " * 18), [0] * 18)
quiet()
set_board(RUN3)
redraw()                                        #   the well back over it
kick()
poke("PrismTimer", 200)
for _ in range(400):
    frames(1)
    if peek("PlayState") == PLAY_ARE:
        break
frames(1)
check("no banner for a one-step cascade", band(" " * 18), [0] * 18)

print("\na step BIGGER than the dirty ring still reaches the screen")
#   The reagents are what made this reachable. Before P5 a step removed the
#   cells one run had matched — a handful — and CascadeRemove marked each one
#   on the spot. Five bolts in one run take 71, the ring holds 64, and a mark
#   dropped by a full ring is never made again (D6): the tile would stay on
#   the screen with nothing behind it on the board. CascadeRemove falls back to
#   RenderBoard, and this is the test that says the fallback works — the VDP's
#   own name table, read back and compared with the board cell by cell.
AreDelay = [12, 10]                             # tables.inc, by region

big = {}
palette = [RED, YELLOW, GREEN, CYAN, BLUE, PURPLE]
for r in range(2, 16):
    for c in range(6):
        big[(r, c)] = palette[(r + 2 * c) % 6]  # No run anywhere in it
for c in range(6):
    big[(15, c)] = RED                          # ...except this one
for c in range(5):
    big[(15, c)] |= GLYPH_BOLT                  # five of which cut a column

poke("Level", 1)
poke("TilesCleared", 0)
set_score(0)
set_board(big)
redraw()                                        # The plant is only in RAM
kick()
biggest, used = 0, 0
while used < 400:
    frames(1)
    used += 1
    biggest = max(biggest, peek("CellCount"))
    if peek("PlayState") == PLAY_ARE:
        break
#   The fallback is a CURSOR, so the screen is a few frames behind the board
#   when the cascade settles rather than level with it — which is fine and is
#   the point: the next piece does not arrive until the ARE delay is up
#   (SPEC 5.6), and the redraw has to have landed by then. Waiting for it here
#   and counting the frames is what says so.
catchup = 0
while catchup < 30 and not (peek("RedrawIdx") == 0xFF and peek("DirtyCount") == 0):
    frames(1)
    catchup += 1

bd = board()
vram = base64.b64decode(rpc("mem.read", {"space": "vram", "address": VRAM_NAMES,
                                         "length": 32 * 24})["data"])
screen = {}
for r in range(16):
    for c in range(6):
        v = vram[(PANEL_Y + WELL_Y + r) * 32 + PANEL_X + WELL_X + c]
        if v:
            screen[(r, c)] = v
print(f"  ({used} frames; the biggest single step removed {biggest} cells, "
      f"and the screen caught up {catchup} frames later)")
check("the cascade terminated", used < 400, True)
check("one step removed more than the ring holds", biggest > 64, True)
check("the screen caught up inside the ARE delay",
      catchup <= AreDelay[peek("Region")], True)
check("nothing floats", resting(tiles(bd)), True)
check("no cell of the well differs between the board and the screen",
      sorted(set(screen.items()) ^ set(tiles(bd).items())), [])

print("\nwhat steps 3 and 4 cost, on the worst board above (measured)")
#   MEASURED, not estimated, the same way P3's scan was: run to the routine,
#   read the cycle counter, run to the next one, read it again. SPEC 8's steps
#   3 and 4 are the reagents' whole share of a frame.
def cycles():
    return rpc("session.info")["cycles"]

set_board(big)
kick()
rpc("exec.runTo", {"address": syms["MatchScan"], "timeout": "5s"})
c0 = cycles()
rpc("exec.runTo", {"address": syms["EffectEnqueueMarked"], "timeout": "5s"})
c1 = cycles()
rpc("exec.runTo", {"address": syms["AnimGlowBegin"], "timeout": "5s"})
c2 = cycles()
rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})
c3 = cycles()                                   # ...and the rest of that frame
rpc("exec.runTo", {"address": syms["AnimShatterBegin"], "timeout": "5s"})
c4 = cycles()
rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})
c5 = cycles()
print(f"  (scan {c1 - c0} cycles, then enqueue + resolve {c2 - c1}, "
      f"against a 16667-cycle frame)")
print(f"  (the glow that follows them costs {c3 - c2}, and the heaviest frame "
      f"of the animation — the beams coming down and the ring going up — "
      f"{c5 - c4})")
check("the reagents cost less than the scan they follow", c2 - c1 < c1 - c0, True)
#   Nothing is asserted about those two animation numbers, because on THIS
#   board they are worse than the scan and saying otherwise would be a test
#   written to pass. It is the extreme — a full well, a run of six, five bolts,
#   110 beam cells against a 64-entry dirty ring — and what the game does about
#   it is drop what does not fit and repaint the well (D6, D12, anim.asm). The
#   frame it costs is measured, printed, and lived with, exactly as P5 lived
#   with the 22,145 above it. The number that matters for play is the one
#   below, on a board a player will actually see.
frames(1)                                       # Back to the top of the loop
while peek("PlayState") != PLAY_ARE and used < 800:
    frames(1)
    used += 1

print("\n...and on an ORDINARY clear, which is what the frame budget is for")
quiet()
set_board(RUN3)
redraw()
kick()
rpc("exec.runTo", {"address": syms["AnimGlowBegin"], "timeout": "5s"})
g0 = cycles()
rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})
g1 = cycles()
rpc("exec.runTo", {"address": syms["AnimShatterBegin"], "timeout": "5s"})
g2 = cycles()
rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})
g3 = cycles()
print(f"  (three in a row: the glow frame {g1 - g0} cycles, the frame the "
      f"shatter starts {g3 - g2})")
check("the glow goes up inside one frame", g1 - g0 < 16667, True)
check("...and so does the shatter", g3 - g2 < 16667, True)
while peek("PlayState") != PLAY_ARE:
    frames(1)


# =============================================================================
#   P7 — screen states (SPEC 13)
# =============================================================================
#   The loop around the game rather than the game: title, play, pause, game
#   over, title. Everything below is read off the VDP's own name table or out
#   of RAM, and the two screens that are mostly a drawn image are checked
#   against that image — data/screen-title-ac6502.bin is the same file the
#   cartridge has linked into it, so "the title screen is correct" is a byte
#   comparison and not a description.
#
#   PAUSE needs a key, not a stick: INPUT_PAUSE is `P` on every machine and no
#   joystick carries it (SPEC 11.2). The emulator's own keyboard drives the
#   matrix encoder this cartridge polls, which is what makes it reachable here
#   at all.

STATE_TITLE, STATE_PLAY, STATE_PAUSE, STATE_GAMEOVER = 0, 1, 2, 3
FIELD_X, FIELD_Y, FIELD_W, FIELD_CELLS = 4, 8, 14, 28   # constants.inc
PROMPT_X, PROMPT_Y, PROMPT_LEN = 6, 11, 10
BLINK_HALF = [15, 13]                           # tables.inc, by region
SECOND_FRAMES = [60, 50]
GAMEOVER_SECS = 10
PETRIFY_FRAMES = 2
TILE_WASH, ART_BASE, ART_TILES = 7, 128, 128
MSG_X, MSG_W = 2, 18                            # The band's OWNED cells
HIGH_FLASH_BLINKS = 6

TITLE_IMAGE = open(os.path.join(ROOT, "data",
                                "screen-title-ac6502.bin"), "rb").read()


def key(name):
    """Tap a key on the emulated keyboard, the way a player would."""
    rpc("input.key", {"code": name})


def screen():
    """The whole 32 x 24 name table."""
    return list(base64.b64decode(rpc("mem.read", {
        "space": "vram", "address": VRAM_NAMES, "length": 32 * 24})["data"]))


def field():
    """The magic field's 28 cells, as the screen has them."""
    return {(r, c): t
            for r in range(2)
            for c, t in enumerate(panel(FIELD_X, FIELD_Y + r, FIELD_W))}


def image_at(col, row, width):
    """What the drawn title screen holds across a run of panel cells."""
    base = (PANEL_Y + row) * 32 + PANEL_X + col
    return list(TITLE_IMAGE[base:base + width])


def to_title():
    """Put the machine on the title screen and let it draw itself."""
    poke("GameState", STATE_TITLE)
    poke("NeedsRedraw", 1)
    frames(3)                                   # Blit, reset, first live frame


print("\nSPEC 13.1 — the title screen IS the drawn image, plus two moving things")
to_title()
seen = screen()
moving = set(range(768))
moving -= {(PANEL_Y + FIELD_Y + r) * 32 + PANEL_X + FIELD_X + c
           for r in range(2) for c in range(FIELD_W)}
moving -= {(PANEL_Y + PROMPT_Y) * 32 + PANEL_X + PROMPT_X + c
           for c in range(PROMPT_LEN)}
check("every cell outside the field and the prompt is the artist's",
      [i for i in sorted(moving) if seen[i] != TITLE_IMAGE[i]], [])
check("...which is 730 of the 768", len(moving), 768 - FIELD_CELLS - PROMPT_LEN)
check("the prompt is up, untouched, on the frame it is drawn",
      panel(PROMPT_X, PROMPT_Y, PROMPT_LEN), image_at(PROMPT_X, PROMPT_Y,
                                                      PROMPT_LEN))

print("\n...the prompt blinks at SPEC 14's period, and comes back byte for byte")
to_title()
lit = image_at(PROMPT_X, PROMPT_Y, PROMPT_LEN)
runs, dark_cells = [], set()
for _ in range(4 * BLINK_HALF[0] + 4):
    frames(1)
    now = panel(PROMPT_X, PROMPT_Y, PROMPT_LEN)
    if now != lit:
        dark_cells |= set(now)
    on = now == lit
    if runs and runs[-1][0] == on:
        runs[-1][1] += 1
    else:
        runs.append([on, 1])
check("it goes dark, comes back, and goes dark again",
      [r[0] for r in runs[:4]], [True, False, True, False])
check(f"...each half exactly BlinkHalf ({BLINK_HALF[0]}) frames",
      [r[1] for r in runs[1:3]], [BLINK_HALF[0]] * 2)
check("the dark half is blank — not a second string", sorted(dark_cells), [0])
check("what it puts back is PRESS FIRE, as the image has it",
      lit, tile_str("PRESS FIRE"))

print("\n...and the magic field crawls, one cell a frame (SPEC 13.1)")
to_title()
was, per_frame, touched, written = field(), [], set(), set()
for _ in range(400):
    frames(1)
    now = field()
    changed = [k for k in now if now[k] != was[k]]
    per_frame.append(len(changed))
    for k in changed:
        touched.add(k)
        written.add(now[k])
    was = now
check("never more than one cell in a frame", max(per_frame), 1)
check("...and it is doing something on nearly all of them",
      sum(per_frame) > 350, True)
check("every tile it writes is one of the 128 hatch tiles (Appendix A)",
      sorted(written)[0] >= ART_BASE and sorted(written)[-1] < ART_BASE
      + ART_TILES, True)
check("it reaches every one of the block's 28 cells", len(touched),
      FIELD_CELLS)
check("...and never a cell outside it",
      [i for i in sorted(moving) if screen()[i] != TITLE_IMAGE[i]], [])

print("\nSPEC 15 — the seed IS the frame counter at the press, not a constant")
to_title()
frames(9)
rpc("input.joystick", {"side": "b", "buttons": ["a"]})
rpc("exec.runTo", {"address": syms["RngSeed"], "timeout": "5s"})
fc = peek("FrameCounter")
rpc("exec.step", {"count": 5})                  # LDA ORA STA EOR STA, then RTS
check("RngLo is the counter with bit 0 forced", peek("RngLo"), fc | 1)
check("...and RngHi is the other half of the same byte", peek("RngHi"),
      (fc | 1) ^ 0x5A)
rpc("exec.runTo", {"address": syms["GameLoop"], "timeout": "5s"})
frames(1)
check("FIRE on the title starts a game", peek("GameState"), STATE_PLAY)


def deal(wait):
    """Start a game `wait` frames into the title screen; report what it dealt."""
    to_title()
    frames(wait)
    frames(1, ["a"])                            # FIRE — a fresh edge
    return [peek(n) for n in ("PieceA", "PieceB", "PieceC",
                              "NextA", "NextB", "NextC")]


print("\n...so two games from one boot are not the same game (P7 exit criteria)")
first, second = deal(5), deal(37)
print(f"  (first {first}, second {second})")
check("the two deals differ", first == second, False)

print("\nSPEC 13.3 — PAUSE washes the well; it does not blank it")
PAUSED = {(15, 0): RED, (15, 1): BLUE, (14, 0): GREEN + GLYPH_BOMB,
          (12, 4): PURPLE, (11, 4): YELLOW + GLYPH_STAR}
quiet()
set_board(PAUSED)
redraw()
poke("GameState", STATE_PLAY)
frames(1)
key("KeyP")
frames(8)                                       # 96 cells at 24 a frame, and
                                                #   the banner in front of them
check("P pauses", peek("GameState"), STATE_PAUSE)
check("all 96 cells of the well are the wash tile, board and empties alike",
      sorted(set(well().values())), [TILE_WASH])
check("the band says PAUSED (SPEC 12.2)", band("~~ PAUSED ~~"),
      tile_str("~~ PAUSED ~~"))

print("\n...and the clock stops while it is up")
frozen = [peek(n) for n in ("AreTimer", "FrameCounter", "PrismTimer")]
frames(60)
after = [peek(n) for n in ("AreTimer", "FrameCounter", "PrismTimer")]
check("the game's own timers do not move", (after[0], after[2]),
      (frozen[0], frozen[2]))
check("...but the frame counter does, because it feeds the RNG (SPEC 13.3)",
      after[1] != frozen[1], True)
check("the well is still covered a second later",
      sorted(set(well().values())), [TILE_WASH])

print("\n...and the board is still there underneath it")
check("nothing washed the board itself, only the screen", tiles(board()),
      PAUSED)
frames(2)
frames(1, ["a"])                                # FIRE resumes as well as P
frames(8)
check("resuming returns to play", peek("GameState"), STATE_PLAY)
check("the band is clear again", band(" " * 18), [0] * 18)
check("...and every cell of the well is back off the board",
      {k: v for k, v in well().items() if v}, PAUSED)

print("\nSPEC 13.4 — a blocked spawn ends the game")
#   The real path, not a planted state: the spawn column is filled to the top
#   and the ARE timer run out, which is the one and only way STATE_GAMEOVER is
#   ever entered.
SPAWN_COL = 2
DEAD = {(r, SPAWN_COL): RED + (r & 1) for r in range(16)}
DEAD[(15, 0)] = BLUE
quiet()
set_board(DEAD)
redraw()
poke("GameState", STATE_PLAY)
poke("HighOwned", 0)
poke("HighFlash", 0)
poke("AreTimer", 1)
frames(1)
check("the game is over", peek("GameState"), STATE_GAMEOVER)
check("the screen has not started counting itself out yet", peek("OverSecs"), 0)

print("\n...the well sets to stone BEFORE the band says anything (13.4 steps 2-3)")
#   One frame counter across both loops below, because the timeout is measured
#   from the frame it was armed on and not from wherever a loop happened to
#   start. `held` down the whole way, so the press-is-ignored check is real.
n, said_at, stone_at, armed_at = 0, None, None, None
while n < 48:
    frames(1, ["a"])
    n += 1
    if stone_at is None and peek("PetrifyRow") == 0xFF:
        stone_at = n
    if armed_at is None and peek("OverSecs"):
        armed_at = n
    if said_at is None and band("~~ GAME OVER! ~~") == tile_str("~~ GAME OVER! ~~"):
        said_at = n
check("sixteen rows at PETRIFY_FRAMES is 32 frames (SPEC 14)", stone_at,
      16 * PETRIFY_FRAMES)
check("FIRE held through the whole petrify is ignored, not queued",
      armed_at is not None and armed_at > stone_at, True)
check("the banner goes up the frame after the last row sets", said_at,
      armed_at + 1)
check("the timeout is running now", peek("OverSecs"), GAMEOVER_SECS)
check("no fanfare — this game did not take the high score", peek("HighFlash"), 0)

print("\n...and ten seconds later it is back on the title, unattended (step 5)")
left = None
while n < armed_at + GAMEOVER_SECS * SECOND_FRAMES[0] + 30:
    frames(1)
    n += 1
    if peek("GameState") == STATE_TITLE:
        left = n
        break
check(f"{GAMEOVER_SECS} seconds is {GAMEOVER_SECS * SECOND_FRAMES[0]} frames "
      f"of NTSC, counted from the banner", left is not None
      and left - armed_at, GAMEOVER_SECS * SECOND_FRAMES[0])
frames(3)                                       # The redraw the title asked for
check("...and the title screen is up, all 768 cells of it",
      [i for i in sorted(moving) if screen()[i] != TITLE_IMAGE[i]], [])


def die(owned):
    """Play a real game from the title, kill it, and see the petrify out.

    From the title and not from a poked GameState, because the play screen is
    an IMAGE the title screen has just painted over (SPEC 12.6) — GameStart is
    the only thing that puts it back, and every check below reads a panel field
    off it.
    """
    if peek("GameState") == STATE_TITLE:
        frames(2)                               # Release, so the press is fresh
        frames(1, ["a"])
        frames(8)                               # GameStart's own redraw
    quiet()
    set_board(DEAD)
    redraw()
    poke("HighOwned", owned)
    poke("HighFlash", 0)
    poke("AreTimer", 1)
    frames(1)
    for _ in range(48):
        frames(1)
        if peek("OverSecs"):
            return
    raise RuntimeError("the game never reached the game-over screen")


print("\nSPEC 13.4 step 4 — a game that took the high score gets a fanfare")
die(owned=1)
check("HIGH is set flashing, which is what SPEC 9.8's blink counts",
      peek("HighFlash"), HIGH_FLASH_BLINKS)
blanked = False
for _ in range(4 * BLINK_HALF[0]):
    frames(1)
    if digits(HIGH_X, HIGH_Y, SCORE_DIGITS) is None:
        blanked = True
check("...and the field really does go dark and come back", blanked, True)
frames(4 * BLINK_HALF[0])
check("it ends lit, always (SPEC 9.8)",
      digits(HIGH_X, HIGH_Y, SCORE_DIGITS) is not None, True)

print("\n...and FIRE ends the screen early rather than waiting out the ten")
die(owned=0)
frames(2)
frames(1, ["a"])
frames(1)
check("a press returns to the title", peek("GameState"), STATE_TITLE)

print("\nthe loop leaks nothing between games (P7 exit criteria)")
#   The high score survives a game; everything the last game earned does not.
set_high(123400)
poke("Level", 9)
set_score(50000)
frames(1)
frames(1, ["a"])                                # Start the next game from here
frames(6)
check("a new game is playing", peek("GameState"), STATE_PLAY)
check("the score is back to zero", score(), 0)
check("the level is back to 1", peek("Level"), 1)
check("the high score is not", high(), 123400)
check("nothing owns it yet", peek("HighOwned"), 0)
check("the band is clear", band(" " * 18), [0] * 18)
check("the board is empty — the piece is not in it until it locks",
      tiles(board()), {})
check("...and no wash is left over from a pause two games ago",
      peek("RedrawWash"), 0)

print("\nthe effect queue drained after every cascade in this run (SPEC 7.2)")
check(f"{len(queue_left)} cascades, all of them empty at the end",
      sorted(set(queue_left)), [0])

print()
print(f"{len(fails)} FAILED: {fails}" if fails else "all checks passed")
proc.terminate()
sys.exit(1 if fails else 0)
