; =============================================================================
;   tables.inc — Wizards Lab, spec-derived lookup tables
; =============================================================================
;   Straight out of SPEC.md sections 5.3, 9 and 10. Hand-authored, never
;   overwritten by an editor export. Included once, from the RODATA segment.
;
;   Score values above 99 do not fit in a byte, so every scoring table is a
;   pair of parallel arrays — low BCD byte and high BCD byte — indexed by the
;   same value.
; =============================================================================

; --- Gravity, frames per row (SPEC 10.2) -------------------------------------
;   Indexed by (level - 1), clamped to LEVEL_SPEED_CAP - 1.
;   PAL is round(NTSC * 50/60), so wall-clock speed matches across regions.

SpeedNTSC:
  .byte  48, 43, 38, 34, 30, 26, 23, 20   ; levels  1- 8   0.800s .. 0.333s
  .byte  17, 15, 13, 11,  9,  8,  7,  6   ; levels  9-16   0.283s .. 0.100s

SpeedPAL:
  .byte  40, 36, 32, 28, 25, 22, 19, 17   ; levels  1- 8   0.800s .. 0.340s
  .byte  14, 13, 11,  9,  8,  7,  6,  5   ; levels  9-16   0.280s .. 0.100s

; --- Frame counts that differ by region (SPEC 5.6, 11.3, 14) -----------------
;   Indexed by Region: 0 = NTSC, 1 = PAL. PAL is round(NTSC * 50/60) wherever
;   the difference is worth a frame, so a piece takes the same number of
;   SECONDS to lock on both machines rather than the same number of frames.
;
;   Two bytes each rather than one table of pairs, because every read is
;   `ldx Region / lda Name,x` and a pair table would need the index doubled.

LockDelay:                              ; SPEC 5.6
  .byte 16, 14
AreDelay:                               ; Entry delay after a cascade settles
  .byte 12, 10
DasInitial:                             ; SPEC 11.3 — first repeat
  .byte 12, 10
DasRepeat:                              ; ...and every one after it
  .byte  4,  3
SoftDropRate:                           ; Frames per row while DOWN is held.
  .byte  3,  2                          ;   Never used when gravity is faster.

; --- Per-tile value for MATCH removals (SPEC 9.1) ----------------------------
;   Indexed by (chain - 1), clamped to 7.   20 50 100 200 300 400 500 600
TileValueLo:
  .byte $20, $50, $00, $00, $00, $00, $00, $00
TileValueHi:
  .byte $00, $00, $01, $02, $03, $04, $05, $06

; --- Per-tile value for EFFECT removals (SPEC 9.2) ---------------------------
;   Indexed by (chain - 1), clamped to 7.   30 60 120 240 350 450 550 650
EffectValueLo:
  .byte $30, $60, $20, $40, $50, $50, $50, $50
EffectValueHi:
  .byte $00, $00, $01, $02, $03, $04, $05, $06

; --- Run length bonus (SPEC 9.3) ---------------------------------------------
;   Indexed by (length - 3), clamped to 4.  0 100 300 600 1000
LengthBonusLo:
  .byte $00, $00, $00, $00, $00
LengthBonusHi:
  .byte $00, $01, $03, $06, $10

; --- Simultaneous run bonus (SPEC 9.4) ---------------------------------------
;   Indexed by (runs - 1), clamped to 4.    0 200 500 1000 2000
MultiBonusLo:
  .byte $00, $00, $00, $00, $00
MultiBonusHi:
  .byte $00, $02, $05, $10, $20

; --- Level -> reagent probability band (SPEC 5.3) ----------------------------
;   Indexed by (level - 1), clamped to 15. Bands are 1-3, 4-6, 7-9, 10-12, 13+.
LevelBand:
  .byte 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4

; --- Chance a piece carries a reagent, out of 256 (SPEC 5.3) -----------------
;   Indexed by band.                        15%  22%  27%  32%  36%
PSpecial:
  .byte  38,  56,  69,  82,  92

; --- Reagent type, cumulative thresholds out of 256 (SPEC 5.3) ---------------
;   Four thresholds per band; a roll at or above the last one is a Prism.
;       roll <  [0] -> Fireball
;       roll <  [1] -> Bolt
;       roll <  [2] -> Bomb
;       roll <  [3] -> Star
;       else        -> Prism
ReagentThresholds:
  .byte  77, 138, 195, 236             ; band 0   levels  1-3
  .byte  77, 141, 192, 238             ; band 1   levels  4-6
  .byte  82, 146, 197, 238             ; band 2   levels  7-9
  .byte  79, 141, 195, 238             ; band 3   levels 10-12
  .byte  79, 143, 199, 240             ; band 4   levels 13+

; --- Reagent trigger bonuses, indexed by glyph (SPEC 9.5) --------------------
;   Glyph 0 potion and 4 star award nothing here (the star multiplies instead).
TriggerBonusLo:
  .byte $00, $00, $00, $00, $00, $00, $00, $00
TriggerBonusHi:
  .byte $00, $05, $03, $03, $00, $00, $00, $00
