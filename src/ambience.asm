; =============================================================================
;   ambience.asm — Wizards Lab, the sound of the title screen
; =============================================================================
;   SPEC 13.1 gives the title screen two moving things and no sound at all.
;   This is a third: not music, which one channel and no envelope cannot carry
;   for thirty seconds without becoming a nursery rhyme, but the ROOM. A
;   cauldron bubbling away somewhere under the page, and every so often one of
;   the game's own effects drifting past at half volume as though an experiment
;   two benches over just went off.
;
;   HOW IT FITS IN ONE CHANNEL. It does not mix, because nothing here can mix:
;   there is one voice and no way to sum two sounds into it. What it does
;   instead is fill the gaps. AudioTick calls this from the frame where the
;   channel fell silent and from no other (audio.asm), so the ambience only
;   ever speaks when nothing else is speaking, and a bubble is not a special
;   case of anything — it is an effect out of the same table, begun through the
;   same driver, at half volume and a random pitch.
;
;   That last part is what stops it sounding like a loop. There are three
;   cauldron sounds; there are sixteen entries in AmbTable saying how often
;   each of them and each of the five borrowed effects comes up; every one is
;   transposed by a fresh 0-7 semitones as it starts; and the quiet between
;   them is rolled every time. Two random bytes and a table lookup per sound.
;
;   WHY IT NEEDS NO OFF SWITCH IN PLAY. SfxLevel is both the volume and the
;   flag, and the game never sets it. A frame of play reaches AmbienceTick only
;   when nothing is sounding, reads one byte, finds zero and returns: nine
;   cycles, and no branch anywhere else in the audio path (ram.inc).
; =============================================================================

; -----------------------------------------------------------------------------
;   AmbienceBegin — the lab starts murmuring
;   Out: nothing.  Modifies: A
;   Called from the title screen's redraw, beside AnimTitleBegin, so a second
;   visit in a session sounds like the first one (main.asm).
; -----------------------------------------------------------------------------
AmbienceBegin:
  lda #TIMBRE_QUIET             ; Half volume from here until GameStart, and
  sta SfxLevel                  ;   the flag that says this routine is live
  lda #AMB_GAP_MIN
  sta AmbTimer                  ; A beat before the first sound, not a bloop on
  rts                           ;   the frame the screen appears — the title
                                ;   arrives from a game-over fanfare as often as
                                ;   from a cold boot, and a cauldron that starts
                                ;   ON the cut reads as part of the fanfare

; -----------------------------------------------------------------------------
;   AmbienceEnd — and stops
;   Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2 (HalSfx)
;
;   Cuts whatever is sounding rather than letting it finish, because what
;   follows this is the play screen and the first thing on it is a piece
;   spawning. A bubble carried over the cut would be the game's first noise.
; -----------------------------------------------------------------------------
AmbienceEnd:
  lda #0
  sta SfxLevel
  sta SfxId
  sta SfxRequest                ; Nothing on the title screen asks for a sound,
                                ;   but a byte of BSS is not a promise
  ldx #0
  lda #TIMBRE_OFF
  jmp HalSfx

; -----------------------------------------------------------------------------
;   AmbienceTick — one frame of it, from AudioTick's silent branch
;   Out: nothing.  Modifies: A, X, Y, Tmp0, Tmp1
;
;   The gap is counted HERE and not in the main loop, which is the reason this
;   hangs off the silent branch rather than off StateTitle: a sound that runs
;   forty frames should be followed by the full gap, not by whatever is left of
;   one that was ticking down underneath it. Silence is the only thing the
;   timer measures.
; -----------------------------------------------------------------------------
AmbienceTick:
  lda SfxLevel
  beq @Done                     ; The game is playing — this is the whole cost
  dec AmbTimer
  bne @Done                     ; Still quiet

  jsr RngNext
  and #(AMB_ENTRIES - 1)        ; Sixteen entries, so a nibble picks one evenly
  tax                           ;   without RngRange
  lda AmbTable,x
  pha                           ; The sound, parked while the pitch is rolled —
                                ;   nothing may hold a value in Tmp0-Tmp3
                                ;   across RngRange (zeropage.inc)
  lda #AMB_SHIFT_RANGE
  jsr RngRange                  ; 0 .. 7 semitones up: what makes two bubbles
  tax                           ;   two different sizes rather than one sound
  pla
  jsr SfxBeginShifted           ; The channel is silent — that is the only
                                ;   frame this routine runs on — so it is taken
                                ;   outright and not asked for (audio.asm)

  lda #AMB_GAP_RANGE
  jsr RngRange
  clc
  adc #AMB_GAP_MIN              ; AMB_GAP_MIN .. MIN + RANGE - 1 frames of quiet
  ldx SfxId                     ; What just started, read back off the channel
  cpx #SFX_CAULDRON             ;   rather than remembered across two calls
  bcs @Set                      ; The cauldron carries straight on...
  clc
  adc #AMB_GAP_EVENT            ; ...but the lab goes quiet for a while after
@Set:                           ;   something actually happens in it
  sta AmbTimer
@Done:
  rts
