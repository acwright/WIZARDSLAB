; =============================================================================
;   strings.inc — Wizards Lab, tile-encoded text
; =============================================================================
;   Strings are stored as TILE numbers, not ASCII, terminated by TEXT_END, so
;   TextDraw is a copy with no translation at run time (see text.asm). The
;   translation happens here instead, at assembly time, in TileStr.
;
;   Hand-authored, never overwritten by an editor export (D3). Included once,
;   from each platform's RODATA segment.
; =============================================================================

; -----------------------------------------------------------------------------
;   TileChar / TileStr — ASCII source, tile bytes out
;   The font is forty glyphs in one run from FONT_BASE:
;       0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ . x ! ~
;   and a space is TILE_BLANK. Anything else is not in the tileset and is an
;   assembly error rather than a wrong glyph on the screen.
; -----------------------------------------------------------------------------
.macro TileChar c
  .if c = ' '
    .byte TILE_BLANK
  .elseif (c >= '0') .and (c <= '9')
    .byte FONT_DIGIT_0 + (c - '0')
  .elseif (c >= 'A') .and (c <= 'Z')
    .byte FONT_LETTER_A + (c - 'A')
  .elseif c = '.'
    .byte FONT_DOT
  .elseif c = 'x'
    .byte FONT_TIMES
  .elseif c = '!'
    .byte FONT_BANG
  .elseif c = '~'
    .byte FONT_TILDE
  .else
    .error "strings.inc: no tile for this character"
  .endif
.endmacro

.macro TileStr s
  .repeat .strlen(s), I
    TileChar {.strat(s, I)}
  .endrepeat
  .byte TEXT_END
.endmacro

; -----------------------------------------------------------------------------
;   Banners — SPEC 12.2, 13.3
;   Even length, so (PANEL_W - length) / 2 centres exactly. The band is 18
;   cells of backdrop between two shelf tiles either side, so a banner has 18
;   to play with before it starts overwriting the artwork.
;
;   MsgPaused matches the play screen image byte for byte on purpose: the
;   artwork ships with the band already reading `~~ PAUSED ~~` (see SPEC 12.1),
;   so entering play clears the band and pausing draws this straight back.
; -----------------------------------------------------------------------------
MsgPaused:
  TileStr "~~ PAUSED ~~"                 ; 12 cells, centres at panel column 5

MsgLevelUp:
  TileStr "~~ LEVEL UP ~~"               ; 14 cells, centres at panel column 4

; `GAME OVER` is nine characters, so a symmetric ornament around it is always
; an ODD length and would sit half a cell left of centre. The bang makes it
; even and is the reason it is there; SPEC 13.4 records the wording.
MsgGameOver:
  TileStr "~~ GAME OVER! ~~"             ; 16 cells, centres at panel column 3

; The chain banner carries a number, and TextDraw copies bytes rather than
; formatting them, so the digit is a placeholder that CascadeSettle overwrites
; with one RenderMark at CHAIN_DIGIT_X (constants.inc). Keeping the length at
; MSG_CHAIN_LEN is what makes that column a constant instead of a measurement.
MsgChain:
  TileStr "~~ CHAIN x0 ~~"               ; 14 cells; the `0` is panel column 14

; -----------------------------------------------------------------------------
;   The title screen's prompt (SPEC 13.1)
;   Not a banner: it is ten cells of the DRAWN title image, and the only reason
;   the string exists at all is that blinking it means putting it back. It must
;   match data/screen-title-*.bin at PROMPT_X, PROMPT_Y byte for byte, or the
;   first blink would redraw the screen slightly differently from the way the
;   artist drew it.
; -----------------------------------------------------------------------------
MsgPressFire:
  TileStr "PRESS FIRE"                   ; PROMPT_LEN cells (constants.inc)
