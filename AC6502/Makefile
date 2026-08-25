TARGET = WizardsLab
CONFIG = AC6502-16K

DEPS = ../src/*.asm ../src/*.inc ../data/*.inc ../data/*.bin ../include/ac6502.inc

.PHONY: all build view run smoke eeprom clean

all: build

build: $(TARGET).crt

$(TARGET).crt: $(TARGET).asm $(DEPS)
	cl65 -t none -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm

view: $(TARGET).crt
	hexdump -C $(TARGET).crt

run: $(TARGET).crt
	6502 run --cart $(TARGET).crt

# Boot headless and report why it stopped. --console video is what fits the
# TMS9918; the default serial console leaves the machine with no video card at
# all, and this cartridge would spin in HalWaitFrame forever waiting on it.
# Exit code 2 is "timed out", which for a game that loops forever is the
# success case — anything that halts or fails to load exits non-zero sooner.
smoke: $(TARGET).crt
	@6502 run --headless --console video --cart $(TARGET).crt \
	   --timeout 5s --json --quiet; \
	 status=$$?; \
	 if [ $$status -eq 2 ]; then echo "AC6502: ran 5s without halting"; \
	 else echo "AC6502: stopped early (exit $$status)"; exit 1; fi

eeprom: $(TARGET).crt
	minipro -p AT28C256 -w $(TARGET).crt

clean:
	rm -f $(TARGET).crt $(TARGET).lst $(TARGET).o
