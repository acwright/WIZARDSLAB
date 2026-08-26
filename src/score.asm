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
;   ScoreReset — zero the score, seed the session high score
;   SPEC 9.8 — the high score is not persisted; it starts at 0010000 on every
;   power-on, which is the target the first game is played against.
; -----------------------------------------------------------------------------
ScoreReset:
  ; TODO
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
; -----------------------------------------------------------------------------
ScoreGravity:
  lda #48                       ; TODO: index SpeedNTSC/SpeedPAL by Level-1,
  rts                           ;       clamped to LEVEL_SPEED_CAP - 1
