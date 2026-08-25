; =============================================================================
;   rng.asm — Wizards Lab, random numbers
; =============================================================================
;   A 16-bit Galois LFSR with the conventional $B400 taps, which is maximal
;   length: it visits all 65535 non-zero states before repeating. Eight shifts
;   per call, one whole byte out.
;
;   Seeding matters more than the generator does. A fixed seed would deal the
;   same first three pieces every session and the game would feel dead, so the
;   seed is taken from the free-running frame counter at the moment the player
;   presses fire on the title screen — human reaction time is the entropy.
;
;   SPEC.md section 15.
; =============================================================================

; -----------------------------------------------------------------------------
;   RngSeed — seed from the frame counter
;   In:  nothing (reads FrameCounter)
;   Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
RngSeed:
  lda FrameCounter
  ora #$01                      ; Never let the state reach zero — it sticks
  sta RngLo
  eor #$5A                      ; Spread one byte of entropy over both halves
  sta RngHi
  rts

; -----------------------------------------------------------------------------
;   RngNext — next pseudo-random byte
;   In:  nothing
;   Out: A = random 0-255.  Modifies: A, X, flags
; -----------------------------------------------------------------------------
RngNext:
  ldx #8                        ; Eight shifts give one whole output byte
@Bit:
  lsr RngHi                     ; Shift the 16-bit state right one place,
  ror RngLo                     ;   the bit falling out of bit 0 lands in C
  bcc @NoTap
  lda RngHi
  eor #$B4                      ; Galois feedback mask $B400
  sta RngHi
@NoTap:
  dex
  bne @Bit
  lda RngLo
  rts
