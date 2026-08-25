; =============================================================================
;   constants.inc — Wizards Lab, shared game constants
; =============================================================================
;   Everything here comes straight out of SPEC.md. If a number changes there,
;   it changes here, and nowhere else. Nothing in this file is platform
;   specific — see the per-platform WizardsLab.asm for PANEL_X / PANEL_Y and
;   the hardware addresses.
; =============================================================================

; --- Board (SPEC 3) ----------------------------------------------------------
BOARD_W             = 6         ; Playfield columns
BOARD_H             = 16        ; Playfield rows
BOARD_STRIDE        = 8         ; Bytes per row — two wasted, on purpose
BOARD_ROWS_ALLOC    = 20        ; 16 playfield + 2 floor sentinels + 2 reserved
BOARD_BYTES         = BOARD_ROWS_ALLOC * BOARD_STRIDE    ; 160
SPAWN_COL           = 2         ; 0-indexed, left of centre
MATCH_MIN           = 3         ; Run length that clears

; --- Tile encoding (SPEC 4) --------------------------------------------------
;   tile = COLOR_BASE + (color << 3) + glyph
;   The board byte IS the tile index. No translation on the way to the screen.
TILE_EMPTY          = $00
TILE_WALL           = $FF
COLOR_BASE          = $40
COLOR_MASK          = $F8       ; AND this and you have the colour key
GLYPH_MASK          = $07
WILD_BASE           = $70       ; Colour 6 — the prism
NUM_COLORS          = 6

COLOR_RED           = 0
COLOR_YELLOW        = 1
COLOR_GREEN         = 2
COLOR_CYAN          = 3
COLOR_BLUE          = 4
COLOR_PURPLE        = 5
COLOR_WILD          = 6

GLYPH_POTION        = 0
GLYPH_FIREBALL      = 1
GLYPH_BOLT          = 2
GLYPH_BOMB          = 3
GLYPH_STAR          = 4
GLYPH_GLOW          = 6         ; Match-flash frame

; --- Named tiles -------------------------------------------------------------
TILE_BLANK          = 0
TILE_BAR_H          = 1
TILE_BAR_V          = 2
TILE_COR_TL         = 3
TILE_COR_TR         = 4
TILE_COR_BL         = 5
TILE_COR_BR         = 6
TILE_JOINT          = 7
FONT_BASE           = 16        ; '0'..'9' then 'A'..'Z' then . x ! -
FONT_DIGIT_0        = 16
FONT_LETTER_A       = 26
VFX_SHATTER1        = 56
VFX_SHATTER2        = 57
VFX_BLAST           = 58
VFX_BEAM_H          = 59
VFX_BEAM_V          = 60
VFX_BEAM_CROSS      = 61
VFX_SPARKLE         = 62
TILE_STONE          = 120       ; Game-over petrify
TILE_RUBBLE         = 121
ART_BASE            = 128       ; Groups 16-31, margin artwork

; --- Panel geometry (SPEC 12) ------------------------------------------------
;   One 22 x 23 panel, rendered identically on all three machines. Each
;   platform supplies PANEL_X / PANEL_Y to centre it.
PANEL_W             = 22
PANEL_H             = 23

WELL_ORIGIN_X       = 1         ; Panel-relative: board (0,0) lives here
WELL_ORIGIN_Y       = 3

SCORE_X             = 9
SCORE_Y             = 4
HIGH_X              = 9
HIGH_Y              = 7
LEVEL_X             = 9
LEVEL_Y             = 10
NEXT_X              = 11        ; Single tile column
NEXT_Y              = 14        ; Cells A, B, C at NEXT_Y, +1, +2
MSG_X               = 0
MSG_Y               = 21        ; Two rows, full panel width

SCORE_DIGITS        = 6
LEVEL_DIGITS        = 2

; --- Levels (SPEC 10) --------------------------------------------------------
LEVEL_TILES         = 30        ; Tiles cleared per level
LEVEL_SPEED_CAP     = 16        ; Speed stops improving here
LEVEL_MAX_SHOWN     = 99

; --- Scoring (SPEC 9) --------------------------------------------------------
BONUS_FIREBALL      = $0500     ; BCD
BONUS_BOLT          = $0300
BONUS_BOMB          = $0300
BONUS_PRISM         = $0400
BONUS_LEVELUP       = $1000
STAR_SHIFT_CAP      = 3         ; Three doublings — x8
SCORE_BYTES         = 3         ; 6 digits packed BCD
HIGH_INIT_LO        = $00       ; 010000
HIGH_INIT_MID       = $00
HIGH_INIT_HI        = $01

; --- Reagent probability, out of 256 (SPEC 5.3) ------------------------------
PSPECIAL_BANDS      = 5

; --- Input bitmask (SPEC 11.1) -----------------------------------------------
;   Active HIGH. Each platform inverts and remaps its own hardware into this.
INPUT_UP            = %00000001 ; Rotate forward
INPUT_DOWN          = %00000010 ; Soft drop
INPUT_LEFT          = %00000100
INPUT_RIGHT         = %00001000
INPUT_FIRE          = %00010000 ; Rotate reverse / confirm
INPUT_PAUSE         = %00100000

; --- Game states (SPEC 13) ---------------------------------------------------
STATE_TITLE         = 0
STATE_PLAY          = 1
STATE_PAUSE         = 2
STATE_GAMEOVER      = 3

; --- Play sub-states (SPEC 8) ------------------------------------------------
PLAY_FALLING        = 0
PLAY_LOCKING        = 1
PLAY_GLOW           = 2
PLAY_SHATTER        = 3
PLAY_GRAVITY        = 4
PLAY_ARE            = 5

; --- Buffer sizes (SPEC 17.1) ------------------------------------------------
MARKS_BYTES         = 16        ; One byte per row, bits 0-5
EFFECTQ_ENTRIES     = 48        ; 2 bytes each; drop on overflow
EFFECTQ_BYTES       = EFFECTQ_ENTRIES * 2
DIRTY_ENTRIES       = 64        ; 3 bytes each: offset lo, offset hi, tile
DIRTY_BYTES         = DIRTY_ENTRIES * 3
DIRTY_FLUSH_MAX     = 48        ; Cells pushed to the screen per frame
