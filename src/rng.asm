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

; -----------------------------------------------------------------------------
;   RngRange — a random number below a small limit
;   In:  A = limit, 1-128
;   Out: A = 0 .. limit-1.  Modifies: A, X, Tmp0, Tmp1.  PRESERVES Y.
;
;   Not a modulo. `random % 6` throws four of the 256 outcomes into the low
;   values and leaves colours 0-3 a shade likelier than 4-5; this takes the
;   HIGH byte of (random * limit) instead, which spreads the remainder evenly
;   across the range and costs a fixed eight shifts either way.
;
;   The eight-bit multiply keeps only the high byte: the low half falls out of
;   the accumulator one bit at a time and is never wanted.
;
;   Y is preserved so a caller can loop over the three cells of a piece with
;   it (piece.asm does).
; -----------------------------------------------------------------------------
RngRange:
  pha                           ; The limit — RngNext wants A
  jsr RngNext
  sta Tmp0                      ; The random byte
  pla
  sta Tmp1                      ; The limit, shifted out one bit at a time
  lda #0
  ldx #8
@Bit:
  lsr Tmp1                      ; Next multiplier bit into C
  bcc @NoAdd
  clc
  adc Tmp0                      ; Partial product, carry out into C
@NoAdd:
  ror a                         ; Shift the accumulator down, carry in at bit 7
  dex
  bne @Bit
  rts
