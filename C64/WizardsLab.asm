; =============================================================================
;   Wizards Lab — Commodore 64
; =============================================================================
;   A 16 K cartridge: EXROM and GAME both low, so ROML ($8000-$9FFF) and ROMH
;   ($A000-$BFFF) map contiguously and the whole thing is one image.
;
;   The C64 is the roomiest of the three targets and gets no gameplay
;   advantage for it. The 22 x 23 panel is centred at (9, 1) and the nine
;   columns either side are static artwork, drawn once on entering a state and
;   never touched again — so they cost tiles, not cycles.
;
;   Its first eight colours are numerically identical to the VIC-20's eight
;   hi-res colours, so the playfield colour bytes are the same numbers on both
;   machines. The upper eight are for margin artwork only.
;
;   No sprites. Everything is tiles, on every platform, by design.
;
;   Built with C64-16K.cfg.
; =============================================================================

.include "../include/c64.inc"

; --- Platform constants (hal.inc) --------------------------------------------
SCR_COLS         = 40
SCR_ROWS         = 25
SCR_CELLS        = 1000          ; 40 x 25
PANEL_X             = 9             ; (40 - 22) / 2 — exact centring
PANEL_Y             = 1             ; (25 - 23) / 2
HAS_COLOR_RAM       = 1

CHARSET_RAM         = $2000         ; 2 K, VIC bank 0

.include "../src/constants.inc"
.include "../src/zeropage.inc"
.include "../src/ram.inc"
.include "../src/hal.inc"

; =============================================================================
;   Cartridge header — $8000
; =============================================================================

.segment "CARTHDR"

.addr ColdStart                 ; Cold start vector
.addr ColdStart                 ; Warm start vector (NMI)
.byte $C3, $C2, $CD, $38, $30   ; "CBM80" autostart signature

; =============================================================================
;   Entry
; =============================================================================

.segment "CODE"

ColdStart:
  sei
  cld
  ldx #$FF
  txs                           ; The KERNAL jumped here before doing any of this

  lda #$7F                      ; Silence the CIA timer interrupt...
  sta $DC0D
  lda $DC0D                     ;   ...and acknowledge whatever was pending
  lda #$00
  sta VIC_IMR                   ; No raster interrupt either — we poll instead

  jsr GameInit                  ; Never returns

; --- Shared game code --------------------------------------------------------
.include "../src/main.asm"
.include "../src/rng.asm"
.include "../src/input.asm"
.include "../src/board.asm"
.include "../src/piece.asm"
.include "../src/match.asm"
.include "../src/cascade.asm"
.include "../src/score.asm"
.include "../src/render.asm"
.include "../src/text.asm"
.include "../src/audio.asm"

; =============================================================================
;   HAL — VIC-II, standard text mode
; =============================================================================

; -----------------------------------------------------------------------------
;   HalInitVideo — 40 x 25 cells, custom charset at $2000, everything black
; -----------------------------------------------------------------------------
HalInitVideo:
  lda $DD00                     ; VIC bank 0: $0000-$3FFF
  ora #$03
  sta $DD00

  lda #$1B                      ; Text mode, display on, 25 rows
  sta VIC_CTRL1
  lda #$C8                      ; 40 columns, no multicolor
  sta VIC_CTRL2
  lda #$18                      ; Screen $0400, character set $2000
  sta VIC_MEMPTR
  lda #$00
  sta VIC_BORDERCOL
  sta VIC_BGCOL0
  sta VIC_SPRENA                ; No sprites. Not an oversight — see the header.

  jsr LoadTileset
  ; falls through

; -----------------------------------------------------------------------------
;   HalClearScreen — blank tiles, white colour RAM
; -----------------------------------------------------------------------------
HalClearScreen:
  ldx #0
@Cell:
  lda #TILE_BLANK
  sta SCREEN + $0000,x
  sta SCREEN + $0100,x
  sta SCREEN + $0200,x
  sta SCREEN + $0300,x
  lda #1                        ; White
  sta COLRAM + $0000,x
  sta COLRAM + $0100,x
  sta COLRAM + $0200,x
  sta COLRAM + $0300,x
  inx
  bne @Cell
  rts

; -----------------------------------------------------------------------------
;   LoadTileset — copy 2 K of patterns from cartridge ROM to $2000
;   PLACEHOLDER ART: Tileset is data/tileset.bin. The same 2048-byte file
;   drives all three machines — the pattern format is identical. See
;   data/README.md.
; -----------------------------------------------------------------------------
LoadTileset:
  lda #<Tileset
  sta SrcPtr
  lda #>Tileset
  sta SrcPtr+1
  lda #<CHARSET_RAM
  sta DstPtr
  lda #>CHARSET_RAM
  sta DstPtr+1

  ldx #8                        ; 8 x 256 = 2048 bytes
  ldy #0
@Byte:
  lda (SrcPtr),y
  sta (DstPtr),y
  iny
  bne @Byte
  inc SrcPtr+1
  inc DstPtr+1
  dex
  bne @Byte
  rts

; -----------------------------------------------------------------------------
;   HalWaitFrame — sync on raster line 251, below the visible area
; -----------------------------------------------------------------------------
HalWaitFrame:
@NotYet:
  lda VIC_RASTER
  cmp #251
  beq @NotYet                   ; Leave the line first, so a fast frame
@Wait:                          ;   cannot fall straight through
  lda VIC_RASTER
  cmp #251
  bne @Wait
  rts

; -----------------------------------------------------------------------------
;   HalPlotCell — In: A = tile, X = screen column, Y = screen row
; -----------------------------------------------------------------------------
HalPlotCell:
  pha                           ; Hold the tile; RowPtrs needs A
  jsr RowPtrs
  txa
  tay                           ; Y = column
  pla                           ; A = tile
  sta (ScreenPtr),y
  tax                           ; The tile is its own colour lookup index
  lda TileColorC64,x
  sta (ColorPtr),y
  rts

; -----------------------------------------------------------------------------
;   RowPtrs — In: Y = screen row.  Out: ScreenPtr, ColorPtr at that row
; -----------------------------------------------------------------------------
RowPtrs:
  lda RowLo,y
  sta ScreenPtr
  sta ColorPtr
  lda RowHi,y
  sta ScreenPtr+1
  clc
  adc #(>COLRAM - >SCREEN)      ; Colour RAM mirrors the matrix, page-offset
  sta ColorPtr+1
  rts

; -----------------------------------------------------------------------------
;   HalBlitScreen — draw a full 1000-byte screen plus its colour image
;   In: SrcPtr -> name table, Ptr1 -> colour table
; -----------------------------------------------------------------------------
HalBlitScreen:
  ldy #0
@Page0:
  lda (SrcPtr),y
  sta SCREEN + $0000,y
  lda (Ptr1),y
  sta COLRAM + $0000,y
  iny
  bne @Page0

  inc SrcPtr+1
  inc Ptr1+1
  ldy #0
@Page1:
  lda (SrcPtr),y
  sta SCREEN + $0100,y
  lda (Ptr1),y
  sta COLRAM + $0100,y
  iny
  bne @Page1

  inc SrcPtr+1
  inc Ptr1+1
  ldy #0
@Page2:
  lda (SrcPtr),y
  sta SCREEN + $0200,y
  lda (Ptr1),y
  sta COLRAM + $0200,y
  iny
  bne @Page2

  inc SrcPtr+1
  inc Ptr1+1
  ldy #0
@Page3:
  lda (SrcPtr),y
  sta SCREEN + $0300,y
  lda (Ptr1),y
  sta COLRAM + $0300,y
  iny
  cpy #232                      ; 1000 - 768
  bne @Page3
  rts

; -----------------------------------------------------------------------------
;   HalReadInput — joystick port 2, folded into the abstract active-high mask
;   Port 1 shares the keyboard matrix, so only port 2 is supported. Keyboard
;   is TODO: the KERNAL scanner is off, so it means scanning $DC00/$DC01
;   directly.
; -----------------------------------------------------------------------------
HalReadInput:
  lda $DC00                     ; Active low: bit0 U, 1 D, 2 L, 3 R, 4 fire
  eor #$FF
  and #$1F
  sta Tmp0

  lda #0
  sta Tmp1

  lda Tmp0
  and #%00000001                  ; U
  beq @NoUp
  lda Tmp1
  ora #INPUT_UP
  sta Tmp1
@NoUp:
  lda Tmp0
  and #%00000010                  ; D
  beq @NoDown
  lda Tmp1
  ora #INPUT_DOWN
  sta Tmp1
@NoDown:
  lda Tmp0
  and #%00000100                  ; L
  beq @NoLeft
  lda Tmp1
  ora #INPUT_LEFT
  sta Tmp1
@NoLeft:
  lda Tmp0
  and #%00001000                  ; R
  beq @NoRight
  lda Tmp1
  ora #INPUT_RIGHT
  sta Tmp1
@NoRight:
  lda Tmp0
  and #%00010000                  ; fire
  beq @NoFire
  lda Tmp1
  ora #INPUT_FIRE
  sta Tmp1
@NoFire:

  lda Tmp1
  rts

; -----------------------------------------------------------------------------
;   HalDetectRegion — PAL has 312 raster lines, NTSC 263
;   Both overflow $D012, so sample it only while $D011 bit 7 (raster bit 8) is
;   set: PAL climbs to $37 up there, NTSC only to about $06.
; -----------------------------------------------------------------------------
HalDetectRegion:
  lda #0
  sta Tmp0                      ; Highest high-page line seen
  ldx #0
  ldy #0
@Sample:
  lda VIC_CTRL1
  bpl @Next                     ; Raster bit 8 clear — not the range we want
  lda VIC_RASTER
  cmp Tmp0
  bcc @Next
  sta Tmp0
@Next:
  iny
  bne @Sample
  inx
  cpx #64                       ; 16384 samples — comfortably over one frame
  bne @Sample

  lda Tmp0
  cmp #$20
  bcc @Ntsc
  lda #1                        ; PAL
  rts
@Ntsc:
  lda #0
  rts

; -----------------------------------------------------------------------------
;   HalSfx — TODO: SID at $D400. Shares a driver with the AC6502's $9800.
; -----------------------------------------------------------------------------
HalSfx:
  rts

; =============================================================================
;   Data
; =============================================================================

.segment "RODATA"

.include "../data/tilecolor-c64.inc"

; --- Screen row start addresses ----------------------------------------------
RowLo:
  .repeat SCR_ROWS, i
    .byte <(SCREEN + i * SCR_COLS)
  .endrepeat
RowHi:
  .repeat SCR_ROWS, i
    .byte >(SCREEN + i * SCR_COLS)
  .endrepeat

.segment "TILES"

; --- PLACEHOLDER ART — see data/README.md ------------------------------------
Tileset:      .incbin "../data/tileset.bin"
TitleScreen:  .incbin "../data/screen-title-c64.bin"
TitleColor:   .incbin "../data/screen-title-c64-color.bin"
PlayScreen:   .incbin "../data/screen-play-c64.bin"
PlayColor:    .incbin "../data/screen-play-c64-color.bin"
