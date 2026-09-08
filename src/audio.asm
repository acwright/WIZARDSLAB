; =============================================================================
;   audio.asm — Wizards Lab, sound
; =============================================================================
;   SPEC.md section 16. Twelve effects, one channel, and none of it knows what
;   a sound chip is: an effect is a list of STEPS in ROM (tables.inc), a step
;   is a duration, a timbre and a note, and pushing one at the hardware is
;   HalSfx's whole job (hal.inc).
;
;   That split is the opposite way round from the one SPEC 16 assumed. It said
;   the AC6502 and the C64 would share a SID driver and the VIC-20 would need
;   its own, which is true of the twenty lines that write registers and of
;   nothing else: the sequencing, the priority, the envelope of an effect
;   across frames and every note in the game are the same on all three, so
;   they live here and are shared by all three rather than by two (PLAN.md
;   D22). What each platform still owns is a note table and five stores.
;
;   ONE CHANNEL. The id is the priority — SPEC 16 lists the twelve from the
;   quietest event to the loudest — so a request takes the channel only if its
;   id is at least the id of what is already playing. That is what keeps the
;   move blip out of the middle of a fireball, and it is why SfxPlay exists
;   rather than logic storing into SfxRequest: a lock, a match and a bomb can
;   all be requested in ONE frame, and last-write-wins would pick whichever
;   the code happened to reach last.
;
;   Nothing here waits, loops over cells, or touches the screen. AudioTick is
;   fifteen cycles on a frame where nothing changes and a step's worth of
;   register writes on a frame where something does, so it cannot delay a
;   frame however the frame is going.
; =============================================================================

; -----------------------------------------------------------------------------
;   AudioInit — silence, and whatever the sound chip needs to be told once
;   Out: nothing.  Modifies: A, X
; -----------------------------------------------------------------------------
AudioInit:
  lda #0
  sta SfxRequest
  sta SfxId
  sta SfxTimer
  sta SfxShift
  sta SfxStepIdx
  ldx #0
  lda #TIMBRE_OFF
  jmp HalSfx

; -----------------------------------------------------------------------------
;   SfxPlay — ask for an effect
;   In:  A = SFX_* id
;   Out: nothing.  Modifies: A only — X, Y and zero page are untouched, because
;        half the callers are in the middle of a walk that is holding a cursor
;        in a register (cascade.asm).
;
;   The loudest request in a frame is the one that survives, and the id is the
;   loudness. A quieter one is not queued for later: by the next frame the
;   event it belonged to is over.
; -----------------------------------------------------------------------------
SfxPlay:
  cmp SfxRequest
  bcc @Done                     ; Something at least as loud is already asked
  sta SfxRequest                ;   for this frame
@Done:
  rts

; -----------------------------------------------------------------------------
;   AudioTick — one frame of sound. Called from the bottom of the main loop.
;   Out: nothing.  Modifies: A, X, Y
; -----------------------------------------------------------------------------
AudioTick:
  lda SfxRequest
  beq @Advance                  ; Nothing asked for — carry on with what plays
  ldx #0
  stx SfxRequest                ; Consumed either way: a request that loses is
  cmp SfxId                     ;   dropped, not held over
  bcc @Advance
  jmp SfxBegin

@Advance:
  lda SfxId
  beq @Done                     ; Silent
  dec SfxTimer
  bne @Done                     ; The step still has frames left in it
  jmp SfxStep                   ; ...and when it does not, the next one starts
@Done:
  rts

; -----------------------------------------------------------------------------
;   SfxBegin — start an effect from its first step
;   In:  A = SFX_* id
;   Out: nothing.  Modifies: A, X, Y
;
;   Eleven of the twelve play at the pitch tables.inc wrote them at. The match
;   chime is the one SPEC 16 says rises with the chain, and it rises by
;   transposing the whole effect rather than by having a step list per depth.
; -----------------------------------------------------------------------------
SfxBegin:
  sta SfxId
  ldx #0
  cmp #SFX_MATCH
  bne @Shift

  lda ChainStep                 ; 1 on the first step of a cascade (SPEC 8)
  beq @Shift                    ; Never zero in practice; X is already 0
  sec
  sbc #1
  asl a                         ; SFX_CHAIN_SHIFT semitones a link
  cmp #(SFX_CHAIN_MAX + 1)
  bcc @Capped
  lda #SFX_CHAIN_MAX
@Capped:
  tax

@Shift:
  stx SfxShift
  ldx SfxId
  lda SfxOffsets - 1,x          ; The id is 1-based; the table is not
  sta SfxStepIdx
  ; falls through into the first step

; -----------------------------------------------------------------------------
;   SfxStep — play the step at SfxStepIdx and advance past it
;   Out: nothing.  Modifies: A, X, Y
;   A zero frame count is the end of the effect and returns the channel to
;   silence — which is a real event on a SID, where it is the gate coming down.
; -----------------------------------------------------------------------------
SfxStep:
  ldx SfxStepIdx
  lda SfxSteps,x
  beq @End
  sta SfxTimer

  lda SfxSteps + 2,x            ; The note...
  clc
  adc SfxShift                  ;   ...transposed, for the match chime
  cmp #(NOTE_MAX + 1)
  bcc @Note
  lda #NOTE_MAX                 ; Both note tables stop at C6 and a chain deep
@Note:                          ;   enough to push past it clamps rather than
  tay                           ;   reading off the end of one
  lda SfxSteps + 1,x            ; The timbre
  pha
  txa
  clc
  adc #SFX_STEP_BYTES
  sta SfxStepIdx
  tya
  tax                           ; X = note
  pla                           ; A = timbre
  jmp HalSfx

@End:
  lda #0
  sta SfxId
  ldx #0
  lda #TIMBRE_OFF
  jmp HalSfx
