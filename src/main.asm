; =============================================================================
;   main.asm — Wizards Lab, shared entry point and main loop
; =============================================================================
;   Included by every platform's WizardsLab.asm after that file has defined
;   PANEL_X / PANEL_Y and its half of the HAL (see hal.inc). Nothing below
;   touches hardware.
;
;   BOOTSTRAP STATUS
;   ----------------
;   What runs today is SPEC.md Appendix D step 1-2: the machine boots, the
;   tileset loads, and the static screens blit at the right offset with fire
;   moving between them. That is deliberately the whole of it — it exercises
;   every platform-specific thing (cartridge header, video mode, tile format,
;   colour model, frame sync, input) with none of the game, so when the game
;   goes in, anything that breaks is the game.
;
;   Everything the state machine calls below is a stub in its own module.
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
  sta InputNow
  sta InputPrev
  sta InputEdge
  sta TitlePage

  jsr ScoreReset
  jsr BoardClear

  lda #STATE_TITLE
  sta GameState
  lda #1
  sta NeedsRedraw
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
;   StateTitle — logo, blinking prompt, auto-cycling help pages
;   SPEC 13.1. The help pages are the only place the rules are taught, so the
;   reagent legend gets the most room of the four.
; -----------------------------------------------------------------------------
StateTitle:
  lda NeedsRedraw
  beq @Live
  lda #0
  sta NeedsRedraw
  jsr DrawTitleScreen

@Live:
  ; TODO: blink the prompt every 30 frames, cycle help pages every 240.
  lda InputEdge
  and #INPUT_FIRE
  beq @Done

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
  jsr RenderDirtyReset

  lda #1
  sta Level
  lda #0
  sta TilesCleared

  jsr DrawPlayScreen
  jsr PieceGenerateNext         ; Fill the preview...
  jsr PieceSpawn                ; ...then promote it and refill
  jsr PieceGenerateNext

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

  ; TODO: dispatch on PlayState —
  ;   PLAY_FALLING   input, DAS, gravity, land detection
  ;   PLAY_LOCKING   lock delay with up to LOCK_RESET_MAX moves
  ;   PLAY_GLOW      matched cells showing glyph +6
  ;   PLAY_SHATTER   matched cells showing the white shatter tile
  ;   PLAY_GRAVITY   one row every FALL_FRAMES until settled
  ;   PLAY_ARE       entry delay, then spawn or game over
  rts

@ToPause:
  lda #STATE_PAUSE
  sta GameState
  ; TODO: blank the well so a pause cannot be used to study the board (13.3)
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
  jsr RenderBoard               ; Put the board back
@Done:
  rts

; -----------------------------------------------------------------------------
;   StateGameOver — petrify, banner, back to the title
;   SPEC 13.4
; -----------------------------------------------------------------------------
StateGameOver:
  ; TODO: fill the well with TILE_STONE from the bottom up, 2 frames a row,
  ; then the banner and a 10 second timeout.
  lda InputEdge
  and #INPUT_FIRE
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
;   The images are PLACEHOLDER until the artwork lands. See data/README.md.
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
