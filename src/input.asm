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
;   SPEC 11.3 — initial delay 12 frames NTSC / 10 PAL, then 4 / 3.
; -----------------------------------------------------------------------------
InputShift:
  ; TODO: on a fresh press, fire immediately and load DasTimer with the
  ; initial delay; while held, fire again each time DasTimer runs out and
  ; reload it with the repeat rate; on release, clear DasDir.
  lda #0
  rts
