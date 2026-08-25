; =============================================================================
;   ram.inc — Wizards Lab, work RAM
; =============================================================================
;   SPEC.md section 17.1. Around 530 bytes, which is what lets the whole game
;   fit the VIC-20's 1 KB of usable work RAM — the tightest of the three
;   targets, and therefore the one the layout is designed against.
;
;   Every platform places the BSS segment somewhere different (see each
;   linker config); nothing in this file cares where.
; =============================================================================

.segment "BSS"

; --- The board (SPEC 3.2) ----------------------------------------------------
;   20 rows x 8 stride. Columns 6-7 of every row and rows 16-19 entirely are
;   permanent $FF sentinels, so scans walk off the edge and stop by themselves.
;   Page-align it: address(row,col) = Board + (row << 3) + col.
.align 256
Board:          .res BOARD_BYTES

; --- Match / cascade state (SPEC 6.2, 8) -------------------------------------
Marks:          .res MARKS_BYTES        ; One byte per row, bits 0-5 = columns
EffectQ:        .res EFFECTQ_BYTES      ; Ring of pending reagent detonations
EffectQHead:    .res 1
EffectQTail:    .res 1
RunCount:       .res 1                  ; Runs resolved in the current step
ChainStep:      .res 1                  ; 1 on the first step of a cascade
StarCount:      .res 1                  ; Doublings pending, capped at 3
CascadeLo:      .res 1                  ; Cascade point accumulator, packed BCD
CascadeMid:     .res 1
CascadeHi:      .res 1

; --- Render (SPEC 12.6) ------------------------------------------------------
Dirty:          .res DIRTY_BYTES        ; offset lo, offset hi, tile
DirtyCount:     .res 1
DirtyFlushed:   .res 1                  ; Carried across frames when capped

; --- The falling piece (SPEC 5) ----------------------------------------------
PieceCol:       .res 1
PieceRow:       .res 1                  ; Row of cell A (the top cell)
PieceA:         .res 1                  ; Tile bytes, top to bottom
PieceB:         .res 1
PieceC:         .res 1
NextA:          .res 1                  ; The preview piece
NextB:          .res 1
NextC:          .res 1

; --- Progress (SPEC 9, 10) ---------------------------------------------------
ScoreLo:        .res 1                  ; 6 digits packed BCD, low byte first
ScoreMid:       .res 1
ScoreHi:        .res 1
HighLo:         .res 1
HighMid:        .res 1
HighHi:         .res 1
Level:          .res 1                  ; Binary, 1-99
TilesCleared:   .res 1                  ; Toward the next level, wraps at 30

; --- Timers, all in frames (SPEC 14) -----------------------------------------
GravityTimer:   .res 1
LockTimer:      .res 1
LockResets:     .res 1
DasTimer:       .res 1
DasDir:         .res 1
AreTimer:       .res 1
AnimTimer:      .res 1
BannerTimer:    .res 1
FrameCounter:   .res 1                  ; Free-running from power-on; seeds RNG

; --- Input (SPEC 11.1) -------------------------------------------------------
InputNow:       .res 1
InputPrev:      .res 1
InputEdge:      .res 1                  ; Newly pressed this frame

; --- State machine (SPEC 13) -------------------------------------------------
GameState:      .res 1                  ; STATE_*
PlayState:      .res 1                  ; PLAY_*
TitlePage:      .res 1
Region:         .res 1                  ; 0 = NTSC, 1 = PAL
NeedsRedraw:    .res 1

; --- Audio (SPEC 16) ---------------------------------------------------------
SfxRequest:     .res 1                  ; Written by logic, consumed by AudioTick
SfxTimer:       .res 1
SfxState:       .res 14
