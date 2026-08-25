.setcpu "65C02"

; =============================================================================
;   Wizards Lab — AC6502
; =============================================================================
;   A 16 K cartridge for the A.C. Wright 6502, running the TMS9918 in
;   Graphics Mode I: 32 x 24 cells of 8 x 8 pixels, 256 patterns, and colour
;   assigned one foreground/background pair per group of eight patterns.
;
;   That colour model is the strictest of the three targets, so it is the one
;   the whole tileset is laid out against — each potion colour owns one group,
;   and every glyph of that colour lives inside it. See SPEC.md section 4.
;
;   This file is the platform half of the contract in src/hal.inc. Everything
;   it includes from src/ is shared, byte for byte, with the VIC-20 and C64.
;
;   Built with AC6502-16K.cfg.
; =============================================================================

.include "../include/ac6502.inc"

; --- Platform constants (hal.inc) --------------------------------------------
SCR_COLS         = 32
SCR_ROWS         = 24
SCR_CELLS        = SCR_COLS * SCR_ROWS     ; 768
PANEL_X             = 5             ; (32 - 22) / 2 — exact centring
PANEL_Y             = 0
HAS_COLOR_RAM       = 0             ; Colour lives in the VDP colour table

; --- VRAM map (SPEC Appendix C.1) --------------------------------------------
VRAM_PATTERNS       = $0000         ; 2 K, 256 patterns x 8 bytes
VRAM_NAMES          = $1400         ; 768, the 32 x 24 name table
VRAM_SPRITES        = $1B00         ; Sprite attributes — disabled below
VRAM_COLORS         = $2000         ; 32, one byte per 8-pattern group

.include "../src/constants.inc"
.include "../src/zeropage.inc"
.include "../src/ram.inc"
.include "../src/hal.inc"

; =============================================================================
;   Cartridge entry
; =============================================================================

.segment "CODE"

CartReset:
  sei
  cld
  ldx #$FF
  txs                           ; Nothing did this for us
  jsr KernalInit                ; Probe and initialise every card, IRQs left off

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
;   HAL — TMS9918 Graphics Mode I
; =============================================================================

; -----------------------------------------------------------------------------
;   VdpSetWrite — point the VDP at a VRAM address for writing
;   In:  A = address low, X = address high
; -----------------------------------------------------------------------------
VdpSetWrite:
  sta VC_REG
  txa
  ora #$40                      ; Bit 6 selects write
  sta VC_REG
  rts

; -----------------------------------------------------------------------------
;   VdpSetReg — write a VDP control register
;   In:  A = value, X = register number
; -----------------------------------------------------------------------------
VdpSetReg:
  sta VC_REG
  txa
  ora #$80
  sta VC_REG
  rts

; -----------------------------------------------------------------------------
;   HalInitVideo — Graphics I, tiles loaded, screen cleared, everything black
; -----------------------------------------------------------------------------
HalInitVideo:
  ldx #0                        ; R0: external VDP disabled, Graphics I
  lda #$00
  jsr VdpSetReg
  ldx #1                        ; R1: 16 K, display on, IRQ enabled, 8x8 sprites
  lda #$E0                      ; The IE bit stays SET even though this game
  jsr VdpSetReg                 ;   polls: HalWaitFrame reads the status
                                ;   register for the vblank flag, and the flag
                                ;   only raises when IE is on. The CPU's own I
                                ;   flag is never cleared, so the interrupt is
                                ;   asserted and simply ignored — reading the
                                ;   status register acknowledges it.
  ldx #2                        ; R2: name table    $1400 / $400
  lda #$05
  jsr VdpSetReg
  ldx #3                        ; R3: colour table  $2000 / $40
  lda #$80
  jsr VdpSetReg
  ldx #4                        ; R4: pattern table $0000 / $800
  lda #$00
  jsr VdpSetReg
  ldx #5                        ; R5: sprite attrs  $1B00 / $80
  lda #$36
  jsr VdpSetReg
  ldx #6                        ; R6: sprite patterns $0000
  lda #$00
  jsr VdpSetReg
  ldx #7                        ; R7: backdrop black
  lda #$01
  jsr VdpSetReg

  jsr LoadTileset
  jsr LoadColorTable
  jsr DisableSprites
  ; falls through

; -----------------------------------------------------------------------------
;   HalClearScreen — fill the name table with the blank tile
; -----------------------------------------------------------------------------
HalClearScreen:
  lda #<VRAM_NAMES
  ldx #>VRAM_NAMES
  jsr VdpSetWrite
  ldx #3                        ; 3 x 256 = 768 cells
  ldy #0
@Cell:
  lda #TILE_BLANK
  sta VC_DATA
  iny
  bne @Cell
  dex
  bne @Cell
  rts

; -----------------------------------------------------------------------------
;   LoadTileset — 2 K of patterns into VRAM
;   PLACEHOLDER ART: Tileset is data/tileset.bin. See data/README.md.
; -----------------------------------------------------------------------------
LoadTileset:
  lda #<VRAM_PATTERNS
  ldx #>VRAM_PATTERNS
  jsr VdpSetWrite

  lda #<Tileset
  sta SrcPtr
  lda #>Tileset
  sta SrcPtr+1

  ldx #8                        ; 8 x 256 = 2048 bytes
  ldy #0
@Byte:
  lda (SrcPtr),y
  sta VC_DATA
  iny
  bne @Byte
  inc SrcPtr+1
  dex
  bne @Byte
  rts

; -----------------------------------------------------------------------------
;   LoadColorTable — 32 bytes, one per 8-pattern group
;   This is what makes a tile red: its pattern number selects the group, and
;   the group's byte here selects the colour. Nothing is per cell.
; -----------------------------------------------------------------------------
LoadColorTable:
  lda #<VRAM_COLORS
  ldx #>VRAM_COLORS
  jsr VdpSetWrite
  ldy #0
@Byte:
  lda TileColorTMS,y
  sta VC_DATA
  iny
  cpy #32
  bne @Byte
  rts

; -----------------------------------------------------------------------------
;   DisableSprites — park every sprite off screen
;   The game uses none; $D0 in the first Y byte terminates the sprite list.
; -----------------------------------------------------------------------------
DisableSprites:
  lda #<VRAM_SPRITES
  ldx #>VRAM_SPRITES
  jsr VdpSetWrite
  lda #$D0
  sta VC_DATA
  rts

; -----------------------------------------------------------------------------
;   HalWaitFrame — poll the VDP status register for vertical blank
;   No raster interrupt here, and the status poll is self-syncing.
; -----------------------------------------------------------------------------
HalWaitFrame:
@Wait:
  lda VC_STATUS
  and #$80                      ; Bit 7 sets at the end of each frame
  beq @Wait
  rts

; -----------------------------------------------------------------------------
;   HalPlotCell — In: A = tile, X = screen column, Y = screen row
; -----------------------------------------------------------------------------
HalPlotCell:
  pha
  jsr NameAddr                  ; Ptr1 = VRAM_NAMES + row * 32 + col
  lda Ptr1
  ldx Ptr1+1
  jsr VdpSetWrite
  pla
  sta VC_DATA
  rts

; -----------------------------------------------------------------------------
;   NameAddr — In: X = column, Y = row.  Out: Ptr1 = name table address
; -----------------------------------------------------------------------------
NameAddr:
  tya
  and #$07
  asl a                         ; (row & 7) * 32 lands in bits 5-7...
  asl a
  asl a
  asl a
  asl a
  sta Ptr1
  txa
  ora Ptr1                      ; ...leaving bits 0-4 free for the column
  sta Ptr1
  tya
  lsr a                         ; row >> 3 is the page within the name table
  lsr a
  lsr a
  clc
  adc #>VRAM_NAMES
  sta Ptr1+1
  rts

; -----------------------------------------------------------------------------
;   HalBlitScreen — draw a full 768-byte name table image
;   In: SrcPtr -> image. Ptr1 (colour) is ignored: this machine has no colour
;   RAM, so the same image drives every platform's layout and only the palette
;   mechanism differs.
; -----------------------------------------------------------------------------
HalBlitScreen:
  lda #<VRAM_NAMES
  ldx #>VRAM_NAMES
  jsr VdpSetWrite

  ldx #3                        ; 3 full pages
  ldy #0
@Byte:
  lda (SrcPtr),y
  sta VC_DATA
  iny
  bne @Byte
  inc SrcPtr+1
  dex
  bne @Byte
  rts

; -----------------------------------------------------------------------------
;   HalReadInput — joystick 1, folded into the abstract active-high mask
;   The port is active low, %RLDUYXBA (6502.inc). Keyboard is TODO: it arrives
;   through the same VIA, so it reads from GPIO_PORTB alongside the stick.
; -----------------------------------------------------------------------------
HalReadInput:
  lda HW_PRESENT
  and #HW_GPIO                  ; No GPIO card means a floating bus, not input
  beq @None

  jsr ReadJoystick1
  eor #$FF                      ; Active low in, active high out
  sta Tmp0

  lda #0
  sta Tmp1

  lda Tmp0
  and #%00010000                  ; U
  beq @NoUp
  lda Tmp1
  ora #INPUT_UP
  sta Tmp1
@NoUp:
  lda Tmp0
  and #%00100000                  ; D
  beq @NoDown
  lda Tmp1
  ora #INPUT_DOWN
  sta Tmp1
@NoDown:
  lda Tmp0
  and #%01000000                  ; L
  beq @NoLeft
  lda Tmp1
  ora #INPUT_LEFT
  sta Tmp1
@NoLeft:
  lda Tmp0
  and #%10000000                  ; R
  beq @NoRight
  lda Tmp1
  ora #INPUT_RIGHT
  sta Tmp1
@NoRight:
  lda Tmp0
  and #%00000001                  ; A
  beq @NoFire
  lda Tmp1
  ora #INPUT_FIRE
  sta Tmp1
@NoFire:

  lda Tmp1
  rts

@None:
  lda #0
  rts

; -----------------------------------------------------------------------------
;   HalDetectRegion — the TMS9918 here is 60 Hz
; -----------------------------------------------------------------------------
HalDetectRegion:
  lda #0                        ; NTSC
  rts

; -----------------------------------------------------------------------------
;   HalSfx — TODO: SID at $9800. Shares a driver with the C64's $D400.
; -----------------------------------------------------------------------------
HalSfx:
  rts

; =============================================================================
;   Data
; =============================================================================

.segment "RODATA"

.include "../data/tilecolor-tms9918.inc"

; --- PLACEHOLDER ART — replace via TMS9918-EDITOR, see data/README.md --------
TitleScreen:  .incbin "../data/screen-title-ac6502.bin"
PlayScreen:   .incbin "../data/screen-play-ac6502.bin"
TitleColor    = TitleScreen      ; No colour RAM on this machine
PlayColor     = PlayScreen

.segment "TILES"

Tileset:      .incbin "../data/tileset.bin"

; =============================================================================
;   Interrupt trampolines and CPU vectors
; =============================================================================
;   KernalInit has already pointed the RAM vectors at the default handlers, so
;   bouncing through them keeps keyboard and serial input alive without this
;   cartridge writing a handler of its own.

.segment "CODE"

IrqTrampoline:
  jmp (IRQ_PTR)

NmiTrampoline:
  jmp (NMI_PTR)

.segment "VECTORS"

.word   NmiTrampoline           ; NMI
.word   CartReset               ; RESET — the cartridge entry point
.word   IrqTrampoline           ; IRQ
