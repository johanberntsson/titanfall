# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Commodore 64 game called **TITAN Fall** (working title) — a cinematic infiltration puzzle thriller in the vein of *Impossible Mission* and *Paradroid*. The player infiltrates an automated missile launch complex and must subvert its drone workforce to stop a launch countdown. The game is targeted at PAL/NTSC C64 hardware. See `design/gamedesign.md` for the full design document — it is partly out of date but is kept as a source of ideas for future features; this file and `titan.yaml` describe what is actually implemented.

## Build & Run

```
make        # generate world.asm + assemble + pack
make run    # generate, assemble, pack, and launch in Vice
make clean  # remove game.prg, titanfall.prg and the generated src/world.asm
```

The build is three steps handled by the Makefile:
1. **tools/genworld.py** (Python 3 + PyYAML) generates `src/world.asm` from `titan.yaml` — all world data tables (rooms, actors, items, doors, lasers, terminal zones) plus the room map data converted from the vchar64 exports
2. **ACME 0.97** assembles `src/titanfall.asm` → `game.prg` (`-f cbm`, 2-byte load header)
3. **Exomizer** packs `game.prg` + the music PRG into a self-extracting `titanfall.prg`

Emulator: **x64sc** (Vice). Do not run `acme` directly; always use `make`.

**`src/world.asm` is generated — never edit it** (it's in `.gitignore` and `make clean` removes it). To change rooms, robots, items, doors, lasers, the starting clock, or the death penalty, edit `titan.yaml` and rebuild. `tools/genworld.py` validates the config (unknown room/item references, >2 robots per room, over-long strings, etc.) and fails the build with a clear message.

## Code Layout

The source is split into one orchestrator and eight state/data modules, all `!source`d into a single ACME assembly pass:

| File | Contents |
|------|----------|
| `src/titanfall.asm` | Constants, BASIC stub, entry point, `MAIN_LOOP`, `CLS`, `RASTER_IRQ`, shared strings, the sprite block; `!source`s all other modules including the generated `world.asm` |
| `src/intro.asm` | `DO_INTRO`, `DRAW_INTRO_SCREEN`, `BLINK_ON/OFF`, intro strings |
| `src/titanfall_title.asm` | `TITLE_SCR`/`TITLE_COL` — the 8-row "TITAN FALL" block-letter logo on the intro screen (data only; `!source`d after the sprite block, not in the code area). Reference image: `screenshots/titanfall_title.png` |
| `src/game.asm` | `DO_GAME`, `SETUP_GAME`, HUD, clock, reactor, player/robot movement, sound |
| `src/gameover.asm` | `DO_GAMEOVER`, `SETUP_GAMEOVER`, `GO_BLINK` helpers, strings |
| `src/win.asm` | `DO_WIN`, `SETUP_WIN`, `WIN_BLINK` helpers, strings |
| `src/terminal.asm` | `SETUP_TERMINAL`, `DO_TERMINAL`, `TERM_DRAW_SEL`, `CLEAR_ROOM`, strings |
| `src/map.asm` | `DO_MAP`, `SETUP_MAP`, map strings |
| `src/popup.asm` | `DO_POPUP`, `SHOW_POPUP`, `SETUP_SEARCH`, `SETUP_DOOR_LOCKED`, popup strings |
| `src/c64_walker_sprites.asm`, `src/c64_robot_sprites.asm`, `src/c64_drone_sprites.asm` | Multicolour sprite sets (player / walking robot / flying drone), `!source`d into the sprite block at `$3000`. All three have all four facings (robots need up/down too — the terminal lets you drive them in any direction) |
| `src/charset.asm` | `TILE_COLORS` (256-byte tile→colour table) and `CHARSET` (custom 2K charset at `$2800`), generated from `graphics/*.s` — see "Custom Charset / Screen Art" |
| `src/world.asm` | **Generated** by `tools/genworld.py` from `titan.yaml` (data only, no code): `NUM_*`/`ACTOR_*`/`ITEM_*`/`CFG_*` constants, `ROOM_*`/`TYPE_*`/`ACT_*`/`ITEM_*`/`DOOR_*`/`LASER_*`/`TERMZ_*`/`MAPHL_*` tables, `ROOM_MAP_n` screen-code data, and the runtime state arrays (`ACT_X/Y/TGT/ALIVE/DIR/ANIM`, `GL_PXL/PXH/PY`, `ITEM_STATE`, `LASER_STATE`, `SPR_SLOT_ACT`) |

Other files:
- `titan.yaml` — **the world definition** (rooms, robots, items, doors, lasers, terminals, start clock); the preferred place to change gameplay content
- `tools/genworld.py` — build-time generator `titan.yaml` → `src/world.asm`
- `graphics/` — vchar64 project files (`.vchar64proj`) and their raw ASM exports (`.s`); source of truth for room art, edited in vchar64 and re-exported, not hand-edited
- `game.prg` — intermediate assembled output (not committed)
- `titanfall.prg` — final self-extracting packed output (not committed)
- `music/Licence_to_Kill.prg` — the SID music binary packed into the build (load `$C000–$CFFF`; see "SID / Music")
- `music/Licence_to_Kill.sid` / `.info` — source SID file and its sidplayfp info dump
- `music/armalyte.prg` — the previous tune, kept as an alternative (same `$C000` load address, but play is `$C059` not `$C127`)
- `music/find_sids_in_range.py`, `music/possible_songs.txt` — HVSC scan for tunes that fit `$C000-$CFFF`; `music/lok_disasm.asm`/`lok_raw.bin` — disassembly of the Licence to Kill player

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
| `$0810` | Entry point / code start (code + `TILE_COLORS` end before `$2800`) |
| `$0400–$07FF` | Screen RAM (default VIC bank) |
| `$2800–$2FFF` | `CHARSET` — custom 2K room-art charset (see below) |
| `$D800–$DBFF` | Colour RAM |
| `$07F8` | Sprite pointer table (end of screen RAM — **must be restored after every CLS call**) |
| `$3000–$38FF` | Sprite frames (36 × 64 bytes, pointers `$C0–$E3`): player 12, robot 12, drone 12 — see "Sprites" |
| `$3900` | Generated world data (`src/world.asm`): tables, room maps, runtime state arrays — follows the sprite block, grows with content, must stay below `$C000` |
| `$C000–$CFFF` | Licence to Kill SID music (init `$C000`, play `$C127`; loaded by exomizer) |

## Core Design Constraints

When implementing code, always respect these C64 hardware limits:

- **CPU:** MOS 6510 (6502 derivative); assembler is **ACME** (not cc65, not KickAssembler)
- **VIC-II sprites:** Exactly 8 hardware sprites available — the design intentionally avoids a sprite multiplexer
- **Room layout:** 22 rows × 40 chars (custom charset, screen codes) per room; the walkable tile grid is per-room (`bounds:` in `titan.yaml` → `ROOM_MAXX/Y`) — both rooms are 13×10 (X 0–12, Y 0–9) since their art spans the full 40 columns; the 13th X tile reaches the room's actual right wall, which the shared 24px/tile pitch (see `TILE_TO_PIXEL_X`) doesn't cover in only 10 tiles
- **Memory:** 64 KB total; code, data, and screen RAM must all fit within the standard C64 memory map
- **SID chip:** 3 voices for audio

## State Machine

`GAME_STATE` (`$1A`) holds the current state. The main loop syncs to a raster IRQ at line 50 (~50 Hz PAL); `TICK_FLAG` is set by the IRQ and cleared each frame by `MAIN_LOOP`.

| Value | State | Description |
|-------|-------|-------------|
| 0 | Intro | Title screen, tagline, blinking "press any key" prompt |
| 1 | Game | Playfield with HUD, player sprite, room map, countdown clock, reactor meter |
| 2 | Game over | Red border + descending-pitch sound, then game-over screen |
| 3 | Terminal | Full-screen drone selection menu (Space near terminal; time paused; sprite hidden) |
| 4 | Win | Mission complete screen (reached via bottom exit in room 2) |
| 5 | Map | Sector map overlay (M key; time paused; sprite hidden; any key to return) |
| 6 | Popup | "Found item" or "door locked" popup (Space at a search spot, or blocked at a locked door; time/robots paused; a fresh Space press closes it — see the popup section) |

**Stack discipline:** The state machine uses fall-through / `jmp` between states, not `jsr`/`rts`. `MAIN_LOOP` is entered by falling through from init code, never by `jsr`. State transitions use `jmp SETUP_*` not `jsr`, so the return address on the stack is always the one from `DISPATCH`'s `jsr TICK_*`. Never `jsr` into anything that falls into `MAIN_LOOP`.

**Dispatch uses `bne`+`jmp` pairs, not `beq`.** The `DO_*` handlers live in `!source`d files assembled after `CLS`/`RASTER_IRQ`/shared strings, placing them beyond the ±127-byte range of a `beq`. The dispatch reads: `bne MLNOT0 : jmp DO_INTRO` etc.

**State ≠ 1 guard in GAME_ALIVE:** After `MOVE_PLAYER` and `READ_KEYS`, `GAME_ALIVE` checks `lda GAME_STATE : cmp #1 : bne GAME_TICK_DONE`. This skips sprite update / HUD / status draws whenever any other state (3 terminal, 4 win, 5 map, 6 popup) was entered mid-frame. It used to be `cmp #4 : bcs`, which let the terminal (state 3) through: `UPDATE_ROBOT_SPRITES` then re-enabled the robot sprites right after `SETUP_TERMINAL` had cleared `VIC_SPEN`, so robots stayed visible over the terminal screen.

## Gameplay Architecture

The game has two distinct active modes sharing a single countdown timer:

1. **Human mode** — player explores rooms, scavenges for Access Clearance Chips (levels 1–4) and Direct Override Codes (robot serial numbers)
2. **Robot/proxy mode** — activated at mainframe terminals; the human sprite freezes and the player controls a drone remotely

`PLAYER_MODE` (`$31`) implements this generically: **0 = human control, otherwise (actor index + 1) = that actor is player-driven**. Robots are entries in the generated actor tables (`ACT_*` in `world.asm`); the splicer is `ACTOR_BOT3312` (equate from `id: bot3312` in `titan.yaml`).
- Selecting bot-3312 in the terminal (`TERM_LINK_SPLICER` in `terminal.asm`) sets `PLAYER_MODE=ACTOR_BOT3312+1` and jumps straight back into gameplay via the shared `TERM_ABORT` exit path — no extra confirmation keypress.
- While `PLAYER_MODE≠0`, `MOVE_PLAYER` (`game.asm`) dispatches to `MOVE_ACTOR`, which moves `ACT_X/Y` of actor `PLAYER_MODE-1` — WASD/joystick drive the robot, clamped to its own room's `ROOM_MAXX/Y` bounds; no doorway checks (robots can't leave their room); the human sprite stays frozen at its last `PLR_X/Y`. Driving into an active laser destroys both robot and laser — see "Lasers can be destroyed by a driven robot".
- `TICK_ROBOT` skips the patrol step for the player-driven actor (index+1 == `PLAYER_MODE`) so the AI doesn't fight manual control.
- `CHECK_SPRITE_HIT` ignores player-sprite collisions while `PLAYER_MODE≠0` (the human is standing safely at the terminal); it still reads `VIC_SPCOLL` every frame regardless of mode so the hardware latch doesn't accumulate a stale hit for when control returns to human.
- The **X key** (`KEY_X`, checked at the end of `READ_KEYS`) exits proxy mode at any time, setting `PLAYER_MODE=0` back to human control. It is the only way out mid-link: both Space actions (terminal and search) are gated on `PLAYER_MODE=0` — a player-driven robot can't use equipment, and the frozen human still standing in the terminal zone must not re-trigger the terminal. The terminal menu's **logoff** entry (`TERM_LOGOFF`) still clears `PLAYER_MODE` but is only reachable in human mode.
- `DRAW_HUD_DYNAMIC` and `DRAW_STATUS` both branch on `PLAYER_MODE` to show "robot"/`ACT_X/Y` instead of "human"/`PLR_X/Y`.

Key state to track:
- Countdown timer (real-time; configurable penalty and respawn per human death, see "Death & Respawn"; Game Over only when the clock hits zero)
- Inventory: `ITEM_STATE` array (0=hidden 1=carried 2=used), one byte per config item
- Per-actor: `ACT_X/Y` (position), `ACT_TGT` (patrol waypoint), `ACT_ALIVE`
- Per-laser: `LASER_STATE` (0=active 1=destroyed)
- Active mode (human / drone) and which actor is linked (`PLAYER_MODE`)

## Rooms

Rooms are defined in `titan.yaml`; `CUR_ROOM` (`$25`) indexes the generated `ROOM_*` tables. Two rooms are currently configured (room1: terminal, laser wall at X=6, search spot at (9,5), left door to room2; room2: right door back, locked bottom exit to the win screen).

Movement is fully table-driven (`MOVE_PLAYER`/`TRY_MOVE` in `game.asm`):
- **Bounds:** each room has its own `ROOM_MAXX`/`ROOM_MAXY` (both current rooms are 13 tiles wide, X 0–12 — match `max_x` to the art's right wall when adding a room; see the `TILE_TO_PIXEL_X` gotcha).
- **Doors** (`DOOR_*` tables) are rectangles *one tile outside* the walkable range (e.g. `x: -1` on a left wall, `y: 10` on a bottom wall, encoded `$FF`/`$0A`). A move landing inside a door rect triggers it: locked check first (`DOOR_KEY` = item index+1, 0=none; locked shows the popup and acts like a wall), then either the win screen (`DOOR_DEST=$FF`, `leads_to: exit`) or a room change (`DOOR_AX/AY` set the arrival position; `$FF` = keep current coordinate). Anything out of bounds that isn't a door is a wall.
- **Lasers** (`LASER_*` tables) are rectangles inside the room; `LASER_AT` checks the attempted position against every active laser in the current room. The human dies without entering the tile; a player-driven robot enters the tile and `ROBOT_LASER_DEATH` destroys both robot and laser.

Doorway transitions call `DRAW_ROOM`, which blits 22×40 chars via the `ROOM_MAP_LO/HI` pointer tables and then calls `ASSIGN_SPRITES` to remap the new room's actors onto hardware sprites 1–2.

### Adding content (config-only recipes)

- **New room:** author the art in vchar64 (22×40, shared charset — see `graphics/README.txt`), export the map as ASM, add a `rooms:` entry in `titan.yaml` (name, `vchar64_map`, `bounds`, `player_start`, `map_view`) plus doors linking it to its neighbours (a door in each direction of travel, one per room). Until the sector-map art is generated, also extend the `MAP_R*` strings in `src/map.asm` by hand.
- **New hidden item:** add an entry under `items:` (label ≤12 chars, found_text ≤30 chars) and place it with a `things:` entry in a room. Lock any door with `key: <item>`.
- **New robot:** add a `robots:` entry in a room (`type`, `start`, two-point `patrol`; ≤2 robots per room). Give it an `id:` if code needs to reference it (emitted as `ACTOR_<ID>`). A new *type* needs an `actor_types:` entry, a sprite data block in `titanfall.asm` (64-byte aligned, referenced by label), and — until more AI exists — `ai: patrol`.
- **New laser / terminal zone:** one line under the room's `lasers:` / `terminals:`.
- Check the room art visually matches the config rectangles — nothing validates art against logic.

## Drone Types

Three drone classes with distinct capabilities (treat as puzzle keys, not combat units):
- **Industrial Loader Bot (BOT-7741)** — immune to lasers and cryogenic hazards; can push heavy objects
- **Maintenance Splicer (BOT-3312)** — fits through 1-tile ventilation ducts; can short-circuit junction boxes
- **Suppressor Centurion (BOT-9901)** — armed; used only in sectors flooded with hostile rogue drones (locked — requires access chip)

## Sprites

All sprites are **multicolour** (`$D01C = $07`): `$D025` (MC0, `%01`) = black and `$D026` (MC1, `%11`) = light grey are shared; each sprite's own colour (`%10` — the player's skin, a robot's visor/lights, the drone's eye/thruster) comes from the actor type's `color:` in `titan.yaml` (`TYPE_COLOR`).

| Set | File | Frames | Used by (`titan.yaml` type) |
|-----|------|--------|-----------------------------|
| Walker | `src/c64_walker_sprites.asm` | 12: down/up/left/right × rest/walk1/walk2 | `human` (player, light red) |
| Robot | `src/c64_robot_sprites.asm` | 12: down/up/left/right × rest/walk1/walk2 | `sentry` (orange), `splicer` (green) — room 1 |
| Drone | `src/c64_drone_sprites.asm` | 12: down/up/left/right × hover/move1/move2 | `drone` (yellow) — room 2 |

The three files are `!source`d back-to-back into one block at `* = $3000` (right after the charset, still in VIC bank 0) — each frame is 64 bytes, so they stay 64-byte aligned as long as every file holds whole frames. **Commenting frames in or out shifts everything after them**; that's fine because everything addresses frames by label (`sprite:` in `titan.yaml`, `SPRP_*` equates), never by hard-coded pointer value.

**Frame selection** (`FRAME_PTR` in `game.asm`): pointer = `TYPE_SPRPTR + (facing − TYPE_DIR0)*3 + frame`. Per actor type in `titan.yaml`:
- `sprite:` — label of the type's first frame
- `directions: 4` (default; facings `DIR_DOWN/UP/LEFT/RIGHT` = 0–3) or `2` (left/right only → `TYPE_DIR0=2`; `ACT_FACE` ignores up/down, so the actor keeps its last horizontal facing while moving vertically). All current types use 4 — robots need up/down poses because a robot taken over at the terminal can be driven in every direction; `directions: 2` is only for a future type with a left/right-only sprite set.
- `anim: walk` (default — frame advances rest→walk1→walk2→walk1… once per tile step, back to rest when a step doesn't happen: idle player, patrol waypoint pause) or `hover` (ignores steps; loops hover/move1/hover/move2 off the free-running `ANIM_CNT`, 8 frames per pose)

State: player `PLR_DIR`/`PLR_ANIM` (zero page); actors `ACT_DIR`/`ACT_ANIM` (runtime arrays in `world.asm`, reset by `RESET_ROUND`). The facing is set on every move *attempt* (so walking into a wall turns you), the walk frame only on a committed step (incl. walking through a door). `UPDATE_SPRITE0` / `UPDATE_ROBOT_SPRITES` write the frame pointer into `$07F8–$07FA` every frame; `ASSIGN_SPRITES` sets each slot's colour (and an initial pointer) on room entry. `ATYPE_<NAME>` constants (e.g. `ATYPE_HUMAN`) are emitted by `genworld.py`.

After every `CLS` the pointers are reset to `SPRP_PLAYER`/`SPRP_ROBOT`/`SPRP_DRONE` (just sane defaults — the per-frame update replaces them). `VIC_SPEN` is set to `$07` during game state (`UPDATE_ROBOT_SPRITES` clears the bits of unused/dead/off-room slots every frame), `$00` in all other states.

### Actors and patrol AI
All robots are rows in the generated `ACT_*` tables (the player is *not* in them; `PLAYER_MODE` maps "actor index+1" onto them for proxy mode). Static data per actor: `ACT_TYPE` (indexes `TYPE_SPRPTR`/`TYPE_COLOR`), `ACT_ROOM`, `ACT_SX/SY` (start), `ACT_WX0/WY0`/`ACT_WX1/WY1` (two patrol waypoints). Runtime state: `ACT_X/Y`, `ACT_TGT` (which waypoint it's heading for), `ACT_ALIVE`.

`TICK_ROBOT` is called every game frame (shared `ROB_PERIOD` = 24-frame timer, `ROB_TMR`) and runs `ACTOR_PATROL_STEP` for every alive, non-player-driven actor — one step toward the current target waypoint (X axis first, then Y; on arrival the target flips). Actors in other rooms keep patrolling off-screen. Patrol paths are authored in `titan.yaml` not to cross lasers — the patrol AI does no hazard checks.

**Smooth movement (gliding).** Logic stays tile-based (`PLR_X/Y`, `ACT_X/Y` — collisions with walls/doors/lasers/terminals/items are all per tile), but sprites don't jump a whole tile (24×16 px) per step. Each sprite has its own pixel position in `GL_PXL`/`GL_PXH`/`GL_PY` (runtime arrays in `world.asm`, `NUM_ACTORS+1` long: slot = actor index, last slot `GL_PLAYER` = the human), and `GLIDE` (`game.asm`) moves it `GL_SX`/`GL_SY` px per frame toward the pixel position of its tile, clamping so it never overshoots. Speeds are matched to the step periods so a glide finishes just as the next step starts:
- player, and a player-driven robot: one step per `MOVE_PERIOD` = 8 frames, glide `GL_FAST_X/Y` = 3/2 px per frame (24/8, 16/8) → continuous walking with no stop at each tile
- patrolling robots: one step per `ROB_PERIOD` = 24 frames, glide `GL_SLOW_X/Y` = 1/1 px per frame (a vertical step finishes after 16 frames and waits)
- `SNAP_ALL` (called by `DRAW_ROOM` — room change, respawn, redraws after terminal/map/popup) jumps every sprite straight to its tile, so nothing glides across a room change.
If you change a step period, change the matching speeds (tile pitch / period) or the glide will lag behind or stall. Hardware sprite collisions (`$D01E`) use the glided positions, i.e. what's on screen. A robot that drives into a laser finishes its glide into the beam before it is destroyed (see "Lasers can be destroyed by a driven robot").

**Sprite mapping:** `ASSIGN_SPRITES` (called from the end of `DRAW_ROOM`) scans the actor table for actors in `CUR_ROOM` and assigns them to hardware sprites 1–2 (`SPR_SLOT_ACT`, 2 bytes, `$FF`=empty), setting each slot's sprite pointer and colour from the actor's type. `UPDATE_ROBOT_SPRITES` glides and positions both slots every frame; the glide *targets* use the shared `TILE_TO_PIXEL_X` formula (X pixel = `tile*24+28`, Y pixel = `tile*16+66`, per-slot `VIC_SP_MSB` bit from `GL_PXH` — see the "Extended (9-bit) sprite X" gotcha) and disables the `VIC_SPEN` bit for any slot that is empty, dead, or out of the room. `genworld.py` rejects configs with more than 2 robots in one room.

### Lasers can be destroyed by a driven robot
`LASER_STATE` (one byte per config laser, 0=active 1=destroyed) implements a one-way puzzle mechanic: driving any proxy-controlled robot into an active laser destroys both.
- `LASER_AT` (`game.asm`) is the shared test — carry set if `NEWX/NEWY` is inside an active laser rect of the current room, returning the laser index in `Y`. `TRY_MOVE` (human) and `TRY_ACT` (driven robot) both call it on every attempted move.
- On a robot hit, `TRY_ACT` doesn't destroy it yet: it sets `ACT_ALIVE=2` ("dying") and remembers the laser in `PEND_LSR`. A dying robot ignores input (`MOVE_ACTOR`) and patrol (`TICK_ROBOT` only moves `ACT_ALIVE=1`), and keeps gliding onto the laser tile; once its sprite arrives, `UPD_DYING` (from `UPD_SLOT`) calls `ROBOT_LASER_DEATH`, which sets that actor's `ACT_ALIVE=0` (sprite hidden for good, patrol suspended forever) and that laser's `LASER_STATE=1` (it stops killing the human too), erases the beam from the screen (`ERASE_LASER`, below), flashes the border yellow via `BFLASH`, and resets `PLAYER_MODE=0` (control snaps back to human without waiting for the X key).
- **Destroyed lasers disappear from the room art.** The room maps always have every laser drawn in, so `genworld.py` precomputes per laser a patch list (`LASER_ART_n`, via `LASER_ART_LO/HI`): every cell under the laser rect (its tiles' sprite footprint ±1 char row, to catch the emitters) whose screen code is in `art.laser_tiles` in `titan.yaml`, with its replacement — the char on both sides if they match (so a beam crossing a wall leaves the wall continuous), else `art.floor_tile`. `ERASE_LASER` (Y = laser index) writes those cells + their `TILE_COLORS` colour; it runs from `ROBOT_LASER_DEATH` and at the end of `DRAW_ROOM` for every destroyed laser in `CUR_ROOM` (so room changes / popup / map / terminal redraws keep it erased; `RESET_ROUND` re-arms lasers before redrawing, so a respawn brings the beam back). The build warns if a laser has no `laser_tiles` under it — usually art and config have drifted apart. New laser glyphs in the charset must be added to `laser_tiles`.
- The terminal blocks re-linking to a destroyed splicer: `TERM_LINK_SPLICER` in `terminal.asm` checks `ACT_ALIVE+ACTOR_BOT3312` and shows `TMSG_DEAD` instead of linking if it's already gone.

### Sprite collision
`CHECK_SPRITE_HIT` reads `VIC_SPCOLL` (`$D01E`) each frame after all three sprites are positioned. Bit 0 (sprite 0 / player) non-zero means the player overlapped any other enabled sprite. Response mirrors laser death: red border, `DEATH_TMR = DEATH_LEN`, `SOUND_DEATH_START` (the falling sweep; a laser death plays the zap with `DEATH_TMR = ZAP_LEN`). `$D01E` is cleared by the hardware on read. (With only 2 sprites the old code checked `bits 0-1`; with 3 sprites a robot-vs-robot collision could set bit 1 or 2 without the player involved, so only bit 0 is checked now.)

### Death & Respawn (Impossible Mission style)
Dying (laser or sprite collision, `DEATH_TMR` counting down to 0 in `DO_GAME`) no longer ends the game outright — it costs time and respawns you:
- `APPLY_DEATH_PENALTY` (`game.asm`) subtracts `CFG_PENALTY_M` minutes (`death_penalty_minutes` in `titan.yaml`) from `CLK_H:CLK_M:CLK_S`, clamped at `0:00:00` (borrows an hour into `CLK_M` when `CLK_M` is short; if `CLK_H` is also `0`, clamps straight to zero rather than going negative).
- If the clock is still nonzero after that, it calls `RESET_ROUND` to respawn: player position (start room's `ROOM_PSX/PSY`), all actors (`ACT_X/Y/TGT/ALIVE` from their start values), all lasers (`LASER_STATE=0` — destroyed lasers come back), `CUR_ROOM`, `PLAYER_MODE`, the reactor gauge, and the room/HUD redraw all reset to their fresh-game starting values — **except** the clock, which keeps the post-penalty value. Gameplay resumes immediately (`GAME_STATE` stays/returns to 1).
- If the penalty brings the clock to exactly zero, it goes to `SETUP_GAMEOVER` instead of respawning.
- `RESET_ROUND` is also what `SETUP_GAME` calls (after separately setting the starting clock from `CFG_CLK_H/M/S` and hiding all items again — `ITEM_STATE` is inventory and survives respawns, so only `SETUP_GAME` clears it) to avoid duplicating all the per-round init — see the comment there for the shared/not-shared split.
- The game can now also reach Game Over purely by the clock running out with no death in between: `GAME_ALIVE` checks `CLK_H|CLK_M|CLK_S` right after `TICK_CLOCK` every frame.
- `TICK_CLOCK` itself now clamps at `0:00:00` (early-returns if already zero) — without this, decrementing past zero would underflow `CLK_S`/`CLK_M` to 59 while leaving `CLK_H` at 0, i.e. the clock would visibly jump *up* to `0:59:59` instead of staying at zero.

### Popups (search, locked door) — GAME_STATE=6
`src/popup.asm` implements one shared popup overlay used by two features:
- **Searching (items).** Space is the search key (`KEY_SPC`) — WASD/joystick already own W/A/S/D, so search couldn't reuse S. `READ_KEYS`' `RKSEARCHCHK` block scans the generated `ITEM_ROOM/X/Y` tables for a still-hidden (`ITEM_STATE=0`) item at the player's exact tile; it requires `PLAYER_MODE=0` — **like the terminal, search is human-only; a player-driven robot can't use equipment or search**. On a match it calls `SETUP_SEARCH` with the item index in `X`, which sets `ITEM_STATE=1` (carried) and shows the item's generated found-message (`ITEM_MSG_*`, built from `found_text` in `titan.yaml`). Adding a search spot = adding an `items:` entry plus a `things:` placement in the config — no code.
- **Locked door.** `DOOR_ENTER` calls `SETUP_DOOR_LOCKED` when the door's `DOOR_KEY` item is still hidden — the door just acts like a wall.
- Both funnel into the shared `SHOW_POPUP`, which draws the box/border/hint rows and takes only the message row's address via `PTR`/`PTR+1` (a 40-byte PETSCII string) — a new popup means one more message string and a one-line caller, not touching the drawing code.
- **The popup closes on a fresh Space press, not `GETIN`.** The Space press that opened it is still in the KERNAL keyboard buffer (the raster IRQ's `$EA31` tail runs the KERNAL keyboard scan every frame), so a `GETIN`-based wait closes the popup after one frame. `DO_POPUP` instead polls the CIA matrix directly with edge detection (`POPUP_ST`, `$33`: 0=opening press still held, 1=released/armed, 2=new press seen; closes on that press's release so the closing Space can't leak into `READ_KEYS` either), and drops any buffered keys (`$C6=0`) on close.
- Unlike terminal/map, the popup does **not** `CLEAR_ROOM` first — `SHOW_POPUP` only overwrites rows 8-13 with a small bordered box, so the room art stays visible underneath. `DO_POPUP` erases it on close by calling `DRAW_ROOM` (full redraw) rather than restoring specific rows.
- Time and robot patrol are paused for free, the same way terminal/map already pause them: `DO_GAME` (and hence `TICK_CLOCK`/`TICK_ROBOT`) simply isn't called while `GAME_STATE=6`.
- `ITEM_STATE` is reset only in `SETUP_GAME` (fresh game), not in `RESET_ROUND` — carried items are inventory and survive a death/respawn, unlike the actor/laser state that `RESET_ROUND` does reset.
- `DRAW_STATUS` shows `item:` plus the first non-hidden item's 12-char label (`label:` in `titan.yaml`, in `LTRED`) in the status line.

## Zero Page Map

```
$02  PLR_X        player tile X (0..ROOM_MAXX of the current room)
$03  PLR_Y        player tile Y (0..ROOM_MAXY of the current room)
$04  CLK_H        countdown hours
$05  CLK_M        countdown minutes
$06  CLK_S        countdown seconds
$07  CLK_TICK     jiffy counter (0-49, PAL)
$08  REACT_TEMP   reactor temperature 0-99, derived from the countdown each frame
$09  REACT_CNT    reactor frame counter (flicker cadence)
$0A  REACT_JIT    reactor display flicker 0-3, added to REACT_TEMP when drawn
$0B  LFSR_ST      8-bit LFSR state for noise
$0C  MOVE_TMR     player movement throttle (one step per MOVE_PERIOD = 8 frames)
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
$1A  GAME_STATE   0=intro 1=game 2=gameover 3=terminal 4=win 5=map 6=popup
$1B  DEATH_TMR    frames remaining after laser/robot hit (as long as the death sound: `ZAP_LEN` for a laser, `DEATH_LEN` for a robot hit, so border, sound and pause end together); on expiry, APPLY_DEATH_PENALTY runs (see Death & Respawn)
$1C  BLINK_TMR    blink frame counter
$1D  BLINK_ST     blink state (0=visible 1=hidden)
$1E  SND_TMR      sound effect countdown (0=silent, music plays)
$1F  TERM_SEL     terminal selected drone row (0-3)
$20  TERM_TMR     terminal link confirmation countdown
$21  NEAR_TERM    non-zero when player is adjacent to terminal
$22  (free — was KEY_F1/T key flag, removed when terminal entry moved to Space/KEY_SPC)
$23  KEY_RET      Return key flag
$24  KEY_ESC      F7/Escape key flag
$25  CUR_ROOM     current room index (into world.asm ROOM_* tables)
$26  KEY_MAP      M key flag (open map)
$27  NEWX         candidate tile X for the move being attempted
$28  NEWY         candidate tile Y (MOVE_PLAYER/MOVE_ACTOR/patrol/sprite scratch)
$29  PLR_DIR      player facing (DIR_DOWN/UP/LEFT/RIGHT = 0-3)
$2A  PLR_ANIM     player walk frame (0=rest 1=walk1 2=walk2)
$2B  ANIM_CNT     free-running game-frame counter (hover animation)
$2C  SND_KIND     sound effect playing: 0=death sweep 1=laser zap
$2D  ROB_TMR      robot movement timer (shared by all actors, ROB_PERIOD = 24 frames)
$2E  GL_SX        GLIDE speed X, px/frame (smooth movement)
$2F  GL_SY        GLIDE speed Y, px/frame
$31  PLAYER_MODE  0=human (PLR_X/Y)  else actor index+1 (proxy mode, ACT_X/Y)
$32  KEY_X        X key flag (exit robot proxy mode)
$33  POPUP_ST     popup close edge-detector (0=opener held, 1=armed, 2=pressed)
$34  JOY_PREV     joystick 2 bits held last frame (1=pressed; 0 U 1 D 2 L 3 R 4 fire)
$35  KEY_SPC      space key flag (search, and enter terminal — see Keyboard matrix gotcha)
$36  JOY_NEW      joystick 2 bits newly pressed this frame (set in MAIN_LOOP)
```

Free zero-page slots: `$30`, `$37+`. Per-robot positions, laser/item state etc. moved to RAM arrays at the end of `src/world.asm` (`ACT_X/Y/TGT/ALIVE`, `ITEM_STATE`, `LASER_STATE`, `SPR_SLOT_ACT`) — indexed with `,x`, sized by the config.

## Room Map

The playfield (screen rows 2–23) is a custom-charset top-down map, 22 rows × 40 chars, authored in vchar64 (see `graphics/` and `src/charset.asm`). The walkable tile grid is per-room (`bounds:` in `titan.yaml`). Tile colours come from `TILE_COLORS` (indexed by screen code), not a hand-written switch.

Room art is purely visual — walls, lasers, doorways, and terminals are **not** detected by inspecting tile bytes. Their logical positions come from `titan.yaml` (doors, lasers, terminal zones, item spots as tile coordinates/rectangles), so the art and the config coordinates can silently drift out of visual sync; check new room art against the config before relying on it. Current config:

| Feature | Config (titan.yaml) | Colour |
|---------|---------------------|--------|
| Laser wall | room1 laser rect X=6, Y 0–9 — kills player on contact, unless destroyed (`LASER_STATE`) | Lt Red (visual) |
| Terminal | room1 terminal zone X 1–3, Y 3–5; press space | Lt Green (visual) |
| Room 1 ↔ room 2 doorway | door rects at x=-1 (room1) / x=13 (room2), Y 5–6 | — |
| Win exit | room2 door rect y=10, X 4–6, `leads_to: exit`, `key: red_card` — locked popup without the card | — |

## HUD Layout (row 0, 40 chars)

```
00:00:00 human reactor:[========]  99%
^      ^ ^   ^ ^      ^^       ^^  ^
0      7 9  13 15    23 24    31 33 36
```

The reactor gauge visualises the countdown (nothing in the game reads it back). `TICK_REACTOR` sets `REACT_TEMP = 99 − M·99/START` every frame, with `M = CLK_H*60+CLK_M` (minutes left) and `START` the starting countdown in minutes — 0% at mission start, 99% as the clock runs out, and a death penalty visibly heats it up. To avoid a runtime division it multiplies `M` by `REACT_K = 99*256/START` (an assembly-time constant from `CFG_CLK_H/M`) and takes the high byte; `genworld.py` rejects a `start_time` under one minute. It also re-rolls a 0–3 flicker (`REACT_JIT`) every 8 frames; the shown value is `REACT_TEMP+REACT_JIT` (capped 99). `DRAW_HUD_DYNAMIC` draws it as an 8-segment thermometer in columns 24–31: solid blocks (`CH_SOLID` = `$E0` — not `$A0`, which is a room tile in the custom charset), `(shown+6)/12` segments lit in their zone colour from `REACT_ZONES` (4 green, 2 yellow, 2 red), the rest dark gray. The percentage (columns 33–35) uses the colour of the topmost lit segment. Note `DEC3`/`DEC2` clobber `TMP`/`TMP2`/`X` — keep any colour you need across them on the stack (the old code kept it in `TMP2`, so the digits were coloured by their own character code — usually black).

## Visual Style

- Tilted top-down oblique 2.5D perspective (similar to *Cadaver* / *The Last Ninja*)
- VIC-II hardware sprite priority flag used for depth: sprite priority flips when the player walks "behind" tall tiles
- Color palette: C64 dark registers (dark grays, muted blues, deep browns) with high-contrast multi-color tiles
- Flip-screen room transitions (no scrolling); screen RAM blasted per transition
- Charset: custom vchar64-authored charset at `$2800` (`$D018 = $1A`); `$0291 = $0E` written at init

## Custom Charset / Screen Art

Room/HUD art is authored with **vchar64** (charset + screen + colour editor). `graphics/` holds the vchar64 project files (`.vchar64proj`) plus their ASM exports (`-charset.s`, `-colors.s`, `-map.s` per room); `src/charset.asm` is the ACME-ready version wired into the build (`!source`d from `titanfall.asm` after `map.asm`).

- **Export format: ASM**, not BIN/PRG. Fits the existing convention (sprites/room data are already inline `!byte` literals in source); avoids managing binary blobs, load-header stripping, or Makefile/Exomizer changes for extra files.
- vchar64 labels its ASM export "ACME-compatible" but it isn't: it emits `.byte` (64tass/KickAssembler syntax), which ACME rejects. Every export needs `s/^\.byte/!byte/` before inclusion. `src/charset.asm` is the already-fixed, checked-in version — regenerate it from `graphics/*.s` with the same substitution if the art changes.
- **Charset lives at `$2800`** (2K-aligned, in the gap between end-of-code/`TILE_COLORS` and the sprite block at `$3000`; moved up from `$2000` once code growth started colliding with it — see the gotcha below). `$D018 = $1A` selects screen `$0400` / charset `$2800`. A-Z, digits, and the box-drawing glyphs (`G_HORIZ_BAR`, `G_VERT_BAR`, rounded corners, etc.) used by the intro/gameover/win screens keep their default-ROM-charset code points and shapes — only unused graphics-character slots were repurposed for room-art tiles, so those three screens needed no changes.
- **`TILE_COLORS`** (in `src/charset.asm`, right before the `CHARSET` data) is a 256-byte table indexed by screen code, giving the default colour RAM value for each tile. `COL_BYTE` in `game.asm` does a straight `lda (PTR),y : tax : lda TILE_COLORS,x` lookup instead of switching on individual byte values — **`X` is the caller's page counter in `DRMCPG` and must be saved/restored across the call** (`txa:pha` / `pla:tax`), since `COL_BYTE` needs `X` itself to index the table.
- **Room data is raw screen codes, not PETSCII.** The `ROOM_MAP_n` blocks in the generated `world.asm` (converted by `genworld.py` from the `vchar64_map:` files listed in `titan.yaml`, `.byte`→`!byte`) are blitted straight from `(PTR),y` to `(PTR2),y` in `DRAW_ROOM` with no `PET2SCREEN` conversion (the vchar64 export already emits screen codes). Don't add a `PET2SCREEN` call back in if editing this path.
- **Room/tile collision is not byte-driven.** Walls, lasers, doorways, and terminal zones come from the `titan.yaml` tables, never from inspecting room map bytes. Redrawing a room with new tile art is purely visual, but the art and the config coordinates can silently drift out of visual sync; check new room art against the config rectangles before relying on it.
- Screen/colour canvases are authored at 22 rows in vchar64 (matching the runtime playfield — 2 HUD rows + 1 status row are drawn by game code, not part of the room art).

## Critical Gotchas

### Code growth can silently corrupt TILE_COLORS/CHARSET — watch for ACME warnings
`TILE_COLORS` (256 bytes, in `src/charset.asm`) has no fixed address — it starts wherever the code before it (all of `titanfall.asm` + every `!source`d module) happens to end, and `CHARSET` right after it is pinned to a fixed, 2K-aligned address (`* = $2800`). If code+`TILE_COLORS` ever grows past that fixed address, ACME does **not** fail the build — it prints `Warning - ... Segment starts inside another one, overwriting it.` and silently truncates the tail of `TILE_COLORS`, whose bytes get overwritten by the start of `CHARSET`. Since most room tiles use screen codes in the `$80s`-`$A0s`, this corrupts colour lookups for most of the room art (tiles render in wrong/black colours) while leaving the charset bitmaps themselves intact — exactly the "graphics look horrible, wrong colours" symptom, with no build error to point at it.
- **Always check `make`'s full output for `Warning` lines, not just for a nonzero exit code** — a successful build can still have silently corrupted data.
- To check headroom: `acme -f cbm -o /tmp/g.prg -l /tmp/labels.txt src/titanfall.asm` then `grep TILE_COLORS /tmp/labels.txt` — its start address + 256 must stay under `CHARSET`'s fixed address.
- `CHARSET` was moved from `$2000` to `$2800` for exactly this reason (code had grown ~173 bytes past the old boundary); this freed a full extra 2KB of headroom. If it happens again, the same fix applies — bump `CHARSET`'s `* =` in `src/charset.asm` to the next free 2K-aligned address (the sprite block at `$3000` and the world data after it would have to move up too) and update `VIC_VMCSB`'s value in `titanfall.asm` to match (`$D018 = (screen_base/1024)*16 + (charset_base/2048)*2`; `$0400`/`$2800` → `$1A`).

### CLS wipes the sprite pointers
`CLS` clears all 1024 bytes of screen RAM (`$0400–$07FF`), which includes the sprite pointer table at `$07F8–$07FF`. After **every** `CLS` call, immediately restore all three pointers:
```asm
jsr CLS
lda #SPRP_PLAYER : sta SPRPTR
lda #SPRP_ROBOT  : sta SPRPTR+1
lda #SPRP_DRONE  : sta SPRPTR+2
```
(`ASSIGN_SPRITES` re-points slots 1–2 per room afterwards, but the defaults keep the table sane in non-game states.) `CLEAR_ROOM` (which clears only rows 2–23, `$0450–$07BF`) does **not** reach `$07F8` and does not need a restore.

### CIA1's Timer A IRQ must be disabled before installing the raster IRQ
`$0314`/`$0315` is the general IRQ vector — it fires for **any** IRQ source, not just the VIC raster compare. The KERNAL leaves CIA1 Timer A (the jiffy clock) running at ~60Hz from boot. `RASTER_IRQ` doesn't check which source triggered it, so if CIA1's IRQ isn't disabled, the handler runs on both sources combined (~50Hz raster + ~60Hz CIA ≈ 110Hz) instead of just 50Hz — this manifested as music and the countdown clock both running at ~2x speed. Fixed by disabling CIA1's IRQ sources during init, before `cli`:
```asm
lda #$7F : sta CIA1_ICR   ; disable all CIA1 IRQ sources
lda CIA1_ICR                ; ack any pending CIA1 IRQ
```
This doesn't break keyboard input — `READ_KEYS` polls the CIA1 matrix registers directly, and `RASTER_IRQ`'s `jmp $EA31` tail only needs to run once per raster tick, not to be triggered by a CIA interrupt.

### Table loops count up, not down
All loops over the generated world tables use the counting-up pattern `ldx #0 : L cpx #NUM_* : bcs done : ... : inx : bne L` rather than `ldx #NUM_*-1 ... bpl`. This is deliberate: a config with zero entries of some kind (no lasers, no items) makes `NUM_*-1` underflow to `$FF` and a `bpl` loop would run 256 times over garbage; the count-up form falls straight through on zero. Keep the pattern when adding new table scans. (The `!fill NUM_*+1` on `ITEM_STATE`/`LASER_STATE` in `world.asm` exists so the label is still a valid address in the empty case.)

### No anonymous or local labels
ACME anonymous labels (`-` and `+`) scope to the entire zone, not the subroutine — with many routines in one file they resolve to wrong targets silently. Local labels (`.foo`) also caused duplicate-definition errors across routines in the same zone. **All labels are explicit global names** (e.g. `CLSP`, `HUDST1`, `TSETB1`).

### Sound effects tick from the raster IRQ
While `SND_TMR > 0`, `RASTER_IRQ` calls `SOUND_TICK` (`game.asm`) *instead of* the music player, every frame and in every game state. (It used to be called from the top of `DO_GAME`, i.e. only in state 1 — an effect still playing when the state changed, e.g. Space straight into the terminal right after the splicer's laser zap, froze with the gate open and blocked the music.) Because it runs inside the IRQ, `SOUND_TICK` may only use `A` (the KERNAL IRQ entry/exit saves A/X/Y) and the `SND_*` variables — never `TMP`/`PTR`/`NEWX` or other main-loop scratch.

### Keyboard matrix — key positions
Convention used throughout `READ_KEYS`: "col N" = CIA1 `$DC00` (PRA) written with bit N cleared (selects that column); "row N" = CIA1 `$DC01` (PRB) bit N, active low (0 = pressed).
```
W (up):            col 1 (PA=$FD), row 1 (PRB bit 1 = mask $02, active low)
A (left):          col 1 (PA=$FD), row 2 (PRB bit 2 = mask $04, active low)
S (down):          col 1 (PA=$FD), row 5 (PRB bit 5 = mask $20, active low)
D (right):         col 2 (PA=$FB), row 2 (PRB bit 2 = mask $04, active low)
M key (map):       col 4 (PA=$EF), row 4 (PRB bit 4 = mask $10, active low)
X key (exit proxy):col 2 (PA=$FB), row 7 (PRB bit 7 = mask $80, active low)
Space (search/terminal): col 7 (PA=$7F), row 4 (PRB bit 4 = mask $10, active low)
Return:            col 1 (PA=$FD), row 1 (PRB bit 1 = mask $02, active low)
F7 (exit):         col 7 (PA=$7F), row 4 (PRB bit 3 = mask $08, active low)
```
Movement is WASD, not cursor keys. Joystick port 2 works alongside the keyboard: `READ_KEYS` first reads `CIA1_PRA` (`$DC00`) with `PRA=$FF` (no keyboard column selected; bits 0-4 = up/down/left/right/fire, active low) and ORs the directions into the same `KEY_U/D/L/R` flags (held = move). Fire is Space, but only on a *fresh* press: `MAIN_LOOP` polls port 2 once per frame into `JOY_PREV` (held bits) and `JOY_NEW` (bits newly pressed this frame, 1=pressed), and `READ_KEYS` sets `KEY_SPC` from `JOY_NEW` — otherwise fire still held from the terminal's logoff would re-enter the terminal on the next frame. (Port 1 would be `$DC01`, which collides with keyboard rows; it isn't read.) The `GETIN`-driven screens also take `JOY_NEW`: fire = "press any key" on intro/game over/win/map, and in the terminal menu fire = Return, up/down = cursor up/down. `DO_POPUP` polls fire directly with its own edge detector, alongside Space. Space does double duty: it enters the terminal inside a terminal zone (`TERMZ_*` tables) and searches on an item spot (`ITEM_*` tables) — keep these zones non-overlapping in `titan.yaml`, since the terminal check wins (it runs first in `READ_KEYS`). There used to be a dedicated T key for the terminal; it was removed in favor of reusing Space. If a key seems to trigger the wrong action, re-derive its column/row from the matrix table rather than guessing; `col`/`row` values that look adjacent (e.g. row 4 vs row 6) are an easy transcription error.

Terminal menu navigation uses `GETIN` (KERNAL keyboard buffer) for PETSCII codes: `$11`=cursor down, `$91`=cursor up, `$0D`=Return, `$88`=F7.

### Sprite data placement
All sprite frames live in one block at `$3000` (see "Sprites"), which must stay inside VIC bank 0 and outside `$1000–$1FFF` (the VIC sees the character ROM there, not RAM). No runtime copy loop. Pointers are `address/64` — always computed from labels, never hard-coded.

### Sprite collision register clears on read
`VIC_SPCOLL` (`$D01E`) is cleared by the hardware the moment it is read. Read it exactly once per frame in `CHECK_SPRITE_HIT` and act on the value immediately — reading it again will always return 0.

### Extended (9-bit) sprite X needs every carry, not just the last one
The `X pixel = tile*24+28` formula is computed as `tile*16 + tile*8`, then `+28` — two separate 8-bit adds. For tiles 0-10 only the final `+28` can push the result past 255, so a single `bcs` after that last add is enough to catch it. But at tile 11-12 (reachable in room 1 by `PLR_X` and by a player-driven robot's `ACT_X`), `tile*24` alone already exceeds 255 — the *first* add overflows. A naive `clc` before the final `+28` (needed so that add doesn't also pick up a stray carry-in) throws away that first overflow, so `bcs` after the last add sees no carry and the sprite's `VIC_SP_MSB` bit never gets set — the sprite silently wraps to a low X instead of continuing right, instead of correctly extending onto the far right of the screen.

The shared fix is `TILE_TO_PIXEL_X` (`game.asm`): given a tile number in A, it returns the pixel-X low byte in A and sets carry iff the *true* 9-bit value exceeds 255, by explicitly carrying the overflow forward — store the low byte and overflow bit from the first add (`TMP`/`TMP2`), then `adc #0` the second add's carry into `TMP2` and convert that 0/1 into the carry flag with `cmp #1` (done *after* restoring the low byte into `A`, since `LDA` doesn't touch carry). `UPDATE_SPRITE0` and `UPDATE_ROBOT_SPRITES` both call this instead of duplicating the add — any sprite's tile coordinate can safely reach 11-12 (or beyond, up to the point pixel X would exceed the visible screen) and get the right `VIC_SP_MSB` bit.

## SID / Music

### Background music
`music/Licence_to_Kill.prg` is the Licence to Kill SID tune (David Whittaker, 1989 Domark), loading at `$C000–$CFFF` (PSID, 5 subtunes; the game plays tune 1). The Makefile packs it into `titanfall.prg` via exomizer.

- **Init:** `lda #0 : jsr $C000` — called once during startup (after SID clear, before `cli`). `A` selects the subtune (0 = tune 1).
- **Play:** `jsr $C127` — called from `RASTER_IRQ` every frame (50 Hz PAL). (The old Armalyte tune used `$C059` — if the music file is swapped, the play address in `RASTER_IRQ` must change with it; check with `sidplayfp -v <file>.sid`.)
- **Sound effect interlock:** while `SND_TMR > 0`, `RASTER_IRQ` calls `SOUND_TICK` instead of `$C127`, giving the effect (death sweep or laser zap) exclusive SID control. Music resumes automatically when `SND_TMR` reaches 0.
- Candidate replacement tunes that fit the `$C000–$CFFF` window are listed in `music/possible_songs.txt` (HVSC scan via `music/find_sids_in_range.py`); `music/README.txt` documents the sid→prg conversion (`psid64`).

### $D418 (master volume) discipline
The Whittaker player writes `$D418` itself during play (unlike the old Armalyte player, which set it only at init — the original reason for this rule). But while `SND_TMR > 0` the play routine is not called, so nothing restores volume during the death-sound window:

**Rule:** never leave `$D418` at `$00`. `SOUND_DEATH_START` and `SOUND_ZAP_START` set `$D418 = $0F` (the zap fades through `$D418` but never reaches 0), and `SNDOFF` restores `$0F` after gating off voice 1. `SETUP_GAMEOVER` and `SETUP_WIN` must not write to `$D418` — let music continue. `SND_TMR` is zeroed explicitly in the init before `cli` — the KERNAL may leave `$1E` non-zero, which would permanently block music in intro.

### Sound effects
Voice 1, one effect at a time, `SND_KIND` (`$2C`) selects the effect `SOUND_TICK` plays:
- **Death sweep** (`SOUND_DEATH_START`, kind 0) — sawtooth, gates on at ~350 Hz and sweeps downward over 50 frames. Used when a patrol robot catches the human (`CHECK_SPRITE_HIT`).
- **Laser zap** (`SOUND_ZAP_START`, kind 1, `ZAP_LEN` = 40 frames) — the "bzzzt": a thin 12.5% pulse at ~60–90 Hz (mains-hum range, pitch jittered from `LFSR_ST`) alternating every frame with a high noise crackle, a one-frame gate drop every 8 frames for the stutter, fading out through `$D418` over the last 15 frames. Used when the human walks into a laser (`TRY_MOVE`) and when a driven robot burns one out (`ROBOT_LASER_DEATH`).
Both set `$D418 = $0F` on start, and `SNDOFF` gates off and restores `$0F` at the end.

## Screen Art

Non-game screens (intro, game over, win) use a PETSCII box design: a bordered panel (rows 3–13 on game over / win, rows 10–19 under the logo on the intro) drawn at 50 Hz by the relevant setup routine. All three share the subroutine `DRAW_INTRO_SCREEN` for the intro layout (called from `SHOW_INTRO`, the `DO_GAMEOVER` restart path, and the `DO_WIN` restart path).

### Shared string labels (each exactly 40 bytes)
- `SCR_BORDER_TOP` — rounded top border (`G_RD_UL` + 38 × `G_HORIZ_BAR` + `G_RD_UR`)
- `SCR_BORDER_BOTTOM` — rounded bottom border (`G_RD_LL` + 38 × `G_HORIZ_BAR` + `G_RD_LR`)
- `SCR_BLANK` — `G_VERT_BAR` + 38 spaces + `G_VERT_BAR` empty interior row
- `ITR_SEP` — `G_VERT_BAR  ==...==  G_VERT_BAR` separator (reused by all three screens)

**All boxes use the PETSCII line glyphs** from `src/petscii.asm` — rounded corners `G_RD_UL/UR/LL/LR`, `G_HORIZ_BAR`, `G_VERT_BAR` — never ASCII `+`, `-`, `|` (those render as plain/odd glyphs). The terminal box reuses `SCR_BORDER_TOP`/`SCR_BORDER_BOTTOM`/`SCR_BLANK`; the popup's narrower box (`SBOX_*`, columns 4–35) builds its border rows with `!fill 30, G_HORIZ_BAR`; `genworld.py` frames the generated `ITEM_MSG_*` rows with `G_VERT_BAR`; the sector map's room outlines (`MAP_R9`–`MAP_R13`) use the rounded corners too. After drawing a box, call `FRAME_EDGES` (full width) / `FRAME_EDGES_LR` (columns preset in `FR_L`/`FR_R`) with the frame colour so the `G_VERT_BAR` ends don't inherit each row's text colour.

All string-copy loops call `jsr PET2SCREEN` to convert PETSCII to screen codes before writing to screen RAM. `PET2SCREEN` is defined in `src/titanfall.asm` after `CLS`.
- `ITR_TAG`, `ITR_M1`–`ITR_M3` — intro panel content (the intro has no title row in the box any more — the logo above it replaces it)
- `GO_TITLE`, `GO_M1`–`GO_M3` — game over panel content
- `WIN_TITLE`, `WIN_M1`–`WIN_M3` — win panel content
- `TXT_PRESS`, `TXT_GOPRESS`, `TXT_WINPRESS` — blinking footer prompts

Star characters (`*`) in the game over / win titles are recoloured to YELLOW after the row loop by writing to individual CRAM addresses.

**Intro layout:** `DRAW_INTRO_SCREEN` copies the logo (`TITLE_SCR`/`TITLE_COL`, raw screen codes, no `PET2SCREEN`) into rows 1–8, draws the mission box in rows 10–19 (top border, blank, tagline, separator, blank, 3 mission lines, blank, bottom border), and `BLINK_ON`/`BLINK_OFF` blink the prompt on row 22 (`SCRN+880`). The logo's solid block is screen code 224 (`$E0`), not the usual 160 (`$A0`) — `$80–$A2` in the custom charset are room-art tiles, and `$E0` is the other all-ones glyph in the ROM font. Any new full-screen PETSCII art must likewise avoid `$80–$A2` (check `src/charset.asm`).

## Current Status

The core puzzle loop is in place and playable end-to-end: explore, take over the splicer via the terminal, destroy the laser with it, search for the access card, and reach the win screen through the now-unlockable room 2 door — with a real risk/reward death penalty (lose time + respawn) instead of an instant Game Over, and Game Over genuinely tied to the countdown clock hitting zero.

The world is now **config-driven**: rooms (bounds, player start, vchar64 map), robots (type, start, patrol waypoints), items (position, label, found-text), doors (rect, destination, arrival position, key), lasers, terminal zones, the starting clock and the death penalty all live in `titan.yaml` and are compiled into `src/world.asm` data tables at build time. Adding a room = a vchar64 map export + a `rooms:` entry (plus, for now, hand-drawn sector-map art — see below). Adding an item, door, laser or robot is config-only.

## What's Not Yet Implemented

- Drone control for bot-7741 (loader) and bot-9901 (centurion) — only bot-3312 (splicer) is a real controllable proxy so far; the terminal menu itself (`TBOX_D0-D3` in `terminal.asm`) is still hardcoded, not generated from the actor tables, and selecting the other two is cosmetic (loader) or blocked (centurion, locked)
- Sector map background art (`MAP_R8-R17` strings in `map.asm`) is still hand-drawn for the two current rooms; only the current-room highlight box is table-driven (`MAPHL_*` from `map_view:` in `titan.yaml`). A third room needs new map strings.
- Item states `carried` vs `used` aren't distinguished yet — door keys accept either, nothing sets `used` (=2)
- `ai:` in `titan.yaml` only accepts `patrol` (two-waypoint shuttle); no other AI routines exist yet
- Max 2 robots per room (hardware sprites 1–2; enforced by `genworld.py`) — a sprite multiplexer is deliberately out of scope
