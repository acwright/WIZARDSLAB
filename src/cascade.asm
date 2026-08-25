; =============================================================================
;   cascade.asm — Wizards Lab, clear resolution
; =============================================================================
;   SPEC.md section 8. A cascade runs from the moment a piece locks until no
;   further matches exist, one step per iteration, with ChainStep counting the
;   steps. The step order is fixed:
;
;       scan -> score matches -> enqueue reagents -> resolve queue
;            -> animate -> remove -> level check -> gravity -> repeat
;
;   The effect queue always drains. Effects only ever remove tiles, never add
;   them, and each cell can be marked at most once, so the queue is bounded by
;   the 96 cells of the playfield.
; =============================================================================

; -----------------------------------------------------------------------------
;   CascadeBegin — called immediately after PieceLock
; -----------------------------------------------------------------------------
CascadeBegin:
  ; TODO: ChainStep = 1, Cascade* = 0, StarCount = 0.
  rts

; -----------------------------------------------------------------------------
;   CascadeStep — advance one step
;   Out: C clear when the cascade has settled and CascadeSettle should run.
; -----------------------------------------------------------------------------
CascadeStep:
  clc
  rts

; -----------------------------------------------------------------------------
;   CascadeSettle — apply the star multiplier and bank the points
;   SPEC 8 SETTLE, SPEC 9.6 — the doubling covers the WHOLE cascade, including
;   points scored before the star cleared.
; -----------------------------------------------------------------------------
CascadeSettle:
  ; TODO: shift CascadeLo/Mid/Hi left by min(StarCount, STAR_SHIFT_CAP) in BCD
  ; (a BCD doubling is one self-addition), then ScoreAdd.
  rts

; -----------------------------------------------------------------------------
;   The five reagents (SPEC 7.3). Each marks its targets, scores them at
;   EffectValue[chain], and pushes any reagent it uncovers back onto the queue.
; -----------------------------------------------------------------------------
EffectFireball:                   ; In: A = colour key. Every tile of it, board wide.
  rts                             ;     Prisms are immune — they have no colour.

EffectBolt:                       ; In: X = row, Y = column. Row + column, <= 21 cells.
  rts

EffectBomb:                       ; In: X = row, Y = column. 3x3, clipped at the edges.
  rts

EffectStar:                       ; Removes nothing; StarCount += 1, capped later.
  rts

EffectPrism:                      ; Removes nothing; awards BONUS_PRISM.
  rts

; -----------------------------------------------------------------------------
;   The effect queue — a ring of (glyph, row, col) packed into two bytes.
;   On overflow an effect is dropped rather than growing the buffer; with at
;   most one reagent per piece, EFFECTQ_ENTRIES is not reachable in practice.
; -----------------------------------------------------------------------------
EffectQClear:
  rts

EffectQPush:                      ; In: A = glyph, X = row, Y = column
  rts

EffectQPop:                       ; Out: C clear if empty
  clc
  rts
