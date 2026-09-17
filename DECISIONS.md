# Wizards Lab — Decisions

The design record behind the code: the questions that had to be measured (S1–S5)
and the implementation decisions (D1–D26) that the sources cite by label.
[SPEC.md](SPEC.md) owns the *game* rules; this file owns the choices about how
the game is built.

Both sections were kept verbatim from the implementation plan when the plan was
retired. Phase labels in the sources (P0–P10) name that plan's build order, and
it stays in history: `git show f3eab29:PLAN.md`.

## Settled questions (S1–S5)

Things that needed measuring, not deciding. Each one blocked the phase named.
S1 through S4 are settled; S5 is answered on NTSC and cannot be asked on PAL
here.

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

### S3 — How well do the screen images compress? — **settled, and nothing is done about it**

**Well enough to be worth doing, and nowhere near as well as SPEC §17.2
assumed.** Measured with a byte-pair RLE — a count and a value, runs capped at
255 — over what each cartridge actually carries:

| Cartridge | Raw | RLE'd | Saved |
|---|---:|---:|---:|
| AC6502 | 1536 | 904 | 632 |
| VIC-20 | 2024 | 728 | 1296 |
| C64 | 4000 | 1022 | 2978 |

A title screen comes to 330 bytes and a play screen to 574 — not the "under 200
bytes each" §17.2 predicted. The prediction's reasoning was the wrong one: the
margin is two tiles (SPEC §12.5) and does compress to almost nothing, and so do
the colour maps, but the panel is boxes and ornamental frames drawn a cell at a
time and that detail is most of a play screen. SPEC §17.2 now carries the
measurement.

**Nothing is waiting on it and nothing has been implemented.** The most a
cartridge would get back is the C64's 2978 bytes, and at 73% of 16 KB it does
not need them; a decoder would cost some of that back, and every image would
stop being a plain `.incbin` of a file `make artwork` writes. It stays on the
deferred list (in the implementation plan, now history) with the number attached, so the decision can be made on
arithmetic if ROM ever gets tight.

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

### S5 — Does a real machine agree with the region detection? — *NTSC: yes*

`HalDetectRegion` samples the raster counter on both Commodores. **The NTSC
side is now answered on hardware:** a gold-label VIC-20 with an original MOS
6560 comes up NTSC and plays at NTSC speed, and so does a C64 Ultimate. The
Ultimate is an FPGA recreation rather than a real 6567, so it is good evidence
and not proof about that chip; the VIC's 6560 is the real thing.

**PAL is unanswered and will stay that way here** — there is no PAL machine to
sample a 6561 or a PAL 6567 with. What rides on it is the region branch and
the `SpeedPAL` side of the timing tables, both of which run correctly under
VICE in PAL mode. Marked untested rather than open.

---

## Decisions (D1–D26)

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
- **D15 — SPACE is `FIRE`, and confirm accepts either bit.** One key cannot be
  both rotate-forward and rotate-reverse, so SPACE has to fold into one of
  them; it folds into `INPUT_FIRE` with `RETURN` and `Q`, leaving `W` and
  cursor-up to carry rotate. The title and game-over screens therefore test
  `INPUT_FIRE | INPUT_UP`, which also means joystick up starts a game.
  Nothing in play is ambiguous. SPEC §11.2 records it.

  It went the other way first — SPACE as `INPUT_UP` — on the reasoning that a
  Commodore's shifted cursor pairs are awkward enough that a keyboard player
  might never find rotate otherwise. Then the AC6502 gained its cursor keys,
  which are four plain codes and not awkward at all, and holding the old rule
  would have meant SPACE doing one thing on one machine and the opposite on
  the other two. One game, one control scheme; the divergence is not worth
  what it bought.
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
- **D22 — The audio driver is shared by three machines, not two, and
  `HalSfx` takes a note.** SPEC §16 put the split one level lower: a SID driver
  shared by the AC6502 and the C64, a VIC-I driver written separately, and a
  `HalSfx` that is handed an effect id. Everything above the register writes is
  the same on all three machines, though — which effect is playing, which step
  of it, how long the step lasts, what pitch it is, and which request wins when
  three arrive in one frame — so all of that is in `src/audio.asm` and the
  platform is asked for one note in one timbre. What makes it fit two sound
  chips with nothing in common is that **a timbre is a voice AND an octave**:
  the VIC-I's bass, alto and soprano oscillators are the same design divided by
  256, 128 and 64, so they are exactly an octave apart and `TIMBRE_SOFT` /
  `BUZZ` / `BRIGHT` cost one register choice there, against a 16-bit shift on a
  SID. The register writes the two SID machines DO share live in
  `include/sid.inc`, which is the one file in that directory that is code
  rather than equates: it belongs to two platforms and not to the third, so it
  can be in neither `WizardsLab.asm` and it cannot be in `src/`, where nothing
  touches hardware (D2).
- **D23 — One sound at a time, and the effect id is the priority.** SPEC §16
  lists the twelve from the quietest event to the loudest, so "is this request
  louder than what is playing" is a `CMP`. A request that loses is dropped
  rather than queued: by the next frame the event it belonged to is over.
  Logic therefore goes through `SfxPlay` instead of storing into `SfxRequest`,
  because more than one effect is asked for in a single frame routinely — a
  lock, the chime for the run it made and the bomb inside that run are three
  requests in one frame, and the bomb is asked for FIRST (it is resolved inside
  `CascadeScan`, and the chime after it returns). A plain store would leave the
  quieter of the two playing for no better reason than being written second.
- **D24 — The title screen has an ambience, built out of the twelve effects.**
  SPEC §13.1 gives it two moving things and no sound; this is a third, and it
  is the sounds of the lab rather than music — a cauldron bubbling under the
  page and one of the game's own effects drifting past every so often at half
  volume. It is not a music driver and does not mix, because one channel
  cannot: `AmbienceTick` hangs off the SILENT branch of `AudioTick`, so it
  fills the gaps rather than sharing them, and a bubble is an effect out of
  `SfxSteps` like any other — three more step lists, ids 13-15, begun through
  `SfxBeginShifted` with a fresh random transposition. `AmbTable`'s sixteen
  entries are the entire mix; changing the balance is changing that table.
  Two consequences worth naming. **The ids above `SFX_COUNT` are not events**
  and nothing may ask for one through `SfxPlay`, because they sit above a game
  over in a scheme where the id is the priority (D23) — the ambience takes the
  channel outright, on a frame it already knows is silent. And **bit 7 of the
  timbre is a LEVEL**: neither chip has a per-voice volume, so "quieter" is a
  master register the platform writes on its way past, and the byte already
  going there carries the choice. Every `HalSfx` masks it off first, and the
  channel lets go at the level it was playing at — a full-volume release on a
  quiet note is a click at the end of every bubble.
- **D25 — A game announces itself with the game-over run backwards.** SPEC §16
  has twelve effects and none of them covers the transition that matters most:
  the screen changes, a piece is already falling, and nothing says so.
  `SFX_START` is the eight notes of the game-over run in the other order, and
  the two things about it that are NOT mirrored are the point — `TIMBRE_BRIGHT`
  rather than `SOFT`, which puts it two octaves above its twin, and three
  frames a step rather than six, because a loss may take its time and a start
  may not. A scale and not an arpeggio, which is what keeps it clear of the two
  fanfares. **It is id 13, above the game-over run**, because the id is the
  priority (D23) and the player can steer the first piece while it is still
  playing: a move blip cutting the game's own opening in half would be the
  first thing they ever hear. The three ambience ids moved up to 14-16 to make
  room, which is the whole cost of the ordering being meaningful.
- **D26 — One AC6502 cartridge serves both video cards.** The same image runs
  unchanged on a TMS9918A with BIOS 1.x and on a 6502-PICOVDP with BIOS 2.x,
  and it stays that way. It can, because it asks the machine for almost
  nothing: the tiles are its own, uploaded from the cartridge's `TILES`
  segment, so it never reads the 1.x character set at `$B800` (Kernal code on
  2.x); it calls only `KernalInit` and `ReadJoystick1`, which keep their slots
  on both BIOS lines; and it never prints, so 2.x leaves the PICOVDP in its
  reset-time legacy submode, where the game's TMS9918 register writes select
  Graphics I and `HalWaitFrame`'s status poll behaves as before. The tools run
  on both cards by default (`CARDS=`), so 2.x stays tested rather than
  assumed. **There is no VDP build in this line.** Nothing the PICOVDP adds
  can be shown without breaking the game's own rules — richer tiles or colour
  would be art drawn outside the TMS9918 project (D10), and scrolling, palette
  cycling or a taller screen would be a feature on one machine only (SPEC
  pillar 3) — and a VDP-only image would be the first that fails on a
  TMS9918A. If that changes, it is a new SPEC revision and a new version.
  `include/ac6502.inc` stays the frozen BIOS 1.6 copy, byte for byte: its
  memory-map text is right for 1.6, and this cartridge's own comments say what
  differs on 2.x.
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
