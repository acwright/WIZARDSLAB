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
;   Steps 3 and 4 are the reagents, and they run between the scan and the
;   removal because everything they do is add cells to Marks: by the time
;   CascadeRemove walks the bitmap it cannot tell a cell the scan found from
;   a cell a fireball took, and does not need to. Step 5 is still to come —
;   P6 puts the glow and the shatter here, which is the reason the step is
;   split into a scan and a removal that a sub-state can sit between.
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

  jsr EffectEnqueueMarked       ; SPEC 8 step 3
  jsr EffectResolve             ; SPEC 8 step 4

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
;   Every marked cell is zeroed in one go, because the gravity that follows
;   needs a board that is finished changing. Only the REDRAW is rationed: at
;   most 96 cells can be marked and the dirty ring holds 64, and P5 made that
;   reachable — a bolt is 21 cells on its own and a chain of them is most of
;   the well. A mark dropped by a full ring is never made again (D6), so
;   rather than drop one this falls back to RenderBoard, the whole-well cursor
;   RenderFlush already feeds a frame at a time (D12). Four frames of redraw
;   instead of a hole in the screen, and only on the rare huge step: a plain
;   three-in-a-row never comes near the cap.
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

  lda DirtyCount                ; Room to mark this one?
  cmp #DIRTY_ENTRIES
  bcs @Bulk                     ; No — redraw the lot instead of losing it
  txa
  pha
  jsr RenderCell
  pla
  tax
  jmp @NextCell
@Bulk:
  txa
  pha
  jsr RenderBoard               ; Sets the cursor and nothing else, so the
  pla                           ;   cells already queued still land and the
  tax                           ;   redraw overwrites them with the same values
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


; =============================================================================
;   The reagents (SPEC 7)
; =============================================================================
;   Steps 3 and 4 of SPEC 8, and the five effects between them. The shape is:
;
;     EffectEnqueueMarked   walks MARKS once the scan has finished, and offers
;                           every matched cell to EffectEnqueue
;     EffectEnqueue         decides what a cell being removed is worth — a
;                           prism pays, a star counts, a fireball/bolt/bomb
;                           queues
;     EffectResolve         drains the queue, detonating each in turn
;     EffectFireball/Bolt/  list the cells a detonation reaches, and offer each
;       Bomb                one to EffectHit
;     EffectHit             marks it, scores it, and offers it to
;                           EffectEnqueue in its turn — which is the whole of
;                           SPEC 7.2's chain reaction, in one routine
;
;   TERMINATION IS STRUCTURAL, not a limit. An effect only ever MARKS cells and
;   never adds one, and EffectHit refuses a cell that is already marked, so a
;   cell can be pushed at most once and the loop is bounded by the 96 cells of
;   the well.
;
;   Nothing here touches the board. Marked cells are still sitting there,
;   readable, until CascadeRemove zeroes them in step 6 — which is what lets a
;   queue entry be a board index and nothing else (constants.inc).
; =============================================================================

; -----------------------------------------------------------------------------
;   EffectEnqueueMarked — SPEC 8 step 3
;   In:  Marks, as MatchScan left it
;   Out: nothing.  Modifies: A, X, Y, EffectIdx, EffectQ, StarCount, Cascade*
;
;   Nothing called from here marks anything, so the bitmap being walked cannot
;   change underneath the walk. Step 4 is where marking starts, and the cells
;   it marks enqueue themselves as they are marked (EffectHit) rather than
;   waiting for a second pass over MARKS.
;
;   It has to be a pass over the union rather than part of MatchEmit's mark
;   loop: a cell in a horizontal run AND a vertical one is marked twice and
;   would then detonate twice (SPEC 6.1).
; -----------------------------------------------------------------------------
EffectEnqueueMarked:
  lda #0
  sta EffectIdx
@Row:
  lda EffectIdx
  lsr a
  lsr a
  lsr a
  tay
  lda Marks,y
  beq @NextRow                  ; Nothing marked in this row, which is most
                                ;   rows of most steps
@Cell:
  lda EffectIdx
  jsr MarkTest
  bcc @NextCell
  ldx EffectIdx
  jsr EffectEnqueue
@NextCell:
  inc EffectIdx
  lda EffectIdx
  and #(BOARD_STRIDE - 1)
  cmp #BOARD_W
  bcc @Cell

  lda EffectIdx                 ; On the row's first sentinel column; step
  clc                           ;   over both of them
  adc #(BOARD_STRIDE - BOARD_W)
  sta EffectIdx
  jmp @Test

@NextRow:
  lda EffectIdx
  clc
  adc #BOARD_STRIDE
  sta EffectIdx
@Test:
  lda EffectIdx
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Row
  rts

; -----------------------------------------------------------------------------
;   EffectEnqueue — a marked cell is going; make what it holds count
;   In:  X = board index of a cell that is ALREADY marked
;   Out: nothing.  Modifies: A, X, Y
;
;   Called exactly once per removed cell — from step 3 for the cells the scan
;   found, and from EffectHit for every cell an effect takes. Three outcomes:
;
;     a prism   pays BONUS_PRISM here and now and is never queued: it has no
;               effect to fire, only a bonus (SPEC 7.3)
;     a star    counts into StarCount and is never queued either — SPEC 8
;               step 3 is explicit that stars are counted, not queued
;     the rest  go on the queue, and pay their trigger bonus when they pop
;
;   THE COLOUR IS TESTED BEFORE THE GLYPH, and that order is not cosmetic. A
;   prism is glyph 0 of colour 6, indistinguishable from a plain potion by its
;   glyph alone — and from P6 onward the board may hold any of the prism's four
;   idle rotation frames, whose low three bits read as a bolt or a bomb and
;   would detonate one. Colour 6 is the only test that stays true.
; -----------------------------------------------------------------------------
EffectEnqueue:
  lda Board,x
  and #COLOR_MASK
  cmp #WILD_BASE
  beq @Prism
  lda Board,x
  and #GLYPH_MASK
  beq @Done                     ; A plain potion, which is most of the board
  cmp #GLYPH_STAR
  beq @Star
  bcs @Done                     ; Glyphs 5-7 are animation frames (SPEC 4.4),
                                ;   never reagents
  txa
  jmp EffectQPush               ; Fireball, bolt or bomb — glyphs 1 to 3
@Done:
  rts
@Prism:
  jmp EffectPrism               ; Both of these are the far side of the three
@Star:                          ;   detonations below, well out of branch range
  jmp EffectStar

; -----------------------------------------------------------------------------
;   EffectHit — one cell of one detonation
;   In:  X = board index
;   Out: nothing.  Modifies: A, X, Y
;
;   The whole of SPEC 8 step 4's inner loop, which is why every effect below
;   is nothing but a list of cells to offer it.
;
;   A cell that is empty, a wall, or already marked is not a target. "Not
;   already marked" is what makes the queue terminate and what stops a cell
;   being paid for twice; testing the WALL here is what lets the walks above
;   run over the two sentinel columns without bounds checks of their own. A
;   marked sentinel would be zeroed by CascadeRemove and the well would grow
;   a hole in its floor.
; -----------------------------------------------------------------------------
EffectHit:
  lda Board,x
  beq @Done                     ; Empty
  cmp #TILE_WALL
  beq @Done                     ; A sentinel is never a target
  txa
  pha
  jsr MarkTest
  pla
  tax                           ; Neither PLA nor TAX touches C
  bcs @Done                     ; Already going

  txa
  pha                           ; MarkSet takes the index in A, which PHA left
  jsr MarkSet                   ;   alone
  jsr EffectScoreCell           ; SPEC 9.2, per cell an effect took
  pla
  tax
  jmp EffectEnqueue             ; ...and if it was a reagent, it fires too
@Done:
  rts

; -----------------------------------------------------------------------------
;   EffectScoreCell — EffectValue[chain] for one cell taken by an effect
;   Out: nothing.  Modifies: A, X, Y
;   SPEC 9.2 — deliberately dearer than a matched tile at low chain depth, so
;   that the first reagent a player ever sets off feels better than plain play.
; -----------------------------------------------------------------------------
EffectScoreCell:
  ldx ChainStep
  dex                           ; Indexed by chain - 1 ...
  cpx #8
  bcc @Chain
  ldx #7                        ;   ... and flattens out at 8
@Chain:
  lda EffectValueLo,x
  pha
  lda EffectValueHi,x
  tax
  pla
  jmp CascadeAdd

; -----------------------------------------------------------------------------
;   EffectResolve — drain the queue (SPEC 8 step 4)
;   Out: nothing.  Modifies: A, X, Y, Effect*, Marks, Cascade*, StarCount
;
;   The detonation runs first and the trigger bonus is paid on the way back,
;   which is the order SPEC 8 step 4 sets out. It makes no difference to the
;   total — everything lands in the same accumulator — but it does mean the
;   glyph has to survive a routine that clobbers all three registers, and the
;   stack is the cheapest place to put it.
; -----------------------------------------------------------------------------
EffectResolve:
@Loop:
  jsr EffectQPop
  bcc @Done                     ; Empty — the step is finished

  tax                           ; X = the detonating cell
  lda Board,x                   ; Still on the board: step 6 has not run
  and #GLYPH_MASK
  pha
  cmp #GLYPH_FIREBALL
  beq @Fireball
  cmp #GLYPH_BOLT
  beq @Bolt

  lda #SFX_BOMB                 ; Glyph 3 — nothing else ever reaches here
  sta SfxRequest
  jsr EffectBomb
  jmp @Bonus

@Fireball:
  lda #SFX_FIREBALL
  sta SfxRequest
  lda Board,x
  and #COLOR_MASK               ; Its own colour, which can never be wild
  jsr EffectFireball
  jmp @Bonus

@Bolt:
  lda #SFX_BOLT
  sta SfxRequest
  jsr EffectBolt

@Bonus:
  pla
  tay                           ; TriggerBonus is indexed by glyph (SPEC 9.5),
  lda TriggerBonusLo,y          ;   and is paid however the reagent was removed
  ldx TriggerBonusHi,y
  jsr CascadeAdd
  jmp @Loop
@Done:
  rts

; -----------------------------------------------------------------------------
;   The five reagents (SPEC 7.3). Each lists the cells it reaches and leaves
;   the marking, the scoring and the chain reaction to EffectHit.
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
;   EffectFireball — every remaining tile of one colour, board wide
;   In:  A = the colour key ($40 to $68)
;   Out: nothing.  Modifies: A, X, Y, EffectIdx, EffectArg, Marks, Cascade*
;   SPEC 7.3 — the signature reagent, and the reason a chain goes three deep.
;
;   PRISMS ARE IMMUNE AND IT COSTS NOTHING TO MAKE THEM SO (SPEC 7.4). A prism
;   is colour 6 and a fireball's colour never is, so the compare below is the
;   immunity — there is no special case to forget. An empty cell and a wall
;   fail it for the same reason, which is why this walks all eight columns of
;   every row rather than stepping over the sentinels.
;
;   The fireball's own cell is already marked, so it is not a target of itself,
;   and a second fireball of the same colour in the same step finds nothing
;   left to take — and still pays its trigger bonus (SPEC 7.3).
; -----------------------------------------------------------------------------
EffectFireball:
  sta EffectArg                 ; The colour it is hunting
  lda #0
  sta EffectIdx
@Cell:
  ldx EffectIdx
  lda Board,x
  and #COLOR_MASK
  cmp EffectArg
  bne @Next
  jsr EffectHit
@Next:
  inc EffectIdx
  lda EffectIdx
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Cell
  rts

; -----------------------------------------------------------------------------
;   EffectBolt — the whole row and the whole column through the bolt's cell
;   In:  X = board index
;   Out: nothing.  Modifies: A, X, Y, EffectIdx, EffectEnd, EffectArg, Marks
;   SPEC 7.3 — up to 6 + 16 - 1 = 21 cells, and the only reagent that reaches
;   something buried at the bottom of a column.
;
;   Neither walk needs clipping: a row is six cells wherever it is, and a
;   column is sixteen. The bolt's own cell is offered twice, once by each, and
;   is refused both times because it was marked before this was called.
; -----------------------------------------------------------------------------
EffectBolt:
  txa
  and #(BOARD_STRIDE - 1)
  sta EffectArg                 ; Its column, for the second walk
  txa
  and #(256 - BOARD_STRIDE)     ; $F8 — its row base
  sta EffectIdx
  clc
  adc #BOARD_W
  sta EffectEnd                 ; One past the row's last playfield cell
@Row:
  ldx EffectIdx
  jsr EffectHit
  inc EffectIdx
  lda EffectIdx
  cmp EffectEnd
  bcc @Row

  lda EffectArg                 ; The column, row 0 downward
  sta EffectIdx
@Col:
  ldx EffectIdx
  jsr EffectHit
  lda EffectIdx
  clc
  adc #BOARD_STRIDE
  sta EffectIdx
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Col
  rts

; -----------------------------------------------------------------------------
;   EffectBomb — the 3 x 3 block centred on the bomb, clipped at the edges
;   In:  X = board index
;   Out: nothing.  Modifies: A, X, Y, Effect*, Tmp0, Tmp1, Marks, Cascade*
;   SPEC 7.3 — up to 9 cells, and the reagent most likely to catch another.
;
;   BOTH SPANS ARE CLIPPED, and the row span has to be: row 0 minus one row is
;   index minus 8, which underflows a byte and reads the BSS in front of a
;   page-aligned Board. The column span could lean on the sentinels the way
;   every other walk in the game does — except at row 0, column 0, where
;   "one to the left" is index $FF and off the end of the board. Clipping both
;   is smaller than special-casing one corner.
;
;   Tmp0 and Tmp1 are finished with before the first JSR, which is what the
;   rule about them says (zeropage.inc).
; -----------------------------------------------------------------------------
EffectBomb:
  txa                           ; --- the column span ---
  and #(BOARD_STRIDE - 1)
  tay
  beq @Left                     ; Column 0 — the block starts there
  dey
@Left:
  sty Tmp0                      ; First column of the block
  txa
  and #(BOARD_STRIDE - 1)
  cmp #(BOARD_W - 1)
  bcs @Right                    ; Already against the right wall
  adc #1                        ; C is clear — the CMP above failed
@Right:
  sta EffectArg                 ; Last column of the block

  txa                           ; --- the row span ---
  and #(256 - BOARD_STRIDE)
  sta Tmp1                      ; The bomb's own row base
  beq @Top                      ; Row 0 — the block starts there
  sec
  sbc #BOARD_STRIDE
@Top:
  clc
  adc Tmp0
  sta EffectRow                 ; First cell of the block's first row

  lda Tmp1
  cmp #((BOARD_H - 1) * BOARD_STRIDE)
  bcs @Bottom                   ; Row 15 — the block ends there
  clc
  adc #BOARD_STRIDE
@Bottom:
  clc
  adc Tmp0
  sta EffectEnd                 ; First cell of the block's LAST row

@Rows:
  lda EffectRow
  sta EffectIdx
@Cell:
  ldx EffectIdx
  jsr EffectHit
  lda EffectIdx
  and #(BOARD_STRIDE - 1)
  cmp EffectArg
  inc EffectIdx                 ; INC touches N and Z only, so the CMP's carry
  bcc @Cell                     ;   is still the one being branched on

  lda EffectRow
  cmp EffectEnd
  bcs @Done                     ; That was the last row of the block
  clc
  adc #BOARD_STRIDE
  sta EffectRow
  bne @Rows                     ; Always — a row base past the first is >= 8
@Done:
  rts

; -----------------------------------------------------------------------------
;   EffectStar — removes nothing; it multiplies (SPEC 7.3)
;   Out: nothing.  Modifies: A
;
;   The cap is not applied here. SPEC 9.6 doubles the WHOLE cascade up to three
;   times at the end, so the count has to survive to CascadeSettle, which is
;   where min(StarCount, STAR_SHIFT_CAP) is taken. A cascade cannot remove more
;   than the 96 cells of the well, so the count cannot wrap on its way there.
; -----------------------------------------------------------------------------
EffectStar:
  inc StarCount
  lda #SFX_STAR
  sta SfxRequest
  rts

; -----------------------------------------------------------------------------
;   EffectPrism — removes nothing; a flat bonus per prism cleared (SPEC 9.5)
;   Out: nothing.  Modifies: A, X
;
;   It goes through CascadeAdd and not ScoreAward, so a star in the same
;   cascade doubles it: SPEC 9.6 exempts only the soft drop and the level
;   bonus from the multiplier (D5, D18).
; -----------------------------------------------------------------------------
EffectPrism:
  lda #SFX_PRISM
  sta SfxRequest
  lda #<BONUS_PRISM
  ldx #>BONUS_PRISM
  jmp CascadeAdd

; -----------------------------------------------------------------------------
;   The effect queue — a ring of board indices, one byte an entry.
;
;   The board still holds every pending reagent when its entry pops, because
;   nothing is zeroed until step 6, so the glyph and the colour SPEC 8 packs
;   into the entry are one `lda Board,x` away and storing them again would be
;   storing a copy of the board (constants.inc).
;
;   Head and tail are entry numbers; the ring keeps one slot free, so it holds
;   EFFECTQ_ENTRIES - 1. On overflow the effect is DROPPED and the cascade
;   carries on (D6) — the cell is still marked, still scored and still removed,
;   it simply does not detonate. With at most one reagent a piece, 47 pending
;   detonations is not somewhere a real board goes.
; -----------------------------------------------------------------------------
EffectQClear:
  lda #0
  sta EffectQHead
  sta EffectQTail
  rts

; -----------------------------------------------------------------------------
;   EffectQPush — In: A = board index.  Modifies: A, X, Y
; -----------------------------------------------------------------------------
EffectQPush:
  ldx EffectQTail
  ldy EffectQTail
  iny
  cpy #EFFECTQ_ENTRIES
  bcc @Store
  ldy #0                        ; Wrap
@Store:
  cpy EffectQHead
  beq @Full                     ; One slot free is the ring being full
  sta EffectQ,x
  sty EffectQTail
@Full:
  rts

; -----------------------------------------------------------------------------
;   EffectQPop — Out: C set and A = board index; C clear when empty
;   Modifies: A, X
; -----------------------------------------------------------------------------
EffectQPop:
  ldx EffectQHead
  cpx EffectQTail
  beq @Empty
  lda EffectQ,x
  inx
  cpx #EFFECTQ_ENTRIES
  bcc @Store
  ldx #0                        ; Wrap
@Store:
  stx EffectQHead
  sec
  rts
@Empty:
  clc
  rts
