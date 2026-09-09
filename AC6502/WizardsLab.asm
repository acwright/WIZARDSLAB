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
.include "../src/anim.asm"
.include "../src/score.asm"
.include "../src/render.asm"
.include "../src/text.asm"
.include "../src/audio.asm"
.include "../src/ambience.asm"

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
;   HalReadInput — joystick 1 and the keyboard, in one active-high mask
;   The port is active low, %RLDUYXBA (ac6502.inc).
;
;   This machine has no key matrix to scan. Two encoders sit on the VIA ports
;   the joysticks share and hand over one ASCII byte per keystroke, strobing
;   CB1 (matrix keyboard) or CA1 (PS/2) when it is ready. There is no key-up
;   event and no way to ask whether a key is still down, so a key here is a
;   ONE-FRAME PULSE rather than a held bit: the edge-triggered controls
;   (rotate, pause, fire) work exactly as they do on a stick, and the held
;   ones (left, right, soft drop) advance once per keystroke and once per
;   encoder auto-repeat. DAS never engages from the keyboard, because the bit
;   is never down two frames running.
;
;   Polled, not interrupt driven: the IFR flag raises on the strobe whether or
;   not the VIA is allowed to assert IRQ, and this cartridge never clears the
;   CPU's I flag (D7). Reading the port takes the byte and clears the flag.
; -----------------------------------------------------------------------------
HalReadInput:
  lda HW_PRESENT
  and #HW_GPIO                  ; No GPIO card means a floating bus, not input
  beq @None

  jsr ScanKeys                  ; BEFORE the joystick: ReadJoystick1 releases
  sta Tmp2                      ;   both encoders, and a key pending at that
                                ;   moment would go with them

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
  ora Tmp2
  rts

@None:
  lda #0
  rts

; -----------------------------------------------------------------------------
;   ScanKeys — whatever the two encoders have strobed since the last frame
;   Out: A = INPUT_* bits.  Modifies: A, X, Tmp2
;   Both are checked, so either keyboard drives the game.
; -----------------------------------------------------------------------------
ScanKeys:
  lda #0
  sta Tmp2

  lda GPIO_IFR
  and #GPIO_INT_CB1             ; Matrix keyboard encoder, on port B
  beq @Ps2
  lda GPIO_PORTB                ; Reading it takes the byte and clears CB1
  jsr KeyBit
  ora Tmp2
  sta Tmp2

@Ps2:
  lda GPIO_IFR
  and #GPIO_INT_CA1             ; PS/2 encoder, on port A
  beq @Done
  lda GPIO_PORTA
  jsr KeyBit
  ora Tmp2
  sta Tmp2

@Done:
  lda Tmp2
  rts

; -----------------------------------------------------------------------------
;   KeyBit — one ASCII byte to one input bit
;   In:  A = character      Out: A = INPUT_* bit, or 0 for anything else
;   SPEC 11.2. Two control schemes, either one whole on its own:
;
;     WASD    W rotate, S drop, A/D move
;     Arrows  cursor up rotate, down drop, left/right move
;
;   and SPACE under both of them, as rotate-back and as start (D15). That is
;   the same scheme all three machines read — a key does the same thing on
;   every one of them, and this file is not the place to be interesting.
;
;   The encoders DO define codes for the arrow keys — the C0 four nobody
;   else uses, $1C left, $1D right, $1E up, $1F down — and send them from
;   the matrix keyboard and the PS/2 port alike. They are matched before the
;   case fold below, which would otherwise turn them into punctuation.
; -----------------------------------------------------------------------------
KeyBit:
  cmp #$1C                      ; Cursor left
  beq @Left
  cmp #$1D                      ; Cursor right
  beq @Right
  cmp #$1E                      ; Cursor up
  beq @Up
  cmp #$1F                      ; Cursor down
  beq @Down
  cmp #$0D                      ; RETURN — confirm
  beq @Fire
  cmp #' '                      ; SPACE — rotate back, and start
  beq @Fire
  ora #$20                      ; Fold to lower case. Anything that is not a
  cmp #'w'                      ;   letter simply matches nothing below.
  beq @Up
  cmp #'s'
  beq @Down
  cmp #'a'
  beq @Left
  cmp #'d'
  beq @Right
  cmp #'q'
  beq @Fire
  cmp #'p'
  beq @Pause
  lda #0
  rts

@Up:
  lda #INPUT_UP
  rts
@Down:
  lda #INPUT_DOWN
  rts
@Left:
  lda #INPUT_LEFT
  rts
@Right:
  lda #INPUT_RIGHT
  rts
@Fire:
  lda #INPUT_FIRE
  rts
@Pause:
  lda #INPUT_PAUSE
  rts

; -----------------------------------------------------------------------------
;   HalDetectRegion — the TMS9918 here is 60 Hz
; -----------------------------------------------------------------------------
HalDetectRegion:
  lda #0                        ; NTSC
  rts

; -----------------------------------------------------------------------------
;   HalColorFlash — the fireball's detonation (SPEC 4.6, 14)
;   In:  A = colour key ($40..$68), or TINT_NONE.  Modifies: A, X, Y, TintColor
;
;   ONE BYTE. A tile's colour on this machine belongs to its 8-pattern group
;   and not to the cell, so turning every red tile on the board white is a
;   single write to the VDP colour table — and its undo is another. SPEC 4.6
;   calls this the fireball's free trick and it is not an exaggeration: the
;   Commodores' equivalent costs a compare on every cell they draw for as long
;   as the flash lasts, and this costs nothing at all once it is lit.
;
;   The group index is the colour key >> 3, because both the tile map and the
;   colour table are eight patterns to a group (SPEC Appendix A).
;
;   The old colour goes back BEFORE the new one is lit, so two fireballs of
;   different colours in one step leave exactly one group flashing rather than
;   one group flashing and another stuck white for the rest of the game.
; -----------------------------------------------------------------------------
HalColorFlash:
  pha
  ldy TintColor
  cpy #TINT_NONE
  beq @Light                    ; Nothing lit — nothing to put back
  tya
  lsr a
  lsr a
  lsr a
  tay
  lda TileColorTMS,y            ; Its own colour, straight out of the table the
  jsr VdpPutColor               ;   init loaded from

@Light:
  pla
  sta TintColor
  cmp #TINT_NONE
  beq @Done
  lsr a
  lsr a
  lsr a
  tay
  lda TileColorTMS,y
  and #$0F                      ; Keep the background nibble — black (SPEC 4.3)
  ora #$F0                      ; ...and make the foreground white
  jsr VdpPutColor
@Done:
  rts

; -----------------------------------------------------------------------------
;   VdpPutColor — In: A = colour byte, Y = group 0-31.  Modifies: A, X, Y
; -----------------------------------------------------------------------------
VdpPutColor:
  pha
  tya
  clc
  adc #<VRAM_COLORS             ; 32 bytes, one per group; the low byte of the
  ldx #>VRAM_COLORS             ;   table's address is zero so this cannot carry
  jsr VdpSetWrite
  pla
  sta VC_DATA
  rts

; -----------------------------------------------------------------------------
;   HalSfx — one note on the SID at $9800 (hal.inc)
;   In:  A = TIMBRE_*, X = note.  Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2
;
;   The sound card is the one piece of this machine the game uses and cannot
;   count on — HW_PRESENT bit 6 is set by the BIOS probe at boot, and a machine
;   with an empty IO 7 leaves it clear. Writing to an absent card's addresses
;   is a read of a floating bus away from being harmless, and "harmless" is not
;   a thing to build a frame on: the guard is four cycles and the game plays
;   through in silence without it (PLAN.md P8).
; -----------------------------------------------------------------------------
HalSfx:
  pha
  lda HW_PRESENT
  and #HW_SID
  beq @None
  pla
  jmp SidSfx                    ; include/sid.inc, shared with the C64
@None:
  pla
  rts

SID_BASE = $9800                ; IO 7 (ac6502.inc). The C64's is $D400 and
.include "../include/sid.inc"   ;   nothing else about the two differs

; =============================================================================
;   Data
; =============================================================================

.segment "RODATA"

.include "../data/tilecolor-tms9918.inc"
.include "../src/tables.inc"
.include "../src/strings.inc"

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
