TARGET = WizardsLab
CONFIG = VC83
PRG    = WIZLAB.PRG
IMAGE  = wizlab.img

# Built and run against vc83computer at commit 8648902. The VC83 is still
# being designed and its OS, memory map and video formats move from month to
# month, so a newer checkout may need this port changing to match.
VC83_REPO ?= $(HOME)/Developer/Github/vc83computer
VC83_SIM   = $(VC83_REPO)/simulator/build/vc83_sim

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
OUTPUTS = $(PRG) $(IMAGE) $(TARGET).lst $(TARGET).o
DEBUGSTAMP = .debug-$(DEBUG)

.PHONY: debugstamp
debugstamp:
	@test -f $(DEBUGSTAMP) || { rm -f .debug-* $(OUTPUTS); touch $(DEBUGSTAMP); }

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin

.PHONY: all build debugstamp view run clean

all: build

build: debugstamp
	@$(MAKE) --no-print-directory $(IMAGE)

$(PRG): $(TARGET).asm $(CONFIG).cfg $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(PRG) $(TARGET).asm

# A 64 MB FAT SD card holding the one file. The simulator mounts it as A:,
# the default device, so EXEC "WIZLAB.PRG" finds it.
$(IMAGE): $(PRG)
	rm -f $(IMAGE)
	dd if=/dev/zero of=$(IMAGE) bs=1m count=64 2>/dev/null
	mformat -i $(IMAGE) -F ::
	mcopy -o -i $(IMAGE) $(PRG) ::$(PRG)

view: build
	hexdump -C $(PRG)

# Boot the simulator to BASIC with the card in. Type EXEC "WIZLAB.PRG" to
# play; Esc goes back to BASIC, and Cmd+Q quits the simulator.
run: build
	cd $(dir $(VC83_SIM)).. && $(VC83_SIM) --sd $(CURDIR)/$(IMAGE)

clean:
	rm -f .debug-* $(OUTPUTS)
