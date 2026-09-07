TARGET = WizardsLab
CONFIG = C64-16K

# DEBUG=1 adds -DWL_DEBUG: the title screen is skipped and the game starts
# playing, so a headless machine with no input attached still gets past it.
ifeq ($(DEBUG),1)
ASMFLAGS = --asm-define WL_DEBUG=1
endif

# The setting is not a file, so make cannot see it change and would leave the
# last build in place under the other flag — which looks exactly like a bug in
# the game. A stamp named after the setting fixes that, but it has to throw the
# stale outputs away in a make pass of its own: deleting a target from inside a
# prerequisite's recipe does not un-do the stat make already took.
OUTPUTS = $(TARGET).crt $(TARGET).lst $(TARGET).o
DEBUGSTAMP = .debug-$(DEBUG)

.PHONY: debugstamp
debugstamp:
	@test -f $(DEBUGSTAMP) || { rm -f .debug-* $(OUTPUTS); touch $(DEBUGSTAMP); }

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/c64.inc

.PHONY: all build debugstamp view run smoke clean

all: build

build: debugstamp
	@$(MAKE) --no-print-directory $(TARGET).crt

$(TARGET).crt: $(TARGET).asm $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm

view: build
	hexdump -C $(TARGET).crt

run: build
	x64sc -cart16 $(TARGET).crt

# Boot headless in warp for 20M cycles and leave a screenshot to look at.
smoke: build
	@x64sc -console -warp -limitcycles 20000000 -cart16 $(TARGET).crt \
	  -exitscreenshot $(TARGET)-screenshot.png >/dev/null 2>&1 || true
	@test -s $(TARGET)-screenshot.png \
	  && echo "C64: ran 20M cycles, wrote $(TARGET)-screenshot.png" \
	  || { echo "C64: no screenshot — the cartridge did not come up"; exit 1; }

clean:
	rm -f .debug-* $(TARGET).crt $(TARGET)-screenshot.png $(TARGET)-crosscheck.png $(TARGET).lst $(TARGET).o
