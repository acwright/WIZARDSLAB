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
EffectQ:        .res EFFECTQ_BYTES      ; Ring of pending reagent detonations —
                                        ;   the board INDEX of each, one byte,
                                        ;   because the tile is still on the
                                        ;   board when the entry pops
                                        ;   (constants.inc, SPEC 8)
EffectQHead:    .res 1
EffectQTail:    .res 1
RunCount:       .res 1                  ; Runs resolved in the current step
ChainStep:      .res 1                  ; 1 on the first step of a cascade
StarCount:      .res 1                  ; Doublings pending, capped at 3
CascadeLo:      .res 1                  ; Cascade point accumulator, packed BCD
CascadeMid:     .res 1
CascadeHi:      .res 1

; --- Animation (SPEC 14) -----------------------------------------------------
AnimStep:       .res 1                  ; Ring frame the shatter is showing,
                                        ;   0 .. AnimSteps - 1
AnimSteps:      .res 1                  ; SHATTER_STEPS, or BLIP_STEPS when a
                                        ;   marked prism is blipping out along
                                        ;   with the rest (constants.inc)
TintColor:      .res 1                  ; Colour key currently drawn WHITE — the
                                        ;   fireball flash (SPEC 4.6) — or
                                        ;   TINT_NONE. Read by HalPlotCell on
                                        ;   the Commodores and written to the
                                        ;   VDP colour table on the AC6502;
                                        ;   HalColorFlash is the only thing that
                                        ;   sets it (hal.inc)
PrismFrame:     .res 1                  ; Idle rotation frame, 0-3
PrismTimer:     .res 1                  ; Frames until the next one
PetrifyRow:     .res 1                  ; Board row the game-over petrify is
                                        ;   working up from, $FF when it is done
TitleTimer:     .res 1                  ; Frames until the title prompt's next
                                        ;   half-blink (SPEC 13.1, 14)
TitlePhase:     .res 1                  ; 0 while it is lit, 1 while it is dark

; --- Render (SPEC 12.6) ------------------------------------------------------
;   A ring of DIRTY_ENTRIES cells waiting to be pushed to the screen, three
;   bytes each: SCREEN column, SCREEN row, tile. Not a 16-bit screen offset —
;   HalPlotCell takes a column and a row (hal.inc), and every platform reaches
;   a cell through a per-row pointer table (SPEC 12.3), so an offset would only
;   have to be taken apart again at the far end.
;
;   A ring rather than a list with a resume index, because a frame that flushes
;   its cap leaves a remainder and the next frame's marks have to go somewhere.
;   Head and tail are BYTE offsets into Dirty, not entry numbers, so stepping
;   one entry is an add of 3 and never a multiply.
Dirty:          .res DIRTY_BYTES        ; screen col, screen row, tile
DirtyCount:     .res 1                  ; Entries pending, 0..DIRTY_ENTRIES
DirtyHead:      .res 1                  ; Byte offset of the oldest pending
DirtyTail:      .res 1                  ; Byte offset the next mark goes to
RedrawIdx:      .res 1                  ; Board index RenderBoardStep resumes
                                        ;   at, or $FF when no redraw is
                                        ;   outstanding
RedrawWash:     .res 1                  ; TILE_WASH while the cursor above is
                                        ;   painting the PAUSE wash rather than
                                        ;   the board, zero otherwise. Both are
                                        ;   96 cells against a 64-entry ring, so
                                        ;   both have to be a cursor (D12) and
                                        ;   one byte is cheaper than a second
                                        ;   one (SPEC 13.3)

; --- The falling piece (SPEC 5) ----------------------------------------------
PieceCol:       .res 1
PieceRow:       .res 1                  ; Row of cell A (the top cell)
PieceA:         .res 1                  ; Tile bytes, top to bottom
PieceB:         .res 1
PieceC:         .res 1
NextA:          .res 1                  ; The preview piece
NextB:          .res 1
NextC:          .res 1
PieceDirty:     .res 1                  ; Non-zero when the three cells need
                                        ;   drawing. Not drawn on the spot,
                                        ;   because a full-board redraw may be
                                        ;   in flight and would paint over
                                        ;   them — see StatePlay (D14).

; --- Progress (SPEC 9, 10) ---------------------------------------------------
ScoreLo:        .res 1                  ; 7 digits packed BCD, low byte first;
ScoreMid:       .res 1                  ;   the top nibble of ScoreTop stays 0
ScoreHi:        .res 1
ScoreTop:       .res 1
HighLo:         .res 1
HighMid:        .res 1
HighHi:         .res 1
HighTop:        .res 1
HighLevel:      .res 1                  ; Level the high score was set on, BCD
HighOwned:      .res 1                  ; Non-zero once THIS game has taken the
                                        ;   high score. From the overtake on,
                                        ;   score and high score are equal and
                                        ;   every bank copies again, so without
                                        ;   this the one-shot fanfare and flash
                                        ;   would fire on every one (SPEC 9.8)
HighFlash:      .res 1                  ; Half-blinks of the HIGH field left to
                                        ;   run. Odd = dark, even = lit, and it
                                        ;   ends at zero, so the field is always
                                        ;   left readable
HighTimer:      .res 1                  ; Frames until the next half-blink
Level:          .res 1                  ; Binary, 1-99
TilesCleared:   .res 1                  ; Toward the next level, carries past 30

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
OverSecs:       .res 1                  ; Seconds left on the game-over screen,
                                        ;   and ZERO until the petrify has
                                        ;   finished and the banner is up. That
                                        ;   double duty is what makes the setup
                                        ;   a one-shot without a second flag:
                                        ;   the count never rests at zero,
                                        ;   because reaching it returns to the
                                        ;   title in the same frame (SPEC 13.4)
OverTimer:      .res 1                  ; Frames until the next second of it
Region:         .res 1                  ; 0 = NTSC, 1 = PAL
NeedsRedraw:    .res 1

; --- Audio (SPEC 16) ---------------------------------------------------------
;   Five bytes, not the sixteen SPEC 17.1 budgeted. The effect data is a step
;   list in ROM (tables.inc) and the driver is a cursor into it, so the only
;   thing RAM has to hold is where in that list the one playing channel is.
SfxRequest:     .res 1                  ; Effect asked for THIS frame, or 0.
                                        ;   Logic writes it through SfxPlay,
                                        ;   which keeps the loudest of several
                                        ;   in one frame; AudioTick consumes and
                                        ;   clears it (audio.asm)
SfxId:          .res 1                  ; Effect playing, or 0 for silence. It
                                        ;   is also the priority a new request
                                        ;   has to beat (constants.inc)
SfxStepIdx:     .res 1                  ; Byte offset into SfxSteps of the NEXT
                                        ;   step — which is why that table has
                                        ;   to stay under 256 bytes
SfxTimer:       .res 1                  ; Frames left in the step now sounding
SfxShift:       .res 1                  ; Semitones added to every note of the
                                        ;   effect playing. Zero for eleven of
                                        ;   the twelve; the match chime sets it
                                        ;   from the chain (SPEC 16)
