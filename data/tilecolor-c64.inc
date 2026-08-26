; =============================================================================
;   tilecolor-c64.inc — C64 tile -> colour RAM table
; =============================================================================
;   Generated from SPEC.md section 4.3 and Appendix A. Spec-derived data, not
;   artwork: edit this file by hand, it is never overwritten by an editor
;   export. Tile groups 16-31 (tiles 128-255) are the margin artwork and their
;   colours are the artist's to choose.
; =============================================================================


;   256 bytes, indexed by tile number. Render is:
;       SCREEN,x = tile   /   COLRAM,x = TileColor,tile
;   C64: all 16 colours available. Groups 0-15 match the VIC-20
;   table except where the VIC has no equivalent (gray).

TileColorC64:
  .res 8, $01                      ; tiles   0-7    group 0  UI / well frame        white
  .res 8, $0F                      ; tiles   8-15   group 1  UI accents             gray
  .res 8, $01                      ; tiles  16-23   group 2  Font  0 1 2 3 4 5 6 7  white
  .res 8, $01                      ; tiles  24-31   group 3  Font  8 9 A B C D E F  white
  .res 8, $01                      ; tiles  32-39   group 4  Font  G H I J K L M N  white
  .res 8, $01                      ; tiles  40-47   group 5  Font  O P Q R S T U V  white
  .res 8, $01                      ; tiles  48-55   group 6  Font  W X Y Z . x ! -  white
  .res 8, $01                      ; tiles  56-63   group 7  VFX                    white
  .res 8, $02                      ; tiles  64-71   group 8  POTION 0  RED
  .res 8, $07                      ; tiles  72-79   group 9  POTION 1  YELLOW
  .res 8, $05                      ; tiles  80-87   group 10 POTION 2  GREEN
  .res 8, $03                      ; tiles  88-95   group 11 POTION 3  CYAN
  .res 8, $06                      ; tiles  96-103  group 12 POTION 4  BLUE
  .res 8, $04                      ; tiles 104-111  group 13 POTION 5  PURPLE
  .res 8, $01                      ; tiles 112-119  group 14 POTION 6  WILD / prism white
  .res 8, $02                      ; tiles 120-127  group 15 Wall / stone           red
  .res 8, $0F                      ; tiles 128-135  group 16 artwork
  .res 8, $09                      ; tiles 136-143  group 17 artwork
  .res 8, $0C                      ; tiles 144-151  group 18 artwork
  .res 8, $08                      ; tiles 152-159  group 19 artwork
  .res 8, $0B                      ; tiles 160-167  group 20 artwork
  .res 8, $0D                      ; tiles 168-175  group 21 artwork
  .res 8, $0A                      ; tiles 176-183  group 22 artwork
  .res 8, $03                      ; tiles 184-191  group 23 artwork
  .res 8, $07                      ; tiles 192-199  group 24 artwork
  .res 8, $0E                      ; tiles 200-207  group 25 artwork
  .res 8, $04                      ; tiles 208-215  group 26 artwork
  .res 8, $05                      ; tiles 216-223  group 27 artwork
  .res 8, $02                      ; tiles 224-231  group 28 artwork
  .res 8, $01                      ; tiles 232-239  group 29 artwork
  .res 8, $0F                      ; tiles 240-247  group 30 artwork
  .res 8, $01                      ; tiles 248-255  group 31 artwork
