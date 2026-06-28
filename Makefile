TARGET = titanfall
SRC    = src/titanfall.asm
BIN    = game.prg
PRG    = $(TARGET).prg

ACME = acme
VICE = x64sc
EXOMIZER = exomizer

all: $(PRG)

$(PRG): $(SRC)
	$(ACME) -f cbm -o $(BIN) $(SRC)
	$(EXOMIZER) sfx sys,0x0801 $(BIN) music/armalyte.prg -o $(PRG)

run: $(PRG)
	$(VICE) $(PRG)

clean:
	rm -f $(PRG) $(BIN)

.PHONY: all run clean
