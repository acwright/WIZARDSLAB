; =============================================================================
;   render.asm — Wizards Lab, the dirty-cell renderer
; =============================================================================
;   SPEC.md section 12.6. The screen is never fully redrawn during play.
;   Changed cells are appended to a list and flushed during vertical blank,
;   at most DIRTY_FLUSH_MAX per frame with the remainder carried over.
;
;   The cap exists for the AC6502, where every cell is a VDP port write with a
;   minimum spacing between writes. The Commodores would not need it, but they
;   use the same path so the game runs at one speed everywhere.
;
;   All screen access goes through HalPlotCell (see hal.inc). Nothing in this
;   file knows where screen memory is.
; =============================================================================

; -----------------------------------------------------------------------------
;   RenderDirtyReset / RenderMark / RenderFlush
; -----------------------------------------------------------------------------
RenderDirtyReset:
  lda #0
  sta DirtyCount
  sta DirtyFlushed
  rts

; -----------------------------------------------------------------------------
;   RenderMark — queue one panel cell
;   In:  A = tile, X = panel column, Y = panel row
;   The PANEL_X / PANEL_Y offset is applied here, once, so nothing upstream
;   has to know which machine it is running on.
; -----------------------------------------------------------------------------
RenderMark:
  ; TODO: append (screen offset, tile) to Dirty; drop silently when full —
  ; a dropped cell is corrected by the next redraw of that cell.
  rts

; -----------------------------------------------------------------------------
;   RenderFlush — push up to DIRTY_FLUSH_MAX queued cells to the screen
;   Called once per frame, inside vertical blank.
; -----------------------------------------------------------------------------
RenderFlush:
  ; TODO: walk Dirty from DirtyFlushed, calling HalPlotCell, stopping at the
  ; cap and remembering where to resume.
  rts

; -----------------------------------------------------------------------------
;   RenderBoard — queue the whole 6 x 16 well
;   Used on state entry and after a pause, not per frame.
; -----------------------------------------------------------------------------
RenderBoard:
  rts

; -----------------------------------------------------------------------------
;   RenderPiece / RenderPieceErase — the three falling cells
; -----------------------------------------------------------------------------
RenderPiece:
  rts

RenderPieceErase:
  rts

; -----------------------------------------------------------------------------
;   RenderNext — the preview, panel column NEXT_X, rows NEXT_Y..NEXT_Y+2
; -----------------------------------------------------------------------------
RenderNext:
  rts

; -----------------------------------------------------------------------------
;   RenderScore / RenderHigh / RenderLevel — only called when a value changes
; -----------------------------------------------------------------------------
RenderScore:
  rts

RenderHigh:
  rts

RenderLevel:
  rts
