# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Commodore 64 game called **TITAN Fall** (working title) — a cinematic infiltration puzzle thriller in the vein of *Impossible Mission* and *Paradroid*. The player infiltrates an automated missile launch complex and must subvert its drone workforce to stop a launch countdown. The game is targeted at PAL/NTSC C64 hardware. See `gamedesign.md` for the full design document.

## Build & Run

```
make        # assemble + pack
make run    # assemble, pack, and launch in Vice
make clean  # remove game.prg and titanfall.prg
```

The build is two steps handled by the Makefile:
1. **ACME 0.97** assembles `src/titanfall.asm` → `game.prg` (`-f cbm`, 2-byte load header)
2. **Exomizer** packs `game.prg` + `music/armalyte.prg` into a self-extracting `titanfall.prg`

Emulator: **x64sc** (Vice). Do not run `acme` directly; always use `make`.

## Code Layout

The source is split into one orchestrator and six state modules, all `!source`d into a single ACME assembly pass:

| File | Contents |
|------|----------|
| `src/titanfall.asm` | Constants, BASIC stub, entry point, `MAIN_LOOP`, `CLS`, `RASTER_IRQ`, shared strings, sprite data, room data |
| `src/intro.asm` | `DO_INTRO`, `DRAW_INTRO_SCREEN`, `BLINK_ON/OFF`, intro strings |
| `src/game.asm` | `DO_GAME`, `SETUP_GAME`, HUD, clock, reactor, player/robot movement, sound |
| `src/gameover.asm` | `DO_GAMEOVER`, `SETUP_GAMEOVER`, `GO_BLINK` helpers, strings |
| `src/win.asm` | `DO_WIN`, `SETUP_WIN`, `WIN_BLINK` helpers, strings |
| `src/terminal.asm` | `SETUP_TERMINAL`, `DO_TERMINAL`, `TERM_DRAW_SEL`, `CLEAR_ROOM`, strings |
| `src/map.asm` | `DO_MAP`, `SETUP_MAP`, map strings |

Other files:
- `game.prg` — intermediate assembled output (not committed)
- `titanfall.prg` — final self-extracting packed output (not committed)
- `music/armalyte.prg` — stripped Armalyte SID music binary (load address `$C000`)
- `music/armalyte.info` — sidplayfp info for the music file

`!source` paths in `titanfall.asm` are relative to the project root (where `make` runs), so they are written as `!source "src/intro.asm"` etc.

### BASIC stub convention

Only `src/titanfall.asm` carries the BASIC stub. The `* = $0801` loader appears once in the whole codebase:

```asm
* = $0801
    !byte $0B, $08      ; next-line pointer
    !byte $0A, $00      ; line number 10
    !byte $9E           ; SYS token
    !pet "2064"         ; decimal address of machine code entry point
    !byte $00           ; end of line
    !byte $00, $00      ; end of BASIC program
; machine code starts here at $0810
```

The SYS address in `!pet` must be kept in sync manually if the header ever changes size.

**Use `!pet` not `!text` for all strings.** `!text` outputs raw ASCII; the C64 uses PETSCII, which has different character codes and causes garbled output.

## Memory Layout

| Address | Purpose |
|---------|---------|
| `$0801` | BASIC stub (SYS 2064) |
| `$0810` | Entry point / code start (code + strings end before `$3F00`) |
| `$0400–$07FF` | Screen RAM (default VIC bank) |
| `$D800–$DBFF` | Colour RAM |
| `$07F8` | Sprite pointer table (end of screen RAM — **must be restored after every CLS call**) |
| `$3F00` | Sprite 1 data — robot enemy (64-byte aligned, pointer `$FC`) |
| `$3F40` | Sprite 0 data — player (64-byte aligned, pointer `$FD`) |
| `$3F80` | Room data (`ROOM_DATA`, `ROOM2_DATA`) and all string constants |
| `$C000–$CF81` | Armalyte SID music (init `$C000`, play `$C059`; loaded by exomizer) |

## Core Design Constraints

When implementing code, always respect these C64 hardware limits:

- **CPU:** MOS 6510 (6502 derivative); assembler is **ACME** (not cc65, not KickAssembler)
- **VIC-II sprites:** Exactly 8 hardware sprites available — the design intentionally avoids a sprite multiplexer
- **Room layout:** 22 rows × 40 chars of PETSCII per room; player tile grid is 10×10 (0–9 each axis)
- **Memory:** 64 KB total; code, data, and screen RAM must all fit within the standard C64 memory map
- **SID chip:** 3 voices for audio

## State Machine

`GAME_STATE` (`$1A`) holds the current state. The main loop syncs to a raster IRQ at line 50 (~50 Hz PAL); `TICK_FLAG` is set by the IRQ and cleared each frame by `MAIN_LOOP`.

| Value | State | Description |
|-------|-------|-------------|
| 0 | Intro | Title screen, tagline, blinking "press any key" prompt |
| 1 | Game | Playfield with HUD, player sprite, room map, countdown clock, reactor meter |
| 2 | Game over | Red border + descending-pitch sound, then game-over screen |
| 3 | Terminal | Full-screen drone selection menu (T key near terminal; time paused; sprite hidden) |
| 4 | Win | Mission complete screen (reached via bottom exit in room 2) |
| 5 | Map | Sector map overlay (M key; time paused; sprite hidden; any key to return) |

**Stack discipline:** The state machine uses fall-through / `jmp` between states, not `jsr`/`rts`. `MAIN_LOOP` is entered by falling through from init code, never by `jsr`. State transitions use `jmp SETUP_*` not `jsr`, so the return address on the stack is always the one from `DISPATCH`'s `jsr TICK_*`. Never `jsr` into anything that falls into `MAIN_LOOP`.

**Dispatch uses `bne`+`jmp` pairs, not `beq`.** The `DO_*` handlers live in `!source`d files assembled after `CLS`/`RASTER_IRQ`/shared strings, placing them beyond the ±127-byte range of a `beq`. The dispatch reads: `bne MLNOT0 : jmp DO_INTRO` etc.

**State >= 4 guard in GAME_ALIVE:** After `MOVE_PLAYER` and `READ_KEYS`, `GAME_ALIVE` checks `lda GAME_STATE : cmp #4 : bcs GAME_TICK_DONE`. This skips sprite update / HUD / status draws whenever state 4 (win) or 5 (map) was triggered mid-frame.

## Gameplay Architecture

The game has two distinct active modes sharing a single countdown timer:

1. **Human mode** — player explores rooms, scavenges for Access Clearance Chips (levels 1–4) and Direct Override Codes (robot serial numbers)
2. **Robot/proxy mode** — activated at mainframe terminals; the human sprite freezes and the player controls a drone remotely

Key state to track:
- Countdown timer (real-time; –10 min penalty per human death)
- Inventory: access chips and robot serial codes
- Per-room: tile array, active sprite positions, patrol paths
- Active mode (human / drone) and which drone serial is linked

## Rooms

Two rooms are implemented. `CUR_ROOM` (`$25`) selects which room is drawn and which robot is shown.

| Room | Index | Notable features |
|------|-------|-----------------|
| Room 1 | 0 | Terminal (T), laser wall at tile X=6, left-wall doorway at PLR_Y 5–6 |
| Room 2 | 1 | Right-wall doorway (back to room 1) at PLR_Y 5–6; bottom-wall exit (win) at PLR_X 4–6 |

Doorway transitions call `DRAW_ROOM` which dispatches on `CUR_ROOM` to blit the appropriate 22×40 char block from `ROOM_DATA` or `ROOM2_DATA`.

## Drone Types

Three drone classes with distinct capabilities (treat as puzzle keys, not combat units):
- **Industrial Loader Bot (BOT-7741)** — immune to lasers and cryogenic hazards; can push heavy objects
- **Maintenance Splicer (BOT-3312)** — fits through 1-tile ventilation ducts; can short-circuit junction boxes
- **Suppressor Centurion (BOT-9901)** — armed; used only in sectors flooded with hostile rogue drones (locked — requires access chip)

## Sprites

| Slot | Pointer | Address | Content | Colour |
|------|---------|---------|---------|--------|
| 0 | `$FD` | `$3F40` | `SPR_PLAYER` — top-down human (oval head, torso, legs) | Cyan |
| 1 | `$FC` | `$3F00` | `SPR_ROBOT` — robot enemy (square head, wide shoulders, split legs) | Orange |

Both sprite pointers (`$07F8` and `$07F9`) must be restored after every `CLS` call. `VIC_SPEN` is set to `$03` (both sprites enabled) during game state, `$00` in all other states.

### Robot enemy patrol
`TICK_ROBOT` is called every game frame (shared 20-frame timer):
- Robot 0 (room 1): patrols tile X 2–4, fixed Y=7
- Robot 1 (room 2): patrols tile X 2–7, fixed Y=5

`UPDATE_SPRITE1` uses the same coordinate formula as `UPDATE_SPRITE0`: X pixel = `ROB_X * 24 + 28`, Y pixel = `ROB_Y * 16 + 66`.

### Sprite collision
`CHECK_SPRITE_HIT` reads `VIC_SPCOLL` (`$D01E`) each frame after both sprites are positioned. Bits 0–1 non-zero means sprites 0 and 1 overlapped. Response is identical to laser death: red border, `DEATH_TMR = 100`, `SOUND_DEATH_START`. `$D01E` is cleared by the hardware on read.

## Zero Page Map

```
$02  PLR_X        player tile X (0-9)
$03  PLR_Y        player tile Y (0-9)
$04  CLK_H        countdown hours
$05  CLK_M        countdown minutes
$06  CLK_S        countdown seconds
$07  CLK_TICK     jiffy counter (0-49, PAL)
$08  REACT_TEMP   reactor temperature 0-99
$09  REACT_CNT    reactor drift counter
$0A  REACT_JIT    reactor jitter sub-counter
$0B  LFSR_ST      8-bit LFSR state for noise
$0C  MOVE_TMR     player movement throttle
$0D  TICK_FLAG    set by raster IRQ each frame
$0E  BFLASH       border flash countdown
$0F  KEY_U        up key flag
$10  KEY_D        down key flag
$11  KEY_L        left key flag
$12  KEY_R        right key flag
$14/$15  PTR      source pointer (indirect addressing)
$16/$17  PTR2     dest pointer
$18  TMP          scratch
$19  TMP2         scratch / bar colour
$1A  GAME_STATE   0=intro 1=game 2=gameover 3=terminal 4=win 5=map
$1B  DEATH_TMR    frames remaining after laser/robot hit (100 frames)
$1C  BLINK_TMR    blink frame counter
$1D  BLINK_ST     blink state (0=visible 1=hidden)
$1E  SND_TMR      death sound countdown (0=silent)
$1F  TERM_SEL     terminal selected drone row (0-3)
$20  TERM_TMR     terminal link confirmation countdown
$21  NEAR_TERM    non-zero when player is adjacent to terminal
$22  KEY_F1       T key flag (enter terminal)
$23  KEY_RET      Return key flag
$24  KEY_ESC      F7/Escape key flag
$25  CUR_ROOM     current room (0=room1, 1=room2)
$26  KEY_MAP      M key flag (open map)
$27  ROB0_X       room 1 robot tile X
$28  ROB0_Y       room 1 robot tile Y
$29  ROB0_DIR     room 1 robot direction (0=left 1=right)
$2A  ROB1_X       room 2 robot tile X
$2B  ROB1_Y       room 2 robot tile Y
$2C  ROB1_DIR     room 2 robot direction
$2D  ROB_TMR      robot movement timer (shared, 20-frame period)
```

Next free zero-page slot: `$2E`

## Room Map

The playfield (screen rows 2–23) is a PETSCII schematic top-down map, 22 rows × 40 chars. Player tile grid is 10×10 (X: 0–9, Y: 0–9).

| Char | Meaning | Colour |
|------|---------|--------|
| `+` `G_HORIZ_BAR` `G_VERT_BAR` | Walls | Blue |
| `=` | Server racks | Yellow |
| `#` | Crates | Orange |
| `!` | Laser wall (column 18, tile X=6 — kills player on contact) | Lt Red |
| `T` | Terminal (press T nearby to access; proximity: PLR_X 1–3, PLR_Y 3–5) | Lt Green |
| `[D1]` `[D2]` | Drone positions | Lt Green |

## HUD Layout (row 0, 40 chars)

```
00:00:00 human reactor:[========]  99%
^      ^ ^   ^ ^      ^^       ^^  ^
0      7 9  13 15    23 24    31 33 36
```

## Visual Style

- Tilted top-down oblique 2.5D perspective (similar to *Cadaver* / *The Last Ninja*)
- VIC-II hardware sprite priority flag used for depth: sprite priority flips when the player walks "behind" tall tiles
- Color palette: C64 dark registers (dark grays, muted blues, deep browns) with high-contrast multi-color tiles
- Flip-screen room transitions (no scrolling); screen RAM blasted per transition
- Charset: default uppercase/graphics set (`$D018` left at KERNAL default `$14`, charset at `$1000`); `$0291 = $0E` written at init

## Custom Charset / Screen Art (planned, not yet wired in)

Room/HUD art is being redone with **vchar64** (charset + screen + colour editor), replacing the current hand-authored PETSCII strings in `ROOM_DATA`/`ROOM2_DATA`. Nothing below is integrated yet — this documents the agreed plan.

- **Export format: ASM**, not BIN/PRG. Fits the existing convention (sprites/room data are already inline `!byte`/`!pet` literals in source); avoids managing binary blobs, load-header stripping, or Makefile/Exomizer changes for extra files.
- vchar64 labels its ASM export "ACME-compatible" but it isn't: it emits `.byte` (64tass/KickAssembler syntax), which ACME rejects. **Every export needs `s/^\.byte/!byte/` before inclusion**, plus a `* = $ADDR` origin line (vchar64 doesn't emit one). Verified: after that fix, a 2048-byte charset export assembles to the expected 2050-byte prg.
- **Free memory for the charset:** code currently ends around `$1DB9`; sprites/room data start at `$3F00`. That leaves `$1E00–$3EFF` (~8 KB) open. Planned charset origin: `$2800` (2K-aligned, clear of both ends). `$D018` would become `$18` (screen at `$0400`, charset bank at `$2800`).
- **Screen/colour canvases are authored at 25 rows** in vchar64 but only 22 are needed at runtime (2 HUD rows + 1 status row are drawn by game code, not part of the room art) — crop to 22 rows in vchar64 before exporting rather than trimming bytes at build time.
- **Tile-code collision hazard:** `game.asm` (~line 449-459) switches on specific PETSCII byte values to decide wall/rack/crate/laser/door behavior (space, `+`, `G_HORIZ_BAR`, `G_VERT_BAR`, `=`, `#`, `!`, `[`, `]`). If the new charset draws these elements using different byte codes, that switch table must be updated to match, or the visuals will no longer collide correctly. Confirm code-to-meaning mapping before wiring in real room art.

## Critical Gotchas

### CLS wipes both sprite pointers
`CLS` clears all 1024 bytes of screen RAM (`$0400–$07FF`), which includes the sprite pointer table at `$07F8–$07FF`. After **every** `CLS` call, immediately restore both pointers:
```asm
jsr CLS
lda #$FD : sta SPRPTR      ; spr0 → $3F40
lda #$FC : sta SPRPTR+1    ; spr1 → $3F00
```
`CLEAR_ROOM` (which clears only rows 2–23, `$0450–$07BF`) does **not** reach `$07F8` and does not need a restore.

### No anonymous or local labels
ACME anonymous labels (`-` and `+`) scope to the entire zone, not the subroutine — with many routines in one file they resolve to wrong targets silently. Local labels (`.foo`) also caused duplicate-definition errors across routines in the same zone. **All labels are explicit global names** (e.g. `CLSP`, `HUDST1`, `TSETB1`).

### Sound must tick every frame including during death timer
`SOUND_TICK` is called at the **top** of `DO_GAME`, before the death-timer branch, so it runs on every game frame. If called only from `GAME_ALIVE`, it never fires once the laser hit sets `DEATH_TMR`, leaving the SID gate open indefinitely.

### Keyboard matrix — key positions
```
T key (terminal): col 2 (PA=$FB), row 4 (PRB bit 4 = mask $10, active low)
M key (map):      col 4 (PA=$EF), row 4 (PRB bit 4 = mask $10, active low)
Return:           col 1 (PA=$FD), row 1 (PRB bit 1 = mask $02, active low)
F7 (exit):        col 7 (PA=$7F), row 4 (PRB bit 3 = mask $08, active low)
```
Terminal menu navigation uses `GETIN` (KERNAL keyboard buffer) for PETSCII codes: `$11`=cursor down, `$91`=cursor up, `$0D`=Return, `$88`=F7.

### Sprite data placement
Two sprites are placed at fixed 64-byte-aligned addresses before `ROOM_DATA`:
- `* = $3F00` → `SPR_ROBOT` (sprite 1, pointer `$FC`)
- `* = $3F40` → `SPR_PLAYER` (sprite 0, pointer `$FD`)

No runtime copy loop. Both pointer bytes at `$07F8`/`$07F9` must be set at init and restored after every `CLS`.

### Sprite collision register clears on read
`VIC_SPCOLL` (`$D01E`) is cleared by the hardware the moment it is read. Read it exactly once per frame in `CHECK_SPRITE_HIT` and act on the value immediately — reading it again will always return 0.

## SID / Music

### Background music
`music/armalyte.prg` is the Armalyte SID tune (Martin Walker, 1988 Thalamus), stripped to load at `$C000–$CF81`.

- **Init:** `lda #0 : jsr $C000` — called once during startup (after SID clear, before `cli`). `A` must be 0 to select song 1. Sets `$D418 = $0F` (full volume) internally.
- **Play:** `jsr $C059` — called from `RASTER_IRQ` every frame (50 Hz PAL).
- **Death sound interlock:** `RASTER_IRQ` skips the `$C059` call while `SND_TMR > 0`, giving the death sound exclusive SID control for its ~1 second sweep. Music resumes automatically when `SND_TMR` reaches 0.

### Armalyte player does NOT manage $D418
**Critical:** In normal play mode (`$C057 = $FF`, `$C058 = $FF`), the `$C059` routine skips all volume code and jumps directly to `$C089` (the main SID register update loop). It never touches `$D418`. The master volume is set once by `$C000` init to `$0F` and must be maintained by our code.

**Rule:** Never write `$00` to `$D418` without immediately restoring it to `$0F`. Any write of `$D418 = 0` permanently silences music until `$C000` is called again (which only happens on cold start).

- `SNDOFF` restores `$D418 = $0F` after gating off voice 1 — do not zero it here
- `SETUP_GAMEOVER` and `SETUP_WIN` must not write to `$D418` — let music continue
- `SND_TMR` is zeroed explicitly in the init before `cli` — the KERNAL may leave `$1E` non-zero, which would permanently block music in intro

### Death sound effect
Voice 1, sawtooth wave. `SOUND_DEATH_START` gates on at ~350 Hz and sets `$D418 = $0F`. `SOUND_TICK` (called every game frame from the top of `DO_GAME`) sweeps frequency downward over 50 frames, then gates off and restores `$D418 = $0F`.

## Screen Art

Non-game screens (intro, game over, win) use a PETSCII box design: rows 3–13 form a bordered panel drawn at 50 Hz by the relevant setup routine. All three share the subroutine `DRAW_INTRO_SCREEN` for the intro layout (called from `SHOW_INTRO`, the `DO_GAMEOVER` restart path, and the `DO_WIN` restart path).

### Shared string labels (each exactly 40 bytes)
- `SCR_BORDER_TOP` — rounded top border (`G_RD_UL` + 38 × `G_HORIZ_BAR` + `G_RD_UR`)
- `SCR_BORDER_BOTTOM` — rounded bottom border (`G_RD_LL` + 38 × `G_HORIZ_BAR` + `G_RD_LR`)
- `SCR_BLANK` — `G_VERT_BAR` + 38 spaces + `G_VERT_BAR` empty interior row
- `ITR_SEP` — `G_VERT_BAR  ==...==  G_VERT_BAR` separator (reused by all three screens)

All string-copy loops call `jsr PET2SCREEN` to convert PETSCII to screen codes before writing to screen RAM. `PET2SCREEN` is defined in `src/titanfall.asm` after `CLS`.
- `ITR_TITLE`, `ITR_TAG`, `ITR_M1`–`ITR_M3` — intro panel content
- `GO_TITLE`, `GO_M1`–`GO_M3` — game over panel content
- `WIN_TITLE`, `WIN_M1`–`WIN_M3` — win panel content
- `TXT_PRESS`, `TXT_GOPRESS`, `TXT_WINPRESS` — blinking footer prompts

Star characters (`*`) in each title are recoloured to YELLOW after the row loop by writing to individual CRAM addresses.

## What's Not Yet Implemented

- Actual drone control / robot mode (drone proxy mechanic from design doc)
- Access chip system (chips found by searching desks/lockers)
- Clock penalty on death (currently DEATH_TMR just leads to game over, no time deduction)
- Robot patrol paths drawn in room data (currently pure sprite movement, no tile-level representation)
- More than 2 rooms / sector navigation beyond the current prototype
