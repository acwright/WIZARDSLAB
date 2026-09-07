; =============================================================================
;   render.asm — Wizards Lab, the dirty-cell renderer
; =============================================================================
;   SPEC.md section 12.6. The screen is never fully redrawn during play.
;   Changed cells are appended to a ring and flushed once a frame, at most
;   DIRTY_FLUSH_MAX per frame with the remainder carried over.
;
;   The cap is NOT a hardware write-spacing limit. S1 measured this loop at
;   165 cycles a cell on the AC6502, which puts two VRAM data writes 165 us
;   apart at 1 MHz and the closest two VDP PORT accesses 8 cycles apart —
;   inside even a real TMS9918A's 8 us and 2 us windows with two orders of
;   magnitude to spare, and further inside a pico9918's, which emulates VRAM
;   in RP2040 memory and has no display contention at all. A 6502 at this
;   clock cannot write a TMS9918 too fast however hard it tries.
;
;   The cap is a TIME BUDGET: DIRTY_FLUSH_MAX cells is what fits in vertical
;   blank on the tightest of the three. See constants.inc and PLAN.md S1.
;
;   All screen access goes through HalPlotCell (see hal.inc). Nothing in this
;   file knows where screen memory is.
; =============================================================================

; -----------------------------------------------------------------------------
;   RenderDirtyReset — empty the ring and cancel any outstanding board redraw
;   Call this after anything that draws the whole screen behind the renderer's
;   back (HalBlitScreen), because every queued cell then describes a screen
;   that no longer exists.
;   In:  nothing        Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
RenderDirtyReset:
  lda #0
  sta DirtyCount
  sta DirtyHead
  sta DirtyTail
  lda #$FF
  sta RedrawIdx
  rts

; -----------------------------------------------------------------------------
;   RenderMark — queue one panel cell
;   In:  A = tile, X = panel column, Y = panel row
;   Out: nothing.  Modifies: A, X.  PRESERVES Y and every byte of zero page.
;
;   The PANEL_X / PANEL_Y offset is applied here, once, so nothing upstream
;   has to know which machine it is running on.
;
;   Preserving Y and zero page is a contract, not an accident: text.asm holds
;   its string cursor across this call (see zeropage.inc). The three values
;   ride the stack rather than scratch bytes because A, X and Y are all live
;   at once and there is no fourth register to index the ring with.
;
;   A mark that arrives with the ring full is DROPPED, silently (D6).
; -----------------------------------------------------------------------------
RenderMark:
  pha                           ; Tile
  tya
  clc
  adc #PANEL_Y                  ; Panel row -> screen row
  pha
  txa
  clc
  adc #PANEL_X                  ; Panel column -> screen column
  pha

  lda DirtyCount
  cmp #DIRTY_ENTRIES
  bcs @Full
  inc DirtyCount

  ldx DirtyTail
  pla
  sta Dirty+0,x                 ; Screen column
  pla
  sta Dirty+1,x                 ; Screen row
  pla
  sta Dirty+2,x                 ; Tile

  inx                           ; Step one entry, wrapping the ring
  inx
  inx
  cpx #DIRTY_BYTES
  bcc @Store
  ldx #0
@Store:
  stx DirtyTail
  rts

@Full:
  pla                           ; Unwind and drop it. The cell is wrong until
  pla                           ;   something marks it again.
  pla
  rts

; -----------------------------------------------------------------------------
;   RenderFlush — push up to DIRTY_FLUSH_MAX queued cells to the screen
;   Called once per frame, from the top of the main loop.
;   In:  nothing        Out: nothing.  Modifies: A, X, Y, Ptr1, Ptr2
; -----------------------------------------------------------------------------
RenderFlush:
  jsr RenderBoardStep           ; Top the ring up from a board redraw, if one
                                ;   is outstanding, so it always makes progress
  lda DirtyCount
  beq @Done
  cmp #DIRTY_FLUSH_MAX
  bcc @Budget
  lda #DIRTY_FLUSH_MAX
@Budget:
  sta FlushLeft

@Cell:
  ldx DirtyHead
  lda Dirty+1,x
  tay                           ; Y = screen row
  lda Dirty+2,x
  pha                           ; Tile
  lda Dirty+0,x
  tax                           ; X = screen column
  pla                           ; A = tile
  jsr HalPlotCell

  lda DirtyHead                 ; Step one entry, wrapping the ring
  clc
  adc #3
  cmp #DIRTY_BYTES
  bcc @Store
  lda #0
@Store:
  sta DirtyHead
  dec DirtyCount
  dec FlushLeft
  bne @Cell
@Done:
  rts

; -----------------------------------------------------------------------------
;   RenderBoard — ask for the whole 6 x 16 well to be redrawn
;   Used on state entry and after a pause, not per frame.
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;
;   The well is 96 cells and the ring holds DIRTY_ENTRIES; a redraw therefore
;   cannot be queued in one go. This only sets the cursor. RenderBoardStep,
;   which RenderFlush calls every frame, feeds the ring as fast as it drains,
;   so the redraw spreads over as many frames as it needs and never drops a
;   cell.
; -----------------------------------------------------------------------------
RenderBoard:
  lda #0
  sta RedrawIdx                 ; Board index 0 = row 0, column 0
  rts                           ; And nothing else. Falling through into the
                                ;   step below would fill the ring here and
                                ;   drop whatever the caller marks next.

; -----------------------------------------------------------------------------
;   RenderBoardStep — queue as much of an outstanding board redraw as fits
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;   Does nothing when RedrawIdx is $FF.
; -----------------------------------------------------------------------------
RenderBoardStep:
  lda RedrawIdx
  bmi @Done                     ; $FF — nothing outstanding

@Cell:
  lda DirtyCount
  cmp #DIRTY_ENTRIES
  bcs @Done                     ; Ring full — pick this cell up next frame

  ldx RedrawIdx
  txa
  and #(BOARD_STRIDE - 1)
  clc
  adc #WELL_ORIGIN_X
  sta RedrawCol
  txa
  lsr a                         ; Board index >> 3 is the row (stride 8)
  lsr a
  lsr a
  clc
  adc #WELL_ORIGIN_Y
  tay                           ; Y = panel row
  lda Board,x                   ; The board byte IS the tile — empty is $00,
  ldx RedrawCol                 ;   which is TILE_BLANK (SPEC 3.3, 4.2)
  jsr RenderMark

  ldx RedrawIdx                 ; Advance, stepping over the two sentinel
  inx                           ;   columns at the end of each row
  txa
  and #(BOARD_STRIDE - 1)
  cmp #BOARD_W
  bcc @Save
  txa
  clc
  adc #(BOARD_STRIDE - BOARD_W)
  tax
@Save:
  cpx #(BOARD_H * BOARD_STRIDE)
  bcs @Finish
  stx RedrawIdx
  jmp @Cell

@Finish:
  lda #$FF
  sta RedrawIdx
@Done:
  rts

; -----------------------------------------------------------------------------
;   RenderCell — queue one board cell by board index
;   In:  X = board index (row * BOARD_STRIDE + column)
;   Out: nothing.  Modifies: A, X, Y
;   The single-cell form of RenderBoardStep, for the phases that move one tile
;   at a time.
; -----------------------------------------------------------------------------
RenderCell:
  txa
  and #(BOARD_STRIDE - 1)
  clc
  adc #WELL_ORIGIN_X
  sta RedrawCol
  txa
  lsr a
  lsr a
  lsr a
  clc
  adc #WELL_ORIGIN_Y
  tay
  lda Board,x
  ldx RedrawCol
  jmp RenderMark

; -----------------------------------------------------------------------------
;   RenderPiece — queue the three falling cells at where the piece is now
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;
;   RenderMark clobbers X and keeps Y, so the panel column is parked in
;   RedrawCol and the panel row rides Y down the three cells. Cell C can never
;   be lower than board row 15, so all three are always inside the well and
;   there is nothing to clip.
; -----------------------------------------------------------------------------
RenderPiece:
  lda PieceCol
  clc
  adc #WELL_ORIGIN_X
  sta RedrawCol
  lda PieceRow
  clc
  adc #WELL_ORIGIN_Y
  tay
  lda PieceA
  ldx RedrawCol
  jsr RenderMark
  iny
  lda PieceB
  ldx RedrawCol
  jsr RenderMark
  iny
  lda PieceC
  ldx RedrawCol
  jmp RenderMark

; -----------------------------------------------------------------------------
;   RenderPieceErase — blank the three cells the piece is leaving
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;
;   Three blanks rather than three board reads, because the cells under a
;   falling piece are always empty: every move and every gravity step tests
;   the target cells before it happens, and the one thing that writes them is
;   PieceLock, after which nothing erases the piece again (piece.asm).
; -----------------------------------------------------------------------------
RenderPieceErase:
  lda PieceCol
  clc
  adc #WELL_ORIGIN_X
  sta RedrawCol
  lda PieceRow
  clc
  adc #WELL_ORIGIN_Y
  tay
  lda #TILE_EMPTY
  ldx RedrawCol
  jsr RenderMark
  iny
  lda #TILE_EMPTY
  ldx RedrawCol
  jsr RenderMark
  iny
  lda #TILE_EMPTY
  ldx RedrawCol
  jmp RenderMark

; -----------------------------------------------------------------------------
;   RenderNext — the preview, panel column NEXT_X, rows NEXT_Y..NEXT_Y+2
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
;
;   All three cells every time. The play screen image ships with a piece
;   already drawn in the NEXT box (SPEC 12.1), so this has to overwrite rather
;   than assume it is drawing onto backdrop.
; -----------------------------------------------------------------------------
RenderNext:
  ldy #NEXT_Y
  lda NextA
  ldx #NEXT_X
  jsr RenderMark
  iny
  lda NextB
  ldx #NEXT_X
  jsr RenderMark
  iny
  lda NextC
  ldx #NEXT_X
  jmp RenderMark

; -----------------------------------------------------------------------------
;   RenderScore / RenderHigh / RenderLevel — only called when a value changes
;   Nothing here compares anything: the caller knows when it changed a value
;   and these are not cheap enough to run every frame. SCORE_DIGITS cells is
;   most of a frame's flush budget on its own.
; -----------------------------------------------------------------------------
RenderScore:
  lda #<ScoreLo
  sta Ptr1
  lda #>ScoreLo
  sta Ptr1+1
  ldx #SCORE_X
  ldy #SCORE_Y
  lda #SCORE_DIGITS
  jmp TextBcd

RenderHigh:
  lda #<HighLo
  sta Ptr1
  lda #>HighLo
  sta Ptr1+1
  ldx #HIGH_X
  ldy #HIGH_Y
  lda #SCORE_DIGITS
  jsr TextBcd

  lda #<HighLevel               ; The level it was set on, under the digits
  sta Ptr1
  lda #>HighLevel
  sta Ptr1+1
  ldx #HIGHLVL_X
  ldy #HIGHLVL_Y
  lda #LEVEL_DIGITS
  jmp TextBcd

; -----------------------------------------------------------------------------
;   RenderHighBlank — the dark half of the HIGH field's overtake flash
;   In:  nothing        Out: nothing.  Modifies: A, X, Y, TextCol
;   SPEC 9.8. The seven digits only; the level under them stays put, so the
;   box never looks empty and the flash costs seven cells of the budget.
; -----------------------------------------------------------------------------
RenderHighBlank:
  lda #HIGH_X
  sta TextCol                   ; Not X: RenderMark clobbers it
@Cell:
  lda #TILE_BLANK
  ldx TextCol
  ldy #HIGH_Y
  jsr RenderMark
  inc TextCol
  lda TextCol
  cmp #(HIGH_X + SCORE_DIGITS)
  bcc @Cell
  rts

RenderLevel:
  lda Level
  jmp TextLevel
