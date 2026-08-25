; =============================================================================
;   Wizards Lab — VIC-20
; =============================================================================
;   A 16 K cartridge for an unexpanded VIC-20: BLK5 ($A000) carries the
;   autostart header and the code, BLK3 ($6000) carries the tileset and screen
;   images.
;
;   This machine sets the shape of the whole game. Its 22 x 23 screen is
;   exactly the panel every platform draws, and its eight hi-res foreground
;   colours are what cap the potion palette at six plus white. Designing
;   against it first is what lets one layout serve all three.
;
;   The VIC chip cannot see cartridge ROM, so the character set is copied out
;   of BLK3 into RAM at $1400 during boot.
;
;   Built with VIC20-16K.cfg.
; =============================================================================

.include "../include/vic20.inc"

; --- Platform constants (hal.inc) --------------------------------------------
SCR_COLS         = 22
SCR_ROWS         = 23
SCR_CELLS        = 506           ; 22 x 23
PANEL_X             = 0             ; The screen IS the panel
PANEL_Y             = 0
HAS_COLOR_RAM       = 1

CHARSET_RAM         = $1400         ; 2 K, $1400-$1BFF

.include "../src/constants.inc"
.include "../src/zeropage.inc"
.include "../src/ram.inc"
.include "../src/hal.inc"

; =============================================================================
;   Cartridge header — BLK5, $A000
; =============================================================================

.segment "CARTHDR"

.addr ColdStart                 ; Cold start vector
.addr ColdStart                 ; Warm start vector (RESTORE = full restart)
.byte $41, $30, $C3, $C2, $CD   ; "A0CBM" autostart signature

; =============================================================================
;   Entry
; =============================================================================

.segment "CODE"

ColdStart:
  sei
  cld
  ldx #$FF
  txs                           ; Nothing did this for us

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
;   HAL — VIC-I, hi-res text
; =============================================================================

; -----------------------------------------------------------------------------
;   HalInitVideo — 22 x 23 cells, custom charset in RAM, everything black
; -----------------------------------------------------------------------------
HalInitVideo:
  ; Screen centring. The KERNAL normally sets these, but an autostart cart
  ; takes over before it gets that far, so they are still at their power-on
  ; values and the picture sits in the wrong place. The right pair depends on
  ; the region, which is why HalDetectRegion runs before this.
  ldx #$05                      ; NTSC
  ldy #$19
  lda Region
  beq @Centre
  ldx #$0C                      ; PAL
  ldy #$26
@Centre:
  stx VIC_CR0                   ; Horizontal centring (bit 7 = interlace, off)
  sty VIC_CR1                   ; Vertical centring

  lda #$96                      ; 22 columns, video matrix bit 9 set -> $1E00
  sta VIC_CR2
  lda #$2E                      ; 23 rows (46 half-lines), 8-pixel characters
  sta VIC_CR3
  lda #$FD                      ; Screen $1E00, character set $1400
  sta VIC_CR5
  lda #$08                      ; Black background, black border, normal video
  sta VIC_CRF

  jsr LoadTileset
  ; falls through

; -----------------------------------------------------------------------------
;   HalClearScreen — blank tiles, white colour RAM
; -----------------------------------------------------------------------------
HalClearScreen:
  ldx #0                        ; 506 cells = one full page plus 250
@Page0:
  lda #TILE_BLANK
  sta SCREEN + $0000,x
  lda #1                        ; White
  sta COLRAM + $0000,x
  inx
  bne @Page0
@Page1:
  lda #TILE_BLANK
  sta SCREEN + $0100,x
  lda #1
  sta COLRAM + $0100,x
  inx
  cpx #250                      ; $1E00 + 506 = $1FFA, the end of the matrix
  bne @Page1
  rts

; -----------------------------------------------------------------------------
;   LoadTileset — copy 2 K of patterns from BLK3 into RAM at $1400
;   The VIC chip cannot see cartridge ROM, so this copy is not optional.
;   PLACEHOLDER ART: Tileset is data/tileset.bin. See data/README.md.
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
;   HalWaitFrame — sync on the top of the raster
; -----------------------------------------------------------------------------
HalWaitFrame:
@NotTop:
  lda VIC_CR4                   ; Raster line / 2
  beq @NotTop                   ; Leave the top of the frame first...
@Top:
  lda VIC_CR4
  bne @Top                      ; ...then wait for it to come round again
  rts

; -----------------------------------------------------------------------------
;   HalPlotCell — In: A = tile, X = screen column, Y = screen row
; -----------------------------------------------------------------------------
HalPlotCell:
  pha                           ; Hold the tile; RowPtrs needs A
  jsr RowPtrs                   ; ScreenPtr / ColorPtr = start of row Y
  txa
  tay                           ; Y = column
  pla                           ; A = tile
  sta (ScreenPtr),y
  tax                           ; The tile is its own colour lookup index
  lda TileColorVIC,x
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
;   HalBlitScreen — draw a full 506-byte screen plus its colour image
;   In: SrcPtr -> name table, Ptr1 -> colour table
; -----------------------------------------------------------------------------
HalBlitScreen:
  ldy #0                        ; 506 cells = one full page plus 250
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
  cpy #250                      ; Anything past here is not screen memory
  bne @Page1
  rts

; -----------------------------------------------------------------------------
;   HalReadInput — joystick, folded into the abstract active-high mask
;   The VIC splits its stick across two chips: up, down, left and fire are on
;   VIA1 $9111, but RIGHT is on VIA2 $9120 and reading it means flipping that
;   port's direction register first. Do that dance once, here, per frame.
;   Keyboard is TODO: it scans the same VIA2 matrix.
; -----------------------------------------------------------------------------
HalReadInput:
  lda $9113                     ; VIA1 DDR: the joystick lines are inputs
  and #%11000011
  sta $9113

  lda $9111                     ; Active low: bit2 U, bit3 D, bit4 L, bit5 fire
  eor #$FF
  and #%00111100                ; Only those four; PA7 here is not the stick
  sta Tmp0

  lda #$7F                      ; VIA2 PB7 as an input for the RIGHT switch
  sta $9122
  lda $9120
  eor #$FF
  and #$80                      ; Fold RIGHT in as bit 7 of the same byte
  ora Tmp0
  sta Tmp0
  lda #$FF                      ; Put the DDR back for keyboard scanning
  sta $9122

  lda #0
  sta Tmp1

  lda Tmp0
  and #%00000100                  ; VIA1 bit 2
  beq @NoUp
  lda Tmp1
  ora #INPUT_UP
  sta Tmp1
@NoUp:
  lda Tmp0
  and #%00001000                  ; VIA1 bit 3
  beq @NoDown
  lda Tmp1
  ora #INPUT_DOWN
  sta Tmp1
@NoDown:
  lda Tmp0
  and #%00010000                  ; VIA1 bit 4
  beq @NoLeft
  lda Tmp1
  ora #INPUT_LEFT
  sta Tmp1
@NoLeft:
  lda Tmp0
  and #%10000000                  ; VIA2 PB7, folded in above
  beq @NoRight
  lda Tmp1
  ora #INPUT_RIGHT
  sta Tmp1
@NoRight:
  lda Tmp0
  and #%00100000                  ; VIA1 bit 5
  beq @NoFire
  lda Tmp1
  ora #INPUT_FIRE
  sta Tmp1
@NoFire:

  lda Tmp1
  rts

; -----------------------------------------------------------------------------
;   HalDetectRegion — NTSC has 261 raster lines, PAL 312
;   $9004 carries the line number halved, so the highest value it reaches is
;   about $82 on NTSC and $9C on PAL. Sample it and take the maximum.
; -----------------------------------------------------------------------------
HalDetectRegion:
  lda #0
  sta Tmp0                      ; Highest line seen
  ldx #0
  ldy #0
@Sample:
  lda VIC_CR4
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
  cmp #$90
  bcc @Ntsc
  lda #1                        ; PAL
  rts
@Ntsc:
  lda #0
  rts

; -----------------------------------------------------------------------------
;   HalSfx — TODO: VIC-I sound, $900A-$900E. Its own driver; no SID here.
; -----------------------------------------------------------------------------
HalSfx:
  rts

; =============================================================================
;   Data
; =============================================================================

.segment "RODATA"

.include "../data/tilecolor-vic20.inc"

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

; --- PLACEHOLDER ART — replace via VIC-EDITOR, see data/README.md ------------
Tileset:      .incbin "../data/tileset.bin"
TitleScreen:  .incbin "../data/screen-title-vic20.bin"
TitleColor:   .incbin "../data/screen-title-vic20-color.bin"
PlayScreen:   .incbin "../data/screen-play-vic20.bin"
PlayColor:    .incbin "../data/screen-play-vic20-color.bin"
