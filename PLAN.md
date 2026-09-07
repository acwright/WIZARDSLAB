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
  body goes.
- **Phase P1 is done.** The dirty-cell ring, the board, and the text and
  number routines are real, and a `make DEBUG=1` build draws a known board,
  both BCD fields, the stacked level and a centred banner identically on all
  three machines — verified cell by cell, not by eye (see §3). S1 is measured
  and settled; `DIRTY_FLUSH_MAX` is **24**, down from the estimated 48, and
  the reason turned out not to be the one the estimate assumed. Work RAM is
  557 bytes on every platform against SPEC §17.1's ~560; ROM use is 30% / 33% /
  45% of 16 KB.
- **Phase P9 is done, out of sequence.** All 256 tiles and both screens are
  drawn in `artwork/WizardsLab.tms9918`; `make artwork` imports them into
  `data/` and into the VIC-EDITOR project. SPEC Appendix A describes what is
  there and is the authority on it. Drawing the art settled several things the
  spec had left open, and the ones that reach code are listed under P9 below —
  **read that table before starting P5, P6 or P7.** The only work left in P9 is
  compression (S3), which nothing is blocked on.
- P0 settled three things worth carrying forward. **The AC6502's VDP needs
  register 1's interrupt-enable bit set** even though the game polls, because
  the vblank status flag does not raise without it (D7). **The VIC-20 must set
  its own screen-centring registers** (`$9000`/`$9001`), because an autostart
  cartridge takes over before the KERNAL sets them (D8). And the headless
  AC6502 emulator fits **no video card at all** unless `--console video` is
  passed, which looks exactly like a hung cartridge (§3).
- P1 settled how the dirty list is shaped (D11), that a bulk redraw is a
  resumable cursor rather than a bulk enqueue (D12), and that `RenderMark`
  preserves Y and zero page so text can loop across it (D13).
- Next: **P2 — the falling piece.**

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
- **The artwork pipeline.** `.bin` files are imported from the editor project
  and pulled in with `.incbin`; `.inc` files are hand-authored from SPEC.md.
  `artwork/WizardsLab.tms9918` is the master, and `make artwork`
  (`tools/import-artwork.py`) is the one path from it to `data/` — it also
  rewrites `artwork/WizardsLab.vic20` so the two projects cannot drift.
  `make artwork-check` fails if `data/` is behind.
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
- **Screens can be read back, so read them.** `tools/read-screen.py` recovers
  the name table from a `make smoke` screenshot by matching each cell against
  `data/tileset.bin`, using the cell's colour to tell the potion groups apart.
  On the AC6502 there is no screenshot but something better: the emulator's
  debug protocol (`6502 run --debug --debug-port N --debug-token T`, then
  JSON-RPC `POST /rpc`) serves `mem.read` with `space: "vram"`, plus `bp.set` /
  `exec.run` / `exec.step` for stepping a frame at a time. `cl65 -g -Wl
  --dbgfile,X.dbg` gives it the symbol addresses. That combination is how P1's
  exit criteria were checked and how the flush cap was confirmed against a
  running machine; do not go back to squinting at PNGs.
- **`make DEBUG=1`** builds with `-DWL_DEBUG`: the title screen is skipped and
  the well is filled with a known asymmetric pattern. It is the only way to see
  the render path on a headless machine with no input attached, and it is
  temporary — it goes when P2 can put a real piece on the board.
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

### S1 — What is the real per-cell cost of a VDP write? — **settled**

**The question was wrong, and the answer is 24.**

Measured, with the real `RenderFlush` and the real AC6502 `HalPlotCell` in a
cycle harness against the emulator's cycle counter: **165 cycles a cell**, so
a 24-cell flush is 3,965 cycles. The Commodores' path hand-counts to about 132
a cell. Confirmed against a running machine by breaking on `RenderFlush` and
diffing the name table frame to frame: 24 cells is the most that ever reaches
the screen in one frame, and a 146-cell state entry settles in 8.

The premise — that write spacing is what limits the cap — does not survive
contact with the numbers:

- A real TMS9918A wants **8 µs** between VRAM data accesses during active
  display and **2 µs** between any two port accesses. At 165 cycles a cell,
  two VRAM writes are **165 µs** apart at 1 MHz, and the closest two port
  accesses (the two halves of `VdpSetWrite`) are 8 cycles — 8 µs — apart. Both
  clear with two orders of magnitude to spare, and still clear at 2 MHz, which
  is the AC6502's other speed. **A 6502 at this clock cannot write a TMS9918
  too fast**, whatever it does.
- The AC6502 does not have a TMS9918A anyway; it has a **pico9918**. Reading
  its firmware settles it: `src/tms9918.pio` latches each bus write off the
  CSW edge into a PIO FIFO and `tmsWriteIrqHandler` in `src/main.c` drains it
  from RAM-resident code on an RP2040 clocked at 252–352 MHz, into VRAM that is
  ordinary processor memory. There is no display contention to have a window
  about, so its tolerance is strictly looser than the part it replaces. Its
  documentation says nothing about write timing because there is nothing to
  say.

So the cap is a **time budget**, not a hardware limit, and the right thing to
budget against is vertical blank: 24 cells fits inside it on all three, and is
tightest on the AC6502, whose 70 blank lines are about 4,450 cycles at 1 MHz.
24 is also a quarter of the 96-cell well, so a full redraw is four frames.

Overrunning that budget would not corrupt anything on any of the three — at
worst a cell lands a frame late — so the number is a comfort setting rather
than a fragile one. **Nothing here needs real hardware to confirm**, which is
just as well: SPEC §12.6 and `constants.inc` now carry the reasoning, and P10
inherits no open question from this.

### S2 — Does the piece feel right at the SPEC timings? — *blocks P2*

Lock delay 16 frames, DAS 12/4, soft drop 3 frames a row (SPEC §5.6, §11.3).
These are the numbers the game lives or dies on and they were chosen on paper.
P2 exists partly to play with them. Whatever comes out, update SPEC §11.3 and
§14 to match — the tables are the authority, not the code.

### S3 — How well do the screen images compress? — *blocks nothing yet*

SPEC §17.2 budgets 800 bytes for the six screen images RLE'd. The margin is two
tiles (SPEC §12.5), so the images are almost entirely long runs and should beat
that comfortably — the C64's 1000-cell images look like they should come in
under 200 bytes each. Nobody has measured it, and nothing is waiting on it: at
43% of 16 KB the C64 carries them raw. Take the measurement when ROM gets
tight.

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
- **D11 — The dirty list is a ring of `(screen column, screen row, tile)`.**
  Not a 16-bit offset, which SPEC §17.1 originally said: `HalPlotCell` takes a
  column and a row, and every platform reaches a cell through a row-pointer
  table (SPEC §12.3), so an offset would only be taken apart again at the far
  end. Three bytes an entry either way. A ring rather than a list with a resume
  index, because a frame that flushes its cap leaves a remainder and the next
  frame's marks still have to go somewhere; the alternative is compacting 48
  bytes down every frame that overflows.
- **D12 — A bulk redraw is a cursor, not a bulk enqueue.** The well is 96 cells
  and the ring holds 64, so `RenderBoard` cannot queue one. It sets a cursor;
  `RenderFlush` calls `RenderBoardStep` first thing every frame, which fills
  whatever the ring has room for. The redraw then paces itself to the flush and
  never overflows — which is the only reason D6's drop-on-overflow is
  survivable, because a dropped cell in a *redraw* would never be corrected.
- **D13 — `RenderMark` preserves Y and the whole of zero page.** It clobbers A,
  X and the stack, and nothing else. That is what lets `text.asm` hold a string
  cursor across it. The cursor bytes live in their own zero-page block rather
  than `Tmp0`-`Tmp3`, whose contract is the opposite one, and the block's
  comment says why. Anything else called from a marking loop breaks this.
- **D9 — The whole static screen comes from the editors.** Panel frame, labels
  and margin are one name-table image per platform; code draws only the well,
  the digits, the preview and the message band over the top.
- **D10 — The TMS9918 project is the only place art is drawn.** Everything
  else is derived by `tools/import-artwork.py`: the tileset verbatim, the
  AC6502 screens verbatim, the VIC-20's as the panel with row 23 clipped, and
  the C64's as the master's 32 columns centred on 40 with its own edge column
  carried out to the sides. Nothing in that script names a tile, so the margin
  stays the artist's. Hand-editing `artwork/WizardsLab.vic20` or any `.bin` in
  `data/` is overwritten by the next `make artwork`.

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

- [x] S1 measured; `DIRTY_FLUSH_MAX` set from it — **24**, and for a different
      reason than the question assumed
- [x] `render.asm`: `RenderMark` appends `(screen column, screen row, tile)`
      applying `PANEL_X`/`PANEL_Y` once, here (D11)
- [x] `RenderFlush` pushes up to the cap per frame and resumes where it stopped
- [x] `board.asm`: `BoardClear` and `BoardRowPtr`, sentinels laid down correctly
- [x] `RenderBoard` queues the whole 6 × 16 well — as a cursor, across frames
      (D12)
- [x] `text.asm`: `TextDraw`, `TextBcd`, `TextBanner`, `TextBannerClear`,
      `TextLevel`
- [x] `RenderScore` / `RenderHigh` / `RenderLevel`, dirty-flagged on change only
- [x] A temporary debug path that fills the board with a known pattern —
      `make DEBUG=1`, `BoardDebugFill`

**Exit criteria: met**, and checked cell by cell rather than by eye. The
panel's 22 × 23 is **byte-identical on all three machines**; the well matches a
Python model of `BoardDebugFill` in all 96 cells; SCORE reads `0000000` and
HIGH `0010000` with `01` under it; LEVEL draws `0` over `1` in one column;
`~~ LEVEL UP ~~` centres at panel column 4 in the one-row band with the rest of
it cleared. Breaking on `RenderFlush` and diffing the AC6502's name table frame
to frame shows **at most 24 cells reaching the screen in any frame** and a
146-cell state entry settling in 8, with every cell correct — nothing dropped.
Not torn, either: 24 cells is 3,965 cycles and fits inside vertical blank on
all three (S1).

**What P1 settled, for the phases that inherit it:** D11, D12, D13, and three
things worth knowing before P2:

| Found | Consequence |
|---|---|
| The play screen image ships with `~~ PAUSED ~~` already in the message band, and a preview piece already in the NEXT box — the artist drew a populated panel | Entering play must **clear** the band (`TextBannerClear`); `RenderNext` must overwrite the box rather than assume it is empty |
| `RenderBoard` falling through into `RenderBoardStep` filled the ring on the spot and silently dropped whatever the caller marked next | D12. A routine that says it only sets a cursor must only set a cursor |
| `ScoreReset` seeding the high score from "is it zero?" assumes BSS is cleared, which is not true on all three | Split into `ScoreHighInit` (once, from `GameInit`) and `ScoreReset` (per game). Strictly P4's module; done here because P1 cannot render an undefined field |

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

- [ ] `PLAY_GLOW` — matched cells swap to glyph `+6` of their own colour.
      **Marked prisms are skipped** — group 14 has no `+6`
- [ ] `PLAY_SHATTER` — the removal ring, `VFX_REMOVE1..3`, two frames each.
      One animation for the match, the bomb and the star
- [ ] Marked prisms run `PRISM_BLIP` instead: the same ring closing inward
- [ ] Prism idle rotation, `PRISM_SPIN + 0..3`, one frame every 8
- [ ] Fireball flash: one VDP colour-table byte on the AC6502, colour RAM on
      the Commodores — same frame count, different mechanism
- [ ] Bolt beam overlay (the bomb has no overlay of its own now)
- [ ] Level-up and chain banners in the message band
- [ ] Game-over petrify: `PETRIFY_BASE + (tile & GLYPH_MASK)`, bottom-up, so
      each cell sets as its own shape
- [ ] Every duration from the SPEC §14 table, per region

**Exit criteria:** a clear step takes the frames SPEC §14 says it does on both
regions; a deep chain reads as roughly half a second a link; the fireball flash
is one byte on the AC6502; nothing in the animation path blocks the main loop.

---

### Phase P7 — Screen states

**Goal:** a complete arcade loop — title, play, pause, game over, title.

- [ ] `StateTitle`: blinking prompt over the drawn screen. **No help pages** —
      the controls are on the page and the rest was cut (SPEC §13.1)
- [ ] The magic field: a random tile from `ART_BASE`..`ART_BASE + 127` into a
      random one of the block's 28 cells, every frame
- [ ] RNG seeded from the frame counter at the fire press (SPEC §15)
- [ ] `StatePause`: well washed with `TILE_WASH` so it cannot be studied,
      timers frozen
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

### Phase P9 — Artwork — **done**

**Goal:** real tiles, real screens. Complete out of sequence, which is why the
phases numbered below it are still open.

- [x] Tileset drawn in TMS9918-EDITOR Graphics I per SPEC Appendix A
- [x] The four reagents distinguishable by silhouette in peripheral vision
- [x] Both screens laid out on the 32 × 24 master
- [x] The margin — two tiles, brick and shelf, the same on all three machines
- [x] `tools/import-artwork.py` and `make artwork`: master → `data/` and →
      the VIC-EDITOR project (D10)
- [x] SPEC.md carrying the drawn tile map (§12.5, §13.1, §13.3, §13.4, §14,
      Appendix A)
- [ ] Screenshot into the README — `make smoke` writes one beside each
      Commodore cartridge, but `*-screenshot.png` is gitignored, so a committed
      one needs a different name
- [ ] RLE the screen images — deferred to P10 with S3; nothing needs it yet

**Exit criteria met:** every `.bin` in `data/` comes from the master,
`make artwork-check` is clean, and all three cartridges build and boot. The two
open boxes above are follow-on work, not part of getting the art in.

**What the tile map requires of code.** The constants are in
[`src/constants.inc`](src/constants.inc); the behaviour belongs to the phases
that own it, and each is easy to get wrong by assuming the obvious:

| Requirement | Lands in |
|---|---|
| One removal ring (56–58) serves match, bomb and star. There is no separate blast or sparkle tile | P3, P5, P6 |
| **`WILD_BASE + GLYPH_GLOW` is an arrow, not a glow.** A matched prism sits out the glow phase | P5, P6 |
| A matched prism blips out — 116, 117, 57, 56, 52 — rather than shattering | P6 |
| A prism at rest rotates through 112–115, one frame every 8 | P6 |
| PAUSE washes the well with tile 7; it does not blank it | P7 |
| Game over petrifies each cell into its own shape, `120 + (tile & 7)` | P7 |
| The title screen's magic field: random tiles from 128–255 into a 14 × 2 block, one cell a frame | P7 |
| The title screen has no help pages. The controls are part of the image | P7 |

---

### Phase P10 — Hardware and release

**Goal:** it runs on the real machines.

- [ ] S5 measured on a real 6560 and 6561
- [ ] AC6502 on real hardware: joystick and keyboard. **Not write spacing** —
      S1 settled that, and the margin is two orders of magnitude
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
  as P2 if hardware is to hand. This is about *feel* — lock delay, DAS, drop
  rate — not about whether the machine can keep up; S1 answered that from the
  cycle counts, which emulators reproduce exactly.
- **The C64's ROM budget.** It carries 4000 bytes of screen images against the
  VIC-20's 2024, because its screen is bigger. This has got better rather than
  worse: the margin is two tiles now, so the images are long runs and should
  RLE well past the 4:1 the budget assumed (S3). Nothing is tight at 43%.
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

- **Two more reagents.** Slots `+5` and `+7` are free in all six potion
  groups, and tile 125 is held for the `+5` petrified frame, so an hourglass
  needs no tileset reflow. A `+7` would, because group 15 has no room for its
  stone twin (SPEC Appendix A.3, Appendix E).
- **Two-piece preview.** The panel has room only if the vignette goes.
- **Difficulty select** on the title screen — start at level 1, 5 or 10.
- **Persisted high score.** Possible on the AC6502 alone via the DS1511Y NVRAM,
  which argues for leaving it out everywhere for parity.
- **A fourth platform.** The HAL is seven routines; the tile format is shared
  by anything with 8 × 8 1bpp characters. The work would be a linker config, a
  cartridge header, and one new `WizardsLab.asm`.
