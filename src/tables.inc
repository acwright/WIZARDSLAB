; =============================================================================
;   tables.inc — Wizards Lab, spec-derived lookup tables
; =============================================================================
;   Straight out of SPEC.md sections 5.3, 9, 10, 14 and 16. Hand-authored,
;   never overwritten by an editor export. Included once, from the RODATA
;   segment.
;
;   Score values above 99 do not fit in a byte, so every scoring table is a
;   pair of parallel arrays — low BCD byte and high BCD byte — indexed by the
;   same value.
; =============================================================================

; --- Gravity, frames per row (SPEC 10.2) -------------------------------------
;   Indexed by (level - 1), clamped to LEVEL_SPEED_CAP - 1.
;   PAL is round(NTSC * 50/60), so wall-clock speed matches across regions.

SpeedNTSC:
  .byte  48, 43, 38, 34, 30, 26, 23, 20   ; levels  1- 8   0.800s .. 0.333s
  .byte  17, 15, 13, 11,  9,  8,  7,  6   ; levels  9-16   0.283s .. 0.100s

SpeedPAL:
  .byte  40, 36, 32, 28, 25, 22, 19, 17   ; levels  1- 8   0.800s .. 0.340s
  .byte  14, 13, 11,  9,  8,  7,  6,  5   ; levels  9-16   0.280s .. 0.100s

; --- Frame counts that differ by region (SPEC 5.6, 11.3, 14) -----------------
;   Indexed by Region: 0 = NTSC, 1 = PAL. PAL is round(NTSC * 50/60) wherever
;   the difference is worth a frame, so a piece takes the same number of
;   SECONDS to lock on both machines rather than the same number of frames.
;
;   Two bytes each rather than one table of pairs, because every read is
;   `ldx Region / lda Name,x` and a pair table would need the index doubled.

LockDelay:                              ; SPEC 5.6
  .byte 16, 14
AreDelay:                               ; Entry delay after a cascade settles
  .byte 12, 10
DasInitial:                             ; SPEC 11.3 — first repeat
  .byte 12, 10
DasRepeat:                              ; ...and every one after it
  .byte  4,  3
SoftDropRate:                           ; Frames per row while DOWN is held.
  .byte  3,  2                          ;   Never used when gravity is faster.
BlinkHalf:                              ; SPEC 14 — half of the 30 / 25 frame
  .byte 15, 13                          ;   blink period, which is what a
                                        ;   blinking field actually counts
GlowFrames:                             ; SPEC 14 — the GLOW window: the match
  .byte  6,  5                          ;   glow and the bolt's beams
FlashFrames:                            ; ...and what the window grows to when
  .byte  8,  7                          ;   a fireball fired, because its flash
                                        ;   is the longer of the two and both
                                        ;   are showing at once (constants.inc)
BannerFrames:                           ; SPEC 14 — how long LEVEL UP and
  .byte 45, 38                          ;   CHAIN xN stay in the message band
SecondFrames:                           ; One second, which is the unit the
  .byte 60, 50                          ;   game-over timeout is counted in
                                        ;   (SPEC 13.4). The only entry here
                                        ;   that is not a duration out of
                                        ;   SPEC 14 but the frame rate itself

; --- The two removal animations (SPEC 14, Appendix A.3) ----------------------
;   One ring, run in both directions. Indexed by AnimStep, which advances every
;   VFX_FRAMES frames.
;
;   Potions, reagents, the bomb blast and the star all open OUTWARD and are
;   gone in SHATTER_STEPS frames; the fourth entry only ever comes up when a
;   marked prism is blipping out beside them and holding the window open, and
;   it blanks the cell rather than leaving the last ring frame sitting there
;   for four more frames.

VfxShatter:
  .byte VFX_REMOVE1, VFX_REMOVE2, VFX_REMOVE3, TILE_EMPTY

;   The prism closes INWARD, and does not pass through the glow (SPEC A.3 —
;   group 14 has no glyph +6). Five frames, so a step that clears one runs
;   BLIP_STEPS rather than SHATTER_STEPS.

VfxBlip:
  .byte PRISM_BLIP, PRISM_BLIP + 1, VFX_REMOVE2, VFX_REMOVE1, FONT_DOT

; --- Per-tile value for MATCH removals (SPEC 9.1) ----------------------------
;   Indexed by (chain - 1), clamped to 7.   20 50 100 200 300 400 500 600
TileValueLo:
  .byte $20, $50, $00, $00, $00, $00, $00, $00
TileValueHi:
  .byte $00, $00, $01, $02, $03, $04, $05, $06

; --- Per-tile value for EFFECT removals (SPEC 9.2) ---------------------------
;   Indexed by (chain - 1), clamped to 7.   30 60 120 240 350 450 550 650
EffectValueLo:
  .byte $30, $60, $20, $40, $50, $50, $50, $50
EffectValueHi:
  .byte $00, $00, $01, $02, $03, $04, $05, $06

; --- Run length bonus (SPEC 9.3) ---------------------------------------------
;   Indexed by (length - 3), clamped to 4.  0 100 300 600 1000
LengthBonusLo:
  .byte $00, $00, $00, $00, $00
LengthBonusHi:
  .byte $00, $01, $03, $06, $10

; --- Simultaneous run bonus (SPEC 9.4) ---------------------------------------
;   Indexed by (runs - 1), clamped to 4.    0 200 500 1000 2000
MultiBonusLo:
  .byte $00, $00, $00, $00, $00
MultiBonusHi:
  .byte $00, $02, $05, $10, $20

; --- Level -> reagent probability band (SPEC 5.3) ----------------------------
;   Indexed by (level - 1), clamped to 15. Bands are 1-3, 4-6, 7-9, 10-12, 13+.
LevelBand:
  .byte 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4

; --- Chance a piece carries a reagent, out of 256 (SPEC 5.3) -----------------
;   Indexed by band.                        15%  22%  27%  32%  36%
PSpecial:
  .byte  38,  56,  69,  82,  92

; --- Reagent type, cumulative thresholds out of 256 (SPEC 5.3) ---------------
;   Four thresholds per band; a roll at or above the last one is a Prism.
;       roll <  [0] -> Fireball
;       roll <  [1] -> Bolt
;       roll <  [2] -> Bomb
;       roll <  [3] -> Star
;       else        -> Prism
ReagentThresholds:
  .byte  77, 138, 195, 236             ; band 0   levels  1-3
  .byte  77, 141, 192, 238             ; band 1   levels  4-6
  .byte  82, 146, 197, 238             ; band 2   levels  7-9
  .byte  79, 141, 195, 238             ; band 3   levels 10-12
  .byte  79, 143, 199, 240             ; band 4   levels 13+

; --- Reagent trigger bonuses, indexed by glyph (SPEC 9.5) --------------------
;   Glyph 0 potion and 4 star award nothing here (the star multiplies instead).
TriggerBonusLo:
  .byte $00, $00, $00, $00, $00, $00, $00, $00
TriggerBonusHi:
  .byte $00, $05, $03, $03, $00, $00, $00, $00

; --- The twelve sound effects (SPEC 16) --------------------------------------
;   An effect is a list of STEPS and a step is three bytes: how many FRAMES it
;   lasts, its TIMBRE, and its NOTE in semitones above C3 (constants.inc). A
;   zero frame count ends the list. Nothing here is a register value: a note
;   means the same pitch on both sound chips and each platform turns it into
;   whatever its own hardware wants (audio.asm, hal.inc).
;
;   SPEC 16 gives each effect a CHARACTER and not a tune — "short blip",
;   "dull thunk", "descending noise sweep" — and the notes below are the
;   reading of it. What is not a choice is the range: the VIC-I's oscillator
;   value runs out of resolution above C5, where consecutive semitones start
;   landing on the same number, so everything melodic is WRITTEN inside C3-C5
;   and lifted by its timbre instead. TIMBRE_BRIGHT is already an octave up.
;
;   SfxStepIdx is a byte offset into SfxSteps, so this table has to stay under
;   256 bytes. It is 196 — 144 for SPEC 16's twelve, 25 for the thirteenth that
;   starts a game, and 27 for the three at the bottom that belong to the title
;   screen's ambience rather than to the game (constants.inc, ambience.asm).

SfxOffsets:                             ; Indexed by (SFX_* id - 1)
  .byte SfxMove     - SfxSteps
  .byte SfxRotate   - SfxSteps
  .byte SfxLock     - SfxSteps
  .byte SfxMatch    - SfxSteps
  .byte SfxFireball - SfxSteps
  .byte SfxBolt     - SfxSteps
  .byte SfxBomb     - SfxSteps
  .byte SfxStar     - SfxSteps
  .byte SfxPrism    - SfxSteps
  .byte SfxLevelUp  - SfxSteps
  .byte SfxHighScore- SfxSteps
  .byte SfxGameOver - SfxSteps
  .byte SfxStart    - SfxSteps          ; 13 is an event SPEC 16 does not have
  .byte SfxBubble   - SfxSteps          ; 14-16 are the title screen's, and are
  .byte SfxGloop    - SfxSteps          ;   not events — see the ambience at the
  .byte SfxSeethe   - SfxSteps          ;   bottom of this file

SfxSteps:

SfxMove:                                ; 1 — short blip                2 frames
  .byte  2, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte  0

SfxRotate:                              ; 2 — rising two-step           6 frames
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_C
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte  0

SfxLock:                                ; 3 — dull thunk                6 frames
  .byte  2, TIMBRE_NOISE,  OCT_4 + SEMI_C
  .byte  4, TIMBRE_SOFT,   OCT_4 + SEMI_C
  .byte  0

SfxMatch:                               ; 4 — bright chime              9 frames
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_C   ; ...and the whole thing is
  .byte  6, TIMBRE_BRIGHT, OCT_4 + SEMI_E   ;   transposed up by the chain
  .byte  0                                  ;   (SPEC 16, audio.asm)

SfxFireball:                            ; 5 — descending noise sweep   10 frames
  .byte  2, TIMBRE_NOISE,  OCT_6 + SEMI_C
  .byte  2, TIMBRE_NOISE,  OCT_5 + SEMI_G
  .byte  2, TIMBRE_NOISE,  OCT_5 + SEMI_D
  .byte  2, TIMBRE_NOISE,  OCT_4 + SEMI_A
  .byte  2, TIMBRE_NOISE,  OCT_4 + SEMI_E
  .byte  0

SfxBolt:                                ; 6 — fast noise crack          3 frames
  .byte  3, TIMBRE_NOISE,  OCT_5 + SEMI_A
  .byte  0

SfxBomb:                                ; 7 — low noise thump          10 frames
  .byte  2, TIMBRE_NOISE,  OCT_4 + SEMI_D
  .byte  8, TIMBRE_NOISE,  OCT_3 + SEMI_E
  .byte  0

SfxStar:                                ; 8 — sparkle arpeggio          8 frames
  .byte  2, TIMBRE_BRIGHT, OCT_4 + SEMI_C
  .byte  2, TIMBRE_BRIGHT, OCT_4 + SEMI_E
  .byte  2, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte  2, TIMBRE_BRIGHT, OCT_5 + SEMI_C
  .byte  0

SfxPrism:                               ; 9 — shimmer                  12 frames
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_C   ; The one effect that wants an edge
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_E   ;   to it rather than a bell: a
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_C   ;   sawtooth beating between two
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_E   ;   notes six times in a fifth of
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_C   ;   a second
  .byte  2, TIMBRE_BUZZ,   OCT_5 + SEMI_E
  .byte  0

SfxLevelUp:                             ; 10 — fanfare                 25 frames
  .byte  5, TIMBRE_BRIGHT, OCT_4 + SEMI_C
  .byte  5, TIMBRE_BRIGHT, OCT_4 + SEMI_E
  .byte  5, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte 10, TIMBRE_BRIGHT, OCT_5 + SEMI_C
  .byte  0

SfxHighScore:                           ; 11 — longer fanfare          40 frames
  .byte  4, TIMBRE_BRIGHT, OCT_4 + SEMI_C
  .byte  4, TIMBRE_BRIGHT, OCT_4 + SEMI_E
  .byte  4, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte  4, TIMBRE_BRIGHT, OCT_5 + SEMI_C
  .byte  4, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte  4, TIMBRE_BRIGHT, OCT_5 + SEMI_C
  .byte 16, TIMBRE_BRIGHT, OCT_5 + SEMI_E
  .byte  0

SfxGameOver:                            ; 12 — descending minor run    58 frames
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_A
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_G
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_F
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_E
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_D
  .byte  6, TIMBRE_SOFT,   OCT_4 + SEMI_C
  .byte  6, TIMBRE_SOFT,   OCT_3 + SEMI_B
  .byte 16, TIMBRE_SOFT,   OCT_3 + SEMI_A
  .byte  0

; --- ...and the thirteenth, which is that one backwards ----------------------
;   The game announcing itself (constants.inc). SPEC 16 has no such effect and
;   the game had no sound at all for the transition that matters most: the
;   screen changes, a piece is already falling, and nothing says so.
;
;   It is the GAME-OVER RUN CLIMBED — the same eight notes of A minor in the
;   other order, so the game opens with the phrase that will close it, played
;   backwards. Two things about it are not mirrored, and both are the point:
;
;     BRIGHT, not SOFT. A timbre is a voice and an octave (constants.inc), so
;     the same written notes come out two octaves above the game-over run
;     rather than beside it. The contour is the quotation; the colour is what
;     says which end of the game you are at.
;
;     THREE FRAMES A STEP, not six. A loss is allowed to take its time because
;     nothing is happening afterwards. A start is not: the first piece is
;     already falling while this plays, and 33 frames is about as long as a
;     sound can hold the top of a screen the player has started using.
;
;   A scale and not an arpeggio, which is what keeps it clear of the two
;   fanfares above — those leap, this walks.

SfxStart:                               ; 13 — the run, climbed       33 frames
  .byte  3, TIMBRE_BRIGHT, OCT_3 + SEMI_A
  .byte  3, TIMBRE_BRIGHT, OCT_3 + SEMI_B
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_C
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_D
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_E
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_F
  .byte  3, TIMBRE_BRIGHT, OCT_4 + SEMI_G
  .byte 12, TIMBRE_BRIGHT, OCT_4 + SEMI_A   ; ...and arrives, rather than
  .byte  0                                  ;   stopping

; --- The cauldron (constants.inc) --------------------------------------------
;   Three more step lists, in the same table and read by the same driver, and
;   the only things about them that are not effects are that no event asks for
;   one and that the ambience pitches each one up by a random 0-7 semitones
;   before it plays. That transposition is what turns three lists into a boil:
;   a bubble is a bubble whatever size it is, and a cauldron of one size sounds
;   like a machine.
;
;   All three are TIMBRE_SOFT or TIMBRE_NOISE and all three are written in the
;   bottom octave and a half, because everything up here has to sit UNDER the
;   title screen rather than on top of it. Nothing bright bubbles.

SfxBubble:                              ; 13 — a bloop, rising      8 frames
  .byte  3, TIMBRE_SOFT,   OCT_4 + SEMI_C   ; TIMBRE_SOFT sounds an octave
  .byte  3, TIMBRE_SOFT,   OCT_4 + SEMI_G   ;   below what is written, so this
  .byte  2, TIMBRE_SOFT,   OCT_5 + SEMI_C   ;   is C3 to C4 (constants.inc)
  .byte  0

SfxGloop:                               ; 14 — a heavier one, falling  6 frames
  .byte  2, TIMBRE_SOFT,   OCT_4 + SEMI_G
  .byte  4, TIMBRE_SOFT,   OCT_4 + SEMI_C
  .byte  0

SfxSeethe:                              ; 15 — the churn under both    9 frames
  .byte  3, TIMBRE_NOISE,  OCT_3 + SEMI_G   ; Low noise, dropping: the sound a
  .byte  4, TIMBRE_NOISE,  OCT_3 + SEMI_C   ;   pot makes between bubbles
  .byte  2, TIMBRE_OFF,    0                ; A REST, and a legal step — the
  .byte  0                                  ;   driver hands TIMBRE_OFF to the
                                            ;   platform like any other timbre
                                            ;   and gets silence for a beat,
                                            ;   which keeps the churn from
                                            ;   running straight into whatever
                                            ;   the next roll deals

; --- The mix (ambience.asm) --------------------------------------------------
;   Rolled once per sound, indexed by five random bits, so the shape of the
;   ambience is this table and nothing else: twenty-seven bubbles of one kind
;   or another to five borrowed effects, which is one thing happening in the
;   lab for every five or six the cauldron does. Change the balance by changing
;   the entries — there is no other knob and no code to edit.
;
;   THIRTY-TWO ROWS AND NOT SIXTEEN, which is the whole of how the borrowed
;   effects were halved after the first version came out too busy: the five of
;   them are the same five, spread over twice as many rolls. Doing it the other
;   way — dropping two or three of the five from a sixteen-row table — would
;   have changed which sounds the lab makes as well as how often it makes one,
;   and the mix among them was not the problem.
;
;   The five borrowed ones are the game's own sounds (SPEC 16), played half
;   volume and out of context: the prism's shimmer and the star's arpeggio read
;   as apparatus, the bolt's crack as a spark somewhere off to the side, the
;   lock's thunk as something heavy being set down, and the match chime as a
;   phial being touched. Nothing louder than those — a game-over run drifting
;   past the title screen would sound like a fault, not a laboratory.
;
;   Position means nothing here; only the counts do. Every roll is independent,
;   so the five are spread out to be read rather than to be heard that way.

AmbTable:
  .byte SFX_BUBBLE, SFX_SEETHE, SFX_BUBBLE, SFX_PRISM
  .byte SFX_GLOOP,  SFX_BUBBLE, SFX_BUBBLE, SFX_SEETHE
  .byte SFX_BUBBLE, SFX_GLOOP,  SFX_BOLT,   SFX_BUBBLE
  .byte SFX_GLOOP,  SFX_SEETHE, SFX_BUBBLE, SFX_BUBBLE
  .byte SFX_MATCH,  SFX_BUBBLE, SFX_GLOOP,  SFX_BUBBLE
  .byte SFX_SEETHE, SFX_BUBBLE, SFX_GLOOP,  SFX_STAR
  .byte SFX_GLOOP,  SFX_BUBBLE, SFX_SEETHE, SFX_BUBBLE
  .byte SFX_BUBBLE, SFX_LOCK,   SFX_GLOOP,  SFX_BUBBLE

