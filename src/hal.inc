; =============================================================================
;   hal.inc — Wizards Lab, the platform contract
; =============================================================================
;   Everything in src/ is shared, unmodified, by all three machines. The only
;   things that differ are collected here: each platform's WizardsLab.asm must
;   define these constants and implement these seven routines, and nothing
;   else in src/ may touch hardware directly.
;
;   This file declares nothing. It is the documentation for the boundary, kept
;   next to the code it constrains so it cannot drift out of date unnoticed.
;
;   CONSTANTS the platform must define BEFORE including the shared sources
;   ---------------------------------------------------------------------
;     PANEL_X, PANEL_Y      Where the 22 x 23 panel sits on this screen.
;                             AC6502  5, 0      VIC-20  0, 0      C64  9, 1
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
;                       per-cell colour.
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
;     HalSfx            Start a sound effect. May be a bare RTS until audio
;                       exists.
;                       In:  A = effect id (SPEC 16)
;                       Out: nothing
;
;   The shared code assumes nothing about interrupts. Each platform may drive
;   HalWaitFrame from a raster IRQ, a timer, or a status-register poll.
; =============================================================================
