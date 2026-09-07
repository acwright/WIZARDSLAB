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
;   HalReadInput — joystick and keyboard, folded into one active-high mask
;
;   The VIC splits its stick across two chips: up, down, left and fire are on
;   VIA1 $9111, but RIGHT is on VIA2 $9120 bit 7 — which is also the last of
;   the eight keyboard row lines. That collision is PLAN.md S4, and it turns
;   out not to be one:
;
;     Every key this game reads lives in matrix rows 1-6. Row 0 is the top
;     number row and row 7 the rest of it, and the game wants neither. So DDRB
;     is set ONCE to $7F and never touched again — PB0-PB6 drive the six rows
;     that matter, PB7 stays an input for the RIGHT switch, and the two never
;     take turns.
;
;   That is better than flipping the DDR twice a frame, and not only because
;   it is shorter: driving PB7 high while a closed RIGHT switch pulls it to
;   ground puts the VIA's output stage against the joystick, and never
;   configuring PB7 as an output means that cannot happen at all.
; -----------------------------------------------------------------------------
HalReadInput:
  lda $9113                     ; VIA1 DDR: the joystick lines are inputs
  and #%11000011
  sta $9113

  lda #%01111111                ; VIA2 DDRB: rows 0-6 out, RIGHT switch in
  sta $9122
  lda #$00                      ; VIA2 DDRA: the column lines are inputs
  sta $9123

  lda $9111                     ; Active low: bit2 U, bit3 D, bit4 L, bit5 fire
  eor #$FF
  and #%00111100                ; Only those four; PA7 here is not the stick
  sta Tmp0

  lda $9120
  eor #$FF
  and #$80                      ; Fold RIGHT in as bit 7 of the same byte
  ora Tmp0
  sta Tmp0

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

  jsr ScanKeys
  ora Tmp1
  rts

; -----------------------------------------------------------------------------
;   ScanKeys — the keyboard matrix, as the same active-high mask
;   Out: A = INPUT_* bits.  Modifies: A, X, Tmp2
;
;   VIA2 $9120 drives the rows (one bit LOW selects one row) and $9121 reads
;   the columns, active low. Every key the game uses is in KeyTable below;
;   the two cursor keys come after it because SHIFT turns them around, and
;   knowing whether SHIFT is down means having scanned the table first.
; -----------------------------------------------------------------------------
KEY_SHIFT           = %01000000 ; Scratch inside this file only — INPUT_MASK
                                ;   strips it before the mask leaves here

ScanKeys:
  lda #0
  sta Tmp2
  ldx #0
@Key:
  lda KeyTable,x
  beq @Cursors                  ; $00 drives every row at once — the
  sta $9120                     ;   terminator, because it is not a row mask
  lda $9121
  eor #$FF                      ; Active low in, active high out
  and KeyTable+1,x
  beq @Next
  lda Tmp2
  ora KeyTable+2,x
  sta Tmp2
@Next:
  inx
  inx
  inx
  bne @Key                      ; Always — the table is far shorter than 256

  ; --- the two cursor keys, which SHIFT turns around (SPEC 11.2) ------------
  ;   Unshifted they are RIGHT and DOWN, shifted LEFT and UP, which is exactly
  ;   the four the game wants and the reason for reading the matrix rather
  ;   than letting the KERNAL translate a keystroke into one character.
@Cursors:
  lda #%11111011                ; Row 2 — CRSR RIGHT shares it with A and D
  sta $9120
  lda $9121
  and #%10000000                ; Column 7
  bne @NoLeftRight              ; Still high, so not pressed
  ldx #INPUT_RIGHT
  lda Tmp2
  and #KEY_SHIFT
  beq @LeftRight
  ldx #INPUT_LEFT
@LeftRight:
  txa
  ora Tmp2
  sta Tmp2
@NoLeftRight:

  lda #%11110111                ; Row 3 — CRSR DOWN, next to LSHIFT
  sta $9120
  lda $9121
  and #%10000000
  bne @NoUpDown
  ldx #INPUT_DOWN
  lda Tmp2
  and #KEY_SHIFT
  beq @UpDown
  ldx #INPUT_UP
@UpDown:
  txa
  ora Tmp2
  sta Tmp2
@NoUpDown:

  lda Tmp2
  and #INPUT_MASK               ; Drop KEY_SHIFT — it is not an input
  rts

; -----------------------------------------------------------------------------
;   KeyTable — row mask, column mask, input bit.  Terminated by $00.
;   Rows 1-6 only; see HalReadInput above for why that matters.
; -----------------------------------------------------------------------------
KeyTable:
  .byte %11111101, %00000010, INPUT_UP      ; W        row 1, col 1
  .byte %11111011, %00000010, INPUT_LEFT    ; A        row 2, col 1
  .byte %11011111, %00000010, INPUT_DOWN    ; S        row 5, col 1
  .byte %11111011, %00000100, INPUT_RIGHT   ; D        row 2, col 2
  .byte %10111111, %00000001, INPUT_FIRE    ; Q        row 6, col 0
  .byte %11111101, %00100000, INPUT_PAUSE   ; P        row 1, col 5
  .byte %11101111, %00000001, INPUT_UP      ; SPACE    row 4, col 0
  .byte %11111101, %10000000, INPUT_FIRE    ; RETURN   row 1, col 7
  .byte %11110111, %00000010, KEY_SHIFT     ; LSHIFT   row 3, col 1
  .byte %11101111, %01000000, KEY_SHIFT     ; RSHIFT   row 4, col 6
  .byte $00

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
.include "../src/tables.inc"
.include "../src/strings.inc"

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
