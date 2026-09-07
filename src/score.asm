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
;
;   TWO WAYS IN, AND THEY ARE NOT INTERCHANGEABLE (D5):
;
;     CascadeAdd / CascadeAddTimes    points scored INSIDE a cascade. They go
;                                     into Cascade{Lo,Mid,Hi} and stay there
;                                     until CascadeSettle, because a star
;                                     caught anywhere in the cascade doubles
;                                     everything it scored, retroactively
;                                     (SPEC 9.6).
;     ScoreAward                      the awards SPEC 9.6 gives outside a
;                                     cascade — the soft drop and the level-up
;                                     bonus. These reach Score at once and a
;                                     star never touches them.
;
;   Both funnel through ScoreBank, which is the only routine that writes
;   Score, the only one that clamps, and the only one that can hand the high
;   score over to the player.
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
;
;   The high score itself is NOT reset (SPEC 9.8) — but the two flags that say
;   what this game has done about it are, or the second game of a session
;   would never flash.
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
  sta HighOwned
  sta HighFlash
  sta HighTimer
  rts

; -----------------------------------------------------------------------------
;   CascadeAdd — add a 16-bit BCD value to the cascade accumulator
;   In:  A = low BCD byte, X = high BCD byte
;   Out: nothing.  Modifies: A, flags.  PRESERVES X and Y.
;
;   Preserving X and Y is what lets CascadeAddTimes loop over this without
;   spilling anything, and Tmp0-Tmp3 may not be held across a JSR anyway
;   (zeropage.inc).
; -----------------------------------------------------------------------------
CascadeAdd:
  sed
  clc
  adc CascadeLo
  sta CascadeLo
  txa
  adc CascadeMid
  sta CascadeMid
  lda CascadeHi
  adc #0
  sta CascadeHi
  cld                           ; CLD leaves the carry alone
  bcs CascadeClamp
  rts

; -----------------------------------------------------------------------------
;   CascadeClamp — six nines, when an accumulate would have wrapped
;   Out: nothing.  Modifies: A.  PRESERVES X and Y.
;
;   Not reachable by playing: nothing is ever ADDED to the board during a
;   cascade, so one cascade can never remove more than the 96 cells the well
;   holds, and 96 cells at the dearest tile value there is (650, SPEC 9.2)
;   plus every bonus in section 9 comes to a little over 200,000 — a fifth of
;   what three bytes hold, and an eighth of what it would take to wrap after
;   the star cap has doubled it three times. It is here because "never wraps"
;   in SPEC 9 has to be true of every accumulator on the path, not just of the
;   one the player can see.
; -----------------------------------------------------------------------------
CascadeClamp:
  lda #$99
  sta CascadeLo
  sta CascadeMid
  sta CascadeHi
  rts

; -----------------------------------------------------------------------------
;   CascadeAddTimes — add a value N times (the tiles-cleared multiply)
;   In:  A = low BCD, X = high BCD, Y = count
;   Out: nothing.  Modifies: A, Y, flags.  PRESERVES X.
;
;   SPEC 9 chose values that are all multiples of ten so that scoring is an
;   ADC chain, but `length * TileValue[chain]` is still a multiply. The count
;   is a run length — three to sixteen — so a loop of BCD additions is both
;   smaller and, at these counts, faster than any multiply routine worth
;   writing.
; -----------------------------------------------------------------------------
CascadeAddTimes:
  pha                           ; The low byte rides the stack, because
@Loop:                          ;   CascadeAdd returns in A
  cpy #0
  beq @Done
  pla
  pha
  jsr CascadeAdd
  dey
  bne @Loop
@Done:
  pla
  rts

; -----------------------------------------------------------------------------
;   CascadeDouble — one BCD doubling of the cascade accumulator
;   Out: nothing.  Modifies: A, flags.  PRESERVES X and Y.
;   A doubling in BCD is a self-addition; three of them is the star cap.
; -----------------------------------------------------------------------------
CascadeDouble:
  sed
  clc
  lda CascadeLo
  adc CascadeLo
  sta CascadeLo
  lda CascadeMid
  adc CascadeMid
  sta CascadeMid
  lda CascadeHi
  adc CascadeHi
  sta CascadeHi
  cld
  bcs CascadeClamp
  rts

; -----------------------------------------------------------------------------
;   ScoreAdd — bank the cascade accumulator into Score, clamped
;   Out: C as ScoreHighCheck leaves it.  Modifies: A, X, Y, Tmp0-Tmp2
;   SPEC 9.8 — the high score updates live, so the player watches the overtake.
; -----------------------------------------------------------------------------
ScoreAdd:
  lda CascadeLo
  sta Tmp0
  lda CascadeMid
  sta Tmp1
  lda CascadeHi
  sta Tmp2
  jmp ScoreBank

; -----------------------------------------------------------------------------
;   ScoreAward — add a 16-bit BCD value straight to Score
;   In:  A = low BCD byte, X = high BCD byte
;   Out: C as ScoreHighCheck leaves it.  Modifies: A, X, Y, Tmp0-Tmp2
;
;   The two awards SPEC 9.6 gives outside a cascade: one point a row for a
;   soft drop, and BONUS_LEVELUP when the level advances. Neither is a cascade
;   point and neither is doubled by a star, which is the whole reason they do
;   not go through CascadeAdd.
; -----------------------------------------------------------------------------
ScoreAward:
  sta Tmp0
  stx Tmp1
  lda #0
  sta Tmp2
  ; falls through into ScoreBank

; -----------------------------------------------------------------------------
;   ScoreBank — Score += the three BCD bytes in Tmp0-Tmp2, clamped at 9999999
;   Out: C as ScoreHighCheck leaves it.  Modifies: A, X, Y, Tmp0-Tmp2
;
;   The only writer of Score. It redraws the field itself, because there is no
;   other moment at which the score is known to have changed (SPEC 12.6 —
;   nothing polls).
; -----------------------------------------------------------------------------
ScoreBank:
  sed
  clc
  lda ScoreLo
  adc Tmp0
  sta ScoreLo
  lda ScoreMid
  adc Tmp1
  sta ScoreMid
  lda ScoreHi
  adc Tmp2
  sta ScoreHi
  lda ScoreTop
  adc #0
  sta ScoreTop
  cld                           ; CLD leaves the carry alone
  bcs @Clamp
  lda ScoreTop                  ; The eighth digit is held at zero (SPEC 9),
  cmp #$10                      ;   so anything that reached it has overflowed
  bcc @Drawn                    ;   the seven the panel shows
@Clamp:
  lda #$99
  sta ScoreLo
  sta ScoreMid
  sta ScoreHi
  lda #$09
  sta ScoreTop
@Drawn:
  jsr RenderScore
  ; falls through into ScoreHighCheck

; -----------------------------------------------------------------------------
;   ScoreHighCheck — hand the high score over the moment the score reaches it
;   Out: C set if the score is level with or past the high score — which, once
;        it has been taken, is EVERY call. The one-shot is HighOwned below, not
;        this flag; nothing currently reads it.  Modifies: A, X, Y, Tmp0
;
;   SPEC 9.8. The copy happens on every call once the score is level with the
;   high score, not just on the first — that is what keeps HighLevel tracking
;   the live level while a run is holding its own record, which is the point of
;   the number: it says how deep you have to get to beat it.
;
;   The fanfare and the flash are the one-shot half, and HighOwned is what
;   makes them one: without it every subsequent bank would fire them again,
;   because from the overtake onward the score and the high score are equal.
; -----------------------------------------------------------------------------
ScoreHighCheck:
  lda HighTop                   ; Four-byte compare, most significant first
  cmp ScoreTop
  bne @Test
  lda HighHi
  cmp ScoreHi
  bne @Test
  lda HighMid
  cmp ScoreMid
  bne @Test
  lda HighLo
  cmp ScoreLo
@Test:
  bcc @Take                     ; high < score
  bne @Behind                   ; high > score — nothing to do
                                ; equal: still copy, so HighLevel tracks
@Take:
  lda ScoreLo
  sta HighLo
  lda ScoreMid
  sta HighMid
  lda ScoreHi
  sta HighHi
  lda ScoreTop
  sta HighTop
  jsr ScoreLevelBcd             ; The level box under the digits is BCD; Level
  sta HighLevel                 ;   itself is binary (SPEC 12.2)
  jsr RenderHigh

  lda HighOwned
  bne @Owned
  inc HighOwned
  lda #SFX_HIGHSCORE            ; SPEC 9.8 — a longer fanfare, once
  sta SfxRequest
  lda #HIGH_FLASH_BLINKS
  sta HighFlash
  ldx Region
  lda BlinkHalf,x
  sta HighTimer
@Owned:
  sec
  rts

@Behind:
  clc
  rts

; -----------------------------------------------------------------------------
;   ScoreLevelBcd — Level (binary 1-99) as one packed BCD byte
;   Out: A = the level in BCD.  Modifies: A, X, Tmp0
; -----------------------------------------------------------------------------
ScoreLevelBcd:
  lda Level
  ldx #0
@Tens:
  cmp #10
  bcc @Split
  sbc #10                       ; Carry is set by the CMP that got us here
  inx
  bne @Tens                     ; Always — X tops out at 9
@Split:
  sta Tmp0                      ; Units
  txa
  asl a
  asl a
  asl a
  asl a
  ora Tmp0
  rts

; -----------------------------------------------------------------------------
;   ScoreSoftDrop — one point for one row descended under soft drop (SPEC 9.6)
;   Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2
;
;   The one award in the game that is not a multiple of ten. BCD does not care.
; -----------------------------------------------------------------------------
ScoreSoftDrop:
  lda #$01
  ldx #$00
  jmp ScoreAward

; -----------------------------------------------------------------------------
;   ScoreLevelCheck — advance the level when 30 tiles have gone
;   In:  A = tiles removed this step
;   Out: C set if the level advanced.  Modifies: A, X, Y, Tmp0-Tmp2
;   SPEC 10.1 — at most one advance per step, surplus carries over, so a big
;   fireball chain can never skip a level. Match and effect removals both
;   count, which is why the count comes from CascadeRemove and not from the
;   scan: by then the two are the same cells.
; -----------------------------------------------------------------------------
ScoreLevelCheck:
  clc
  adc TilesCleared
  sta TilesCleared              ; A whole step can clear far more than thirty;
  cmp #LEVEL_TILES              ;   the surplus stays here and buys the next
  bcc @No                       ;   level on the next step
  sbc #LEVEL_TILES              ; Carry is set by the CMP that got us here
  sta TilesCleared

  lda Level
  cmp #LEVEL_MAX_SHOWN
  bcs @No                       ; The box is two digits wide (SPEC 10.1), and
  inc Level                     ;   nothing about level 100 is reachable in a
  jsr RenderLevel               ;   session anyway
  lda #SFX_LEVELUP
  sta SfxRequest
  lda #<BONUS_LEVELUP           ; SPEC 9.6 — an award, not a cascade point, so
  ldx #>BONUS_LEVELUP           ;   a star in the same cascade does not double
  jsr ScoreAward                ;   it (D5)
  sec
  rts
@No:
  clc
  rts

; -----------------------------------------------------------------------------
;   ScoreFlashTick — one frame of the HIGH field's overtake flash
;   Out: nothing.  Modifies: A, X, Y
;   SPEC 9.8, SPEC 14 — the blink period is 30 frames NTSC / 25 PAL, shared
;   with the title screen's prompt, so HighFlash counts HALF blinks and
;   HighTimer counts the frames of one.
;
;   HighFlash is odd on the dark half and even on the lit one, and it ends at
;   zero, so the field is always left readable however the count is set.
; -----------------------------------------------------------------------------
ScoreFlashTick:
  lda HighFlash
  beq @Done
  dec HighTimer
  bne @Done
  dec HighFlash
  beq @Show                     ; Out of blinks — end lit
  ldx Region
  lda BlinkHalf,x
  sta HighTimer
  lda HighFlash
  lsr a
  bcc @Show
  jmp RenderHighBlank
@Show:
  jmp RenderHigh
@Done:
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
