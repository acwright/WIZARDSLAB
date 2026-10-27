.setcpu "65C02"

; =============================================================================
;   Wizards Lab — VC83
; =============================================================================
;   A program for the VC83, run from the SD card with EXEC "WIZLAB.PRG" at
;   the BASIC prompt. There is no VC83 hardware yet, so this targets Willis
;   Blackburn's simulator, built from vc83computer at commit 8648902.
;
;   The VCGA runs one tilemap layer: 40 x 25 cells of 8 x 8 pixels, doubled to
;   fill the 640 x 400 frame. That is the C64's grid, so the C64's two screen
;   images serve here unchanged, and the panel sits where it does there.
;
;   Colour follows the TMS9918's model, not the C64's. A VCGA tilemap has no
;   colour per cell, only a pixel value per tile, so each tile is drawn in
;   8 bpp and its pixel values name its 8-pattern group: (group << 1) | bit.
;   Each group then owns two palette entries, its background and foreground,
;   which is the AC6502's colour table under another name, and the fireball's
;   flash is one palette write as it is there.
;
;   This file is the platform half of the contract in src/hal.inc. For now
;   input reads only Esc, which goes back to BASIC, and the game is silent.
;
;   Built with VC83.cfg.
; =============================================================================

; --- Zero page and OS (submodules/vc83os/os.inc) -----------------------------
BANK_A              = $00           ; Bank window selects: each holds bus
BANK_B              = $01           ;   address bits 19:12 for its 4 K window
BANK_C              = $02
BANK_D              = $03

OS_ARG1             = $20           ; OS call arguments
OS_ARG2             = $21
OS_ARG3             = $22
OS_ARG4             = $23
OS_PATH_PTR         = $31           ; EXEC's file name, and its length
OS_PATH_LEN         = $33

OS_EXEC             = $E000         ; Load and run a .PRG; returns only on error
OS_VCGALAYER        = $E003         ; Configure one VCGA layer
OS_RESET            = $FFFC         ; Cold-start vector, if EXEC fails

; --- Bank windows while the game runs ----------------------------------------
;   Each window is pointed at one device and left there; anything that moves
;   one (an OS call does) puts it back with SetWindows.
WIN_VRAM            = $80           ; A: VRAM $80000, the tilemap
WIN_KBD             = $E0           ; B: peripheral slots, the keyboard
WIN_VCSS            = $C0           ; C: VCSS registers
WIN_VCGA            = $B0           ; D: VCGA registers and palette RAM
WIN_TILE_RAM        = $A0           ; A, during init only: tile RAM $A0000

TILEMAP             = $A000         ; VRAM $80000, through window A
TILE_RAM            = $A000         ; Tile RAM through window A: one 2 K
PLANE_BYTES         = $0800         ;   bitplane per half, two per window

; --- VCGA, through window D --------------------------------------------------
VCGA_LAYER_MODE     = $D00C         ; + 32 * layer: 0 = disabled
VCGA_BG_PALETTE     = $D080         ; Colour outside every layer: palette...
VCGA_BG_COLOR       = $D081         ;   ...and entry
VCGA_FRAME          = $D087         ; Frame counter, low byte: +1 per vblank
PALETTE             = $D800         ; Palette 0, $B0800: 256 entries of 2 bytes,
                                    ;   little-endian 0rrrrrgggggbbbbb

LAYER_REGION        = $04           ; Part 1 (full) of frame 0 (640 x 400)
LAYER_FORMAT        = $14           ; Text, 2X, 8 bpp: 40 x 25 cells

; --- Keyboard, through window B ($E0000, registers from $E0080) --------------
KBD_LEVEL           = $B080         ; FIFO entries waiting (bit 7 = overflow)
KBD_DATA            = $B081         ; Read pops one entry
KBD_HELD            = $B086         ; 10 bytes: one bit per matrix key, held
KEY_ESC             = 1             ; Matrix code
ASCII_ESC           = $1B           ; What a press of it puts in the FIFO

; --- Platform constants (hal.inc) --------------------------------------------
SCR_COLS            = 40
SCR_ROWS            = 25
SCR_CELLS           = SCR_COLS * SCR_ROWS     ; 1000
PANEL_X             = 9             ; (40 - 22) / 2, as on the C64
PANEL_Y             = 0
HAS_COLOR_RAM       = 0             ; Colour lives in the palette, by group

.include "../src/constants.inc"
.include "../src/zeropage.inc"
.include "../src/ram.inc"
.include "../src/hal.inc"

; =============================================================================
;   Header — see VC83.cfg
; =============================================================================

.segment "HEADER"

  .byte "VC83"
  .word Start
  .word __MAIN_START__              ; One segment record: the whole image,
  .byte $00                         ;   into main RAM
  .word __MAIN_LAST__ - __MAIN_START__

.import __MAIN_START__, __MAIN_LAST__

; =============================================================================
;   Entry — EXEC leaves interrupts off, the windows at 0 and S at $FF
; =============================================================================

.segment "CODE"

Start:
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
;   HAL — VCGA, one 8 bpp tilemap layer
; =============================================================================

; -----------------------------------------------------------------------------
;   SetWindows — point all four bank windows where the game keeps them
; -----------------------------------------------------------------------------
SetWindows:
  lda #WIN_VRAM
  sta BANK_A
  lda #WIN_KBD
  sta BANK_B
  lda #WIN_VCSS
  sta BANK_C
  lda #WIN_VCGA
  sta BANK_D
  rts

; -----------------------------------------------------------------------------
;   HalInitVideo — the layer, its tiles and palette, black everywhere
;   VCGALAYER sets every layer 0 register and loads B:PALETTE.DAT over
;   palette 0, so the palette is written after it, not before.
; -----------------------------------------------------------------------------
HalInitVideo:
  stz OS_ARG3                   ; Base 0: the tilemap at the start of VRAM
  stz OS_ARG4
  lda #LAYER_REGION
  sta OS_ARG1
  lda #LAYER_FORMAT
  sta OS_ARG2
  lda #0                        ; Layer 0, which uses palette 0
  jsr OS_VCGALAYER
  jsr SetWindows

  stz VCGA_LAYER_MODE + 32*1    ; BASIC's console is layer 2, and EXEC
  stz VCGA_LAYER_MODE + 32*2    ;   leaves it on
  stz VCGA_LAYER_MODE + 32*3

  jsr LoadPlanes
  jsr LoadPalette

  stz VCGA_BG_PALETTE           ; Palette 0, entry 0: group 0's background,
  stz VCGA_BG_COLOR             ;   which is black (tilecolor-tms9918.inc)
  ; falls through

; -----------------------------------------------------------------------------
;   HalClearScreen — fill the tilemap with the blank tile
; -----------------------------------------------------------------------------
HalClearScreen:
  lda #TILE_BLANK
  ldx #0
@Cell:
  sta TILEMAP + $0000,x
  sta TILEMAP + $0100,x
  sta TILEMAP + $0200,x
  sta TILEMAP + $02E8,x         ; The last page overlaps the third: 1000 cells
  inx
  bne @Cell
  rts

; -----------------------------------------------------------------------------
;   LoadPlanes — all 16 K of tile RAM: the tileset in bitplane 0, and its
;   colour group, five bits of it, across planes 1-5
;   PLACEHOLDER ART: Tileset is data/tileset.bin. See data/README.md.
;
;   Bitplane b holds bit b of every pixel, at tile * 8 + row; bit 7 is the
;   leftmost pixel, as on the TMS9918, so plane 0 is the tileset verbatim.
;   Planes 1-5 are each tile's group, which is the same for all 64 pixels of
;   it: $FF for every row where the group has that bit set, $00 where not.
;   Planes 6 and 7 are zero. All of it is overwritten here, and BASIC reloads
;   its own font into plane 0 when it starts again.
; -----------------------------------------------------------------------------
LoadPlanes:
  lda #WIN_TILE_RAM             ; Planes 0 and 1
  sta BANK_A

  lda #<Tileset
  sta SrcPtr
  lda #>Tileset
  sta SrcPtr+1
  lda #<TILE_RAM
  sta DstPtr
  lda #>TILE_RAM
  sta DstPtr+1
  ldx #>PLANE_BYTES             ; 8 x 256 = 2048 bytes
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

  ldx #1                        ; X = plane
@Plane:
  txa
  lsr a                         ; Two planes to a window
  ora #WIN_TILE_RAM
  sta BANK_A
  txa
  and #1                        ; Odd planes are the upper half of it
  asl a
  asl a
  asl a
  ora #>TILE_RAM
  sta DstPtr+1
  stz DstPtr

  stz Tmp0                      ; Tmp0 = group, 32 of them, 64 bytes each
@Group:
  lda Tmp0
  and PlaneBit,x
  beq @Fill                     ; A = $00 for this group in this plane...
  lda #$FF                      ; ...or $FF
@Fill:
  ldy #63
@Row:
  sta (DstPtr),y
  dey
  bpl @Row
  lda DstPtr
  clc
  adc #64
  sta DstPtr
  bcc @Next
  inc DstPtr+1
@Next:
  inc Tmp0
  lda Tmp0
  cmp #32
  bne @Group

  inx
  cpx #8
  bne @Plane

  lda #WIN_VRAM
  sta BANK_A
  rts

; -----------------------------------------------------------------------------
;   LoadPalette — palette entries 0-63: each group's background at 2g and its
;   foreground at 2g + 1, out of the AC6502's colour table
;   This is what makes a tile red: its pattern number selects the group, the
;   group selects the entries, and nothing is per cell.
; -----------------------------------------------------------------------------
LoadPalette:
  ldx #0                        ; X = group
  ldy #0                        ; Y = byte offset into the palette, 4 a group
@Group:
  lda TileColorTMS,x
  and #$0F                      ; Background
  jsr PutTmsColor
  lda TileColorTMS,x
  lsr a                         ; Foreground
  lsr a
  lsr a
  lsr a
  jsr PutTmsColor
  inx
  cpx #32
  bne @Group
  rts

; -----------------------------------------------------------------------------
;   PutTmsColor — In: A = TMS9918 colour 0-15, Y = palette byte offset
;   Out: Y advanced past the entry.  Modifies: A
; -----------------------------------------------------------------------------
PutTmsColor:
  phx
  asl a
  tax
  lda TmsRgb,x
  sta PALETTE,y
  iny
  lda TmsRgb+1,x
  sta PALETTE,y
  iny
  plx
  rts

; -----------------------------------------------------------------------------
;   HalWaitFrame — wait for the frame counter, which counts vblank starts
;   No interrupts here, as on the AC6502: the I flag EXEC left set stays set.
; -----------------------------------------------------------------------------
HalWaitFrame:
  lda VCGA_FRAME
@Wait:
  cmp VCGA_FRAME
  beq @Wait
  rts

; -----------------------------------------------------------------------------
;   HalPlotCell — In: A = tile, X = screen column, Y = screen row
;   The tile is the whole of a cell here; its colour comes with it.
; -----------------------------------------------------------------------------
HalPlotCell:
  pha
  lda RowLo,y
  sta ScreenPtr
  lda RowHi,y
  sta ScreenPtr+1
  txa
  tay                           ; Y = column
  pla
  sta (ScreenPtr),y
  rts

; -----------------------------------------------------------------------------
;   HalBlitScreen — draw a full 1000-byte screen image
;   In: SrcPtr -> image. Ptr1 (colour) is ignored: as on the AC6502, colour is
;   the tile's, so the C64's name table is all this needs.
; -----------------------------------------------------------------------------
HalBlitScreen:
  ldy #0
@Page0:
  lda (SrcPtr),y
  sta TILEMAP + $0000,y
  iny
  bne @Page0
  inc SrcPtr+1
@Page1:
  lda (SrcPtr),y
  sta TILEMAP + $0100,y
  iny
  bne @Page1
  inc SrcPtr+1
@Page2:
  lda (SrcPtr),y
  sta TILEMAP + $0200,y
  iny
  bne @Page2
  inc SrcPtr+1
@Page3:
  lda (SrcPtr),y
  sta TILEMAP + $0300,y
  iny
  cpy #<(SCR_CELLS - 768)
  bne @Page3
  rts

; -----------------------------------------------------------------------------
;   HalReadInput — STUB: Esc goes back to BASIC; nothing else is read yet
;   Out: A = INPUT_* bits, active high
; -----------------------------------------------------------------------------
HalReadInput:
  jsr DrainKeys
  bcs @Exit                     ; Esc typed since the last frame,
  lda KBD_HELD + KEY_ESC/8      ;   or held now
  and #1 << (KEY_ESC .mod 8)
  bne @Exit
  lda #0
  rts
@Exit:
  jmp ExitToBasic

; -----------------------------------------------------------------------------
;   DrainKeys — empty the keyboard FIFO, which BASIC's line editor would
;   otherwise read as typing when it gets the machine back
;   Out: carry set if one of the entries was Esc. A tap shorter than a frame
;        can come and go between two looks at the held bits, but it always
;        leaves its character here.
;        Modifies: A, X
; -----------------------------------------------------------------------------
DrainKeys:
  ldx #0                        ; Becomes 1 at the first Esc
@Next:
  lda KBD_LEVEL                 ; Plain LDA abs only: see
  and #$7F                      ;   doc/bus_accelerator.md
  beq @Done
  lda KBD_DATA
  cmp #ASCII_ESC
  bne @Next
  ldx #1
  bra @Next
@Done:
  cpx #1                        ; Carry = X >= 1
  rts

; -----------------------------------------------------------------------------
;   ExitToBasic — wait for Esc to come up, drain, and EXEC BASIC afresh. It
;   reloads its own font and palette, so nothing here needs putting back.
; -----------------------------------------------------------------------------
ExitToBasic:
  jsr DrainKeys
  lda KBD_HELD + KEY_ESC/8
  and #1 << (KEY_ESC .mod 8)
  bne ExitToBasic
  jsr DrainKeys

  lda #<BasicPath
  sta OS_PATH_PTR
  lda #>BasicPath
  sta OS_PATH_PTR + 1
  lda #BasicPathLen
  sta OS_PATH_LEN
  jsr OS_EXEC                   ; Does not return unless it failed
  jmp (OS_RESET)

; -----------------------------------------------------------------------------
;   HalDetectRegion — the VCGA's output is 60 Hz
; -----------------------------------------------------------------------------
HalDetectRegion:
  lda #0                        ; NTSC
  rts

; -----------------------------------------------------------------------------
;   HalColorFlash — STUB: records the colour and lights nothing
;   In:  A = colour key ($40..$68), or TINT_NONE.  Modifies: TintColor
; -----------------------------------------------------------------------------
HalColorFlash:
  sta TintColor
  rts

; -----------------------------------------------------------------------------
;   HalSfx — STUB: silent
; -----------------------------------------------------------------------------
HalSfx:
  rts

; =============================================================================
;   Data
; =============================================================================

.segment "RODATA"

.include "../data/tilecolor-tms9918.inc"
.include "../src/tables.inc"
.include "../src/strings.inc"

BasicPath:      .byte "B:BASIC.PRG"
BasicPathLen    = * - BasicPath

; --- Which bit of the group each bitplane holds ------------------------------
PlaneBit:       .byte 0, 1, 2, 4, 8, 16, 0, 0

; --- The TMS9918's sixteen colours, as VCGA palette entries ------------------
;   Colour 0 is transparent on the TMS9918; here it is black, which is what
;   it shows through to there.
.define RGB(r, g, b) .word ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3)

TmsRgb:
  RGB $00, $00, $00             ;  0 transparent
  RGB $00, $00, $00             ;  1 black
  RGB $21, $C8, $42             ;  2 medium green
  RGB $5E, $DC, $78             ;  3 light green
  RGB $54, $55, $ED             ;  4 dark blue
  RGB $7D, $76, $FC             ;  5 light blue
  RGB $D4, $52, $4D             ;  6 dark red
  RGB $42, $EB, $F5             ;  7 cyan
  RGB $FC, $55, $54             ;  8 medium red
  RGB $FF, $79, $78             ;  9 light red
  RGB $D4, $C1, $54             ; 10 dark yellow
  RGB $E6, $CE, $80             ; 11 light yellow
  RGB $21, $B0, $3B             ; 12 dark green
  RGB $C9, $5B, $BA             ; 13 magenta
  RGB $CC, $CC, $CC             ; 14 gray
  RGB $FF, $FF, $FF             ; 15 white

; --- Tilemap row start addresses ---------------------------------------------
RowLo:
  .repeat SCR_ROWS, i
    .byte <(TILEMAP + i * SCR_COLS)
  .endrepeat
RowHi:
  .repeat SCR_ROWS, i
    .byte >(TILEMAP + i * SCR_COLS)
  .endrepeat

; --- PLACEHOLDER ART — see data/README.md ------------------------------------
;   The C64's screens: the same 40 x 25 grid. Their colour images are not
;   needed, because colour here belongs to the tile.
TitleScreen:  .incbin "../data/screen-title-c64.bin"
PlayScreen:   .incbin "../data/screen-play-c64.bin"
TitleColor    = TitleScreen
PlayColor     = PlayScreen

.segment "TILES"

Tileset:      .incbin "../data/tileset.bin"
