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
GLYPH_GLOW          = 6         ; Match-flash frame. Potion colours only —
                                ;   WILD_BASE + GLYPH_GLOW is an arrow, not a
                                ;   glow, so the prism never takes this path.
                                ;   See PRISM_BLIP below and SPEC 4.4.

; --- Named tiles -------------------------------------------------------------
TILE_BLANK          = 0
TILE_BAR_H          = 1
TILE_BAR_V          = 2
TILE_COR_TL         = 3
TILE_COR_TR         = 4
TILE_COR_BL         = 5
TILE_COR_BR         = 6
TILE_WASH           = 7         ; PAUSE / dim wash, white
FONT_BASE           = 16        ; '0'..'9' then 'A'..'Z' then . x ! ~
FONT_DIGIT_0        = 16
FONT_LETTER_A       = 26
FONT_DOT            = 52        ; A CENTRED dot, not a baseline period — it is
                                ;   also frame 0 of the removal ring below
FONT_TIMES          = 53
FONT_BANG           = 54
FONT_TILDE          = 55        ; The banner ornament, ~~~LIKE THIS~~~
TEXT_END            = $FF       ; String terminator. Shares its value with
                                ;   TILE_WALL, which costs nothing: no string
                                ;   ever contains tile 255.

; The removal ring (SPEC 14). One animation, used for every removal there is:
; the match shatter, the bomb blast, the star. It opens outward
;
;       FONT_DOT -> VFX_REMOVE1 -> VFX_REMOVE2 -> VFX_REMOVE3 -> empty
;
; and the prism's blip-out runs the same tiles closed inward (PRISM_BLIP).
VFX_REMOVE1         = 56
VFX_REMOVE2         = 57
VFX_REMOVE3         = 58
VFX_BEAM_H          = 59        ; The bolt's row
VFX_BEAM_V          = 60        ; The bolt's column
VFX_BEAM_CROSS      = 61        ; Drawn once, at the bolt's own cell
ARROW_UP            = 62        ; The title screen's controls (SPEC 13.1).
ARROW_DOWN          = 63        ;   Up and down live in group 7, left and
ARROW_LEFT          = 118       ;   right in group 14 — whichever white group
ARROW_RIGHT         = 119       ;   had a slot spare. Nothing indexes them.

; Group 14 is the prism's. Slots +0..+3 are its idle rotation and +4..+5 its
; blip-out; there is no glow slot (SPEC A.3).
PRISM_SPIN          = WILD_BASE ; Four frames, WILD_BASE + 0..3
PRISM_SPIN_FRAMES   = 4
PRISM_BLIP          = WILD_BASE + 4     ; Two frames, then VFX_REMOVE2,
                                        ;   VFX_REMOVE1, FONT_DOT, empty

; Group 15 is the stone group: the petrified glyph set at the same offsets the
; potions use, so a cell petrifies into its own shape —
;
;       petrified = PETRIFY_BASE + (tile & GLYPH_MASK)     for glyphs 0-4
;
; — and then the two tiles the margins are built from.
PETRIFY_BASE        = 120       ; +0 potion, +1 fireball, +2 bolt,
                                ;   +3 bomb, +4 star
TILE_RESERVED       = 125       ; Held for a sixth glyph, if one is ever added
TILE_SHELF          = 126       ; The shelf the panel stands on
TILE_BRICK          = 127       ; Brick — the margin fill
FRAME_DIM           = 8         ; Group 1 is group 0 byte for byte, one colour
                                ;   quieter, so frame_tile + FRAME_DIM is any
                                ;   frame piece's dim twin (SPEC A.3)
ART_BASE            = 128       ; Groups 16-31 — one hatch in sixteen colours,
                                ;   the title screen's magic field (SPEC 13.1)
ART_TILES           = 128

; --- Panel geometry (SPEC 12) ------------------------------------------------
;   One 22 x 24 panel, rendered identically on all three machines. PANEL_Y is
;   0 everywhere; only PANEL_X differs. The panel is vertically symmetric —
;   backdrop row, band row, backdrop row, eighteen rows of frame, backdrop row,
;   band row, backdrop row — which is why 24 is the height. The AC6502 is the
;   exact fit; the VIC-20 clips panel row 23 off the bottom and the C64 has one
;   spare screen row (24) below the panel. See SPEC 12.4.
PANEL_W             = 22
PANEL_H             = 24

WELL_ORIGIN_X       = 1         ; Panel-relative: board (0,0) lives here
WELL_ORIGIN_Y       = 4

SCORE_X             = 12        ; 7 digits, cols 12-18
SCORE_Y             = 5
HIGH_X              = 12        ; 7 digits, cols 12-18
HIGH_Y              = 10
HIGHLVL_X           = 15        ; Level the high score was set on, 2 digits;
                                ;   the 'L' at col 14 is in the static image
HIGHLVL_Y           = 11
LEVEL_X             = 18        ; Single column: tens above units
LEVEL_Y             = 17        ; Tens at LEVEL_Y, units at LEVEL_Y + 1
NEXT_X              = 11        ; Single tile column
NEXT_Y              = 16        ; Cells A, B, C at NEXT_Y, +1, +2
MSG_X               = 2         ; The band's OWNED cells. Panel columns 0-1 and
MSG_W               = 18        ;   20-21 of row 22 are shelf in the static
MSG_Y               = 22        ;   image and code never touches them; the
                                ;   banner still centres on the full PANEL_W,
                                ;   which lands in the same place for an
                                ;   even-length string (SPEC 12.2).

MSG_CHAIN_LEN       = 14        ; `~~ CHAIN x0 ~~` (strings.inc)
MSG_CHAIN_DIGIT     = 10        ; Where the digit sits inside it
CHAIN_DIGIT_X       = (PANEL_W - MSG_CHAIN_LEN) / 2 + MSG_CHAIN_DIGIT
                                ; TextBanner centres on PANEL_W, so the one
                                ;   cell the chain banner overwrites afterwards
                                ;   is worked out here rather than counted off
                                ;   the screen
CHAIN_MAX_SHOWN     = 9         ; One digit. A chain past 9 says 9 rather than
                                ;   drawing a glyph that is not a numeral

SCORE_DIGITS        = 7         ; Always all 7 drawn, zero padded
LEVEL_DIGITS        = 2         ; Always zero padded — level 5 draws "0" / "5"

; --- Piece and timing (SPEC 5.6, 11.3, 14) -----------------------------------
;   Every duration in the game is a frame count, and most of them differ
;   between NTSC and PAL so that wall-clock speed matches. Those live in
;   tables.inc as two-entry tables indexed by Region, not here — a constant
;   that is not one number is not a constant. The ones below are the same on
;   both machines.
LOCK_RESET_MAX      = 4         ; Horizontal moves that may reset the lock
                                ;   delay, per piece. Rotation never resets it.
FALL_FRAMES         = 2         ; Frames a row while the pile falls into the
                                ;   holes a clear left (SPEC 14). The one
                                ;   duration in the game that is the same on
                                ;   both regions, because SPEC 14 says so: at
                                ;   two frames there is nothing to round.

; --- Animation (SPEC 14) -----------------------------------------------------
;   A clear step animates in two windows, and everything SPEC 14 lists happens
;   inside one of them. A window lasts as long as the LONGEST thing in it:
;
;     GLOW      the matched cells' glow glyph, the bolt's beams and the
;               fireball's white flash. GlowFrames, or the longer FlashFrames
;               when a fireball fired (tables.inc)
;     SHATTER   the removal ring, and the prism's blip-out running alongside
;               it. SHATTER_STEPS ring frames, or BLIP_STEPS when a marked
;               prism is winking out with them
;
;   The two counts below are the SAME on both regions, for the reason
;   FALL_FRAMES is: they are a tile count times VFX_FRAMES, and two frames a
;   tile does not round to 1.67. SPEC 14 says so.
VFX_FRAMES          = 2         ; Frames each tile of a removal ring holds
SHATTER_STEPS       = 3         ; VFX_REMOVE1..3           — 6 frames
BLIP_STEPS          = 5         ; PRISM_BLIP, +1, VFX_REMOVE2, VFX_REMOVE1,
                                ;   FONT_DOT               — 10 frames
PRISM_SPIN_RATE     = 8         ; Frames per idle rotation frame (SPEC 14).
                                ;   The only tile on the board that moves when
                                ;   nothing is happening
PETRIFY_FRAMES      = 2         ; Frames per row of the game-over petrify
                                ;   (SPEC 13.4). Same number as FALL_FRAMES
                                ;   and not the same thing, so it is its own
                                ;   constant
TINT_NONE           = $01       ; TintColor when nothing is flashing white.
                                ;   Every real colour key has its low three
                                ;   bits clear, so $01 is a value no masked
                                ;   tile can equal — which is what lets the
                                ;   Commodores' HalPlotCell test the tint with
                                ;   one CMP and no separate "is anything
                                ;   flashing at all" branch (SPEC 4.6)

; --- The title screen (SPEC 13.1) --------------------------------------------
;   Panel-relative, and every one of them is a measurement off the drawn
;   screen rather than a choice: `make artwork` owns data/screen-title-*.bin
;   and the numbers below have to agree with it. The magic field is the block
;   of hatch tiles at rows 8-9 and the prompt is the ten cells that say
;   PRESS FIRE, which is the one string code redraws over its own image.
FIELD_X             = 4         ; The magic field, 14 x 2 (SPEC 13.1)
FIELD_Y             = 8
FIELD_W             = 14
FIELD_CELLS         = FIELD_W * 2       ; 28, and one of them changes a frame
PROMPT_X            = 6         ; `PRESS FIRE`, blinked at SPEC 14's period
PROMPT_Y            = 11
PROMPT_LEN          = 10

; --- Game over (SPEC 13.4) ---------------------------------------------------
GAMEOVER_SECS       = 10        ; Seconds on the game-over screen before it
                                ;   returns to the title by itself. SECONDS,
                                ;   not frames: 600 does not fit in a byte and
                                ;   would not be the same wall clock on both
                                ;   regions if it did, so the timeout counts
                                ;   seconds and SecondFrames counts the frames
                                ;   of one (tables.inc)

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
HIGH_FLASH_BLINKS   = 6         ; Half-blinks of the HIGH field when the score
                                ;   overtakes it (SPEC 9.8) — three dark, three
                                ;   lit, ending lit. At SPEC 14's 30-frame
                                ;   blink period that is about a second and a
                                ;   half, and play never stops for it.
SCORE_BYTES         = 4         ; 8 nibbles packed BCD; the top one stays 0,
                                ;   so 7 digits show and the score wraps at
                                ;   10,000,000.
HIGH_INIT_LO        = $00       ; 0010000
HIGH_INIT_MID       = $00
HIGH_INIT_HI        = $01
HIGH_INIT_TOP       = $00

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
INPUT_MASK          = %00111111 ; Everything the game reads. Bits 6-7 are free
                                ;   for a platform to use as scratch inside
                                ;   HalReadInput, as long as it strips them.

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
EFFECTQ_ENTRIES     = 48        ; ONE byte each — the board index of a pending
EFFECTQ_BYTES       = EFFECTQ_ENTRIES   ;   detonation, and nothing else.
                                ;   SPEC 8 budgeted two bytes for a packed
                                ;   glyph/row/column, which is a copy of what
                                ;   the board already holds: cells are not
                                ;   zeroed until step 6 and the queue is drained
                                ;   in step 4, so the tile is still there when
                                ;   the effect pops and its glyph and colour are
                                ;   one `lda Board,x` away. Half the RAM for
                                ;   nothing (SPEC 17.1).
                                ;   A ring keeps one slot free, so 47 pending
                                ;   detonations. On overflow an effect is
                                ;   dropped rather than growing the buffer (D6);
                                ;   at one reagent a piece it is not reachable.
DIRTY_ENTRIES       = 64        ; 3 bytes each: offset lo, offset hi, tile
DIRTY_BYTES         = DIRTY_ENTRIES * 3
DIRTY_FLUSH_MAX     = 24        ; Cells pushed to the screen per frame.
                                ;   MEASURED, not estimated (PLAN.md S1). A
                                ;   flush costs 165 cycles a cell on the
                                ;   AC6502 and about 132 on the Commodores, so
                                ;   24 cells is 3965 cycles — inside vertical
                                ;   blank on all three, and tightest on the
                                ;   AC6502 at 1 MHz, whose 70 blank lines are
                                ;   roughly 4450. It is also a quarter of the
                                ;   96-cell well, so a full redraw is exactly
                                ;   four frames.
                                ;   Overrunning vblank is not dangerous on any
                                ;   of the three — no VRAM write spacing is
                                ;   anywhere near violated (S1) — it only
                                ;   risks a cell landing a frame late. This is
                                ;   a budget, not a hardware limit.
