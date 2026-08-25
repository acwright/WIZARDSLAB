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
;   In:  nothing        Out: nothing.  Modifies: A, X, Y
; -----------------------------------------------------------------------------
BoardClear:
  ; TODO: fill rows 0-15 columns 0-5 with TILE_EMPTY, everything else $FF.
  rts

; -----------------------------------------------------------------------------
;   BoardRowPtr — point Ptr1 at the start of a board row
;   In:  A = row        Out: Ptr1 = &Board[row][0].  Modifies: A, Ptr1
; -----------------------------------------------------------------------------
BoardRowPtr:
  ; TODO: asl x3, add to <Board, high byte is >Board (the board is page-aligned
  ; and 160 bytes, so it never crosses a page — the add cannot carry).
  rts

; -----------------------------------------------------------------------------
;   BoardGravity — compact every column downward
;   In:  nothing
;   Out: C set if anything moved.  Modifies: A, X, Y, Ptr1, Tmp0-Tmp2
;   SPEC 8 step 8.
; -----------------------------------------------------------------------------
BoardGravity:
  ; TODO: per column, walk bottom to top with a write cursor; mark moved cells
  ; dirty as they go.
  clc
  rts
