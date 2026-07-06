TARGET = titanfall
SRC    = src/titanfall.asm
WORLD  = src/world.asm
SRCS   = $(wildcard src/*.asm) $(WORLD)
BIN    = game.prg
PRG    = $(TARGET).prg

ACME = acme
VICE = x64sc
EXOMIZER = exomizer
PYTHON = python3

all: $(PRG)

# world.asm is generated from the config — edit titan.yaml, not world.asm
$(WORLD): titan.yaml tools/genworld.py $(wildcard graphics/*-map.s)
	$(PYTHON) tools/genworld.py titan.yaml $(WORLD)

$(BIN): $(SRCS)
	$(ACME) -f cbm -o $(BIN) $(SRC)

$(PRG): $(BIN)
	$(EXOMIZER) sfx sys,0x0801 $(BIN) music/Licence_to_Kill.prg -o $(PRG)

run: $(PRG)
	$(VICE) $(PRG)

clean:
	rm -f $(PRG) $(BIN) $(WORLD)

.PHONY: all run clean
