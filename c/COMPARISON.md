# TITAN FALL: asm against C (Calypsi)

2026-10-16. The two builds are the same game for the same C64 PRG (also on
the MEGA65), and the same data from `titan.yaml`. The C port follows the asm
module by module (`c/README.md`). Reproduce the size table with `make
compare`.

**Played side by side, the two versions feel identical** -- after the speed
work below. The first C version walked ~10% slower and took a visible 0.6 s
to get from the cut scene into the game.

## Summary

| | asm (ACME) | C (Calypsi 5.18) |
|---|---|---|
| Lines of code (non-blank, non-comment; see Source size) | 4,602 (8,281 statements) | 3,968: 3,862 C + 106 asm |
| Bytes for the same modules (code + its strings, tables, buffers) | 20,995 | 27,137 (**+29%**) |
| … of which code | — | 22,266 |
| Fits the asm build's memory map | yes (~220 bytes free) | **no**: needs 7.4 KB of the RAM under the KERNAL |
| Free memory left | ~220 bytes | ~1.1 KB (178 high, 184 low, 772 under the KERNAL) |
| Frame rate | 50 fps | 50 fps; walking in the busiest rooms drops ~1 frame in 200 (39 fps walking before tuning) |
| CPU per frame, room 5 (1 robot) | 11,540 cycles (59%) | 11,450 cycles (58%) |
| CPU per frame, room 9 (4 robots) | 11,360 cycles (58%) | 12,420 cycles (63%) |
| Cut scene → game (`SETUP_GAME`) | 231,000 cycles | 331,000 cycles (620,000 before tuning) |
| Rooms drawn identically (screen + colour RAM) | — | 16 of 16 (rooms 15/16 differ only in timed state: a shutter, the switch blocks) |

Cycles per frame come from VICE 3.10's profiler (exact counts, not sampling):
everything except the wait for the next frame, so the music IRQ and the
cycles the VIC steals are included in both. The averages hide the problem:
the C build only keeps up because of several changes the asm doesn't have
(listed under Speed), which save it ~10,000 cycles a frame; like for like
the C game logic costs roughly 1.5–2× the asm's cycles.

## Size

Per module (`make compare`):

| asm module | asm B | C B | C/asm |
|---|---:|---:|---:|
| game.asm (C: game.c + move.c + actors.c) | 5,012 | 7,066 | 1.41 |
| carrier.asm | 2,173 | 2,803 | 1.29 |
| popup.asm | 1,338 | 1,583 | 1.18 |
| cutscene.asm | 1,329 | 1,577 | 1.19 |
| crates.asm | 719 | 1,078 | 1.50 |
| switches.asm | 681 | 1,120 | 1.64 |
| hopper.asm | 514 | 774 | 1.51 |
| traps.asm | 311 | 494 | 1.59 |
| … all 22 modules | 20,995 | 27,137 | 1.29 |

Modules that are mostly text and tables (intro, help, terminal, popup) cost
about the same in C. Modules of dense bit-fiddling logic (crates, traps,
hopper, switches) come out 1.4–1.6×. Compiler flags hardly matter:
`-O2 --space` and `-O2 --speed` gave the same size, `--no-inline` +1%,
`--no-cross-call` +3%, `-O1` +14%. (The speed work below added ~450 bytes:
switches.asm's port grew most, by its faster crush check.)

**Memory was the hard part.** The asm build fills the C64: code to `$20F3`
under the sprites, the high area to `$BFAE`. The C build was 6.2 KB over. It
fits because:

- data that's read rarely (the packed room maps, the sector map, the logo,
  the robodex pages: 7.4 KB) moved to the RAM under the KERNAL ROM. It's read
  with the KERNAL banked out for a moment (`kernal_out()`/`kernal_in()`), so the
  game still uses the KERNAL's IRQ and keyboard scan;
- that makes two memories, which a PRG can't hold: the linker writes Intel hex,
  `tools/hex2prg.py` splits it, exomizer packs the parts.

## Source size

| | Lines in total | Lines of code |
|---|---:|---:|
| **C version** | 4,977 | **3,968** |
| … C (`c/src/*.c`, 25 files) | 4,497 | 3,579 |
| … C header (`titan.h`) | 340 | 283 |
| … assembly (`irq.s`) | 140 | 106 |
| **asm version** (`src/*.asm`, 22 modules) | 6,385 | **4,602** |

"Lines of code" leaves out blank and comment-only lines. The asm often puts
several instructions on one line (`lda #0 : sta X`): counted as statements
it's 8,281 instructions and directives on those 4,602 lines. So the C is 86%
of the asm by lines, and under half by statements. The assembly in the C
version (3%) is the bank switch before the C startup, the raster IRQ and the
sound effects that run inside it.

Not counted, in either: the generated and data files both builds share (world,
charset, sprites, logo, PETSCII constants) and the C65/C64 wrapper. The C
build's own tooling adds 553 lines: `tools/acme2c.py` (367),
`tools/hex2prg.py` (51), `tools/compare.py` (92) and the linker rules
`c/titan-c64.scm` (43).

## Memory maps

One character = 512 bytes, `$0000` at the left of the first row, `$8000` of
the second; each cell shows what fills most of it.

```
        c code (compiled / assembled)    t game tables and strings
        w world data (from titan.yaml)   s sprites    f charset   l logo
        r runtime state and buffers      m music      h help screen's save buffers
        k C stack    i I/O    o KERNAL ROM    z zero page, stack, system    . free

asm   $0000 zzzzcccccccccccctsssssssssssfffflwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww
      $8000 wwwrccccccccccccccccccrrccccccccmmmhhhh.iiiiiiiioooooooooooooooo

C     $0000 zzzzcccccccccccccsssssssssssffffwwwwwwwwwwwwwwwwwwwccccccccccccc
      $8000 ccccccccccccccccccccwwwwwwwwrrrrmmmhhhhkiiiiiiiiwwwwwwwwwwwwww..
```

The same picture in two places: VIC data (sprites, charset) pinned below
`$4000`, the music at `$C000`, the help buffers at `$C600`. The difference: the
asm has code at both ends of the program area with the world data between,
the C has the world data first and one long run of code; and the C build
needs the RAM under the KERNAL ROM for 7.4 KB of world data, where the asm
build leaves the ROM in place.

### asm (ACME)

| Address | Bytes | Contents |
|---|---:|---|
| `$0002–$0068` | 103 | zero page: the game's variables |
| `$0801–$080F` | 15 | BASIC stub |
| `$0810–$20F2` | 6,371 | code: `titanfall.asm`, `game.asm`, `interlock.asm`, `shutters.asm` (with their strings) |
| `$20F3–$21F2` | 256 | `TILE_COLORS` |
| `$21F3–$227F` | 141 | free |
| `$2280–$36FF` | 5,504 | sprites, 86 frames |
| `$3700–$37FF` | 256 | cut scene frames (filled at run time) |
| `$3800–$3FFF` | 2,048 | charset |
| `$4000–$427F` | 640 | title logo |
| `$4280–$8581` | 17,154 | world data: tables, room maps (RLE), wall grids, sector map, texts |
| `$8582–$8774` | 499 | world runtime state (`ACT_X` …) |
| `$8775–$BFAD` | 14,393 | code: the other 18 modules, with their strings and tables (880 of it `ROOM_BUF` at `$AC1C`) |
| `$BFAE–$BFFF` | 82 | free |
| `$C000–$C55D` | 1,374 | music |
| `$C600–$CDFF` | 2,048 | help screen's save buffers |
| `$CE00–$CFFF` | 512 | free |
| `$E000–$FFFF` | | KERNAL ROM (in use) |

### C (Calypsi)

| Address | Bytes | Contents |
|---|---:|---|
| `$0002–$0037` | 54 | zero page: Calypsi's pseudo-registers |
| `$0038–$0071` | 58 | zero page: the game's variables |
| `$0801–$083B` | 59 | BASIC stub, Calypsi's startup |
| `$083C–$087F` | 68 | small constant tables |
| `$0880–$21C7` | 6,472 | code (`lowcode`): `actors.c`, `move.c`, `traps.c`, `rle.c`, `shutters.c`, `main.c` |
| `$21C8–$227F` | 184 | constants (world tables, strings) |
| `$2280–$37FF` | 5,504 + 256 | sprites + cut scene frames |
| `$3800–$3FFF` | 2,048 | charset |
| `$4000–$662F` | 9,776 | constants: world tables 6.9 KB, the C code's strings and tables 2.8 KB, interleaved |
| `$6630–$A7DD` | 16,814 | code: the other modules (809 of it Calypsi's library: multiply, divide, prologues) |
| `$A7DE–$B826` | 4,169 | initialised writable data: the wall grids (3,520), texts patched at run time |
| `$B827–$BF4D` | 1,831 | runtime state (world 441) and buffers (`ROOM_BUF` 880, beam path, …) |
| `$BF4E–$BFFF` | 178 | free |
| `$C000–$C55D` | 1,374 | music |
| `$C600–$CDFF` | 2,048 | help screen's save buffers |
| `$CE00–$CFFF` | 512 | C stack |
| `$E000–$FCF5` | 7,414 | under the KERNAL ROM: packed room maps, sector map, logo, robodex pages |
| `$FCF6–$FFF9` | 772 | free (under the KERNAL ROM) |
| `$FFFA–$FFFF` | 6 | NMI/RESET/IRQ vectors for while the KERNAL is banked out |

Code in all: asm ~19,800 bytes (with its strings and buffers), C 22,476 +
809 library. The `TILE_COLORS`/logo/world-data rows are the same bytes in
both builds, placed differently.

## Speed

The straight port ran at about **45 fps**: frames that ran the robots' AI
overran 20 ms. Profiling (VICE 3.10, `prof on` / `prof flat` with the link
map's symbols) found:

1. **Calypsi's cross-call optimisation** (on by default) turned even a
   two-instruction loop body into a `jsr` to a shared fragment.
   `--no-cross-call` for the whole build (+650 bytes).
2. **`memcpy`/`memset`** are generic and slow for 40-byte copies (18% of the
   time went to one `memcpy` in `draw_status`). Replaced with plain loops in
   per-frame code.
3. **`SCRN[960 + i]`** compiles to a 16-bit pointer computed per iteration;
   `(SCRN + 960)[i]` is `sta $07C0,y`.
4. **Integer promotion**: `(shown + 6) / 12` called a 16-bit division, so the
   division became a subtraction loop. `scr()` (text to screen code) became
   `static inline`.
5. **Two redraws made incremental** — *a change of algorithm the asm doesn't
   have*. The status line's template is drawn once and only its fields each
   frame. The orders line is redrawn only when the room or its goal changes.
   The asm redraws both, about 80 characters, every frame. That saves the C
   ~7,000 cycles a frame. The asm could do the same.

After 1–5 a standing player saw 50 fps, but play-testing found walking
noticeably slower (~10%) and the switch from the cut scene to the game slow
(the screen visibly clearing, then dark). A second round:

6. **The robots' AI in one frame** (every 8th) cost ~22,000 cycles in C, a
   whole frame on its own, so one frame in eight was dropped. *Changed from
   the asm*: each robot keeps its own rhythm but takes its turn on its own
   frame of the 16-frame cycle, so a few think per frame. Robots in a room
   no longer step in unison.
7. **The KERNAL's keyboard scan** costs ~1,300 cycles a frame while a key is
   held. *Changed from the asm*: in the game state the IRQ skips the
   KERNAL's housekeeping (the game reads the key matrix itself; the menus,
   which use GETIN, keep it).
8. **The HUD clock and mode, the status fields, the reactor's 16-bit
   multiplication**: computed or drawn only when they change.
9. **An off-screen switch flip** (room 16's dozer, from anywhere) checked
   every robot and every crate for each of 11 blocks: ~600 loop iterations in
   one frame. Now each robot of the room is checked once, and the crates only
   if the room has any.
10. **`memset`/`memcpy`** (~80 cycles a byte) replaced by `fill`/`copy`
    (~20): clearing the screen alone took 0.17 s. The room blit is one loop
    over four 220-byte quarters with constant bases.

After 1–10: average load as in the asm build (58–63% against 58–59%), 50 fps
standing everywhere measured, and walking in the busiest rooms drops about
one frame in 200 (a step and a robot turn on the same frame). The switch to
the game takes 0.33 s against the asm's 0.23 s. Frames are counted in
`irq_frames`/`loop_frames` (`main.c`).

## Ease of development

- **The port**: the whole game in one session. Every C file compiled first
  time; the bugs were found by running it. Two were mine: brackets drawn as
  the wrong glyph (ASCII `[` = `$5B` is a line glyph in screen codes), and
  dialog offsets I first hard-coded. One was the compiler's (next item).
- **A Calypsi 5.18 code generation bug**: `ptr + (uint8_t)(a + b)`
  sign-extends the cast, at every optimisation level. The wall grid lookup
  read the wrong bytes for tile rows 6–10, so the player couldn't walk below
  row 5. A temporary variable avoids it. The asm has no such class of problem,
  but it has its own: the CLAUDE.md gotchas (`TILE_COLORS` overwritten without
  an error, branch ranges, `$D011` bit 7, anonymous labels).
- **Readability**: the C is shorter (3,968 lines of code against 4,602; the
  asm packs 8,281 statements on its lines). The asm passes tiles in the
  globals `NEWX`/`NEWY`, so every routine documents what it clobbers. In C the
  coordinates are parameters (`wall_at(room, x, y)`), and the register and
  scratch-variable rules ("preserves X, clobbers TMP/PTR") disappear. Carry
  flag returns became `bool`, the `DRAW_ROWS` byte tables became
  `struct row` arrays, the state dispatch a `switch`.
- **What C doesn't remove**: the hardware rules, the memory map, the IRQ (still
  asm, `irq.s`), and the need to read the compiler's output. Speed depended on
  knowing what Calypsi does with a given C construct, which needs the list
  files and a profiler. The memory map is more work in C than in ACME:
  sections, pinned addresses, a hex splitter.
- **Data**: no duplication. `tools/acme2c.py` turns the asm build's generated
  data into C, so `titan.yaml` stays the only source. Code changes still have
  to be made in both builds.

## Not done yet

- Verified so far: every room's art, walking, doors, the switch door, search,
  popups, terminal, map, robodex, links and driving, laser burn-out, pushing,
  plates and gate, the interlock, shutters and the bolt hitting the target,
  the hopper's jump, the laser trap, death and respawn, crushing blocks, the
  carrier lock's screen, help, game over, the win with its level step, and the
  MEGA65 boot. Not yet: a full play-through to the win in one game, the
  carrier lock won, the mirror puzzle solved, and the game on real hardware.
- The performance numbers are a few rooms and one run each. The room 9
  figure includes whatever its random robots did in those 5 seconds.
- The speed-ups 6–9 are algorithm changes the asm build doesn't have; the
  asm could make them too, but doesn't need them.

## TL;DR

**Is C with Calypsi competitive with assembly on the C64? Yes.** The same
game, ported module by module, plays identically side by side on the same
hardware:

- **Size: +29%** for the same modules (27.1 KB against 21.0 KB); the code
  alone is only ~13% bigger. The plan had guessed 1.5–2.5×. It still didn't
  fit the asm build's full memory map: 7.4 KB of rarely read data moved under
  the KERNAL ROM.
- **Speed: on par.** 58–63% of a frame against 58–59%, 50 fps. But only after
  profiler-guided tuning: the straight port ran ~10% slow, mostly from
  library routines, cross-call fragments, integer promotion and doing all the
  robots' AI in one frame.
- **Source: shorter and clearer.** 3,968 lines (3% of it asm) against 4,602
  lines holding 8,281 asm statements; parameters instead of shared scratch
  variables and register rules.
- **Costs:** you still need to read the generated code and profile, and the
  toolchain has rough edges (one code generation bug; the linker's
  single-memory PRG limit).

That's Calypsi 5.18; a weaker compiler would change the answer — cc65's code
is usually reckoned considerably slower and bigger, though this project
hasn't measured it.
