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
;
;   THE BAND EITHER SIDE OF THE STRING IS BLANKED, and only that. Banners are
;   not all the same width — `~~ PAUSED ~~` is two cells narrower than
;   `~~ LEVEL UP ~~`, which is exactly what pausing during a level-up meets —
;   so a shorter one drawn straight over a longer one would leave the tail of
;   the old ornament sitting either side of it. Blanking the WHOLE band first
;   would fix that too, and cost 18 marks on top of the string's: past
;   DIRTY_FLUSH_MAX, so every banner in the game would take an extra frame to
;   arrive. Blanking the margins costs only the cells the string is not
;   covering — six for the narrowest banner in the game, two for the widest.
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
  sta TextByte                  ; Where the string starts...
  clc
  adc TextIdx
  sta TextSkip                  ; ...and one cell past where it ends. Neither
                                ;   is TextCol / TextRow / TextIdx, because
                                ;   TextClearRun below takes those

  lda TextByte                  ; The band to the left of it
  sec
  sbc #MSG_X
  beq @Right
  ldx #MSG_X
  ldy #MSG_Y
  jsr TextClearRun
@Right:
  lda #(MSG_X + MSG_W)          ; ...and to the right
  sec
  sbc TextSkip
  beq @Draw
  ldx TextSkip
  ldy #MSG_Y
  jsr TextClearRun
@Draw:
  ldx TextByte
  ldy #MSG_Y
  jmp TextDraw

; -----------------------------------------------------------------------------
;   TextBannerClear — blank the message band back to backdrop
;   Out: nothing.  Modifies: A, X, Y, TextCol, TextRow, TextIdx
;
;   Columns MSG_X .. MSG_X + MSG_W - 1 only. The shelf tiles at either end of
;   the band belong to the static screen image and are never redrawn.
; -----------------------------------------------------------------------------
TextBannerClear:
  lda #MSG_W
  ldx #MSG_X
  ldy #MSG_Y
  ; falls through

; -----------------------------------------------------------------------------
;   TextClearRun — blank a horizontal run of panel cells
;   In:  A = width (never 0), X = panel column, Y = panel row
;   Out: nothing.  Modifies: A, X, Y, TextCol, TextRow, TextIdx
;
;   Three callers wanted this loop with different numbers in it: the message
;   band above, the HIGH field's dark half (SPEC 9.8) and the title screen's
;   blinking prompt (SPEC 13.1). The cursor is in memory for the usual reason —
;   RenderMark clobbers A and X and keeps only Y (D13).
; -----------------------------------------------------------------------------
TextClearRun:
  sta TextIdx                   ; Cells left
  stx TextCol
  sty TextRow
@Cell:
  lda #TILE_BLANK
  ldx TextCol
  ldy TextRow
  jsr RenderMark
  inc TextCol
  dec TextIdx
  bne @Cell
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
