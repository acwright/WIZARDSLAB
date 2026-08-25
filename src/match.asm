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
; =============================================================================

; -----------------------------------------------------------------------------
;   MatchScan — find every run on the board
;   In:  nothing
;   Out: Marks filled, RunCount set, Z set if nothing matched.
;        Modifies: A, X, Y, Ptr1, Ptr2, Scan*
; -----------------------------------------------------------------------------
MatchScan:
  ; TODO: MarksClear, then the four passes below, accumulating RunCount and
  ; the per-run (length, colour) pairs the scorer needs.
  lda #0
  sta RunCount
  rts

MatchScanHorizontal:
  rts

MatchScanVertical:
  rts

MatchScanDiagonal:                ; down-right
  rts

MatchScanAntiDiagonal:            ; down-left
  rts

; -----------------------------------------------------------------------------
;   MarksClear / MarkSet / MarkTest — the 16-byte bitmap
;   One byte per row, bits 0-5 = columns 0-5. Union of runs is a free ORA.
; -----------------------------------------------------------------------------
MarksClear:
  rts

MarkSet:                          ; In: X = row, Y = column
  rts

MarkTest:                         ; In: X = row, Y = column.  Out: C = marked
  clc
  rts
