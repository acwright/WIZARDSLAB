# VDP assessment: WIZARDSLAB

> An outline, not a plan. The detailed plan for this repository goes in `VDP-PLAN.md`,
> written in a session of its own. Surveyed 2026-09-16 across the whole workspace.

## The change

The ACE moves from a Pico9918 running stock TMS9918A firmware to the **6502-PICOVDP**
(`6502-PICOVDP/SPEC.md`) on PICO9918 PRO v2.0 hardware, running **BIOS 2.x**. Everything
else stays where it is: COB, DEV, KIM, VCS, PicoCalc, and any ACE whose card cannot be
reflashed (RP2040 pico9918 v1.0–1.3). Those keep the stock firmware and **BIOS 1.x**,
whose last release is **1.6**.

- **Legacy** in these documents means TMS9918A + BIOS 1.x. **VDP** means PICOVDP + BIOS 2.x.
- **Compatibility runs one way.** The PICOVDP's legacy submode runs Text and Graphics I
  programs unchanged, so BIOS 1.x and existing cartridges run on it. Graphics II and
  Multicolor fall back to Graphics I and draw garbage. Register writes above 7 no longer
  alias, so F18A tricks break. Sprites per line are 16 by default, not 4. Nothing written
  for the VDP runs on a TMS9918A.

## Decisions already made

- **No new repositories.**
- **BIOS 1.6 is the last 1.x release.** It is 1.5 plus the NVRAM save slots in
  `6502-BIOS/PLAN.md`, and nothing else. It ships in emulator **2.7.0**, and the frozen
  legacy docs document it.
- **BIOS 2.0 is 1.6 plus:**
  - The PICOVDP work in `6502-EMULATOR`'s `docs/handoff/6502-BIOS.md` (branch `v3-vdp`):
    card detection, hardware scroll, port B for interrupt handlers, `WaitVBlank`.
  - A console in the PICOVDP's **Text mode** (`VMODE $1`, 40×24, 6×8 cells) with a
    **per-cell colour table**. It keeps the same font and every screen layout.
  - **No Monitor.** The machine **boots straight to BASIC**, with a new header and a colour
    logo drawn from the font's CP437 block characters. Wozmon stays at `$FF00`.
  - **The font lives in the PICOVDP firmware.** The card loads it into VRAM at reset and
    on command (a new register and a capability bit, SPEC draft 0.5). ROM `$B800` holds
    no font on 2.x.
  - **ROM layout:** BASIC takes the Monitor's 4.3 KB (`$C000–$FEFF`), and the Kernal takes
    all of `$A000–$BFFF`, including the space the font used. Nothing the Kernal needs goes
    above `$C000`, because cartridges overlay `$C000–$FFFF`. The Kernal holds the
    primitives cartridges need; BASIC-only work lives in BASIC.
  - **No TMS9918A support.** BIOS 2.x runs only with a PICOVDP, with no fallback paths.
  - **New BASIC commands with matching Kernal entries.**
    - Core: `SCREEN`, `VPOKE`/`VPEEK`, `VREG`, `PALETTE`, `VSYNC`, `VLOAD`.
    - Second tier, if room is found: `SPRITE`, `SCROLL`, `LAYER`, `VSTAT`.
    - Save-slot commands, if room is found.
    - `SYS addr[,a,x,y]`, and `BLOAD`/`BSAVE` over XModem when given no filename.
    - BASIC returns to the text console when a program stops.
  - **Tokens:** every 1.x token keeps its value, and new keywords are appended after `$D4`.
    The `BRK` statement is retired and its token `$B4` goes to a new keyword.
  - **A BRK instruction** prints `BREAK $nn AT $xxxx  A= X= Y= P= S=` and warm-starts
    BASIC. `BRK_PTR` stays hookable.
  - **`COLOR fg[,bg[,border]]`** sets the pen for later output, `CLS` fills the screen with
    it, and `border` is register 7's low nibble.
  - **Existing jump-table addresses do not move.** New entries are appended.
- **6502-EMULATOR** makes the video card an option (TMS9918A or PICOVDP): one app, one
  site. It also publishes a frozen **2.7.0** web build at `/6502-EMULATOR/v2/` for the
  legacy docs.
- **6502-DOCS** is versioned: legacy docs (BIOS 1.6) are frozen at `/6502-DOCS/v1/`, and
  the main site is rewritten for the VDP and BIOS 2.x.
- **6502-BIOS** gets a `v1.x` branch cut at `v1.6`; `main` becomes 2.x.
- **Assembly and C projects** get a VDP include chosen by a build option, not branches.
  The legacy `6502.inc` gets one last update, for 1.6.
- **EhBASIC and vc83basic** stay 1.x. **PicoCalc** and **KIMULATOR** stay legacy and ship BIOS 1.6. **The YouTube series**
  teaches the legacy VDP and mentions the new features.

## Order across the workspace

**Part 1: BIOS 1.6, the last legacy release**

1. **6502-BIOS:** build 1.6 on `main`, tag `v1.6`, and cut `v1.x` from it.
2. **6502-EMULATOR `main`:** bundle 1.6, release **2.7.0**, and publish its frozen web build
   at `/6502-EMULATOR/v2/`. Then merge `main` into `v3-vdp` and re-capture the goldens
   there; they exist only on that branch.
3. **6502-PICOVDP:** re-sync `tests/oracle/`, whose pinned `bios` goldens moved.
4. **The legacy include** gains the NVRAM entries in every copy: 6502-ASM, 6502-CRT,
   6502-PRG, 6502-BIN, 6502-EHBASIC, 6502-C (with `6502.h`) and WIZARDSLAB.
5. **6502-DOCS `main`** documents 1.6 and pins 2.7.0. Then it cuts `v1`, published at
   `/6502-DOCS/v1/`, against the emulator's frozen 2.7.0 build at `/6502-EMULATOR/v2/`.

Alongside steps 2–5, once step 1 is tagged: **6502-PICOCALC** embeds the `v1.6` ROM and
releases a new UF2, and **6502-KIMULATOR** bundles it and releases 1.0.9. DOCS waits for both
releases before cutting `v1`.

**Part 2: the VDP**

6. **6502-PICOVDP:**
   - SPEC draft 0.5 adds the built-in font and its load command. The emulator's PICOVDP
     card implements it first, then the firmware.
   - Firmware proven on the PRO (its Phases 9–11) gates the hardware switch, not the
     software work.
7. **6502-EMULATOR:** `v3-vdp` merged, with the card as an option; tagged 3.x.
8. **6502-BIOS:** 2.0 on `main`. This can start once step 1 is done, because the `v3-vdp`
   emulator already runs the PICOVDP. Its console work needs the built-in font in the
   emulator (step 6).
9. **6502-ASM** sets the VDP include convention. 6502-CRT, 6502-PRG, 6502-BIN and 6502-C
   follow it.
10. **Everything else follows BIOS 2.0:**
    - The emulator bundles BIOS 2.0.
    - 6502-DOCS `main` is rewritten.
    - bastok gains the 2.x token table.
    - 6502-ACE, WIZARDSLAB, 6502-EHBASIC, vc83basic, cffs and 6502-ASSEMBLY follow.

---

## This repository's role

A released game (v1.0.0, itch.io) for the AC6502, VIC-20 and C64. The AC6502 build drives
the VDP directly in Graphics Mode I (`src/render.asm`, `src/hal.inc`,
`include/ac6502.inc`, `data/tilecolor-tms9918.inc`). **It is the emulator's second
acceptance test:** its debug cartridge is committed in 6502-EMULATOR as a fixture, and its
goldens hold the PICOVDP to the frames it drew on the TMS9918A.

## Impact: light

- **It runs unchanged on both cards.** Graphics I is in the legacy submode, and it uses no
  sprites, so the 4-versus-16 per-line difference cannot show.
- **Colours shift slightly** on the PICOVDP: its palette is 12-bit, and the game's eight
  colours move by up to 8 per channel. Nothing to fix; screenshots differ by that much.
- `include/ac6502.inc` is the settled legacy `6502.inc`, byte-identical across the
  workspace and checked against the BIOS v1.5 build (see 6502-ASM's assessment).
  Rebuilding the cartridge with it produced an identical `.crt`. It takes BIOS 1.6's
  NVRAM entries when 6502-ASM updates the copies (a copy, then a rebuild to confirm).

## Work outline

1. **Keep the AC6502 build legacy.** One cartridge for every AC6502 is the right product,
   and its include is already settled.
2. **README and itch page.**
   - State that it runs on every AC6502, old card or new.
   - `README.md` says "no AC6502 shots because its emulator writes no PNG". Emulator 3.x
     has `run --headless --console video --screenshot`, so shots are now possible.
3. **Tooling.** `make run-AC6502`, `smoke-AC6502` and `playtest` drive `6502 run`.
   - Pin them to the TMS9918A card explicitly, or test both.
   - The default card is set by 6502-EMULATOR and will flip at the switchover.
4. **Fixture coordination.** Any change to the AC6502 cartridge does not touch the
   emulator's committed fixture. If the fixture is ever refreshed, the goldens are
   re-captured in 6502-EMULATOR in a commit of their own.
5. **Optional, a product idea:** BIOS 1.6's NVRAM save slots could hold high scores on
   every AC6502 with an RTC card.
6. **Optional, later, not planned:** a VDP-enhanced build (palette, hardware scroll,
   layers) using the VDP include. It would be a separate product decision.

## Linked repositories

| Repository | Path | Why |
|---|---|---|
| 6502-EMULATOR | `~/Developer/NodeJS/6502-EMULATOR` | Acceptance fixture and goldens; CLI card flag and default |
| 6502-ASM | `~/Developer/Assembly/6502-ASM` | Reconciled legacy include; VDP include if an enhanced build ever happens |
| 6502-PICOVDP | `~/Developer/C/6502-PICOVDP` | Its `wizardslab` goldens are pinned in `tests/oracle/` |
| 6502-DOCS | `~/Developer/NodeJS/6502-DOCS` | Listed on the cartridge/software pages |
