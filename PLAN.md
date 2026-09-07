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
- **Phase P2 is done.** Pieces spawn, steer, rotate, fall, lock and stack, the
  preview refills, a blocked spawn ends the game, and all three machines
  produce the same pieces in the same order — checked against a Python model of
  the LFSR, cell by cell, not by eye. Both open questions closed: **S4** turned
  out to be a non-question (the VIC-20 never has to flip its DDR at all), and
  **S2 was played and the SPEC timings survived unaltered**, so §11.3 and §14
  stand as written. Keyboards are scanned on all three. Two bugs older than P2
  came out of it: `BoardClear` was writing exactly one byte of 160, and nothing
  seeded the LFSR before the first `RngNext`. Work RAM is 558 bytes against
  SPEC §17.1's ~560; ROM use is 37% / 42% / 54% of 16 KB.
- **Phase P3 is done.** Runs of three or more clear in all four directions,
  the pile falls into the holes at SPEC §14's two frames a row, and chains keep
  going until a step finds nothing — all of it verified against numbers read out
  of RAM, and one test against the VDP's own name table. The scan turned out to
  be the expensive routine of the whole game and was measured, not guessed:
  **33,336 cycles at first, 11,542 now**, against a 16,667-cycle frame. Work RAM
  is 563 bytes against SPEC §17.1's ~560; ROM use is 41% / 45% / 58% of 16 KB.
  Two things came out of it that outlive the phase: `make playtest` now steps by
  GAME frames rather than by cycles (§3), and `make crosscheck` plays the same
  game on all three machines and compares the wells.
- **Phase P4 is done.** The game scores. Every value in SPEC §9 is paid — per
  tile by chain depth, per run by length, per step by how many runs landed at
  once — the level ramps at thirty tiles with the surplus carrying, the score
  clamps at 9999999 instead of wrapping, the soft drop pays its point a row,
  and the high score is taken live and flashes when it changes hands. All of it
  is checked against SPEC arithmetic done in Python, including §9.7's worked
  example A, and the gravity table is read back off real falls at all sixteen
  levels on both regions rather than out of the table it came from. Work RAM is
  566 bytes against SPEC §17.1's ~560; ROM use is 44% / 49% / 61% of 16 KB.
  `make crosscheck` now compares the SCORE and LEVEL boxes as well as the well.
- **Phase P5 is done.** The game has reagents. A fireball wipes its colour off
  the board, a bolt cuts a row and a column, a bomb takes its 3 × 3, a star
  doubles the whole cascade and a prism pays its bonus — and anything caught by
  one of them fires in its turn, through an effect queue that always drains.
  Every one of the twenty-four cells of SPEC §7.4's interaction table is
  checked with a witness cell that only the caught reagent could have reached,
  and **SPEC §9.7 examples B and C come out at exactly 1280 and 3360**. The
  reagent roll itself is finally verified: 300 pieces across all five level
  bands against a Python model of `PieceGenerateNext`, byte for byte. P4 was
  right that nothing here had to touch the accumulator's arithmetic — only feed
  it. Work RAM is **522 bytes** against SPEC §17.1's ~560, forty-four *fewer*
  than P4 used, because an EFFECTQ entry turned out to be one byte and not two;
  ROM use is 47% / 51% / 64% of 16 KB.
- P5 broke one thing that had been true since P1 and fixed it: `CascadeRemove`
  marking every removed cell on the spot only worked while a step removed one
  run's worth. Five bolts in one run remove 71 cells and the dirty ring holds
  64, so it now falls back to the whole-well redraw cursor rather than dropping
  marks nothing would ever make again. See the P5 table.
- **Phase P6 is done.** A clear is an event now. Matched cells glow in their
  own colour, a bolt lays beams down its row and column, a fireball turns its
  colour white board-wide, and then the whole lot shatters through one white
  ring — while a marked prism sits the glow out and blips inward instead. A
  prism at rest turns. The band says `LEVEL UP` and `CHAIN x3`. The well
  petrifies from the floor up at game over, each cell into its own stone shape.
  Every duration is read back off the VDP's own name table frame by frame on
  both regions, and the whole twelve-frame sequence for one cell is a single
  assertion: `[(potion, 1), (glow, 6), (ring1, 2), (ring2, 2), (ring3, 2)]`.
  Work RAM is **533 bytes** against SPEC §17.1's ~570; ROM use is
  52% / 56% / 68% of 16 KB.
- P6 changed SPEC twice, both times because the code met a number that could
  not be right. **SPEC §14's PAL removal was 5 frames for 3 tiles at 2 frames
  each**, which does not divide, so the removal, the bomb blast and the prism's
  blip-out are now the same on both regions for the reason `FALL_FRAMES`
  already was. And **Appendix A said no board cell can hold 113–115**, which
  stopped being true the moment a prism rotated: the constraint is not that
  nothing may write a wild cell's glyph, it is that nothing may *read* one.
- Next: **P7 — screen states.** P6 leaves it the two pieces it needs: the
  petrify is written and wired, so P7 adds the banner, the fanfare and the
  timeout around it, and `AnimBannerShow` is the message band's one entry
  point. Read the P9 table below before starting.

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
- **`make DEBUG=1`** builds with `-DWL_DEBUG`, which now does exactly one
  thing: skip the title screen and start playing. A headless machine has no
  input attached, so without it every run sits on the title forever. P1's
  `BoardDebugFill` is gone — a real falling piece is a better test of the
  render path than a painted-on pattern. Changing the setting forces a
  rebuild; it did not used to, and a stale build under the other flag looks
  exactly like a bug in the game.
- **`make playtest` plays the game and checks what happened.** `tools/playtest.py`
  boots the AC6502 DEBUG cartridge paused, advances it one frame at a time with
  the joystick held wherever the test wants it, and reads `PieceCol`,
  `PieceRow`, `PieceA`-`C` and the board out of RAM after each frame — so DAS
  timing, rotation, soft drop, the lock delay, the walls and the floor are all
  assertions about numbers. Joystick **side `b`** is joystick 1; side `a` is the
  port the game does not read, and pointing at the wrong one looks exactly like
  input being ignored.
- **`make playtest` counts GAME frames, not cycles.** It advances with
  `exec.runTo GameLoop`, which stops at the top of the main loop with the
  previous frame's logic finished. Running a fixed 16,666 cycles instead — which
  is what it used to do — drifts the moment anything overruns vblank, and a
  cascade scan is most of a frame on its own: the peek then lands in the middle
  of the game's own work and reads a state it is halfway through writing. That
  looked exactly like two P2 timing regressions that were not regressions.
- **`make crosscheck` plays one headless game on all three and compares the
  wells.** It is the cross-platform half of `make playtest`, and it is slow —
  three whole games. What it proves is that the shared logic runs identically on
  the two Commodores; what it does not prove is that a *clear* looks right
  there, because the headless game deals five pieces that happen not to match
  and there is no way to plant a board through VICE the way the AC6502's debug
  protocol allows. See P3 below.
- **A `bpl` loop over more than 128 bytes does not loop.** `BoardClear` counted
  down from 159 to a `bpl` and wrote one byte of 160 for two whole phases,
  because bit 7 of 159 is already set. Nothing noticed until the falling piece
  needed a floor, and on the Commodores it *still* looked right, because
  uninitialised RAM happened to be non-zero where a sentinel belonged. Count up
  and end on a `cpx`.
- **A stale emulator on the debug port silently hijacks the test.** If a headless
  `6502` from an earlier run is still listening on 8770 or 8771, the one the
  test starts dies with `EADDRINUSE` into `/dev/null` and every `mem.read`
  below then reads *the other machine* — a different cartridge, sometimes
  billions of cycles in. It does not look like a broken harness; it looks like
  the game under test doing something impossible, and it burned a session
  before `make crosscheck` was believed again. `playtest.py` and
  `crosscheck.py` now refuse to start when something is already listening
  (`require_free_port`), and say which port to go and look at. `playtest.py`
  also terminates its emulator from an `atexit` hook, because a test that
  *raises* used to leave one holding the port and take the next run down with
  it — one broken assertion, two lost runs.
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
S1, S2 and S4 are settled; S3 and S5 are what is left.

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

### S2 — Does the piece feel right at the SPEC timings? — **settled**

**Yes. Played, and nothing changed.**

Lock delay 16 frames, DAS 12/4, soft drop 3 frames a row (SPEC §5.6, §11.3).
These are the numbers the game lives or dies on and they were chosen on paper;
they survived contact with a player unaltered, so SPEC §11.3 and §14 stand as
written and no table moved.

They are also verified, not just liked. `make playtest` confirms frame by frame
that a fresh press moves on the frame it arrives, that the repeat starts twelve
frames later and then runs every four, that rotation is edge-triggered and
never repeats however long UP is held, that soft drop is three frames a row
against gravity's forty-eight at level 1, and that the lock delay is sixteen
frames with four resets and no more.

**If a later phase wants to retune them, change SPEC §11.3 and §14 first** —
the tables are the authority, not the code, and the code reads them out of
`tables.inc` indexed by region, so a change is one edit in one place. P4 puts
the level ramp on top of these, which is the next thing that could make them
feel different; P5's reagents are the one after.

One thing the measurement did settle on the way past: SPEC §11.3 used to say
soft drop is ignored "at levels 14+ NTSC", and that never happens. Gravity's
fastest is 6 frames a row against soft drop's 3, so soft drop wins at every
level. The guard is still in the code and SPEC §11.3 now says why it never
fires.

### S3 — How well do the screen images compress? — *blocks nothing yet*

SPEC §17.2 budgets 800 bytes for the six screen images RLE'd. The margin is two
tiles (SPEC §12.5), so the images are almost entirely long runs and should beat
that comfortably — the C64's 1000-cell images look like they should come in
under 200 bytes each. Nobody has measured it, and nothing is waiting on it: at
43% of 16 KB the C64 carries them raw. Take the measurement when ROM gets
tight.

### S4 — Can the VIC-20 scan its keyboard without disturbing the joystick? — **settled**

**Yes, and the DDR dance the question assumed turns out to be unnecessary.**

Every key the game reads (SPEC §11.2) lives in matrix **rows 1-6**. Row 0 is
the top number row and row 7 is the rest of it, and the game wants no key from
either. So `$9122` is set **once** to `$7F` and never touched again: PB0-PB6
drive the six rows that matter and PB7 stays an input for the RIGHT switch. The
joystick and the keyboard never take turns, so there is nothing to interact.

That is also the safer arrangement, for a reason that has nothing to do with
the scan. Flipping the DDR back to `$FF` makes PB7 an output; drive it high
while a closed RIGHT switch is pulling it to ground and the VIA's output stage
is fighting the joystick. Never configuring PB7 as an output means that cannot
happen at all.

Confirmed on both Commodores by running `make DEBUG=1 smoke` with the scan in
place and reading the screen back: with no input attached the stack grows dead
straight up the spawn column and the pieces match a model of the generator
exactly, so the scan is contributing no phantom bits.

The **C64** has the same collision and it is not solvable there: joystick port
2 shares CIA1 port A with the keyboard columns, so a held direction pulls a
column low and a scan sees every key in it. Every C64 game with both has this.
The joystick is read first, with `$FF` on `$DC00` so no column is selected,
which at least keeps the stick clean.

The **AC6502** has no matrix at all — two encoders hand over one ASCII byte per
keystroke and there is no key-up event, so a key there is a one-frame pulse and
DAS never engages from it. SPEC §11.4 now says all of this.

### S5 — Does a real machine agree with the region detection? — *blocks P10*

`HalDetectRegion` samples the raster counter on both Commodores. It has only
been run against VICE, which is not evidence about a real 6560 or 6561.

---

## 5. Decisions

Numbered so phases can cite them. SPEC.md owns the *game* decisions; these are
the implementation ones that SPEC.md does not cover.

- **D1 — One translation unit.** `src/` modules are `.include`d, not linked
  separately. Revisit only if the assembler gets slow enough to matter.
- **D2 — The HAL is eight routines.** Growing it is fine; branching inside
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
- **D14 — The piece is marked, not drawn, and the mark waits for any redraw.**
  Every routine that moves or rotates the piece sets `PieceDirty`; `StatePlay`
  does the drawing, at the end of the frame, and only once `RedrawIdx` says no
  full-board redraw is outstanding. `RenderBoard` is a cursor that feeds the
  ring over several frames (D12), so a mark made while one is in flight is
  drawn *before* the redraw reaches that cell and is then painted over. One
  byte of BSS buys the guarantee; the alternative is a piece that disappears
  for four frames after every unpause.
- **D15 — SPACE is `UP`, and confirm accepts either bit.** One key cannot be
  both rotate-forward and rotate-reverse, so SPACE folds into `INPUT_UP` with
  `W` and cursor-up, while `RETURN` and `Q` fold into `INPUT_FIRE`. The title
  and game-over screens therefore test `INPUT_FIRE | INPUT_UP`, which also
  means joystick up starts a game. Nothing in play is ambiguous. SPEC §11.2
  records it.
- **D16 — A row of falling is a cursor, like a board redraw.** D12 says
  anything bigger than the ring is a cursor; gravity is the second thing that
  is. Six full columns dropping one row changes 84 cells and the ring holds 64,
  so `BoardGravityStep` stops when the ring is nearly full and resumes next
  frame, and `PlayGravity` only starts the two-frame beat once the row has
  actually landed. A heavy board therefore falls a shade slower instead of
  losing cells off the screen — a dropped mark during a fall is never marked
  again, which is the one case D6's drop-on-overflow does not survive.
- **D17 — The match scan starts at the top of the pile, not at row 0.** Every
  one of the four steps moves down at most one row, so a line that reaches the
  pile must cross its top row. Finding that row costs about 45 cycles a row of
  empty air and takes a six-row pile from 448 cells scanned to 178. SPEC §6.2
  now says so, because it changes the procedure and not just the code.
- **D18 — The awards SPEC §9.6 gives outside a cascade bypass the accumulator.**
  The soft drop's point a row and the level advance's 1000 go straight into
  `Score` through `ScoreAward`, not into `Cascade*` through `CascadeAdd`, so a
  star cannot double them. SPEC §9.6 lists them in the same table as the star
  multiplier and does not say; SPEC §8's `SETTLE` decides it, because its
  pseudocode never adds either one to `cascade_pts`. It also settles what the
  soft-drop point means: `PieceFallRate` now returns carry clear when the soft
  drop was the rate actually used, so a row that fell at gravity's own speed
  with DOWN held pays nothing — at level 16 there is no soft drop to reward.
- **D19 — Animation is two windows, not six timers.** SPEC §14 gives every
  effect its own duration and they do not agree — a glow is 6 frames, a
  fireball's flash 8, a prism's blip 10. Rather than a timer per effect, a step
  animates in `PLAY_GLOW` and `PLAY_SHATTER`, and **a window lasts as long as
  the longest thing in it**: the glow window is `GlowFrames` or `FlashFrames`
  when a fireball fired, the shatter is `SHATTER_STEPS` ring frames or
  `BLIP_STEPS` when a marked prism is winking out beside them. Every count in
  SPEC §14 holds and the game tracks two numbers. It also fixes what "the
  fireball flash is 8 frames" means when the cells flashing are the same cells
  glowing.
- **D20 — The fireball's flash is one shared byte, read by the platform.** The
  AC6502's colour belongs to an 8-pattern group and the Commodores' to a cell,
  so the same effect is one VDP write on one machine and a per-cell decision on
  the others — and a Commodore flush during the flash would undo any colour RAM
  poked ahead of it. `HalColorFlash` therefore sets `TintColor` and does
  whatever the platform needs; the Commodores' `HalPlotCell` substitutes white
  for any tile of that colour as it draws it, which stays consistent through
  every redraw for one `CMP` a cell. `TINT_NONE` is `$01`, not `$00`, because no
  masked tile can equal `$01` — so the test needs no separate "is anything
  flashing" branch, and `TILE_BLANK` is not accidentally in the tinted group.
- **D21 — A prism's glyph bits are a frame number, so nothing may read them.**
  The idle rotation writes `WILD_BASE + 0..3` into the board, whose low three
  bits read as a potion, a fireball, a bolt or a bomb. Every test of a wild cell
  is therefore a test of its **colour**, and the colour is tested *first*: the
  fireball's immunity, the effect queue, the beam pass and the game-over
  petrify all sit on this. P5 wrote the rule into `EffectEnqueue` a phase before
  the reason for it existed; SPEC §5.2 and Appendix A now say so as well, having
  previously claimed no board cell could hold 113-115.
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

- [x] S4 measured; keyboard scanning added to `HalReadInput` on all three
- [x] `piece.asm`: `PieceGenerateNext` per SPEC §5.2 — colours *and* reagents,
      because the compare chain is 20 bytes and leaving it out would have meant
      writing the same roll twice
- [x] `PieceSpawn`, with the game-over condition detected and handed to
      `STATE_GAMEOVER` (the petrify animation is still P7's)
- [x] `PieceMoveLeft` / `PieceMoveRight` / `PieceRotate` / `PieceRotateBack`
- [x] `PieceStep`, lock delay with `LOCK_RESET_MAX` resets, `PieceLock`
- [x] `input.asm`: `InputShift` — DAS on left/right, **no auto-repeat on rotate**
- [x] Soft drop, ignored when gravity is already faster — the guard is there,
      and with the shipped speed table it never fires (S2)
- [x] `RenderPiece` / `RenderPieceErase` / `RenderNext`
- [x] `main.asm`: `StatePlay` dispatching `PLAY_FALLING`, `PLAY_LOCKING`, `PLAY_ARE`
- [x] S2: played. The SPEC timings survived unaltered, so §11.3 and §14 stand
      as written and no table moved

Two things arrived alongside, because P2 could not run without them:
`ScoreGravity` (P4's module, but nothing falls without a speed) and
`tables.inc`, which had been written in P0 and never actually `.include`d by
any platform — nothing had needed a table until now.

**Exit criteria: met**, and checked against a model rather than by eye. The
falling piece can be steered to either wall and no further, rotation cycles the
three cells forward on UP and back on FIRE and never repeats however long the
button is held, soft drop and gravity run at their table rates, the piece locks
on the floor and on the pile after sixteen frames with four resets available,
the preview refills and overwrites the piece the artwork ships in the NEXT box,
and a blocked spawn ends the game. Every one of those is an assertion in
`make playtest` against `PieceCol` / `PieceRow` / `PieceA`-`C` read out of RAM,
frame by frame — see §3.

Cross-platform agreement is exact: with the LFSR seeded identically, the first
three pieces on all three machines are `[72,72,88]`, `[72,64,104]`,
`[64,64,80]`, matching a Python model of `RngNext` / `RngRange` /
`PieceGenerateNext` byte for byte, and the whole five-piece stack of a headless
run matches it too. Work RAM 558 bytes; ROM 37% / 42% / 54%.

**What P2 settled, for the phases that inherit it:** D14, D15, S2, S4, and four
things worth knowing before P3:

| Found | Consequence |
|---|---|
| `BoardClear` counted `ldx #159` down to a `bpl` and wrote **one byte of 160**. Bit 7 of 159 is already set, so the branch fell through immediately | The sentinels were never laid down. P1 did not notice because nothing read one; the Commodores did not notice because uninitialised RAM happened to be non-zero where the floor belonged, and only the AC6502's zeroed RAM let the piece fall out of the well. Count up, end on `cpx` — and see §3 |
| Nothing seeded the LFSR before the first `RngNext`, and a zero state is the one state a Galois LFSR never leaves | Every piece was identical. `GameInit` now seeds once so the generator is never stuck; `StateTitle` still reseeds from reaction time, which is the seed SPEC §15 actually cares about |
| `RngRange` takes the high byte of `random * limit` rather than a modulo | `random % 6` gives colours 0-3 a 43/256 chance against 4-5's 42/256. The multiply is uniform to within one part in 256, is fixed-time, and is reusable — P7's title shimmer wants a cell in 0-27 and a tile in 0-127 |
| The three cells under a falling piece are always empty, because every move and every gravity step tests them first and `PieceLock` is the only thing that writes them | `RenderPieceErase` is three blanks, not three board reads. If P3 ever writes the piece into the board early, that stops being true |

---

### Phase P3 — Matching and gravity

**Goal:** it becomes a game. Runs clear, tiles fall, chains count.

- [x] `match.asm`: the four scan passes, `Marks` filled, `RunCount` set — one
      `ScanLine` walked with four different steps, +1, +8, +9 and +7, each
      ending on a sentinel rather than on a bounds check
- [x] Wildcard handling in the scanner, ahead of the prism existing (SPEC §6.3)
- [x] `MarksClear` / `MarkSet` / `MarkTest`
- [x] `BoardGravity` — per-column compaction, marking moved cells dirty; a row
      at a time and as a resumable cursor (D16)
- [x] `cascade.asm`: `CascadeBegin` / `CascadeStep` / `CascadeSettle` skeleton,
      scan and removal only
- [x] `PLAY_GRAVITY` sub-state, one row every `FALL_FRAMES`
- [x] Chain counter advancing across cascade steps

**Exit criteria: met**, and checked against RAM rather than by eye. Three of a
colour clear horizontally, vertically and on both diagonals; two do not; a run
of four is one run and counts once; a hole in a row does not hide the run past
it; an L of five cells is two runs and clears once; a prism closes a red run,
three prisms are a run of their own, and one prism closes a red run and a blue
one in the same scan and counts twice; a red potion, a red fireball and a red
star are one run, because colour matches and glyph does not. Tiles above a clear
fall **one row every two frames, measured row by row**, and a fall that makes a
new run runs the cascade on to `ChainStep` 3. Every one of those is an assertion
in `make playtest` against `Marks`, `RunCount`, `ChainStep` and the board, read
out of RAM frame by frame.

The two invariants the criteria really turn on are checked on a full board, not
a contrived one: an 84-cell well with a six-wide clear along the bottom
settles in 7 frames with **nothing floating** and — read back out of the VDP's
own name table — **not one cell of the well differing between the board and
the screen**. That is the test that says D16 works.

`make crosscheck` plays one headless game on all three machines and compares
the wells: the VIC-20, the C64 and the AC6502 finish byte for byte identical.
**What that does not cover is a clear on a Commodore**, and it is worth being
plain about it: the headless game has no input, so every piece lands in the
spawn column, and the five pieces it deals before the well blocks happen to
contain no run. Planting a board needs memory writes at a chosen moment, which
the AC6502's debug protocol gives and VICE's `-moncommands` does not — VICE has
a binary monitor that would, and P4 or P6 is where building that client starts
to pay for itself. Until then the rules are proven on one machine and *identical
execution* on the other two.

**What P3 settled, for the phases that inherit it:** D16, D17, and five things
worth knowing before P4:

| Found | Consequence |
|---|---|
| A line that stops at the first empty cell never looks below the top of the pile. Every diagonal starts in row 0, which is empty for most of a game, so the first scanner found nothing at all | **A hole breaks the run, not the line.** Only a wall ends a line. SPEC §6.2 now says so, because it is a property of the procedure and not of the code |
| The first working scan cost **33,336 cycles** — two whole frames — where the estimate had been "it runs once a step, it will be fine" | Measured, then fixed: start at the top of the pile (D17), keep the cursor in X, and never call a subroutine on the two paths a scan spends its life in (an empty cell, and a colour change, which is five adjacent cells in six). **11,542 cycles** now, and `CascadeRemove` 8,411 → 1,352 by skipping rows whose `Marks` byte is zero |
| Six columns falling one row changes 84 cells; the dirty ring holds 64 and drains 24 a frame | D16. Gravity is a cursor, and the two-frame beat starts when the row lands rather than when it was asked for. A dropped mark in a *fall* is never corrected, which is the one place D6 does not hold |
| A cascade step is a whole frame's work on a deep pile, and the game's frame is one trip round `GameLoop` however long that takes | A test that advances by cycles reads state the game is halfway through writing. `make playtest` advances by `exec.runTo GameLoop` instead (§3) — and two P2 assertions that "broke" in P3 were this, not the game |
| `StatePause` put the piece back on resume whatever the sub-state was, and from `PLAY_GLOW` upward `PieceA`-`C` are stale — the cascade may have taken those cells away entirely | Resume only re-marks the piece below `PLAY_GLOW`. Harmless before P3, because a locked piece still matched the board underneath it |

### Phase P4 — Scoring and levels — **done**

**Goal:** the full scoring loop from SPEC §9 and the speed ramp from §10.

- [x] `score.asm`: `ScoreReset`, `CascadeAdd`, `CascadeAddTimes`, `ScoreAdd`
- [x] Four-byte BCD accumulate, clamped at 9999999, never wrapping
- [x] Per-run scoring: `TileValue[chain]`, `LengthBonus`, `MultiBonus`
- [x] `ScoreLevelCheck` — 30 tiles a level, one advance per step, surplus carries
- [x] `ScoreGravity` indexing `SpeedNTSC` / `SpeedPAL` by region
- [x] Live high score update, and the flash when it is overtaken
- [x] Panel fields updating on change

**Exit criteria met.** `make playtest` reads all of it out of RAM and off the
VDP's name table, against SPEC arithmetic recomputed in Python rather than
against constants the test made up: SPEC §9.7 example A pays exactly 60; runs
of 3, 4, 5, 6 and 7 pay their tile value plus their length bonus; two runs
sharing a corner pay both runs and `MultiBonus[2]`, with the shared cell
scoring twice and clearing once; a second cascade step pays 50 a tile and not
20; thirty tiles advances the level once with the surplus carrying and 72 in
one step still advances it only once; 9999950 + 60 clamps to 9999999 and stays
there; the soft drop pays a point a row and a row that fell at gravity's rate
pays none; the panel shows what RAM holds, all seven digits, zero padded; the
high score is taken the instant it is passed, carries the level it was set on
in BCD, tracks the live level while the run holds it, and flashes once. Gravity
is read back off real falls — poke the level, poke `GravityTimer` to 1, run one
frame, read what `ScoreGravity` reloaded — and all sixteen levels on both
regions match SPEC §10.2, including the cap holding at levels 17 and 99.
`make crosscheck` agrees on the well, the SCORE box and the LEVEL box on all
three machines.

**What came out of it.**

| What happened | What it changed |
|---|---|
| The one moment a run's length and colour are both in hand is `MatchEmit`, *before* its mark loop — which counts `ScanLen` down to zero on its way back along the line | Scoring is a call at the top of `MatchEmit`. `MatchScoreRun` is the only routine in the game that must run before a loop rather than after it, and the comment says so |
| Once the score overtakes the high score the two are **equal**, and every subsequent bank copies again | `HighOwned`. Without it the one-shot fanfare and flash of SPEC §9.8 fire on every bank for the rest of the game. The copy itself is not one-shot and must not be — that is what keeps `HighLevel` tracking the live level (SPEC §9.8) |
| SPEC §9.6 lists the soft drop and the level bonus in the same table as the star multiplier, and does not say whether a star doubles them | D18. SPEC §8's `SETTLE` decides it: its pseudocode never adds either to `cascade_pts`, so they go straight to `Score`. `PieceFallRate` returns carry to say whose rate a row actually fell at, so DOWN at level 16 earns nothing |
| The tile-value multiply is `length × TileValue[chain]`, and a vertical run can be sixteen cells long | A loop of BCD additions with the count in Y, not a multiply routine. Three to sixteen adds is smaller and faster than anything worth writing, and SPEC §9 chose multiples of ten so that every add is one `ADC` |
| Three bytes of cascade accumulator, doubled up to three times at settle | `CascadeClamp`. Not reachable by playing — a cascade can only ever remove the 96 cells the well holds, which caps it around 200,000 — but "never wraps" in SPEC §9 has to hold for every accumulator on the path, not just the one on the panel |
| A headless `6502` left listening on the debug port from an earlier run hijacks the next test completely | `require_free_port` in both tools (§3). It cost a session: `make crosscheck` was reading a two-billion-cycle-old machine and reporting a game that could not exist |
| The headless crosscheck game has no input, so every piece lands in the spawn column and whether it ever matches is down to the seed | The score and level are still compared on all three, and the run prints a note when the comparison came out three zeroes rather than pretending it proved something |

---

### Phase P5 — Reagents — **done**

**Goal:** the five reagents and the chain reactions between them (SPEC §7).

- [x] `PieceGenerateNext` gains the reagent roll — one per piece, `PSpecial`
      and `ReagentThresholds` by level band. Written in P2, because the compare
      chain is 20 bytes and leaving it out meant writing the same roll twice —
      but never *checked* until now: P2's model check ran on a seed that dealt
      no reagent at all
- [x] `EffectQClear` / `EffectQPush` / `EffectQPop`, drop-on-overflow per D6
- [x] `EffectFireball` — colour-scoped, board wide, prisms immune
- [x] `EffectBolt` — row plus column
- [x] `EffectBomb` — 3 × 3, clipped at edges
- [x] `EffectStar` — `StarCount`; the cap is `CascadeSettle`'s, because SPEC
      §9.6 doubles the whole cascade at the end and the count has to reach it
- [x] `EffectPrism` — `BONUS_PRISM`, no removal
- [x] Reagents removed by other reagents' effects are enqueued and fire
- [x] `EffectValue[chain]` and the trigger bonuses — through `CascadeAddTimes`
      and `CascadeAdd`, which P4 left with exactly this shape
- [x] `CascadeSettle` applies the star multiplier to the whole cascade — done in
      P4; `EffectStar` only has to count into `StarCount`

**Exit criteria met**, and every number below is read out of RAM or off the
VDP's own name table and compared with SPEC §7 and §9 arithmetic recomputed in
Python, never with a constant the test made up.

All twenty-four cells of SPEC §7.4's interaction table are exercised: a potion,
a fireball, a bolt, a bomb, a star and a prism, each removed by a match, by a
fireball, by a bolt and by a bomb, with a *witness* cell in every case that only
the caught reagent's own effect can reach — so "it fired" is a tile that
vanished and not a flag. **The prism survives a fireball and dies to a bolt and
to a bomb.** A fireball inside a run detonates once; two of them in one run
each pay 500 and the second finds nothing left. Two bolts in one run cut two
crosses, and the tile in neither cross is still there afterwards. A bomb at the
bottom-left corner takes four cells and not nine, and the sentinels are read
back intact. One star doubles, two quadruple, three make ×8 and **four still
make ×8**. The effect queue was empty at the end of all sixty-eight cascades
the suite runs.

**SPEC §9.7 example B pays exactly 1280 and example C exactly 3360**, both at
chain 2 with the depth planted rather than played into.

The reagent roll is checked against a Python model of `RngNext` / `RngRange` /
`PieceGenerateNext`: **300 pieces across all five level bands, byte for byte,
none differing** — dealt sixty at a time by re-entering `PLAY_ARE` on an empty
board, one piece a frame. At most one reagent in any piece, all five types come
out of the chain, a prism is always colour 6, and the observed rates track
SPEC §5.3's table. `make crosscheck` compares the NEXT box across all three
machines as well as the well, the SCORE and the LEVEL.

Work RAM is **522 bytes** against SPEC §17.1's ~560 — *down* 44 from P4's 566,
because the queue entry got smaller (below). ROM use is 47% / 51% / 64% of
16 KB.

**What came out of it.**

| What happened | What it changed |
|---|---|
| SPEC §8 budgeted two bytes an EFFECTQ entry for a packed `glyph\|row\|col`. But marked cells are not zeroed until step 6 and the queue drains in step 4, so the reagent is **still on the board** when its entry pops | The entry is a board index and nothing else — one byte, and the glyph and colour are an `lda Board,x` away. 48 bytes back, and SPEC §8 and §17.1 now say so |
| A prism is glyph 0 of colour 6, so by glyph alone it is a plain potion — and from P6 on, its four idle rotation frames read as a bolt or a bomb | `EffectEnqueue` tests the **colour before the glyph**. The same test is the fireball's immunity rule for free: a fireball's colour is never 6, so the compare that finds its targets skips prisms without a special case (SPEC §7.4) |
| `CascadeRemove` marked every removed cell on the spot, with a comment saying it did not need the cursor treatment gravity gets — true when a step removed one run's worth. **Five bolts in one run remove 71 cells and the ring holds 64** | The comment was wrong the moment reagents existed. It now falls back to `RenderBoard`, the whole-well cursor `RenderFlush` already feeds (D12), rather than dropping marks that are never made again (D6). Measured: the screen is 3 frames behind when the cascade settles, and the ARE delay is 12 |
| The effect queue's termination is not a limit, it is structural: an effect only ever *marks*, never adds, and `EffectHit` refuses a cell that is already marked | A cell is pushed at most once, so the drain is bounded by the 96 of the well. `EffectHit` is also the one place the wall test lives, which is what lets the walks run over the sentinel columns — a marked sentinel would be zeroed by `CascadeRemove` and the floor would grow a hole |
| SPEC §9.7 example C read "one more step for another 400", and **no board can do that**: a further step is chain 3 or deeper, where the cheapest run pays 300 and the next 500 (§9.1, §9.3). There is no 400 among them | SPEC was wrong, so SPEC changed first (§9.7 C now closes example B's run of four with a prism, whose bonus is exactly 400). Same 3360, and it exercises the wildcard, the fireball and the star at once. The star still doubles points scored before it cleared, which is what the example is for |
| A cascade step is now the scan **plus** the reagents. Measured on the worst board there is — a full well, a run of six, five bolts: scan 24,521 cycles, enqueue and resolve 22,145, against a 16,667-cycle frame | About three video frames for one step, which the game already tolerates: its frame is one trip round `GameLoop` however long that takes (P3). Not optimised, because it is the extreme and the common case is a handful of cells |
| A `playtest.py` assertion that *raised* left the emulator holding the debug port, and the next run then refused to start | `atexit.register(proc.terminate)`. One broken assertion used to cost two runs (§3) |
| The headless crosscheck game rolled no reagent at all, so comparing the three wells said nothing about SPEC §5.2 | The run now says which it was rather than looking like it proved something, and compares the NEXT box too. The glyph is part of every cell compared, so a divergence *would* show — there was none to see |

---

### Phase P6 — Animation — **done**

**Goal:** clears read as events rather than as the score jumping.

- [x] `PLAY_GLOW` — matched cells swap to glyph `+6` of their own colour.
      **Marked prisms are skipped** — group 14 has no `+6`
- [x] `PLAY_SHATTER` — the removal ring, `VFX_REMOVE1..3`, two frames each.
      One animation for the match, the bomb and the star
- [x] Marked prisms run `PRISM_BLIP` instead: the same ring closing inward
- [x] Prism idle rotation, `PRISM_SPIN + 0..3`, one frame every 8
- [x] Fireball flash: one VDP colour-table byte on the AC6502, one byte of
      state that `HalPlotCell` reads on the Commodores — same frame count,
      different mechanism. `HalColorFlash` is the eighth HAL routine (D2)
- [x] Bolt beam overlay (the bomb has no overlay of its own now)
- [x] Level-up and chain banners in the message band
- [x] Game-over petrify: `PETRIFY_BASE + (tile & GLYPH_MASK)`, bottom-up, so
      each cell sets as its own shape
- [x] Every duration from the SPEC §14 table, per region

**Exit criteria met** — 52 new checks, 240 in the suite — and every duration
below is counted off the VDP's own name table one frame at a time, never off a
timer the game happens to hold.

**A clear step takes the frames SPEC §14 says on both regions.** Six of glow
and six of shatter on NTSC, five and six on PAL, and no frame of a step spent
anywhere else. The whole visible life of a matched cell comes back as
`[(potion, 1), (glow, 6), (ring1, 2), (ring2, 2), (ring3, 2)]` and then empty
— one assertion covering the window lengths, the order of the ring and the two
frames a tile. **A marked prism holds its rotation frame for all six frames of
the glow**, then runs `116, 117, 57, 56, 52` inward at two frames each while
the potions beside it shatter and wait; the shatter window is the prism's ten,
not the potions' six. `WILD_BASE + GLYPH_GLOW` is never drawn — checked, on
every frame of that cascade.

**The board is untouched for all twelve of those frames**, which is the whole
of the phase: the glow is "of the cell's own colour" only because the cell is
still there saying what it is. Read back off RAM, frame by frame, for both
windows.

**The bolt's beam is whole.** Beam-H across all six cells of its row, beam-V
down all sixteen of its column, the cross on its own cell drawn over its own
glow — and the empty cells it covered for continuity are put back afterwards,
because nothing else would ever draw them again.

**The fireball flash is one byte on the AC6502**, read back out of the VDP's
colour table and compared with the value that table held *before* the flash:
the foreground nibble is 15 for the whole window, the background nibble is
untouched, and the original byte is back afterwards. The window is the flash's
eight frames and not the glow's six.

**A prism at rest turns** through `113, 114, 115, 112`, exactly eight frames
each, on the board and on the screen. **The well petrifies** in sixteen rows
of two frames — thirty-two, as SPEC §14 says — from the floor upward, each
cell into its own stone shape, and a prism into `PETRIFY_BASE` rather than into
a stone bomb. `make crosscheck` now plays all three machines to game over and
finds the same fifteen stone cells on each, so the petrify is compared across
platforms and not merely the well.

**The banners work and play never stops for one.** Thirty tiles raises
`LEVEL UP` and the level goes up with it; a played two-link chain — the reds
clear, the blues fall and only *then* make a run — raises `CHAIN x2`; a
one-step cascade raises nothing; and both come down on their own after
`BannerFrames`.

**Nothing in the animation path blocks the main loop**, and on an ordinary
clear nothing comes near a frame either: the glow goes up in **2,607 cycles**
and the shatter starts in **1,529**, against 16,667. The extreme board is a
different story and is in the table below.

Work RAM is **533 bytes** against SPEC §17.1's ~570 — eleven more than P5, five
of them zero-page walk cursors. ROM use is 52% / 56% / 68% of 16 KB.

**What came out of it.**

| What happened | What it changed |
|---|---|
| SPEC §14 gave the removal 6 frames NTSC and **5 PAL**, for "3 tiles at 2 frames each". Three twos are six, and 5/3 is not a frame count | SPEC was wrong, so SPEC changed first. The removal, the bomb blast and the prism's blip-out are **the same on both regions**, for the reason `FALL_FRAMES` already was: they are a tile count times `VFX_FRAMES`, not a duration. A PAL step is 11 frames against NTSC's 12 — 17 ms, which nobody can see |
| Appendix A said **"no board cell can ever hold 113–119"**, and the idle rotation makes that false on the first prism | The rule was never about writing, it was about reading: a wild cell's low three bits are a *frame number* and nothing may ask them what glyph they are. SPEC §5.2, A.1 and A.3 now say so. P5 had already made `EffectEnqueue` test the colour first for exactly this reason, one phase before the reason existed; `AnimCellBolt` and the petrify do the same |
| Every effect has its own duration in SPEC §14 and they do not agree — a glow is 6, a fireball's flash 8, a prism's blip 10 | One timer per **window**, not per effect, and a window lasts as long as the longest thing inside it. The glow window is `GlowFrames`, or `FlashFrames` when a fireball fired; the shatter is `SHATTER_STEPS`, or `BLIP_STEPS` when a marked prism is winking out beside it. Every count in the table holds and the game tracks two numbers instead of six |
| A beam laid over an **empty** cell has nothing behind it that anything will ever draw again, and D6 drops marks silently when the ring is full. Five bolts in one run put 110 beam cells through a 64-entry ring | The one mark in the animation that cannot be dropped. It takes `CascadeRemove`'s way out — the whole-well redraw cursor (D12). Every other animation mark is made again within a few frames: a lost glow is covered by the shatter, a lost ring frame by `CascadeRemove`. Worth writing down, because the asymmetry is not obvious and the failure is a white beam sitting in the well for the rest of the game |
| The AC6502's colour is per **group** and the Commodores' is per **cell**, so "turn every red tile white" is one VDP byte on one machine and 96 colour-RAM writes on the others — and any flush during the flash would undo those writes | `HalColorFlash` sets one shared byte, `TintColor`, and the Commodores' `HalPlotCell` substitutes white for any tile of that colour as it draws it. Consistent through every redraw for free, and it costs one `CMP` a cell. `TINT_NONE` is **$01** rather than $00 because no masked tile can equal $01, so there is no separate "is anything flashing" test |
| On the worst board there is, the frame that starts the glow costs **39,361 cycles** — worse than the scan before it | Measured, printed and lived with, exactly as P5 lived with its 22,145. It is a full well, a run of six and five bolts: 110 beam cells and 71 glow cells against a 64-entry ring, so most of it is dropped and the well is repainted. `make playtest` asserts nothing about that number and asserts the ordinary clear's 2,607 instead, because a test written to pass on the extreme would say nothing about either |
| `redraw()` in `playtest.py` waited for the redraw **cursor** to run out and not for the ring behind it, so a screen read on the next frame was one frame early | It waits for both now. Under P5 nothing noticed, because no test read the well the frame after a plant; the first P6 track came back starting with a blank cell. The same run turned up a second one: a cascade left half-finished by one test carried straight on over the board the next had just planted, which is what `quiet()` is for |
| The two expensive halves of a step — the scan and the removal — used to share one frame (P3's risk list, and P5 measured them at 46,000 cycles together) | They are twelve frames apart now, which is what D4 always implied and what P6 finally cashes in. Neither is competing with an animation for the same 16,667 cycles |

**One thing is not tested and should be said so.** The *tinted* half of the
Commodores' `HalPlotCell` — the white substitution — is exercised by nothing,
because a clear cannot be planted through VICE and the headless crosscheck game
rolls whatever the seed gives it (the same limit P3 recorded). What *is*
covered is everything around it: the AC6502's whole flash is read back out of
the VDP's colour table, and the untinted path on both Commodores runs on every
cell they ever draw — `tools/read-screen.py` tells the potion groups apart by
their **colour**, so `make crosscheck` reading the right well off a VIC-20
screen is also the evidence that `TintColor` is `TINT_NONE` and the ordinary
lookup is intact. Six instructions on each machine remain unproven; a real
machine and a fireball is the cheapest way to close it, in P10.

---

### Phase P7 — Screen states

**Goal:** a complete arcade loop — title, play, pause, game over, title.

- [ ] `StateTitle`: blinking prompt over the drawn screen. **No help pages** —
      the controls are on the page and the rest was cut (SPEC §13.1)
- [ ] The magic field: a random tile from `ART_BASE`..`ART_BASE + 127` into a
      random one of the block's 28 cells, every frame
- [ ] RNG seeded from the frame counter at the fire press (SPEC §15)
- [ ] `StatePause`: well washed with `TILE_WASH` so it cannot be studied,
      timers frozen. **Resuming inside a GLOW window loses the glow**: the
      resume is `RenderBoard`, which paints the board's own tiles back over
      it, and the glow is drawn once at the window's start rather than every
      frame. Cosmetic, six frames wide, and left for whoever rewrites this
      path — the shatter recovers on its own because it re-marks every
      `VFX_FRAMES`, and the board is authoritative throughout either way
- [ ] `StateGameOver`: the banner, the high-score fanfare and the 10-second
      timeout. **The petrify is done** — P6 wrote `AnimPetrifyBegin` /
      `AnimPetrifyTick` and `PlayAre` already starts it on a blocked spawn, and
      `StateGameOver` holds the input off until it finishes

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
| One removal ring (56–58) serves match, bomb and star. There is no separate blast or sparkle tile | P3, P5, P6 — done |
| **`WILD_BASE + GLYPH_GLOW` is an arrow, not a glow.** A matched prism sits out the glow phase | P5, P6 — done |
| A matched prism blips out — 116, 117, 57, 56, 52 — rather than shattering | P6 — done |
| A prism at rest rotates through 112–115, one frame every 8 | P6 — done, and it turned "no board cell can hold 113-115" into D21 |
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
- [ ] Set a fireball off on each Commodore and look at it. The tinted half of
      their `HalPlotCell` is the one thing P6 left unproven — VICE cannot be
      handed a planted clear — and it is six instructions that either turn a
      colour white or do not
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
- **The frame cost of a cascade step.** Measured, and the fix D4 implied has
  landed. The scan and the removal used to share one frame; `PLAY_GLOW` and
  `PLAY_SHATTER` now sit between them, twelve frames apart, so neither is
  competing with an animation for the same 16,667 cycles. On an ordinary clear
  nothing is close: the glow goes up in 2,607 cycles and the shatter starts in
  1,529. On the **extreme** board — a full well, a run of six, five bolts — the
  step is still several video frames wide (scan 24,478, reagents 22,161, the
  glow that follows them 39,361) and that is accepted rather than optimised,
  for the reason P5 accepted its half: overrunning is not corruption, it is one
  slow moment at the instant a piece locks, and the common case is a handful of
  cells. If it ever does matter, the glow is a *pass over marked cells* and
  splitting it across two frames is a cursor like every other one in the game
  (D12, D16). **Termination** was never in doubt — effects only remove tiles and
  each cell marks once — and is now also observed: every cascade in
  `make playtest` settles, including one on a full board.
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
- **A fourth platform.** The HAL is eight routines; the tile format is shared
  by anything with 8 × 8 1bpp characters. The work would be a linker config, a
  cartridge header, and one new `WizardsLab.asm`.
