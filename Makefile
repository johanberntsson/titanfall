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

# =============================================================================
# The C port (c/, the calypsi branch): the same game in C, built with Calypsi
# 5.18 into the same kind of PRG -- C64, and the MEGA65 through the same
# wrapper. The data comes from the asm build's generated files through
# tools/acme2c.py. See c/README.md.
# =============================================================================
CC6502   = cc6502
AS6502   = as6502
LN6502   = ln6502
CBUILD   = c/build
COPT    ?= -O2 --speed --no-cross-call
CFLAGS_C = --target=C64 $(COPT) -I c/src -I $(CBUILD)
C_SRCS   = $(wildcard c/src/*.c)
C_OBJS   = $(patsubst c/src/%.c,$(CBUILD)/%.o,$(C_SRCS)) $(CBUILD)/irq.o $(CBUILD)/data.o
C_GAME   = $(CBUILD)/game-c.prg
C_C64PRG = $(TARGET)-c-c64.prg
C_PRG    = $(TARGET)-c.prg
SPRITE_SRCS = src/c64_walker_sprites.asm src/c64_robot_sprites.asm \
              src/c64_drone_sprites.asm src/c64_dozer_sprites.asm \
              src/c64_tripod_sprites.asm src/c64_hopper_sprites.asm \
              src/c64_bolt_sprites.asm src/c64_forcefield_h_sprites.asm \
              src/c64_forcefield_v_sprites.asm

cgame: $(C_PRG)

$(CBUILD)/data.c $(CBUILD)/data.h: $(WORLD) $(CHARSET) $(SPRITE_SRCS) src/petscii.asm src/titanfall_title.asm tools/acme2c.py Makefile
	mkdir -p $(CBUILD)
	$(PYTHON) tools/acme2c.py --out $(CBUILD)/data --extra-frames 4 \
	    --writable CHARSET --pinned CHARSET=charset \
	    --pinned 'ROOM_MAP_[0-9]+|MAP_SCR|MAP_COL|TITLE_SCR|TITLE_COL|DEX_[0-9]+=kdata' \
	    --sprites $(SPRITE_SRCS) \
	    --defs src/petscii.asm src/titanfall_title.asm $(CHARSET) $(WORLD)

$(CBUILD)/%.o: c/src/%.c c/src/titan.h $(CBUILD)/data.h
	$(CC6502) $(CFLAGS_C) -c -o $@ $< --list-file $(CBUILD)/$*.lst

$(CBUILD)/data.o: $(CBUILD)/data.c $(CBUILD)/data.h
	$(CC6502) $(CFLAGS_C) -c -o $@ $<

$(CBUILD)/irq.o: c/src/irq.s
	mkdir -p $(CBUILD)
	$(AS6502) --target=C64 -o $@ $<

$(CBUILD)/titan.scm: c/titan-c64.scm $(CBUILD)/data.h
	sed "s/@SPRITES@/#x$$(sed -n 's/#define SPRITES_START 0x//p' $(CBUILD)/data.h)/" $< > $@

# Intel hex, not prg: the program is in two memories (c/titan-c64.scm)
$(C_GAME): $(C_OBJS) $(CBUILD)/titan.scm tools/hex2prg.py
	$(LN6502) --target=C64 --output-format=intel-hex --list-file $(CBUILD)/game-c.lst \
	    -o $(CBUILD)/game-c.elf $(C_OBJS) $(CBUILD)/titan.scm
	rm -f $(CBUILD)/game-c-*.prg
	$(PYTHON) tools/hex2prg.py $(CBUILD)/game-c.hex $(CBUILD)/game-c > $(CBUILD)/parts
	cp $(CBUILD)/game-c-0801.prg $@

$(C_C64PRG): $(C_GAME) $(MUSIC_PRG)
	$(EXOMIZER) sfx sys,0x0801 $$(cat $(CBUILD)/parts) $(MUSIC_PRG) -o $(C_C64PRG)

$(C_PRG): $(WRAPPER_PRG) $(C_C64PRG)
	cat $(WRAPPER_PRG) $(C_C64PRG) > $@

c-c64: $(C_PRG)
	$(VICE) -basicload $(C_PRG)

c-mega65: $(C_PRG)
	$(XMEGA65) -besure -prg $(C_PRG)

cclean:
	rm -rf $(CBUILD) $(C_PRG) $(C_C64PRG)

.PHONY: cgame c-c64 c-mega65 cclean

# bytes and lines per module, asm against C (tools/compare.py)
compare: $(C_GAME) $(SRCS)
	$(ACME) -f cbm -o $(CBUILD)/asm.prg -r $(CBUILD)/asm-report.txt $(SRC)
	$(PYTHON) tools/compare.py $(CBUILD)/asm-report.txt

.PHONY: compare
