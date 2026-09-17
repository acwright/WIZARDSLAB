TARGET = WizardsLab
CONFIG = AC6502-16K

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

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/ac6502.inc ../include/sid.inc

.PHONY: all build debugstamp view run smoke eeprom clean

all: build

build: debugstamp
	@$(MAKE) --no-print-directory $(TARGET).crt

$(TARGET).crt: $(TARGET).asm $(DEPS)
	cl65 -t none $(ASMFLAGS) -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm

view: build
	hexdump -C $(TARGET).crt

# The same cartridge runs on either video card: a TMS9918A with BIOS 1.x, or a
# 6502-PICOVDP with BIOS 2.x. CARD picks the one to run on, and with it the
# BIOS the emulator boots (1.6 or 2.0). Naming it keeps a change in the
# emulator's default from changing what gets run.
CARD ?= tms9918a
# `make smoke` boots every card listed here; a plain CARD= narrows it to one.
ifeq ($(origin CARD),command line)
SMOKE_CARDS ?= $(CARD)
else
SMOKE_CARDS ?= tms9918a picovdp
endif

run: build
	6502 run --vdp $(CARD) --cart $(TARGET).crt

# Boot headless and report why it stopped. --console video is what fits the
# TMS9918; the default serial console leaves the machine with no video card at
# all, and this cartridge would spin in HalWaitFrame forever waiting on it.
# Exit code 2 is "timed out", which for a game that loops forever is the
# success case — anything that halts or fails to load exits non-zero sooner.
# One run per card in SMOKE_CARDS; any card that stops early fails the target.
smoke: build
	@failed=0; \
	 for card in $(SMOKE_CARDS); do \
	   6502 run --headless --console video --vdp $$card --cart $(TARGET).crt \
	     --timeout 5s --json --quiet; \
	   status=$$?; \
	   if [ $$status -eq 2 ]; then echo "AC6502 ($$card): ran 5s without halting"; \
	   else echo "AC6502 ($$card): stopped early (exit $$status)"; failed=1; fi; \
	 done; \
	 exit $$failed

eeprom: build
	minipro -p AT28C256 -w $(TARGET).crt

clean:
	rm -f .debug-* $(TARGET).crt $(TARGET).lst $(TARGET).o
