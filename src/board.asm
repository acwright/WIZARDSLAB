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
;
;   The wall loop counts UP and ends on a CPX. Counting down from 159 to a BPL
;   looks tidier and is wrong: 159 is $9F, bit 7 already set, so the branch
;   falls through after the first store and the other 159 bytes keep whatever
;   the machine powered up with. That went unnoticed for a whole phase,
;   because nothing read a sentinel until the falling piece needed a floor.
; -----------------------------------------------------------------------------
BoardClear:
  lda #TILE_WALL
  ldx #0
@Wall:
  sta Board,x
  inx
  cpx #BOARD_BYTES
  bne @Wall

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
;   BoardGravityBegin / BoardGravityStep — the pile falls, one row at a time
;   SPEC 8 step 8, SPEC 14: tiles descend one row every FALL_FRAMES.
;
;   A row of falling is one pass over the board, bottom to top, moving every
;   tile that has an empty cell under it down into it. Repeat until a pass
;   moves nothing and the columns are compacted — but repeat it a row at a
;   time, because the fall is animated and a column that dropped four rows in
;   one frame would read as a teleport.
;
;   Walking BOTTOM TO TOP is what makes a whole column fall together rather
;   than one tile a frame: by the time the pass reaches a tile, the tile below
;   it has already moved and left the gap.
;
;   The pass is a CURSOR, not a loop that runs to completion (D12, SPEC 12.6).
;   Sixty tiles falling is a hundred-odd changed cells and the dirty ring holds
;   64, so the pass stops when the ring is full and picks up where it stopped
;   next frame. Nothing is dropped and the board is a legal board at every
;   point it stops — one frame's worth of columns has fallen a row and the
;   rest has not, which is a stagger nobody can see.
;
;   The two sentinel columns need no special case: a wall's "cell below" is
;   another wall, so columns 6 and 7 never move.
; -----------------------------------------------------------------------------
GRAV_TOP = (BOARD_H - 1) * BOARD_STRIDE - 1     ; The last cell of row 14, the
                                                ;   lowest row that can fall at
                                                ;   all. Row 15 is on the floor
BoardGravityBegin:
  lda #GRAV_TOP
  sta GravIdx
  lda #0
  sta GravMoved
  rts

; -----------------------------------------------------------------------------
;   BoardGravityStep — carry on with the current row of falling
;   In:  nothing
;   Out: C set when the row is finished; GravMoved non-zero if it moved
;        anything. Modifies: A, X, Y, GravIdx, GravMoved, RedrawCol
; -----------------------------------------------------------------------------
BoardGravityStep:
  lda GravIdx
  bmi @Finished                 ; $FF — the row is already done

@Cell:
  lda DirtyCount                ; Room for both cells of a move, or wait for
  cmp #(DIRTY_ENTRIES - 2)      ;   the flush. A mark dropped here would never
  bcs @Later                    ;   be marked again (D6 is survivable only
                                ;   because nothing that MUST land uses it)

  ldx GravIdx
  lda Board,x
  beq @Next                     ; Nothing here to fall
  lda Board + BOARD_STRIDE,x
  bne @Next                     ; Something under it — a tile, or the floor

  lda Board,x                   ; Move it down one row
  sta Board + BOARD_STRIDE,x
  lda #TILE_EMPTY
  sta Board,x
  inc GravMoved

  lda GravIdx                   ; The cell it LEFT only needs redrawing if it
  cmp #BOARD_STRIDE             ;   is going to stay empty. If there is a tile
  bcc @Vacated                  ;   above it, that tile lands here later in
  ldx GravIdx                   ;   this same pass and its own arrival mark
  lda Board - BOARD_STRIDE,x    ;   covers the cell. Half the marks of a
  bne @Arrived                  ;   sliding column, which is what the ring
@Vacated:                       ;   pressure is made of.
  ldx GravIdx
  jsr RenderCell
@Arrived:
  lda GravIdx
  clc
  adc #BOARD_STRIDE
  tax
  jsr RenderCell

@Next:
  dec GravIdx                   ; Down to 0, then $FF, which ends the pass —
  bpl @Cell                     ;   GRAV_TOP is 119, so bit 7 starts clear
                                ;   (see PLAN.md section 3)
@Finished:
  sec
  rts

@Later:
  clc                           ; Ring full: the rest of this row waits a frame
  rts
