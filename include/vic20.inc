; VIC-20 Include File for ca65
; Memory addresses, KERNAL routines, and hardware registers
; Compatible with both NTSC and PAL VIC-20 systems

;=============================================================================
; Zero Page Locations
;=============================================================================
VARTAB          = $2D           ; Pointer to start of BASIC variables
ARYTAB          = $2F           ; Pointer to start of BASIC arrays
STREND          = $31           ; Pointer to end of BASIC arrays
FRETOP          = $33           ; Pointer to bottom of string space
MEMSIZ          = $37           ; Pointer to top of BASIC memory
TIME            = $A0           ; Jiffy clock (3 bytes)
TIMER           = $A0           ; Same as TIME
STATUS          = $90           ; I/O status byte
STKEY           = $91           ; STOP key flag
MSGFLG          = $9D           ; Kernal message control flag
FNLEN           = $B7           ; Length of filename
LA              = $B8           ; Logical file number
SA              = $B9           ; Secondary address
FA              = $BA           ; Device number
FNADR           = $BB           ; Pointer to filename (2 bytes)
STAL            = $C1           ; Pointer for tape I/O (2 bytes)
EAL             = $C3           ; Pointer for tape I/O (2 bytes)

;=============================================================================
; Screen and Color Memory (Unexpanded VIC-20)
;=============================================================================
SCREEN          = $1E00         ; Screen memory start (22x23 default)
COLRAM          = $9600         ; Color RAM start

;=============================================================================
; User BASIC Memory
;=============================================================================
BASIC_START     = $1001         ; Start of BASIC program area
BASIC_END       = $1E00         ; End of BASIC (screen memory starts)

;=============================================================================
; VIC Chip Registers (6560/6561 Video Interface Chip)
;=============================================================================
VIC             = $9000         ; Base address of VIC chip

; Individual VIC registers
VIC_CR0         = $9000         ; Horizontal centering (bit 7 = interlace)
VIC_CR1         = $9001         ; Vertical centering
VIC_CR2         = $9002         ; Video matrix columns (bits 0-6, bit 7=raster)
VIC_CR3         = $9003         ; Raster value (bits 1-7 = rows*2, bit 0=character size)
VIC_CR4         = $9004         ; TV raster beam location (read only)
VIC_CR5         = $9005         ; Video matrix start address (bits 4-7)
VIC_CRA         = $900A         ; Bass frequency
VIC_CRB         = $900B         ; Alto frequency  
VIC_CRC         = $900C         ; Soprano frequency
VIC_CRD         = $900D         ; Noise frequency
VIC_CRE         = $900E         ; Auxiliary color / Volume
VIC_CRF         = $900F         ; Screen & border colors / reverse mode

; VIC register aliases
VIC_HORZ        = VIC_CR0       ; Horizontal position
VIC_VERT        = VIC_CR1       ; Vertical position
VIC_COLUMNS     = VIC_CR2       ; Number of columns
VIC_ROWS        = VIC_CR3       ; Number of rows
VIC_RASTER      = VIC_CR4       ; Raster position
VIC_ORIGIN      = VIC_CR5       ; Screen memory location
VIC_BASS        = VIC_CRA       ; Sound: Bass voice
VIC_ALTO        = VIC_CRB       ; Sound: Alto voice
VIC_SOPRANO     = VIC_CRC       ; Sound: Soprano voice
VIC_NOISE       = VIC_CRD       ; Sound: Noise voice
VIC_VOLUME      = VIC_CRE       ; Volume control (bits 0-3)
VIC_AUX_COLOR   = VIC_CRE       ; Auxiliary color (bits 4-7)
VIC_BACKGROUND  = VIC_CRF       ; Background color (bits 4-7)
VIC_BORDER      = VIC_CRF       ; Border color (bits 0-2)
VIC_REVERSE     = VIC_CRF       ; Reverse mode (bit 3)

;=============================================================================
; VIA Chip #1 Registers (6522 VIA - Keyboard, Joystick)
;=============================================================================
VIA1            = $9110         ; Base address of VIA1
VIA1_PB         = $9110         ; Port B (keyboard row select, joystick)
VIA1_PA1        = $9111         ; Port A (keyboard column read)
VIA1_DDRB       = $9112         ; Data direction register B
VIA1_DDRA       = $9113         ; Data direction register A
VIA1_T1CL       = $9114         ; Timer 1 counter low
VIA1_T1CH       = $9115         ; Timer 1 counter high
VIA1_T1LL       = $9116         ; Timer 1 latch low
VIA1_T1LH       = $9117         ; Timer 1 latch high
VIA1_T2CL       = $9118         ; Timer 2 counter low
VIA1_T2CH       = $9119         ; Timer 2 counter high
VIA1_SR         = $911A         ; Shift register
VIA1_ACR        = $911B         ; Auxiliary control register
VIA1_PCR        = $911C         ; Peripheral control register
VIA1_IFR        = $911D         ; Interrupt flag register
VIA1_IER        = $911E         ; Interrupt enable register
VIA1_PA2        = $911F         ; Port A (no handshake)

;=============================================================================
; VIA Chip #2 Registers (6522 VIA - Serial, Tape, Joystick)
;=============================================================================
VIA2            = $9120         ; Base address of VIA2
VIA2_PB         = $9120         ; Port B (serial bus, tape control, joystick)
VIA2_PA1        = $9121         ; Port A (serial bus)
VIA2_DDRB       = $9122         ; Data direction register B
VIA2_DDRA       = $9123         ; Data direction register A
VIA2_T1CL       = $9124         ; Timer 1 counter low
VIA2_T1CH       = $9125         ; Timer 1 counter high
VIA2_T1LL       = $9126         ; Timer 1 latch low
VIA2_T1LH       = $9127         ; Timer 1 latch high
VIA2_T2CL       = $9128         ; Timer 2 counter low
VIA2_T2CH       = $9129         ; Timer 2 counter high
VIA2_SR         = $912A         ; Shift register
VIA2_ACR        = $912B         ; Auxiliary control register
VIA2_PCR        = $912C         ; Peripheral control register
VIA2_IFR        = $912D         ; Interrupt flag register
VIA2_IER        = $912E         ; Interrupt enable register
VIA2_PA2        = $912F         ; Port A (no handshake)

;=============================================================================
; Joystick (VIA1 Port A = $9111, VIA2 Port B = $9120)
; Active-low: bit is 0 when the switch is closed (direction/fire pressed)
;=============================================================================
JOY_UP          = %00000100     ; VIA1_PA1 bit 2
JOY_DOWN        = %00001000     ; VIA1_PA1 bit 3
JOY_LEFT        = %00010000     ; VIA1_PA1 bit 4
JOY_FIRE        = %00100000     ; VIA1_PA1 bit 5
JOY_RIGHT       = %10000000     ; VIA2_PB bit 7

;=============================================================================
; Color Codes
;=============================================================================
BLACK           = $00
WHITE           = $01
RED             = $02
CYAN            = $03
PURPLE          = $04
GREEN           = $05
BLUE            = $06
YELLOW          = $07
ORANGE          = $08
LIGHT_ORANGE    = $09
PINK            = $0A
LIGHT_CYAN      = $0B
LIGHT_PURPLE    = $0C
LIGHT_GREEN     = $0D
LIGHT_BLUE      = $0E
LIGHT_YELLOW    = $0F

;=============================================================================
; Character Codes (PETSCII)
;=============================================================================
CHR_RETURN      = $0D
CHR_SPACE       = $20
CHR_DELETE      = $14
CHR_INSERT      = $94
CHR_HOME        = $13
CHR_CLEAR       = $93
CHR_RVSON       = $12           ; Reverse on
CHR_RVSOFF      = $92           ; Reverse off
CHR_DOWN        = $11
CHR_UP          = $91
CHR_RIGHT       = $1D
CHR_LEFT        = $9D
CHR_BLACK       = $90
CHR_WHITE       = $05
CHR_RED         = $1C
CHR_CYAN        = $9F
CHR_PURPLE      = $9C
CHR_GREEN       = $1E
CHR_BLUE        = $9E
CHR_YELLOW      = $9B

;=============================================================================
; ROM Addresses
;=============================================================================
CHARROM         = $8000         ; Character ROM
BASIC_ROM       = $C000         ; BASIC ROM start
KERNAL_ROM      = $E000         ; KERNAL ROM start

;=============================================================================
; KERNAL Routines
;=============================================================================
; Internal KERNAL routines (address may vary by ROM version)
CINT            = $E518         ; Initialize screen editor
IOINIT          = $FDF9         ; Initialize I/O
RAMTAS          = $FD8D         ; Initialize RAM
RESTOR          = $FD52         ; Restore default I/O vectors
VECTOR          = $FD1A         ; Manage RAM vectors

; KERNAL Jump Table (standard across all VIC-20s)
SETMSG          = $FF90         ; Control KERNAL messages
SECOND          = $FF93         ; Send secondary address
TKSA            = $FF96         ; Send secondary address for talk
MEMTOP          = $FF99         ; Read/set top of memory
MEMBOT          = $FF9C         ; Read/set bottom of memory
SCNKEY          = $FF9F         ; Scan keyboard
SETTMO          = $FFA2         ; Set timeout for serial bus
ACPTR           = $FFA5         ; Input byte from serial bus
CIOUT           = $FFA8         ; Output byte to serial bus
UNTLK           = $FFAB         ; Send UNTALK to serial bus
UNLSN           = $FFAE         ; Send UNLISTEN to serial bus
LISTEN          = $FFB1         ; Send LISTEN to serial bus
TALK            = $FFB4         ; Send TALK to serial bus
READST          = $FFB7         ; Read I/O status word
SETLFS          = $FFBA         ; Set logical file parameters
SETNAM          = $FFBD         ; Set filename
OPEN            = $FFC0         ; Open a logical file
CLOSE           = $FFC3         ; Close a logical file
CHKIN           = $FFC6         ; Define file as default input
CHKOUT          = $FFC9         ; Define file as default output
CLRCHN          = $FFCC         ; Restore default I/O devices
CHRIN           = $FFCF         ; Input character from channel
CHROUT          = $FFD2         ; Output character to channel
LOAD            = $FFD5         ; Load RAM from device
SAVE            = $FFD8         ; Save RAM to device
SETTIM          = $FFDB         ; Set 24-hour clock
RDTIM           = $FFDE         ; Read 24-hour clock
STOP            = $FFE1         ; Check STOP key
GETIN           = $FFE4         ; Get character from keyboard
CLALL           = $FFE7         ; Close all channels and files
UDTIM           = $FFEA         ; Increment 24-hour clock
SCREEN_ORG      = $FFED         ; Return screen organization
PLOT            = $FFF0         ; Read/set cursor X/Y position
IOBASE          = $FFF3         ; Return I/O base address

;=============================================================================
; IRQ/NMI Vectors
;=============================================================================
IRQ_VECTOR      = $0314         ; IRQ vector (2 bytes)
BRK_VECTOR      = $0316         ; BRK vector (2 bytes)
NMI_VECTOR      = $0318         ; NMI vector (2 bytes)

;=============================================================================
; Hardware Vectors (in ROM)
;=============================================================================
HW_NMI          = $FFFA         ; NMI vector
HW_RESET        = $FFFC         ; Reset vector
HW_IRQ          = $FFFE         ; IRQ/BRK vector

;=============================================================================
; Useful Constants
;=============================================================================
SCREEN_COLS     = 22            ; Default screen columns
SCREEN_ROWS     = 23            ; Default screen rows
JIFFY_PAL       = 50            ; Jiffies per second (PAL)
JIFFY_NTSC      = 60            ; Jiffies per second (NTSC)

;=============================================================================
; Memory Expansion Configurations
;=============================================================================
; RAM Block 0 (BLK0) = $0400-$0FFF (3K)
; RAM Block 1 (BLK1) = $2000-$3FFF (8K)
; RAM Block 2 (BLK2) = $4000-$5FFF (8K)
; RAM Block 3 (BLK3) = $6000-$7FFF (8K)
; RAM Block 5 (BLK5) = $A000-$BFFF (8K)

BLK0            = $0400         ; 3K expansion
BLK1            = $2000         ; 8K expansion
BLK2            = $4000         ; 8K expansion
BLK3            = $6000         ; 8K expansion
BLK5            = $A000         ; 8K expansion

;=============================================================================
; End of VIC20.inc
;=============================================================================
