; =============================================================================
;   cascade.asm — Wizards Lab, clear resolution
; =============================================================================
;   SPEC.md section 8. A cascade runs from the moment a piece locks until no
;   further matches exist, one step per iteration, with ChainStep counting the
;   steps. The step order is fixed:
;
;       scan -> score matches -> enqueue reagents -> resolve queue
;            -> animate -> remove -> level check -> gravity -> repeat
;
;   The effect queue always drains. Effects only ever remove tiles, never add
;   them, and each cell can be marked at most once, so the queue is bounded by
;   the 96 cells of the playfield.
; =============================================================================

; -----------------------------------------------------------------------------
;   CascadeBegin — called immediately after PieceLock
;   Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
CascadeBegin:
  lda #1
  sta ChainStep                 ; The step about to run is step 1 (SPEC 8)
  lda #0
  sta CascadeLo
  sta CascadeMid
  sta CascadeHi
  sta StarCount
  sta RunCount
  jmp EffectQClear

; -----------------------------------------------------------------------------
;   CascadeStep — run one step's scan and take what it found off the board
;   In:  nothing
;   Out: C set if anything matched, and the caller should let the pile fall.
;        C clear when nothing matched and the cascade has settled.
;        Modifies: A, X, Y, Scan*, CellCount, Marks, RunCount
;
;   Steps 3 to 5 of SPEC 8 are still to come: P5 enqueues and resolves the
;   reagents among the marked cells, and P6 puts the glow and the shatter
;   between the scan and the removal. Both land between the calls below
;   without moving any of them, which is the reason the step is split into a
;   scan and a removal that a sub-state can sit between.
;
;   Step 2's per-run half is in MatchEmit, which is the one moment a run's
;   length and colour are both in hand; what is left of it here is the bonus
;   for having found several at once, which nothing knows until all four
;   passes have finished.
; -----------------------------------------------------------------------------
CascadeStep:
  jsr MatchScan
  beq @Settled                  ; RunCount is zero — nothing left to clear

  ldx RunCount                  ; SPEC 8 step 2, last line, and SPEC 9.4
  dex                           ; MultiBonus is indexed by runs - 1 ...
  cpx #5
  bcc @Multi
  ldx #4                        ;   ... and flattens out at 5
@Multi:
  lda MultiBonusLo,x
  pha
  lda MultiBonusHi,x
  tax
  pla
  jsr CascadeAdd

  jsr CascadeRemove             ; SPEC 8 step 6
  lda CellCount
  jsr ScoreLevelCheck           ; SPEC 8 step 7 — match and effect removals
  sec                           ;   both count, and by here they are the same
  rts                           ;   cells
@Settled:
  clc
  rts

; -----------------------------------------------------------------------------
;   CascadeRemove — empty every marked cell and queue it for redraw
;   In:  Marks
;   Out: CellCount = cells removed.  Modifies: A, X, Y, CellCount, RedrawCol
;   SPEC 8 step 6.
;
;   At most 96 cells and the ring holds 64 — but a marked cell is a cell that
;   just matched, and a board cannot hold more matches than it holds tiles
;   that a single piece completed. The worst real case is a handful. This one
;   does NOT need the cursor treatment BoardGravityStep gets: gravity moves
;   cells that were never marked, and can genuinely touch the whole well.
;
;   CellCount goes to ScoreLevelCheck — thirty cleared tiles is a level
;   (SPEC 10.1) — and P6 will have animated these cells before they go.
; -----------------------------------------------------------------------------
CascadeRemove:
  lda #0
  sta CellCount
  tax                           ; X = board index, walked a row at a time
@Row:
  txa
  lsr a
  lsr a
  lsr a
  tay
  lda Marks,y
  beq @NextRow                  ; Nothing marked in this row, and most rows
                                ;   hold nothing marked
@Cell:
  txa
  pha
  jsr MarkTest
  pla
  tax                           ; MarkTest needs X, so the cursor comes back
  bcc @NextCell                 ;   through A. Neither PLA nor TAX touches C.
  lda #TILE_EMPTY
  sta Board,x
  inc CellCount
  txa
  pha
  jsr RenderCell
  pla
  tax
@NextCell:
  inx
  txa
  and #(BOARD_STRIDE - 1)
  cmp #BOARD_W
  bcc @Cell

  txa                           ; X is on the row's first sentinel column;
  clc                           ;   step over both of them
  adc #(BOARD_STRIDE - BOARD_W)
  tax
  jmp @Test

@NextRow:
  txa
  clc
  adc #BOARD_STRIDE
  tax
@Test:
  cpx #(BOARD_H * BOARD_STRIDE)
  bcc @Row
  rts

; -----------------------------------------------------------------------------
;   CascadeSettle — apply the star multiplier and bank the points
;   SPEC 8 SETTLE, SPEC 9.6 — the doubling covers the WHOLE cascade, including
;   points scored before the star cleared.
; -----------------------------------------------------------------------------
CascadeSettle:
  lda StarCount
  cmp #STAR_SHIFT_CAP
  bcc @Shift
  lda #STAR_SHIFT_CAP           ; x8 and no further, however many were caught
@Shift:
  tax
  beq @Bank
@Double:
  jsr CascadeDouble             ; A doubling in BCD is one self-addition
  dex
  bne @Double
@Bank:
  jmp ScoreAdd                  ; Its carry is not read: ScoreHighCheck has
                                ;   already raised the fanfare and the flash
                                ;   itself, and does so exactly once

; -----------------------------------------------------------------------------
;   The five reagents (SPEC 7.3). Each marks its targets, scores them at
;   EffectValue[chain], and pushes any reagent it uncovers back onto the queue.
; -----------------------------------------------------------------------------
EffectFireball:                   ; In: A = colour key. Every tile of it, board wide.
  rts                             ;     Prisms are immune — they have no colour.

EffectBolt:                       ; In: X = row, Y = column. Row + column, <= 21 cells.
  rts

EffectBomb:                       ; In: X = row, Y = column. 3x3, clipped at the edges.
  rts

EffectStar:                       ; Removes nothing; StarCount += 1, capped later.
  rts

EffectPrism:                      ; Removes nothing; awards BONUS_PRISM.
  rts

; -----------------------------------------------------------------------------
;   The effect queue — a ring of (glyph, row, col) packed into two bytes.
;   On overflow an effect is dropped rather than growing the buffer; with at
;   most one reagent per piece, EFFECTQ_ENTRIES is not reachable in practice.
; -----------------------------------------------------------------------------
EffectQClear:                   ; Real ahead of the rest of the queue, because
  lda #0                        ;   CascadeBegin has to start every cascade
  sta EffectQHead               ;   with an empty one and P5 is the phase that
  sta EffectQTail               ;   first puts something in it
  rts

EffectQPush:                      ; In: A = glyph, X = row, Y = column
  rts

EffectQPop:                       ; Out: C clear if empty
  clc
  rts
