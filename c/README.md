# TITAN FALL in C (Calypsi)

The `calypsi` branch's port of the game from ACME assembly (`src/`) to C,
built with the Calypsi 6502 C compiler 5.18. It is the same game for the same
machine: one C64 PRG that also runs on the MEGA65 through the same C65/C64
wrapper. Both builds live in one tree, so they can be compared side by side
(`c/COMPARISON.md`).

```
make cgame      # titanfall-c.prg (C64 + MEGA65), like `make` for the asm build
make c-c64      # build and run it in VICE
make c-mega65   # build and run it in xemu
make cclean
```

`make` alone still builds the asm game. `COPT` overrides the compiler flags
(default `-O2 --speed --no-cross-call`).

## Layout

| File | Ports | Contents |
|------|-------|----------|
| `c/src/titan.h` | `titanfall.asm`'s equates | hardware registers, constants, the shared state, every module's functions |
| `c/src/main.c` | `titanfall.asm` | init, the main loop, F1 |
| `c/src/irq.s` | `titanfall.asm`, `game.asm` | the only assembly: banking BASIC out before the C startup, the raster IRQ, the sound effects (they run inside it), the `$FFFA` vectors |
| `c/src/screen.c` | `titanfall.asm` | row drawing, the shared box strings |
| `c/src/game.c` | `game.asm` | the frame, a new game / round, death, HUD, status line, clock, reactor, link |
| `c/src/move.c` | `game.asm` | keys, the human's and the driven robot's moves, doors, the wall grid |
| `c/src/actors.c` | `game.asm` | drawing the room, sprites, glide, the robot AI, the bolt, the force field |
| `c/src/*.c` | the asm module of the same name | everything else, one to one |
| `c/titan-c64.scm` | — | the linker's memory map (the Makefile fills in the sprite block's address) |
| `tools/acme2c.py` | — | the asm build's data files → `c/build/data.c`/`data.h` |
| `tools/hex2prg.py` | — | the linker's Intel hex → one PRG per memory, for exomizer |

Each `.c` file says which asm module it ports, and the C keeps the asm's
names (lower case) and structure, so the two can be read side by side.

## Data: from the asm build

`titan.yaml` and the vchar64 exports stay the only sources. The asm build's
generators write `src/world.asm` and `src/charset.asm`; `tools/acme2c.py`
reads those (and the sprite files, the logo and `petscii.asm`) and writes one
C file and header with the same names:

- constants → `#define`; a label with `!byte`/`!pet`/`!fill` data → an array;
  `X_LO`/`X_HI` tables of `<LABEL`/`>LABEL` → one pointer table `X[]`;
- everything after `world.asm`'s "runtime state" marker, the `ROOM_WALLS_n`
  grids and the charset are writable, the rest `const`;
- the sprite files become one block, `SPRITES[]`, ending at `$3800`, and
  `SPRP_<label>` constants for the sprite pointers.

**Text is ASCII.** The asm keeps text in PETSCII and converts it to screen
codes when drawing (`PET2SCREEN`). Calypsi's string literals are raw or
shifted PETSCII, neither of which suits `!pet`'s lower case, so the C port
uses ASCII everywhere and one conversion, `scr()` in `titan.h`: `a-z` →
1–26, everything below `$60` unchanged. A line glyph is written as its screen
code (`VB` = `"\x5d"`, `SC_RD_UL` …), and `[`/`]` as `LBR`/`RBR` (`$1B`/`$1D`
— ASCII's `$5B`/`$5D` are line glyphs here). `acme2c.py` converts `!pet`
data the same way.

## Memory

The C version doesn't fit where the asm version does. Its code is about the
same size as the asm's, but the asm's code area and high area were both full
(~220 bytes free), and the C build has a C stack and ~1 KB more of tables and
strings. So:

- **One PRG memory, `$0801–$BFFF`**, BASIC banked out (`__low_level_init` in
  `irq.s`, before the C startup runs anything above `$A000`). The sprites and
  the charset are pinned inside it at `$2280`/`$3800`; the linker fills the
  rest. The gap below the sprites holds the `lowcode` sections (`#pragma
  clang section text="lowcode"`: `actors.c`, `move.c`, `traps.c`, `rle.c`,
  `shutters.c`, `main.c`).
- **Under the KERNAL, `$E000–$FFF9` (`kdata`)**: data that's read rarely —
  the packed room maps, the sector map, the logo, the robodex pages. The
  KERNAL stays in (GETIN, its IRQ tail); a read is wrapped in `kernal_out()` /
  `kernal_in()` (`sei`, `$01 = $35` … `$01 = $36`, `cli`). The NMI vector at
  `$FFFA` points at an `rti`, so RESTORE can't crash it meanwhile.
- A PRG can't hold two memories, so the linker writes Intel hex,
  `tools/hex2prg.py` makes a PRG of each run of bytes, and exomizer packs them
  all with the music (it decrunches with all RAM banked in).
- The C stack (512 bytes) at `$CE00`, the help screen's buffers at `$C600`,
  the music at `$C000` — as in the asm build. Zero page `$02–$8F` (Calypsi's
  pseudo-registers and the game's hot variables, `ZP` in `titan.h`); above it
  is the KERNAL's.

## Gotchas

- **Calypsi 5.18 sign-extends `ptr + (uint8_t)(a + b)`**, at every
  optimisation level: an offset of 128–255 lands 256 bytes too low. Put the
  sum in a `uint8_t` variable first. (`wall_ptr` in `move.c`: the player
  couldn't walk below tile row 5.) Look for `ora #127` in the list files.
- **Write `(SCRN + 960)[i]`, not `SCRN[960 + i]`**: the first is
  `sta $07C0,x`, the second a 16-bit pointer computed on every iteration.
- **Cross-call optimisation** (`-O2`'s default) turns common code into
  `jsr` fragments, even a two-instruction loop body; the build turns it off
  (`--no-cross-call`, ~650 bytes bigger, much faster in loops).
- **Calypsi's `memcpy`/`memset` are slow**: ~80 cycles a byte (generic,
  16-bit counts). The C uses `fill()`/`copy()` (`screen.c`, ~20 cycles a
  byte); clearing the screen with `memset` made the switch from the cut
  scene to the game visibly slow.
- **Function calls cost**: a prologue that saves Calypsi's callee-saved
  pseudo-registers (`_AllocStackSave`) is often the biggest single item in a
  profile. Code that runs for every robot on every step must stay flat.
- **Frame budget**: the asm can do every robot's AI in one frame; the C
  can't. `tick_robot` staggers them (each robot keeps its own rhythm, a few
  think per frame), and the game state's IRQ skips the KERNAL's keyboard
  scan (~1300 cycles a frame while a key is held; the game reads the matrix
  itself). `irq_frames`/`loop_frames` (main.c) count frames run against
  frames shown: read them in the monitor to see dropped frames.
- **C's integer promotions** make `a + 1 == player_mode` a 16-bit compare and
  `(x + 6) / 12` a call to `_UDivMod16`; keep per-frame arithmetic in `uint8_t`
  variables.
- Data under the KERNAL must only be read between `kernal_out()` and
  `kernal_in()`, and nothing in between may call the KERNAL.
- The list files (`c/build/*.lst`, `game-c.lst` for the link map) are the
  first place to look; VICE 3.10's monitor profiler (`prof on` / `prof flat`
  with the symbols loaded from the link map) found every speed problem so far.
