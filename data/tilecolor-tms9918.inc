; =============================================================================
;   tilecolor-tms9918.inc — TMS9918 Graphics I colour table
; =============================================================================
;   Generated from SPEC.md section 4.3 and Appendix A. Spec-derived data, not
;   artwork: edit this file by hand, it is never overwritten by an editor
;   export. Tile groups 16-31 (tiles 128-255) are the margin artwork and their
;   colours are the artist's to choose.
; =============================================================================


;   32 bytes -> VDP colour table. Each byte is (foreground << 4) | background;
;   background is 1 (black) throughout, matching the backdrop register.

TileColorTMS:
  .byte $F1                        ; group 0  tiles   0-7    UI / well frame        white
  .byte $E1                        ; group 1  tiles   8-15   UI accents             gray
  .byte $F1                        ; group 2  tiles  16-23   Font  0 1 2 3 4 5 6 7  white
  .byte $F1                        ; group 3  tiles  24-31   Font  8 9 A B C D E F  white
  .byte $F1                        ; group 4  tiles  32-39   Font  G H I J K L M N  white
  .byte $F1                        ; group 5  tiles  40-47   Font  O P Q R S T U V  white
  .byte $F1                        ; group 6  tiles  48-55   Font  W X Y Z . x ! -  white
  .byte $F1                        ; group 7  tiles  56-63   VFX                    white
  .byte $81                        ; group 8  tiles  64-71   POTION 0  RED
  .byte $B1                        ; group 9  tiles  72-79   POTION 1  YELLOW
  .byte $31                        ; group 10 tiles  80-87   POTION 2  GREEN
  .byte $71                        ; group 11 tiles  88-95   POTION 3  CYAN
  .byte $51                        ; group 12 tiles  96-103  POTION 4  BLUE
  .byte $D1                        ; group 13 tiles 104-111  POTION 5  PURPLE
  .byte $F1                        ; group 14 tiles 112-119  POTION 6  WILD / prism white
  .byte $E1                        ; group 15 tiles 120-127  Stone / rubble         gray
  .byte $E1                        ; group 16 tiles 128-135  artwork
  .byte $61                        ; group 17 tiles 136-143  artwork
  .byte $C1                        ; group 18 tiles 144-151  artwork
  .byte $A1                        ; group 19 tiles 152-159  artwork
  .byte $41                        ; group 20 tiles 160-167  artwork
  .byte $21                        ; group 21 tiles 168-175  artwork
  .byte $91                        ; group 22 tiles 176-183  artwork
  .byte $71                        ; group 23 tiles 184-191  artwork
  .byte $B1                        ; group 24 tiles 192-199  artwork
  .byte $51                        ; group 25 tiles 200-207  artwork
  .byte $D1                        ; group 26 tiles 208-215  artwork
  .byte $31                        ; group 27 tiles 216-223  artwork
  .byte $81                        ; group 28 tiles 224-231  artwork
  .byte $F1                        ; group 29 tiles 232-239  artwork
  .byte $E1                        ; group 30 tiles 240-247  artwork
  .byte $F1                        ; group 31 tiles 248-255  artwork
