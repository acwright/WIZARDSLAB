; =============================================================================
;   anim.asm — Wizards Lab, the animations a clear is made of
; =============================================================================
;   SPEC.md section 14, and step 5 of SPEC 8. Everything here is a frame's
;   worth of work and then a return: nothing waits, nothing loops on a timer,
;   and the main loop never stops for any of it (D4).
;
;   A CLEAR STEP ANIMATES IN TWO WINDOWS, and every event SPEC 14 lists lands
;   inside one of them:
;
;     PLAY_GLOW      matched cells wear glyph +6 of their own colour, the
;                    bolt's beams lie over its row and column, and the
;                    fireball's colour is white board-wide. GlowFrames, or the
;                    longer FlashFrames when a fireball fired
;     PLAY_SHATTER   the removal ring opens outward over every marked cell,
;                    two frames a tile, with a marked prism's blip-out closing
;                    inward beside it. SHATTER_STEPS ring frames, or the
;                    prism's BLIP_STEPS when there is one
;
;   A window is as long as the LONGEST thing in it, which is the one rule that
;   makes the durations in SPEC 14 hold without a timer per effect.
;
;   THE BOARD IS UNTOUCHED THE WHOLE TIME. Marked cells are not zeroed until
;   CascadeRemove runs at the end of the shatter (SPEC 8 step 6), so every
;   routine below can read a cell to find out what it is while drawing
;   something else entirely over it — which is also what let P5 make an effect
;   queue entry one byte (cascade.asm). Nothing here writes Board except the
;   prism's idle rotation and the game-over petrify, both of which change what
;   a cell IS and not merely what it shows.
;
;   THE COLOUR IS TESTED BEFORE THE GLYPH, everywhere, for the reason P5 found
;   the hard way: a prism is glyph 0 of colour 6 and, now that it rotates, its
;   board byte is WILD_BASE + 0..3, whose low three bits read as a bolt or a
;   bomb. Colour 6 is the only test that stays true.
; =============================================================================

ANIM_GLOW           = 0         ; The four passes AnimMarked can make over the
ANIM_BEAM           = 1         ;   marked cells. AnimMode picks one; the walk
ANIM_UNBEAM         = 2         ;   itself is the same 30 bytes for all four
ANIM_SHATTER        = 3         ;   and is written once.

; -----------------------------------------------------------------------------
;   AnimMarked — run one pass over every marked cell
;   In:  A = ANIM_*      Out: nothing.  Modifies: A, X, Y, Anim*, and whatever
;        the pass itself touches
;
;   The same walk as EffectEnqueueMarked (cascade.asm) and for the same reason:
;   MARKS is the union of everything the step is taking, and a cell in a
;   horizontal run AND a vertical one appears in it once. Marks are read only
;   here — no pass sets one — so the bitmap cannot change underneath the walk.
;
;   The cursor is in memory rather than in X because everything the passes call
;   ends at RenderMark, which clobbers A and X (D13).
; -----------------------------------------------------------------------------
AnimMarked:
  sta AnimMode
  lda #0
  sta AnimIdx
@Row:
  lda AnimIdx
  lsr a
  lsr a
  lsr a
  tay
  lda Marks,y
  beq @NextRow                  ; Nothing marked in this row, which is most
                                ;   rows of most steps
@Cell:
  lda AnimIdx
  jsr MarkTest
  bcc @NextCell
  ldx AnimIdx
  jsr AnimCell
@NextCell:
  inc AnimIdx
  lda AnimIdx
  and #(BOARD_STRIDE - 1)
  cmp #BOARD_W
  bcc @Cell

  lda AnimIdx                   ; On the row's first sentinel column; step
  clc                           ;   over both of them
  adc #(BOARD_STRIDE - BOARD_W)
  sta AnimIdx
  jmp @Test

@NextRow:
  lda AnimIdx
  clc
  adc #BOARD_STRIDE
  sta AnimIdx
@Test:
  lda AnimIdx
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Row
  rts

; -----------------------------------------------------------------------------
;   AnimCell — one marked cell, in whichever pass is running
;   In:  X = board index, AnimMode      Out: nothing.  Modifies: A, X, Y
; -----------------------------------------------------------------------------
AnimCell:
  lda AnimMode
  beq AnimCellGlow
  cmp #ANIM_SHATTER
  beq AnimCellShatter
  ; falls through into the two beam passes, which are the same test

; -----------------------------------------------------------------------------
;   AnimCellBolt — is this cell a bolt? If so, draw or undraw its cross
;   In:  X = board index      Out: nothing.  Modifies: A, X, Y, Anim*
;
;   The beams are their own pass and not a case inside the glow, because a
;   beam goes OVER a glow: a cell in a bolt's row is very often also a matched
;   cell, and both have to be drawn in that order.
; -----------------------------------------------------------------------------
AnimCellBolt:
  lda Board,x
  and #COLOR_MASK
  cmp #WILD_BASE
  beq @Done                     ; Colour before glyph: a rotating prism's low
                                ;   three bits say "bolt" and it is not one
  lda Board,x
  and #GLYPH_MASK
  cmp #GLYPH_BOLT
  bne @Done
  jmp AnimBeam
@Done:
  rts

; -----------------------------------------------------------------------------
;   AnimCellGlow — glyph +6 of the cell's own colour (SPEC 14)
;   In:  X = board index      Out: nothing.  Modifies: A, X, Y, AnimSteps
;
;   A MARKED PRISM SITS THE GLOW OUT. Group 14's slot +6 is an arrow, not a
;   glow (SPEC A.3), so `WILD_BASE + GLYPH_GLOW` must never be constructed —
;   the prism holds whatever rotation frame it was on and blips out later
;   instead. Meeting one here is also how the shatter window learns it has to
;   run BLIP_STEPS rather than SHATTER_STEPS, which saves a second walk.
; -----------------------------------------------------------------------------
AnimCellGlow:
  lda Board,x
  and #COLOR_MASK
  cmp #WILD_BASE
  beq @Prism
  ora #GLYPH_GLOW               ; The colour key's low three bits are clear, so
  jmp RenderCellAs              ;   an ORA is the whole conversion (SPEC 4.2)
@Prism:
  lda #BLIP_STEPS
  sta AnimSteps
  rts

; -----------------------------------------------------------------------------
;   AnimCellShatter — the ring frame this cell is showing right now
;   In:  X = board index, AnimStep      Out: nothing.  Modifies: A, X, Y
;   SPEC 14, Appendix A.3 — one ring, opening outward for everything except a
;   prism, which runs it closed inward.
; -----------------------------------------------------------------------------
AnimCellShatter:
  lda Board,x
  and #COLOR_MASK
  cmp #WILD_BASE
  beq @Blip
  ldy AnimStep
  cpy #(SHATTER_STEPS + 1)
  bcs @Done                     ; The ring is spent and the cell already blank.
  lda VfxShatter,y              ;   Only reachable while a prism holds the
  jmp RenderCellAs              ;   window open for its last two frames
@Blip:
  ldy AnimStep
  lda VfxBlip,y
  jmp RenderCellAs
@Done:
  rts

; -----------------------------------------------------------------------------
;   AnimBeam — the bolt's beams, along its whole row and its whole column
;   In:  X = board index of the bolt; AnimIdx holds the same index, because
;        this is only ever reached from AnimMarked's cursor
;   Out: nothing.  Modifies: A, X, Y, AnimCur, AnimEnd, AnimArg
;   SPEC 14, Appendix A.3.
;
;   The beams cover EVERY cell of the row and the column, empty ones included.
;   A beam has to butt against its neighbours to read as a beam, and the cells
;   the bolt found empty were never marked — so those are also the cells the
;   ANIM_UNBEAM pass exists to put back, since nothing else would ever draw
;   them again.
;
;   The cross goes down last, over both walks, because it is the one cell that
;   belongs to each.
; -----------------------------------------------------------------------------
AnimBeam:
  txa
  and #(BOARD_STRIDE - 1)
  sta AnimArg                   ; Its column, for the second walk
  txa
  and #(256 - BOARD_STRIDE)     ; $F8 — its row base
  sta AnimCur
  clc
  adc #BOARD_W
  sta AnimEnd                   ; One past the row's last playfield cell
@Row:
  ldx AnimCur
  lda #VFX_BEAM_H
  jsr AnimBeamCell
  inc AnimCur
  lda AnimCur
  cmp AnimEnd
  bcc @Row

  lda AnimArg                   ; The column, row 0 downward
  sta AnimCur
@Col:
  ldx AnimCur
  lda #VFX_BEAM_V
  jsr AnimBeamCell
  lda AnimCur
  clc
  adc #BOARD_STRIDE
  sta AnimCur
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Col

  ldx AnimIdx                   ; The bolt's own cell. The outer walk is still
  lda #VFX_BEAM_CROSS           ;   standing on it, which is cheaper than
  ; falls through                ;   keeping a copy across both walks

; -----------------------------------------------------------------------------
;   AnimBeamCell — one cell of a beam, drawn or put back
;   In:  X = board index, A = beam tile      Modifies: A, X, Y
;
;   On the way back only the cells that are NOT marked need anything: the
;   marked ones are about to be drawn by the shatter, twice a frame apart, and
;   drawing them here as well would only queue two marks for one cell.
;
;   THE RESTORE IS THE ONE MARK IN THE WHOLE ANIMATION THAT CANNOT BE DROPPED.
;   Every other one is made again within a few frames — a lost glow is covered
;   by the shatter six frames later, a lost ring frame by CascadeRemove at the
;   end of it — but a beam laid over an EMPTY cell has nothing behind it that
;   anything will ever draw again, and D6's drop-on-overflow would leave a
;   white beam sitting in the well for the rest of the game. Five bolts in one
;   run put 110 beam cells through here against a 64-entry ring, so this is
;   reachable and not theoretical. It takes the same way out CascadeRemove
;   does: the whole-well redraw cursor, which repaints every one of them from
;   the board (D12).
; -----------------------------------------------------------------------------
AnimBeamCell:
  ldy AnimMode
  cpy #ANIM_BEAM
  bne @Restore
  jmp RenderCellAs
@Restore:
  txa
  pha                           ; MarkTest takes the index in A and clobbers
  jsr MarkTest                  ;   X; neither PLA nor TAX touches C
  pla
  tax
  bcs @Done                     ; Marked — the shatter has it
  lda DirtyCount
  cmp #DIRTY_ENTRIES
  bcs @Bulk                     ; No room, and this cell must not be lost
  jmp RenderCell                ; Board,x — empty, in every case that gets here
@Bulk:
  jmp RenderBoard               ; Sets the cursor and nothing else; the cells
                                ;   already queued still land and the redraw
                                ;   goes over them with the same values
@Done:
  rts

; =============================================================================
;   The two windows
; =============================================================================

; -----------------------------------------------------------------------------
;   AnimGlowBegin — SPEC 8 step 5, first half. Called with MARKS filled and
;   the effect queue drained, from CascadeEnter.
;   Out: PlayState = PLAY_GLOW.  Modifies: A, X, Y, Anim*
;
;   The fireball's flash is already lit: EffectResolve calls HalColorFlash as
;   it detonates, so TintColor arriving here as anything but TINT_NONE is how
;   this knows a fireball fired and the window has to be the longer one
;   (SPEC 14). Two fireballs of different colours in one step leave the LAST
;   one's colour flashing — one byte can only name one group, and the other's
;   cells still glow and still shatter.
; -----------------------------------------------------------------------------
AnimGlowBegin:
  lda #SHATTER_STEPS            ; Raised to BLIP_STEPS by AnimCellGlow if it
  sta AnimSteps                 ;   meets a marked prism
  lda #ANIM_GLOW
  jsr AnimMarked
  lda #ANIM_BEAM
  jsr AnimMarked

  ldx Region
  lda GlowFrames,x
  ldy TintColor
  cpy #TINT_NONE
  beq @Time
  lda FlashFrames,x
  pha
  jsr RenderNext                ; The preview is redrawn so that a piece of the
  pla                           ;   flashing colour goes white there too. On
                                ;   the AC6502 the whole group recolours and
                                ;   this changes nothing; on the Commodores the
                                ;   tint is per cell and this is the only way
                                ;   those three cells hear about it (SPEC 4.6)
@Time:
  sta AnimTimer
  lda #PLAY_GLOW
  sta PlayState
  rts

; -----------------------------------------------------------------------------
;   AnimGlowEnd — take the beams and the flash down, and start the shatter
;   Out: PlayState = PLAY_SHATTER.  Modifies: A, X, Y, Anim*
; -----------------------------------------------------------------------------
AnimGlowEnd:
  lda #ANIM_UNBEAM
  jsr AnimMarked

  lda TintColor
  cmp #TINT_NONE
  beq AnimShatterBegin
  lda #TINT_NONE
  jsr HalColorFlash             ; The flash ends with the window; every cell it
  jsr RenderNext                ;   covered is marked and about to be redrawn
                                ;   by the shatter, so only the preview needs
                                ;   asking for again
  ; falls through

; -----------------------------------------------------------------------------
;   AnimShatterBegin — SPEC 8 step 5, second half
;   Out: PlayState = PLAY_SHATTER.  Modifies: A, X, Y, Anim*
;   Frame 0 of the ring goes up now rather than next frame, so the window is
;   AnimSteps * VFX_FRAMES frames long and every tile of it holds for
;   VFX_FRAMES, the last one included.
; -----------------------------------------------------------------------------
AnimShatterBegin:
  lda #0
  sta AnimStep
  lda #VFX_FRAMES
  sta AnimTimer
  lda #PLAY_SHATTER
  sta PlayState
  lda #ANIM_SHATTER
  jmp AnimMarked

; =============================================================================
;   The prism at rest (SPEC 7.3, 14)
; =============================================================================

; -----------------------------------------------------------------------------
;   AnimPrismTick — advance the idle rotation, one frame every PRISM_SPIN_RATE
;   Out: nothing.  Modifies: A, X, Y, AnimIdx, AnimArg, PrismFrame, PrismTimer
;
;   The only tile in the game that moves when nothing is happening, and the
;   only place other than the petrify that WRITES a tile to the board without
;   the board having changed: a prism's cell really does hold WILD_BASE + 0..3
;   from here on. Everything that reads a cell masks the colour first, so the
;   glyph bits carrying a frame number rather than a zero is invisible to the
;   scan, to gravity and to the effects — but it is exactly why P5 made
;   EffectEnqueue test the colour before the glyph, and why the petrify below
;   does too.
;
;   IT DOES NOT RUN DURING THE GLOW OR THE SHATTER. A marked prism has to hold
;   still for the glow window and then play its blip-out, and it is cheaper to
;   stand the whole walk down for those twelve frames than to test every cell
;   against MARKS.
;
;   The walk is the 96 cells of the well every eighth frame whether a prism is
;   on the board or not — about 150 cycles a frame amortised, against a board
;   scan's eleven thousand. Remembering where the prisms are would cost more
;   than it saves, and would have to be kept right through gravity.
; -----------------------------------------------------------------------------
AnimPrismTick:
  lda PlayState
  cmp #PLAY_GLOW
  beq @Done
  cmp #PLAY_SHATTER
  beq @Done
  dec PrismTimer
  bne @Done

  lda #PRISM_SPIN_RATE
  sta PrismTimer
  inc PrismFrame
  lda PrismFrame
  and #(PRISM_SPIN_FRAMES - 1)
  sta PrismFrame
  ora #PRISM_SPIN               ; WILD_BASE + frame (SPEC A.3)
  sta AnimArg

  lda #0
  sta AnimIdx
@Cell:
  ldx AnimIdx
  lda Board,x
  and #COLOR_MASK
  cmp #WILD_BASE
  bne @Next
  lda AnimArg
  sta Board,x
  jsr RenderCell
@Next:
  inc AnimIdx
  lda AnimIdx
  and #(BOARD_STRIDE - 1)
  cmp #BOARD_W
  bcc @Test
  lda AnimIdx                   ; Over the two sentinel columns
  clc
  adc #(BOARD_STRIDE - BOARD_W)
  sta AnimIdx
@Test:
  lda AnimIdx
  cmp #(BOARD_H * BOARD_STRIDE)
  bcc @Cell
@Done:
  rts

; =============================================================================
;   The message band (SPEC 12.2, 14)
; =============================================================================

; -----------------------------------------------------------------------------
;   AnimBannerShow — put a banner up for BannerFrames
;   In:  Ptr1 -> string      Out: nothing.  Modifies: A, X, Y and the text
;        cursor
; -----------------------------------------------------------------------------
AnimBannerShow:
  jsr TextBanner
  ldx Region
  lda BannerFrames,x
  sta BannerTimer
  rts

; -----------------------------------------------------------------------------
;   AnimBannerTick — one frame of whatever banner is up
;   Out: nothing.  Modifies: A, X, Y
;   Play never stops for a banner: it ticks alongside the sub-states, like the
;   high-score flash it shares its clock with (SPEC 9.8).
; -----------------------------------------------------------------------------
AnimBannerTick:
  lda BannerTimer
  beq @Done
  dec BannerTimer
  bne @Done
  jmp TextBannerClear
@Done:
  rts

; -----------------------------------------------------------------------------
;   AnimBannerLevel — "~~ LEVEL UP ~~" (SPEC 10.1, 14)
; -----------------------------------------------------------------------------
AnimBannerLevel:
  lda #<MsgLevelUp
  sta Ptr1
  lda #>MsgLevelUp
  sta Ptr1+1
  jmp AnimBannerShow

; -----------------------------------------------------------------------------
;   AnimBannerChain — "~~ CHAIN xN ~~" (SPEC 8 SETTLE, 14)
;   In:  A = links in the cascade      Modifies: A, X, Y and the text cursor
;
;   The banner is a fixed-length string with a placeholder digit, overwritten
;   afterwards at CHAIN_DIGIT_X — which is a constant only because the string
;   is MSG_CHAIN_LEN cells long and TextBanner centres on PANEL_W
;   (constants.inc). A chain past 9 says 9 rather than drawing whatever tile
;   FONT_DIGIT_0 + 10 turns out to be.
; -----------------------------------------------------------------------------
AnimBannerChain:
  cmp #(CHAIN_MAX_SHOWN + 1)
  bcc @Show
  lda #CHAIN_MAX_SHOWN
@Show:
  pha
  lda #<MsgChain
  sta Ptr1
  lda #>MsgChain
  sta Ptr1+1
  jsr AnimBannerShow
  pla
  clc
  adc #FONT_DIGIT_0
  ldx #CHAIN_DIGIT_X
  ldy #MSG_Y
  jmp RenderMark

; =============================================================================
;   Game over (SPEC 13.4)
; =============================================================================

; -----------------------------------------------------------------------------
;   AnimPetrifyBegin — start the well turning to stone from the floor up
;   Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
AnimPetrifyBegin:
  lda #(BOARD_H - 1)
  sta PetrifyRow
  lda #PETRIFY_FRAMES
  sta AnimTimer
  rts

; -----------------------------------------------------------------------------
;   AnimPetrifyTick — one frame of it
;   Out: C set while it is still running, clear once the well is stone.
;        Modifies: A, X, Y, AnimIdx, AnimEnd, AnimTimer, PetrifyRow, Board
;   SPEC 13.4 — a row every PETRIFY_FRAMES, bottom upward, 32 frames in all.
;
;   Each cell sets as ITS OWN SHAPE, because group 15 holds the petrified
;   glyphs at the same five offsets the potions use (SPEC A.3): one AND and
;   one ORA, and a bomb sets as a stone bomb at the exact moment the player is
;   looking hardest at the board. Empty cells stay empty — the pile petrifies,
;   not the well.
;
;   A prism has no stone twin, so it sets as the plain one. Testing the colour
;   first is what keeps it off `PETRIFY_BASE + 3`, a stone bomb, which is what
;   a rotating prism's glyph bits would otherwise buy (AnimPrismTick above).
; -----------------------------------------------------------------------------
AnimPetrifyTick:
  lda PetrifyRow
  bmi @Finished                 ; $FF — the whole well is stone
  dec AnimTimer
  bne @Running

  lda #PETRIFY_FRAMES
  sta AnimTimer
  lda PetrifyRow
  asl a                         ; Row base — the board's stride is 8
  asl a
  asl a
  sta AnimIdx
  clc
  adc #BOARD_W
  sta AnimEnd
@Cell:
  ldx AnimIdx
  lda Board,x
  beq @Next                     ; Empty stays empty (SPEC 13.4)
  and #COLOR_MASK
  cmp #WILD_BASE
  beq @Prism
  lda Board,x
  and #GLYPH_MASK
  ora #PETRIFY_BASE
  bne @Set                      ; Always — PETRIFY_BASE is 120
@Prism:
  lda #PETRIFY_BASE
@Set:
  sta Board,x
  jsr RenderCell
@Next:
  inc AnimIdx
  lda AnimIdx
  cmp AnimEnd
  bcc @Cell
  dec PetrifyRow
@Running:
  sec
  rts
@Finished:
  clc
  rts
