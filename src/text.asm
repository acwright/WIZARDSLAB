; =============================================================================
;   text.asm — Wizards Lab, text and numbers on the panel
; =============================================================================
;   The font lives in tile groups 2-6, forty glyphs in the order
;
;       0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ . x ! ~
;
;   starting at FONT_BASE, so a digit is FONT_DIGIT_0 + value and a letter is
;   FONT_LETTER_A + (letter - 'A'). Strings are stored pre-converted to tile
;   numbers, terminated by TEXT_END, so drawing one is a copy with no
;   translation. src/strings.inc holds them and the macro that encodes them.
;
;   Everything here draws through RenderMark, never to the screen: text is
;   panel cells like any other and goes through the same one flush a frame.
;   That is also why the cursor state lives in the zero-page block RenderMark
;   promises not to touch (zeropage.inc) rather than in Tmp0-Tmp3.
; =============================================================================

; -----------------------------------------------------------------------------
;   TextDraw — draw a tile-encoded string
;   In:  Ptr1 -> string (TEXT_END terminated), X = panel column, Y = panel row
;   Out: nothing.  Modifies: A, X, Y, TextCol, TextRow, TextIdx
; -----------------------------------------------------------------------------
TextDraw:
  stx TextCol
  sty TextRow
  lda #0
  sta TextIdx
@Char:
  ldy TextIdx
  lda (Ptr1),y
  cmp #TEXT_END
  beq @Done
  ldx TextCol
  ldy TextRow
  jsr RenderMark
  inc TextCol
  inc TextIdx
  bne @Char                     ; Always — a string is never 256 tiles long
@Done:
  rts

; -----------------------------------------------------------------------------
;   TextBcd — draw a packed-BCD number, zero padded
;   In:  Ptr1 -> BCD bytes (low first), A = digit count,
;        X = panel column, Y = panel row
;   Out: nothing.  Modifies: A, X, Y, TextCol, TextRow, TextIdx, TextByte,
;        TextSkip
;
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
  stx TextCol
  sty TextRow
  pha                           ; Digit count
  and #$01
  sta TextSkip                  ; Odd count: the top high nibble is not drawn
  pla
  clc
  adc #1                        ; Bytes = (digits + 1) / 2
  lsr a
  tax
  dex
  stx TextIdx                   ; Start at the most significant byte

@Byte:
  ldy TextIdx
  lda (Ptr1),y
  sta TextByte

  lda TextSkip
  bne @Low
  lda TextByte
  lsr a
  lsr a
  lsr a
  lsr a
  jsr TextDigit
@Low:
  lda #0
  sta TextSkip
  lda TextByte
  and #$0F
  jsr TextDigit

  dec TextIdx
  bpl @Byte
  rts

; -----------------------------------------------------------------------------
;   TextDigit — draw one digit at the cursor and step it right
;   In:  A = value 0-9      Modifies: A, X, Y, TextCol
; -----------------------------------------------------------------------------
TextDigit:
  clc
  adc #FONT_DIGIT_0
  ldx TextCol
  ldy TextRow
  jsr RenderMark
  inc TextCol
  rts

; -----------------------------------------------------------------------------
;   TextBanner — centre a string in the one-row message band
;   In:  Ptr1 -> string
;   Out: nothing.  Modifies: A, X, Y and the text cursor
;
;   SPEC 12.2 — the band is panel row MSG_Y, full width, one row only. The
;   string arrives already wrapped as `~~ TEXT ~~` — two FONT_TILDE, a blank,
;   the text, a blank, two FONT_TILDE. Centring is (PANEL_W - length) / 2,
;   which is why banner strings are drawn even-length.
; -----------------------------------------------------------------------------
TextBanner:
  ldy #0
@Len:
  lda (Ptr1),y
  cmp #TEXT_END
  beq @Got
  iny
  bne @Len
@Got:
  tya
  sta TextIdx
  lda #PANEL_W
  sec
  sbc TextIdx
  lsr a                         ; (PANEL_W - length) / 2
  tax
  ldy #MSG_Y
  jmp TextDraw

; -----------------------------------------------------------------------------
;   TextBannerClear — blank the message band back to backdrop
;   Out: nothing.  Modifies: A, X, Y
;
;   Columns MSG_X .. MSG_X + MSG_W - 1 only. The shelf tiles at either end of
;   the band belong to the static screen image and are never redrawn.
; -----------------------------------------------------------------------------
TextBannerClear:
  lda #MSG_X
  sta TextCol                   ; Not X: RenderMark clobbers it
@Cell:
  lda #TILE_BLANK
  ldx TextCol
  ldy #MSG_Y
  jsr RenderMark
  inc TextCol
  lda TextCol
  cmp #(MSG_X + MSG_W)
  bcc @Cell
  rts

; -----------------------------------------------------------------------------
;   TextLevel — the LEVEL box, tens above units in one column
;   In:  A = level (binary, 1-99)
;   Out: nothing.  Modifies: A, X, Y, TextByte
;   SPEC 12.2 — LEVEL_X, tens at LEVEL_Y and units at LEVEL_Y + 1. Always two
;   digits: level 5 draws "0" over "5".
; -----------------------------------------------------------------------------
TextLevel:
  ldx #0
@Tens:
  cmp #10
  bcc @Split
  sbc #10                       ; Carry is set by the CMP that got us here
  inx
  bne @Tens                     ; Always — X tops out at 9
@Split:
  sta TextByte                  ; Units
  txa
  clc
  adc #FONT_DIGIT_0
  ldx #LEVEL_X
  ldy #LEVEL_Y
  jsr RenderMark
  lda TextByte
  clc
  adc #FONT_DIGIT_0
  ldx #LEVEL_X
  ldy #LEVEL_Y + 1
  jmp RenderMark
