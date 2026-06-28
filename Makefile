TARGET = titanfall
SRC    = src/titanfall.asm
PRG    = $(TARGET).prg

ACME = acme
VICE = x64sc

all: $(PRG)

$(PRG): $(SRC)
	$(ACME) -f cbm -o $(PRG) $(SRC)

run: $(PRG)
	$(VICE) $(PRG)

clean:
	rm -f $(PRG)

.PHONY: all run clean
