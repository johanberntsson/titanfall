TARGET = titanfall
SRC    = src/titanfall.asm
WORLD  = src/world.asm
CHARSET = src/charset.asm
WRAPPER = src/c65toc64wrapper.asm
SRCS   = $(filter-out $(WRAPPER),$(wildcard src/*.asm)) $(WORLD) $(CHARSET)
BIN    = game.prg
C64PRG = $(TARGET)-c64.prg
PRG    = $(TARGET).prg
D64    = release/$(TARGET).d64
D81    = release/$(TARGET).d81
WRAPPER_PRG = c65toc64wrapper.prg

ACME = acme
VICE = x64sc
EXOMIZER = exomizer
C1541 = c1541
PYTHON = python3
# SDL/xemu doesn't play nice with pipewire
XMEGA65 = SDL_AUDIODRIVER=pulseaudio xemu-xmega65

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

# the packed game on its own: a plain C64 PRG at $0801
$(C64PRG): $(BIN) $(MUSIC_PRG)
	$(EXOMIZER) sfx sys,0x0801 $(BIN) $(MUSIC_PRG) -o $(C64PRG)

# the game: one PRG for both the MEGA65 and the C64 — the C65/C64 mode wrapper
# (loads at $2001 in C65 mode, $0801 in C64 mode) with the packed game
# appended; it moves the game down to $0801 in C64 memory mode and starts it.
# On a C64 it's loaded with LOAD"TITANFALL",8 (not ,8,1)
$(PRG): $(WRAPPER_PRG) $(C64PRG)
	cat $(WRAPPER_PRG) $(C64PRG) > $@

$(WRAPPER_PRG): $(WRAPPER)
	$(ACME) --setpc 0x2001 --cpu m65 -f cbm -o $@ $<

# release disk images: the packed game as the only file on a fresh D64
# (C64) and D81 (MEGA65)
release: $(D64) $(D81)

$(D64): $(PRG) sid
	mkdir -p release
	rm -f $(D64)
	cp ${PRG} release
	$(C1541) -format "titan fall,tf" d64 $(D64) -write $(PRG) $(TARGET)

$(D81): $(PRG)
	mkdir -p release
	rm -f $(D81)
	$(C1541) -format "titan fall,tf" d81 $(D81) -write $(PRG) $(TARGET)

# VICE's autostart loads with ,8,1 unless told otherwise
c64: $(PRG)
	$(VICE) -basicload $(PRG)

mega65: $(PRG)
	$(XMEGA65) -besure -prg $(PRG)

clean:
	rm -f $(PRG) $(C64PRG) $(BIN) $(WRAPPER_PRG) $(WORLD) $(CHARSET) $(MUSIC_PRG) $(MUSIC_SID)

.PHONY: all release c64 mega65 clean sid
