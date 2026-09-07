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
    whatever rate the flush drains it (D12), so wait for it to run out.
    """
    poke("RedrawIdx", 0)
    for _ in range(30):
        frames(1)
        if peek("RedrawIdx") == 0xFF:
            return
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
got, runs, chain, left = scored({
    (15, 0): RED, (15, 1): RED, (15, 2): RED + GLYPH_FIREBALL,
    (12, 0): RED, (12, 4): WILD})
check("the prism survived a red fireball", left, {(15, 4): WILD})
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
COLOR_MASK, GLYPH_MASK = 0xF8, 0x07


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
rpc("exec.runTo", {"address": syms["CascadeRemove"], "timeout": "5s"})
c2 = cycles()
print(f"  (scan {c1 - c0} cycles, then enqueue + resolve {c2 - c1}, "
      f"against a 16667-cycle frame)")
check("the reagents cost less than the scan they follow", c2 - c1 < c1 - c0, True)
frames(1)                                       # Back to the top of the loop
while peek("PlayState") != PLAY_ARE and used < 800:
    frames(1)
    used += 1

print("\nthe effect queue drained after every cascade in this run (SPEC 7.2)")
check(f"{len(queue_left)} cascades, all of them empty at the end",
      sorted(set(queue_left)), [0])

print()
print(f"{len(fails)} FAILED: {fails}" if fails else "all checks passed")
proc.terminate()
sys.exit(1 if fails else 0)
