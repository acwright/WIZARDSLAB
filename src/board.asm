; =============================================================================
;   board.asm — Wizards Lab, the playfield
; =============================================================================
;   SPEC.md section 3. The board is 20 rows of 8 bytes, page-aligned, with
;   columns 6-7 and rows 16-19 held permanently at $FF. Those sentinels are
;   what let every scan in match.asm run without a bounds check.
;
;   address(row, col) = Board + (row << 3) + col
; =============================================================================

; -----------------------------------------------------------------------------
;   BoardClear — empty the playfield and lay the sentinels back down
;   In:  nothing        Out: nothing.  Modifies: A, X
;
;   Walls first over the whole 160 bytes, then the six playfield columns of
;   the sixteen playfield rows punched back out to empty. Doing it in that
;   order means the sentinels can never be forgotten: everything that is not
;   explicitly playfield is a wall.
; -----------------------------------------------------------------------------
BoardClear:
  lda #TILE_WALL
  ldx #BOARD_BYTES - 1
@Wall:
  sta Board,x
  dex
  bpl @Wall

  ldx #0                        ; X walks the row bases, 0, 8, 16, ...
@Row:
  lda #TILE_EMPTY               ; Reloaded every row: the TXA below eats it
  .repeat BOARD_W, COL
    sta Board + COL, x
  .endrepeat
  txa
  clc
  adc #BOARD_STRIDE
  tax
  cpx #(BOARD_H * BOARD_STRIDE)
  bcc @Row
  rts

; -----------------------------------------------------------------------------
;   BoardRowPtr — point Ptr1 at the start of a board row
;   In:  A = row        Out: Ptr1 = &Board[row][0].  Modifies: A, Ptr1
;
;   Board is page-aligned and 160 bytes, so row * 8 is at most 152 and the low
;   byte can never carry into the high one.
; -----------------------------------------------------------------------------
BoardRowPtr:
  asl a
  asl a
  asl a
  clc
  adc #<Board
  sta Ptr1
  lda #>Board
  sta Ptr1+1
  rts

; -----------------------------------------------------------------------------
;   BoardGravity — compact every column downward
;   In:  nothing
;   Out: C set if anything moved.  Modifies: A, X, Y, Ptr1, Tmp0-Tmp2
;   SPEC 8 step 8.  P3.
; -----------------------------------------------------------------------------
BoardGravity:
  ; TODO: per column, walk bottom to top with a write cursor; mark moved cells
  ; dirty as they go.
  clc
  rts

.ifdef WL_DEBUG
; -----------------------------------------------------------------------------
;   BoardDebugFill — a known pattern, for looking at the render path
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;
;   TEMPORARY (PLAN.md P1). Nothing in the game calls this; it exists so a
;   -DWL_DEBUG build has something in the well to draw, and it is deliberately
;   asymmetric so a transposed row and column, an off-by-one origin or a wrong
;   stride all show up as a picture rather than as a plausible board:
;
;     rows 0-3    empty — the well is not full, and the top edge is visible
;     rows 4-14   a diagonal colour ramp, (row + col) mod 6
;     row 14      column 0 left empty — breaks the diagonal's symmetry
;     row 15      one of every glyph the tileset draws, left to right:
;                 potion, fireball, bolt, bomb, star, then a prism
; -----------------------------------------------------------------------------
BoardDebugFill:
  ldy #4                        ; Y = row
@Row:
  ldx #0                        ; X = column
@Col:
  tya
  stx Tmp0
  clc
  adc Tmp0                      ; row + col
@Mod6:
  cmp #NUM_COLORS
  bcc @Got
  sbc #NUM_COLORS
  bcs @Mod6                     ; Always — sbc left carry set
@Got:
  asl a                         ; colour << 3 + COLOR_BASE
  asl a
  asl a
  clc
  adc #COLOR_BASE
  sta Tmp1

  cpy #BOARD_H - 1              ; Bottom row carries the glyph sampler
  bne @Plain
  txa
  cmp #NUM_COLORS - 1           ; Column 5 is the prism
  bcc @Glyph
  lda #WILD_BASE
  sta Tmp1
  bne @Store                    ; Always — WILD_BASE is non-zero
@Glyph:
  ora Tmp1                      ; Glyphs 0-4 of that cell's own colour
  sta Tmp1
  bne @Store                    ; Always
@Plain:
  cpy #BOARD_H - 2              ; One hole, so the diagonal is not symmetric
  bne @Store
  cpx #0
  bne @Store
  lda #TILE_EMPTY
  sta Tmp1

@Store:
  tya                           ; Board index = row * 8 + column
  asl a
  asl a
  asl a
  stx Tmp0
  clc
  adc Tmp0
  tax
  lda Tmp1
  sta Board,x
  ldx Tmp0

  inx
  cpx #BOARD_W
  bcc @Col
  iny
  cpy #BOARD_H
  bcc @Row
  rts
.endif
