#!/usr/bin/env python3
"""Take the screenshots the README shows, and check they show what it says.

`make smoke` already leaves a PNG beside each Commodore cartridge, but those
are throwaway — `*-screenshot.png` is gitignored, and the cycle count they are
taken at is chosen to prove the cartridge came up rather than to look like
anything. These are the committed ones. They live in docs/ under names git
keeps, and `make screenshots` regenerates them from the current build.

Two shots per Commodore, both off the SHIPPED cartridge:

  docs/<plat>-title.png   the title screen, with its prompt showing
  docs/<plat>-play.png    a game in progress, 32 pieces in

**The play shots are played, not planted.** A game left to itself drops every
piece down the spawn column and photographs as one dull stripe, so this drives
the game the way a player does: VICE's remote monitor holds a breakpoint on
`HalReadInput` and puts a joystick mask in A on the way out of it, one frame at
a time, which is the same conditioning a real stick goes through — the rotate
edge, the auto-repeat, the lock delay (SPEC 11). Nothing here writes the board,
the score or the piece. Where to aim is the flattest-column rule in aim(), and
the well fills the way someone playing would fill it.

The game is the cartridge's own: FIRE is pressed on the title screen and
`RngSeed` takes the frame counter (rng.asm), which is poked to a fixed value
first so the same game is dealt every run and on both machines. SEED_FRAME is
chosen for what it deals — a game with reagents in it, because a picture of
Wizards Lab with no reagent in the well is a picture of the wrong game.

That both machines really did play the same game is checked rather than
assumed: the two wells are read back off the two PNGs with tools/read-screen.py
and compared cell for cell, the same way `make crosscheck` compares three
machines at game over.

The title shots have a different problem: the prompt BLINKS (SPEC 14), so half
of all cycle counts catch `PRESS FIRE` blanked, which is a poor advertisement.
Rather than freeze a magic number that a timing change would silently rot, the
run steps forward by half a blink period until the prompt is on screen, and
gives up after two whole periods — by which point the prompt is not being drawn
at all, and no cycle count would have caught it.

    make screenshots

Run from the repository root. Needs both emulators, Pillow, and the `-g` builds
`make screenshots` leaves in /tmp for the symbols — the cartridges photographed
are the shipped ones, which those builds are byte-for-byte identical to.
"""
import os
import random
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

read_screen = import_module("read-screen").read_screen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = "docs"

EMU = {"VIC20": "xvic", "C64": "x64sc"}
CART = {"VIC20": ["-cartA", "WizardsLab-blk5.crt", "-cart6", "WizardsLab-blk3.crt"],
        "C64": ["-cart16", "WizardsLab.crt"]}
DBGFILE = {"VIC20": "/tmp/wl-vic20.dbg", "C64": "/tmp/wl-c64.dbg"}
MONPORT = 6510

# --- the title shots ---------------------------------------------------------
#
# Far enough in for the boot to be over and the magic field to have shimmered
# (SPEC 13.1 — one random tile a frame into 28 cells, so ~150 frames is several
# times over). Half of SPEC 14's blink period is 13 PAL frames, at 22152 cycles
# a frame on the VIC-20 (71 x 312) and 19656 on the C64 (63 x 312); one step
# flips the prompt, so four tries covers two whole periods. VICE's default for
# both machines is PAL.
TITLE_CYCLES = {"VIC20": 3_000_000, "C64": 3_000_000}
BLINK_STEP = {"VIC20": 13 * 22152, "C64": 13 * 19656}
BLINK_TRIES = 4

# `PRESS FIRE` as the artist drew it, read straight out of the master screen
# image: row PROMPT_Y, PROMPT_LEN cells from PROMPT_X, panel-relative, and the
# AC6502 panel sits at column 5 of the 32-column master (SPEC 12.4). The tile
# numbers are the same on all three machines, so the same run is looked for in
# a Commodore's screen — which also makes the search immune to where the panel
# landed, and a title screen has to be read without coordinates for the reason
# tools/read-screen.py's docstring gives.
MASTER = "data/screen-title-ac6502.bin"
MASTER_W, MASTER_PANEL = 32, 5
PROMPT_X, PROMPT_Y, PROMPT_LEN = 6, 11, 10
FIELD_TILE = 160                        # What the field's 28 cells start as

# --- the play shots ----------------------------------------------------------
#
# SEED_FRAME is what FrameCounter is set to before FIRE, so it is the whole
# game: RngSeed spreads that one byte over both halves of the LFSR (rng.asm)
# and every colour, every reagent and every piece follows from it. $C3 was
# picked by running the model of PieceGenerateNext in tools/playtest.py over
# all 256 of them — it deals six reagents in its first eighteen pieces, one of
# each kind, where most seeds deal two or three.
SEED_FRAME = 0xC3
PIECES = 32                             # Pieces to place before photographing
AIM_SEED = 3                            # The tie-break rolls in aim(), fixed

# What the shot has to show before it is worth committing. The numbers are
# floors well under what this game actually reaches (59 cells, 3 reagents), so
# ordinary drift does not fail the run — a different game does.
MIN_FILLED = 40
MIN_REAGENTS = 2

INPUT_UP, INPUT_DOWN, INPUT_LEFT, INPUT_RIGHT, INPUT_FIRE = 1, 2, 4, 8, 16
STATE_PLAY = 1                          # GameState (SPEC 13)
PLAY_FALLING = 0                        # PlayState

# The board, as the game holds it (SPEC 3.3): 16 rows of 8, six of them the
# playfield and two the wall sentinels.
BOARD_W, BOARD_H, STRIDE = 6, 16, 8
COLOR_MASK, GLYPH_MASK = 0xF8, 0x07
WILD_BASE = 0x70                        # The prism's own group
GLYPH_REAGENTS = (1, 2, 3, 4)           # Fireball, bolt, bomb, star

# The well, in the coordinates tools/read-screen.py hands back — the same ones
# tools/crosscheck.py reads it in (SPEC 12.2).
WELL_X, WELL_Y = 1, 4
PANEL_X = {"VIC20": 0, "C64": 9}


def prompt_tiles():
    img = open(MASTER, "rb").read()
    base = PROMPT_Y * MASTER_W + MASTER_PANEL + PROMPT_X
    return list(img[base:base + PROMPT_LEN])


def contains_run(grid, run):
    """Is this sequence of tiles somewhere in a row of the screen?"""
    return any(row[c:c + len(run)] == run
               for row in grid for c in range(len(row) - len(run) + 1))


def staged_path(path):
    """Where a shot is written before it has passed its checks.

    Next to its destination and not onto it: a shot that fails is a shot nobody
    should commit, and a run that dies half way through used to leave one there
    — a blank prompt, or a well from the wrong moment, with nothing to say it
    was not what the README claims. VICE picks the image format off the
    extension and appends .png if it does not find one, so the staging name has
    to keep it.
    """
    return path[:-len(".png")] + ".new.png"


def commit(staged):
    for tmp, path in staged:
        os.replace(os.path.join(ROOT, tmp), os.path.join(ROOT, path))


def discard(staged):
    for tmp, _ in staged:
        tmp = os.path.join(ROOT, tmp)
        if os.path.exists(tmp):
            os.remove(tmp)


# =============================================================================
#   The title shots — a cycle count, and a check that it caught the prompt
# =============================================================================

def capture_at(plat, cycles, path):
    """Boot the cartridge headless in warp and screenshot it at `cycles`."""
    out = os.path.join(ROOT, staged_path(path))
    subprocess.run([EMU[plat], "-console", "+saveres", "-warp",
                    "-limitcycles", str(cycles), *CART[plat],
                    "-exitscreenshot", out],
                   cwd=os.path.join(ROOT, plat),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(out) or os.path.getsize(out) == 0:
        sys.exit(f"screenshots: {plat} wrote nothing at {cycles} cycles — the "
                 f"cartridge did not come up")
    return read_screen(out, plat)[1]


def title(plat):
    """The title screen, with the prompt showing."""
    want = prompt_tiles()
    path = f"{OUTDIR}/{plat.lower()}-title.png"
    for i in range(BLINK_TRIES):
        cycles = TITLE_CYCLES[plat] + i * BLINK_STEP[plat]
        grid = capture_at(plat, cycles, path)
        if not contains_run(grid, want):
            continue                    # Caught on the blink's dark half
        # The field is drawn as 28 cells of one hatch tile and the title screen
        # scribbles a random one from 128-255 into one of them every frame, so
        # a screen holding nothing but the drawn tile is a picture and not a
        # running title.
        scribbled = {v for row in grid for v in row if v >= 128} - {FIELD_TILE}
        if not scribbled:
            discard([(staged_path(path), path)])
            sys.exit(f"screenshots: {plat}'s magic field is still the tile it "
                     f"was drawn as at {cycles} cycles — the title screen is "
                     f"not animating (SPEC 13.1)")
        print(f"{plat}: {cycles} cycles, title with the prompt showing "
              f"-> {path}")
        return [(staged_path(path), path)]
    discard([(staged_path(path), path)])
    sys.exit(f"screenshots: {plat} never showed PRESS FIRE across "
             f"{BLINK_TRIES} half-periods from {TITLE_CYCLES[plat]} cycles. "
             f"Either the title screen is not up by then or the prompt is not "
             f"being drawn at all (SPEC 13.1).")


# =============================================================================
#   The play shots — a game, played through VICE's monitor
# =============================================================================

class Machine:
    """A Commodore in VICE, stopped every frame where its input is read.

    VICE's remote monitor is a line protocol: send a command, read back to the
    next `(C:$xxxx)` prompt. Everything below is four of them — run, step out,
    poke, peek — and the only byte of the game's own memory this writes is the
    frame counter, one frame before FIRE.
    """

    def __init__(self, plat):
        self.plat = plat
        self.syms = self.symbols(plat)
        self.require_free_port()
        self.proc = subprocess.Popen(
            [EMU[plat], "-console", "+saveres", "-warp", "-remotemonitor",
             "-remotemonitoraddress", f"ip4://127.0.0.1:{MONPORT}",
             *CART[plat]],
            cwd=os.path.join(ROOT, plat),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.connect()
        self.cmd(f"break c:{self.syms['HalReadInput']:04x}")

    @staticmethod
    def symbols(plat):
        """Addresses out of the -g build the Makefile leaves in /tmp.

        It is a separate build only because the shipped cartridge carries no
        debug file: `-g` changes not one byte of the output, which is what
        makes it safe to read one build's addresses off the other.
        """
        path = DBGFILE[plat]
        if not os.path.exists(path):
            sys.exit(f"screenshots: no {path} — run `make screenshots` rather "
                     f"than this script, so the -g builds get made")
        syms = {}
        for line in open(path):
            m = re.match(r'sym\s+id=\d+,name="([^"]+)".*?,val=(0x[0-9a-fA-F]+)',
                         line)
            if m:
                syms[m.group(1)] = int(m.group(2), 16)
        return syms

    def require_free_port(self):
        """Fail loudly if an emulator from an earlier run still holds the port.

        Otherwise this one dies with EADDRINUSE into /dev/null and every
        command below is answered by the OTHER machine — the same trap
        tools/crosscheck.py guards its debug port against.
        """
        s = socket.socket()
        s.settimeout(0.5)
        try:
            s.connect(("127.0.0.1", MONPORT))
        except OSError:
            return
        finally:
            s.close()
        sys.exit(f"screenshots: port {MONPORT} already has a listener — an "
                 f"emulator from an earlier run is still alive. Kill it "
                 f"(lsof -nP -iTCP:{MONPORT}) and try again.")

    def connect(self, timeout=20):
        end = time.time() + timeout
        while time.time() < end:
            try:
                self.sock = socket.create_connection(("127.0.0.1", MONPORT), 1)
                break
            except OSError:
                time.sleep(0.2)
        else:
            sys.exit(f"screenshots: {self.plat}'s monitor never came up")
        self.sock.settimeout(30)
        self.sock.sendall(b"\n")            # The monitor answers; it does not
        self.read_to_prompt()               #   greet, so ask it something

    def read_to_prompt(self):
        out = b""
        while True:
            m = re.search(rb"\(C:\$[0-9a-f]{4}\)\s*$", out)
            if m:
                return out[:m.start()].decode(errors="replace")
            more = self.sock.recv(65536)
            if not more:
                raise EOFError(f"{self.plat}'s monitor closed the connection")
            out += more

    def cmd(self, text):
        self.sock.sendall(text.encode() + b"\n")
        return self.read_to_prompt()

    # --- the game, one frame at a time ---------------------------------------

    def frame(self, mask):
        """Run to the next input read and hand the game this joystick mask.

        `x` runs on to the breakpoint on HalReadInput, `ret` steps out of it,
        and the mask goes into A exactly where the platform's own read would
        have left it — so InputPoll's edge detection, the auto-repeat and the
        lock delay all see a stick being held (SPEC 11.1, 11.3).
        """
        self.cmd("x")
        self.cmd("ret")
        self.cmd(f"r a={mask:02x}")

    def read(self, addr, length):
        out = self.cmd(f"m c:{addr:04x} {addr + length - 1:04x}")
        vals = []
        for line in out.splitlines():
            m = re.match(r">C:[0-9a-f]{4}\s\s((?:[0-9a-f]{2}\s\s?)+)",
                         line.strip())
            if m:
                vals += [int(h, 16) for h in m.group(1).split()]
        return vals[:length]

    def peek(self, sym):
        return self.read(self.syms[sym], 1)[0]

    def poke(self, sym, value):
        self.cmd(f"> c:{self.syms[sym]:04x} {value:02x}")

    def board(self):
        return self.read(self.syms["Board"], BOARD_H * STRIDE)

    def screenshot(self, path):
        self.cmd(f'screenshot "{os.path.join(ROOT, path)}" 2')   # 2 = PNG

    def close(self):
        try:
            self.cmd("quit")
        except (OSError, EOFError):
            pass                            # It quit before it could answer
        time.sleep(0.3)
        self.proc.kill()


def column_heights(bd):
    """(height, top tile) for each of the six columns."""
    out = []
    for c in range(BOARD_W):
        for r in range(BOARD_H):
            if bd[r * STRIDE + c]:
                out.append((BOARD_H - r, bd[r * STRIDE + c]))
                break
        else:
            out.append((0, 0))
    return out


def aim(bd, bottom, rng):
    """Which column to drop this piece down.

    The flattest column, minus a bonus for landing the piece's bottom cell on
    its own colour — the whole of the strategy, and enough of one that the well
    fills with runs and clears rather than growing straight up until the game
    ends. The roll only separates columns that are level with each other, and
    it is seeded, so the same game is played every run.
    """
    best, best_score = 0, None
    for c, (height, top) in enumerate(column_heights(bd)):
        score = height + rng.random() * 1.5
        if top and (top & COLOR_MASK) == (bottom & COLOR_MASK):
            score -= 3
        if best_score is None or score < best_score:
            best, best_score = c, score
    return best


def reagents(bd):
    """Every reagent sitting in the well, as (row, col, tile)."""
    out = []
    for r in range(BOARD_H):
        for c in range(BOARD_W):
            t = bd[r * STRIDE + c]
            if t and ((t & GLYPH_MASK) in GLYPH_REAGENTS
                      or WILD_BASE <= t < WILD_BASE + 8):
                out.append((r, c, t))
    return out


def play(plat):
    """Play a game on the shipped cartridge and photograph it mid-game."""
    path = f"{OUTDIR}/{plat.lower()}-play.png"
    rng = random.Random(AIM_SEED)
    vm = Machine(plat)
    try:
        vm.frame(0)                          # Land on a frame boundary
        vm.poke("FrameCounter", SEED_FRAME)  # The seed RngSeed is about to take
        vm.frame(INPUT_FIRE)                 # Start the game as a player does
        vm.frame(0)

        placed, target, frames = 0, None, 0
        while placed < PIECES and frames < 12000:
            if vm.peek("GameState") != STATE_PLAY:
                sys.exit(f"screenshots: {plat}'s game ended after {placed} "
                         f"pieces — PIECES is past what this seed survives, or "
                         f"aim() has stopped keeping the well alive")
            if vm.peek("PlayState") != PLAY_FALLING:
                target = None                # A clear or a fall is running
                vm.frame(0)
                frames += 1
                continue
            if target is None:               # A new piece is in the air
                target = aim(vm.board(), vm.peek("PieceC"), rng)
                placed += 1
                for _ in range(rng.randint(0, 2)):
                    vm.frame(INPUT_UP)       # Rotate is edge-triggered: press,
                    vm.frame(0)              #   release, press (SPEC 11.1)
                    frames += 2
            col = vm.peek("PieceCol")
            vm.frame(INPUT_RIGHT if col < target else
                     INPUT_LEFT if col > target else INPUT_DOWN)
            frames += 1

        # Photograph a frame that looks like a game rather than the gap between
        # two: a piece in the air, near the top, with nothing animating.
        for _ in range(300):
            if vm.peek("PlayState") == PLAY_FALLING and vm.peek("PieceRow") <= 2:
                break
            vm.frame(0)

        bd = vm.board()
        filled = sum(1 for r in range(BOARD_H) for c in range(BOARD_W)
                     if bd[r * STRIDE + c])
        found = reagents(bd)
        if filled < MIN_FILLED or len(found) < MIN_REAGENTS:
            sys.exit(f"screenshots: {plat} is showing {filled} cells and "
                     f"{len(found)} reagents after {PIECES} pieces, under the "
                     f"{MIN_FILLED}/{MIN_REAGENTS} this shot is worth "
                     f"committing at. The game SEED_FRAME deals has drifted — "
                     f"pick another with the model in tools/playtest.py.")
        vm.screenshot(staged_path(path))
        print(f"{plat}: {placed} pieces, level {vm.peek('Level')}, "
              f"{filled} cells, {len(found)} reagents -> {path}")
    finally:
        vm.close()

    grid = read_screen(os.path.join(ROOT, staged_path(path)), plat)[1]
    x0 = PANEL_X[plat] + WELL_X
    well = [row[x0:x0 + BOARD_W] for row in grid[WELL_Y:WELL_Y + BOARD_H]]
    return well, (staged_path(path), path)


def main():
    os.chdir(ROOT)
    stages = sys.argv[1:] or ["play", "title"]
    if any(s not in ("play", "title") for s in stages):
        sys.exit("usage: screenshots.py [play|title]  (see `make screenshots`)")
    os.makedirs(OUTDIR, exist_ok=True)

    if "play" in stages:
        wells, staged = {}, []
        try:
            for plat in ("VIC20", "C64"):
                wells[plat], shot = play(plat)
                staged.append(shot)
        except SystemExit:
            discard(staged)             # One machine's shot, and the other
            raise                       #   machine's refusal to match it
        if wells["VIC20"] != wells["C64"]:
            for plat, well in wells.items():
                print(f"\n{plat}:")
                for row in well:
                    print("   " + " ".join("  ." if v == 0 else "%3d" % v
                                           for v in row))
            discard(staged)
            sys.exit("\nscreenshots: the two machines played the same game to "
                     "different wells, which is either a real cross-platform "
                     "bug — run `make crosscheck` — or one emulator not driven "
                     "frame for frame the way the other was.")
        commit(staged)
        print("both machines played the same game to the same well, "
              "cell for cell")

    if "title" in stages:
        staged = []
        for plat in ("VIC20", "C64"):
            staged += title(plat)
        commit(staged)


if __name__ == "__main__":
    main()
