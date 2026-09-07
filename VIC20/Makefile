TARGET = WizardsLab
CONFIG = VIC20-16K

# DEBUG=1 adds -DWL_DEBUG: the P1 debug board fill and a straight jump into
# play. Changing it must force a rebuild, so it is part of DEPS' effect via
# the ASMFLAGS below rather than a silent recompile.
ifeq ($(DEBUG),1)
ASMFLAGS = --asm-define WL_DEBUG=1
endif

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/vic20.inc

.PHONY: all build view run smoke clean

all: build

build: $(TARGET)-blk5.crt

# 16K is two 8K blocks, so the linker writes two files: BLK5 at $A000 carries
# the autostart header and the code, BLK3 at $6000 carries the data.
# ld65 names both files itself from the config, so -o only supplies the stem
# and cl65 leaves an empty file behind under that name. Sweep it up.
$(TARGET)-blk5.crt: $(TARGET).asm $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET) $(TARGET).asm
	@rm -f $(TARGET)

view: $(TARGET)-blk5.crt
	hexdump -C $(TARGET)-blk5.crt

run: $(TARGET)-blk5.crt
	xvic -cartA $(TARGET)-blk5.crt -cart6 $(TARGET)-blk3.crt

# Boot headless in warp for 20M cycles and leave a screenshot to look at.
smoke: $(TARGET)-blk5.crt
	@xvic -console -warp -limitcycles 20000000 \
	  -cartA $(TARGET)-blk5.crt -cart6 $(TARGET)-blk3.crt \
	  -exitscreenshot $(TARGET)-screenshot.png >/dev/null 2>&1 || true
	@test -s $(TARGET)-screenshot.png \
	  && echo "VIC20: ran 20M cycles, wrote $(TARGET)-screenshot.png" \
	  || { echo "VIC20: no screenshot — the cartridge did not come up"; exit 1; }

clean:
	rm -f $(TARGET) $(TARGET)-screenshot.png $(TARGET)-blk3.crt $(TARGET)-blk5.crt $(TARGET).lst $(TARGET).o
