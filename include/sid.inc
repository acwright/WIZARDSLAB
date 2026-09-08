; =============================================================================
;   sid.inc — the SID half of the HAL, shared by the two machines that have one
; =============================================================================
;   SPEC.md section 16: the AC6502 and the C64 "share SID driver code almost
;   verbatim (register base differs: $9800 vs $D400)". This is that code, and
;   the base is all that differs — the platform defines SID_BASE and includes
;   this file once, from inside its CODE segment.
;
;   It is the one file in include/ that is not a list of equates. It has
;   nowhere else to be: it belongs to two platforms and not to the third, so
;   it cannot live in either WizardsLab.asm without one machine including the
;   other's, and it cannot live in src/, where nothing touches hardware
;   (PLAN.md D2, D22).
;
;   What it does NOT contain is a driver in the sequencing sense. Which effect
;   is playing, which step of it, how long the step lasts and what note it is
;   are all in src/audio.asm and shared by all three machines; SidSfx is asked
;   for one note in one timbre and writes eleven registers.
;
;   ONE VOICE. Voice 1 only — the game plays one sound at a time by design
;   (audio.asm), and voices 2 and 3 are left silent rather than half-used.
;
;   Leaves the RODATA segment selected; every caller declares its own segment
;   immediately afterwards.
; =============================================================================

; --- Register offsets from SID_BASE ------------------------------------------
SID_FREQ_LO         = 0
SID_FREQ_HI         = 1
SID_PW_LO           = 2
SID_PW_HI           = 3
SID_CTRL            = 4         ; Waveform in the high nibble, GATE in bit 0
SID_AD              = 5
SID_SR              = 6
SID_VOL             = 24        ; Master volume, low nibble

; -----------------------------------------------------------------------------
;   SidSfx — HalSfx for a SID (hal.inc)
;   In:  A = TIMBRE_*, X = note (semitones above C3; ignored when A is
;        TIMBRE_OFF)
;   Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2
; -----------------------------------------------------------------------------
SidSfx:
  cmp #TIMBRE_OFF
  beq SidGateOff

  sta Tmp0                      ; The timbre, 1..4 — an index into the three
                                ;   tables at the bottom of this file
  lda SidNoteLo,x
  sta Tmp1
  lda SidNoteHi,x
  sta Tmp2

  ; --- the timbre's octave (constants.inc) ----------------------------------
  ;   A SID frequency register is linear in Hz, so an octave is a shift. On the
  ;   VIC-20 the same octave is free, because its three tone oscillators are
  ;   already an octave apart and the timbre picks between them.
  ldy Tmp0
  cpy #TIMBRE_SOFT
  bne @NotSoft
  lsr Tmp2                      ; Down one
  ror Tmp1
@NotSoft:
  cpy #TIMBRE_BRIGHT
  bne @NotBright
  asl Tmp1                      ; Up one
  rol Tmp2
@NotBright:

  ; --- the hard restart ------------------------------------------------------
  ;   Gate down with a zeroed envelope BEFORE the new note. Without it the
  ;   SID's envelope generator can be caught mid-release and skip the attack
  ;   of the note that follows — the ADSR delay bug — and every step of every
  ;   effect comes through here, so a skipped attack is a silent sound effect
  ;   rather than a quiet one.
  lda #0
  sta SID_BASE + SID_CTRL
  sta SID_BASE + SID_AD
  sta SID_BASE + SID_SR

  lda Tmp1
  sta SID_BASE + SID_FREQ_LO
  lda Tmp2
  sta SID_BASE + SID_FREQ_HI
  lda #$00                      ; A 50% pulse, which is a square wave. Only
  sta SID_BASE + SID_PW_LO      ;   TIMBRE_BRIGHT reads it, and it never
  lda #$08                      ;   changes, so it is written with everything
  sta SID_BASE + SID_PW_HI      ;   else rather than kept as state

  lda SidAD - 1,y               ; The timbre tables are 1-based: TIMBRE_OFF
  sta SID_BASE + SID_AD         ;   never reaches them
  lda SidSR - 1,y
  sta SID_BASE + SID_SR

  lda #$0F                      ; Master volume, every note. Nothing else in
  sta SID_BASE + SID_VOL        ;   the game writes it and one store is
                                ;   cheaper than a byte remembering whether
                                ;   it has been written once already
  lda SidWave - 1,y
  sta SID_BASE + SID_CTRL       ; Waveform and GATE — the note starts here
  rts

; -----------------------------------------------------------------------------
;   SidGateOff — end whatever is sounding
;   The release does the rest. Voice 1 keeps its frequency and waveform, which
;   costs nothing and means the next note writes the same registers either way.
; -----------------------------------------------------------------------------
SidGateOff:
  lda #0
  sta SID_BASE + SID_CTRL
  rts

; =============================================================================
;   SID tables
; =============================================================================

.segment "RODATA"

; --- Waveform and envelope by timbre, indexed 1..4 (constants.inc) -----------
;   TIMBRE_SOFT   triangle, decaying to a low sustain — the lock's thunk and
;                 the game-over run
;   TIMBRE_BUZZ   sawtooth, full sustain
;   TIMBRE_BRIGHT pulse, full sustain — chimes, blips and fanfares
;   TIMBRE_NOISE  noise, no sustain at all: it decays to nothing on its own,
;                 which is what makes a crack a crack rather than a hiss that
;                 lasts exactly as long as its step
SidWave:
  .byte $11, $21, $41, $81      ; ...and bit 0 of each is the gate, set
SidAD:
  .byte $08, $00, $00, $05      ; Attack 0 on all four — a sound effect that
                                ;   fades in is a sound effect that is late
SidSR:
  .byte $40, $F0, $C0, $00

; --- Note table: semitones above C3, C3 to C6 (NOTE_MAX) ---------------------
;   Register value = round(Hz * 16777216 / 1000000), equal temperament from
;   A4 = 440 Hz. That is the AC6502's 1 MHz SID clock exactly and the C64's
;   within 2.3% either way — under half a semitone, and the SAME fraction for
;   every note, so a C64 plays this perfectly in tune with itself and a hair
;   sharp of an AC6502. Its two regions are a uniform transposition of each
;   other for the same reason, which is why there is no second table here and
;   nothing in this file reads Region.
;
;   The octave a note actually sounds in is the timbre's (constants.inc), so
;   TIMBRE_BRIGHT doubles what it reads here and TIMBRE_SOFT halves it. C6
;   doubled is 35114, well inside the register.
SidNoteLo:
  .byte $93, $15, $9F, $32, $CD, $72, $20, $D8, $9C, $6B, $46, $2F   ; C3-B3
  .byte $25, $2A, $3F, $64, $9A, $E3, $3F, $B1, $38, $D6, $8D, $5E   ; C4-B4
  .byte $4B, $55, $7E, $C8, $34, $C6, $7F, $61, $6F, $AC, $1A, $BC   ; C5-B5
  .byte $95                                                          ; C6
SidNoteHi:
  .byte $08, $09, $09, $0A, $0A, $0B, $0C, $0C, $0D, $0E, $0F, $10   ; C3-B3
  .byte $11, $12, $13, $14, $15, $16, $18, $19, $1B, $1C, $1E, $20   ; C4-B4
  .byte $22, $24, $26, $28, $2B, $2D, $30, $33, $36, $39, $3D, $40   ; C5-B5
  .byte $44                                                          ; C6
