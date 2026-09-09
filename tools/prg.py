#!/usr/bin/env python3
"""Build the VIC-20 disk version: one .prg that loads and runs the cartridge.

Called by tools/package.py, which puts the result in run/ beside the .crt.

WHY THIS EXISTS

A .crt is a container for something that emulates cartridge ROM -- VICE, a
Final Expansion 3, an Ultimate II+. It is useless to a disk drive, and a disk
drive is what most people actually have hanging off a real VIC-20: an sd2iec,
a Penultimate Cartridge's SD side, a 1541. Those speak the serial bus. They
can hand the machine a file; they cannot put ROM in the address space at reset,
which is when the KERNAL looks for the A0CBM signature that starts a cartridge.

So a cartridge reaches a disk as a PROGRAM that puts itself where the cartridge
would have been. That is what every cart-to-disk conversion on an sd2iec card
is, and they all have the same three parts:

    a one-line BASIC program, `10 SYS <addr>`, so LOAD and RUN starts it
    a machine-code copier at <addr>
    the ROM image itself, carried along as payload

The copier moves the payload to the addresses the cartridge lives at and jumps
to its cold-start vector. From that instruction on, the machine is running the
same bytes a real cartridge would have run.

THE VIC-20'S COMPLICATION

Wizards Lab is 16 KB in two 8 KB blocks at different addresses -- BLK5 at
$A000 (code) and BLK3 at $6000 (artwork) -- with $8000-$9FFF in between being
I/O, colour RAM and character ROM. A .prg is one contiguous run of bytes from
one load address, so the two blocks cannot simply be laid down where they
belong: a file that spanned them would write 8 KB of payload across the VIC
chip's registers on its way past.

Hence the copy. The file loads low, into BASIC's RAM, and the copier lifts the
two halves out to $6000 and $A000.

WHAT IT NEEDS ON THE MACHINE

    BLK1 + BLK2   to hold the file while it loads ($1201-$52FF)
    BLK3          destination, $6000
    BLK5          destination, $A000

which is 32K of expansion, or 35K with the 3K block that BASIC ignores anyway.
On a Penultimate Cartridge that is the top RAM setting; on anything else it is
the "fully expanded" one. Less than that and there is nowhere to put half the
game, so build_prg() states the requirement and verify_prg() proves the file
comes up on a machine that has it.

$1201 is where BASIC starts on any VIC-20 with RAM in BLK1 -- 8K through 35K
all agree, because RAMTAS prefers BLK1 and leaves the 3K block out of BASIC.
That is why the conversions on an sd2iec card are nearly all $1201 files, and
why this one is too.
"""
import os
import struct
import subprocess
import sys

# Where the pieces sit in the loaded file. The ML is at a round number for the
# same reason the SYS in a hand-made conversion is: it has to be typed into a
# BASIC line as decimal digits, and a tidy one is easier to read back out of a
# hex dump when something has gone wrong.
BASIC_START = 0x1201        # BASIC's first byte, any VIC-20 with BLK1 RAM
ML_BASE     = 0x1210        # the copier; SYS 4624
PAY_BASE    = 0x1300        # payload, page-aligned so the copier's #> is exact

BLOCK = 0x2000              # one VIC-20 expansion block, and one of our ROMs

# Zero page. $FB-$FE are the four bytes the VIC-20 leaves free for exactly
# this: a pair of pointers for an indirect copy. Nothing here returns to the
# KERNAL, so there is no one to give them back to.
ZP_SRC = 0xFB
ZP_DST = 0xFD


def basic_stub(sys_addr, end_addr):
    """`10 SYS <sys_addr>`, padded out to end_addr.

    A BASIC line is a link to the next line, a line number, the tokenised
    text, and a zero; the program ends with a zero link. SYS is one token
    ($9E) and its argument is plain digits, which is why the ML address has to
    be decimal-friendly rather than a nice hex number.
    """
    text = b"\x9e" + str(sys_addr).encode("ascii")
    line = struct.pack("<HH", 0, 10) + text + b"\x00"     # link patched below
    link = BASIC_START + len(line)
    line = struct.pack("<HH", link, 10) + text + b"\x00"
    prog = line + b"\x00\x00"                              # end of program
    pad = end_addr - (BASIC_START + len(prog))
    if pad < 0:
        sys.exit(f"prg: the BASIC stub does not fit below {end_addr:#06x}")
    return prog + b"\x00" * pad


def copier(pay3, pay5, entry):
    """The machine code at ML_BASE: two block copies, then into the cartridge.

    Assembled by hand because it is sixty-one bytes and adding a dependency on
    an assembler to place sixty-one bytes would be the larger complication.
    Every branch offset below is computed from the emitted length rather than
    written down, so the listing cannot drift out of step with the bytes.
    """
    def setup(src, dst):
        return bytes([
            0xA9, src & 0xFF,  0x85, ZP_SRC,        # LDA #<src : STA $FB
            0xA9, src >> 8,    0x85, ZP_SRC + 1,    # LDA #>src : STA $FC
            0xA9, dst & 0xFF,  0x85, ZP_DST,        # LDA #<dst : STA $FD
            0xA9, dst >> 8,    0x85, ZP_DST + 1,    # LDA #>dst : STA $FE
        ])

    # SEI, two setup-and-call pairs, then the jump: a fixed 42 bytes, so the
    # copy routine's address is known before either JSR is emitted and neither
    # needs patching afterwards.
    lead_len = 1 + (16 + 3) * 2 + 3
    copy_addr = ML_BASE + lead_len
    jsr = bytes([0x20, copy_addr & 0xFF, copy_addr >> 8])

    lead = (bytes([0x78])                           # SEI
            + setup(pay3, 0x6000) + jsr
            + setup(pay5, 0xA000) + jsr
            + bytes([0x4C, entry & 0xFF, entry >> 8]))   # JMP cold start
    assert len(lead) == lead_len, len(lead)

    # The copy routine. Both branches go backwards to a label inside this
    # block, so the offsets are worked out from the block's own layout: a
    # 6502 branch is relative to the byte after its operand.
    page, byte = 2, 4                               # label offsets within body
    body = bytearray([
        0xA2, BLOCK >> 8,                           # copy: LDX #32   (pages)
        0xA0, 0x00,                                 # page: LDY #0
        0xB1, ZP_SRC,                               # byte: LDA ($FB),Y
        0x91, ZP_DST,                               #       STA ($FD),Y
        0xC8,                                       #       INY
        0xD0, 0x00,                                 #       BNE byte
        0xE6, ZP_SRC + 1,                           #       INC $FC
        0xE6, ZP_DST + 1,                           #       INC $FE
        0xCA,                                       #       DEX
        0xD0, 0x00,                                 #       BNE page
        0x60,                                       #       RTS
    ])
    body[10] = (byte - (10 + 1)) & 0xFF             # -7
    body[17] = (page - (17 + 1)) & 0xFF             # -16
    return lead + bytes(body)


def build_prg(blk5_path, blk3_path, dst):
    """Write the .prg. Returns a one-line description of what it holds."""
    blk5 = open(blk5_path, "rb").read()
    blk3 = open(blk3_path, "rb").read()
    for p, d in ((blk5_path, blk5), (blk3_path, blk3)):
        if len(d) != BLOCK:
            sys.exit(f"prg: {p} is {len(d)} bytes, expected {BLOCK}")

    # The cold-start vector, read out of the ROM rather than written down here.
    # A cartridge's first two bytes ARE its entry point, and the whole file is
    # worthless if this number is wrong, so it comes from the one place that
    # cannot disagree with the shipped cartridge.
    entry = struct.unpack("<H", blk5[:2])[0]
    if blk5[4:9] != b"\x41\x30\xc3\xc2\xcd":        # 'A0' + CBM, high bits set
        sys.exit(f"prg: {blk5_path} has no A0CBM signature at $A004 — "
                 f"this is not an autostart VIC-20 cartridge")

    pay3 = PAY_BASE
    pay5 = PAY_BASE + BLOCK
    image = (basic_stub(ML_BASE, ML_BASE)
             + copier(pay3, pay5, entry).ljust(PAY_BASE - ML_BASE, b"\x00")
             + blk3 + blk5)

    top = BASIC_START + len(image) - 1
    if top >= 0x6000:
        sys.exit(f"prg: the image reaches {top:#06x}, into BLK3 at $6000")

    with open(dst, "wb") as f:
        f.write(struct.pack("<H", BASIC_START))
        f.write(image)

    return (f"${BASIC_START:04X}-${top:04X}, SYS {ML_BASE}, "
            f"BLK3->$6000 BLK5->$A000, entry ${entry:04X}")


# How far the converted file's title screen may sit from the cartridge's before
# this calls it a different picture. The title animates -- the potions twinkle
# and the streaks scroll -- so two boots stopped at different cycles never match
# to the pixel even when both are right. A wrong conversion is not off by a few
# per cent: a block copied to the wrong address, or a file that never finished
# loading, leaves a BASIC screen or a field of garbage and lands above 90.
TITLE_TOLERANCE = 5.0


def shot_of(argv, shot):
    subprocess.run(["xvic", "-console", "+saveres", "-warp",
                    "-limitcycles", "60000000"] + argv +
                   ["-exitscreenshot", shot], capture_output=True)
    return os.path.exists(shot) and os.path.getsize(shot) > 0


def verify_prg(path, tmp):
    """Boot it, and require it to draw what the cartridge draws.

    package.py holds every .crt to "it still runs after 20 million cycles",
    which is the right bar for a container: the machine either finds the ROM or
    it does not. A converted file can clear that bar and still be broken --
    BASIC sits there quite happily at a READY prompt -- so this asks the harder
    question instead, the one crosscheck.py asks of the three platforms. Boot
    the cartridge, boot the conversion, and require the same title screen.

    `-memory all` is the 35K machine the file is built for; run it on less and
    there is nowhere for BLK5 to go. `-autostartprgmode 1` injects the program
    rather than emulating a serial load, which at 16 KB does not finish inside
    any cycle budget worth waiting for -- and the loading is not what is being
    tested here. What is being tested is where the bytes end up afterwards.
    """
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    prg_png = os.path.join(tmp, "verify-prg.png")
    ref_png = os.path.join(tmp, "verify-cart.png")

    if not shot_of(["-memory", "all", "-autostartprgmode", "1",
                    "-autostart", path], prg_png):
        sys.exit(f"prg: {os.path.basename(path)} did not come up in xvic — "
                 f"the conversion does not run, do not ship it")
    if not shot_of(["-cartA", os.path.join(root, "VIC20/WizardsLab-blk5.crt"),
                    "-cart6", os.path.join(root, "VIC20/WizardsLab-blk3.crt")],
                   ref_png):
        sys.exit("prg: the cartridge itself did not come up — build it first")

    from PIL import Image                            # as tools/read-screen.py
    a = Image.open(prg_png).convert("RGB")
    b = Image.open(ref_png).convert("RGB")
    if a.size != b.size:
        sys.exit(f"prg: screenshots differ in size, {a.size} vs {b.size}")
    pa, pb = a.load(), b.load()
    w, h = a.size
    diff = sum(1 for y in range(h) for x in range(w) if pa[x, y] != pb[x, y])
    pct = 100.0 * diff / (w * h)

    if pct > TITLE_TOLERANCE:
        sys.exit(f"prg: the conversion draws a different screen from the "
                 f"cartridge ({pct:.1f}% of pixels differ, tolerance "
                 f"{TITLE_TOLERANCE}%) — see {prg_png}")
    return f"booted in xvic, title matches the cartridge to {pct:.2f}%"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    blk5 = os.path.join(root, "VIC20/WizardsLab-blk5.crt")
    blk3 = os.path.join(root, "VIC20/WizardsLab-blk3.crt")
    dst = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(root, "dist", "WizardsLab-VIC20.prg")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    print(" ", os.path.basename(dst), build_prg(blk5, blk3, dst))
    print(" ", verify_prg(dst, os.path.dirname(dst)))


if __name__ == "__main__":
    main()
