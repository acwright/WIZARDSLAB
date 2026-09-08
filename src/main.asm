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
;   the pile falls into the holes, chains keep going until nothing matches, all
;   of it scores and ramps the level, the five reagents fire and set each other
;   off, a clear glows and shatters on the frame clock instead of happening
;   between two frames, the arcade loop around all of it is closed — title,
;   play, pause, game over, title — and every event of SPEC 16 makes a noise
;   (PLAN.md P2 to P8). The game is complete; what is left is real hardware
;   (P10).
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
  sta TitlePhase                ; The title prompt starts lit, and the game-over
  sta OverSecs                  ;   screen starts un-entered. Both are BSS, and
                                ;   BSS is not cleared on all three machines.
  lda #1
  sta PrismTimer                ; A zero here would DEC to 255 and stall the
                                ;   prism's rotation for four seconds
  lda #TINT_NONE                ; BSS is not cleared on all three machines, and
  sta TintColor                 ;   a garbage colour key here would draw the
                                ;   title screen's tiles of that colour white
                                ;   on the Commodores. Set before anything
                                ;   plots a cell, not in HalColorFlash, which
                                ;   reads it to undo the last flash (hal.inc).

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
  jsr StateGameOver             ; JSR, not JMP — every state handler ends in an
  jmp @Audio                    ;   RTS, and a JMP here would hand that RTS the
                                ;   return address of the JSR GameInit that the
                                ;   cart entry point never expects back. The
                                ;   first loss unwound the loop into GameInit;
                                ;   the second pulled from an empty stack.

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

  jsr AnimTitleBegin            ; ...and the prompt blinks from lit, so it never
                                ;   starts a second visit dark
@Live:
  jsr AnimTitleField            ; The two things that move here, and the whole
  jsr AnimTitleBlink            ;   of the screen's animation (SPEC 13.1)

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
  sta BannerTimer               ; Nothing from the last game is still up
  sta PrismFrame
  lda #1
  sta PrismTimer
  lda #TINT_NONE                ; ...and no colour is still flashing white, on
  jsr HalColorFlash             ;   a machine where that is a VDP register and
                                ;   not a byte of RAM (SPEC 4.6)

  jsr DrawPlayScreen            ; The whole screen at once, behind the
  jsr RenderDirtyReset          ;   renderer's back — so drop anything queued
                                ;   against the screen that just went away

  jsr TextBannerClear           ; The play image ships with the band reading
                                ;   `~~ PAUSED ~~` (SPEC 12.1); play owns it,
                                ;   and so does whatever the last game left in
                                ;   it — GAME OVER stays up until here
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
  jsr ScoreFlashTick            ; SPEC 9.8 — the HIGH field blinking after an
                                ;   overtake. Play never stops for it, so it
                                ;   ticks alongside whatever the sub-state is
                                ;   doing rather than inside one.
  jsr AnimBannerTick            ; ...and neither does it for a banner (SPEC 14)
  jsr AnimPrismTick             ; ...nor for the one tile that moves at rest

  lda InputEdge
  and #INPUT_PAUSE
  bne @ToPause

  lda PlayState
  cmp #PLAY_FALLING
  beq @Falling
  cmp #PLAY_LOCKING
  beq @Locking
  cmp #PLAY_GLOW
  beq @Glow
  cmp #PLAY_SHATTER
  beq @Shatter
  cmp #PLAY_GRAVITY
  beq @Gravity
  cmp #PLAY_ARE
  beq @Are
  jmp @Draw                     ; Not a state anything sets

@Falling:
  jsr PlayFalling
  jmp @Draw
@Locking:
  jsr PlayLocking
  jmp @Draw
@Glow:
  jsr PlayGlow
  jmp @Draw
@Shatter:
  jsr PlayShatter
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
  lda #<MsgPaused               ; SPEC 12.2 — without this the screen does not
  sta Ptr1                      ;   change at all on a pause, and a paused game
  lda #>MsgPaused               ;   is indistinguishable from a hung one
  sta Ptr1+1
  jsr TextBanner
  jmp RenderWash                ; SPEC 13.3 — the well is covered, not blanked,
                                ;   so a pause cannot be used to study the
                                ;   board. Queued as a cursor because 96 cells
                                ;   do not fit the ring (render.asm, D12), and
                                ;   AFTER the banner, so the banner's marks are
                                ;   in the ring before the wash starts filling
                                ;   it

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
  jsr PieceFallRate             ; ...and C tells us whose rate the row that
  sta GravityTimer              ;   just fell used. STA leaves it alone.
  bcs @Done
  jmp ScoreSoftDrop             ; SPEC 9.6 — one point, one row

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
;   A step that marks something hands over to PLAY_GLOW, and the removal and
;   the fall follow it twelve frames later; a step that finds nothing is where
;   the cascade settles and the next piece is queued.
;
;   Nothing has come off the board when CascadeScan returns — that is the whole
;   point of the split (cascade.asm). CascadeFinish does the taking, at the far
;   end of PLAY_SHATTER.
; -----------------------------------------------------------------------------
CascadeEnter:
  jsr CascadeScan
  bcc @Settle
  lda #SFX_MATCH                ; SPEC 16 effect 4, and the chime is pitched by
  jsr SfxPlay                   ;   ChainStep when AudioTick starts it. A
                                ;   reagent that fired inside the scan has
                                ;   already asked for a louder sound and keeps
                                ;   the channel (audio.asm)
  jmp AnimGlowBegin             ; SPEC 8 step 5

@Settle:
  jsr CascadeSettle             ; The star multiplier and the bank (SPEC 8
                                ;   SETTLE)
  lda ChainStep                 ; SPEC 8 SETTLE, SPEC 14 — a chain of two links
  sec                           ;   or more is worth saying out loud. ChainStep
  sbc #1                        ;   counts the step that found nothing as well,
  cmp #2                        ;   so the links are one fewer
  bcc @Are
  jsr AnimBannerChain

@Are:
  ldx Region
  lda AreDelay,x
  sta AreTimer
  lda #PLAY_ARE
  sta PlayState
  rts

; -----------------------------------------------------------------------------
;   PlayGlow — hold the glow, the beams and the fireball's flash (SPEC 14)
;   The window is one timer however many things are showing inside it: they all
;   start together and the longest decides how long it lasts (anim.asm).
; -----------------------------------------------------------------------------
PlayGlow:
  dec AnimTimer
  bne @Done
  jmp AnimGlowEnd               ; ...which starts the shatter
@Done:
  rts

; -----------------------------------------------------------------------------
;   PlayShatter — the removal ring, VFX_FRAMES a tile (SPEC 14)
;   The board is finally emptied at the end of this, not at the start of it:
;   every frame up to here has been drawing over cells that still hold their
;   own tiles (cascade.asm).
; -----------------------------------------------------------------------------
PlayShatter:
  dec AnimTimer
  bne @Done
  inc AnimStep
  lda AnimStep
  cmp AnimSteps
  bcs @Over
  lda #VFX_FRAMES
  sta AnimTimer
  lda #ANIM_SHATTER
  jmp AnimMarked

@Over:
  jsr CascadeFinish             ; SPEC 8 steps 6 and 7
  jsr BoardGravityBegin         ; ...and let what was above it fall
  lda #PLAY_GRAVITY
  sta PlayState
@Done:
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
  lda #SFX_GAMEOVER
  jsr SfxPlay
  jsr AnimPetrifyBegin          ; The well turns to stone from the floor up
  lda #0                        ;   while StateGameOver holds the input off
  sta OverSecs                  ; The screen proper has not started yet — the
                                ;   petrify runs first (SPEC 13.4 step 2)
  lda #STATE_GAMEOVER
  sta GameState
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
  jsr TextBannerClear           ; The banner comes down...
  jsr RenderBoard               ; ...the board goes back up...
  lda PlayState                 ;   ...and the piece on top of it, once the
  cmp #PLAY_GLOW                ;   redraw has gone by (D14) — but only while
  bcs @Done                     ;   there IS one. From GLOW on up the piece is
  lda #1                        ;   in the board and PieceA-C are stale; the
  sta PieceDirty                ;   cascade may have taken those cells away
@Done:                          ;   entirely.
  rts

; -----------------------------------------------------------------------------
;   StateGameOver — petrify, banner, fanfare, back to the title
;   SPEC 13.4, in its own order: the well sets to stone, THEN the band says so,
;   and only then does the screen start counting itself out.
;
;   OverSecs is the phase as well as the count. It is zero for the length of
;   the petrify and never zero afterwards, because the frame it would reach
;   zero is the frame this state ends — so the one-shot in the middle needs no
;   flag of its own.
;
;   Nothing here ticks the banner down (AnimBannerTick is StatePlay's), which
;   is what leaves GAME OVER up for the whole ten seconds rather than the 45
;   frames every other banner gets. GameStart clears the band on the way out.
; -----------------------------------------------------------------------------
StateGameOver:
  jsr AnimPetrifyTick           ; SPEC 13.4 step 2, a row every PETRIFY_FRAMES
  bcs @Done                     ; Still setting. A press during the petrify is
                                ;   ignored rather than queued: the animation
                                ;   is the game telling the player it is over
                                ;   and skipping it reads as a dropped input.
  lda OverSecs
  bne @Waiting

  jsr AnimBannerOver            ; SPEC 13.4 step 3
  lda HighOwned                 ; Step 4 — the fanfare and the flash, but only
  beq @Start                    ;   if THIS game took the record. HighOwned is
                                ;   what says so, and ScoreReset clears it for
                                ;   the next one (score.asm, SPEC 9.8)
  lda #SFX_HIGHSCORE
  jsr SfxPlay
  lda #HIGH_FLASH_BLINKS
  sta HighFlash
  ldx Region
  lda BlinkHalf,x
  sta HighTimer
@Start:
  lda #GAMEOVER_SECS
  sta OverSecs
  ldx Region
  lda SecondFrames,x
  sta OverTimer
  rts

@Waiting:
  jsr ScoreFlashTick            ; The HIGH field blinks here for the same
                                ;   reason it does in play — nothing else is
                                ;   calling it now that StatePlay has stopped
  dec OverTimer
  bne @Input
  ldx Region
  lda SecondFrames,x
  sta OverTimer
  dec OverSecs
  beq @ToTitle                  ; SPEC 13.4 step 5 — ten seconds, unattended
@Input:
  lda InputEdge
  and #(INPUT_FIRE | INPUT_UP)  ; Fire, or SPACE (D15)
  beq @Done
@ToTitle:
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
