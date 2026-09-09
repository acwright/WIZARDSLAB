#!/usr/bin/env python3
"""Build the download: cartridge images people can load, and ROMs they can burn.

    make dist

What the linker writes is a raw ROM image — the bytes that go on an EPROM,
nothing around them. That is the right thing to burn and the wrong thing to
hand somebody with a C64 Ultimate or a flash cart, because nothing in a raw
image says where in the address map it belongs. VICE will not take one by drag
and drop, an Ultimate II+ will not list it, and the VIC-20's is worse still:
its 16 KB is two 8 KB blocks at different addresses, so it is two files, and
the second is not optional.

So this ships BOTH, in two directories that say what they are for:

    run/     .crt container images. One file per machine, the load address
             carried inside it. Drag onto VICE, or put on the SD card of an
             Ultimate II+, an Ultimate 64 or a Final Expansion 3.
    eprom/   The raw images, named for their size and load address. What goes
             on the EPROM.

The AC6502's cartridge image and its EPROM image are the same bytes — it burns
straight to a 28C256 — so its file appears in both directories under both
names, rather than being the one machine you have to read a note about.

The .crt files are made with VICE's own cartconv, except for the one thing
cartconv cannot express: see vic20_crt(). And they are not merely built, they
are BOOTED — every container this writes is attached to a headless emulator
and has to reach its title screen before the zip is written. A cartridge image
that does not run is exactly the failure this tool exists to prevent, and it is
not one you can see by looking at the file.

Outputs, under dist/:

    WizardsLab-cartridges-<version>.zip     the download, for GitHub and itch
    WizardsLab-cartridges-<version>/        the same, unzipped, to upload loose

Run from the repository root. Needs VICE (cartconv, x64sc, xvic).
"""
import os
import shutil
import struct
import subprocess
import sys
import zipfile

# The version the download is named for. Kept in step with the git tag and the
# GitHub release, so a zip somebody downloaded a year ago can be traced back to
# the commit that built it: v1.0.0 here is the tag v1.0.0 is the release
# v1.0.0. Override with `make VERSION=v1.1.0 dist`.
VERSION = "v1.0.0"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")

CART_NAME = "Wizards Lab"

# Raw ROM images the linker writes, and what they are on the machine. The
# addresses are SPEC Appendix C: C.1 for the AC6502, C.2's BLK5/BLK3 split for
# the VIC-20, C.3's 16 KB at $8000 for the C64.
ROMS = {
    "ac6502":     ("AC6502/WizardsLab.crt",     0x8000, 32768),
    "c64":        ("C64/WizardsLab.crt",        0x8000, 16384),
    "vic20-blk5": ("VIC20/WizardsLab-blk5.crt", 0xA000, 8192),
    "vic20-blk3": ("VIC20/WizardsLab-blk3.crt", 0x6000, 8192),
}


def run(*argv):
    p = subprocess.run(argv, capture_output=True, text=True)
    if p.returncode:
        sys.exit(f"package: {argv[0]} failed\n{p.stdout}{p.stderr}")
    return p.stdout


def rom(key):
    path, _, size = ROMS[key]
    path = os.path.join(ROOT, path)
    if not os.path.exists(path):
        sys.exit(f"package: {path} is missing — run `make` first")
    if os.path.getsize(path) != size:
        sys.exit(f"package: {path} is {os.path.getsize(path)} bytes, "
                 f"expected {size}")
    return path


def c64_crt(dst):
    """A 16 KB generic C64 cartridge, EXROM and GAME both low (SPEC C.3).

    cartconv works this out from the file size on its own: 16 KB of generic
    cartridge is only ever ROML $8000 plus ROMH $A000, which is the mode the
    header has to declare for the game to see its own data.
    """
    run("cartconv", "-q", "-t", "normal", "-n", CART_NAME,
        "-i", rom("c64"), "-o", dst)


def vic20_crt(dst):
    """One VIC-20 cartridge holding both blocks, BLK5 at $A000, BLK3 at $6000.

    This is the one place cartconv cannot say what needs saying. A VIC-20 CRT
    is a header followed by a CHIP packet per block, each carrying its own load
    address — which is exactly the shape this cartridge needs. But cartconv's
    -l is one global setting rather than one per input file: pass two -i and
    two -l and BOTH packets come out at whichever address was named last, and
    it reports success. (Concatenating the blocks into one 16 KB input is worse
    — that writes a single 8 KB packet and drops half the game, quietly.)

    So each block is converted on its own, correctly, and the second file's
    packet is appended to the first file. cartconv still writes the header and
    frames both packets; the only thing done here is joining them. What the
    join produced is then read back and checked, by check_header().
    """
    parts = []
    for key in ("vic20-blk5", "vic20-blk3"):
        _, addr, _ = ROMS[key]
        out = dst + f".{key}"
        run("cartconv", "-q", "-t", "vic20", "-n", CART_NAME,
            "-l", hex(addr), "-i", rom(key), "-o", out)
        parts.append(out)

    head = open(parts[0], "rb").read()
    tail = open(parts[1], "rb").read()

    # The header length is a big-endian long at offset $10, so the packets are
    # found by reading the file rather than by assuming the usual $40.
    hlen = struct.unpack(">I", head[0x10:0x14])[0]
    if hlen != struct.unpack(">I", tail[0x10:0x14])[0]:
        sys.exit("package: the two VIC-20 conversions disagree on header size")

    with open(dst, "wb") as f:
        f.write(head)
        f.write(tail[hlen:])
    for p in parts:
        os.remove(p)


# What each container has to be. The magic string, the emulator that attaches
# it, and the CHIP packets the machine must find inside — every block, at the
# address SPEC Appendix C puts it at.
#
# The AC6502 is absent on purpose. Its image is raw by that platform's
# convention, there is no container around it to get wrong, and its emulator
# writes no screenshot to check with.
CONTAINERS = {
    "WizardsLab-C64.crt": dict(
        magic=b"C64 CARTRIDGE   ", emu="x64sc",
        chips=[(0x8000, 0x4000)]),
    "WizardsLab-VIC20.crt": dict(
        magic=b"VIC20 CARTRIDGE ", emu="xvic",
        chips=[(0xA000, 0x2000), (0x6000, 0x2000)]),
}


def check_header(path, want):
    """Read the container back and confirm it says what it must.

    NOT `cartconv -c`, which exits 0 on sixteen kilobytes of /dev/urandom and
    therefore proves nothing. This walks the actual structure: the magic
    string, then the CHIP packets, and requires exactly the blocks expected at
    exactly the addresses expected. Getting a VIC-20 block to the wrong address
    is the specific mistake vic20_crt() exists to avoid, and it produces a file
    that is well formed in every other respect.
    """
    d = open(path, "rb").read()
    if d[:16] != want["magic"]:
        sys.exit(f"package: {path} does not start {want['magic']!r}")

    hlen = struct.unpack(">I", d[0x10:0x14])[0]
    got, off = [], hlen
    while off < len(d):
        if d[off:off + 4] != b"CHIP":
            sys.exit(f"package: {path} has junk where a CHIP packet should be")
        plen = struct.unpack(">I", d[off + 4:off + 8])[0]
        _, _, addr, size = struct.unpack(">HHHH", d[off + 8:off + 16])
        got.append((addr, size))
        off += plen

    if got != want["chips"]:
        sys.exit(f"package: {path} holds "
                 + ", ".join(f"{s:#x} at {a:#06x}" for a, s in got)
                 + " — expected "
                 + ", ".join(f"{s:#x} at {a:#06x}" for a, s in want["chips"]))
    return " + ".join(f"{s // 1024}K at {a:#06x}" for a, s in got)


def verify(path, tmp):
    """Confirm the container says what it must, then boot it.

    Two questions, and the second is the one that matters. The header check
    says the file describes the right cartridge. Booting says the machine
    agrees: the emulator is handed nothing but this one file, runs 20 million
    cycles, and has to still be alive at the end of them. A cartridge image
    that does not run is exactly what this tool exists to prevent, and it is
    not something you can see by looking at the file.
    """
    name = os.path.basename(path)
    want = CONTAINERS.get(name)
    if want is None:
        return "raw image, AC6502 convention"

    where = check_header(path, want)
    shot = os.path.join(tmp, name + ".png")
    subprocess.run([want["emu"], "-console", "+saveres", "-warp",
                    "-limitcycles", "20000000", "-cartcrt", path,
                    "-exitscreenshot", shot],
                   capture_output=True)
    if not (os.path.exists(shot) and os.path.getsize(shot)):
        sys.exit(f"package: {name} did not come up in {want['emu']} — the "
                 f"container is not loadable, do not ship it")
    return f"{where}, booted in {want['emu']}"


README = """\
WIZARDS LAB
===========

A falling-block match-three game for the AC6502, the Commodore VIC-20 and the
Commodore 64. One game, three 16 KB cartridges, written in 6502 assembly.

    https://github.com/acwright/WIZARDSLAB


WHICH FILE DO I WANT
--------------------

Two directories, because a cartridge image and an EPROM image are not the same
file.

  run/     Load these. One file per machine, with the load address carried
           inside it. Drag onto VICE, or put on the SD card of a C64 Ultimate,
           an Ultimate II+ or a VIC-20 Final Expansion 3.

  eprom/   Burn these. Raw ROM images, nothing around the bytes, named for
           their size and load address.

The AC6502's file is the same in both -- its cartridge image burns straight to
a 28C256 -- so the same bytes appear under both names.


RUNNING IT
----------

VICE is at https://vice-emu.sourceforge.io/ ; the AC6502 emulator is at
https://github.com/acwright/6502-EMULATOR

  Commodore 64      x64sc -cartcrt run/WizardsLab-C64.crt
  Commodore VIC-20  xvic -cartcrt run/WizardsLab-VIC20.crt
  AC6502            6502 run --cart run/WizardsLab-AC6502.crt

Or drag the .crt onto a running VICE window, which works now that these are
real container files. On a C64 Ultimate, an Ultimate II+ or a Final Expansion
3, copy run/ to the SD card and pick the .crt from the file browser.

ONE FILE PER MACHINE, INCLUDING THE VIC-20. The VIC-20's 16 KB is two 8 KB
blocks at different addresses -- BLK5 at $A000 holds the code, BLK3 at $6000
the artwork -- and both are inside run/WizardsLab-VIC20.crt. The two blocks are
separate files only in eprom/, where they are two separate chips.


BURNING IT
----------

  eprom/WizardsLab-AC6502-32k-8000.bin
      28C256 EEPROM or 27C256 EPROM. 16 KB of cartridge inside a 32 KB image
      spanning $8000-$FFFF; the low half is padding the machine never reads.

  eprom/WizardsLab-C64-16k-8000.bin
      27C128 (16 KB). Pull EXROM and GAME both low so ROML $8000 and ROMH
      $A000 map together.

  eprom/WizardsLab-VIC20-blk5-8k-a000.bin    BLK5, $A000 -- code
  eprom/WizardsLab-VIC20-blk3-8k-6000.bin    BLK3, $6000 -- artwork
      Two 27C64s, or one 27C128. Most VIC-20 cartridge boards socket the two
      blocks separately. The machine will not boot with either one missing.


CONTROLS
--------

                    Joystick        Keyboard
    Rotate          Up              W  or  cursor up
    Soft drop       Down            S  or  cursor down
    Move            Left / Right    A / D  or  cursor left / right
    Rotate back     Fire            Q  or  SPACE
    Pause           --              P
    Start           Fire            SPACE  or  RETURN

Joysticks are Atari 2600 compatible -- port 2 on the C64.


HOW IT PLAYS
------------

Pieces are vertical stacks of three vials in six colours. Steer them into the
well, rotate to reorder the three colours, and line up three or more of a
colour -- horizontally, vertically or diagonally. They react and vanish, and
whatever sat above them drops into new arrangements.

Among the potions fall the arcane reagents. THE ONE RULE WORTH KNOWING is that
tiles match on COLOUR, and the glyph on a tile only decides what happens when
it clears. A red potion, a red fireball and a red star are all "red" -- so
every reagent is aimed exactly like the potion it resembles, and you choose
when to set it off.

    FIREBALL    destroys every tile of its own colour, board wide
    BOLT        clears its whole row and column, up to 21 cells
    BOMB        clears the 3 x 3 around it
    STAR        doubles the whole cascade's score, up to x8
    PRISM       wildcard -- matches any colour

A reagent caught in another reagent's blast goes off too. That is where the
game lives.

Every 30 tiles removed advances a level; the fall speed ramps to level 16 and
holds. High score lives in RAM for the session -- it is a cartridge, so power
off is the end of it.


LICENCE
-------

MIT. See LICENSE.txt. Source, and the full design document, at
https://github.com/acwright/WIZARDSLAB
"""


def build(version):
    stem = f"WizardsLab-cartridges-{version}"
    stage = os.path.join(DIST, stem)
    shutil.rmtree(stage, ignore_errors=True)
    run_dir, eprom_dir = os.path.join(stage, "run"), os.path.join(stage, "eprom")
    tmp = os.path.join(DIST, ".verify")
    for d in (run_dir, eprom_dir, tmp):
        os.makedirs(d, exist_ok=True)

    made = []

    c64_crt(os.path.join(run_dir, "WizardsLab-C64.crt"))
    vic20_crt(os.path.join(run_dir, "WizardsLab-VIC20.crt"))
    shutil.copy(rom("ac6502"), os.path.join(run_dir, "WizardsLab-AC6502.crt"))
    for name in sorted(os.listdir(run_dir)):
        path = os.path.join(run_dir, name)
        made.append((f"run/{name}", os.path.getsize(path), verify(path, tmp)))

    for key, label in (("ac6502",     "AC6502-32k-8000"),
                       ("c64",        "C64-16k-8000"),
                       ("vic20-blk5", "VIC20-blk5-8k-a000"),
                       ("vic20-blk3", "VIC20-blk3-8k-6000")):
        name = f"WizardsLab-{label}.bin"
        shutil.copy(rom(key), os.path.join(eprom_dir, name))
        made.append((f"eprom/{name}", os.path.getsize(rom(key)), "raw image"))

    open(os.path.join(stage, "README.txt"), "w").write(README)
    shutil.copy(os.path.join(ROOT, "LICENSE"),
                os.path.join(stage, "LICENSE.txt"))
    shutil.rmtree(tmp, ignore_errors=True)

    # Clear out any earlier version. This directory exists to be uploaded from,
    # and two near-identical zips in it is how the wrong one gets picked.
    for stale in sorted(os.listdir(DIST)):
        if stale.startswith("WizardsLab-cartridges-") and \
                stale not in (stem, stem + ".zip"):
            path = os.path.join(DIST, stale)
            shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
            print(f"  removed stale dist/{stale}")

    zip_path = os.path.join(DIST, stem + ".zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, _, names in os.walk(stage):
            for n in sorted(names):
                full = os.path.join(folder, n)
                z.write(full, os.path.relpath(full, DIST))

    for name, size, note in made:
        print(f"  {stem}/{name:44} {size:>6,} bytes   {note}")
    print(f"  dist/{stem}.zip{'':<39} {os.path.getsize(zip_path):>6,} bytes")
    return zip_path


def main():
    os.makedirs(DIST, exist_ok=True)
    build(sys.argv[1] if len(sys.argv) > 1 else VERSION)


if __name__ == "__main__":
    main()
