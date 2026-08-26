; =============================================================================
;   text.asm — Wizards Lab, text and numbers on the panel
; =============================================================================
;   The font lives in tile groups 2-6, forty glyphs in the order
;
;       0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ . x ! ~
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
;   In:  Ptr1 -> BCD bytes (low first), A = digit count,
;        X = panel column, Y = panel row
;   SCORE_DIGITS (7) for the score and the high score, 2 for the high score's
;   level. The LEVEL box is not drawn with this — see TextLevel.
;
;   The count is in DIGITS, not bytes, because the score is seven digits in
;   four bytes: the top nibble of the most significant byte is held at zero
;   (SPEC 9) and must not be drawn, or the field would be eight cells wide and
;   no longer centred. An odd count starts at the LOW nibble of the top byte.
;
;   **Every digit is drawn, every time.** A leading zero is a zero glyph, not
;   a blank: 1250 draws as 0001250. There is no suppression pass and no
;   right-alignment — the field is fixed width so a digit never changes
;   column while the player is watching it (SPEC 9). This also makes the
;   routine branchless, and lets RenderScore mark a fixed run of cells dirty.
; -----------------------------------------------------------------------------
TextBcd:
  ; TODO: walk the bytes most significant first, drawing high nibble then low
  ; nibble as FONT_DIGIT_0 + nibble, skipping the first high nibble when the
  ; digit count is odd. Stop after A digits.
  rts

; -----------------------------------------------------------------------------
;   TextBanner — centre a string in the one-row message band
;   In:  Ptr1 -> string
;   SPEC 12.2 — the band is panel row MSG_Y, full width, one row only. The
;   string arrives already wrapped as `~~ TEXT ~~` — two FONT_TILDE, a blank,
;   the text, a blank, two FONT_TILDE. Centring is (PANEL_W - length) / 2,
;   which is why banner strings are drawn even-length.
; -----------------------------------------------------------------------------
TextBanner:
  rts

TextBannerClear:
  rts

; -----------------------------------------------------------------------------
;   TextLevel — the LEVEL box, tens above units in one column
;   In:  A = level (binary, 1-99)
;   SPEC 12.2 — LEVEL_X, tens at LEVEL_Y and units at LEVEL_Y + 1. Always two
;   digits: level 5 draws "0" over "5".
; -----------------------------------------------------------------------------
TextLevel:
  ; TODO: divide by ten, draw FONT_DIGIT_0 + tens then FONT_DIGIT_0 + units.
  rts
