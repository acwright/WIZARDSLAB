# Root Makefile — delegates to each platform's own Makefile.
#
# Wizards Lab is one game built three ways. The shared sources live in src/
# and the artwork in data/; each platform directory holds only its cartridge
# header, its linker config, and its half of the HAL contract in src/hal.inc.

PLATFORMS = AC6502 VIC20 C64

.PHONY: all clean data smoke $(PLATFORMS) \
        run-AC6502 run-VIC20 run-C64 \
        smoke-AC6502 smoke-VIC20 smoke-C64

all: $(PLATFORMS)

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

# Regenerate the placeholder artwork in data/. Only needed after editing
# tools/make-placeholders.py — real artwork arrives as editor exports and is
# not generated. See data/README.md.
data:
	python3 tools/make-placeholders.py

clean:
	@for dir in $(PLATFORMS); do \
		echo "==> Cleaning $$dir"; \
		$(MAKE) -C "$$dir" clean || exit 1; \
	done
