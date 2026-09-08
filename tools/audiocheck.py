#!/usr/bin/env python3
"""Read what the two Commodores' sound chips are actually told, and check it.

`make playtest` proves the audio driver on the AC6502, where the channel can
be read out of RAM a byte at a time and the (timbre, note) pairs it hands the
platform can be caught in the CPU registers at HalSfx. None of that reaches
the machines whose HalSfx is a different routine against different hardware —
and those two are exactly where SPEC 16's register writes live.

VICE gives us something better than a screenshot for this. Its `dump` sound
device is not an audio device at all: it writes one line per SOUND CHIP
REGISTER WRITE, as `cycles-since-the-last-one register value`, so a headless
run leaves a complete transcript of everything the game told the SID or the
VIC-I and exactly when. That is what this reads.

    make audiocheck

Nothing here listens to anything. Each machine plays one headless game to game
over, its transcript is split into notes, and every note is compared against
what src/tables.inc says the effect should play once src/constants.inc's
timbres and the platform's own note table have been applied to it — the register
value byte for byte, the duration in frames. The two machines are then compared
against each other, because they run the same shared driver over the same game
and must therefore have said the same thing in the same order.

WHAT IT DOES NOT COVER. A headless game has no input and takes whatever the
seed deals it, so the effects that fire are the ones that need no player: the
run that starts a game, the lock thunk, and the run that ends it. Between them
they exercise TIMBRE_NOISE, TIMBRE_SOFT and TIMBRE_BRIGHT over eighteen
(timbre, note) pairs — and since SOFT halves a frequency and BRIGHT doubles it,
both ends of the range the note table can reach. What is left out is
TIMBRE_BUZZ, which is the same lookup a row over. It is checked on the AC6502,
at the HalSfx boundary, for all four timbres and every effect
(tools/playtest.py). This is the same limitation `make crosscheck` has and for
the same reason: there is no way to plant a board through VICE.

Run it from the repository root. Exits non-zero if anything disagrees.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Cycles to run. The AC6502's crosscheck window says the game is on the
# game-over screen from about 37M, and the fanfare that goes with it is over by
# 36.5M on both machines; 40M is past the last note and short of the ten-second
# timeout back to the title (SPEC 13.4).
CYCLES = "40000000"

# Cycles in one video frame, exactly: lines x cycles per line. Used only to
# check the frame length the transcript itself implies is a real one — the
# durations below are measured, not assumed.
FRAME_CYCLES = {"VIC20": {"NTSC": 261 * 65, "PAL": 312 * 71},
                "C64":   {"NTSC": 263 * 65, "PAL": 312 * 63}}

# Cycles at the start of a run during which a step's DURATION is not measured.
# The DEBUG cartridge skips the title and calls GameStart from GameInit, so the
# run that starts a game sounds on the machine's first few main-loop passes —
# and those passes are not yet frame-locked. They are flushing the initial
# screen redraw, and a pass that overruns vblank leaves the flag already set
# for the next one, which then returns without waiting: three steps of the
# start run measured 3.95, 2.76 and 2.52 frames before every step after them
# came out exact.
#
# It settles by frame 24, and that is measured rather than assumed — the
# SHIPPED cartridge sits on the title screen instead, and the first sound its
# ambience makes there begins at frame 24.1 and keeps 2.96 / 3.00 from the
# start. A real game begins hundreds of frames after that. So this window
# excludes a boot artifact of the test cartridge and nothing a player can hear.
#
# What is NOT skipped for that effect is its register content, which is checked
# like any other — and matters more than most, since the start run is the only
# TIMBRE_BRIGHT a headless game produces.
SETTLE_CYCLES = 700000                  # ~41 frames NTSC, ~31 PAL

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


# =============================================================================
#   What the sources say should come out
# =============================================================================
#   Read from src/, not retyped here. A number that appears in both this file
#   and the cartridge is a number that can agree with itself and be wrong.

def read_constants(path, names):
    """The `NAME = expression` lines of an .inc, evaluated in order."""
    out = {}
    for line in open(path):
        line = line.split(";")[0]
        m = re.match(r"\s*(\w+)\s*=\s*(.+?)\s*$", line)
        if not m or m.group(1) not in names:
            continue
        expr = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", m.group(2))
        out[m.group(1)] = eval(expr, {"__builtins__": {}}, dict(out))
    missing = names - set(out)
    if missing:
        sys.exit(f"audiocheck: {path} defines none of {sorted(missing)}")
    return out


def read_bytes(path, label, consts):
    """The `.byte` rows under one label, up to the next label."""
    rows, seen = [], False
    for line in open(path):
        line = line.split(";")[0].rstrip()
        if re.match(rf"\s*{label}:", line):
            seen = True
            continue
        if not seen:
            continue
        if re.match(r"\s*\w+:", line):
            break
        m = re.match(r"\s*\.byte\s+(.+)$", line)
        if not m:
            continue
        for tok in m.group(1).split(","):
            tok = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", tok.strip())
            rows.append(eval(tok, {"__builtins__": {}}, dict(consts)))
    if not rows:
        sys.exit(f"audiocheck: no .byte rows under {label} in {path}")
    return rows


CONST_NAMES = ({"TIMBRE_OFF", "TIMBRE_SOFT", "TIMBRE_BUZZ", "TIMBRE_BRIGHT",
                "TIMBRE_NOISE", "NOTE_MAX", "SFX_STEP_BYTES"}
               | {f"OCT_{n}" for n in (3, 4, 5, 6)}
               | {f"SEMI_{n}" for n in "CDEFGAB"})
K = read_constants(os.path.join(ROOT, "src", "constants.inc"), CONST_NAMES)

#   SPEC 16's twelve, plus the thirteenth that starts a game (src/tables.inc).
#   That one matters here out of proportion to its size: a headless game plays
#   it, and it is TIMBRE_BRIGHT, which nothing else a headless game reaches
#   uses.
SFX_LABELS = ["SfxMove", "SfxRotate", "SfxLock", "SfxMatch", "SfxFireball",
              "SfxBolt", "SfxBomb", "SfxStar", "SfxPrism", "SfxLevelUp",
              "SfxHighScore", "SfxGameOver", "SfxStart"]

TABLES = os.path.join(ROOT, "src", "tables.inc")
SCRIPTS = {}
for label in SFX_LABELS:
    raw = read_bytes(TABLES, label, K)
    steps = []
    while raw and raw[0]:
        steps.append(tuple(raw[:3]))
        raw = raw[3:]
    SCRIPTS[label[3:]] = steps

SID = os.path.join(ROOT, "include", "sid.inc")
SID_WAVE = read_bytes(SID, "SidWave", K)
SID_NOTE = [lo | (hi << 8)
            for lo, hi in zip(read_bytes(SID, "SidNoteLo", K),
                              read_bytes(SID, "SidNoteHi", K))]

VIC = os.path.join(ROOT, "VIC20", "WizardsLab.asm")
VIC_OSC = read_bytes(VIC, "VicOsc", K)
VIC_NOTE = read_bytes(VIC, "VicNotes", K)


def expect(plat, timbre, note):
    """The one register value this (timbre, note) has to reach the chip as.

    A timbre is a voice and an OCTAVE (constants.inc): on the SID the octave is
    a shift of a linear frequency register, and on the VIC-I it is which of
    three oscillators sounds the same 7-bit number, because they are already an
    octave apart. That difference is the whole of what this file is checking.
    """
    if plat == "C64":
        freq = SID_NOTE[note]
        if timbre == K["TIMBRE_SOFT"]:
            freq >>= 1
        elif timbre == K["TIMBRE_BRIGHT"]:
            freq = (freq << 1) & 0xFFFF
        return SID_WAVE[timbre - 1], freq
    return 10 + VIC_OSC[timbre - 1], 0x80 | VIC_NOTE[note]


EXPECTED = {p: {name: [expect(p, t, n) for _, t, n in steps]
                for name, steps in SCRIPTS.items()}
            for p in ("C64", "VIC20")}


def note_name(n):
    return f"{NOTE_NAMES[n % 12]}{3 + n // 12}"


# =============================================================================
#   What actually came out
# =============================================================================

def transcript(plat):
    """Play one headless game and return VICE's sound register transcript.

    +saveres matters: without it VICE writes every option on this command line
    into the user's own vicerc on exit, and a `-sounddev dump` left behind
    there silences the next person to open the emulator by hand.
    """
    emu = {"VIC20": "xvic", "C64": "x64sc"}[plat]
    cart = (["-cartA", "WizardsLab-blk5.crt", "-cart6", "WizardsLab-blk3.crt"]
            if plat == "VIC20" else ["-cart16", "WizardsLab.crt"])
    out = os.path.join(ROOT, plat, "WizardsLab-audio.txt")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run([emu, "-console", "+saveres", "-warp", "-sound",
                    "-soundwarpmode", "1", "-sounddev", "dump",
                    "-soundarg", out, "-limitcycles", CYCLES, *cart],
                   cwd=os.path.join(ROOT, plat), stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(out):
        sys.exit(f"audiocheck: {plat} wrote no transcript — it did not boot, "
                 f"or this VICE has no `dump` sound device")
    at, events = 0, []
    for line in open(out):
        parts = line.split()
        if len(parts) != 3:
            continue
        at += int(parts[0])
        events.append((at, int(parts[1]), int(parts[2])))
    return events


def notes(plat, events, gap=1000):
    """Split a transcript into notes: one HalSfx call is one entry.

    Every call writes its registers back to back and the next is a frame or
    more away, so a gap of a thousand cycles is an unambiguous divider — the
    widest gap inside a call is twenty-odd.
    """
    out, group, prev = [], [], None
    for e in events:
        if prev is not None and e[0] - prev > gap:
            out.append(group)
            group = []
        group.append(e)
        prev = e[0]
    if group:
        out.append(group)

    played = []
    for g in out:
        wrote = {}
        for _, reg, val in g:
            wrote[reg] = val                    # The LAST write to a register
        if plat == "C64":
            key = None if not wrote.get(4) else (
                wrote[4], wrote.get(0, 0) | (wrote.get(1, 0) << 8))
        else:
            on = [(r, v) for r in (10, 11, 12, 13)
                  for v in [wrote.get(r, 0)] if v]
            key = on[0] if on else None
        played.append((g[0][0], key))
    return played


def split_effects(played):
    """A run of notes ending in silence is one effect. Returns them in order."""
    runs, cur = [], []
    for at, key in played:
        if key is None:
            if cur:
                runs.append((cur, at))          # ...and where it fell silent
            cur = []
        else:
            cur.append((at, key))
    if cur:
        runs.append((cur, None))
    return runs


# =============================================================================
#   The check
# =============================================================================

fails = []


def check(label, got, want):
    ok = got == want
    if not ok:
        fails.append(label)
    print(f"  {'ok  ' if ok else 'FAIL'} {label}: got {got}, want {want}")


def examine(plat):
    print(f"\n{plat}: one headless game, {CYCLES} cycles, every sound register "
          f"write logged")
    played = notes(plat, transcript(plat))
    runs = split_effects(played)

    heard, spans, began = [], [], []
    for cells, silent in runs:
        began.append(cells[0][0])
        keys = [k for _, k in cells]
        name = next((n for n, want in EXPECTED[plat].items() if want == keys),
                    None)
        if name is None:
            partial = next((n for n, want in EXPECTED[plat].items()
                            if want[:len(keys)] == keys), None)
            name = f"<{partial} cut short>" if partial else f"<unknown {keys}>"
        heard.append(name)
        ends = [c[0] for c in cells[1:]] + ([silent] if silent else [])
        spans.append([(b - a) for a, b in zip([c[0] for c in cells], ends)])

    print(f"  heard: {', '.join(heard)}")
    check("every sound is one of the thirteen, played to its end",
          [n for n in heard if n.startswith("<")], [])
    check("the run that starts a game and the one that ends it are both there",
          ("Start" in heard, "GameOver" in heard), (True, True))

    #   The frame length the transcript itself implies, and then whether it is
    #   a real one. The FIRST step of an effect is left out of both: it starts
    #   at whatever point in its frame AudioTick was reached, and the frame a
    #   lock happens in is the frame that also ran a match scan, so the gap
    #   after it is short by however long that took. Every step after it is
    #   measured between two ordinary frames and is exact.
    measured = []
    for name, span, at in zip(heard, spans, began):
        if at < SETTLE_CYCLES:                  # The frame clock is still
            continue                            #   settling — see above
        want = [s[0] for s in SCRIPTS.get(name, [])]
        for cycles, frames in list(zip(span, want))[1:]:
            measured.append(cycles / frames)
    frame = sorted(measured)[len(measured) // 2]
    region = min(FRAME_CYCLES[plat],
                 key=lambda r: abs(FRAME_CYCLES[plat][r] - frame))
    print(f"  ({len(measured)} steps measured; one frame is {frame:.0f} cycles,"
          f" which is {plat} {region} at {FRAME_CYCLES[plat][region]})")
    check(f"...and that is a real {plat} frame, within 1%",
          abs(frame - FRAME_CYCLES[plat][region]) / frame < 0.01, True)

    off = []
    for name, span, at in zip(heard, spans, began):
        if at < SETTLE_CYCLES:
            continue
        want = [s[0] for s in SCRIPTS.get(name, [])]
        for i, (cycles, frames) in enumerate(zip(span, want)):
            if i == 0:
                continue
            if abs(cycles / frame - frames) > 0.15:
                off.append((name, i, round(cycles / frame, 2), frames))
    check("every step lasts the frames tables.inc gave it, once the frame "
          "clock has settled", off, [])

    for name in ("Start", "Lock", "GameOver"):
        if name not in heard:
            continue
        i = heard.index(name)
        cells = [k for _, k in runs[i][0]]
        check(f"{name} is register for register what the tables say",
              cells, EXPECTED[plat][name])
        print("        " + "  ".join(
            f"{note_name(n)}/{['','soft','buzz','bright','noise'][t]}"
            for _, t, n in SCRIPTS[name]))
    return heard, [k for _, k in played]


def main():
    os.chdir(ROOT)
    print("what the sources say the thirteen effects are:")
    print(f"  {len(SCRIPTS)} effects, "
          f"{sum(len(v) for v in SCRIPTS.values())} steps, "
          f"notes {note_name(min(n for v in SCRIPTS.values() for _, _, n in v))}"
          f" to {note_name(max(n for v in SCRIPTS.values() for _, _, n in v))}")

    seen = {}
    for plat in ("C64", "VIC20"):
        seen[plat] = examine(plat)

    print("\n...and the two machines played the same game, so they said the "
          "same thing")
    #   Not the same register values — a SID and a VIC-I have nothing in
    #   common there — but the same effects in the same order, which is the
    #   shared driver's output and the half of this that is not per platform.
    check("the same sounds, in the same order",
          seen["C64"][0], seen["VIC20"][0])

    print()
    print(f"{len(fails)} FAILED: {fails}" if fails else "all checks passed")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
