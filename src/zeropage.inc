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

ScanRow:        .res 1      ; Match scanner cursor
ScanCol:        .res 1
ScanColor:      .res 1      ; Colour key of the run in progress ($FF = unset)
ScanLen:        .res 1

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
RedrawCol:      .res 1      ; Panel column of the cell RenderBoardStep is on
