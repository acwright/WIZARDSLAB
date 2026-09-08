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
;   AND ONE LEVEL. Neither sound chip has a per-voice volume, so "quieter"
;   cannot be a property of a note: it is a master register the platform writes
;   on its way past, and the byte that carries the choice to it is the timbre,
;   bit 7 (constants.inc). Nothing the GAME plays ever sets it. It exists for
;   the title screen, which plays the same twelve effects at half volume
;   underneath a cauldron (ambience.asm).
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
  sta SfxLevel                  ; Full volume, and no ambience — the title
                                ;   screen turns both on for itself
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
  beq @Idle                     ; Silent...
  dec SfxTimer
  bne @Done                     ; The step still has frames left in it
  jmp SfxStep                   ; ...and when it does not, the next one starts
@Done:
  rts

@Idle:                          ; ...and silence is where the title screen puts
  jmp AmbienceTick              ;   its cauldron. Nine cycles and an RTS in
                                ;   play, where the ambience is off

; -----------------------------------------------------------------------------
;   SfxBegin — start an effect from its first step
;   In:  A = SFX_* id
;   Out: nothing.  Modifies: A, X, Y
;
;   Eleven of the twelve play at the pitch tables.inc wrote them at. The match
;   chime is the one SPEC 16 says rises with the chain, and it rises by
;   transposing the whole effect rather than by having a step list per depth —
;   which is the whole of what this routine does before it hands over to
;   SfxBeginShifted below.
; -----------------------------------------------------------------------------
SfxBegin:
  ldx #0
  cmp #SFX_MATCH
  bne SfxBeginShifted

  pha                           ; The id; SfxBeginShifted wants it in A
  lda ChainStep                 ; 1 on the first step of a cascade (SPEC 8)
  beq @Flat                     ; Never zero in practice; X is already 0
  sec
  sbc #1
  asl a                         ; SFX_CHAIN_SHIFT semitones a link
  cmp #(SFX_CHAIN_MAX + 1)
  bcc @Capped
  lda #SFX_CHAIN_MAX
@Capped:
  tax
@Flat:
  pla
  ; falls through

; -----------------------------------------------------------------------------
;   SfxBeginShifted — start an effect transposed by a given number of semitones
;   In:  A = SFX_* id, X = semitones to add to every note of it
;   Out: nothing.  Modifies: A, X, Y
;
;   Split out of SfxBegin for the title screen's ambience, which pitches every
;   bubble by a fresh random amount and would otherwise have to write SfxShift
;   after SfxBegin had already played the first step at the wrong pitch
;   (ambience.asm). It takes the channel unconditionally and is not a request:
;   the only caller outside SfxBegin knows the channel is silent because it is
;   only reached on a frame where it was.
; -----------------------------------------------------------------------------
SfxBeginShifted:
  sta SfxId
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
  lda SfxSteps + 1,x            ; The timbre...
  ora SfxLevel                  ;   ...and how loud, which is bit 7 of the same
                                ;   byte and is zero for everything the game
                                ;   itself plays (constants.inc). A step whose
                                ;   timbre is TIMBRE_OFF — a rest — comes out of
                                ;   here as $80, and every HalSfx masks the bit
                                ;   off before it looks, so a quiet rest is
                                ;   still a rest
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
  lda SfxLevel                  ; TIMBRE_OFF at the level the channel is AT, and
                                ;   TIMBRE_OFF is zero, so the level is the
                                ;   whole byte. Letting go at full volume
                                ;   instead would put the master register back
                                ;   up before the SID's release tail of a quiet
                                ;   note had finished, and every bubble on the
                                ;   title screen would end in a click
                                ;   (include/sid.inc)
  jmp HalSfx
