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
  - [A.3 The groups that do not hold potions](#a3-the-groups-that-do-not-hold-potions)
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
well; it fits the 22 × 24 panel exactly and is a power of two, which matters
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
color 6 (wild), discarding its rolled color. It is generated as glyph +0; once
it is on the board its glyph becomes the frame number of its idle rotation
([§14](#14-animation--timing), [Appendix A.3](#appendix-a--master-tile-map)),
which is why nothing anywhere reads a wild cell's glyph.

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

**An empty cell breaks the run, not the line.** A pass walks its axis to the
sentinel whatever it meets on the way: `. R R R` is a run of three, and a line
that stopped at the first hole would never see below the top of the pile,
which is most of the board.

**The scan may start at the top of the pile** rather than at row 0. Every one
of the four steps moves down at most one row at a time, so a line that reaches
the pile at all must cross the pile's top row; starting each pass there, and
the diagonals' edge-column start cells below it, misses nothing and skips the
empty air above — which on a normal board is most of the work. Measured at
about a third of the cost on a six-row pile ([PLAN.md](PLAN.md) P3).

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
- **In one line it belongs to the run it is already in, not to both.** In
  `R R W B B` the prism finishes the red run; the blue run starts at the first
  `B` and is two long. A prism is a bridge across two axes, not a cell that
  counts twice along one.

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
- It is also the only tile that **animates at rest** (a slow rotation) and the
  only one that **does not shatter** when it clears — it blips out to a point
  ([§14](#14-animation--timing)). Both say the same thing to the player: this
  one is not a potion.

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

  5. ANIMATE      Glow window, then shatter window, on the frame clock — the
                  board is NOT touched until step 6, so every frame of this
                  draws over cells that still hold their own tiles. Marked
                  prisms sit out the glow and blip out instead of shattering.
                  See §14.

  6. REMOVE       Zero every marked cell. tiles_cleared += popcount(MARKS)
                  Clear MARKS.

  7. LEVEL        If tiles_cleared >= 30:
                      tiles_cleared -= 30 ; level += 1  (at most one per step)

  8. GRAVITY      Compact every column downward, ONE ROW AT A TIME: every tile
                  with a hole under it drops into it, then again, until a pass
                  moves nothing. Animate at 1 row / 2 frames.

  9. chain += 1 ; goto STEP

SETTLE:
  cascade_pts <<= min(star_count, 3)      ; ×2 / ×4 / ×8
  score += cascade_pts                     ; BCD, clamp at 9999999
  if chain-1 >= 2 → show chain banner in the message band
  ARE delay, then spawn.
```

`EFFECTQ` is a ring of **48 entries of one byte each**: the board index of a
pending detonation, and nothing else.

An earlier draft of this section budgeted two bytes an entry for a packed
`glyph|row|col`, which turned out to be a copy of something the game already
has. Marked cells are not zeroed until step 6 and the queue is drained in step
4, so a reagent is still sitting on the board when its entry pops and its glyph
and its colour are one `LDA BOARD,X` away — the board byte *is* the tile
([§3.3](#33-cell-values)). Half the RAM for nothing.

Termination bounds the queue at 96 pushes over a whole step, and 48 entries
is far more than reagent density ever reaches: at most one reagent a piece
([§5.2](#52-generation)), a ring that is being drained as it is filled, and
47 usable slots. On overflow the effect is **dropped** and the cascade carries
on — the cell is still marked, still scored and still removed, it simply does
not detonate.

---

## 9. Scoring

Score is **7-digit BCD**, stored in 4 bytes with the top nibble held at zero.
All values are multiples of 10, so every addition is a `SED` / `ADC` chain.
Score **clamps** at `9999999` — it never wraps.

**The score is always drawn as all seven digits, zero padded.** A score of
1250 reads `0001250`, not `1250`. Leading zeros are never blank-suppressed and
the field is never right-aligned into a shorter run of digits, because either
would let the digits shift column as the score grows — and a number that moves
under the eye is unreadable at a glance, which is the only way anyone reads it
during play. The same rule holds for the high score (7 digits) and for the
level the high score was set on (2 digits). See [§12.2](#122-exact-regions-panel-relative-coordinates).

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

**C. Same as B, but the run of four is closed by a prism, and a star was caught
in the blast.**
```
as B — the run is still four long, still red, and the
fireball still finds the same eight               = 1280
prism closing the run: TriggerBonus                =  400
                                                    ————
                                                     1680
star caught in the blast: × 2                        3360
```

*This example used to read "the cascade continues one more step for another
400", which no board can do: a further step is at chain 3 or deeper, and the
cheapest run there pays 3 × 100 = 300 while the next one up pays 4 × 100 +
`LengthBonus[4]` = 500. There is no 400 among them. The one award of exactly
400 available anywhere in a cascade is a prism's, so the example now uses one —
same total, and it exercises the wildcard, the fireball and the star at once.
The star still doubles points scored **before** it cleared, which is the thing
the example exists to show.*

**D. Two bolts and a bomb chained at depth 4.** Roughly 21 + 21 + 9 tiles at
`EffectValue[4]` = 240 → ~12,240 plus 1100 in trigger bonuses. This is the
"once a game if you're good" moment and it should be worth ~1.2 % of the
7-digit ceiling. It is.

### 9.8 High score

- One entry, no name, **not persisted** — reset on every power-on.
- Initial value: `0010000`.
- Seven digits, like the score. Stored as `SCORE_BYTES = 4` packed BCD with the
  top nibble held at zero, so both wrap at 10,000,000.
- **The HIGH box also shows the level the high score was set on**, two digits
  on the row below the number (SPEC 12.2). Copy `Level` into `HighLevel` at the
  same moment the score is copied — while a run is *holding* the high score
  that number tracks the live level, which is the point: it tells you how deep
  you have to get to beat it.
- Updated live during play the instant `score` exceeds it, so the player
  watches themselves overtake it.
- Beating it triggers a one-shot fanfare and a flash of the HIGH field, at the
  30 / 25 frame blink period of [§14](#14-animation--timing). One-shot needs a
  flag of its own: from the overtake onward the score and the high score are
  equal, so "the score reached it" is true on every subsequent award and cannot
  be the trigger. The copy stays live; only the fanfare and the flash are once.

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

Cursor keys on the Commodores are shifted pairs: CRSR-right and CRSR-down
unshifted, CRSR-left and CRSR-up with SHIFT. Read the raw matrix rather than
the KERNAL, and read a SHIFT key alongside them, so all four directions are
reachable — the KERNAL hands back one translated character and loses the
distinction.

**SPACE is `UP`, not `FIRE`.** One key cannot be both rotate-forward and
rotate-reverse, so SPACE folds into the same bit as `W` and cursor-up, and
`RETURN` and `Q` fold into `FIRE`. The two places that ask for a confirm —
the title screen and the game-over screen — therefore accept **either** bit,
which is also why joystick UP starts a game. Nothing in play is ambiguous:
there, `UP` rotates forward and `FIRE` rotates back.

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
already faster.

With the tables in [§10.2](#102-gravity-table) that guard never actually
fires: the fastest gravity ever gets is 6 frames/row on NTSC and 5 on PAL, so
soft drop is quicker at every level including 16. An earlier draft here said
"levels 14+ NTSC", which was arithmetic that never happened. The guard stays
in the code — it is one compare, and it is what keeps soft drop honest if the
speed table is ever pushed further — but nothing today reaches it.

### 11.4 Platform reads

- **AC6502.** `ReadJoystick1` (`$A048`, VIA Port B) and `ReadJoystick2`
  (`$A04B`, Port A). Both are **active low**: `%RLDUYXBA` — bit 7 R, 6 L,
  5 D, 4 U, 3 Y, 2 X, 1 B, 0 A. An untouched stick reads `$FF`. Check
  `HW_GPIO` in `HW_PRESENT` before trusting the value.

  **This machine has no key matrix.** Two encoders sit on the same VIA ports
  and hand over one ASCII byte per keystroke, strobing CB1 (matrix keyboard)
  or CA1 (PS/2). Poll `GPIO_IFR` for those flags and read `GPIO_PORTB` /
  `GPIO_PORTA` — the read takes the byte and clears the flag, and the flag
  raises whether or not the VIA is allowed to assert IRQ, so the cartridge
  never has to clear the CPU's `I` ([D7](PLAN.md)). Read the key **before**
  `ReadJoystick1`, which releases both encoders and would take a pending key
  with them.

  There is no key-up event, so a key here is a **one-frame pulse**, not a held
  bit: rotate, pause and fire behave exactly as on a stick, and left, right
  and soft drop advance once per keystroke and once per encoder auto-repeat.
  DAS never engages from this keyboard because no bit is ever down two frames
  running. WASD, SPACE, RETURN, `Q` and `P` are the whole scheme — the
  encoders define no code for the arrow keys.
- **VIC-20.** Joystick is split: up/down/left/fire on VIA1 `$9111` bits 2–5,
  **right on VIA2 `$9120` bit 7** — which is also the last of the eight
  keyboard row lines.

  That collision does not need resolving. Every key the game reads lives in
  matrix **rows 1–6**; row 0 is the top number row and row 7 the rest of it,
  and the game wants neither. So `$9122` is set **once** to `$7F` and never
  touched again: PB0–PB6 drive the six rows that matter, PB7 stays an input
  for the RIGHT switch, and the two never take turns. That is shorter than
  flipping the DDR twice a frame and also safer — PB7 is never configured as
  an output, so the VIA can never drive it high against a closed RIGHT switch
  pulling it to ground. Set `$9123` to `$00` for the column reads on `$9121`.
- **C64.** Joystick port 2 at `$DC00`, active low, bits 0–4 = up/down/left/
  right/fire. Port 1 (`$DC01`) shares the keyboard matrix; support port 2 only.
  Disable the KERNAL IRQ keyboard scanner and scan directly: `$DC02` = `$FF`
  and `$DC03` = `$00`, then one column low on `$DC00` and the rows read back
  from `$DC01`.

  Port 2 shares CIA1's port A with the keyboard columns and that **is not
  avoidable** — a held direction pulls a column line low and looks to a scan
  like every key in that column being down at once. Every C64 game with both
  has this. Read the joystick first, with `$FF` on `$DC00` so no column is
  selected, and at least the stick is never confused by the keyboard.

---

## 12. Screen Layout

### 12.1 The core panel

**One 22 × 24 panel is defined once and rendered identically on all three
machines.** `PANEL_Y` is **0** everywhere; only `PANEL_X` differs.

Twenty-four rows is not an arbitrary choice. The panel is vertically
symmetric —

```
row  0   shelf
row  1   banner        ~~~WIZARDS LAB🧪~~~
row  2   shelf
rows 3-20  the frames  (18 rows)
row 21   shelf
row 22   banner        ~~~PAUSED~~~
row 23   shelf
```

— and that only closes at an even height. The three machines give us 23, 24
and 25 rows, so **the AC6502's 24 is the one that fits exactly**, and it is
the machine the panel is drawn on. The other two take the rounding:

- **VIC-20 (23 rows)** — panel row 23 falls off the bottom. The message band
  becomes the last row of the screen.
- **C64 (25 rows)** — the panel ends at screen row 23 and row 24 is one spare
  course of margin.

Nothing else moves. Rows 0–22 are identical on all three.

```
      0         1         2
      0123456789012345678901
  0  |▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤|   shelf
  1  |▤▤~~ WIZARDS LAB🧪 ~~▤▤|   title banner
  2  |▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤|   shelf
  3  |╔══════╗·╔═══════════╗|   well top · SCORE box top
  4  |║······║·║···SCORE···║|
  5  |║······║·║··0123456··║|   ← 7 digits
  6  |║······║·╚═══════════╝|
  7  |║······║··············|
  8  |║······║·╔═══════════╗|
  9  |║······║·║·HIGHSCORE·║|
 10  |║······║·║··3456789··║|   ← 7 digits
 11  |║······║·║····L12····║|   ← level it was set on
 12  |║······║·╚═══════════╝|
 13  |║······║··············|
 14  |║······║·╔═══╗·╔═════╗|   NEXT box · LEVEL box
 15  |║······║·║···║·║LEVEL║|
 16  |║······║·║·▓·║·║·····║|   ← next cell A
 17  |║······║·║·▓·║·║··1··║|   ← next cell B · level tens
 18  |║······║·║·▓·║·║··0··║|   ← next cell C · level units
 19  |║······║·║···║·║·····║|
 20  |╚══════╝·╚═══╝·╚═════╝|
 21  |▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤|   shelf
 22  |▤▤···~~ PAUSED ~~···▤▤|   message band
 23  |▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤▤|   shelf  (VIC-20 clips this row)
```

*(The box-drawing above is illustrative — the real frame uses custom tiles from
[Appendix A](#appendix-a--master-tile-map), a braided rope border. `·` is
blank: the panel is black behind the frames. `▤` is the shelf, tile 126, and
the brick wall is outside the panel entirely.)*

The well interior is **cols 1–6, rows 4–19**, so board (0,0) sits at panel
(1,4). Everything to the right of the gutter is a box of the same braid: the
score, the high score, the preview and the level each get their own frame, and
the four frames line up top and bottom with the well.

### 12.2 Exact regions (panel-relative coordinates)

| Region | Cols | Rows | Notes |
|---|---|---|---|
| Shelf | 0–21 | 0, 2, 21, 23 | tile 126, full width — the panel stands on it |
| Backdrop | 0–21 | 3–20 | blank; the panel is black behind the frames |
| Title banner | 2–19 | 1 | `~~ WIZARDS LAB` + potion + ` ~~`, 18 cells |
| Well frame — top | 0–7 | 3 | |
| Well frame — left wall | 0 | 4–19 | |
| **Well interior** | **1–6** | **4–19** | **board (0,0) is at panel (1,4)** |
| Well frame — right wall | 7 | 4–19 | |
| Well frame — bottom | 0–7 | 20 | |
| Panel gutter | 8 | 3–20 | always backdrop |
| SCORE box | 9–21 | 3–6 | frame; interior cols 10–20, rows 4–5 |
| SCORE label | 13–17 | 4 | |
| **SCORE digits** | **12–18** | **5** | **7 digits, always zero padded** |
| HIGH box | 9–21 | 8–12 | frame; interior cols 10–20, rows 9–11 |
| HIGHSCORE label | 11–19 | 9 | |
| **HIGH digits** | **12–18** | **10** | **7 digits, always zero padded** |
| **HIGH level** | **15–16** | **11** | **2 digits, zero padded; the static `L` label sits at col 14** |
| NEXT box | 9–13 | 14–20 | frame, unlabelled; interior cols 10–12, rows 15–19 |
| **NEXT tiles** | **11** | **16, 17, 18** | A, B, C top to bottom |
| LEVEL box | 15–21 | 14–20 | frame; interior cols 16–20, rows 15–19 |
| LEVEL label | 16–20 | 15 | |
| **LEVEL digits** | **18** | **17, 18** | **tens above units, always zero padded** |
| Message band | 0–21 | 22 | **one row**, centred |

Four things are worth calling out because they are not what you would guess:

- **The backdrop is black and the panel stands on a shelf.** Behind the frames
  there is nothing — no texture, no wall — which is what makes the well read as
  depth rather than as a box drawn on a surface. The three rows at the top and
  the three at the bottom are the **shelf** (tile 126), stepping out to the
  brick at the screen edge; rows 1 and 22 carry the banner text with the shelf
  tapering in at either end. Those six rows are the only place the panel meets
  the margin.

- **The score is seven digits, not six.** The boxes are eleven cells wide
  inside, and only an odd-width field centres exactly. Seven digits is what
  centres, so seven digits is what the score is: `SCORE_BYTES = 4` packed BCD
  with the top nibble held at zero, clamping at 9,999,999. **All seven are
  always drawn** — zero padded, never blank-suppressed, so a digit never
  changes column ([§9](#9-scoring)).
- **The high score carries its level.** Row 11 of the HIGH box reads `L12` —
  an `L` in the static image at col 14, then two live digits. It is the only
  two-line value on the panel, and the three cells centre exactly on the box's
  middle column.
- **The level is stacked, not written across.** Tens at row 17, units at row
  18, both in column 18, always zero padded — level 5 draws `0` over `5`. It
  reads as a single tall numeral inside a small square box, which is why the
  LEVEL box can be five cells wide and still balance the NEXT box beside it.

### 12.3 Board ↔ screen address

```
panel_col = board_col + 1
panel_row = board_row + 4

screen_col = PANEL_X + panel_col
screen_row = PANEL_Y + panel_row      (PANEL_Y is 0 on all three)
```

Precompute a **row-start pointer table** per platform (one lo byte + one hi
byte per screen row) so a cell write is `LDA (rowptr),Y`-shaped with `Y` =
column. This is the same code on all three machines; only the table differs.

`PANEL_X` / `PANEL_Y` are applied **once**, where a cell is queued, and nothing
above that line knows which machine it is running on: everything upstream works
in panel coordinates and the dirty ring holds screen ones
([§12.6](#126-rendering-strategy)).

### 12.4 Per-platform placement

| Platform | Grid | `PANEL_X` | `PANEL_Y` | Panel rows shown | Margin to fill |
|---|---|---|---|---|---|
| **VIC-20** | 22 × 23 | 0 | 0 | 0–22 (row 23 clipped) | none — exact fit |
| **AC6502** | 32 × 24 | 5 | 0 | 0–23 | cols 0–4 and 27–31 (5 × 24 each) |
| **C64** | 40 × 25 | 9 | 0 | 0–23 | cols 0–8 and 31–39 (9 × 25 each), row 24 full width |

`PANEL_X` is an exact centring on both wide machines: `(32−22)/2 = 5`,
`(40−22)/2 = 9`. Vertically there is nothing to centre — the panel is top
aligned everywhere and the difference in screen height is taken at the bottom,
one row either way.

### 12.5 The margin

The margins are **static** — drawn once on entering the PLAY state, never
touched again.

**Two tiles do all of it, on all three machines.** Tile 127 is a brick course
and tile 126 is the shelf; both are group 15, dark red. The panel sits on the
shelf, the shelf steps out to the brick, and the brick runs to the edge of
whatever screen the machine has:

- **VIC-20:** none. The screen *is* the panel.
- **AC6502:** five columns either side — three of brick, then a two-column
  bevel of backdrop against the panel.
- **C64:** the same five columns, with four more of brick outside them, plus
  row 24 as one spare course underneath.

Two reasons the margin is a wall and not a scene, in order of weight:

1. **A dark red wall either side is the right frame for a black playfield.**
   Anything with detail in it competes with the well. The wall recedes. The
   panel is the game and the margin's whole job is to not be.
2. It is the same 22-column panel on three different screen widths, so
   whatever is drawn in the margin exists only on the two wide machines. A
   VIC-20 player must not be looking at a different game.

Because margins never redraw, they cost only tiles, not cycles — and they cost
two.

### 12.6 Rendering strategy

**Never redraw the full screen during play.** All three platforms use a
**dirty-cell ring**:

- The well interior is 96 cells. A worst-case cascade step touches all of them.
- Maintain `DIRTY`, a ring of `(screen column, screen row, tile)` entries,
  flushed once per frame during vertical blank. It is a column and a row, not
  a 16-bit offset, because every platform reaches a cell through the row-start
  pointer table of [§12.3](#123-board--screen-address) and would only have to
  take an offset apart again.
- A ring rather than a list with a resume index: a frame that flushes its cap
  leaves a remainder, and the next frame's marks still have to go somewhere.
- Cap the flush at **24 cells per frame** and carry the remainder to the next
  frame. **This is a time budget, not a hardware limit** — see below.
- The score/level/next fields are dirty-flagged separately and only pushed when
  their values change.
- Anything that queues more than the ring holds — a full 96-cell well redraw —
  is a *cursor*, refilled from the flush each frame, so it spreads over as many
  frames as it needs and never overflows.

**Why 24, measured.** One flush costs **165 CPU cycles a cell** on the AC6502
and about 132 on the Commodores, so 24 cells is ~3,965 cycles: inside vertical
blank on all three, and tightest on the AC6502, whose 70 blank lines are about
4,450 cycles at 1 MHz. It is also a quarter of the well, so a full redraw is
exactly four frames.

**Write spacing is not the constraint, on any of them.** A real TMS9918A wants
8 µs between VRAM data accesses during active display and 2 µs between any two
port accesses. This loop puts two VRAM writes **165 µs** apart at 1 MHz and its
closest two port accesses 8 cycles — 8 µs — apart, so it clears both windows
with two orders of magnitude to spare even at 2 MHz. The AC6502's pico9918 is
looser still: it latches bus writes in the RP2040's PIO and emulates VRAM in
processor memory at 252 MHz or more, so it has no display contention to have a
window about. **A 6502 at this clock cannot write a TMS9918 too fast.**
Overrunning the vblank budget is therefore never corruption — at worst a cell
lands a frame late.

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

The screen is one image, `data/screen-title-*.bin`, drawn once on entry
([§12.6](#126-rendering-strategy)). It is a single framed page, not a logo over
a background:

```
      0         1         2
      0123456789012345678901
  1  |╔════════════════════╗|
  4  |║    WIZARDS LAB♦    ║|   the title, in the font, tail potion green
  6  |║     ~~♦♦♦♦♦♦~~     ║|   one potion of each of the six colours
  8  |║   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓   ║|   the magic field — 14 x 2
  9  |║   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓   ║|
 11  |║     PRESS FIRE     ║|
 14  |║   ← →        MOVE  ║|
 16  |║   ↑ ○      ROTATE  ║|
 18  |║   ↓          DROP  ║|
 20  |║    BY AC WRIGHT    ║|
 22  |╚════════════════════╝|
```

*(Rows 0, 2, 3, 5, 7, 10, 12, 13, 15, 17, 19, 21 and 23 are blank, and so is
every column outside the frame — the title screen has no margin art at all. `♦`
is a potion, `▓` the hatch, `○` the FIRE button.)*

- **The magic field** at rows 8–9 is 28 cells of tile 128–255
  ([Appendix A](#appendix-a--master-tile-map)). Every cell is the same diagonal
  hatch in a different color, so writing a random index from that range into a
  random cell each frame makes the block crawl and shimmer. Two `NextRandom`
  bytes and one `RenderMark` per frame — it is the cheapest animation in the
  game and the only thing moving on the screen besides the prompt.
- **"PRESS FIRE"** blinks at 30-frame intervals. It is the ten cells of the
  drawn image at panel (6, 11), blanked and put back — the one string code
  redraws over its own artwork, which is why `MsgPressFire` has to match the
  screen file byte for byte. **It says FIRE on all three machines.** An earlier
  draft had the Commodores say "PRESS SPACE" when the game was being played on
  the keyboard, which cannot be known at the moment the prompt is read: the
  player has not pressed anything yet, and that is what the prompt is asking
  them to fix. Both keys work either way — SPACE folds into `UP` and the title
  accepts `FIRE | UP` ([§11.2](#112-required-controls)) — so one wording it is.
- **The controls are on the page.** Four glyphs and three words: arrows
  left/right for MOVE, arrow up (or the FIRE dot) for ROTATE, arrow down for
  DROP. The whole control scheme fits on the screen at once, so nothing here
  cycles and the player never waits to read it.
- **Nothing else is taught here.** No reagent legend, no scoring table. The
  reagents teach themselves the first time one goes off, and a page nobody is
  reading teaches nothing. If a rules screen is ever wanted, it belongs
  somewhere the player asks for it.
- FIRE starts the game. The RNG is seeded from the frame counter at that
  moment ([§15](#15-randomness)).

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
- The well interior is **washed** — all 96 cells drawn as tile 7, the stipple
  in group 0 ([Appendix A](#appendix-a--master-tile-map)) — so pausing cannot
  be used to study the board. Panel and margins stay.
- A wash rather than a blank: a blank well reads as *crashed*, a stippled one
  reads as *covered*. It is the same 96 writes either way, and the restore on
  resume is `RenderBoard` either way — which is why the wash is the same
  cursor as `RenderBoard` with one byte saying which tile it is laying down.
  96 cells do not fit the dirty ring in one go
  ([§12.6](#126-rendering-strategy)).
- "PAUSED" flashes in the message band.
- All timers freeze; the frame counter keeps running (it feeds the RNG).

### 13.4 GAMEOVER

1. The current piece stops.
2. **Petrify animation**: rows convert to stone from row 15 upward, 2 frames
   per row (32 frames total). Each cell keeps its own shape —
   `PETRIFY_BASE + (tile & GLYPH_MASK)`, one `AND` and one `ORA`
   ([Appendix A](#appendix-a--master-tile-map)) — so a bomb sets as a stone
   bomb. Empty cells stay empty; the pile petrifies, not the well. **A prism
   sets as `PETRIFY_BASE` itself**: group 15 has no wildcard, and the color has
   to be tested before the glyph or a prism caught mid-rotation
   ([§14](#14-animation--timing)) petrifies into a stone bomb.
3. `~~ GAME OVER! ~~` in the message band; the final score stays in the SCORE
   field. The bang is there for the arithmetic and not the emphasis: banner
   strings are drawn even-length so that `(PANEL_W - length) / 2` centres them
   exactly ([§12.2](#122-exact-regions-panel-relative-coordinates)), and nine
   letters inside a symmetric ornament is always odd. The band is cleared
   either side of whatever banner is up, so a shorter one never leaves the tail
   of a longer one behind it.
4. If a new high score was set, HIGH flashes and a fanfare plays. The flash is
   [§9.8](#98-high-score)'s, restarted here — the overtake itself happened
   mid-game, possibly minutes ago.
5. FIRE or a 10-second timeout returns to TITLE. The timeout counts **seconds**
   and not frames: 600 does not fit in a byte, and would not be ten seconds on
   both regions if it did.

The three steps above wait for step 2. Nothing is said and nothing is counted
until the last row has set, and a press during the petrify is ignored rather
than queued — the animation is the game telling the player it is over, and
skipping it reads as a dropped input.

---

## 14. Animation & Timing

All durations in frames. PAL values are `round(NTSC × 50/60)` where the
difference matters; where it doesn't, the same count is used on both.

| Event | NTSC | PAL | Detail |
|---|---|---|---|
| Match glow | 6 | 5 | Matched cells swap to glyph +6 (glow) of their own color. **Prisms are exempt** — see below |
| Removal | 6 | 6 | The white ring opening outward, 3 tiles at 2 frames each. Same on both regions — see below |
| Prism blip-out | 10 | 10 | The prism's own 5 frames, the same ring closing inward |
| Fireball flash | 8 | 7 | Every tile of the target color turns white, then removes |
| Bolt beam | 6 | 5 | White beam tiles drawn along the row and column |
| Bomb blast | 6 | 6 | The removal ring over the 3 × 3, all nine cells in step |
| Gravity fall | 2/row | 2/row | Tiles descend one row every 2 frames. A row that changes more cells than the dirty ring holds takes an extra frame or two while the flush catches up ([§12.6](#126-rendering-strategy)); on a normal clear it never does |
| Lock delay | 16 | 14 | Resets on horizontal move, max 4 resets |
| Entry delay (ARE) | 12 | 10 | After a cascade fully settles |
| Level-up banner | 45 | 38 | "LEVEL 04" in the message band; play continues |
| Chain banner | 45 | 38 | "CHAIN ×3" for chain ≥ 2 |
| Petrify (game over) | 2/row | 2/row | 16 rows = 32 frames |
| Game-over timeout | 600 | 500 | 10 seconds, counted as seconds ([§13.4](#134-gameover)) |
| Blink period | 30 | 25 | "PRESS FIRE", high-score flash |

A single clear step therefore costs **12 frames of animation plus gravity**
(0–32 frames), 11 on PAL. A deep chain reads as a satisfying half-second per
link rather than an instant score jump.

**The three counts that are the same on both regions are the three that are a
tile count, not a duration.** The removal ring, the bomb blast and the prism's
blip-out are 3, 3 and 5 tiles at **2 frames each**, and two frames does not
round to 1.67 — the same reason the gravity fall above them is 2/row on both
machines. Everything else in this table is a single frame held for a while and
scales properly. The cost is that a PAL clear step is 11 frames against NTSC's
12, about 17 ms of wall clock, which nobody has ever been able to see.

**A step animates in two windows, and a window is as long as the longest thing
in it.** The GLOW window carries the match glow, the bolt's beams and the
fireball's flash; the SHATTER window carries the removal ring and, beside it,
a marked prism's blip-out. So a step with a fireball in it glows for 8 frames
rather than 6, and a step that clears a prism shatters for 10 rather than 6.
One timer per window rather than one per effect is what makes every count in
this table hold without the game tracking six animations at once.

**Only one color can flash at a time.** Two fireballs of *different* colors in
one step leave the last one's color white; the other's cells still glow and
still shatter, they simply do not go white on the way. The flash is one byte of
VDP color table on the AC6502 (below) and one byte of state on the Commodores,
and one byte names one color group.

**One removal animation, two directions.** The match shatter, the bomb blast
and the star all play the same three white tiles (56, 57, 58) opening outward —
a tile coming apart and blowing away. The prism plays the same ring *closing*
(116, 117, 57, 56, 52) and winks out to a point. Nothing else on the board
disappears that way, which is how the player learns that the wildcard is not a
potion. See [Appendix A](#appendix-a--master-tile-map).

**Prisms skip the glow phase.** Group 14 has no glyph +6 — that slot is an
arrow — so a matched prism holds its rotation frame through the glow window and
then blips out while everything around it shatters. `WILD_BASE + GLYPH_GLOW`
must never be constructed.

**A prism sitting in the well animates.** Tiles 112–115 are four rotation
frames; a prism on the board advances one frame every 8 frames whether or not
anything else is happening. It is the only tile that moves at rest, and at
roughly one prism per 90 pieces it costs nothing worth measuring.

**Fireball flash implementation note:** on the AC6502 this is one byte written
to the VDP color table (set the target group's foreground nibble to 15, keeping
its background nibble, then restore it). On the Commodores color is per cell,
so the flashing color is held in one byte of state and the cell writer
substitutes white for any tile of that color as it draws it — which works out
the same, because every tile the fireball is about to take is already being
redrawn by the glow. Same visual, different mechanism, identical frame count.

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

Sound is triggered by a one-byte `SFX_REQUEST` written by game logic and
consumed by the audio tick, which is called once a frame from the bottom of the
main loop ([§13.2](#132-play)).

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

**One channel, and the ID is the priority.** The table above runs from the
quietest event to the loudest, so a request takes the channel only when its ID
is at least the ID of whatever is already playing. That is a rule and not an
accident of ordering: a fireball is set off by a piece the player just moved,
and a bomb detonates in the same frame as the chime for the run that set it
off, so more than one effect is asked for in a single frame routinely. A
request that loses is dropped rather than queued — by the next frame the event
it belonged to is over.

**An effect is a list of steps.** A step is a duration in frames, a *timbre*
and a *note*; a note is a count of semitones above C3 and means the same pitch
on every machine. Nothing in the shared code is a register value.

**A timbre is a voice and an octave**, which is the one abstraction that makes
one driver serve both sound chips:

| Timbre | SID | VIC-I | Octave |
|---|---|---|---|
| `SOFT` | triangle | bass, `$900A` | one below the written note |
| `BUZZ` | sawtooth | alto, `$900B` | as written |
| `BRIGHT` | pulse | soprano, `$900C` | one above |
| `NOISE` | noise | noise, `$900D` | as written |

The VIC-I's three tone oscillators are the same design divided by 256, 128 and
64, so they are already exactly an octave apart and the octave costs nothing
there; on a SID it is a shift of a linear frequency register. Each machine
keeps one note table, built for its own clock. Neither is region-dependent: a
region changes the chip's clock, which transposes every note by the same ratio
and leaves the music in tune with itself.

**The match chime rises by transposing the whole effect** — `2` semitones per
chain link, capped at `8` — rather than by having a step list per depth.

The three drivers came out one level higher than this section originally
planned. It said the AC6502 and the C64 would share SID driver code almost
verbatim (register base `$9800` vs `$D400`) and the VIC-20 would need its own
three-oscillator driver, which is true of the register writes and of nothing
else: the sequencing, the priority, the per-frame envelope and every note are
the same on all three machines and are shared by all three. What a platform
still owns is a note table and one routine that is handed a timbre and a note.
The two SID machines share even that, and differ only in the base address.

---

## 17. Memory Budget

### 17.1 RAM (identical logical layout on all platforms)

| Structure | Bytes | Notes |
|---|---|---|
| `BOARD` | 160 | 20 rows × 8 stride, page-aligned |
| `MARKS` | 16 | 1 byte per row, bits 0–5 |
| `EFFECTQ` | 48 | 48 entries × 1 byte — a board index ([§8](#8-cascade-resolution)) |
| `DIRTY` | 192 | 64 entries × 3 bytes (screen col, screen row, tile) |
| Piece state | 8 | column, row, A/B/C, rotation |
| Next piece | 3 | |
| Score / High | 12 | 4 bytes BCD each, + 1 for the high score's level, + 3 for whether this game has taken it and the blink it fires ([§9.8](#98-high-score)) |
| Level, tiles cleared, chain, stars | 6 | |
| Timers (gravity, lock, DAS, ARE, anim) | 10 | |
| Animation | 11 | The two windows' step and length, the flashing color, the prism's rotation frame and clock, the petrify cursor, the title prompt's blink clock and phase ([§13.1](#131-title)), and five bytes of walk cursors ([§14](#14-animation--timing)) |
| Input current/previous/edge | 3 | |
| RNG seed, frame counter | 4 | |
| State machine, flags | 8 | game state, play sub-state, region, redraw flag, the game-over screen's seconds and the frames of one ([§13.4](#134-gameover)) |
| Audio state | 16 | 5 measured — the effect data is a step list in ROM ([§16](#16-audio)) and the driver is a cursor into it, so RAM holds the request, the effect playing, where in its list it is, the frames left in that step and the chime's transposition |
| **Total** | **~570 bytes** | 526 measured — 43 zero page, 483 BSS; plus row-pointer tables in ROM |

Fits the VIC-20's constrained RAM with room to spare, which is the whole point
of designing to the tightest target first. In practice the whole of BSS lands
in the 1 KB at `$1000`–`$13FF` ([C.2](#c2-vic-20)) with 530 bytes still free,
so the `$1C00`–`$1DFF` block that table earmarks for `DIRTY` is untouched and
is spare capacity rather than a plan.

Piece state is 7 bytes of the 8 budgeted (column, row, A/B/C is 5; there is no
rotation byte, because rotation cycles the three cells in place rather than
turning a footprint). The eighth is `PIECE_DIRTY`, the flag that holds the
piece's redraw back until any full-board redraw has gone past it.

### 17.2 ROM (16 KB cartridge)

| Contents | Estimate |
|---|---|
| Tileset (256 × 8 bytes) | 2048 |
| Game logic (board, match, cascade, scoring) | ~3000 |
| Render + platform HAL | ~1500 |
| Title / game-over screens + text | ~1500 |
| Screen images (RLE-compressed) | ~800 |
| Audio driver + data | ~500 measured (~1500 estimated) |
| Tables (speed, scoring, color, row pointers) | ~800 |
| **Subtotal** | **~11,150** |
| **Headroom** | **~5,200** |

Comfortable. The six screen images should be run-length encoded: the margin is
two tiles ([§12.5](#125-the-margin)), so the images are almost entirely runs of
brick and shelf and the C64's 1000-cell images should come down under 200 bytes
each. The 800-byte line above is a conservative estimate.

---

## Appendix A — Master Tile Map

**One 256-tile set, identical indices on all three platforms.** The layout obeys
the TMS9918's 8-pattern color groups, which costs the Commodores nothing (they
have tiles to spare) and buys a completely shared renderer.

| Group | Tiles | Color (TMS fg / CBM) | Contents |
|---:|---|---|---|
| 0 | 0–7 | 15 White / 1 | Blank, bar-H, bar-V, corner-TL, corner-TR, corner-BL, corner-BR, wash |
| 1 | 8–15 | 14 Gray / 15 (C64), 1 (VIC) | Group 0 again, byte for byte, one color quieter; see A.3 |
| 2 | 16–23 | 15 White / 1 | Font: `0 1 2 3 4 5 6 7` |
| 3 | 24–31 | 15 White / 1 | Font: `8 9 A B C D E F` |
| 4 | 32–39 | 15 White / 1 | Font: `G H I J K L M N` |
| 5 | 40–47 | 15 White / 1 | Font: `O P Q R S T U V` |
| 6 | 48–55 | 15 White / 1 | Font: `W X Y Z · × ! ~` — the dot is **centred**, see A.3 |
| 7 | 56–63 | 15 White / 1 | VFX: removal ring ×3, beam-H, beam-V, beam-cross, arrow up, arrow down |
| **8** | **64–71** | **8 Med Red / 2** | **Red:** potion, fireball, bolt, bomb, star, —, glow, — |
| **9** | **72–79** | **11 Lt Yellow / 7** | **Yellow:** same 8 slots |
| **10** | **80–87** | **3 Lt Green / 5** | **Green:** same 8 slots |
| **11** | **88–95** | **7 Cyan / 3** | **Cyan:** same 8 slots |
| **12** | **96–103** | **5 Lt Blue / 6** | **Blue:** same 8 slots |
| **13** | **104–111** | **13 Magenta / 4** | **Purple:** same 8 slots |
| 14 | 112–119 | 15 White / 1 | **Prism:** four rotation frames, two blip-out frames, arrow left, arrow right — see A.3 |
| 15 | 120–127 | **6 Dark Red / 2** | Stone: the petrified glyph set, a reserved slot, the shelf, the brick — see A.3 |
| 16–31 | 128–255 | various | **The magic field** — one hatch in 16 colors, for the title screen ([§13.1](#131-title)) |

Two things here are not what you would guess:

- **There is no joint tile.** No two frames on the panel share an edge — the
  well, SCORE, HIGH, NEXT and LEVEL boxes all stand clear of one another with a
  backdrop cell between — so group 0's slot +7 carries the wash instead.
- **The margin is not artwork.** It is two tiles in group 15, the same on all
  three machines ([§12.5](#125-the-margin)). That leaves the whole upper half
  of the tile map for one purpose: the title screen's field.

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

This is the layout of the **six potion groups**. Group 14, the prism's, does
not follow it: [§5.2](#52-generation) generates a wild tile as glyph +0, and
the only thing that ever changes it is the prism's own idle rotation, which
walks it through 113–115 ([§14](#14-animation--timing)). So a board cell can
never hold 116–119, and the three it can hold are not glyphs at all — nothing
reads a wild cell's glyph. Group 15 borrows the first five offsets for the
petrified set. See A.3.

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
- **Glow** is a 50 % dither over the whole cell — not the potion silhouette
  filled in, which reads as a *block* rather than a bright potion. A dither
  reads as shimmer, and against black it is genuinely half as bright, so a
  field of glowing tiles does not white out the well.
- Draw the six potions as **six copies of one pattern**. Identical shape, six
  color groups. Only the reagents need to differ from each other.

All 256 tiles are drawn, in `artwork/WizardsLab.tms9918`, and
`tools/import-artwork.py` is the only way they reach the build. This appendix
describes what is in that file; if the two ever disagree, this document is
right and the art is wrong.

### A.3 The groups that do not hold potions

Groups 8–13 are six copies of one pattern, five glyphs each, and groups 2–6 are
the font. The rest of the tile map is the frame, the effects, the prism, the
stone, and the field.

#### Groups 0 and 1, tiles 0–15 — the frame, twice

Group 1 is **group 0 byte for byte**, one color quieter: white on the
AC6502 and C64 becomes gray, so

```
dim_tile = frame_tile + FRAME_DIM        ; FRAME_DIM = 8
```

turns any piece of frame into its quieter twin with an `ADC #8`. The panel can
then establish a hierarchy without a second stroke weight: the **well keeps
white** and the SCORE / HIGH / NEXT / LEVEL boxes step back to gray, so the eye
lands on the playfield instead of dividing evenly between five identical
frames.

| Slot | Tile 0–7 (white) | Tile 8–15 (gray) |
|---|---|---|
| +0 | Blank | Blank |
| +1 | bar-H | |
| +2 | bar-V | |
| +3 | corner-TL | |
| +4 | corner-TR | |
| +5 | corner-BL | |
| +6 | corner-BR | |
| +7 | **Wash** | **Wash** |

Slot +7 is the **wash**: a sparse stipple, about one pixel in eight, that knocks
a region back without erasing it. [§13.3](#133-pause) draws it over the well.
The white one and the gray one are the same eight bytes, so which of the two
reads better over the well is a taste call the art can make without touching
code.

> **VIC-20 note.** The VIC's eight hi-res colors have no gray, so group 1
> renders **white** there and the two weights are identical. The hierarchy is
> a bonus on two machines, not something the layout may depend on.

#### Group 6, tiles 48–55 — the font's tail

`W X Y Z · × ! ~`. Tile 52 is a **centred dot, not a baseline period.** No
string the game draws contains a full stop — the labels are `SCORE`,
`HIGHSCORE`, `LEVEL`, `PAUSED`, `GAME OVER`, `PRESS FIRE` — so the slot earns
more as the innermost frame of the removal ring below than as punctuation. If a
string ever does need a period, it can have the dot and nobody will notice.

#### Group 7, tiles 56–63 — VFX (white)

| Tile | Role | Art note |
|---|---|---|
| 56 | **Removal 1** | A small hollow ring at the centre of the cell |
| 57 | **Removal 2** | Eight specks, opened out one pixel |
| 58 | **Removal 3** | Eight specks again, at the corners — nearly gone |
| 59 | Beam-H | The bolt's row. Must butt seamlessly against its neighbours |
| 60 | Beam-V | The bolt's column |
| 61 | Beam-cross | Drawn once, at the bolt's own cell |
| 62 | **Arrow up** | The title screen's controls ([§13.1](#131-title)) |
| 63 | **Arrow down** | |

**There is one removal animation and everything uses it.** Tiles 56–58, with
the centred dot (52) as an optional innermost frame, are a single ring opening
outward:

```
·  →  ○  →  ˙ ˙ ˙  →  ˙   ˙   ˙  →  empty
52    56       57            58
```

It reads as *dispersal* — the tile coming apart and blowing away — and it
covers the match shatter, the bomb blast and the star between them. One
animation for every removal is a better rule than three, because the player
learns it once. The bolt keeps its own beams, because a beam has to join up
with the cell next to it and a ring does not.

Run the same four tiles in the other order and you have the prism's blip-out
(group 14), for no extra art.

Arrows up and down sit here because group 7 has two slots spare after the ring;
left and right are in group 14 for the same reason. Splitting them across two
groups is untidy and costs nothing — nothing indexes the arrows as a set.

The **fireball** needs no tile at all. It recolors in place — one poke to the
VDP color table on the AC6502, a walk of the dirty list on the Commodores
([§4.6](#46-the-fireballs-free-trick)).

#### Group 14, tiles 112–119 — the prism

[§5.2](#52-generation) generates a wild tile as glyph +0 and nothing scores,
matches or removes it by its glyph, so the low three bits of a wild cell are
free for the game to use as a **frame number**. That is what the idle rotation
below does: a prism on the board holds 112–115 and never anything else. Slots
116–119 are the blip-out and two arrows, and no board cell ever holds one of
those — they are drawn *over* a cell, not stored in it. Seven free slots in the
one spare *white* group, and the prism spends six of them on itself.

| Tile | Role |
|---|---|
| 112–115 | **Prism rotation.** Four frames of a faceted diamond turning. The idle animation — a prism sitting in the well is the only tile on the board that moves |
| 116–117 | **Blip-out**, frames 1–2. The diamond coming apart |
| 118 | **Arrow left** |
| 119 | **Arrow right** |

**The prism has no glow slot**, and that is the one thing here that code has to
know. Slot +6 of every potion group is the match-flash frame; slot +6 of *this*
group is an arrow. So `WILD_BASE + GLYPH_GLOW` is not a tile — it is a bug —
and a prism does not take the glow-then-shatter path with the run it clears.
It plays its own five frames instead:

```
🔷  →  ✳  →  ˙ ˙ ˙  →  ○  →  ·  →  empty
116    117      57       56    52
```

The removal ring, closing inward. A prism *contracts to a point and winks
out*; everything else *bursts apart*. Same tiles, opposite direction, and the
one wildcard on the board is the one thing that disappears differently.

> **Two constraints this rests on.** Nothing may add `GLYPH_GLOW` to
> `WILD_BASE` — that is `WILD_BASE + n` arithmetic that looks harmless and is
> not, and it lands on an arrow in the middle of the board. And **nothing may
> read a wild cell's glyph**, because the idle rotation puts a frame number
> there: every test of a wild cell is a test of its *color*, and a test that
> asks the glyph first sees a bolt or a bomb. That second one is not
> hypothetical — the fireball's immunity rule, the effect queue and the
> game-over petrify all sit on it ([§7.4](#74-interaction-summary),
> [§13.4](#134-gameover)).

#### Group 15, tiles 120–127 — stone

The game-over tile and the two tiles the whole screen is built on, in one dark
red group.

| Tile | Role |
|---|---|
| 120–124 | **The petrified glyph set** — potion, fireball, bolt, bomb, star, at the same five offsets the potions use |
| 125 | Reserved. Held for the +5 glyph, if a sixth reagent is ever added |
| 126 | **Shelf.** The plank the panel stands on, top and bottom |
| 127 | **Brick.** The margin fill |

The petrified set is the shape of the group. Because it sits at the same five
offsets as the potion glyphs,

```asm
petrified = PETRIFY_BASE + (tile & GLYPH_MASK)     ; glyphs 0-4
```

is the whole of [§13.4](#134-gameover)'s conversion — one `AND`, one `ORA` —
and the well petrifies **into its own contents**. A bomb sets as a stone bomb,
not as a generic block, so the board keeps its detail at the exact moment the
player is looking hardest at it.

Two of the five (bolt and star) are byte-identical to their potion-group
counterparts: those silhouettes are solid enough that the color change alone
sells stone. The other three are the outlined shapes filled in.

> **VIC-20 note.** The VIC's eight hi-res colors have no gray and no brown, so
> group 15 lands on red (2) — the same red as potion color 0. In the margins
> that is fine, they are never adjacent to the well. At game over the entire
> well petrifies at once, so there is nothing left to confuse it with. The
> petrified silhouettes are *filled* rather than outlined, which is what sells
> them as stone when the color cannot.

#### Groups 16–31, tiles 128–255 — the magic field

All 128 tiles are **the same diagonal hatch**, in sixteen different colors.
That is the entire content of the upper half of the tile map.

The title screen carries a 14 × 2 block of them ([§13.1](#131-title)). Poking
random indices from this range into those 28 cells makes the block crawl and
change color, which is the cheapest convincing "magic" the machine can do — no
per-tile art, no animation frames, one `NextRandom` and one write per cell.

The hatch tiles seamlessly with itself in both axes, so the block reads as one
moving surface rather than 28 squares.

The sixteen colors are the artwork groups in `data/tilecolor-*.inc`, and they
span the machine's whole palette rather than a chosen ramp — several are dark,
so the field flickers as much as it shimmers. That is the intended read: a
field that pulses light and dark is more alive than one that stays bright.
Narrowing it to a ramp is a sixteen-line `.inc` edit that touches no artwork.

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
GLYPH_GLOW       = 6            ; potion groups only — never WILD_BASE + this

NUM_COLORS       = 6

TILE_WASH        = 7            ; PAUSE stipple, white; +8 is the grey one
FONT_DOT         = 52           ; centred, and removal frame 0
VFX_REMOVE1      = 56           ; the ring, opening outward
VFX_REMOVE2      = 57
VFX_REMOVE3      = 58
VFX_BEAM_H       = 59
VFX_BEAM_V       = 60
VFX_BEAM_CROSS   = 61
ARROW_UP         = 62
ARROW_DOWN       = 63
PRISM_SPIN       = $70          ; 4 idle frames, WILD_BASE + 0..3
PRISM_BLIP       = $74          ; 2 frames, then VFX_REMOVE2, 1, FONT_DOT
ARROW_LEFT       = 118
ARROW_RIGHT      = 119
PETRIFY_BASE     = 120          ; + (tile & GLYPH_MASK), glyphs 0-4
TILE_SHELF       = 126
TILE_BRICK       = 127
FRAME_DIM        = 8            ; frame tile + 8 is its grey twin
ART_BASE         = 128          ; 128 hatch tiles — the title screen's field

; ---- Panel ----
PANEL_W          = 22
PANEL_H          = 24
WELL_ORIGIN_X    = 1            ; panel-relative
WELL_ORIGIN_Y    = 4
; per-platform, PANEL_Y is 0 on all three:
;   VIC-20   PANEL_X = 0        panel row 23 clipped
;   AC6502   PANEL_X = 5        exact fit
;   C64      PANEL_X = 9        screen row 24 spare

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
GLOW_FRAMES      =  6 /  5      ; ...and the bolt's beam, in the same window
FLASH_FRAMES     =  8 /  7      ; the fireball's, which LENGTHENS that window
VFX_FRAMES       =  2 /  2      ; frames per tile of a removal ring
REMOVE_FRAMES    =  6 /  6      ; 3 tiles x 2 frames — a tile count, so the
BLIP_FRAMES      = 10 / 10      ;   same on both regions (14). The prism, 5 x 2
SPIN_FRAMES      =  8 /  8      ; per prism rotation frame, at rest
FALL_FRAMES      =  2 /  2
PETRIFY_FRAMES   =  2 /  2      ; per row of the game-over petrify (13.4)
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
SCORE_MAX     = $09,$99,$99,$99
HIGH_INIT     = 0010000

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
  | `$1E00-$1FF9` | 506 | Screen matrix (22 × 23 — panel row 23 is clipped) |

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
  playfield; the upper 8 are reached only by tile groups 16–31, the title
  screen's magic field.
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
- The artwork is finished. Both screens and all 256 tiles are drawn
  (`artwork/WizardsLab.tms9918`), so no phase waits on art. Everything left in
  that area is compression, not drawing.

---

## Appendix E — Cut List & Stretch Ideas

### If ROM or schedule runs short, cut in this order

1. **The magic field** → a static block of one tile. Costs nothing
   mechanically and saves the per-frame writes, though not the tiles.
2. **Prism rotation** → hold frame 0. The blip-out is what carries the idea;
   the rotation is the flourish.
3. **Bomb** (glyph +3) → its role overlaps most with the bolt. Redistribute its
   probability to bolt and fireball.
4. **Reverse rotate** (fire button) → up-only rotation is playable.
5. **Star** → it is the least mechanical reagent, though also the cheapest to
   implement, so it should survive almost anything.

**Not on this list:** the margin, which is two tiles and has nothing left to
give ([§12.5](#125-the-margin)), and the artwork, which is drawn and costs no
schedule.

**Never cut:** the prism (it is what keeps a bad board recoverable) or the
fireball (it is the game's identity).

### Stretch ideas for a v2

- **Slots +5 and +7 are free in all six potion groups**, and tile 125 is held
  for a +5 petrified frame — one more reagent with no tileset reflow required.
  A second would need a stone twin that group 15 has no room for. Candidates:
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
