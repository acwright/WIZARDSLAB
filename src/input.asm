; =============================================================================
;   input.asm — Wizards Lab, input conditioning
; =============================================================================
;   SPEC.md section 11. HalReadInput hands back one active-high mask however
;   the platform likes; everything above this line works on that mask and
;   never touches hardware.
;
;   Auto-repeat applies to LEFT and RIGHT only. Rotate does NOT repeat — up
;   must be released and pressed again. That is not a preference: a repeating
;   rotate makes a three-cell Columns piece impossible to aim.
; =============================================================================

; -----------------------------------------------------------------------------
;   InputPoll — read the hardware and work out what is newly pressed
;   In:  nothing
;   Out: InputNow, InputPrev, InputEdge updated.  Modifies: A
; -----------------------------------------------------------------------------
InputPoll:
  lda InputNow
  sta InputPrev
  jsr HalReadInput
  sta InputNow
  eor InputPrev                 ; Bits that changed
  and InputNow                  ; ...and are now down = newly pressed
  sta InputEdge
  rts

; -----------------------------------------------------------------------------
;   InputShift — LEFT/RIGHT with delayed auto shift
;   Out: A = INPUT_LEFT, INPUT_RIGHT, or 0 if no move should happen this frame.
;        Modifies: A, X
;   SPEC 11.3 — initial delay 12 frames NTSC / 10 PAL, then 4 / 3.
;
;   A fresh press fires on the same frame it arrives; the delay is what comes
;   after it, not before it, so a tap is always exactly one column.
;
;   Holding both directions at once is not something a stick can do, but two
;   keys can. LEFT wins, and it wins consistently, so the piece sits still
;   rather than shivering between the two.
; -----------------------------------------------------------------------------
InputShift:
  lda InputNow
  and #INPUT_LEFT
  bne @Dir
  lda InputNow
  and #INPUT_RIGHT
  beq @None

@Dir:
  cmp DasDir
  beq @Held

  sta DasDir                    ; A new direction: fire now, then wait
  ldx Region
  lda DasInitial,x
  sta DasTimer
  lda DasDir
  rts

@Held:
  dec DasTimer                  ; Always loaded non-zero, so this cannot wrap
  bne @Wait
  ldx Region
  lda DasRepeat,x
  sta DasTimer
  lda DasDir
  rts

@Wait:
  lda #0
  rts

@None:
  sta DasDir                    ; A is already 0 — release, so the next press
  rts                           ;   counts as fresh
