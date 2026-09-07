; =============================================================================
;   main.asm — Wizards Lab, shared entry point and main loop
; =============================================================================
;   Included by every platform's WizardsLab.asm after that file has defined
;   PANEL_X / PANEL_Y and its half of the HAL (see hal.inc). Nothing below
;   touches hardware.
;
;   BUILD STATUS
;   ------------
;   Pieces spawn, steer, rotate, fall and lock, runs of three or more clear,
;   the pile falls into the holes and chains keep going until nothing matches
;   (PLAN.md P2, P3). Nothing scores yet — CascadeSettle banks a total that is
;   still zero — and the clear is instant: GLOW and SHATTER are P6's, and slot
;   into CascadeEnter between the scan and the fall.
; =============================================================================

; -----------------------------------------------------------------------------
;   GameInit — one-time setup, called from the cartridge entry point
; -----------------------------------------------------------------------------
GameInit:
  jsr HalDetectRegion
  sta Region

  jsr HalInitVideo              ; Tiles in place, screen black and cleared
  jsr AudioInit
  jsr RenderDirtyReset

  lda #0
  sta FrameCounter
  jsr RngSeed                   ; A zero LFSR state sticks at zero forever, and
                                ;   BSS is not cleared on all three machines, so
                                ;   seed it once here just to get it out of that
                                ;   hole. This is NOT the game's seed — SPEC 15
                                ;   forbids a constant one, and StateTitle
                                ;   reseeds from the player's reaction time
                                ;   before the first piece is ever rolled.
  lda #0
  sta InputNow
  sta InputPrev
  sta InputEdge
  sta TitlePage

  jsr ScoreHighInit             ; Once a session, before the first ScoreReset
  jsr ScoreReset
  jsr BoardClear

.ifdef WL_DEBUG
  jsr GameStart                 ; TEMPORARY: skip the title and start playing,
                                ;   because a headless machine has no input
                                ;   attached and would sit on the title screen
                                ;   forever. Nothing else about the build
                                ;   differs any more (PLAN.md section 3).
.else
  lda #STATE_TITLE
  sta GameState
  lda #1
  sta NeedsRedraw
.endif
  ; falls through into GameLoop

; -----------------------------------------------------------------------------
;   GameLoop — never returns
; -----------------------------------------------------------------------------
GameLoop:
  jsr HalWaitFrame
  inc FrameCounter              ; Free-running from power-on; seeds the RNG

  jsr RenderFlush               ; Screen writes happen in vertical blank only
  jsr InputPoll

  lda GameState                 ; Dispatch on the current screen state
  cmp #STATE_TITLE
  beq @Title
  cmp #STATE_PLAY
  beq @Play
  cmp #STATE_PAUSE
  beq @Pause
  jmp StateGameOver

@Title:
  jsr StateTitle
  jmp @Audio
@Play:
  jsr StatePlay
  jmp @Audio
@Pause:
  jsr StatePause

@Audio:
  jsr AudioTick
  jmp GameLoop

; =============================================================================
;   States (SPEC 13)
; =============================================================================

; -----------------------------------------------------------------------------
;   StateTitle — blinking prompt over the drawn screen, and the magic field
;   SPEC 13.1. There are no help pages: the controls are part of the screen
;   image, so the only things moving here are the prompt and the field.
; -----------------------------------------------------------------------------
StateTitle:
  lda NeedsRedraw
  beq @Live
  lda #0
  sta NeedsRedraw
  jsr DrawTitleScreen
  jsr RenderDirtyReset          ; A full blit went behind the renderer's back

@Live:
  ; TODO: blink the prompt every 30 frames, and shimmer the magic field —
  ; one NextRandom for a cell in the 14 x 2 block, one for a tile in
  ; ART_BASE..ART_BASE+ART_TILES-1, one RenderMark.
  lda InputEdge
  and #(INPUT_FIRE | INPUT_UP)  ; Fire, or SPACE, which the keyboards fold
  beq @Done                     ;   into UP so it can rotate in play (D15)

  jsr RngSeed                   ; SPEC 15 — seed from reaction time, not a constant
  jsr GameStart
@Done:
  rts

; -----------------------------------------------------------------------------
;   GameStart — enter play from the title screen
; -----------------------------------------------------------------------------
GameStart:
  jsr ScoreReset
  jsr BoardClear

  lda #1
  sta Level
  lda #0
  sta TilesCleared
  sta DasDir                    ; No direction is held into a new game
  sta DasTimer
  sta PieceDirty

  jsr DrawPlayScreen            ; The whole screen at once, behind the
  jsr RenderDirtyReset          ;   renderer's back — so drop anything queued
                                ;   against the screen that just went away

  jsr TextBannerClear           ; The play image ships with the band reading
                                ;   `~~ PAUSED ~~` (SPEC 12.1); play owns it
  jsr RenderScore               ; The panel fields are code's, not the image's
  jsr RenderHigh
  jsr RenderLevel
  jsr RenderBoard               ; Queued across as many frames as it takes

  jsr PieceGenerateNext         ; Fill the preview...
  jsr PieceSpawn                ; ...then promote it and refill. The board is
  jsr PieceGenerateNext         ;   empty, so the spawn cannot be blocked.
  jsr RenderNext

  lda #PLAY_FALLING
  sta PlayState
  lda #STATE_PLAY
  sta GameState
  rts

; -----------------------------------------------------------------------------
;   StatePlay — the game
;   SPEC 13.2. One frame is: advance whatever the play sub-state is doing,
;   then queue whatever changed. Cascades run as sub-states rather than in a
;   blocking loop so animation stays on the frame clock.
; -----------------------------------------------------------------------------
StatePlay:
  lda InputEdge
  and #INPUT_PAUSE
  bne @ToPause

  lda PlayState
  cmp #PLAY_FALLING
  beq @Falling
  cmp #PLAY_LOCKING
  beq @Locking
  cmp #PLAY_GRAVITY
  beq @Gravity
  cmp #PLAY_ARE
  beq @Are
  jmp @Draw                     ; GLOW and SHATTER are P6's

@Falling:
  jsr PlayFalling
  jmp @Draw
@Locking:
  jsr PlayLocking
  jmp @Draw
@Gravity:
  jsr PlayGravity
  jmp @Draw
@Are:
  jsr PlayAre

  ; --- draw the piece, once whatever else wanted the screen has finished ----
  ;   D14. RenderBoard is a cursor that feeds the ring over several frames
  ;   (D12), so marks made while one is outstanding are drawn BEFORE the
  ;   redraw reaches those cells and are then painted over. Holding the piece
  ;   back until the redraw has finished is one byte and always right; the
  ;   alternative is a piece that vanishes for four frames after every pause.
@Draw:
  lda PieceDirty
  beq @Done
  lda RedrawIdx
  bpl @Done                     ; A board redraw is still in flight
  lda #0
  sta PieceDirty
  jsr RenderPiece
@Done:
  rts

@ToPause:
  lda #STATE_PAUSE
  sta GameState
  ; TODO (P7): wash the well with TILE_WASH so a pause cannot be used to study
  ; the board (13.3). A wash, not a blank — a blanked well reads as crashed.
  rts

; -----------------------------------------------------------------------------
;   PlayFalling — steer the piece, and drop it a row when the timer runs out
;   SPEC 5.5, 5.6, 11.3
; -----------------------------------------------------------------------------
PlayFalling:
  jsr PieceControl              ; Rotation and DAS; the result is ignored here
                                ;   because there is no lock delay to reset yet
  jsr PieceFallRate
  sta Tmp0
  lda GravityTimer              ; Pressing DOWN mid-wait must shorten the wait
  cmp Tmp0                      ;   in progress, not just the next one
  bcc @Tick
  lda Tmp0
  sta GravityTimer
@Tick:
  dec GravityTimer
  bne @Done
  jsr PieceStep
  bcs @Land
  jsr PieceFallRate
  sta GravityTimer
  rts

@Land:
  ldx Region
  lda LockDelay,x
  sta LockTimer
  lda #PLAY_LOCKING
  sta PlayState
@Done:
  rts

; -----------------------------------------------------------------------------
;   PlayLocking — the lock delay, and the moves that may reset it
;   SPEC 5.6 — a horizontal move resets the delay LOCK_RESET_MAX times; after
;   that it runs out regardless. Rotation never resets it. A move that opens a
;   gap underneath resumes falling, and the reset count carries.
; -----------------------------------------------------------------------------
PlayLocking:
  jsr PieceControl
  bcc @Settled
  lda LockResets
  cmp #LOCK_RESET_MAX
  bcs @Settled
  inc LockResets
  ldx Region
  lda LockDelay,x
  sta LockTimer

@Settled:
  jsr PieceCanFall
  bcc @Tick
  lda #PLAY_FALLING             ; It moved over a hole — fall again. SPEC 5.6
  sta PlayState                 ;   says the lock counter clears here and the
                                ;   reset count does not; nothing reads
                                ;   LockTimer while falling and the next
                                ;   landing loads it fresh, so it is already
                                ;   clear in every sense that matters.
  jsr PieceFallRate
  sta GravityTimer
  rts

@Tick:
  dec LockTimer
  bne @Done
  jsr PieceLock
  jsr CascadeBegin              ; SPEC 8 — the cascade starts the moment the
  jmp CascadeEnter              ;   piece is board, and runs as sub-states
@Done:
  rts

; -----------------------------------------------------------------------------
;   CascadeEnter — run one cascade step and choose the sub-state after it
;   In:  ChainStep set        Out: PlayState set.  Modifies: A, X, Y
;   SPEC 8, D4. Called from the lock, and again from the bottom of every fall.
;
;   A step that clears something hands over to PLAY_GRAVITY; a step that finds
;   nothing is where the cascade settles and the next piece is queued. P6
;   inserts PLAY_GLOW and PLAY_SHATTER ahead of the fall without changing
;   either branch.
; -----------------------------------------------------------------------------
CascadeEnter:
  jsr CascadeStep
  bcc @Settle

  jsr BoardGravityBegin         ; Something went; let what was above it fall
  lda #PLAY_GRAVITY
  sta PlayState
  rts

@Settle:
  jsr CascadeSettle             ; P4 banks the points here; P6 raises the
                                ;   chain banner
  ldx Region
  lda AreDelay,x
  sta AreTimer
  lda #PLAY_ARE
  sta PlayState
  rts

; -----------------------------------------------------------------------------
;   PlayGravity — the pile falls into the holes the clear left
;   SPEC 8 step 8, SPEC 14 — a row every FALL_FRAMES, and when a row moves
;   nothing the board has settled and the next step scans it.
;
;   The row itself may take more than one frame: BoardGravityStep is a cursor
;   that stops when the dirty ring is full (board.asm). The beat only starts
;   once the row has actually landed, so a heavy board falls a little slower
;   rather than losing cells off the screen.
; -----------------------------------------------------------------------------
PlayGravity:
  lda GravIdx
  bpl @Working                  ; A row is still coming down

  dec AnimTimer
  bne @Done
  lda GravMoved
  beq @Landed                   ; The last row moved nothing: everything is
  jsr BoardGravityBegin         ;   resting on something

@Working:
  jsr BoardGravityStep
  bcc @Done                     ; The ring filled — the rest waits for a flush
  lda #FALL_FRAMES              ; The row is down; hold it there for the beat
  sta AnimTimer
@Done:
  rts

@Landed:
  inc ChainStep                 ; SPEC 8 step 9
  jmp CascadeEnter

; -----------------------------------------------------------------------------
;   PlayAre — the entry delay, then the next piece
;   SPEC 5.6, 13.4 — a blocked spawn is game over.
; -----------------------------------------------------------------------------
PlayAre:
  dec AreTimer
  bne @Done
  jsr PieceSpawn
  bcs @Over
  jsr PieceGenerateNext
  jsr RenderNext
  lda #PLAY_FALLING
  sta PlayState
@Done:
  rts

@Over:
  lda #STATE_GAMEOVER           ; P7 owns the petrify animation; for now the
  sta GameState                 ;   game simply stops
  rts

; -----------------------------------------------------------------------------
;   StatePause
; -----------------------------------------------------------------------------
StatePause:
  lda InputEdge
  and #(INPUT_PAUSE | INPUT_FIRE)
  beq @Done
  lda #STATE_PLAY
  sta GameState
  jsr RenderBoard               ; Put the board back...
  lda PlayState                 ;   ...and the piece on top of it, once the
  cmp #PLAY_GLOW                ;   redraw has gone by (D14) — but only while
  bcs @Done                     ;   there IS one. From GLOW on up the piece is
  lda #1                        ;   in the board and PieceA-C are stale; the
  sta PieceDirty                ;   cascade may have taken those cells away
@Done:                          ;   entirely.
  rts

; -----------------------------------------------------------------------------
;   StateGameOver — petrify, banner, back to the title
;   SPEC 13.4
; -----------------------------------------------------------------------------
StateGameOver:
  ; TODO: petrify the well from the bottom up, 2 frames a row, then the banner
  ; and a 10 second timeout. Each cell keeps its own shape —
  ;   PETRIFY_BASE + (tile & GLYPH_MASK)
  ; — and empty cells stay empty (13.4).
  lda InputEdge
  and #(INPUT_FIRE | INPUT_UP)  ; Fire, or SPACE (D15)
  beq @Done
  lda #STATE_TITLE
  sta GameState
  lda #1
  sta NeedsRedraw
@Done:
  rts

; =============================================================================
;   Static screen drawing
; =============================================================================
;   The whole static layout — panel frame, labels, and the margin artwork that
;   fills the screen either side of it — comes out of the editors as one
;   name-table image per platform. Code only ever draws over the top of it:
;   the well, the score and level digits, the preview, and the message band.
;
;   All six images are real. They come out of artwork/WizardsLab.tms9918 —
;   the master — by way of `make artwork`. See data/README.md.
; =============================================================================

DrawTitleScreen:
  lda #<TitleScreen
  sta SrcPtr
  lda #>TitleScreen
  sta SrcPtr+1
  lda #<TitleColor
  sta Ptr1
  lda #>TitleColor
  sta Ptr1+1
  jmp HalBlitScreen

DrawPlayScreen:
  lda #<PlayScreen
  sta SrcPtr
  lda #>PlayScreen
  sta SrcPtr+1
  lda #<PlayColor
  sta Ptr1
  lda #>PlayColor
  sta Ptr1+1
  jmp HalBlitScreen
