# WIZARDS LAB — Game Design & Rules Specification

**Version:** 0.1 (design draft)
**Targets:** AC6502 (TMS9918 Graphics Mode I) · Commodore VIC-20 · Commodore 64
**Format:** 16 KB cartridge, all platforms
**Genre:** Falling-block match-3 (Columns lineage)

> This document is the gameplay bible. It is normative: every number here is
> intended to be lifted straight into `constants.inc`. Platform build details
> and the art/tile production notes live in the appendices.

---

## Table of Contents

1. [Concept & Pillars](#1-concept--pillars)
2. [Platform Matrix](#2-platform-matrix)
3. [The Board](#3-the-board)
4. [Colors, Glyphs & Cell Encoding](#4-colors-glyphs--cell-encoding)
5. [Pieces](#5-pieces)
6. [Matching](#6-matching)
7. [Specials](#7-specials)
8. [Cascade Resolution](#8-cascade-resolution)
9. [Scoring](#9-scoring)
10. [Levels & Speed](#10-levels--speed)
11. [Input](#11-input)
12. [Screen Layout](#12-screen-layout)
13. [Game States & Flow](#13-game-states--flow)
14. [Animation & Timing](#14-animation--timing)
15. [Randomness](#15-randomness)
16. [Audio](#16-audio)
17. [Memory Budget](#17-memory-budget)
- [Appendix A — Master Tile Map](#appendix-a--master-tile-map)
- [Appendix B — Constants Summary](#appendix-b--constants-summary)
- [Appendix C — Platform Build Notes](#appendix-c--platform-build-notes)
- [Appendix D — Build Order](#appendix-d--build-order) *(moved to PLAN.md)*
- [Appendix E — Cut List & Stretch Ideas](#appendix-e--cut-list--stretch-ideas)

---

## 1. Concept & Pillars

You are an apprentice in a wizard's laboratory. Potions rain down from the
shelves in vials of six colors. Sort them into groups of three or more — in any
line — and they react and vanish. Among the potions fall **arcane reagents**:
fireballs, bolts, bombs, stars and prisms. Handled well they cause spectacular
chain reactions; handled badly they are just more clutter.

### Pillars

1. **One rule, deep consequences.** Everything matches by *color*. The glyph on
   a tile never changes how it matches — only what happens when it clears. A
   player who understands "three of a color, any direction" understands the
   whole game on turn one, and spends the next hundred games learning what the
   reagents do to each other.
2. **Chain reactions are the fantasy.** Specials trigger specials. The best
   moments are the ones the player set up two pieces ago and could not fully
   predict.
3. **One game, three machines.** Identical playfield, identical tile indices,
   identical timing (in frames). The platforms differ only in how a tile gets a
   color and how bytes reach the screen.
4. **Cartridge discipline.** No disk, no load, no persistence. Power on, play,
   power off. High score lives in RAM for the session only.

---

## 2. Platform Matrix

| | **AC6502** | **VIC-20** | **C64** |
|---|---|---|---|
| CPU | WDC 65C02S | 6502 | 6510 |
| Video | TMS9918 / pico9918, **Graphics Mode I** | VIC-I (6560/6561) hi-res text | VIC-II standard text |
| Text grid | 32 × 24 | 22 × 23 | 40 × 25 |
| Tile size | 8 × 8 | 8 × 8 | 8 × 8 |
| Tileset | 256 patterns @ VRAM `$0000` | 256 chars @ `$1400` (RAM) | 256 chars @ `$2000` (RAM) |
| Color model | **Per 8-pattern group** (32 entries) | Per cell, 8 fg colors | Per cell, 16 fg colors |
| Cart | `$C000-$FFF9` (16 K window) | BLK3 `$6000` + BLK5 `$A000` | `$8000-$BFFF` (EXROM+GAME low) |
| Work RAM | `$0800-$7FFF` (30 K) | ~1.5 K + ZP (see C.2) | 32 K + `$C000` |
| Sound | SID / ARMSID | VIC-I 3 osc + noise | SID |
| Refresh | 60 Hz (NTSC) | 60 / 50 Hz | 60 / 50 Hz |

### 2.1 The binding constraints

Three constraints shaped every decision in this document:

- **VIC-20's 22 × 23 grid** sets the playfield size for all three machines.
- **VIC-20's 8 foreground colors** (black, white, red, cyan, purple, green,
  blue, yellow) cap the potion palette at **6 colors + white for UI**. Happily,
  the C64's first eight colors are numerically identical, so *the same color RAM
  byte works on both Commodores*.
- **TMS9918 Graphics I colors patterns in groups of 8**, not per cell. This is
  the strictest rule, so it drives the tileset layout: **each potion color owns
  one 8-pattern group**, and every glyph of that color lives inside it. See
  [§4](#4-colors-glyphs--cell-encoding) — it turns out to be a gift, not a tax.

---

## 3. The Board

### 3.1 Dimensions

```
Playfield:  6 columns × 16 rows = 96 cells
Column 0 = leftmost      Row 0 = top (spawn row)
```

Six wide is the Columns standard and the widest that leaves room for an info
panel inside 22 columns. Sixteen rows is one row taller than a stock Columns
well; it fits the 22 × 23 panel exactly and is a power of two, which matters
below.

### 3.2 Memory layout — stride 8, not 6

The board is stored with an **8-byte stride**, wasting two bytes per row on
purpose:

```
BOARD:  20 rows × 8 bytes = 160 bytes

    col:   0  1  2  3  4  5   6    7
  row  0 [ .  .  .  .  .  .  FF   FF ]   ← playfield rows 0..15
  ...
  row 15 [ .  .  .  .  .  .  FF   FF ]
  row 16 [ FF FF FF FF FF FF FF   FF ]   ← floor sentinel
  row 17 [ FF FF FF FF FF FF FF   FF ]   ← floor sentinel (diagonal safety)
  row 18 [ FF FF FF FF FF FF FF   FF ]   ← reserved
  row 19 [ FF FF FF FF FF FF FF   FF ]   ← reserved

  address(row, col) = BOARD + (row << 3) + col
```

Why this pays for itself:

- **`row << 3` is three `ASL`s.** No 6× multiply, no lookup table.
- **Columns 6 and 7 are permanent `$FF` walls.** Horizontal and diagonal scans
  run off the right edge into a sentinel and stop naturally — no bounds check
  in the inner loop.
- **The left edge is free too.** The byte one before column 0 of row *R* is
  column 7 of row *R-1* — already a wall. Scans walking left or up-left
  terminate on their own.
- **Two sentinel floor rows** let downward and diagonal scans overrun safely.
- The whole board is 160 bytes and fits comfortably in a single page, so
  `BOARD` can be page-aligned and indexed with a single `LDA BOARD,Y`.

### 3.3 Cell values

| Value | Meaning |
|---|---|
| `$00` | Empty |
| `$40`–`$6F` | An occupied potion cell — **the byte is literally the tile index** |
| `$70`–`$77` | Prism (wild) |
| `$FF` | Wall / sentinel (never appears in the playfield proper) |

There is **no translation step between the board and the screen.** A render
pass copies board bytes straight into screen memory. See [§4](#4-colors-glyphs--cell-encoding).

---

## 4. Colors, Glyphs & Cell Encoding

### 4.1 The core idea

> **Tiles match on COLOR. The glyph decides what happens when they clear.**

A red potion, a red fireball, and a red star are all "red" to the match
scanner. This is the single most important rule in the game, and it is also the
cheapest thing to implement: color equality is one `AND #$F8` and one `CMP`.

It also means every special is *steerable*. You never get a reagent you cannot
place — you place it exactly like the potion it resembles, and decide whether
you want it to go off now or sit in the pile until you build something bigger
around it.

### 4.2 Encoding

```
tile index = COLOR_BASE + (color << 3) + glyph

  COLOR_BASE = $40 (64)
  color      = 0..5   (potions)  |  6 = prism/wild
  glyph      = 0..7   (see table below)
```

| Operation | Code |
|---|---|
| Is cell empty? | `LDA cell` / `BEQ empty` |
| Color of cell | `AND #$F8` (this *is* the color key — no shifting needed) |
| Is it a wildcard? | `AND #$F8` / `CMP #$70` |
| Is it a wall? | `CMP #$FF` |
| Glyph of cell | `AND #$07` |
| Same color? | `AND #$F8` / `CMP other_masked` |

### 4.3 Color assignments

| # | Name | Tile base | TMS9918 fg | VIC-20 / C64 color RAM |
|---|---|---|---|---|
| 0 | Red | `$40` (64) | 8 — Medium Red | 2 |
| 1 | Yellow | `$48` (72) | 11 — Light Yellow | 7 |
| 2 | Green | `$50` (80) | 3 — Light Green | 5 |
| 3 | Cyan | `$58` (88) | 7 — Cyan | 3 |
| 4 | Blue | `$60` (96) | 5 — Light Blue | 6 |
| 5 | Purple | `$68` (104) | 13 — Magenta | 4 |
| 6 | **Wild** (prism) | `$70` (112) | 15 — White | 1 |

Background is **black** everywhere: TMS9918 color-table low nibble = `1`,
backdrop register = `1`; VIC-20 `$900F` background = black; C64 `$D021` = 0.

### 4.4 Glyph slots (offset within a color group)

| Slot | Glyph | Role |
|---|---|---|
| +0 | **Potion** | Plain tile. No effect. |
| +1 | **Fireball** | Color bomb |
| +2 | **Bolt** | Row + column cross |
| +3 | **Bomb** | 3 × 3 blast |
| +4 | **Star** | Score doubler |
| +5 | *reserved* | (future special) |
| +6 | **Glow** | Match-flash frame of the potion glyph |
| +7 | *reserved* | (future / second flash frame) |

Slot +6 exists because the TMS9918 cannot recolor a single cell. On the
Commodores you *could* flash by poking color RAM, but the game uses the glow
glyph on all three platforms so the animation is byte-for-byte identical
everywhere.

### 4.5 Coloring a tile, per platform

- **AC6502.** Nothing to do. The tile index selects its pattern group, and the
  group's color-table byte was written once at init. Rendering is a single VRAM
  byte write per cell.
- **VIC-20 / C64.** Two writes per cell: `SCREEN,x = tile` and
  `COLRAM,x = TileColor[tile]`. `TileColor` is a 256-byte ROM table — trivial
  in a 16 K cart, and it removes all branching from the render loop.

### 4.6 The fireball's free trick

On the AC6502, flashing *every red tile on the board* white is **one byte
written to the color table** (group 0's foreground nibble). The fireball
detonation animation costs a single VRAM write and its undo costs another.
On the Commodores the same effect is a walk over the dirty list poking color
RAM. Design the animation around this: it looks expensive and costs nothing.

---

## 5. Pieces

### 5.1 Shape

Every piece is a **1 × 3 vertical stack** of three independently-generated
cells, referred to top → bottom as `A`, `B`, `C`.

### 5.2 Generation

For each new piece:

1. Roll a color for each of `A`, `B`, `C` independently, uniform over 0–5.
   All-same-color pieces are allowed (they self-clear — a small gift).
2. Roll once for **"this piece carries a reagent"** against `P_special[band]`.
3. If yes: pick one of the three cells uniformly, then pick the reagent type
   from the weighted table. Set that cell's glyph.

**At most one reagent per piece.** Rolling once per piece rather than once per
cell both enforces the cap and is cheaper.

If the chosen reagent is a **Prism**, the cell's color is overwritten with
color 6 (wild), discarding its rolled color.

### 5.3 Reagent probability by level band

`P_special` is the chance the *piece* contains a reagent. Rolls are against a
random byte 0–255.

| Level band | P_special | /256 | Fireball | Bolt | Bomb | Star | Prism |
|---|---|---|---|---|---|---|---|
| 1–3 | 15 % | 38 | 30 % | 24 % | 22 % | 16 % | 8 % |
| 4–6 | 22 % | 56 | 30 % | 25 % | 20 % | 18 % | 7 % |
| 7–9 | 27 % | 69 | 32 % | 25 % | 20 % | 16 % | 7 % |
| 10–12 | 32 % | 82 | 31 % | 24 % | 21 % | 17 % | 7 % |
| 13+ | 36 % | 92 | 31 % | 25 % | 22 % | 16 % | 6 % |

Implement the type roll as a 256-entry byte table indexed by a random byte
(one table per band, 5 × 256 = 1280 bytes) **or** as a small cumulative-weight
compare chain. The compare chain is ~20 bytes of code and is the recommended
version; the table is there if the chain shows up in profiling.

### 5.4 Spawn

- Spawn column: **2** (0-indexed, left of center).
- The piece occupies board rows 0, 1, 2 in that column, `A` at row 0.
- **Game over** if any of those three cells is non-empty at spawn time.
- The piece is drawn immediately; there is no off-screen entry.

### 5.5 Movement

| Action | Rule |
|---|---|
| **Left / Right** | Move one column if all three target cells are empty and the column is in range 0–5. Otherwise ignored (no wall kick, nothing to kick). |
| **Rotate (Up)** | Cycle contents upward: `(A,B,C) → (B,C,A)`. Always succeeds — the footprint never changes. |
| **Rotate (Fire)** *(optional)* | Cycle downward: `(A,B,C) → (C,A,B)`. |
| **Soft drop (Down)** | Fall at the soft-drop rate. Never slower than gravity: if gravity is already faster, gravity wins. Awards 1 point per row. |
| **Gravity** | The piece descends one row every `Speed[level]` frames. |

### 5.6 Locking

When the cell below `C` is non-empty (or `C` is at row 15), the **lock delay**
starts:

- Lock delay: **16 frames NTSC / 14 frames PAL**.
- A successful left/right move **resets** the lock delay, up to **4 times** per
  piece. After the fourth reset the delay runs out regardless.
- Rotation does **not** reset the lock delay.
- If the piece moves into a column where it can fall further, it resumes
  falling and the lock counter clears (the reset count does not).
- On lock: the three cells are written into `BOARD`, the piece is retired, and
  [cascade resolution](#8-cascade-resolution) begins.
- After the cascade fully resolves, an **entry delay (ARE)** of
  **12 frames NTSC / 10 PAL** runs, then the next piece spawns and the preview
  refills.

---

## 6. Matching

### 6.1 The rule

**Three or more consecutive cells of the same color in a straight line**, in any
of four orientations:

```
horizontal  ─      vertical  │      diagonal  ╲      anti-diagonal  ╱
```

Longer runs are a single run, not multiple overlapping threes: `R R R R` is one
run of 4, worth more than a run of 3, and is *not* also counted as two 3-runs.

A cell may belong to several runs at once (a horizontal and a vertical
simultaneously) — it clears once, but every run it completes scores.

### 6.2 Scan procedure

Scan the full board once per cascade step, in four passes. Each pass walks its
axis, tracking `run_color` and `run_length`:

1. **Horizontal** — 16 rows × 6, left to right.
2. **Vertical** — 6 columns × 16, top to bottom.
3. **Diagonal ╲** — every start cell in row 0 and column 0.
4. **Anti-diagonal ╱** — every start cell in row 0 and column 5.

When a run reaches length ≥ 3 and then breaks (or hits a sentinel), set the
`MARK` bit for each of its cells in the `MARKS` bitmap and record the run's
length and color for scoring.

`MARKS` is a **16 × 1-byte** bitmap (one byte per row, bits 0–5 = columns 0–5),
so union-of-runs is a free `ORA`. 16 bytes total.

### 6.3 Wildcards in a run

The Prism matches any color. The scanner handles this with one extra rule:

- A `WILD` cell **continues** the current run regardless of `run_color`.
- If the run has no color yet (it started on a `WILD`), `run_color` stays
  unset and is adopted from the first non-wild cell encountered.
- A run of **only** wilds (3+ prisms in a line) is a valid match. It clears and
  pays the prism bonus, but has no color and triggers no color-scoped effects.
- Because color is adopted lazily, a single prism can legitimately close a red
  horizontal run *and* a blue vertical run in the same scan. This is intended
  and is the whole reason the prism exists.

---

## 7. Specials

### 7.1 How many, and why five

**Five reagents: four colored, one colorless.** That number is not arbitrary:

- Each occupies one glyph slot in a color group, and a group holds 8. Four
  colored reagents + the plain potion + the glow frame = 6 of 8, leaving two
  slots for later without ever reflowing the tileset.
- Each covers a *distinct* failure mode of a Columns board. There is no
  redundancy to prune.
- Five icons is about the ceiling for what a player can learn from a single
  legend screen at 8 × 8 pixels.

| | Scope | Solves |
|---|---|---|
| **Fireball** | Board-wide, color-scoped | "I have too much red and it's scattered everywhere" |
| **Bolt** | Line, position-scoped | "There's junk buried at the bottom of column 4" |
| **Bomb** | Area, position-scoped | "This corner is a mess" |
| **Star** | None — scoring | "I want a reason to hold a cascade back one more piece" |
| **Prism** | Rule-bending | "I need one more green and green isn't coming" |

### 7.2 Common rules

- A reagent **matches as its color**, exactly like a potion. Its effect fires
  when — and only when — its cell is *removed*.
- A reagent removed by **another reagent's effect** also fires. Chain reactions
  are the point.
- **Termination is guaranteed.** Effects only ever remove tiles, never add
  them, and each cell can be marked at most once. The effect queue therefore
  drains in at most 96 steps.
- Removing a reagent by any means always awards its **trigger bonus**, whether
  it was matched or blown up.
- A reagent sitting on the board that is *never* removed does nothing. It is
  just a differently-drawn potion of its color.

### 7.3 The five

---

#### 🔥 Fireball — *glyph slot +1*

> **On removal: every remaining tile of the fireball's color is destroyed.**

The signature reagent. A red fireball clears every red tile on the board — and
any reagent among them fires too, which is how three-deep chain reactions
happen.

- The effect fires **once per detonation**, but each fireball detonates
  separately. Two red fireballs in one run: the first clears all red, the second
  finds nothing left to clear but still pays its trigger bonus.
- Fireballs of **different** colors in the same clear step each fire their own
  color, in queue order.
- A fireball whose color is `WILD` cannot exist (prisms overwrite the glyph).

*Design note on the original framing:* the initial idea was "match 3 fireballs
to explode a color." Under color-matching, a fireball is simply *reachable* —
you match it with two ordinary potions of the same color, which happens
naturally. The three-of-a-kind version would make fireballs so rare that most
players would never see one detonate. The current rule keeps the fantasy
(fireball = color wipe) and makes it happen several times per game. Three
fireballs in one run still works — it just isn't the entry price.

---

#### ⚡ Bolt — *glyph slot +2*

> **On removal: the entire row and the entire column through the bolt's cell
> are destroyed.**

Up to 6 + 16 − 1 = **21 cells**. This is the excavator: the only reagent that
reliably reaches a tile buried at the bottom of a deep column, and the only one
whose value depends on *where* you drop it rather than what color it is.

Two bolts in the same run produce two crosses.

---

#### 💣 Bomb — *glyph slot +3*

> **On removal: the 3 × 3 block centered on the bomb is destroyed** (clipped at
> the board edges).

Up to **9 cells**. Where the bolt is precise and long, the bomb is local and
dense — it is the reagent that clears a *tangle*, and the one most likely to
catch another reagent in its blast because it hits neighbors in every direction.

---

#### ⭐ Star — *glyph slot +4*

> **On removal: the entire cascade's score is doubled.**

Removes nothing. Costs no queue processing. Sets a flag.

- Each star in a cascade doubles again: 1 star = ×2, 2 = ×4, 3 = ×8.
- **Capped at ×8.**
- The multiplier applies to the *whole* cascade total at the end, including
  points scored before the star cleared, and including effect points.

Cheap to implement (a shift count and, at the end, up to three BCD
self-additions) and it creates the game's most interesting decision: you can see
a star on the board and choose to build a bigger chain around it before setting
it off.

---

#### 🔮 Prism — *glyph slot +0 of color 6 (wild)*

> **Matches any color.** No removal effect.

The rarest reagent (~6–8 % of reagents, so roughly 1 piece in 90 at level 1).
It is drawn in white and reads instantly as "not a potion."

- Fills a hole in any run, in any of the four directions, simultaneously.
- Clears with the run it completes.
- Awards a flat bonus per prism cleared.
- Because a prism has no color, it is **immune to fireballs** — it can only be
  removed by matching, a bolt, or a bomb. This is a small, learnable wrinkle
  that rewards attention.

---

### 7.4 Interaction summary

| Removed by → | Match | Fireball | Bolt | Bomb |
|---|---|---|---|---|
| Potion | ✔ | ✔ (same color) | ✔ | ✔ |
| Fireball | ✔ fires | ✔ fires | ✔ fires | ✔ fires |
| Bolt | ✔ fires | ✔ fires | ✔ fires | ✔ fires |
| Bomb | ✔ fires | ✔ fires | ✔ fires | ✔ fires |
| Star | ✔ doubles | ✔ doubles | ✔ doubles | ✔ doubles |
| Prism | ✔ bonus | ✖ **immune** | ✔ bonus | ✔ bonus |

---

## 8. Cascade Resolution

A **cascade** runs from the moment a piece locks until no further matches
exist. A **step** is one iteration inside it. `chain` counts steps, starting at
1.

```
LOCK PIECE
chain        := 1
cascade_pts  := 0
star_count   := 0

STEP:
  1. SCAN         Run the four match passes. Fill MARKS. Record each run's
                  (length, color).
                  If no runs found → goto SETTLE.

  2. SCORE MATCH  For each run:  cascade_pts += length * TileValue[chain]
                                 cascade_pts += LengthBonus[length]
                  cascade_pts += MultiBonus[number_of_runs]

  3. ENQUEUE      Walk MARKS. For each marked cell containing a reagent,
                  push (glyph, row, col, color) onto EFFECTQ.
                  Stars are counted here, not queued.

  4. RESOLVE      While EFFECTQ is not empty:
                    pop an effect, compute its target cells
                    for each target not already marked:
                        set its MARK bit
                        cascade_pts += EffectValue[chain]
                        if it holds a reagent → push it onto EFFECTQ
                        if it holds a star    → star_count += 1
                    cascade_pts += TriggerBonus[glyph]
                  (Terminates: cells are only ever added to MARKS, max 96.)

  5. ANIMATE      Glow phase, then shatter phase. See §14.

  6. REMOVE       Zero every marked cell. tiles_cleared += popcount(MARKS)
                  Clear MARKS.

  7. LEVEL        If tiles_cleared >= 30:
                      tiles_cleared -= 30 ; level += 1  (at most one per step)

  8. GRAVITY      Compact every column downward. Animate at 1 row / 2 frames.

  9. chain += 1 ; goto STEP

SETTLE:
  cascade_pts <<= min(star_count, 3)      ; ×2 / ×4 / ×8
  score += cascade_pts                     ; BCD, clamp at 999999
  if chain-1 >= 2 → show chain banner in the message band
  ARE delay, then spawn.
```

`EFFECTQ` is a 96-entry ring of 2 bytes each (packed `glyph|row|col`) — 192
bytes worst case, but a 32-entry (64-byte) queue is sufficient in practice
because reagent density is bounded; on overflow, drop the effect and continue.
**Recommend 48 entries (96 bytes)** with a documented drop-on-overflow.

---

## 9. Scoring

Score is **6-digit BCD**, stored in 3 bytes, displayed zero-padded. All values
are multiples of 10, so every addition is a `SED` / `ADC` chain. Score
**clamps** at `999999` — it never wraps.

### 9.1 Per-tile value by chain depth

`TileValue[chain]` — awarded per tile removed **by a match**.

| Chain | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8+ |
|---|---|---|---|---|---|---|---|---|
| Value | 20 | 50 | 100 | 200 | 300 | 400 | 500 | 600 |

### 9.2 Per-tile value for effect removals

`EffectValue[chain]` — awarded per tile removed **by a reagent's effect**.
Deliberately higher than `TileValue` at low chain depth: reagents should feel
better than plain play from the very first one.

| Chain | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8+ |
|---|---|---|---|---|---|---|---|---|
| Value | 30 | 60 | 120 | 240 | 350 | 450 | 550 | 650 |

### 9.3 Run length bonus

`LengthBonus[length]` — per run, once.

| Length | 3 | 4 | 5 | 6 | 7+ |
|---|---|---|---|---|---|
| Bonus | 0 | 100 | 300 | 600 | 1000 |

### 9.4 Simultaneous run bonus

`MultiBonus[runs]` — for resolving several runs in the same step.

| Runs in step | 1 | 2 | 3 | 4 | 5+ |
|---|---|---|---|---|---|
| Bonus | 0 | 200 | 500 | 1000 | 2000 |

### 9.5 Reagent trigger bonuses

Awarded once per detonation, regardless of how the reagent was removed.

| Reagent | Bonus |
|---|---|
| Fireball | 500 |
| Bolt | 300 |
| Bomb | 300 |
| Prism (per prism cleared) | 400 |
| Star | — (multiplies instead) |

### 9.6 Multipliers and misc

| Event | Award |
|---|---|
| Star in cascade | Cascade total × 2 per star, **cap ×8** |
| Soft drop | 1 point per row descended under soft drop |
| Level advance | +1000 |
| Game over | no bonus |

### 9.7 Worked examples

**A. Plain three-in-a-row, first step of a cascade.**
3 tiles × `TileValue[1]` (20) = 60. `LengthBonus[3]` = 0. One run → 0.
**Total: 60.**

**B. A red fireball inside a run of 4, at chain 2, blowing up 8 more reds.**
```
match:    4 × TileValue[2]=50            = 200
          LengthBonus[4]                 = 100
          MultiBonus[1]                  =   0
fireball: TriggerBonus                   = 500
          8 × EffectValue[2]=60          = 480
                                          ————
                                           1280
```

**C. Same as B, but a star was caught in the blast and the cascade continues
one more step for another 400.**
```
(1280 + 400) × 2 = 3360
```

**D. Two bolts and a bomb chained at depth 4.** Roughly 21 + 21 + 9 tiles at
`EffectValue[4]` = 240 → ~12,240 plus 1100 in trigger bonuses. This is the
"once a game if you're good" moment and it should be worth ~1.5 % of the
6-digit ceiling. It is.

### 9.8 High score

- One entry, no name, **not persisted** — reset on every power-on.
- Initial value: `010000`.
- Updated live during play the instant `score` exceeds it, so the player
  watches themselves overtake it.
- Beating it triggers a one-shot fanfare and a flash of the HIGH field.

---

## 10. Levels & Speed

### 10.1 Advancement

- Level starts at **1**.
- Every **30 tiles removed** (match *and* effect removals both count) advances
  one level. Surplus carries over.
- **At most one level advance per cascade step**, so a big fireball chain can
  never skip a level.
- Level is displayed as 2 digits, capped at 99.
- **Speed caps at level 16.** Levels 17+ display and score normally but fall at
  level 16's rate.

### 10.2 Gravity table

Speed is expressed in **frames per row of 8 × 8 tile movement**. The PAL column
is `round(NTSC × 50/60)`, so wall-clock speed matches across regions.

| Level | NTSC frames/row | NTSC sec/row | PAL frames/row | PAL sec/row |
|---:|---:|---:|---:|---:|
| 1 | 48 | 0.800 | 40 | 0.800 |
| 2 | 43 | 0.717 | 36 | 0.720 |
| 3 | 38 | 0.633 | 32 | 0.640 |
| 4 | 34 | 0.567 | 28 | 0.560 |
| 5 | 30 | 0.500 | 25 | 0.500 |
| 6 | 26 | 0.433 | 22 | 0.440 |
| 7 | 23 | 0.383 | 19 | 0.380 |
| 8 | 20 | 0.333 | 17 | 0.340 |
| 9 | 17 | 0.283 | 14 | 0.280 |
| 10 | 15 | 0.250 | 13 | 0.260 |
| 11 | 13 | 0.217 | 11 | 0.220 |
| 12 | 11 | 0.183 | 9 | 0.180 |
| 13 | 9 | 0.150 | 8 | 0.160 |
| 14 | 8 | 0.133 | 7 | 0.140 |
| 15 | 7 | 0.117 | 6 | 0.120 |
| 16+ | 6 | 0.100 | 5 | 0.100 |

The ramp is roughly −11 % per level. At level 1 a piece takes 12.8 s to fall
the full 16 rows; at level 16 it takes 1.6 s.

### 10.3 Pacing sanity check

At level 1, a piece lands roughly every 6–8 s including player input. Clearing
30 tiles takes maybe 10–14 pieces. Expect level 5 at ~3 minutes, level 10 at
~6 minutes, level 16 at ~10 minutes for an average player — with reagents
accelerating the back half considerably. Ship it, then tune the 30-tile
threshold, which is the single knob that changes overall session length.

---

## 11. Input

### 11.1 Abstract input byte

All platforms funnel into one routine returning a bitmask in `A`, **active
high** (each platform inverts as needed):

```
   bit   7   6   5   4   3   2   1   0
         -   -   P   F   R   L   D   U

   bit 0  UP      rotate forward
   bit 1  DOWN    soft drop
   bit 2  LEFT
   bit 3  RIGHT
   bit 4  FIRE    rotate reverse in play; confirm in menus
   bit 5  PAUSE
   bits 6-7 unused
```

The game logic never knows whether a bit came from a stick or a key. Edge
detection (`new = current AND NOT previous`) happens once, centrally.

### 11.2 Required controls

| Action | Joystick | Keyboard |
|---|---|---|
| Rotate | Up | `W`, Cursor-Up, or `SPACE` |
| Soft drop | Down | `S` or Cursor-Down |
| Move left | Left | `A` or Cursor-Left |
| Move right | Right | `D` or Cursor-Right |
| Rotate reverse *(optional)* | Fire | `Q` |
| Pause | — | `P` |
| Start / confirm | Fire | `SPACE` or `RETURN` |

Cursor keys on the Commodores are shifted pairs; read the raw matrix rather
than the KERNAL so both directions of each key work unshifted.

### 11.3 Auto-repeat (DAS)

Applies to LEFT and RIGHT only.

| | NTSC | PAL |
|---|---|---|
| Initial delay | 12 frames | 10 frames |
| Repeat rate | 4 frames | 3 frames |

**Rotate does not auto-repeat.** UP must be released and re-pressed. This is
non-negotiable — auto-repeating rotate makes a Columns piece unusable.

**Soft drop** does not use DAS; it substitutes its own fall rate:
**3 frames/row NTSC, 2 frames/row PAL**, and is ignored when gravity is
already faster (levels 14+ NTSC).

### 11.4 Platform reads

- **AC6502.** `ReadJoystick1` (`$A048`, VIA Port B) and `ReadJoystick2`
  (`$A04B`, Port A). Both are **active low**: `%RLDUYXBA` — bit 7 R, 6 L,
  5 D, 4 U, 3 Y, 2 X, 1 B, 0 A. An untouched stick reads `$FF`. Check
  `HW_GPIO` in `HW_PRESENT` before trusting the value. Keyboard arrives through
  the same VIA (CB1/CA1 IRQ, ring buffer at `$0200`); poll with `Chrin`
  (`$A003`, non-blocking) for menu text and use the raw port for in-game keys.
- **VIC-20.** Joystick is split: up/down/left/fire on VIA1 `$9111` bits 2–5,
  **right on VIA2 `$9120` bit 7** — and reading right requires briefly setting
  `$9122` DDR. Do the DDR dance once per frame, not per read. Keyboard: scan
  the matrix directly via `$9120`/`$9121`.
- **C64.** Joystick port 2 at `$DC00`, active low, bits 0–4 = up/down/left/
  right/fire. Port 1 (`$DC01`) shares the keyboard matrix; support port 2 only
  and read the keyboard normally. Disable the KERNAL IRQ keyboard scanner and
  scan directly.

---

## 12. Screen Layout

### 12.1 The core panel

**One 22 × 23 panel is defined once and rendered identically on all three
machines.** The VIC-20 is exactly this panel; the other two center it and fill
the margins with static artwork.

```
      0         1         2
      0123456789012345678901
  0  |·······WIZARDS LAB·······|   ornament rule + title
  1  |                         |   spacer
  2  |╔══════╗                 |   well top border
  3  |║······║      SCORE      |
  4  |║······║      001250     |   ← well interior rows 3-18 = board rows 0-15
  5  |║······║                 |
  6  |║······║      HIGH       |
  7  |║······║      010000     |
  8  |║······║                 |
  9  |║······║      LEVEL      |
 10  |║······║      03         |
 11  |║······║                 |
 12  |║······║      NEXT       |
 13  |║······║       ┌─┐       |
 14  |║······║       │▓│       |   ← next piece cell A
 15  |║······║       │▓│       |   ← next piece cell B
 16  |║······║       │▓│       |   ← next piece cell C
 17  |║······║       └─┘       |
 18  |║······║                 |
 19  |╚══════╝    (vignette)   |   well bottom border
 20  |                         |   spacer
 21  |      CHAIN  x4          |   message band, row 1
 22  |                         |   message band, row 2
```

*(The box-drawing above is illustrative — the real frame uses custom tiles from
[Appendix A](#appendix-a--master-tile-map): stone shelf edges and vial racks,
not ASCII lines.)*

### 12.2 Exact regions (panel-relative coordinates)

| Region | Cols | Rows | Notes |
|---|---|---|---|
| Title rule | 0–21 | 0 | "WIZARDS LAB" centered at cols 5–15 |
| Spacer | 0–21 | 1 | |
| Well frame — top | 0–7 | 2 | |
| Well frame — left wall | 0 | 3–18 | |
| **Well interior** | **1–6** | **3–18** | **board (0,0) is at panel (1,3)** |
| Well frame — right wall | 7 | 3–18 | |
| Well frame — bottom | 0–7 | 19 | |
| Panel gutter | 8 | 2–19 | always blank |
| SCORE label | 9–13 | 3 | |
| SCORE digits | 9–14 | 4 | 6 digits |
| HIGH label | 9–12 | 6 | |
| HIGH digits | 9–14 | 7 | 6 digits |
| LEVEL label | 9–13 | 9 | |
| LEVEL digits | 9–10 | 10 | 2 digits |
| NEXT label | 9–12 | 12 | |
| NEXT frame | 10–12 | 13–17 | 3 × 5 box |
| **NEXT tiles** | **11** | **14, 15, 16** | A, B, C top to bottom |
| Vignette (optional decor) | 9–21 | 18–19 | cauldron / wizard, 13 × 2 |
| Spacer | 0–21 | 20 | |
| Message band | 0–21 | 21–22 | 2 rows, centered text |

### 12.3 Board ↔ screen address

```
panel_col = board_col + 1
panel_row = board_row + 3

screen_col = PANEL_X + panel_col
screen_row = PANEL_Y + panel_row
```

Precompute a **row-start pointer table** per platform (one lo byte + one hi
byte per screen row) so a cell write is `LDA (rowptr),Y`-shaped with `Y` =
column. This is the same code on all three machines; only the table differs.

### 12.4 Per-platform placement

| Platform | Grid | `PANEL_X` | `PANEL_Y` | Margin to fill |
|---|---|---|---|---|
| **VIC-20** | 22 × 23 | 0 | 0 | none — exact fit |
| **AC6502** | 32 × 24 | 5 | 0 | cols 0–4 and 27–31 (5 × 24 each), row 23 full width |
| **C64** | 40 × 25 | 9 | 1 | cols 0–8 and 31–39 (9 × 25 each), rows 0 and 24 full width |

Both offsets are exact centerings: `(32−22)/2 = 5`, `(40−22)/2 = 9`,
`(25−23)/2 = 1`.

### 12.5 Margin artwork

The margins are **static** — drawn once on entering the PLAY state, never
touched again. Budget:

- **AC6502:** 2 × 120 = 240 cells + 32 = **272 cells**. A 5-column laboratory
  shelf on each side: stacked bottles, a rack, a candle. Row 23 is a stone
  floor strip.
- **C64:** 2 × 225 = 450 cells + 80 = **530 cells**. Nine columns is enough for
  a proper vertical scene — a wizard at a workbench on the left, a shelf of
  labelled jars and a bubbling cauldron on the right, a beamed ceiling on row 0
  and a flagstone floor on row 24.

Because margins never redraw, they cost only tiles, not cycles. Use the
artwork tile budget generously ([Appendix A](#appendix-a--master-tile-map)
reserves 128 tiles for it).

### 12.6 Rendering strategy

**Never redraw the full screen during play.** All three platforms use a
**dirty-cell list**:

- The well interior is 96 cells. A worst-case cascade step touches all of them.
- Maintain `DIRTY`, a list of `(offset, tile)` pairs flushed once per frame
  during vertical blank.
- Cap the flush at **48 cells per frame** and carry the remainder to the next
  frame. This matters most on the AC6502, where each VRAM write is a port
  write with a minimum inter-write spacing (~29 cycles on a real TMS9918A);
  48 writes is comfortably inside a 60 Hz frame at 1 MHz.
- The score/level/next fields are dirty-flagged separately and only pushed when
  their values change.

---

## 13. Game States & Flow

```
        ┌──────────┐
        │  TITLE   │◄─────────────────┐
        └────┬─────┘                  │
             │ FIRE / SPACE           │
             ▼                        │
        ┌──────────┐   P         ┌────┴─────┐
        │   PLAY   │◄───────────►│  PAUSE   │
        └────┬─────┘             └──────────┘
             │ spawn blocked
             ▼
        ┌──────────┐
        │ GAMEOVER │──── FIRE / 10 s timeout ──┘
        └──────────┘
```

### 13.1 TITLE

- Large "WIZARDS LAB" logo built from artwork tiles.
- "PRESS FIRE" / "PRESS SPACE" blinking at 30-frame intervals.
- **Auto-cycling help pages**, one every 240 frames (4 s), looping:
  1. **CONTROLS** — the four directions with arrow glyphs.
  2. **REAGENTS** — the five specials, each icon shown in a sample color with a
     one-line description. This is the only place the rules are taught, so it
     gets the most room.
  3. **SCORING** — run values, chain multiplier, star.
  4. **HIGH SCORE** — current session best.
- Any direction press skips to the next page; FIRE starts the game.
- The RNG is seeded from the frame counter at the moment FIRE is pressed
  ([§15](#15-randomness)).

### 13.2 PLAY

The main loop. Frame order:

```
wait for vblank
  → flush DIRTY (capped)
  → read input, edge-detect
  → advance state machine (falling / locking / animating / gravity / ARE)
  → update audio
  → tick frame counter
```

### 13.3 PAUSE

- `P` toggles. Fire also resumes.
- The well interior is **blanked** (all 96 cells drawn empty) so pausing cannot
  be used to study the board. Panel and margins stay.
- "PAUSED" flashes in the message band.
- All timers freeze; the frame counter keeps running (it feeds the RNG).

### 13.4 GAMEOVER

1. The current piece stops.
2. **Petrify animation**: rows fill with the grey stone tile from row 15 upward,
   2 frames per row (32 frames total).
3. "GAME OVER" in the message band; final score stays in the SCORE field.
4. If a new high score was set, HIGH flashes and a fanfare plays.
5. FIRE or a 10-second timeout returns to TITLE.

---

## 14. Animation & Timing

All durations in frames. PAL values are `round(NTSC × 50/60)` where the
difference matters; where it doesn't, the same count is used on both.

| Event | NTSC | PAL | Detail |
|---|---|---|---|
| Match glow | 6 | 5 | Matched cells swap to glyph +6 (glow) of their own color |
| Shatter | 6 | 5 | Matched cells swap to the shared white shatter tile |
| Fireball flash | 8 | 7 | Every tile of the target color turns white, then shatters |
| Bolt beam | 6 | 5 | White beam tiles drawn along the row and column |
| Bomb blast | 6 | 5 | White blast tile drawn over the 3 × 3 |
| Gravity fall | 2/row | 2/row | Tiles descend one row every 2 frames |
| Lock delay | 16 | 14 | Resets on horizontal move, max 4 resets |
| Entry delay (ARE) | 12 | 10 | After a cascade fully settles |
| Level-up banner | 45 | 38 | "LEVEL 04" in the message band; play continues |
| Chain banner | 45 | 38 | "CHAIN ×3" for chain ≥ 2 |
| Petrify (game over) | 2/row | 2/row | 16 rows = 32 frames |
| Title page cycle | 240 | 200 | 4 seconds |
| Blink period | 30 | 25 | "PRESS FIRE", high-score flash |

A single clear step therefore costs **12 frames of animation plus gravity**
(0–32 frames). A deep chain reads as a satisfying half-second per link rather
than an instant score jump.

**Fireball flash implementation note:** on the AC6502 this is one byte written
to the VDP color table (set the target group's foreground nibble to 15, then
restore it). On the Commodores, walk the dirty list poking `$01` into color
RAM. Same visual, different mechanism, identical frame count.

---

## 15. Randomness

- **16-bit LFSR**, taps at bits 0 and 1 of the low byte XORed with bits 3 and 5
  — any well-known maximal-length 16-bit polynomial is fine; `$B400` taps are
  the conventional 6502 choice.
- **Seeding:** a free-running frame counter increments every vblank from
  power-on. When the player presses FIRE on the title screen, `seed = counter`
  (and `seed |= 1` to avoid the zero lock-up). Human reaction time supplies the
  entropy.
- **Never** seed from a fixed constant — the first three pieces would be
  identical every session and the game would feel dead.
- One `NextRandom` routine, one byte at a time. Piece generation needs 4 bytes
  per piece (3 colors + 1 reagent roll), sometimes 6.
- **No bag system.** Uniform independent colors. Columns is a game about coping
  with unfairness; a shuffle bag would flatten it.

---

## 16. Audio

Out of scope for v1 gameplay, but reserve the hooks. Sound is triggered by a
one-byte `SFX_REQUEST` written by game logic and consumed by the audio tick.

| ID | Event | Character |
|---|---|---|
| 1 | Move left/right | short blip |
| 2 | Rotate | rising two-step |
| 3 | Lock | dull thunk |
| 4 | Match (chain 1) | bright chime; pitch rises with `chain` |
| 5 | Fireball | descending noise sweep |
| 6 | Bolt | fast noise crack |
| 7 | Bomb | low noise thump |
| 8 | Star | sparkle arpeggio |
| 9 | Prism | shimmer |
| 10 | Level up | fanfare |
| 11 | New high score | longer fanfare |
| 12 | Game over | descending minor run |

AC6502 and C64 share SID driver code almost verbatim (register base differs:
`$9800` vs `$D400`). The VIC-20 needs its own three-oscillator driver against
`$900A-$900E`.

---

## 17. Memory Budget

### 17.1 RAM (identical logical layout on all platforms)

| Structure | Bytes | Notes |
|---|---|---|
| `BOARD` | 160 | 20 rows × 8 stride, page-aligned |
| `MARKS` | 16 | 1 byte per row, bits 0–5 |
| `EFFECTQ` | 96 | 48 entries × 2 bytes |
| `DIRTY` | 192 | 64 entries × 3 bytes (offset lo/hi, tile) |
| Piece state | 8 | column, row, A/B/C, rotation |
| Next piece | 3 | |
| Score / High | 6 | 3 bytes BCD each |
| Level, tiles cleared, chain, stars | 6 | |
| Timers (gravity, lock, DAS, ARE, anim) | 10 | |
| Input current/previous/edge | 3 | |
| RNG seed, frame counter | 4 | |
| State machine, flags | 8 | |
| Audio state | 16 | |
| **Total** | **~530 bytes** | plus row-pointer tables in ROM |

Fits the VIC-20's constrained RAM with room to spare, which is the whole point
of designing to the tightest target first.

### 17.2 ROM (16 KB cartridge)

| Contents | Estimate |
|---|---|
| Tileset (256 × 8 bytes) | 2048 |
| Game logic (board, match, cascade, scoring) | ~3000 |
| Render + platform HAL | ~1500 |
| Title / help / game-over screens + text | ~1500 |
| Margin artwork layouts (RLE-compressed) | ~800 |
| Audio driver + data | ~1500 |
| Tables (speed, scoring, color, row pointers) | ~800 |
| **Subtotal** | **~11,150** |
| **Headroom** | **~5,200** |

Comfortable. The margin artwork layouts should be run-length encoded — they are
mostly repeated stone and shelf tiles, and RLE typically gets 530 C64 cells
down to under 150 bytes.

---

## Appendix A — Master Tile Map

**One 256-tile set, identical indices on all three platforms.** The layout obeys
the TMS9918's 8-pattern color groups, which costs the Commodores nothing (they
have tiles to spare) and buys a completely shared renderer.

| Group | Tiles | Color (TMS fg / CBM) | Contents |
|---:|---|---|---|
| 0 | 0–7 | 15 White / 1 | Blank, bar-H, bar-V, corner-TL, corner-TR, corner-BL, corner-BR, joint |
| 1 | 8–15 | 14 Gray / 15 (C64), 1 (VIC) | Stone/shelf accents, NEXT box frame, rules |
| 2 | 16–23 | 15 White / 1 | Font: `0 1 2 3 4 5 6 7` |
| 3 | 24–31 | 15 White / 1 | Font: `8 9 A B C D E F` |
| 4 | 32–39 | 15 White / 1 | Font: `G H I J K L M N` |
| 5 | 40–47 | 15 White / 1 | Font: `O P Q R S T U V` |
| 6 | 48–55 | 15 White / 1 | Font: `W X Y Z . × ! -` |
| 7 | 56–63 | 15 White / 1 | VFX: shatter1, shatter2, blast, beam-H, beam-V, beam-cross, sparkle, arrow |
| **8** | **64–71** | **8 Med Red / 2** | **Red:** potion, fireball, bolt, bomb, star, —, glow, — |
| **9** | **72–79** | **11 Lt Yellow / 7** | **Yellow:** same 8 slots |
| **10** | **80–87** | **3 Lt Green / 5** | **Green:** same 8 slots |
| **11** | **88–95** | **7 Cyan / 3** | **Cyan:** same 8 slots |
| **12** | **96–103** | **5 Lt Blue / 6** | **Blue:** same 8 slots |
| **13** | **104–111** | **13 Magenta / 4** | **Purple:** same 8 slots |
| 14 | 112–119 | 15 White / 1 | **Prism** (slot +0), prism glow (+6), wild VFX |
| 15 | 120–127 | 14 Gray / 11 (C64), 1 (VIC) | Stone (game-over petrify), rubble, reserved hazards |
| 16–31 | 128–255 | various | **Artwork** — 128 tiles, 16 color groups, for margins and the title logo |

### A.1 Glyph slot recap

Within any color group `G` (base = `64 + G×8` for the six potion colors):

| Offset | Glyph |
|---|---|
| +0 | Potion (vial) |
| +1 | Fireball |
| +2 | Bolt |
| +3 | Bomb |
| +4 | Star |
| +5 | *reserved* |
| +6 | Glow (flash frame) |
| +7 | *reserved* |

### A.2 Art direction

All glyphs are **single-color on transparent/black**, 8 × 8, per the project
constraint. That means silhouette does all the work — there is no shading and
no outline to lean on. Consequences:

- The **potion** is the baseline: a stoppered vial, roughly 5 px wide, filling
  most of the cell so a field of them reads as solid color.
- The four reagents must be distinguishable **from each other at a glance in
  peripheral vision**, because the player is watching the falling piece, not
  the pile. Prioritize gross shape over detail:
  - **Fireball** — round mass with 3 upward flame licks. Only round glyph.
  - **Bolt** — a single thick zigzag corner to corner. Only diagonal glyph.
  - **Bomb** — a filled circle with a fuse. Round like the fireball, so make it
    *smaller and lower* in the cell with an obvious stem.
  - **Star** — 5-point star, hollow center. Only glyph with radial symmetry.
  - **Prism** — a faceted diamond with an internal line. Always white, which
    already sets it apart from every other tile on the board.
- **Glow** is the potion silhouette dilated by one pixel (or fully filled). It
  should read as "brighter," not as a different object.
- Draw the six potions as **six copies of one pattern**. Identical shape, six
  color groups. Only the reagents need to differ from each other.

---

## Appendix B — Constants Summary

```asm
; ---- Board ----
BOARD_W          = 6
BOARD_H          = 16
BOARD_STRIDE     = 8
BOARD_BYTES      = 160          ; 20 rows × 8
SPAWN_COL        = 2
MATCH_MIN        = 3

; ---- Tiles ----
TILE_EMPTY       = $00
TILE_WALL        = $FF
COLOR_BASE       = $40
COLOR_MASK       = $F8
GLYPH_MASK       = $07
WILD_BASE        = $70

GLYPH_POTION     = 0
GLYPH_FIREBALL   = 1
GLYPH_BOLT       = 2
GLYPH_BOMB       = 3
GLYPH_STAR       = 4
GLYPH_GLOW       = 6

NUM_COLORS       = 6

; ---- Panel ----
PANEL_W          = 22
PANEL_H          = 23
WELL_ORIGIN_X    = 1            ; panel-relative
WELL_ORIGIN_Y    = 3
; per-platform:
;   VIC-20   PANEL_X = 0   PANEL_Y = 0
;   AC6502   PANEL_X = 5   PANEL_Y = 0
;   C64      PANEL_X = 9   PANEL_Y = 1

; ---- Levels ----
LEVEL_TILES      = 30           ; tiles cleared per level
LEVEL_SPEED_CAP  = 16
LEVEL_MAX_SHOWN  = 99

SpeedNTSC:  .byte 48,43,38,34,30,26,23,20,17,15,13,11,9,8,7,6
SpeedPAL:   .byte 40,36,32,28,25,22,19,17,14,13,11, 9,8,7,6,5

; ---- Timing (NTSC / PAL) ----
LOCK_DELAY       = 16 / 14
LOCK_RESET_MAX   = 4
ARE_DELAY        = 12 / 10
DAS_INITIAL      = 12 / 10
DAS_REPEAT       =  4 /  3
SOFTDROP_RATE    =  3 /  2
GLOW_FRAMES      =  6 /  5
SHATTER_FRAMES   =  6 /  5
FALL_FRAMES      =  2 /  2
BANNER_FRAMES    = 45 / 38

; ---- Scoring (all BCD) ----
TileValue:    .byte $20,$50,$00,$00,$00,$00,$00,$00   ; see note
              ; 20, 50, 100, 200, 300, 400, 500, 600 — stored as 16-bit BCD
LengthBonus:  ;   len 3..7+ :    0, 100, 300, 600, 1000
MultiBonus:   ;  runs 1..5+ :    0, 200, 500,1000, 2000
EffectValue:  ; chain 1..8+ :   30,  60, 120, 240, 350, 450, 550, 650
BONUS_FIRE    = 500
BONUS_BOLT    = 300
BONUS_BOMB    = 300
BONUS_PRISM   = 400
STAR_CAP      = 3               ; max shifts → ×8
LEVELUP_BONUS = 1000
SCORE_MAX     = $99,$99,$99
HIGH_INIT     = 010000

; ---- Reagent probability, /256 ----
PSpecial:     .byte 38, 56, 69, 82, 92     ; level bands 1-3,4-6,7-9,10-12,13+
```

> Note: `TileValue` and `EffectValue` exceed one byte from chain 3 onward.
> Store them as **16-bit BCD pairs** (2 bytes each, low/high) and add with a
> two-byte `SED`/`ADC` into the 3-byte cascade accumulator.

---

## Appendix C — Platform Build Notes

### C.1 AC6502

- **Cart:** `6502-16K.cfg`. Code lives at `$C000-$FFF9`; the emitted file is
  32 K spanning `$8000-$FFFF` for a 28C256/27C256. Entry is via the RESET
  vector — no loader, no BASIC stub.
- **Boot:** call `KernalInit` (`$A078`) to bring up hardware, then install our
  own IRQ handler. Interrupts are left disabled on return, which is what we
  want.
- **Video:** switch the VDP from the BIOS's text mode into **Graphics Mode I**.
  Suggested VRAM map:

  | VRAM | Size | Contents |
  |---|---|---|
  | `$0000-$07FF` | 2 K | Pattern generator (256 × 8) |
  | `$1400-$16FF` | 768 | Name table (32 × 24) |
  | `$2000-$201F` | 32 | Color table (one byte per 8-pattern group) |
  | `$1B00-$1B7F` | 128 | Sprite attributes — write `$D0` to the first Y to disable all sprites |

  VDP access is `VC_DATA` = `$9C00`, `VC_REG` = `$9C01`. Write low address byte
  then `(high OR $40)` to set up a write; register writes are data byte then
  `(reg# OR $80)`.
- **Timing:** no raster interrupt. Use the VDP status register's vblank flag
  (read `$9C01`) or a VIA timer 1 free-run at the frame rate. The status-flag
  poll is simpler and self-syncing; use it.
- **Backdrop:** register 7 low nibble = 1 (black).

### C.2 VIC-20

- **Cart:** 16 K as **BLK5 (`$A000-$BFFF`, autostart) + BLK3 (`$6000-$7FFF`)**.
  BLK5 carries the autostart header at `$A000`: cold-start vector
  (`$A000-$A001`), NMI/warm vector (`$A002-$A003`), then the five signature
  bytes `41 30 C3 C2 CD` (`"A0CBM"`) at `$A004-$A008`.
  BLK3 rather than BLK1 keeps the KERNAL's RAM probe from doing anything
  surprising with the screen base.
- **RAM (unexpanded, 5 K total):**

  | Range | Size | Use |
  |---|---|---|
  | `$0000-$00FF` | 256 | Zero page — pointers, hot variables |
  | `$0100-$01FF` | 256 | Stack |
  | `$0200-$03FF` | 512 | KERNAL workspace; reclaimable once we stop calling it |
  | `$1000-$13FF` | 1 K | **Game RAM** — `BOARD`, `MARKS`, `EFFECTQ`, state |
  | `$1400-$1BFF` | 2 K | **Character set**, copied from cart ROM at boot |
  | `$1C00-$1DFF` | 512 | `DIRTY` list, audio state, spare |
  | `$1E00-$1FF9` | 506 | Screen matrix (22 × 23) |

  Color RAM is at `$9600` (matches screen at `$1E00`). Set the VIC character
  base register to select `$1400`.
- **Colors:** hi-res text mode gives 8 foreground colors (color RAM bit 3 must
  stay clear). Values 0–7 = black, white, red, cyan, purple, green, blue,
  yellow — exactly the palette this design uses.
- **Timing:** VIC raster register `$9004`. Poll for the frame boundary or hang
  a timer IRQ off VIA2.
- **Region:** detect NTSC vs PAL by reading `$9004` maximum, or check the
  KERNAL's PAL flag before taking over. Select the appropriate timing tables.

### C.3 C64

- **Cart:** 16 K, EXROM and GAME both low → ROML `$8000-$9FFF` + ROMH
  `$A000-$BFFF`. Header at `$8000`: cold vector, warm vector, then `C3 C2 CD
  38 30` (`"CBM80"`).
- **Memory:** VIC bank 0. Screen `$0400`, character set copied to `$2000`
  (2 K). All of `$0800-$1FFF` and `$2800-$7FFF` is free work RAM.
- **Colors:** color RAM `$D800`. Uses the same values 0–7 as the VIC-20 for the
  playfield, and the upper 8 colors for margin artwork only.
- **Timing:** raster IRQ at a fixed line, standard practice. Disable the
  KERNAL IRQ (`$0314` revectored, `$DC0D`/`$D01A` configured) and scan the
  keyboard directly.
- **Sprites:** none. This is a hard project constraint, not an oversight —
  everything is tiles.

---

## Appendix D — Build Order

Moved to **[PLAN.md](PLAN.md)**, which carries the phases, their exit criteria
and their current state. This document stays the authority on the rules; PLAN.md
is the authority on the order they get built in.

Two things from this document shape that order and are worth restating here:

- Steps that set up a platform (cartridge header, video mode, tile format,
  colour model, frame sync) are done per-platform and first, so that when the
  shared game code goes in, anything that breaks is the game.
- The margin artwork is last, because it is the only part that can be trimmed
  if ROM runs short.

---

## Appendix E — Cut List & Stretch Ideas

### If ROM or schedule runs short, cut in this order

1. **Margin artwork** → plain black margins. Costs nothing mechanically.
2. **Bomb** (glyph +3) → its role overlaps most with the bolt. Redistribute its
   probability to bolt and fireball.
3. **Title help pages 3–4** → keep controls and reagents.
4. **Reverse rotate** (fire button) → up-only rotation is playable.
5. **Star** → it is the least mechanical reagent, though also the cheapest to
   implement, so it should survive almost anything.

**Never cut:** the prism (it is what keeps a bad board recoverable) or the
fireball (it is the game's identity).

### Stretch ideas for a v2

- **Slot +5 and +7 are free in every color group** — two more reagents with no
  tileset reflow required. Candidates:
  - **Hourglass** — on removal, halves gravity for 300 frames. A relief valve
    that becomes precious at level 14+.
  - **Skull / cursed vial** — a colorless *hazard* that cannot be matched and
    can only be removed by bolt, bomb, or… nothing else. Appears from level 10.
    High-risk addition: it can make a game unwinnable, so it needs a guaranteed
    removal path before it ships.
- **Two-piece preview** — the NEXT box is 3 × 5; a second one fits in panel rows
  18–19 only if the vignette is dropped.
- **Difficulty select** on the title screen — start at level 1, 5, or 10.
- **Endless vs. timed** modes.
- **Persisted high score** on AC6502 only, via the DS1511Y NVRAM
  (`RtcReadNVRAM` `$A066` / `RtcWriteNVRAM` `$A069`, 256 bytes). Cartridge-clean
  on the other two platforms means no persistence there — which argues for
  leaving it out everywhere, for parity.

---

*End of specification.*
