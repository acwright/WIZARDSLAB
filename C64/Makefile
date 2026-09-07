TARGET = WizardsLab
CONFIG = C64-16K

# DEBUG=1 adds -DWL_DEBUG: the P1 debug board fill and a straight jump into
# play. Changing it must force a rebuild, so it is part of DEPS' effect via
# the ASMFLAGS below rather than a silent recompile.
ifeq ($(DEBUG),1)
ASMFLAGS = --asm-define WL_DEBUG=1
endif

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/c64.inc

.PHONY: all build view run smoke clean

all: build

build: $(TARGET).crt

$(TARGET).crt: $(TARGET).asm $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm

view: $(TARGET).crt
	hexdump -C $(TARGET).crt

run: $(TARGET).crt
	x64sc -cart16 $(TARGET).crt

# Boot headless in warp for 20M cycles and leave a screenshot to look at.
smoke: $(TARGET).crt
	@x64sc -console -warp -limitcycles 20000000 -cart16 $(TARGET).crt \
	  -exitscreenshot $(TARGET)-screenshot.png >/dev/null 2>&1 || true
	@test -s $(TARGET)-screenshot.png \
	  && echo "C64: ran 20M cycles, wrote $(TARGET)-screenshot.png" \
	  || { echo "C64: no screenshot — the cartridge did not come up"; exit 1; }

clean:
	rm -f $(TARGET).crt $(TARGET)-screenshot.png $(TARGET).lst $(TARGET).o
