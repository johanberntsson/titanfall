# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Commodore 64 game called **TITAN Fall** (working title) — a cinematic infiltration puzzle thriller in the vein of *Impossible Mission* and *Paradroid*. The player infiltrates an automated missile launch complex and must subvert its drone workforce to stop a launch countdown. The game is targeted at PAL/NTSC C64 hardware. See `gamedesign.md` for the full design document.

## Build & Run

```
acme -f cbm -o titanfall.prg src/titanfall.asm   # assemble
x64sc titanfall.prg                                # run in Vice
```

Assembler: **ACME 0.97** (`-f cbm` produces a standard `.prg` with a 2-byte load address header).  
Emulator: **x64sc** (Vice).

## Code Layout

- `src/titanfall.asm` — single source file; entry point at `$0810` (SYS 2064)
- `titanfall.prg` — assembled output (load address `$0801`, not committed)

### BASIC stub convention

Every `.asm` file must begin with the standard BASIC loader at `* = $0801`:

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
| `$0810` | Entry point |
| `$0400–$07FF` | Screen RAM (default VIC bank) |
| `$D800–$DBFF` | Colour RAM |
| `$07F8` | Sprite pointer table (end of screen RAM — **must be restored after every CLS call**) |
| `$3F40` | Sprite 0 data (64-byte aligned, pointer `$FD`) — placed by assembler with `* = $3F40` |

## Core Design Constraints

When implementing code, always respect these C64 hardware limits:

- **CPU:** MOS 6510 (6502 derivative); assembler is **ACME** (not cc65, not KickAssembler)
- **VIC-II sprites:** Exactly 8 hardware sprites available — the design intentionally avoids a sprite multiplexer
- **Room layout:** 20×12 grid of 16×16 pixel meta-tiles = 240 bytes per room; rooms must fit this model
- **Memory:** 64 KB total; code, data, and screen RAM must all fit within the standard C64 memory map
- **SID chip:** 3 voices for audio

## State Machine

`GAME_STATE` (`$1A`) holds the current state. The main loop syncs to a raster IRQ at line 50 (~50 Hz PAL); `TICK_FLAG` is set by the IRQ and cleared each frame by `MAIN_LOOP`.

| Value | State | Description |
|-------|-------|-------------|
| 0 | Intro | Title screen, tagline, blinking "press any key" prompt |
| 1 | Game | Playfield with HUD, player sprite, room map, countdown clock, reactor meter |
| 2 | Game over | 2-second red border flash after laser hit, then game-over screen |
| 3 | Terminal | Overlay menu for drone selection (entered by pressing T near terminal) |

**Stack discipline:** The state machine uses fall-through / `jmp` between states, not `jsr`/`rts`. `MAIN_LOOP` is entered by falling through from init code, never by `jsr`. State transitions use `jmp SETUP_*` not `jsr`, so the return address on the stack is always the one from `DISPATCH`'s `jsr TICK_*`. Never `jsr` into anything that falls into `MAIN_LOOP`.

## Gameplay Architecture

The game has two distinct active modes sharing a single 6-hour countdown timer:

1. **Human mode** — player explores rooms, scavenges for Access Clearance Chips (levels 1–4) and Direct Override Codes (robot serial numbers)
2. **Robot/proxy mode** — activated at mainframe terminals; the human sprite freezes and the player controls a drone remotely

Key state to track:
- Countdown timer (real-time, starts at 6 hours; –10 min penalty per human death)
- Inventory: access chips and robot serial codes
- Per-room: 240-byte tile array, active sprite positions, patrol paths
- Active mode (human / drone) and which drone serial is linked

## Drone Types

Three drone classes with distinct capabilities (treat as puzzle keys, not combat units):
- **Industrial Loader Bot (BOT-7741)** — immune to lasers and cryogenic hazards; can push heavy objects
- **Maintenance Splicer (BOT-3312)** — fits through 1-tile ventilation ducts; can short-circuit junction boxes
- **Suppressor Centurion (BOT-9901)** — armed; used only in sectors flooded with hostile rogue drones (locked — requires access chip)

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
$1A  GAME_STATE   0=intro 1=game 2=gameover 3=terminal
$1B  DEATH_TMR    frames remaining after laser hit
$1C  BLINK_TMR    blink frame counter
$1D  BLINK_ST     blink state (0=visible 1=hidden)
$1E  SND_TMR      death sound countdown (0=silent)
$1F  TERM_SEL     terminal selected drone row (0-2)
$20  TERM_TMR     terminal link confirmation countdown
$21  NEAR_TERM    non-zero when player is adjacent to terminal
$22  KEY_F1       T key flag (enter terminal)
$23  KEY_RET      Return key flag
$24  KEY_ESC      F7/Escape key flag
```

## Room Map

The playfield (screen rows 2–23) is a PETSCII schematic top-down map, 22 rows × 40 chars. Player tile grid is 10×10 (X: 0–9, Y: 0–9).

| Char | Meaning | Colour |
|------|---------|--------|
| `+ - \|` | Walls | Blue |
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
- Charset: VIC set to lowercase (`$D018 = $16`, charset at `$1800`); KERNAL flag `$0291 = $0E` prevents IRQ handler from resetting it

## Critical Gotchas

### CLS wipes the sprite pointer table
`CLS` clears all 1024 bytes of screen RAM (`$0400–$07FF`), which includes the sprite pointer table at `$07F8`. After **every** `CLS` call, immediately restore the pointer:
```asm
jsr CLS
lda #$FD : sta SPRPTR   ; $3F40/64 = $FD — always restore after CLS
```

### No anonymous or local labels
ACME anonymous labels (`-` and `+`) scope to the entire zone, not the subroutine — with many routines in one file they resolve to wrong targets silently. Local labels (`.foo`) also caused duplicate-definition errors across routines in the same zone. **All labels are explicit global names** (e.g. `CLSP`, `HUDST1`, `TSETB1`).

### Sound must tick every frame including during death timer
`SOUND_TICK` is called at the **top** of `DO_GAME`, before the death-timer branch, so it runs on every game frame. If called only from `GAME_ALIVE`, it never fires once the laser hit sets `DEATH_TMR`, leaving the SID gate open indefinitely.

### Keyboard matrix for T key (terminal entry)
T key: column 2 (`CIA1_PRA = $FB`), row 4 (`CIA1_PRB bit 4`, active low).
```asm
lda #$FB : sta CIA1_PRA
lda CIA1_PRB : and #$10 : bne NOT_PRESSED
```
Terminal menu navigation uses `GETIN` (KERNAL keyboard buffer) for PETSCII codes: `$11`=cursor down, `$91`=cursor up, `$0D`=Return, `$88`=F7.

### Sprite data placement
Sprite data is placed at a fixed 64-byte-aligned address using `* = $3F40`. No runtime copy loop. The pointer byte at `SPRPTR` (`$07F8`) must be `$3F40 / 64 = $FD`.

## SID Death Sound

Voice 1, sawtooth wave. `SOUND_DEATH_START` gates on at ~350 Hz. `SOUND_TICK` (called every game frame) sweeps frequency downward over 50 frames (~1 second PAL), then gates off.

## What's Not Yet Implemented

- Actual drone control / robot mode (drone proxy mechanic from design doc)
- Access chip system (chips found by searching desks/lockers)
- Multiple rooms / sector navigation
- Drone patrol animation on screen
- Clock penalty on laser hit (currently just kills player)
- Win condition (reach the launch control terminal and abort)
- Music
