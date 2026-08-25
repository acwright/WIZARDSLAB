; =============================================================================
;   audio.asm — Wizards Lab, sound
; =============================================================================
;   SPEC.md section 16. Out of scope for the first playable build, but the
;   hook is here from the start so game logic never has to be revisited to add
;   it: logic writes an effect id to SfxRequest and forgets about it.
;
;   The AC6502 and the C64 both have a SID and can share a driver — only the
;   register base differs ($9800 against $D400). The VIC-20 needs its own,
;   against $900A-$900E.
; =============================================================================

SFX_MOVE        = 1
SFX_ROTATE      = 2
SFX_LOCK        = 3
SFX_MATCH       = 4
SFX_FIREBALL    = 5
SFX_BOLT        = 6
SFX_BOMB        = 7
SFX_STAR        = 8
SFX_PRISM       = 9
SFX_LEVELUP     = 10
SFX_HIGHSCORE   = 11
SFX_GAMEOVER    = 12

; -----------------------------------------------------------------------------
;   AudioInit — silence everything
; -----------------------------------------------------------------------------
AudioInit:
  lda #0
  sta SfxRequest
  sta SfxTimer
  rts

; -----------------------------------------------------------------------------
;   AudioTick — called once per frame, consumes SfxRequest
; -----------------------------------------------------------------------------
AudioTick:
  ; TODO: start a new effect when SfxRequest is non-zero, then advance the
  ; envelope of whatever is playing. Calls HalSfx for the register writes.
  lda #0
  sta SfxRequest
  rts
