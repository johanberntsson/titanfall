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

MUSIC_PRG = music/titan_theme.prg
MUSIC_SID = music/titan_theme.sid

all: $(PRG)

# world.asm is generated from the config — edit titan.yaml, not world.asm
$(WORLD): titan.yaml tools/genworld.py $(wildcard graphics/*-map*.s)
	$(PYTHON) tools/genworld.py titan.yaml $(WORLD)

# charset.asm is generated from the vchar64 exports — edit the art, not charset.asm
$(CHARSET): graphics/titan-charset.s graphics/titan-tile-colors.s tools/gencharset.py
	$(PYTHON) tools/gencharset.py graphics/titan-charset.s graphics/titan-tile-colors.s $(CHARSET)

$(BIN): $(SRCS)
	$(ACME) -f cbm -o $(BIN) $(SRC)

music/titan_theme.prg: music/titan_theme.asm
	$(ACME) -f cbm -o $@ $<

# the tune on its own as a PSID file, for SID players (sidplayfp, vsid)
sid: $(MUSIC_SID)

$(MUSIC_SID): music/titan_theme_sid.asm $(MUSIC_PRG)
	$(ACME) -f plain -o $@ $<

$(PRG): $(BIN) $(MUSIC_PRG)
	$(EXOMIZER) sfx sys,0x0801 $(BIN) $(MUSIC_PRG) -o $(PRG)

# release disk image: the packed game as the only file on a fresh D64
release: $(D64)

$(D64): $(PRG)
	mkdir -p release
	rm -f $(D64)
	$(C1541) -format "titan fall,tf" d64 $(D64) -write $(PRG) $(TARGET)

run: $(PRG)
	$(VICE) $(PRG)

clean:
	rm -f $(PRG) $(BIN) $(WORLD) $(CHARSET) $(MUSIC_PRG) $(MUSIC_SID)

.PHONY: all release run clean sid
