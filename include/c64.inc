; C64 Include File for ca65
; KERNAL routines, VIC-II, SID, and CIA registers

;=============================================================================
; KERNAL Routines
;=============================================================================
CHROUT          = $FFD2         ; Output character in A
CHRIN           = $FFCF         ; Input character
GETIN           = $FFE4         ; Get character from keyboard buffer
SCNKEY          = $FF9F         ; Scan the keyboard
PLOT            = $FFF0         ; Read/set cursor position
CLRSCR          = $E544         ; Clear the screen
STOP            = $FFE1         ; Test the STOP key
SETLFS          = $FFBA         ; Set logical file parameters
SETNAM          = $FFBD         ; Set filename
LOAD            = $FFD5         ; Load from device
SAVE            = $FFD8         ; Save to device

;=============================================================================
; Memory
;=============================================================================
SCREEN          = $0400         ; Screen memory (40 x 25)
COLRAM          = $D800         ; Color RAM
BASIC_START     = $0801         ; Start of BASIC program area

;=============================================================================
; VIC-II - Video
;=============================================================================
VIC_SPR0X       = $D000         ; Sprite 0 X position
VIC_SPR0Y       = $D001         ; Sprite 0 Y position
VIC_SPRENA      = $D015         ; Sprite enable
VIC_CTRL1       = $D011         ; Control register 1
VIC_RASTER      = $D012         ; Raster line
VIC_CTRL2       = $D016         ; Control register 2
VIC_MEMPTR      = $D018         ; Memory pointers
VIC_IRR         = $D019         ; Interrupt request register
VIC_IMR         = $D01A         ; Interrupt mask register
VIC_BORDERCOL   = $D020         ; Border color
VIC_BGCOL0      = $D021         ; Background color 0

;=============================================================================
; SID - Sound
;=============================================================================
SID_V1_FREQ     = $D400         ; Voice 1 frequency
SID_V1_CTRL     = $D404         ; Voice 1 control
SID_V1_AD       = $D405         ; Voice 1 attack/decay
SID_V1_SR       = $D406         ; Voice 1 sustain/release
SID_VOLUME      = $D418         ; Volume and filter select

;=============================================================================
; CIA - I/O
;=============================================================================
CIA1_PRA        = $DC00         ; Port A (keyboard/joystick 2)
CIA1_PRB        = $DC01         ; Port B (keyboard/joystick 1)
CIA1_ICR        = $DC0D         ; Interrupt control
CIA2_PRA        = $DD00         ; Port A (VIC bank select)

;=============================================================================
; Colors
;=============================================================================
COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7

;=============================================================================
; PETSCII Control Codes
;=============================================================================
CHR_CLEAR       = $93           ; Clear screen
CHR_HOME        = $13           ; Cursor home
CHR_CR          = $0D           ; Carriage return
CHR_WHITE       = $05           ; Set text color to white
