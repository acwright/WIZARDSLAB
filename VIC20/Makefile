TARGET = WizardsLab
CONFIG = VIC20-16K

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
OUTPUTS = $(TARGET) $(TARGET)-blk5.crt $(TARGET)-blk3.crt $(TARGET).lst $(TARGET).o
DEBUGSTAMP = .debug-$(DEBUG)

.PHONY: debugstamp
debugstamp:
	@test -f $(DEBUGSTAMP) || { rm -f .debug-* $(OUTPUTS); touch $(DEBUGSTAMP); }

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/vic20.inc

.PHONY: all build debugstamp view run smoke clean

all: build

build: debugstamp
	@$(MAKE) --no-print-directory $(TARGET)-blk5.crt

# 16K is two 8K blocks, so the linker writes two files: BLK5 at $A000 carries
# the autostart header and the code, BLK3 at $6000 carries the data.
# ld65 names both files itself from the config, so -o only supplies the stem
# and cl65 leaves an empty file behind under that name. Sweep it up.
$(TARGET)-blk5.crt: $(TARGET).asm $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET) $(TARGET).asm
	@rm -f $(TARGET)

view: build
	hexdump -C $(TARGET)-blk5.crt

run: build
	xvic -cartA $(TARGET)-blk5.crt -cart6 $(TARGET)-blk3.crt

# Boot headless in warp for 20M cycles and leave a screenshot to look at.
smoke: build
	@xvic -console +saveres -warp -limitcycles 20000000 \
	  -cartA $(TARGET)-blk5.crt -cart6 $(TARGET)-blk3.crt \
	  -exitscreenshot $(TARGET)-screenshot.png >/dev/null 2>&1 || true
	@test -s $(TARGET)-screenshot.png \
	  && echo "VIC20: ran 20M cycles, wrote $(TARGET)-screenshot.png" \
	  || { echo "VIC20: no screenshot — the cartridge did not come up"; exit 1; }

clean:
	rm -f .debug-* $(TARGET) $(TARGET)-screenshot.png $(TARGET)-crosscheck.png $(TARGET)-blk3.crt $(TARGET)-blk5.crt $(TARGET).lst $(TARGET).o
