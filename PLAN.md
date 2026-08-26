# Wizards Lab — Implementation Plan

[SPEC.md](SPEC.md) says what the game *is*. This document says how it gets
built, in what order, and what has to be true before each step is done.

The two are deliberately separate. SPEC.md is the authority on every rule,
table and number, and a phase below never restates one — it points at the
section that owns it. If an implementation detail contradicts SPEC.md, SPEC.md
is right and the code is wrong; if SPEC.md turns out to be wrong, change
SPEC.md first and note it here.

**This document is the source of truth across agent sessions. Update the
checkboxes and the "Current Status" section as work progresses.**

---

## Current Status

- **Phase P0 is done.** All three cartridges assemble, link, boot in an
  emulator and draw their title screen at the correct offset. The build system,
  the platform layer and the artwork pipeline are in place; every game module
  in `src/` exists with the routines SPEC.md calls for and a `TODO` where the
  body goes. Work RAM is 526 bytes on every platform, against SPEC §17.1's
  530-byte budget. ROM use is 27% / 31% / 43% of 16 KB.
- P0 settled three things worth carrying forward. **The AC6502's VDP needs
  register 1's interrupt-enable bit set** even though the game polls, because
  the vblank status flag does not raise without it (D7). **The VIC-20 must set
  its own screen-centring registers** (`$9000`/`$9001`), because an autostart
  cartridge takes over before the KERNAL sets them (D8). And the headless
  AC6502 emulator fits **no video card at all** unless `--console video` is
  passed, which looks exactly like a hung cartridge (§3).
- Next: **P1 — the render path.**

---

## 1. Goal

A finished, playable 16 KB cartridge on three machines, from one shared source
tree, matching SPEC.md.

Secondary, and load-bearing: the shared code must stay genuinely shared. Every
phase below adds to `src/`, and the moment a phase needs an `.if` on the
platform inside `src/`, that is a signal the HAL contract is wrong rather than
a licence to branch.

---

## 2. What is already true

P0 built the parts that are not the game:

- **Three linker configs and three cartridge headers**, each verified by
  hexdump and by booting. `AC6502-16K.cfg`, `VIC20-16K.cfg`, `C64-16K.cfg`.
- **One shared translation unit.** The modules in `src/` are `.include`d by
  each platform's `WizardsLab.asm` rather than assembled separately — one
  `cl65` call, no import/export bookkeeping, which is the right trade at 16 KB.
- **The HAL contract** in [`src/hal.inc`](src/hal.inc): four constants
  (`PANEL_X`, `PANEL_Y`, `SCR_COLS`/`SCR_ROWS`, `HAS_COLOR_RAM`) and seven
  routines (`HalInitVideo`, `HalWaitFrame`, `HalPlotCell`, `HalBlitScreen`,
  `HalReadInput`, `HalDetectRegion`, `HalSfx`).
- **The artwork pipeline.** `.bin` files are editor exports pulled in with
  `.incbin`; `.inc` files are hand-authored from SPEC.md. Editor projects live
  in `artwork/`, pre-seeded with the placeholder tileset and the panel at each
  machine's offset.
- **`make smoke`**, which boots all three headless and fails if a cartridge
  hangs instead of reaching its main loop.
- **`rng.asm`**, the one game module with a real body — a 16-bit Galois LFSR,
  verified to have the full 65535-state period.

---

## 3. Ground rules

Things a session working in this repository needs to know and cannot infer.

- **`make smoke` after any change to a platform file.** It has already caught
  two boot failures that assembled perfectly. The AC6502 emulator exits 2 on
  timeout and VICE exits non-zero on cycle limit; both are the *success* case
  for a game that loops forever, and the Makefiles already account for it.
- **The headless AC6502 emulator needs `--console video`.** Its default serial
  console fits no video card, `HalWaitFrame` then never returns, and the
  symptom is indistinguishable from a hang in the game.
- **Nothing in `src/` touches hardware.** If a module needs a hardware address,
  the HAL is missing a routine. Add it to `hal.inc`, implement it three times,
  and say in `hal.inc` what it promises.
- **The board byte is the tile index.** No translation table between board and
  screen. A cell is `$00` empty, `$40`–`$77` occupied, `$FF` wall.
- **The board has an 8-byte stride and permanent sentinels**, which is what
  lets scans run without bounds checks. Do not "fix" the two wasted bytes per
  row (SPEC §3.2).
- **BSD `sed` has no `\b`.** Use Python for word-boundary rewrites in this repo.
- **`vic20.inc` already defines `SCREEN_COLS` and `SCREEN_ROWS`.** The game's
  own screen constants are `SCR_COLS` / `SCR_ROWS` to avoid the collision.
- **Verify against the reference builds.** The sibling repositories have
  working carts (`../VIC-20/TileDemo`, `../6502-ASM/HelloWorldCart`) — when a
  platform behaves oddly, screenshot one of those under the same emulator
  invocation before assuming the game is at fault. That is how P0 confirmed the
  VIC-20 centring fix.

---

## 4. Open questions

Things that need measuring, not deciding. Each one blocks the phase named.

### S1 — What is the real per-cell cost of a VDP write? — *blocks P1*

SPEC §12.6 caps the dirty-cell flush at 48 cells a frame on the theory that a
real TMS9918A needs roughly 29 cycles between VRAM writes at 1 MHz. Measure
what the emulator and, if possible, real hardware actually tolerate, and set
`DIRTY_FLUSH_MAX` from the measurement rather than the estimate. Getting this
wrong is invisible in an emulator and shows up as corruption on hardware.

### S2 — Does the piece feel right at the SPEC timings? — *blocks P2*

Lock delay 16 frames, DAS 12/4, soft drop 3 frames a row (SPEC §5.6, §11.3).
These are the numbers the game lives or dies on and they were chosen on paper.
P2 exists partly to play with them. Whatever comes out, update SPEC §11.3 and
§14 to match — the tables are the authority, not the code.

### S3 — How well do the screen images compress? — *blocks P9*

SPEC Appendix C and data/README.md both assume the margin artwork RLEs at
roughly 4:1. The C64 carries 4000 bytes of screen images today; if the ratio is
worse than about 2:1, either the title screen shares tiles with the play screen
or the C64 margins get simpler. Measure on real artwork, not placeholder.

### S4 — Can the VIC-20 scan its keyboard without disturbing the joystick? — *blocks P2*

Both live on VIA2, and reading the RIGHT switch means flipping `$9122`'s
direction register. The current `HalReadInput` does that dance once a frame and
puts the DDR back; adding a keyboard scan to the same frame may or may not
interact. Measure before designing around it.

### S5 — Does a real machine agree with the region detection? — *blocks P10*

`HalDetectRegion` samples the raster counter on both Commodores. It has only
been run against VICE, which is not evidence about a real 6560 or 6561.

---

## 5. Decisions

Numbered so phases can cite them. SPEC.md owns the *game* decisions; these are
the implementation ones that SPEC.md does not cover.

- **D1 — One translation unit.** `src/` modules are `.include`d, not linked
  separately. Revisit only if the assembler gets slow enough to matter.
- **D2 — The HAL is seven routines.** Growing it is fine; branching inside
  `src/` on the platform is not.
- **D3 — `.bin` is generated, `.inc` is written.** Editor exports are binaries
  pulled in with `.incbin`; anything derived from SPEC.md is hand-authored
  assembly. Neither kind is ever edited in the other's way.
- **D4 — Cascades run as sub-states, not a blocking loop.** `PlayState` walks
  scan → glow → shatter → gravity → repeat one frame at a time, so animation
  stays on the frame clock and the main loop never stalls (SPEC §8, §14).
- **D5 — Scoring accumulates per cascade, then banks once.** Points go into
  `Cascade*` and only reach `Score*` at settle, because the star multiplier
  applies to the whole cascade retroactively (SPEC §9.6).
- **D6 — The dirty list drops on overflow rather than growing.** A dropped cell
  is corrected by the next redraw of that cell. Silent correctness beats a
  bigger buffer on the VIC-20.
- **D7 — The AC6502 sets VDP R1 interrupt-enable, and the CPU never clears
  `I`.** The vblank status flag does not raise with IE off, so a polling
  `HalWaitFrame` needs it on; the interrupt is asserted and ignored, and
  reading the status register acknowledges it.
- **D8 — The VIC-20 sets its own `$9000`/`$9001`.** An autostart cartridge runs
  before the KERNAL centres the screen, so the game does it, per region.
- **D9 — The whole static screen comes from the editors.** Panel frame, labels
  and margin artwork are one name-table image per platform; code draws only the
  well, the digits, the preview and the message band over the top.

---

## 6. Phases

Eleven phases. Each one leaves all three cartridges building and booting — no
phase depends on a later one to make the repo work again. P1 through P5 each
add a layer of the game that can be seen running before the next begins.

A phase is done when its exit criteria are met on **all three platforms**, not
on whichever one was convenient.

---

### Phase P0 — Bootstrap

**Goal:** three cartridges that build, boot and draw, with none of the game in
them.

- [x] Linker configs, cartridge headers, CPU vectors for all three
- [x] `src/hal.inc` contract; seven routines implemented per platform
- [x] Video init: TMS9918 Graphics I, VIC-I hi-res, VIC-II standard text
- [x] Tileset copied into place (VRAM / `$1400` / `$2000`)
- [x] `HalBlitScreen` drawing a full static screen plus colour image
- [x] Joystick input folded into the abstract active-high mask
- [x] Region detection on both Commodores
- [x] Placeholder artwork generator; editor projects in `artwork/`
- [x] `make`, `make run-*`, `make smoke`, `make data`
- [x] `rng.asm` with a verified full-period LFSR

**Exit criteria: met.** All three boot headless and render the title screen
with the panel at the right offset, confirmed by screenshot. VIC-20 framing
verified against `../VIC-20/TileDemo`. Work RAM 526 bytes on each.

What P0 settled, for the phases that inherit it: D7, D8, and §3's note about
`--console video`. The VIC-20's 506-byte screen is **one page plus 250**, not
two pages plus 250 — the first attempt overran into `$2000` and past colour
RAM, and any new full-screen loop needs the same care.

---

### Phase P1 — The render path

**Goal:** the well and the panel fields draw through the dirty-cell path,
driven by data rather than by the game.

- [ ] S1 measured; `DIRTY_FLUSH_MAX` set from it
- [ ] `render.asm`: `RenderMark` appends `(screen offset, tile)` applying
      `PANEL_X`/`PANEL_Y` once, here
- [ ] `RenderFlush` pushes up to the cap per frame and resumes where it stopped
- [ ] `board.asm`: `BoardClear` and `BoardRowPtr`, sentinels laid down correctly
- [ ] `RenderBoard` queues the whole 6 × 16 well
- [ ] `text.asm`: `TextDraw`, `TextBcd`, `TextBanner`, `TextBannerClear`
- [ ] `RenderScore` / `RenderHigh` / `RenderLevel`, dirty-flagged on change only
- [ ] A temporary debug path that fills the board with a known pattern

**Exit criteria:** a hand-seeded board renders correctly in the well on all
three platforms; seven-digit and two-digit BCD numbers draw in the right panel
cells; the level draws as two stacked digits; a banner centres in the one-row
message band; the flush cap is respected and a
full-board redraw completes over several frames without tearing or dropping
cells.

---

### Phase P2 — The falling piece

**Goal:** pieces spawn, move, rotate, fall and lock. No matching — the pile
just grows. **This is where the game's feel is decided.**

- [ ] S4 measured; keyboard scanning added to `HalReadInput` on all three
- [ ] `piece.asm`: `PieceGenerateNext` per SPEC §5.2 (colours only for now)
- [ ] `PieceSpawn`, with the game-over condition detected but not yet acted on
- [ ] `PieceMoveLeft` / `PieceMoveRight` / `PieceRotate` / `PieceRotateBack`
- [ ] `PieceStep`, lock delay with `LOCK_RESET_MAX` resets, `PieceLock`
- [ ] `input.asm`: `InputShift` — DAS on left/right, **no auto-repeat on rotate**
- [ ] Soft drop, ignored when gravity is already faster
- [ ] `RenderPiece` / `RenderPieceErase` / `RenderNext`
- [ ] `main.asm`: `StatePlay` dispatching `PLAY_FALLING`, `PLAY_LOCKING`, `PLAY_ARE`
- [ ] S2: play it, tune the timings, update SPEC §11.3 and §14 to match

**Exit criteria:** pieces can be steered anywhere in the well and stack up
correctly; the preview shows the next piece; rotation cycles the three cells
and never auto-repeats; the piece cannot leave the well or overlap the pile;
timings feel right and SPEC.md records whatever they ended up being.

---

### Phase P3 — Matching and gravity

**Goal:** it becomes a game. Runs clear, tiles fall, chains count.

- [ ] `match.asm`: the four scan passes, `Marks` filled, `RunCount` set
- [ ] Wildcard handling in the scanner, ahead of the prism existing (SPEC §6.3)
- [ ] `MarksClear` / `MarkSet` / `MarkTest`
- [ ] `BoardGravity` — per-column compaction, marking moved cells dirty
- [ ] `cascade.asm`: `CascadeBegin` / `CascadeStep` / `CascadeSettle` skeleton,
      scan and removal only
- [ ] `PLAY_GRAVITY` sub-state, one row every `FALL_FRAMES`
- [ ] Chain counter advancing across cascade steps

**Exit criteria:** three or more of a colour clear in all four directions;
overlapping runs clear once and count once each; a run of four is one run, not
two threes; tiles above a clear fall and can trigger further clears; cascades
terminate; the board is never left in an impossible state. Playable, scoreless.

---

### Phase P4 — Scoring and levels

**Goal:** the full scoring loop from SPEC §9 and the speed ramp from §10.

- [ ] `score.asm`: `ScoreReset`, `CascadeAdd`, `CascadeAddTimes`, `ScoreAdd`
- [ ] Four-byte BCD accumulate, clamped at 9999999, never wrapping
- [ ] Per-run scoring: `TileValue[chain]`, `LengthBonus`, `MultiBonus`
- [ ] `ScoreLevelCheck` — 30 tiles a level, one advance per step, surplus carries
- [ ] `ScoreGravity` indexing `SpeedNTSC` / `SpeedPAL` by region
- [ ] Live high score update, and the flash when it is overtaken
- [ ] Panel fields updating on change

**Exit criteria:** the worked examples in SPEC §9.7 produce exactly the stated
totals; the score clamps rather than wraps; levels advance at the right rate
and never skip; gravity speeds match the SPEC §10.2 table on both regions.

---

### Phase P5 — Reagents

**Goal:** the five reagents and the chain reactions between them (SPEC §7).

- [ ] `PieceGenerateNext` gains the reagent roll — one per piece, `PSpecial`
      and `ReagentThresholds` by level band
- [ ] `EffectQClear` / `EffectQPush` / `EffectQPop`, drop-on-overflow per D6
- [ ] `EffectFireball` — colour-scoped, board wide, prisms immune
- [ ] `EffectBolt` — row plus column
- [ ] `EffectBomb` — 3 × 3, clipped at edges
- [ ] `EffectStar` — `StarCount`, capped at `STAR_SHIFT_CAP`
- [ ] `EffectPrism` — `BONUS_PRISM`, no removal
- [ ] Reagents removed by other reagents' effects are enqueued and fire
- [ ] `EffectValue[chain]` and the trigger bonuses
- [ ] `CascadeSettle` applies the star multiplier to the whole cascade

**Exit criteria:** every row of SPEC §7.4's interaction table behaves as
written; a fireball inside a run detonates once and prisms survive it; two
bolts in one run cut two crosses; the effect queue always drains; a cascade
containing three stars scores ×8 and not more; SPEC §9.7 example B produces
1280 and example C produces 3360.

---

### Phase P6 — Animation

**Goal:** clears read as events rather than as the score jumping.

- [ ] `PLAY_GLOW` — matched cells swap to glyph `+6` of their own colour
- [ ] `PLAY_SHATTER` — matched cells swap to the shared white shatter tile
- [ ] Fireball flash: one VDP colour-table byte on the AC6502, colour RAM on
      the Commodores — same frame count, different mechanism
- [ ] Bolt beam and bomb blast overlays
- [ ] Level-up and chain banners in the message band
- [ ] Game-over petrify: `TILE_STONE` filling the well bottom-up
- [ ] Every duration from the SPEC §14 table, per region

**Exit criteria:** a clear step takes the frames SPEC §14 says it does on both
regions; a deep chain reads as roughly half a second a link; the fireball flash
is one byte on the AC6502; nothing in the animation path blocks the main loop.

---

### Phase P7 — Screen states

**Goal:** a complete arcade loop — title, play, pause, game over, title.

- [ ] `StateTitle`: logo, blinking prompt, four auto-cycling help pages
- [ ] The reagent legend page — the only place the rules are taught
- [ ] RNG seeded from the frame counter at the fire press (SPEC §15)
- [ ] `StatePause`: well blanked so it cannot be studied, timers frozen
- [ ] `StateGameOver`: petrify, banner, high-score fanfare, 10-second timeout
- [ ] Spawn-blocked detection promoted to an actual game over

**Exit criteria:** the loop runs indefinitely without leaking state between
games; two consecutive games from a cold boot deal different pieces; pausing
hides the board; the high score survives a game and resets on power-on.

---

### Phase P8 — Audio

**Goal:** SPEC §16's twelve effects.

- [ ] SID driver shared by the AC6502 (`$9800`) and the C64 (`$D400`)
- [ ] VIC-I driver against `$900A`-`$900E`
- [ ] `AudioTick` consuming `SfxRequest`; `HalSfx` implemented three times
- [ ] Match chime pitch rising with `chain`
- [ ] All twelve effects wired to their events

**Exit criteria:** every effect in SPEC §16 fires from its event on all three
machines; audio never delays a frame; a machine with no sound card still runs.

---

### Phase P9 — Artwork

**Goal:** real tiles, real margins, real logo. The last phase that can be cut
down if ROM runs short.

- [ ] S3 measured on real artwork
- [ ] Tileset drawn in TMS9918-EDITOR Graphics I per SPEC Appendix A.2
- [ ] The four reagents distinguishable by silhouette in peripheral vision
- [ ] Margin artwork: 272 cells on the AC6502, 530 on the C64
- [ ] Title logo
- [ ] C64 screen project laid out (panel at column 9, row 1)
- [ ] RLE the screen images if S3 says it is needed
- [ ] Screenshot into the README

**Exit criteria:** no hatched tile (128–255) remains unreplaced; every screen
image is an editor export; all three cartridges still fit 16 KB with headroom.

---

### Phase P10 — Hardware and release

**Goal:** it runs on the real machines.

- [ ] S5 measured on a real 6560 and 6561
- [ ] AC6502 on real hardware: TMS9918 write spacing, joystick, keyboard
- [ ] VIC-20 on real hardware, NTSC and PAL
- [ ] C64 on real hardware, NTSC and PAL
- [ ] Burn instructions in the README confirmed against an actual programmer
- [ ] SPEC.md reconciled with whatever the hardware changed

**Exit criteria:** a full game played to game over on each real machine, on
both regions where the machine has both.

---

## 7. Risks

- **Timing tuned only in emulators.** P2 sets the feel of the game against
  VICE and the AC6502 emulator. Real hardware is the only authority, and P10 is
  late for finding out. Mitigate by getting one real machine running as early
  as P2 if hardware is to hand.
- **The C64's ROM budget.** It carries 4000 bytes of screen images against the
  VIC-20's 2024, because its screen is bigger. At 43% used with placeholder
  art, real margins could be tight. S3 is the measurement; simplifying the C64
  margins is the fallback, and it costs nothing mechanically.
- **The effect queue on a pathological board.** Termination is proven — effects
  only remove tiles and each cell marks once — but the *frame cost* of a
  96-cell cascade is not measured. If it stalls, the queue drains across frames
  the way the dirty list does.
- **Reagent probability is guesswork.** SPEC §5.3's tables were chosen on
  paper. They are the most likely thing to need rebalancing after P5, and they
  are also the easiest — five rows of a table.
- **One translation unit could get slow.** Unlikely at this size, but if
  assembly time becomes annoying, D1 is the decision to revisit.

---

## 8. Deferred

Out of scope for the first release, recorded so they are not rediscovered.

- **Two more reagents.** Slots `+5` and `+7` are free in every colour group, so
  an hourglass and a skull need no tileset reflow (SPEC Appendix E).
- **Two-piece preview.** The panel has room only if the vignette goes.
- **Difficulty select** on the title screen — start at level 1, 5 or 10.
- **Persisted high score.** Possible on the AC6502 alone via the DS1511Y NVRAM,
  which argues for leaving it out everywhere for parity.
- **A fourth platform.** The HAL is seven routines; the tile format is shared
  by anything with 8 × 8 1bpp characters. The work would be a linker config, a
  cartridge header, and one new `WizardsLab.asm`.
