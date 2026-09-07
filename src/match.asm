; =============================================================================
;   match.asm — Wizards Lab, the match scanner
; =============================================================================
;   SPEC.md section 6. Four passes — horizontal, vertical, and both diagonals —
;   each walking its axis and tracking a run colour and length. A run of three
;   or more sets the MARK bit for each of its cells.
;
;   Colour comparison is the whole trick:
;
;       lda cell
;       and #COLOR_MASK         ; the low three bits are the glyph, ignore them
;       cmp ScanColor
;
;   which is why a red potion, a red fireball and a red star all match. The
;   glyph decides what happens on removal, never whether cells match.
;
;   Wildcards (SPEC 6.3): a WILD cell continues any run. If the run has no
;   colour yet it stays unset and is adopted from the first non-wild cell, so
;   one prism can close a red horizontal run and a blue vertical run at once.
;
;   THE FOUR PASSES ARE ONE LOOP. A line is a start cell and a step, and the
;   step is the only thing that differs: +1 across, +8 down, +9 down-right,
;   +7 down-left. Every one of them ends on a sentinel rather than on a bounds
;   check, which is what the 8-byte stride was bought for (SPEC 3.2):
;
;     across   from column 5, +1 lands on column 6      — wall
;     down     from row 15,   +8 lands on row 16        — wall row
;     down-r   from column 5, +9 lands on row+1 col 6   — wall
;     down-l   from column 0, +7 lands on THIS row's column 7 — wall
;
;   The last one is the reason the left edge needs no test either: the byte
;   before column 0 belongs to the row above, and it is already a wall.
; =============================================================================

; -----------------------------------------------------------------------------
;   MatchScan — find every run on the board
;   In:  nothing
;   Out: Marks filled, RunCount set, Z set if nothing matched.
;        Modifies: A, X, Y, Scan*
; -----------------------------------------------------------------------------
MatchScan:
  jsr MarksClear
  lda #0
  sta RunCount

  jsr ScanFindTop               ; Everything below skips the empty air above
  lda ScanTop                   ;   the pile, which on most boards is most of
  cmp #(BOARD_H * BOARD_STRIDE) ;   the board
  bcs @Done                     ; Nothing on the board at all

  jsr MatchScanHorizontal
  jsr MatchScanVertical
  jsr MatchScanDiagonal
  jsr MatchScanAntiDiagonal
@Done:
  lda RunCount                  ; Z set when nothing matched
  rts

; -----------------------------------------------------------------------------
;   ScanFindTop — board index of the first row that holds anything
;   Out: ScanTop = row base, or BOARD_H * BOARD_STRIDE if the board is empty.
;        Modifies: A, X, ScanTop
;
;   Every pass below starts here instead of at row 0. A pile six rows deep is
;   scanned as six rows: 178 cells against 448, and the four passes come in
;   under a third of the frame instead of over two whole ones. Finding it costs
;   about 45 cycles a row of empty air, which is the cheapest part of the scan.
;
;   Correct as well as quick, and for a reason worth writing down: a line that
;   reaches the pile at all must CROSS the pile's top row, because every one of
;   the four steps moves down at most one row at a time. Starting the diagonals
;   on that row rather than on row 0 therefore misses nothing.
; -----------------------------------------------------------------------------
ScanFindTop:
  ldx #0
@Row:
  lda Board + 0,x               ; The six playfield columns; the two sentinel
  ora Board + 1,x               ;   ones would make every row look occupied
  ora Board + 2,x
  ora Board + 3,x
  ora Board + 4,x
  ora Board + 5,x
  bne @Found
  txa
  clc
  adc #BOARD_STRIDE
  tax
  cpx #(BOARD_H * BOARD_STRIDE)
  bcc @Row
@Found:
  stx ScanTop
  rts

; -----------------------------------------------------------------------------
;   The four passes (SPEC 6.2). Each sets a step and hands ScanLine its start
;   cells; the start cell rides the stack because ScanLine needs both index
;   registers and the scratch bytes below it.
; -----------------------------------------------------------------------------
MatchScanHorizontal:            ; Every row of the pile, column 0 rightward
  lda #1
  sta ScanStep
  lda ScanTop
@Line:
  pha
  jsr ScanLine
  pla
  clc
  adc #BOARD_STRIDE
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Line
  rts

MatchScanVertical:              ; 6 columns, top of the pile downward
  lda #BOARD_STRIDE
  sta ScanStep
  jmp ScanTopRow

MatchScanDiagonal:              ; down-right: the top row, then the left edge
  lda #(BOARD_STRIDE + 1)
  sta ScanStep
  jsr ScanTopRow
  lda #0
  jmp ScanEdgeColumn

MatchScanAntiDiagonal:          ; down-left: the top row, then the right edge
  lda #(BOARD_STRIDE - 1)
  sta ScanStep
  jsr ScanTopRow
  lda #(BOARD_W - 1)
  jmp ScanEdgeColumn

; -----------------------------------------------------------------------------
;   ScanTopRow — scan a line from each of the six cells of the pile's top row
;   ScanEdgeColumn — and from the rows below it, in the column in A
;   In:  ScanStep set, ScanTop set; A = column (ScanEdgeColumn only)
;
;   Between them those are every start cell a diagonal needs, and the top row
;   alone is every start cell the vertical pass needs. The top row is scanned
;   by the first, so the second skips it rather than scanning the longest
;   diagonal twice.
; -----------------------------------------------------------------------------
ScanTopRow:
  lda ScanTop
@Line:
  pha
  jsr ScanLine
  pla
  clc
  adc #1
  pha                           ; Six columns of that row, whichever row it
  and #(BOARD_STRIDE - 1)       ;   is, so it is the COLUMN that ends the loop
  cmp #BOARD_W                  ;   and not the index
  pla                           ; PLA leaves C alone
  bcc @Line
  rts

ScanEdgeColumn:
  clc
  adc ScanTop                   ; That column, on the pile's top row...
  clc
  adc #BOARD_STRIDE             ;   ...and then the row below it
  cmp #(BOARD_H * BOARD_STRIDE)
  bcs @Done                     ; The pile is one row deep — there is no below
@Line:
  pha
  jsr ScanLine
  pla
  clc
  adc #BOARD_STRIDE
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Line
@Done:
  rts

; -----------------------------------------------------------------------------
;   ScanLine — walk one line, marking every run of MATCH_MIN or more
;   In:  A = start board index, ScanStep = direction
;   Out: nothing.  Modifies: A, X, Scan*, Marks, RunCount
;
;   ONLY A WALL ENDS THE LINE. A hole in the middle of a row breaks the run
;   and the walk carries on past it, because the cells beyond it are a run of
;   their own — a line that stopped at the first empty cell would never look
;   below the top of the pile at all, which is very nearly the whole board.
;
;   A colour change ends the run and starts a new one at the cell that broke
;   it — the cell that broke a red run is the first cell of the blue one, and
;   any prisms that were riding the red run stay with the red run. SPEC 6.3
;   gives a wildcard to the run it is already in, not to both.
; -----------------------------------------------------------------------------
ScanLine:
  tax                           ; The cursor lives in X for the whole line:
  lda #$FF                      ;   this loop runs about four hundred times a
  sta ScanColor                 ;   scan and every cycle in it is four hundred
  lda #0                        ;   cycles of the frame
  sta ScanLen

@Cell:
  lda Board,x
  beq @Gap                      ; A hole breaks the run, not the line
  cmp #TILE_WALL
  beq @End                      ; A wall is where the line stops
  and #COLOR_MASK               ; The colour key, glyph discarded (SPEC 4.2)
  cmp ScanColor
  beq @Grow                     ; Same colour — the commonest case, first
  cmp #WILD_BASE
  beq @Grow                     ; A prism continues any run (SPEC 6.3)

  tay                           ; A different colour. Park it: everything
  lda ScanColor                 ;   below either adopts it or starts a run
  bmi @Adopt                    ;   with it. $FF is the only value here with
                                ;   bit 7 set — colours are $40 to $70
  lda ScanLen
  cmp #MATCH_MIN
  bcs @Close                    ; The run it broke was long enough to mark

  sty ScanColor                 ; It was not, so no call and no marking: this
  lda #1                        ;   cell is simply the start of the next run.
  sta ScanLen                   ;   Five adjacent cells in six differ in
  bne @Advance                  ;   colour, so this is the path that decides
                                ;   what a scan costs
@Adopt:
  sty ScanColor
@Grow:
  inc ScanLen
@Advance:
  txa
  clc
  adc ScanStep
  tax
  jmp @Cell

@Close:
  stx ScanIdx
  jsr MatchEmit                 ; Mark it — and MatchEmit leaves ScanLen zero
  ldx ScanIdx
  lda Board,x
  and #COLOR_MASK
  sta ScanColor
  lda #1
  sta ScanLen
  bne @Advance                  ; Always

@Gap:
  lda ScanLen
  beq @Advance                  ; Nothing running — step over the hole. This
                                ;   is the cell the scan meets most often, so
                                ;   it is the one that must not call anything
  stx ScanIdx
  jsr MatchEmit                 ; Close the run the hole broke...
  ldx ScanIdx
  lda #$FF
  sta ScanColor                 ;   ...and start again on the far side of it
  lda #0
  sta ScanLen
  beq @Advance                  ; Always

@End:
  lda ScanLen
  beq @Nothing                  ; The line ran out with nothing in hand
  stx ScanIdx
  jmp MatchEmit                 ; Whatever was running ends with the line
@Nothing:
  rts

; -----------------------------------------------------------------------------
;   MatchEmit — a run has ended; mark it if it was long enough
;   In:  ScanIdx = one cell PAST the run's last, ScanLen, ScanColor, ScanStep
;   Out: nothing.  Modifies: A, X, Y, ScanEnd, ScanLen, RunCount, Marks
;
;   Runs are marked, not removed: a cell can be in a horizontal run and a
;   vertical one at once, and it clears once while both runs score (SPEC 6.1).
;   The union is what the MARKS bitmap is for.
;
;   P4 SCORES HERE. ScanLen and ScanColor still describe the run at the point
;   RunCount is bumped, which is the only moment they do — the mark loop below
;   counts ScanLen down to zero on its way back along the line.
; -----------------------------------------------------------------------------
MatchEmit:
  lda ScanLen
  cmp #MATCH_MIN
  bcc @Done                     ; Two in a row is not a run

  inc RunCount
  lda ScanIdx
  sec
  sbc ScanStep                  ; Back onto the run's last cell
  sta ScanEnd
@Mark:
  lda ScanEnd
  jsr MarkSet
  lda ScanEnd
  sec
  sbc ScanStep
  sta ScanEnd
  dec ScanLen
  bne @Mark
@Done:
  rts

; -----------------------------------------------------------------------------
;   MarksClear / MarkSet / MarkTest — the 16-byte bitmap
;   One byte per row, bits 0-5 = columns 0-5. Union of runs is a free ORA.
;
;   MarkBits has eight entries rather than six so that the two sentinel
;   columns index it harmlessly: bits 6 and 7 of a Marks byte are never set,
;   so a walk over the whole 8-byte stride can test every cell it meets
;   without first asking whether the cell is a wall.
; -----------------------------------------------------------------------------
MarkBits:
  .byte $01, $02, $04, $08, $10, $20, $40, $80

MarksClear:
  lda #0
  ldx #0
@Row:
  sta Marks,x
  inx
  cpx #MARKS_BYTES
  bne @Row
  rts

MarkSet:                        ; In: A = board index.  Modifies: A, X, Y
  tax
  and #(BOARD_STRIDE - 1)
  tay                           ; Y = column
  txa
  lsr a
  lsr a
  lsr a
  tax                           ; X = row
  lda Marks,x
  ora MarkBits,y
  sta Marks,x
  rts

MarkTest:                       ; In: A = board index.  Out: C set if marked
  tax                           ;     Modifies: A, X, Y
  and #(BOARD_STRIDE - 1)
  tay
  txa
  lsr a
  lsr a
  lsr a
  tax
  lda Marks,x
  and MarkBits,y
  beq @No
  sec
  rts
@No:
  clc
  rts
