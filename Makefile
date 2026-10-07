TARGET = titanfall
SRC    = src/titanfall.asm
WORLD  = src/world.asm
CHARSET = src/charset.asm
SRCS   = $(wildcard src/*.asm) $(WORLD) $(CHARSET)
BIN    = game.prg
PRG    = $(TARGET).prg
D64    = release/$(TARGET).d64

ACME = acme
VICE = x64sc
EXOMIZER = exomizer
C1541 = c1541
PYTHON = python3

all: $(PRG)

# world.asm is generated from the config — edit titan.yaml, not world.asm
$(WORLD): titan.yaml tools/genworld.py $(wildcard graphics/*-map*.s)
	$(PYTHON) tools/genworld.py titan.yaml $(WORLD)

# charset.asm is generated from the vchar64 exports — edit the art, not charset.asm
$(CHARSET): graphics/titan-charset.s graphics/titan-tile-colors.s tools/gencharset.py
	$(PYTHON) tools/gencharset.py graphics/titan-charset.s graphics/titan-tile-colors.s $(CHARSET)

$(BIN): $(SRCS)
	$(ACME) -f cbm -o $(BIN) $(SRC)

$(PRG): $(BIN)
	$(EXOMIZER) sfx sys,0x0801 $(BIN) music/Licence_to_Kill.prg -o $(PRG)

# release disk image: the packed game as the only file on a fresh D64
release: $(D64)

$(D64): $(PRG)
	mkdir -p release
	rm -f $(D64)
	$(C1541) -format "titan fall,tf" d64 $(D64) -write $(PRG) $(TARGET)

run: $(PRG)
	$(VICE) $(PRG)

clean:
	rm -f $(PRG) $(BIN) $(WORLD) $(CHARSET)

.PHONY: all release run clean
