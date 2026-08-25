; =============================================================================
;   text.asm — Wizards Lab, text and numbers on the panel
; =============================================================================
;   The font lives in tile groups 2-6, forty glyphs in the order
;
;       0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ . x ! -
;
;   starting at FONT_BASE, so a digit is FONT_DIGIT_0 + value and a letter is
;   FONT_LETTER_A + (letter - 'A'). Strings are stored pre-converted to tile
;   numbers, terminated by $FF, so drawing one is a copy with no translation.
; =============================================================================

; -----------------------------------------------------------------------------
;   TextDraw — draw a tile-encoded string
;   In:  Ptr1 -> string ($FF terminated), X = panel column, Y = panel row
; -----------------------------------------------------------------------------
TextDraw:
  ; TODO
  rts

; -----------------------------------------------------------------------------
;   TextBcd — draw a packed-BCD number, zero padded
;   In:  Ptr1 -> BCD bytes (low first), A = byte count,
;        X = panel column, Y = panel row
;   Six digits for the score, two for the level.
; -----------------------------------------------------------------------------
TextBcd:
  ; TODO: high nibble then low nibble of each byte, most significant byte
  ; first, each nibble drawn as FONT_DIGIT_0 + nibble.
  rts

; -----------------------------------------------------------------------------
;   TextBanner — centre a string in the two-row message band
;   In:  Ptr1 -> string, A = row within the band (0 or 1)
;   SPEC 12.2 — the band is panel rows MSG_Y and MSG_Y+1, full width.
; -----------------------------------------------------------------------------
TextBanner:
  rts

TextBannerClear:
  rts
