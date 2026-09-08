; =============================================================================
;   hal.inc — Wizards Lab, the platform contract
; =============================================================================
;   Everything in src/ is shared, unmodified, by all three machines. The only
;   things that differ are collected here: each platform's WizardsLab.asm must
;   define these constants and implement these eight routines, and nothing
;   else in src/ may touch hardware directly.
;
;   This file declares nothing. It is the documentation for the boundary, kept
;   next to the code it constrains so it cannot drift out of date unnoticed.
;
;   CONSTANTS the platform must define BEFORE including the shared sources
;   ---------------------------------------------------------------------
;     PANEL_X, PANEL_Y      Where the 22 x 24 panel sits on this screen.
;                             AC6502  5, 0      VIC-20  0, 0      C64  9, 0
;                           PANEL_Y is 0 everywhere; the VIC-20 clips panel
;                           row 23 and the C64 has one spare row below it.
;     SCR_COLS           32 / 22 / 40
;     SCR_ROWS           24 / 23 / 25
;     HAS_COLOR_RAM         1 on the Commodores, 0 on the AC6502, whose colour
;                           lives in the VDP colour table instead.
;
;   ROUTINES the platform must implement
;   ------------------------------------
;     HalInitVideo      Bring up the video hardware: black background and
;                       border, the correct text/tile mode, tileset in place,
;                       colours configured, screen cleared. Called once.
;                       In:  nothing        Out: nothing
;
;     HalWaitFrame      Block until the start of the next vertical blank.
;                       Everything below is called only between frames.
;                       In:  nothing        Out: nothing
;
;     HalPlotCell       Write one cell, colour included where the platform has
;                       per-cell colour — white instead, for any tile whose
;                       colour key is TintColor (see HalColorFlash).
;                       In:  A = tile, X = screen column, Y = screen row
;                       Out: nothing.  Modifies: A, X, Y, Ptr1, Ptr2
;
;     HalBlitScreen     Draw a whole static screen from a name-table image in
;                       ROM: SCR_COLS * SCR_ROWS bytes, row-major, plus
;                       the matching colour image where the platform needs one.
;                       In:  SrcPtr -> name table, Ptr1 -> colour table
;                       Out: nothing
;
;     HalReadInput      Read stick and keyboard, fold both into one mask.
;                       In:  nothing
;                       Out: A = INPUT_* bits, ACTIVE HIGH
;
;     HalDetectRegion   Decide NTSC or PAL so the timing tables can be picked.
;                       In:  nothing        Out: A = 0 NTSC, 1 PAL
;
;     HalColorFlash     Draw every tile of one colour white, or stop doing so.
;                       The fireball's detonation (SPEC 4.6, 14).
;                       In:  A = colour key ($40..$68), or TINT_NONE for none
;                       Out: nothing.  Modifies: A, X, Y, and TintColor, which
;                            it OWNS: nothing else may write that byte.
;                       The platform must handle the transition, not just the
;                       new value — a second call with a different colour puts
;                       the first one back before lighting the second.
;                       On the AC6502 this is ONE byte in the VDP colour table,
;                       because a tile's colour there belongs to its 8-pattern
;                       group and not to the cell. On the Commodores colour is
;                       per cell, so HalPlotCell reads TintColor instead and
;                       substitutes white for any tile of that colour as it
;                       draws it — which also means every tinted cell has to be
;                       re-marked, and the animation is already marking all of
;                       them (anim.asm).
;
;     HalSfx            Sound ONE note, in one timbre, until told otherwise.
;                       In:  A = TIMBRE_* (constants.inc), X = note in
;                            semitones above C3, 0..NOTE_MAX. TIMBRE_OFF ends
;                            whatever is sounding and ignores X.
;                       Out: nothing.  Modifies: A, X, Y, Tmp0-Tmp2
;                       This is NOT "play effect 4". Which effect is playing,
;                       which step of it, how long the step lasts and what
;                       note it is are all shared code (audio.asm), because
;                       none of that differs between a SID and a VIC-I; what
;                       does differ is the register values one note comes out
;                       as, and that is the whole of this routine. SPEC 16
;                       expected the split one level lower — a SID driver
;                       shared by two machines and a third written twice —
;                       and this is the same code shared by three (D22).
;                       A timbre is a voice AND an octave: SOFT sounds an
;                       octave below the note it is given, BUZZ at it, BRIGHT
;                       an octave above. On a SID that is a waveform and a
;                       shift; on the VIC-I the three tone oscillators are
;                       already an octave apart, so it is free.
;                       A machine with no sound card must still return: the
;                       AC6502's is optional hardware and the game plays
;                       silently on one that has none.
;
;   The shared code assumes nothing about interrupts. Each platform may drive
;   HalWaitFrame from a raster IRQ, a timer, or a status-register poll.
; =============================================================================
