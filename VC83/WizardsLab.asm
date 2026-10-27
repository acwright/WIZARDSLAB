.setcpu "65C02"

; =============================================================================
;   Wizards Lab — VC83
; =============================================================================
;   A program for the VC83, run from the SD card with EXEC "WIZLAB.PRG" at
;   the BASIC prompt. There is no VC83 hardware yet, so this targets Willis
;   Blackburn's simulator, built from vc83computer at commit 8648902.
;
;   The VCGA runs one tilemap layer: 40 x 25 cells of 8 x 8 pixels, doubled to
;   fill the 640 x 400 frame, the same grid as the C64's.
;
;   This file will be the platform half of the contract in src/hal.inc. For
;   now it is a skeleton that proves the platform: it brings up the layer,
;   fills it with every tile index over the system font, and goes back to
;   BASIC on Esc. It does not include the game yet.
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

TILEMAP             = $A000         ; VRAM $80000, through window A
TILE_RAM            = $A000         ; Tile RAM $A0000, through window A at init
                                    ;   only: 2 K per bitplane, two per window

; --- VCGA, through window D --------------------------------------------------
VCGA_LAYER_MODE     = $D00C         ; + 32 * layer: 0 = disabled
VCGA_FRAME          = $D087         ; Frame counter, low byte: +1 per vblank

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

.segment "ZEROPAGE"

Ptr:            .res 2

.segment "CODE"

Start:
  stz OS_ARG3                       ; Base 0: the tilemap at the start of VRAM
  stz OS_ARG4
  lda #LAYER_REGION
  sta OS_ARG1
  lda #LAYER_FORMAT
  sta OS_ARG2
  lda #0
  jsr OS_VCGALAYER
  jsr SetWindows

  stz VCGA_LAYER_MODE + 32*1        ; BASIC's console is layer 2, and EXEC
  stz VCGA_LAYER_MODE + 32*2        ;   leaves it on
  stz VCGA_LAYER_MODE + 32*3

  jsr ClearUpperPlanes
  jsr FillTestPattern

@loop:
  jsr WaitFrame
  jsr DrainKeys
  bcs @exit                         ; Esc typed since the last frame,
  lda KBD_HELD + KEY_ESC/8          ;   or held now
  and #1 << (KEY_ESC .mod 8)
  beq @loop
@exit:
  jmp ExitToBasic

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
;   ClearUpperPlanes — zero tile RAM bitplanes 1-7, leaving the system font
;   in plane 0, so an 8 bpp layer draws it in palette entries 0 and 1
; -----------------------------------------------------------------------------
ClearUpperPlanes:
  ldx #$A0                          ; Planes 0-1, then 2-3, 4-5, 6-7
@window:
  stx BANK_A
  ldy #>TILE_RAM + 8                ; Skip plane 0 in the first window
  cpx #$A0
  beq @set
  ldy #>TILE_RAM
@set:
  sty Ptr + 1
  stz Ptr
  lda #0
@page:
  ldy #0
@byte:
  sta (Ptr),y
  iny
  bne @byte
  inc Ptr + 1
  ldy Ptr + 1
  cpy #>TILE_RAM + $10
  bne @page
  inx
  cpx #$A4
  bne @window
  lda #WIN_VRAM
  sta BANK_A
  rts

; -----------------------------------------------------------------------------
;   FillTestPattern — every cell n gets tile n mod 256
; -----------------------------------------------------------------------------
FillTestPattern:
  lda #<TILEMAP
  sta Ptr
  lda #>TILEMAP
  sta Ptr + 1
  ldx #>(SCR_CELLS + 255)           ; Four pages: 1024 cells, the last 24
  ldy #0                            ;   past the bottom row are not shown
@byte:
  tya
  sta (Ptr),y
  iny
  bne @byte
  inc Ptr + 1
  dex
  bne @byte
  rts

; -----------------------------------------------------------------------------
;   WaitFrame — block until the frame counter moves
; -----------------------------------------------------------------------------
WaitFrame:
  lda VCGA_FRAME
@wait:
  cmp VCGA_FRAME
  beq @wait
  rts

; -----------------------------------------------------------------------------
;   DrainKeys — empty the keyboard FIFO, which BASIC's line editor would
;   otherwise read as typing when it gets the machine back
;   Out: carry set if one of the entries was Esc. A tap shorter than a frame
;        can come and go between two looks at the held bits, but it always
;        leaves its character here.
; -----------------------------------------------------------------------------
;        Modifies: A, X
DrainKeys:
  ldx #0                            ; Becomes 1 at the first Esc
@next:
  lda KBD_LEVEL                     ; Plain LDA abs only: see
  and #$7F                          ;   doc/bus_accelerator.md
  beq @done
  lda KBD_DATA
  cmp #ASCII_ESC
  bne @next
  ldx #1
  bra @next
@done:
  cpx #1                            ; Carry = X >= 1
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
  jsr OS_EXEC                       ; Does not return unless it failed
  jmp (OS_RESET)

.segment "RODATA"

BasicPath:      .byte "B:BASIC.PRG"
BasicPathLen    = * - BasicPath
