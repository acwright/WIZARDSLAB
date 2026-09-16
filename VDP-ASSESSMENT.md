# VDP assessment: WIZARDSLAB

> An outline, not a plan. The detailed plan for this repository goes in `VDP-PLAN.md`,
> written in a session of its own. Surveyed 2026-09-16 across the whole workspace.

## The change

The ACE moves from a Pico9918 running stock TMS9918A firmware to the **6502-PICOVDP**
(`6502-PICOVDP/SPEC.md`) on PICO9918 PRO v2.0 hardware, running **BIOS 2.x**. Everything
else stays where it is: COB, DEV, KIM, VCS, PicoCalc, and any ACE whose card cannot be
reflashed (RP2040 pico9918 v1.0–1.3). Those keep the stock firmware and **BIOS 1.x (1.5)**.

- **Legacy** in these documents means TMS9918A + BIOS 1.x. **VDP** means PICOVDP + BIOS 2.x.
- **Compatibility runs one way.** The PICOVDP's legacy submode runs Text and Graphics I
  programs unchanged, so BIOS 1.5 and existing cartridges run on it. Graphics II and
  Multicolor fall back to Graphics I and draw garbage. Register writes above 7 no longer
  alias, so F18A tricks break. Sprites per line are 16 by default, not 4. Nothing written
  for the VDP runs on a TMS9918A.
- **BIOS 2.0 is assumed to be:** BIOS 1.5, plus the NVRAM save slots in
  `6502-BIOS/PLAN.md`, plus the VDP work in `6502-EMULATOR`'s
  `docs/handoff/6502-BIOS.md` (branch `v3-vdp`). Existing jump-table addresses stay put.
  A later BIOS redesign may revise this.

## Decisions already made

- No new repositories.
- **6502-EMULATOR** makes the video card an option (TMS9918A or PICOVDP): one app, one
  site. It also publishes a frozen 2.6.9 web build at a versioned path for the legacy docs.
- **6502-DOCS** is versioned: legacy docs are frozen at `/6502-DOCS/v1/`, and the main
  site is rewritten for the VDP.
- **6502-BIOS** gets a `v1.x` maintenance branch; `main` becomes 2.x.
- **Assembly and C projects** get a VDP include chosen by a build option, not branches.
- **EhBASIC and vc83basic** stay 1.x. **PicoCalc** stays legacy. **The YouTube series**
  teaches the legacy VDP and mentions the new features.

## Order across the workspace

1. **6502-PICOVDP:** firmware proven on the PRO (its Phases 9–11). This gates the
   hardware switch, not the software work.
2. **6502-EMULATOR:** frozen 2.6.9 web build at `/6502-EMULATOR/v2/`.
3. **6502-DOCS:** `v1` branch published at `/6502-DOCS/v1/`, embeds pinned to step 2.
4. **6502-EMULATOR:** `v3-vdp` merged, with the card as an option; tagged 3.x.
5. **6502-BIOS:** `v1.x` cut; 2.0 built on `main`. This can start any time, because the
   `v3-vdp` emulator already runs the PICOVDP.
6. **6502-ASM** sets the VDP include convention. 6502-CRT, 6502-PRG, 6502-BIN and 6502-C
   follow it.
7. The emulator bundles BIOS 2.0. 6502-DOCS `main` is rewritten. 6502-ACE, bastok,
   WIZARDSLAB, 6502-EHBASIC, vc83basic and 6502-ASSEMBLY follow.

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
  Rebuilding the cartridge with it produced an identical `.crt`.

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
5. **Optional, later, not planned:** a VDP-enhanced build (palette, hardware scroll,
   layers) using the VDP include. It would be a separate product decision.

## Linked repositories

| Repository | Path | Why |
|---|---|---|
| 6502-EMULATOR | `~/Developer/NodeJS/6502-EMULATOR` | Acceptance fixture and goldens; CLI card flag and default |
| 6502-ASM | `~/Developer/Assembly/6502-ASM` | Reconciled legacy include; VDP include if an enhanced build ever happens |
| 6502-PICOVDP | `~/Developer/C/6502-PICOVDP` | Its `wizardslab` goldens are pinned in `tests/oracle/` |
| 6502-DOCS | `~/Developer/NodeJS/6502-DOCS` | Listed on the cartridge/software pages |
