; =============================================================================
;   piece.asm — Wizards Lab, the falling piece
; =============================================================================
;   SPEC.md section 5. A piece is three independently generated cells stacked
;   vertically, A on top. At most one of the three carries a reagent, which is
;   enforced by rolling once for the piece rather than once per cell.
;
;   The piece is NOT in the board while it falls. Board cells under it stay
;   empty until PieceLock writes them, which is what makes the movement tests
;   below a plain read of the three target cells and what lets the erase be
;   three blanks rather than three board reads.
;
;   Nothing here draws. Every routine that changes where the piece is or what
;   it holds sets PieceDirty and lets StatePlay pick the moment (D14).
; =============================================================================

; -----------------------------------------------------------------------------
;   PieceIndex — board index of the piece's top cell
;   In:  nothing
;   Out: A = X = PieceRow * BOARD_STRIDE + PieceCol.  Modifies: A, X
;
;   Cells B and C are one and two strides on from it, and the cell below C is
;   three — which is the only address arithmetic the rest of this file needs.
;   Row 16 and beyond is a wall row, so "below C" is always a legal read.
; -----------------------------------------------------------------------------
PieceIndex:
  lda PieceRow
  asl a
  asl a
  asl a                         ; row * 8
  clc
  adc PieceCol
  tax
  rts

; -----------------------------------------------------------------------------
;   PieceGenerateNext — roll the preview piece into NextA/NextB/NextC
;   In:  nothing (reads Level)
;   Out: nothing.  Modifies: A, X, Y, Tmp0, Tmp1
;   SPEC 5.2, 5.3 — colours uniform over 0-5, then one reagent roll.
; -----------------------------------------------------------------------------
PieceGenerateNext:
  ldy #0                        ; RngRange preserves Y, so it can index the
@Color:                         ;   three cells across the call
  lda #NUM_COLORS
  jsr RngRange                  ; 0-5, uniform (SPEC 5.2)
  asl a
  asl a
  asl a                         ; colour << 3 ...
  clc
  adc #COLOR_BASE               ;   ... + base, glyph 0, so it is a potion
  sta NextA,y                   ; NextA/B/C are three consecutive bytes
  iny
  cpy #3
  bcc @Color

  ; --- does this piece carry a reagent at all? (SPEC 5.3) -------------------
  ;   One roll for the whole piece, which both caps it at one reagent and
  ;   costs three rolls fewer than asking each cell.
  jsr RngNext
  sta Tmp0                      ; The roll. Nothing below calls out until it
                                ;   has been compared, so Tmp0 is safe.
  ldx Level
  dex                           ; LevelBand is indexed by level - 1 ...
  cpx #16
  bcc @Band
  ldx #15                       ;   ... and clamped: band 4 is "13 and up"
@Band:
  lda LevelBand,x
  tax                           ; X = band 0-4
  lda Tmp0
  cmp PSpecial,x                ; C clear = the roll came in under the chance
  bcs @Done

  ; --- which cell, and which reagent ----------------------------------------
  txa
  pha                           ; The band, across the cell roll
  lda #3
  jsr RngRange                  ; 0, 1 or 2 — uniform over A, B and C
  tay                           ; Y survives the type roll below
  pla
  asl a
  asl a                         ; band * 4 — ReagentThresholds is four
  pha                           ;   thresholds per band
  jsr RngNext
  sta Tmp0                      ; The type roll
  pla
  tax
  lda Tmp0

  cmp ReagentThresholds+0,x     ; The cumulative-weight compare chain SPEC 5.3
  bcc @Fireball                 ;   recommends over a 1280-byte lookup
  cmp ReagentThresholds+1,x
  bcc @Bolt
  cmp ReagentThresholds+2,x
  bcc @Bomb
  cmp ReagentThresholds+3,x
  bcc @Star

  lda #WILD_BASE                ; A Prism discards the colour it rolled and
  sta NextA,y                   ;   joins group 14 (SPEC 5.2)
@Done:
  rts

@Fireball:
  lda #GLYPH_FIREBALL
  bne @Apply                    ; Always — every glyph below is non-zero
@Bolt:
  lda #GLYPH_BOLT
  bne @Apply
@Bomb:
  lda #GLYPH_BOMB
  bne @Apply
@Star:
  lda #GLYPH_STAR
@Apply:
  ora NextA,y                   ; The cell's glyph nibble is 0, so an ORA sets
  sta NextA,y                   ;   the reagent and keeps the rolled colour
  rts

; -----------------------------------------------------------------------------
;   PieceSpawn — promote the preview to the falling piece
;   In:  nothing
;   Out: C set if the spawn cells were occupied (game over)
;        Modifies: A, X
;   SPEC 5.4 — spawn column SPAWN_COL, rows 0-2, visible immediately.
;
;   The preview is copied whether or not the spawn succeeds; on a blocked
;   spawn nothing looks at the piece again.
; -----------------------------------------------------------------------------
PieceSpawn:
  lda NextA
  sta PieceA
  lda NextB
  sta PieceB
  lda NextC
  sta PieceC

  lda #SPAWN_COL
  sta PieceCol
  lda #0
  sta PieceRow
  sta LockTimer
  sta LockResets                ; The reset allowance is per piece (SPEC 5.6)

  lda Board + 0 * BOARD_STRIDE + SPAWN_COL
  ora Board + 1 * BOARD_STRIDE + SPAWN_COL
  ora Board + 2 * BOARD_STRIDE + SPAWN_COL
  bne @Blocked

  jsr ScoreGravity
  sta GravityTimer
  lda #1
  sta PieceDirty                ; Drawn immediately — there is no off-screen
  clc                           ;   entry (SPEC 5.4)
  rts

@Blocked:
  sec
  rts

; -----------------------------------------------------------------------------
;   PieceMoveLeft / PieceMoveRight — one column, if all three cells are free
;   Out: C set if the move happened (the caller resets the lock timer).
;        Modifies: A, X
;   SPEC 5.5 — no wall kicks; a 1-wide piece has nothing to kick off.
;
;   The right edge needs no bounds check: column 6 is a permanent $FF sentinel
;   and fails the emptiness test on its own (SPEC 3.2). The LEFT edge does,
;   because column -1 of row 0 is the byte before a page-aligned Board and
;   belongs to nobody.
; -----------------------------------------------------------------------------
PieceMoveLeft:
  lda PieceCol
  beq @No                       ; Column 0 — there is no sentinel to the left
  jsr PieceIndex
  dex
  lda Board + 0 * BOARD_STRIDE,x
  ora Board + 1 * BOARD_STRIDE,x
  ora Board + 2 * BOARD_STRIDE,x
  bne @No
  jsr RenderPieceErase
  dec PieceCol
  jmp PieceShifted

@No:
  clc
  rts

PieceMoveRight:
  jsr PieceIndex
  inx
  lda Board + 0 * BOARD_STRIDE,x
  ora Board + 1 * BOARD_STRIDE,x
  ora Board + 2 * BOARD_STRIDE,x
  bne @No
  jsr RenderPieceErase
  inc PieceCol
  jmp PieceShifted
@No:
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceShifted — a horizontal move landed (SPEC 16 effect 1)
;   Out: C set.  Modifies: A
;   Separate from PieceMoved because gravity goes through THAT and a row of
;   falling makes no noise: the blip belongs to the player's hand, not to the
;   piece changing cells.
; -----------------------------------------------------------------------------
PieceShifted:
  lda #SFX_MOVE
  jsr SfxPlay
  ; falls through

; -----------------------------------------------------------------------------
;   PieceMoved — mark the piece for redraw and report success
;   Out: C set.  Modifies: A
; -----------------------------------------------------------------------------
PieceMoved:
  lda #1
  sta PieceDirty
  sec
  rts

; -----------------------------------------------------------------------------
;   PieceRotate / PieceRotateBack — cycle the three cells
;   Out: nothing.  Modifies: A, X
;   SPEC 5.5 — (A,B,C) -> (B,C,A) forward, (C,A,B) back. Always succeeds: the
;   footprint never changes, so there is nothing to test and nothing to erase.
;   Rotation does not reset the lock delay (SPEC 5.6).
; -----------------------------------------------------------------------------
PieceRotate:
  lda PieceA
  ldx PieceB
  stx PieceA
  ldx PieceC
  stx PieceB
  sta PieceC
  lda #1
  sta PieceDirty
  lda #SFX_ROTATE               ; SPEC 16 effect 2 — both directions, one sound
  jmp SfxPlay

PieceRotateBack:
  lda PieceC
  ldx PieceB
  stx PieceC
  ldx PieceA
  stx PieceB
  sta PieceA
  lda #1
  sta PieceDirty
  lda #SFX_ROTATE
  jmp SfxPlay

; -----------------------------------------------------------------------------
;   PieceCanFall — is the cell below C free?
;   Out: C set if the piece can descend one row.  Modifies: A, X
;   Three strides past cell A. With C on row 15 that reads row 18, which is a
;   permanent wall row, so the floor needs no special case (SPEC 3.2).
; -----------------------------------------------------------------------------
PieceCanFall:
  jsr PieceIndex
  lda Board + 3 * BOARD_STRIDE,x
  bne @No
  sec
  rts
@No:
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceStep — one row of gravity
;   Out: C set if the piece has landed and the lock delay should start.
;        Modifies: A, X
; -----------------------------------------------------------------------------
PieceStep:
  jsr PieceCanFall
  bcc @Landed
  jsr RenderPieceErase
  inc PieceRow
  jsr PieceMoved
  clc                           ; Moved, so it has not landed
  rts
@Landed:
  sec
  rts

; -----------------------------------------------------------------------------
;   PieceLock — write the three cells into the board
;   Out: nothing.  Modifies: A, X, Y
;   SPEC 5.6 — after this the caller runs a cascade.
;
;   Once the board holds the piece, drawing the piece and drawing those three
;   board cells are the same three writes, so RenderPiece does the queueing.
; -----------------------------------------------------------------------------
PieceLock:
  jsr PieceIndex
  lda PieceA
  sta Board + 0 * BOARD_STRIDE,x
  lda PieceB
  sta Board + 1 * BOARD_STRIDE,x
  lda PieceC
  sta Board + 2 * BOARD_STRIDE,x

  jsr RenderPiece
  lda #0
  sta PieceDirty                ; It is board now; nothing owes it a redraw
  lda #SFX_LOCK                 ; SPEC 16 effect 3. A match in the same frame is
  jmp SfxPlay                   ;   louder and takes the channel off it
                                ;   (audio.asm)

; -----------------------------------------------------------------------------
;   PieceFallRate — frames per row for this frame
;   Out: A = frame count, C CLEAR if that rate is the soft drop's.
;        Modifies: A, X, Tmp0
;   SPEC 5.5, 11.3 — soft drop substitutes its own rate and is ignored when
;   gravity is already the faster of the two (levels 14+ on NTSC).
;
;   The carry is what pays for the soft drop: SPEC 9.6 gives a point per row
;   "descended under soft drop", and a row that fell at gravity's rate with
;   DOWN held down was not one, so holding DOWN at level 16 earns nothing.
;   Working it out here costs nothing — the comparison has already happened.
; -----------------------------------------------------------------------------
PieceFallRate:
  jsr ScoreGravity              ; Speed[level] for this region
  sta Tmp0
  lda InputNow
  and #INPUT_DOWN
  beq @Gravity
  ldx Region
  lda SoftDropRate,x
  cmp Tmp0                      ; C clear = soft drop is the faster
  bcc @Soft
@Gravity:
  lda Tmp0
  sec
  rts
@Soft:
  clc
  rts

; -----------------------------------------------------------------------------
;   PieceControl — apply this frame's input to the piece
;   Out: C set if a horizontal move succeeded (the caller may reset the lock
;        delay).  Modifies: A, X, Y
;
;   Rotation is edge triggered and never repeats: UP has to be released and
;   pressed again. SPEC 11.3 calls that non-negotiable and it is — a
;   repeating rotate makes a three-cell piece impossible to aim. Left and
;   right go through InputShift, which is where the repeat lives.
; -----------------------------------------------------------------------------
PieceControl:
  lda InputEdge
  and #INPUT_UP
  beq @NoRotate
  jsr PieceRotate
@NoRotate:
  lda InputEdge
  and #INPUT_FIRE
  beq @NoBack
  jsr PieceRotateBack
@NoBack:
  jsr InputShift
  cmp #INPUT_LEFT
  beq @Left
  cmp #INPUT_RIGHT
  beq @Right
  clc
  rts
@Left:
  jmp PieceMoveLeft
@Right:
  jmp PieceMoveRight
