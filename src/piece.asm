; =============================================================================
;   piece.asm — Wizards Lab, the falling piece
; =============================================================================
;   SPEC.md section 5. A piece is three independently generated cells stacked
;   vertically, A on top. At most one of the three carries a reagent, which is
;   enforced by rolling once for the piece rather than once per cell.
; =============================================================================

; -----------------------------------------------------------------------------
;   PieceGenerateNext — roll the preview piece into NextA/NextB/NextC
;   In:  nothing (reads Level)
;   Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2
;   SPEC 5.2, 5.3 — colours uniform over 0-5, then one reagent roll.
; -----------------------------------------------------------------------------
PieceGenerateNext:
  ; TODO: three RngNext calls for colours; one against PSpecial[LevelBand];
  ; on a hit pick a cell and a type from ReagentThresholds. A Prism overwrites
  ; the cell's colour with COLOR_WILD.
  rts

; -----------------------------------------------------------------------------
;   PieceSpawn — promote the preview to the falling piece
;   In:  nothing
;   Out: C set if the spawn cells were occupied (game over)
;   SPEC 5.4 — spawn column SPAWN_COL, rows 0-2, visible immediately.
; -----------------------------------------------------------------------------
PieceSpawn:
  ; TODO
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceMoveLeft / PieceMoveRight
;   Out: C set if the move happened (the caller resets the lock timer).
;   SPEC 5.5 — no wall kicks; a 1-wide piece has nothing to kick off.
; -----------------------------------------------------------------------------
PieceMoveLeft:
  clc
  rts

PieceMoveRight:
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceRotate / PieceRotateBack — cycle the three cells
;   SPEC 5.5 — (A,B,C) -> (B,C,A) forward, (C,A,B) back. Always succeeds.
; -----------------------------------------------------------------------------
PieceRotate:
  rts

PieceRotateBack:
  rts

; -----------------------------------------------------------------------------
;   PieceStep — one row of gravity
;   Out: C set if the piece has landed and the lock delay should start.
; -----------------------------------------------------------------------------
PieceStep:
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceLock — write the three cells into the board
;   SPEC 5.6 — after this the caller runs a cascade.
; -----------------------------------------------------------------------------
PieceLock:
  rts
