; =============================================================================
;   zeropage.inc — Wizards Lab, zero page allocation
; =============================================================================
;   The ZEROPAGE segment is placed at $40 on every platform. That window is
;   free on all three:
;
;     AC6502   $003A-$00FF free for user programs (6502.inc memory map)
;     VIC-20   all of page zero, once the cartridge stops calling the KERNAL
;     C64      all of page zero EXCEPT $00/$01, which are the processor port
;
;   Starting at $40 clears the C64's port bytes and the AC6502's system
;   scratch with room to spare, and keeps one number in three linker configs.
; =============================================================================

.segment "ZEROPAGE"

Ptr1:           .res 2      ; General pointer — free across any call boundary
Ptr2:           .res 2      ; General pointer
SrcPtr:         .res 2      ; Block copy source
DstPtr:         .res 2      ; Block copy destination
ScreenPtr:      .res 2      ; Current screen row base
ColorPtr:       .res 2      ; Current colour RAM row base (Commodore only)

RngLo:          .res 1      ; 16-bit LFSR state — never both zero
RngHi:          .res 1

Tmp0:           .res 1      ; Scratch. Never live across a JSR.
Tmp1:           .res 1
Tmp2:           .res 1
Tmp3:           .res 1

; --- The match scanner (SPEC 6.2) --------------------------------------------
;   One line of one pass at a time. The cursor is a BOARD INDEX rather than a
;   row and a column, because all four passes are the same walk with a
;   different step: +1 horizontal, +8 vertical, +9 diagonal, +7 anti-diagonal.
ScanIdx:        .res 1      ; Where the cursor was when a run ended: ScanLine
                            ;   keeps it in X and spills it only here
ScanStep:       .res 1      ; What to add to reach the next cell of this line
ScanColor:      .res 1      ; Colour key of the run in progress ($FF = unset)
ScanLen:        .res 1      ; Cells in it so far, wildcards included
ScanEnd:        .res 1      ; Walk-back cursor while a finished run is marked
ScanTop:        .res 1      ; Row base of the top of the pile. Every pass
                            ;   starts there rather than at row 0, which is
                            ;   most of the cost of a scan (match.asm)

; --- Board walks that call the renderer (SPEC 8 steps 6 and 8) ---------------
;   RenderCell clobbers A, X and Y, so a walk that marks what it changes
;   cannot keep its cursor in a register. GravIdx also has to survive from one
;   frame to the next: a row of falling is a cursor and not a bulk enqueue,
;   because a full well is more cells than the dirty ring holds (D12,
;   SPEC 12.6).
GravIdx:        .res 1      ; Cell the fall is walking up from, $FF when the
                            ;   row is finished
GravMoved:      .res 1      ; Non-zero if this row of falling moved anything
CellCount:      .res 1      ; Cells CascadeRemove has taken off the board

; --- Reagent effects (SPEC 7.3, SPEC 8 step 4) -------------------------------
;   EffectHit marks a cell, scores it and enqueues whatever it holds, so it
;   clobbers A, X and Y — which means a walk that offers it cells cannot keep
;   its cursor in a register either. Same reason GravIdx exists, and the same
;   reason these are not Tmp0-Tmp3: those are dead across a JSR.
EffectIdx:      .res 1      ; The cell the walk in progress is on
EffectEnd:      .res 1      ; Where it stops. The bolt's row end, or the bomb's
                            ;   last row
EffectRow:      .res 1      ; First cell of the bomb's current row
EffectArg:      .res 1      ; What the walk is looking for: the fireball's
                            ;   colour key, or the bomb's last column

; --- Animation walks (SPEC 14) -----------------------------------------------
;   The glow, the beams and the shatter all walk MARKS and mark what they find,
;   so their cursors cannot live in registers either — RenderMark clobbers A
;   and X. There are two of them because the beam pass NESTS: the outer walk is
;   over the marked cells, looking for bolts, and the inner one is over the
;   cross each bolt draws.
AnimMode:       .res 1      ; Which of the four the walk is doing
AnimIdx:        .res 1      ; Outer cursor — the marked cell being animated
AnimCur:        .res 1      ; Inner cursor — the beam cell being drawn
AnimEnd:        .res 1      ; Where the inner walk stops
AnimArg:        .res 1      ; What it is drawing, or the bolt's own column

; --- Render and text scratch -------------------------------------------------
;   These ARE live across a JSR, unlike Tmp0-Tmp3, because text.asm calls
;   RenderMark once per cell and has to remember where it is. That is safe
;   only because RenderMark touches nothing here: it clobbers A, X and the
;   stack and nothing else (see render.asm). Do not call anything else from a
;   loop that holds one of these.
TextCol:        .res 1      ; Panel column the next glyph goes in
TextRow:        .res 1      ; Panel row the string is drawn on
TextIdx:        .res 1      ; Cursor within the string, or the BCD byte index
TextByte:       .res 1      ; The BCD byte being split into two digits
TextSkip:       .res 1      ; Non-zero while the first high nibble is skipped
FlushLeft:      .res 1      ; Cells left in this frame's flush budget
RedrawCol:      .res 1      ; Panel column of the cell being marked. Shared by
                            ;   every routine that marks a run of cells in one
                            ;   column, because RenderMark clobbers X.
