# Root Makefile — delegates to each platform's own Makefile.
#
# Wizards Lab is one game built three ways. The shared sources live in src/
# and the artwork in data/; each platform directory holds only its cartridge
# header, its linker config, and its half of the HAL contract in src/hal.inc.

PLATFORMS = AC6502 VIC20 C64

.PHONY: all clean artwork artwork-check data smoke playtest crosscheck \
        audiocheck screenshots $(PLATFORMS) \
        run-AC6502 run-VIC20 run-C64 \
        smoke-AC6502 smoke-VIC20 smoke-C64

all: $(PLATFORMS)

# DEBUG=1 builds the -DWL_DEBUG variant: the title screen is skipped and the
# game starts playing, so a headless machine with no input attached still gets
# past it. Changing the setting forces a rebuild — see any platform Makefile.
export DEBUG

AC6502 VIC20 C64:
	@echo "==> Building $@"
	@$(MAKE) -C $@ all

# Launch a platform in its emulator. The AC6502 opens the desktop app; the two
# Commodores open VICE. All three block until the window closes, which is what
# makes them usable as a build step: assemble, look at it, close it.
run-AC6502: AC6502
	@$(MAKE) -C AC6502 run
run-VIC20: VIC20
	@$(MAKE) -C VIC20 run
run-C64: C64
	@$(MAKE) -C C64 run

# Boot headless and check the cartridge comes up rather than hanging. The two
# Commodores leave a screenshot beside their cartridge image.
smoke-AC6502: AC6502
	@$(MAKE) -C AC6502 smoke
smoke-VIC20: VIC20
	@$(MAKE) -C VIC20 smoke
smoke-C64: C64
	@$(MAKE) -C C64 smoke

smoke: smoke-AC6502 smoke-VIC20 smoke-C64

# Pull the drawn artwork out of artwork/WizardsLab.tms9918 — the master — into
# the binaries the build reads, and push the tileset and the clipped panel back
# into the VIC-EDITOR project so the two never drift. Run this after saving in
# TMS9918-EDITOR. See artwork/README.md.
artwork:
	python3 tools/import-artwork.py

# Fail if data/ is behind the master. Cheap enough to run before a release.
artwork-check:
	python3 tools/import-artwork.py --check

# Play the game with a script and check what the piece actually did — DAS
# timing, rotation, soft drop, lock delay, the walls and the floor, all read
# out of RAM rather than off a picture. Needs the DEBUG cartridge and a -g
# build beside it for the symbols. See tools/playtest.py.
playtest:
	@$(MAKE) DEBUG=1 AC6502
	cd AC6502 && cl65 -t none -g --asm-define WL_DEBUG=1 -C AC6502-16K.cfg \
	  -Wl --dbgfile,/tmp/wl.dbg -o /tmp/wl.crt WizardsLab.asm
	python3 tools/playtest.py

# Play one headless game on ALL THREE and check they end up with the same well.
# `make playtest` proves the rules on the machine whose memory can be read and
# written; this proves the other two run the same code to the same answer. Slow
# — three whole games, one of them a frame at a time — so it is a phase check
# and not something to run after every edit. See tools/crosscheck.py.
crosscheck:
	@$(MAKE) DEBUG=1
	cd AC6502 && cl65 -t none -g --asm-define WL_DEBUG=1 -C AC6502-16K.cfg \
	  -Wl --dbgfile,/tmp/wl.dbg -o /tmp/wl.crt WizardsLab.asm
	python3 tools/crosscheck.py

# Read what the two Commodores' sound chips are actually told. VICE's `dump`
# sound device logs every register write with its cycle, so a headless game
# leaves a transcript of every note the SID or the VIC-I was given — checked
# against src/tables.inc, register for register and frame for frame. The
# AC6502's half of SPEC 16 is in `make playtest`. See tools/audiocheck.py.
audiocheck:
	@$(MAKE) DEBUG=1 VIC20 C64
	python3 tools/audiocheck.py

# Retake the screenshots the README shows and check they show what it says.
# Both shots come off the SHIPPED cartridge: the play ones are a real game,
# played through VICE's monitor a frame at a time with the joystick held where
# the aim says, so the well fills the way a player fills it rather than in one
# column. The -g builds are only for the symbols that needs — they are
# byte-for-byte the cartridges above. Unlike `make smoke`'s throwaway PNGs
# these are committed, under names git keeps. See tools/screenshots.py.
screenshots:
	@$(MAKE) VIC20 C64
	cd VIC20 && cl65 -t none -g -C VIC20-16K.cfg \
	  -Wl --dbgfile,/tmp/wl-vic20.dbg -o /tmp/wl-vic20 WizardsLab.asm
	cd C64 && cl65 -t none -g -C C64-16K.cfg \
	  -Wl --dbgfile,/tmp/wl-c64.dbg -o /tmp/wl-c64.crt WizardsLab.asm
	python3 tools/screenshots.py

# Regenerate the placeholder artwork from scratch. Bootstrap only — this throws
# the real art away, and a plain run writes nothing. See data/README.md.
data:
	python3 tools/make-placeholders.py

clean:
	@for dir in $(PLATFORMS); do \
		echo "==> Cleaning $$dir"; \
		$(MAKE) -C "$$dir" clean || exit 1; \
	done
