; =============================================================================
;   score.asm — Wizards Lab, scoring
; =============================================================================
;   SPEC.md section 9. Seven digits of packed BCD in four bytes, low byte
;   first; the top nibble of ScoreTop is held at zero. Every value in
;   tables.inc is a multiple of ten, so scoring is a SED / ADC chain and never
;   a multiply — the one place a tile count has to be multiplied by a table
;   value, it is done as a loop of BCD additions, and the count is at most 21.
;
;   The score clamps at 9999999. It never wraps.
;
;   Display is always all seven digits, zero padded — see TextBcd. Nothing
;   here strips a leading zero, and nothing downstream may either.
; =============================================================================

; -----------------------------------------------------------------------------
;   ScoreHighInit — seed the session high score, once, at power-on
;   SPEC 9.8 — the high score is not persisted; it starts at 0010000 on every
;   power-on, which is the target the first game is played against. It then
;   survives every game in the session, so this is deliberately NOT part of
;   ScoreReset. Nothing may infer "cold boot" from the value being zero: BSS
;   is not cleared on all three machines.
;   Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
ScoreHighInit:
  lda #HIGH_INIT_LO
  sta HighLo
  lda #HIGH_INIT_MID
  sta HighMid
  lda #HIGH_INIT_HI
  sta HighHi
  lda #HIGH_INIT_TOP
  sta HighTop
  lda #$01                      ; BCD — the level the target was "set" on
  sta HighLevel
  rts

; -----------------------------------------------------------------------------
;   ScoreReset — zero the score for a new game
;   Out: nothing.  Modifies: A
; -----------------------------------------------------------------------------
ScoreReset:
  lda #0
  sta ScoreLo
  sta ScoreMid
  sta ScoreHi
  sta ScoreTop
  sta CascadeLo
  sta CascadeMid
  sta CascadeHi
  sta StarCount
  rts

; -----------------------------------------------------------------------------
;   CascadeAdd — add a 16-bit BCD value to the cascade accumulator
;   In:  A = low BCD byte, X = high BCD byte
;   Out: nothing.  Modifies: A, flags
; -----------------------------------------------------------------------------
CascadeAdd:
  ; TODO: SED, three-byte add into CascadeLo/Mid/Hi, CLD.
  rts

; -----------------------------------------------------------------------------
;   CascadeAddTimes — add a value N times (the tiles-cleared multiply)
;   In:  A = low BCD, X = high BCD, Y = count
; -----------------------------------------------------------------------------
CascadeAddTimes:
  rts

; -----------------------------------------------------------------------------
;   ScoreAdd — bank the cascade accumulator into Score, clamped
;   Out: C set if a new high score was reached this call.
;   SPEC 9.8 — the high score updates live, so the player watches the overtake.
; -----------------------------------------------------------------------------
ScoreAdd:
  clc
  rts

; -----------------------------------------------------------------------------
;   ScoreLevelCheck — advance the level when 30 tiles have gone
;   In:  A = tiles removed this step
;   Out: C set if the level advanced.
;   SPEC 10.1 — at most one advance per step, surplus carries over, so a big
;   fireball chain can never skip a level.
; -----------------------------------------------------------------------------
ScoreLevelCheck:
  clc
  rts

; -----------------------------------------------------------------------------
;   ScoreGravity — frames per row for the current level
;   Out: A = frame count, from SpeedNTSC or SpeedPAL per Region.
;        Modifies: A, X
;   SPEC 10.2. Strictly this module is P4's, but the falling piece cannot fall
;   without it, so it is real ahead of the rest of the file — the same reason
;   ScoreHighInit landed here in P1.
; -----------------------------------------------------------------------------
ScoreGravity:
  ldx Level
  dex                           ; The table is indexed by level - 1 ...
  cpx #LEVEL_SPEED_CAP
  bcc @Level
  ldx #LEVEL_SPEED_CAP - 1      ;   ... and stops improving at the cap
@Level:
  lda Region
  bne @Pal
  lda SpeedNTSC,x
  rts
@Pal:
  lda SpeedPAL,x
  rts
