# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Commodore 64 game called **TITAN Fall** (working title) — a cinematic infiltration puzzle thriller in the vein of *Impossible Mission* and *Paradroid*. The player infiltrates an automated missile launch complex and must subvert its drone workforce to stop a launch countdown. The game is targeted at PAL/NTSC C64 hardware. See `design/gamedesign.md` for the full design document — it is partly out of date but is kept as a source of ideas for future features; this file and `titan.yaml` describe what is actually implemented.

## Build & Run

```
make        # generate world.asm + assemble + pack
make run    # generate, assemble, pack, and launch in Vice
make clean  # remove game.prg, titanfall.prg and the generated src/world.asm + src/charset.asm
```

The build is four steps handled by the Makefile:
1. **tools/genworld.py** (Python 3 + PyYAML) generates `src/world.asm` from `titan.yaml` — all world data tables (rooms, actors, items, doors, lasers, terminal zones) plus the room map data converted from the vchar64 exports
2. **tools/gencharset.py** generates `src/charset.asm` (`TILE_COLORS` + `CHARSET`) from the vchar64 exports `graphics/titan-charset.s` and `graphics/titan-tile-colors.s`
3. **ACME 0.97** assembles `src/titanfall.asm` → `game.prg` (`-f cbm`, 2-byte load header)
4. **Exomizer** packs `game.prg` + the music PRG into a self-extracting `titanfall.prg`

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
| `src/map.asm` | `DO_MAP`, `SETUP_MAP` (copies the generated `MAP_SCR`/`MAP_COL`, lights the current room) |
| `src/popup.asm` | `DO_POPUP`, `SHOW_POPUP`, `SETUP_SEARCH`, `SETUP_DOOR_LOCKED`, popup strings |
| `src/c64_walker_sprites.asm`, `src/c64_robot_sprites.asm`, `src/c64_drone_sprites.asm` | Multicolour sprite sets (player / walking robot / flying drone), `!source`d into the sprite block at `$3000`. All three have all four facings (robots need up/down too — the terminal lets you drive them in any direction) |
| `src/charset.asm` | **Generated** by `tools/gencharset.py` (never edit it; in `.gitignore`): `TILE_COLORS` (256-byte tile→colour table) and `CHARSET` (custom 2K charset at `$2800`) from the vchar64 exports — see "Custom Charset / Screen Art" |
| `src/world.asm` | **Generated** by `tools/genworld.py` from `titan.yaml` (data only, no code): `NUM_*`/`ACTOR_*`/`ITEM_*`/`CFG_*` constants, `ROOM_*`/`TYPE_*`/`ACT_*`/`ITEM_*`/`DOOR_*`/`LASER_*`/`TERMZ_*`/`MAPHL_*` tables, the generated sector map `MAP_SCR`/`MAP_COL`, `ROOM_MAP_n` screen-code data, and the runtime state arrays (`ACT_X/Y/TGT/ALIVE/DIR/ANIM`, `GL_PXL/PXH/PY`, `ITEM_STATE`, `LASER_STATE`, `SPR_SLOT_ACT`) |

Other files:
- `titan.yaml` — **the world definition** (rooms, robots, items, doors, lasers, terminals, start clock); the preferred place to change gameplay content
- `tools/genworld.py` — build-time generator `titan.yaml` → `src/world.asm`
- `tools/gencharset.py` — build-time generator vchar64 charset/tile-colour exports → `src/charset.asm`
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
| `$0810` | Entry point / code start (code + `TILE_COLORS` end before `$2800` — ~550 bytes left, see the TILE_COLORS gotcha) |
| `$0340–$0397` | Tape buffer, reused as `SP_BUF` (screen + colour cells under the small search popup) |
| `$0400–$07FF` | Screen RAM (default VIC bank) |
| `$2800–$2FFF` | `CHARSET` — custom 2K room-art charset (see below) |
| `$D800–$DBFF` | Colour RAM |
| `$07F8` | Sprite pointer table (end of screen RAM — **must be restored after every CLS call**) |
| `$3000–$38FF` | Sprite frames (36 × 64 bytes, pointers `$C0–$E3`): player 12, robot 12, drone 12 — see "Sprites" |
| `$3900` | `TITLE_SCR`/`TITLE_COL` intro logo (640 bytes), then the generated world data (`src/world.asm`): tables, room maps, wall grids, runtime state arrays — grows with content (ends ~`$4C85` today), must stay below `$C000` |
| `$C000–$CFFF` | Licence to Kill SID music (init `$C000`, play `$C127`; loaded by exomizer) |

## Core Design Constraints

When implementing code, always respect these C64 hardware limits:

- **CPU:** MOS 6510 (6502 derivative); assembler is **ACME** (not cc65, not KickAssembler)
- **VIC-II sprites:** Exactly 8 hardware sprites available — the design intentionally avoids a sprite multiplexer
- **Room layout:** 22 rows × 40 chars (custom charset, screen codes) per room. **The tile — the unit of every coordinate in the game and in `titan.yaml` — is 2×2 chars (16×16 px)**, so a room is 20×11 tiles (X 0–19, Y 0–10); tile (x,y) covers map cols `2x..2x+1`, rows `2y..2y+1`. `bounds:` in `titan.yaml` (→ `ROOM_MAXX/Y`) is optional and defaults to the whole room; the outer walls of the art make the edge tiles solid anyway
- **Memory:** 64 KB total; code, data, and screen RAM must all fit within the standard C64 memory map
- **SID chip:** 3 voices for audio

## State Machine

`GAME_STATE` (`$1A`) holds the current state. The main loop syncs to a raster IRQ at line 50 (~50 Hz PAL); `TICK_FLAG` is set by the IRQ and cleared each frame by `MAIN_LOOP`.

| Value | State | Description |
|-------|-------|-------------|
| 0 | Intro | Title screen, tagline, blinking "press fire" prompt |
| 1 | Game | Playfield with HUD, player sprite, room map, countdown clock, reactor meter |
| 2 | Game over | Red border + descending-pitch sound, then game-over screen |
| 3 | Terminal | Terminal menu: this room's robots, view map, logoff (fire next to a terminal; time paused; sprites hidden) |
| 4 | Win | Mission complete screen (reached via bottom exit in room 2) |
| 5 | Map | Sector map overlay (terminal's "view map" entry; time paused; sprite hidden; fire/any key returns to the terminal) |
| 6 | Popup | "Found item", "door locked" or F2 "where am I" popup (end of a held-fire search that found something, blocked at a locked door, or F2; time/robots paused; a fresh fire/Space press closes it — see the popup section) |

**Stack discipline:** The state machine uses fall-through / `jmp` between states, not `jsr`/`rts`. `MAIN_LOOP` is entered by falling through from init code, never by `jsr`. State transitions use `jmp SETUP_*` not `jsr`, so the return address on the stack is always the one from `DISPATCH`'s `jsr TICK_*`. Never `jsr` into anything that falls into `MAIN_LOOP`.

**Dispatch uses `bne`+`jmp` pairs, not `beq`.** The `DO_*` handlers live in `!source`d files assembled after `CLS`/`RASTER_IRQ`/shared strings, placing them beyond the ±127-byte range of a `beq`. The dispatch reads: `bne MLNOT0 : jmp DO_INTRO` etc.

**State ≠ 1 guard in GAME_ALIVE:** After `READ_KEYS` (so a terminal/popup opened by a key doesn't let `MOVE_PLAYER` take a step behind it) and again after `MOVE_PLAYER`, `GAME_ALIVE` checks `lda GAME_STATE : cmp #1 : bne GAME_TICK_DONE`. This skips sprite update / HUD / status draws whenever any other state (3 terminal, 4 win, 5 map, 6 popup) was entered mid-frame. It used to be `cmp #4 : bcs`, which let the terminal (state 3) through: `UPDATE_ROBOT_SPRITES` then re-enabled the robot sprites right after `SETUP_TERMINAL` had cleared `VIC_SPEN`, so robots stayed visible over the terminal screen.

## Gameplay Architecture

The game has two distinct active modes sharing a single countdown timer:

1. **Human mode** — player explores rooms, scavenges for Access Clearance Chips (levels 1–4) and Direct Override Codes (robot serial numbers)
2. **Robot/proxy mode** — activated at mainframe terminals; the human sprite freezes and the player controls a drone remotely

`PLAYER_MODE` (`$31`) implements this generically: **0 = human control, otherwise (actor index + 1) = that actor is player-driven**. Robots are entries in the generated actor tables (`ACT_*` in `world.asm`); the splicer is `ACTOR_BOT3312` (equate from `id: bot3312` in `titan.yaml`).
- Selecting a robot in the terminal (`TERM_ROBOT` in `terminal.asm`) sets `PLAYER_MODE=actor+1` and jumps straight back into gameplay via the shared `TERM_ABORT` exit path — no extra confirmation press — unless the robot is destroyed (`TMSG_DEAD`) or `locked: true` in `titan.yaml` (`ACT_LOCK`, `TMSG_LCK`). See "Terminal menu".
- While `PLAYER_MODE≠0`, `MOVE_PLAYER` (`game.asm`) dispatches to `MOVE_ACTOR`, which moves `ACT_X/Y` of actor `PLAYER_MODE-1` — WASD/joystick drive the robot, clamped to its own room's `ROOM_MAXX/Y` bounds; no doorway checks (robots can't leave their room); the human sprite stays frozen at its last `PLR_X/Y`. Driving into an active laser destroys both robot and laser — see "Lasers can be destroyed by a driven robot".
- `TICK_ROBOT` skips the patrol step for the player-driven actor (index+1 == `PLAYER_MODE`) so the AI doesn't fight manual control.
- `CHECK_SPRITE_HIT` ignores player-sprite collisions while `PLAYER_MODE≠0` (the human is standing safely at the terminal); it still reads `VIC_SPCOLL` every frame regardless of mode so the hardware latch doesn't accumulate a stale hit for when control returns to human.
- **Fire** (a fresh press, `JOY_NEW`) or the **X key** (`KEY_X`), checked at `RKXCHK` at the end of `READ_KEYS`, exits proxy mode at any time, setting `PLAYER_MODE=0` back to human control. Fire is free for this because both fire/Space actions (terminal and search) are gated on `PLAYER_MODE=0` — a player-driven robot can't use equipment, and the frozen human still standing in the terminal zone must not re-trigger the terminal.
- `DRAW_HUD_DYNAMIC` and the F2 popup (`SETUP_WHERE`) both branch on `PLAYER_MODE` to show "robot"/`ACT_X/Y` instead of "human"/`PLR_X/Y`.

Key state to track:
- Countdown timer (real-time; configurable penalty and respawn per human death, see "Death & Respawn"; Game Over only when the clock hits zero)
- Inventory: `ITEM_STATE` array (0=hidden 1=carried 2=used), one byte per config item
- Per-actor: `ACT_X/Y` (tile position), `ACT_TGT` (patrol waypoint), `ACT_ALIVE` (0=destroyed 1=alive 2=dying — sliding into a laser), `ACT_DIR`/`ACT_ANIM` (facing, walk frame), `GL_PXL/PXH/PY` (glided sprite pixel position)
- Per-laser: `LASER_STATE` (0=active 1=destroyed)
- Active mode (human / drone) and which actor is linked (`PLAYER_MODE`)

## Rooms

Rooms are defined in `titan.yaml`; `CUR_ROOM` (`$25`) indexes the generated `ROOM_*` tables. Two rooms are currently configured (room1: two terminals, laser wall at X=9, search spot at (14,5), left door to room2; room2: one terminal, right door back, locked bottom exit to the win screen). The art lives in one vchar64 project, `graphics/titan.vchar64proj`.

Movement is fully table-driven (`MOVE_PLAYER`/`TRY_MOVE` in `game.asm`):
- **Bounds:** each room has its own `ROOM_MAXX`/`ROOM_MAXY` (default and maximum 19/10, the full 20×11-tile room; walls in the art do the real limiting).
- **Doors** (`DOOR_*` tables) are rectangles *one tile outside* the walkable range (e.g. `x: -1` on a left wall, `y: 10` on a bottom wall, encoded `$FF`/`$0A`). A move landing inside a door rect triggers it: locked check first (`DOOR_KEY` = item index+1, 0=none; locked shows the popup and acts like a wall), then either the win screen (`DOOR_DEST=$FF`, `leads_to: exit`) or a room change (`DOOR_AX/AY` set the arrival position; `$FF` = keep current coordinate). Anything out of bounds that isn't a door is a wall.
- **Interior walls** come from the room art, computed at build time: `genworld.py`'s `wall_grid` marks a tile solid if any of its 2×2 map chars (map cols `2x..2x+1`, rows `2y..2y+1` — where the sprite's feet stand) is in `art.solid_tiles` in `titan.yaml` (`$84–$8B`, the wall glyphs). It emits `ROOM_WALLS_n` (20 bytes per tile row, index `y*20+x` — max 219, so one byte index covers the room; 1 = solid, with an ASCII picture of the grid in the comments) via `ROOM_WALL_LO/HI`; `WALL_AT` (A = room) looks a tile up, and both `TRY_MOVE` (human) and `TRY_ACT` (driven robot) treat a solid tile like a wall before checking lasers. The build **fails** if a player start, a robot start or any tile on a patrol path, an item, or a door arrival lands on a solid tile (or a terminal zone is all wall) — so new art and the config can't silently drift apart for walls. Furniture isn't solid unless its codes are added to `solid_tiles`.
- **Lasers** (`LASER_*` tables) are rectangles inside the room; `LASER_AT` checks the attempted position against every active laser in the current room. The human steps onto the tile but is already dying (`PLR_DYING=1`: `MOVE_PLAYER` ignores input) and `UPDATE_SPRITE0` calls `PLAYER_DIE` once the sprite has glided onto the beam — the same "finish the slide, then die" as a driven robot; a player-driven robot enters the tile and `ROBOT_LASER_DEATH` destroys both robot and laser.

Doorway transitions call `DRAW_ROOM`, which blits 22×40 chars via the `ROOM_MAP_LO/HI` pointer tables and then calls `ASSIGN_SPRITES` to remap the new room's actors onto hardware sprites 1–2.

### Adding content (config-only recipes)

- **New room:** author the art in vchar64 (22×40, shared charset — see `graphics/README.txt`), export the map as ASM, add a `rooms:` entry in `titan.yaml` (name, `vchar64_map`, `player_start`; `label` — its name on the sector map — and `bounds` optional) plus doors linking it to its neighbours (a door in each direction of travel, one per room). The sector map updates itself (see "Sector map").
- **New hidden item:** add an entry under `items:` (label ≤12 chars, found_text ≤30 chars) and place it with a `things:` entry in a room. Lock any door with `key: <item>`.
- **New robot:** add a `robots:` entry in a room (`type`, `start`, two-point `patrol`, optional terminal `name:` ≤22 chars and `locked: true`; ≤2 robots per room). It appears in the terminal menu of its room automatically. Give it an `id:` if code needs to reference it (emitted as `ACTOR_<ID>`). A new *type* needs an `actor_types:` entry, a sprite data block in `titanfall.asm` (64-byte aligned, referenced by label), and — until more AI exists — `ai: patrol`.
- **New laser:** one line under the room's `lasers:`.
- **New terminal:** just draw it in the room art (chars `$8C`–`$8F`, `art.terminal_tiles`). `genworld.py` finds every 4-connected group of terminal chars (`find_terminals`) and makes it a terminal zone (`TERMZ_*`): the tiles under the group plus one tile around them, clipped to the room — so a terminal works from any side. A room's old `terminals:` key is rejected, and an item inside a terminal zone fails the build (fire there opens the terminal, so the item could never be searched for).
- Check the room art visually matches the config rectangles — only walls are validated against the art (placements inside walls fail the build); lasers/doors/terminals are not.

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

**Spare sets, not yet `!source`d** (drawn for later; adding one costs sprite-block space, and the world data after it moves up): `c64_dozer_sprites.asm` (tracked construction robot, 12 frames, yellow), `c64_tripod_sprites.asm` (tripod walker, 12 frames, light green), and two weapon effects — `c64_bolt_sprites.asm` (plasma bolt, 2 frames `bolt_1/2`, round so it works in any direction, alternate every 1–2 frames, centre at sprite x+12/y+9.5) and `c64_forcefield_sprites.asm` (horizontal force-field beam, 2 frames `forcefield_1/2`, alternate every 2–3 frames; tiles seamlessly at 24 px, or 48 px X-expanded). All use the same shared MC0/MC1 colours, with `%10` as the per-sprite colour. `src/c64_spritemate.spm` is the Spritemate project they're edited in.

The three files are `!source`d back-to-back into one block at `* = $3000` (right after the charset, still in VIC bank 0) — each frame is 64 bytes, so they stay 64-byte aligned as long as every file holds whole frames. **Commenting frames in or out shifts everything after them**; that's fine because everything addresses frames by label (`sprite:` in `titan.yaml`, `SPRP_*` equates), never by hard-coded pointer value.

**Frame selection** (`FRAME_PTR` in `game.asm`): pointer = `TYPE_SPRPTR + (facing − TYPE_DIR0)*3 + frame`. Per actor type in `titan.yaml`:
- `sprite:` — label of the type's first frame
- `directions: 4` (default; facings `DIR_DOWN/UP/LEFT/RIGHT` = 0–3) or `2` (left/right only → `TYPE_DIR0=2`; `ACT_FACE` ignores up/down, so the actor keeps its last horizontal facing while moving vertically). All current types use 4 — robots need up/down poses because a robot taken over at the terminal can be driven in every direction; `directions: 2` is only for a future type with a left/right-only sprite set.
- `anim: walk` (default — frame advances rest→walk1→walk2→walk1… once per tile step, back to rest when a step doesn't happen: idle player, patrol waypoint pause) or `hover` (ignores steps; loops hover/move1/hover/move2 off the free-running `ANIM_CNT`, 8 frames per pose)

State: player `PLR_DIR`/`PLR_ANIM` (zero page); actors `ACT_DIR`/`ACT_ANIM` (runtime arrays in `world.asm`, reset by `RESET_ROUND`). The facing is set on every move *attempt* (so walking into a wall turns you), the walk frame only on a committed step (incl. walking through a door). `UPDATE_SPRITE0` / `UPDATE_ROBOT_SPRITES` write the frame pointer into `$07F8–$07FA` every frame; `ASSIGN_SPRITES` sets each slot's colour (and an initial pointer) on room entry. `ATYPE_<NAME>` constants (e.g. `ATYPE_HUMAN`) are emitted by `genworld.py`.

After every `CLS` the pointers are reset to `SPRP_PLAYER`/`SPRP_ROBOT`/`SPRP_DRONE` (just sane defaults — the per-frame update replaces them). `VIC_SPEN` is set to `$07` during game state (`UPDATE_ROBOT_SPRITES` clears the bits of unused/dead/off-room slots every frame), `$00` in all other states.

### Actors and patrol AI
All robots are rows in the generated `ACT_*` tables (the player is *not* in them; `PLAYER_MODE` maps "actor index+1" onto them for proxy mode). Static data per actor: `ACT_TYPE` (indexes `TYPE_SPRPTR`/`TYPE_COLOR`), `ACT_ROOM`, `ACT_SX/SY` (start), `ACT_WX0/WY0`/`ACT_WX1/WY1` (two patrol waypoints). Runtime state: `ACT_X/Y`, `ACT_TGT` (which waypoint it's heading for), `ACT_ALIVE`.

`TICK_ROBOT` is called every game frame (shared `ROB_PERIOD` = 16-frame timer, `ROB_TMR`) and runs `ACTOR_PATROL_STEP` for every alive, non-player-driven actor — one step toward the current target waypoint (X axis first, then Y; on arrival the target flips). Actors in other rooms keep patrolling off-screen. Patrol paths are authored in `titan.yaml` not to cross lasers — the patrol AI does no hazard checks.

**Smooth movement (gliding).** Logic stays tile-based (`PLR_X/Y`, `ACT_X/Y` — collisions with walls/doors/lasers/terminals/items are all per tile), but sprites don't jump a whole tile (16×16 px) per step. Each sprite has its own pixel position in `GL_PXL`/`GL_PXH`/`GL_PY` (runtime arrays in `world.asm`, `NUM_ACTORS+1` long: slot = actor index, last slot `GL_PLAYER` = the human), and `GLIDE` (`game.asm`) moves it `GL_SX`/`GL_SY` px per frame toward the pixel position of its tile, clamping so it never overshoots. Speeds are matched to the step periods so a glide finishes just as the next step starts:
- player, and a player-driven robot: one step per `MOVE_PERIOD` = 8 frames, glide `GL_FAST_X/Y` = 2/2 px per frame (16/8) → continuous walking with no stop at each tile
- patrolling robots: one step per `ROB_PERIOD` = 16 frames, glide `GL_SLOW_X/Y` = 1/1 px per frame → continuous too
- `SNAP_ALL` (called by `DRAW_ROOM` — room change, respawn, redraws after terminal/map/popup) jumps every sprite straight to its tile, so nothing glides across a room change.
If you change a step period, change the matching speeds (tile pitch / period) or the glide will lag behind or stall. Hardware sprite collisions (`$D01E`) use the glided positions, i.e. what's on screen. A robot that drives into a laser finishes its glide into the beam before it is destroyed (see "Lasers can be destroyed by a driven robot").

**Sprite mapping:** `ASSIGN_SPRITES` (called from the end of `DRAW_ROOM`) scans the actor table for actors in `CUR_ROOM` and assigns them to hardware sprites 1–2 (`SPR_SLOT_ACT`, 2 bytes, `$FF`=empty), setting each slot's sprite pointer and colour from the actor's type. `UPDATE_ROBOT_SPRITES` glides and positions both slots every frame; the glide *targets* use the shared `TILE_TO_PIXEL_X` formula (X pixel = `tile*16+20` — the 24 px sprite centred on the 16 px tile — and Y pixel = `tile*16+62` — feet, sprite line 19, on the tile's bottom line; per-slot `VIC_SP_MSB` bit from `GL_PXH`, needed for tiles 15–19 — see the "Extended (9-bit) sprite X" gotcha) and disables the `VIC_SPEN` bit for any slot that is empty, dead, or out of the room. `genworld.py` rejects configs with more than 2 robots in one room.

### Lasers can be destroyed by a driven robot
`LASER_STATE` (one byte per config laser, 0=active 1=destroyed) implements a one-way puzzle mechanic: driving any proxy-controlled robot into an active laser destroys both.
- `LASER_AT` (`game.asm`) is the shared test — carry set if `NEWX/NEWY` is inside an active laser rect of the current room, returning the laser index in `Y`. `TRY_MOVE` (human) and `TRY_ACT` (driven robot) both call it on every attempted move.
- On a robot hit, `TRY_ACT` doesn't destroy it yet: it sets `ACT_ALIVE=2` ("dying") and remembers the laser in `PEND_LSR`. A dying robot ignores input (`MOVE_ACTOR`) and patrol (`TICK_ROBOT` only moves `ACT_ALIVE=1`), and keeps gliding onto the laser tile; once its sprite arrives, `UPD_DYING` (from `UPD_SLOT`) calls `ROBOT_LASER_DEATH`, which sets that actor's `ACT_ALIVE=0` (sprite hidden for good, patrol suspended forever) and that laser's `LASER_STATE=1` (it stops killing the human too), erases the beam from the screen (`ERASE_LASER`, below), flashes the border yellow via `BFLASH`, and resets `PLAYER_MODE=0` (control snaps back to human without waiting for fire).
- **Destroyed lasers disappear from the room art.** The room maps always have every laser drawn in, so `genworld.py` precomputes per laser a patch list (`LASER_ART_n`, via `LASER_ART_LO/HI`): every cell under the laser rect (its tiles' 2×2 chars ±1 char row, to catch the emitters) whose screen code is in `art.laser_tiles` in `titan.yaml`, with its replacement — the char on both sides if they match (so a beam crossing a wall leaves the wall continuous), else `art.floor_tile`. `ERASE_LASER` (Y = laser index) writes those cells + their `TILE_COLORS` colour; it runs from `ROBOT_LASER_DEATH` and at the end of `DRAW_ROOM` for every destroyed laser in `CUR_ROOM` (so room changes / popup / map / terminal redraws keep it erased; `RESET_ROUND` re-arms lasers before redrawing, so a respawn brings the beam back). The build warns if a laser has no `laser_tiles` under it — usually art and config have drifted apart. New laser glyphs in the charset must be added to `laser_tiles`.
- **Beams flicker.** `ANIM_LASER` (`game.asm`, every 8 game frames from `GAME_ALIVE`) XORs the beam glyph (`$81`) and the beam halves of the emitters (`$82` rows 4–7, `$83` rows 0–3) with `LASER_DASH` (`$18`) **in the charset at `$2800`** — the dashes alternate rows, so this swaps their phase and every beam on screen animates at once with no screen writes. If the laser glyphs are redrawn in vchar64, keep that alternating-row pattern (or update `ANIM_LASER`).
- The terminal blocks re-linking to a destroyed robot: its menu row is dark grey and tagged "destroyed", and `TERM_ROBOT` shows `TMSG_DEAD` instead of linking.

### Sprite collision
`CHECK_SPRITE_HIT` reads `VIC_SPCOLL` (`$D01E`) each frame after all three sprites are positioned. Bit 0 (sprite 0 / player) non-zero means the player overlapped any other enabled sprite. The response is the same as a laser death — both call `PLAYER_DIE` (red border, `DEATH_TMR = ZAP_LEN`, `SOUND_ZAP_START`), so there is one death effect. `$D01E` is cleared by the hardware on read — **but nothing reads it during the death pause** (`DO_GAME` skips `CHECK_SPRITE_HIT` while `DEATH_TMR` runs), so the collision of a robot kill stays latched while the two sprites sit overlapped. `RESET_ROUND` therefore turns all sprites off while it redraws, positions them, reads `$D01E` once to discard the stale hit, and only then re-enables the player sprite; without that, every robot kill killed the respawned player again on its first frame (a second flash, and the time penalty charged twice). (With only 2 sprites the old code checked `bits 0-1`; with 3 sprites a robot-vs-robot collision could set bit 1 or 2 without the player involved, so only bit 0 is checked now.)

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
- **Searching (items) — hold fire, Impossible Mission style.** `SEARCH_TICK` (`popup.asm`, called from `READ_KEYS` at `RKSEARCHCHK`) starts a search on a *fresh* fire/Space press outside a terminal zone (the terminal check runs first and takes the press) and only in human mode — **like the terminal, search is human-only**. While fire stays held, `SRCH_TMR` counts up and `MOVE_PLAYER` stands still; time and robots keep running, so searching is a risk. At `SRCH_SHOW` (10 frames — long enough to ignore a tap) a small 11×4 box saying "searching ..." appears just above the player's sprite (below it near the top wall; `SPOP_PLACE`). At `SRCH_DONE` (+50 frames) the generated `ITEM_ROOM/X/Y` tables are checked for a still-hidden (`ITEM_STATE=0`) item on the player's exact tile: if found, the small box goes and `SETUP_SEARCH` (item index in `X`) sets `ITEM_STATE=1` and shows the big popup with the item's generated found-message (`ITEM_MSG_*`, from `found_text` in `titan.yaml`); otherwise the box changes to "nothing / here" and stays until fire is released. Releasing fire at any point removes the small box. The small box (`SPOP`) saves the 44 screen + 44 colour cells under it in `SP_BUF` (`$0340`, the unused tape buffer) and restores them on close, so the room art — including an erased laser — comes back exactly; `DRAW_ROOM` resets the search (`SRCH_TMR`/`SRCH_ST`) since a full redraw makes the saved cells stale. Adding a search spot = adding an `items:` entry plus a `things:` placement in the config — no code.
- **Locked door.** `DOOR_ENTER` calls `SETUP_DOOR_LOCKED` when the door's `DOOR_KEY` item is still hidden — the door just acts like a wall.
- All three (with F2's where-am-I) funnel into the shared `SHOW_POPUP`, which draws the box/border/hint rows and takes only the message row's address via `PTR`/`PTR+1` (a 40-byte PETSCII string) — a new popup means one more message string and a one-line caller, not touching the drawing code.
- **The popup closes on a fresh Space press, not `GETIN`.** The Space press that opened it is still in the KERNAL keyboard buffer (the raster IRQ's `$EA31` tail runs the KERNAL keyboard scan every frame), so a `GETIN`-based wait closes the popup after one frame. `DO_POPUP` instead polls the CIA matrix directly with edge detection (`POPUP_ST`, `$33`: 0=opening press still held, 1=released/armed, 2=new press seen; closes on that press's release so the closing Space can't leak into `READ_KEYS` either), and drops any buffered keys (`$C6=0`) on close.
- Unlike terminal/map, the popup does **not** `CLEAR_ROOM` first — `SHOW_POPUP` only overwrites rows 8-13 with a small bordered box, so the room art stays visible underneath. `DO_POPUP` erases it on close by calling `DRAW_ROOM` (full redraw) rather than restoring specific rows.
- Time and robot patrol are paused for free, the same way terminal/map already pause them: `DO_GAME` (and hence `TICK_CLOCK`/`TICK_ROBOT`) simply isn't called while `GAME_STATE=6`.
- `ITEM_STATE` is reset only in `SETUP_GAME` (fresh game), not in `RESET_ROUND` — carried items are inventory and survive a death/respawn, unlike the actor/laser state that `RESET_ROUND` does reset.
- `DRAW_STATUS` (row 24) shows only `item:` plus the first non-hidden item's 12-char label (`label:` in `titan.yaml`, in `LTRED`).
- **Where am I (F2).** Room number and the 2-digit tile X/Y of whoever is driven are no longer on the status line; **F2** (shift+F1, hard to hit by accident on a real C64) opens them in the big popup instead (`SETUP_WHERE` patches the digits into `SBOX_MSG_WHERE`, then `SHOW_POPUP`). `READ_KEYS` scans F1 + either shift on the matrix and edge-detects in `F2_PREV` (`$30`), so a held F2 doesn't reopen it after closing. It works in proxy mode too.

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
$1B  DEATH_TMR    frames remaining after a laser/robot hit (`ZAP_LEN`, as long as the zap, so border, sound and pause end together); on expiry, APPLY_DEATH_PENALTY runs (see Death & Respawn)
$1C  BLINK_TMR    blink frame counter
$1D  BLINK_ST     blink state (0=visible 1=hidden)
$1E  SND_TMR      sound effect countdown (0=silent, music plays)
$1F  TERM_SEL     terminal selected menu entry (0..TERM_N-1)
$20  FIRE_PREV    fire/space held (0/1) as of this frame's READ_KEYS (DRAW_ROOM sets 1: a new press is needed after any screen change)
$21  NEAR_TERM    non-zero when player is adjacent to terminal
$22  PLR_DYING    1 = the human is sliding into a laser; UPDATE_SPRITE0 kills the player on arrival (RESET_ROUND clears it)
$23/$24 ROWS_PTR  DRAW_ROWS row-list pointer
$25  CUR_ROOM     current room index (into world.asm ROOM_* tables)
$26  SRCH_TMR     search: frames fire held (0 = not searching; caps at SRCH_DONE)
$27  NEWX         candidate tile X for the move being attempted
$28  NEWY         candidate tile Y (MOVE_PLAYER/MOVE_ACTOR/patrol/sprite scratch)
$29  PLR_DIR      player facing (DIR_DOWN/UP/LEFT/RIGHT = 0-3)
$2A  PLR_ANIM     player walk frame (0=rest 1=walk1 2=walk2)
$2B  ANIM_CNT     free-running game-frame counter (hover animation)
$2C  SRCH_ST      small search popup: 0 none, 1 "searching", 2 "nothing here"
$2D  ROB_TMR      robot movement timer (shared by all actors, ROB_PERIOD = 16 frames)
$2E  GL_SX        GLIDE speed X, px/frame (smooth movement)
$2F  GL_SY        GLIDE speed Y, px/frame
$30  F2_PREV      F2 held last game frame (edge detect for the where-am-I popup)
$31  PLAYER_MODE  0=human (PLR_X/Y)  else actor index+1 (proxy mode, ACT_X/Y)
$32  KEY_X        X key flag (exit robot proxy mode; fire does the same)
$33  POPUP_ST     popup close edge-detector (0=opener held, 1=armed, 2=pressed)
$34  JOY_PREV     joystick 2 bits held last frame (1=pressed; 0 U 1 D 2 L 3 R 4 fire)
$35  KEY_SPC      fire or Space *freshly pressed* this frame (enter terminal, start a search, end a robot link)
$36  JOY_NEW      joystick 2 bits newly pressed this frame (set in MAIN_LOOP)
$37/$38 PTR3      third pointer (search popup colour RAM)
$39  SP_ROW       search popup top screen row
$3A  SP_COL       search popup left column
$3B  SP_R         SPOP row being processed
$3C  SP_MODE      SPOP mode (save/draw/restore)
```

Free zero-page slots: `$3D+`. (`$0340`–`$0397` in the tape buffer is the search popup's `SP_BUF`.) Per-robot positions, laser/item state etc. moved to RAM arrays at the end of `src/world.asm` (`ACT_X/Y/TGT/ALIVE/DIR/ANIM`, `GL_PXL/PXH/PY`, `ITEM_STATE`, `LASER_STATE`, `SPR_SLOT_ACT`) — indexed with `,x`, sized by the config.

## Room Map

The playfield (screen rows 2–23) is a custom-charset top-down map, 22 rows × 40 chars, authored in vchar64 (see `graphics/` and `src/charset.asm`). Positions are in 2×2-char tiles (20×11 per room). Tile colours come from `TILE_COLORS` (indexed by screen code), not a hand-written switch.

Interior walls are derived from the room art at build time (see "Interior walls" above). So are terminals (from `art.terminal_tiles`). Everything else — lasers, doorways, item spots — is **not** detected from tile bytes: their logical positions come from `titan.yaml` (tile coordinates/rectangles), so the art and those config coordinates can silently drift out of visual sync; check new room art against the config before relying on it. Current config:

| Feature | Config (titan.yaml) | Colour |
|---------|---------------------|--------|
| Laser wall | room1 laser rect X=9, Y 0–10 — kills player on contact, unless destroyed (`LASER_STATE`) | Lt Red (visual) |
| Terminals | found in the art: room1 zones X 0–2 and X 16–18, room2 zone X 16–18, all Y 0–2 (the consoles against the top wall); press fire | Lt Green (visual) |
| Room 1 ↔ room 2 doorway | door rects at x=-1 (room1) / x=20 (room2), Y 5–6 | — |
| Win exit | room2 door rect y=11, X 6–10, `leads_to: exit`, `key: red_card` — locked popup without the card | — |

## HUD Layout (row 0, 40 chars)

```
human     reactor: [########]   00:00:00
^   ^     ^      ^ ^^       ^   ^      ^
0   4    10     17 1920    28  32     39
```
Mode (`human` cyan / `robot` green) on the left, the gauge block centred (`HUD_BAR` = 20, first segment), the clock right-aligned (`HUD_CLK` = 32; white, light red under 10 minutes).
(`#` = one thermometer segment, a solid block `$E0`; row 1 below the HUD is a full row of `CH_HBLK` in blue as a separator.)

The reactor gauge visualises the countdown (nothing in the game reads it back). `TICK_REACTOR` sets `REACT_TEMP = 99 − M·89/START` every frame, with `M = CLK_H*60+CLK_M` (minutes left) and `START` the starting countdown in minutes — 10% at mission start (one green segment, clearly safe), 99% as the clock runs out, and a death penalty visibly heats it up. To avoid a runtime division it multiplies `M` by `REACT_K = REACT_SPAN*256/START` (`REACT_SPAN` = 89 = 99 − the starting 10%) (an assembly-time constant from `CFG_CLK_H/M`) and takes the high byte; `genworld.py` rejects a `start_time` under one minute. It also re-rolls a 0–3 flicker (`REACT_JIT`) every 8 frames; the shown value is `REACT_TEMP+REACT_JIT` (capped 99). `DRAW_HUD_DYNAMIC` draws it as an 8-segment thermometer in columns 20–27 (no number — the bar is the whole display): solid blocks (`CH_SOLID` = `$E0` — not `$A0`, which is a room tile in the custom charset), `(shown+6)/12` segments lit in their zone colour from `REACT_ZONES` (4 green, 2 yellow, 2 red), the rest dark gray. Note `DEC2` clobbers `TMP`/`TMP2`/`X` — keep anything you need across it on the stack.

## Visual Style

- Tilted top-down oblique 2.5D perspective (similar to *Cadaver* / *The Last Ninja*)
- VIC-II hardware sprite priority flag used for depth: sprite priority flips when the player walks "behind" tall tiles
- Color palette: C64 dark registers (dark grays, muted blues, deep browns) with high-contrast multi-color tiles
- Flip-screen room transitions (no scrolling); screen RAM blasted per transition
- Charset: custom vchar64-authored charset at `$2800` (`$D018 = $1A`); `$0291 = $0E` written at init

## Custom Charset / Screen Art

Room/HUD art is authored with **vchar64** (charset + screen + colour editor). `graphics/` holds the single vchar64 project for all rooms (`titan.vchar64proj`) plus its ASM exports: `titan-charset.s` (charset), `titan-tile-colors.s` (colour per char), `titan-mapNN.s` (one per room, referenced by `vchar64_map:` in `titan.yaml`) and `titan-char-colorsNN.s` (per-cell colours, not used — the game colours by char via `TILE_COLORS`). The old per-room projects are in `graphics.old/`. `src/charset.asm` is generated from the first two by `tools/gencharset.py` and `!source`d from `titanfall.asm` after `map.asm`.

- **Export format: ASM**, not BIN/PRG. Fits the existing convention (sprites/room data are already inline `!byte` literals in source); avoids managing binary blobs, load-header stripping, or Makefile/Exomizer changes for extra files.
- vchar64 labels its ASM export "ACME-compatible" but it isn't: it emits `.byte` (64tass/KickAssembler syntax), which ACME rejects. So no export is `!source`d directly: `gencharset.py` and `genworld.py` parse the `.byte` lines and re-emit them as `!byte` (and check the sizes: 2048 / 256 / 880 bytes). Just re-export from vchar64 and run `make`.
- **Charset lives at `$2800`** (2K-aligned, in the gap between end-of-code/`TILE_COLORS` and the sprite block at `$3000`; moved up from `$2000` once code growth started colliding with it — see the gotcha below). `$D018 = $1A` selects screen `$0400` / charset `$2800`. A-Z, digits, and the box-drawing glyphs (`G_HORIZ_BAR`, `G_VERT_BAR`, rounded corners, etc.) used by the intro/gameover/win screens keep their default-ROM-charset code points and shapes — only unused graphics-character slots were repurposed for room-art tiles, so those three screens needed no changes.
- **`TILE_COLORS`** (in `src/charset.asm`, right before the `CHARSET` data) is a 256-byte table indexed by screen code, giving the default colour RAM value for each tile. `COL_BYTE` in `game.asm` does a straight `lda (PTR),y : tax : lda TILE_COLORS,x` lookup instead of switching on individual byte values — **`X` is the caller's page counter in `DRMCPG` and must be saved/restored across the call** (`txa:pha` / `pla:tax`), since `COL_BYTE` needs `X` itself to index the table.
- **Room data is raw screen codes, not PETSCII.** The `ROOM_MAP_n` blocks in the generated `world.asm` (converted by `genworld.py` from the `vchar64_map:` files listed in `titan.yaml`, `.byte`→`!byte`) are blitted straight from `(PTR),y` to `(PTR2),y` in `DRAW_ROOM` with no `PET2SCREEN` conversion (the vchar64 export already emits screen codes). Don't add a `PET2SCREEN` call back in if editing this path.
- **Collision is byte-driven only for walls, and only at build time.** `genworld.py` turns the wall chars (`art.solid_tiles`) in each room map into the `ROOM_WALLS_n` tile grid; the game never inspects screen RAM. Terminals are found in the art too (`art.terminal_tiles`, see "New terminal"). Lasers and doorways still come from the `titan.yaml` tables, so the art and those coordinates can silently drift out of visual sync; check new room art against the config rectangles before relying on it.
- Screen/colour canvases are authored at 22 rows in vchar64 (matching the runtime playfield — 2 HUD rows + 1 status row are drawn by game code, not part of the room art).

## Critical Gotchas

### Code growth can silently corrupt TILE_COLORS/CHARSET — watch for ACME warnings
`TILE_COLORS` (256 bytes, in `src/charset.asm`) has no fixed address — it starts wherever the code before it (all of `titanfall.asm` + every `!source`d module) happens to end, and `CHARSET` right after it is pinned to a fixed, 2K-aligned address (`* = $2800`). If code+`TILE_COLORS` ever grows past that fixed address, ACME does **not** fail the build — it prints `Warning - ... Segment starts inside another one, overwriting it.` and silently truncates the tail of `TILE_COLORS`, whose bytes get overwritten by the start of `CHARSET`. Since most room tiles use screen codes in the `$80s`-`$A0s`, this corrupts colour lookups for most of the room art (tiles render in wrong/black colours) while leaving the charset bitmaps themselves intact — exactly the "graphics look horrible, wrong colours" symptom, with no build error to point at it.
- **Always check `make`'s full output for `Warning` lines, not just for a nonzero exit code** — a successful build can still have silently corrupted data.
- To check headroom: `acme -f cbm -o /tmp/g.prg -l /tmp/labels.txt src/titanfall.asm` then `grep TILE_COLORS /tmp/labels.txt` — its start address + 256 must stay under `CHARSET`'s fixed address. **As of 2026-10-07 `TILE_COLORS` starts at `$24D3`, leaving ~550 bytes.** Unrolled 40-byte row-copy loops are the usual bloat: prefer a `DRAW_ROWS` table (see "Screen Art") for new screens.
- Keep *data* out of the code area where possible: the intro logo, sprites and all generated world data already live above the charset (`$3000+`); prefer that for new tables/strings too.
- `CHARSET` was moved from `$2000` to `$2800` for exactly this reason (code had grown ~173 bytes past the old boundary); this freed a full extra 2KB of headroom. If it happens again, the same fix applies — bump `CHARSET`'s `* =` (emitted by `tools/gencharset.py`) to the next free 2K-aligned address (the sprite block at `$3000` and the world data after it would have to move up too) and update `VIC_VMCSB`'s value in `titanfall.asm` to match (`$D018 = (screen_base/1024)*16 + (charset_base/2048)*2`; `$0400`/`$2800` → `$1A`).

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
X key (exit proxy):col 2 (PA=$FB), row 7 (PRB bit 7 = mask $80, active low)
Space (search/terminal): col 7 (PA=$7F), row 4 (PRB bit 4 = mask $10, active low)
F1 (F2 = shift+F1): col 0 (PA=$FE), row 4 (PRB bit 4 = mask $10, active low)
Left shift:        col 1 (PA=$FD), row 7 (PRB bit 7 = mask $80, active low)
Right shift:       col 6 (PA=$BF), row 4 (PRB bit 4 = mask $10, active low)
```
**The game is fully playable with a joystick in port 2** (move, fire = hold to search / use terminal / select / end a robot link / every "press fire" prompt); the keyboard is an alternative: WASD (not cursor keys), Space, X, F2 (where am I), and in the terminal Return/cursor up/down/F7. There is no map key — the map is a terminal entry. Joystick port 2 works alongside the keyboard: `READ_KEYS` first reads `CIA1_PRA` (`$DC00`) with `PRA=$FF` (no keyboard column selected; bits 0-4 = up/down/left/right/fire, active low) and ORs the directions into the same `KEY_U/D/L/R` flags (held = move). Fire and Space are one button: `MAIN_LOOP` polls port 2 once per frame into `JOY_PREV` (held bits) and `JOY_NEW` (bits newly pressed this frame, 1=pressed); `READ_KEYS` ORs held fire (`JOY_PREV` bit 4) with the Space key, then sets `KEY_SPC` = pressed now but not in the previous game frame, `FIRE_PREV` = held now. Actions use the fresh press (`KEY_SPC`) — otherwise fire still held from the terminal's logoff would re-enter the terminal on the next frame — and the search uses the held state. `DRAW_ROOM` sets `FIRE_PREV=1`, so fire held across any screen change (terminal, map, popup, respawn, door) never counts as a new press. (Port 1 would be `$DC01`, which collides with keyboard rows; it isn't read.) The `GETIN`-driven screens also take `JOY_NEW`: fire = "press fire" on intro/game over/win/map (any key also works), and in the terminal menu fire = Return, up/down = cursor up/down. `DO_POPUP` polls fire directly with its own edge detector, alongside Space. Fire/Space does double duty: it enters the terminal inside a terminal zone (`TERMZ_*` tables) and searches anywhere else — items can't be placed in a terminal zone (the build fails), since the terminal check wins (it runs first in `READ_KEYS`). There used to be a dedicated T key for the terminal; it was removed in favor of reusing Space. If a key seems to trigger the wrong action, re-derive its column/row from the matrix table rather than guessing; `col`/`row` values that look adjacent (e.g. row 4 vs row 6) are an easy transcription error.

Terminal menu keyboard navigation uses `GETIN` (KERNAL keyboard buffer) for PETSCII codes: `$11`=cursor down, `$91`=cursor up, `$0D`=Return, `$88`=F7 (leave). Space is deliberately not "select" there: the Space press that opened the terminal is still in the KERNAL buffer.

### Sector map
Generated entirely by `genworld.py` (`build_map`) from the doors — nothing is hand-drawn. Each door's rectangle says which wall it's on (`door_dir`: left/right/up/down — it must lie outside the room), so starting from the start room every door places the room it leads to in the neighbouring grid cell; the build **fails** if two doors disagree about where a room is, two rooms land on one cell, a room isn't reachable through doors, an exit faces another room, or the layout doesn't fit the 22×40 map screen. Each room is a 4-row box (rounded corners, `label:` from `titan.yaml`, default the room's name; up to 12 wide, narrowed to fit), connected rooms get a cyan corridor (two lines between the boxes, the walls turning into it), and every `leads_to: exit` door gets an opening in that wall plus a white stub and "exit" label outside it. Title and prompt are centred above/below. The result is emitted as `MAP_SCR` (screen codes) and `MAP_COL` (colours) for screen rows 2–23, with an ASCII picture of the map in the comments of `world.asm`; `SETUP_MAP` just copies both and paints the current room's box light green from `MAPHL_*` (also generated from the layout). The old `map_view:` room key is rejected.

### Terminal menu
`SETUP_TERMINAL` builds the menu on entry from the actor tables: one entry per robot in `CUR_ROOM` (rows 8–9, at most 2 per room; text from the generated `ACT_TROW_n` row — `name:` from `titan.yaml`, plus "locked" for `locked: true`; a destroyed robot gets "destroyed" drawn over cols 28–36), then **view map** (row 11) and **logoff** (row 12). With no robots in the room, row 8 shows "no units in this sector". `TM_ACT`/`TM_ROW` (per entry: actor index or `TM_MAP`/`TM_LOGOFF`, and screen row) and `TERM_N` drive `TERM_DRAW_SEL` (colours, `>` marker) and `TERM_FIRE`. View map `jsr SETUP_MAP`s; leaving the map (`DO_MAP`) calls `SETUP_TERMINAL` again with `TERM_SEL` still on "view map" (`READ_KEYS` zeroes `TERM_SEL` before a fresh entry).

### Sprite data placement
All sprite frames live in one block at `$3000` (see "Sprites"), which must stay inside VIC bank 0 and outside `$1000–$1FFF` (the VIC sees the character ROM there, not RAM). No runtime copy loop. Pointers are `address/64` — always computed from labels, never hard-coded.

### Sprite collision register clears on read
`VIC_SPCOLL` (`$D01E`) is cleared by the hardware the moment it is read. Read it exactly once per frame in `CHECK_SPRITE_HIT` and act on the value immediately — reading it again will always return 0.

### Extended (9-bit) sprite X
Sprite X is 9 bits: `X pixel = tile*16+20` exceeds 255 for tiles 15–19, and then the slot's `VIC_SP_MSB` bit must be set or the sprite wraps to the left side of the screen. `TILE_TO_PIXEL_X` (`game.asm`) returns the low byte in A and bit 8 in carry; it computes `(tile*8+10)*2` so the only possible overflow is the final `asl`, which lands straight in carry (an earlier 24 px/tile version computed two adds and lost the first add's overflow — keep any future change to the formula to a single overflow point). `GL_TARGET` stores the carry in `GLT_H`, which ends up in `GL_PXH`.

## SID / Music

### Background music
`music/Licence_to_Kill.prg` is the Licence to Kill SID tune (David Whittaker, 1989 Domark), loading at `$C000–$CFFF` (PSID, 5 subtunes; the game plays tune 1). The Makefile packs it into `titanfall.prg` via exomizer.

- **Init:** `lda #0 : jsr $C000` — called once during startup (after SID clear, before `cli`). `A` selects the subtune (0 = tune 1).
- **Play:** `jsr $C127` — called from `RASTER_IRQ` every frame (50 Hz PAL). (The old Armalyte tune used `$C059` — if the music file is swapped, the play address in `RASTER_IRQ` must change with it; check with `sidplayfp -v <file>.sid`.)
- **Sound effect interlock:** while `SND_TMR > 0`, `RASTER_IRQ` calls `SOUND_TICK` instead of `$C127`, giving the effect (the laser zap) exclusive SID control. Music resumes automatically when `SND_TMR` reaches 0.
- Candidate replacement tunes that fit the `$C000–$CFFF` window are listed in `music/possible_songs.txt` (HVSC scan via `music/find_sids_in_range.py`); `music/README.txt` documents the sid→prg conversion (`psid64`).

### $D418 (master volume) discipline
The Whittaker player writes `$D418` itself during play (unlike the old Armalyte player, which set it only at init — the original reason for this rule). But while `SND_TMR > 0` the play routine is not called, so nothing restores volume during the death-sound window:

**Rule:** never leave `$D418` at `$00`. `SOUND_ZAP_START` sets `$D418 = $0F` (the zap fades through `$D418` but never reaches 0), and `SNDOFF` restores `$0F` after gating off voice 1. `SETUP_GAMEOVER` and `SETUP_WIN` must not write to `$D418` — let music continue. `SND_TMR` is zeroed explicitly in the init before `cli` — the KERNAL may leave `$1E` non-zero, which would permanently block music in intro.

### Sound effects
Voice 1. There is a single effect (the old falling-sawtooth death sweep was dropped — every death now uses the zap); a second effect would need a selector variable again (`$2C` is free):
- **Laser zap** (`SOUND_ZAP_START`, `ZAP_LEN` = 40 frames) — the "bzzzt": a thin 12.5% pulse at ~60–90 Hz (mains-hum range, pitch jittered from `LFSR_ST`) alternating every frame with a high noise crackle, a one-frame gate drop every 8 frames for the stutter, fading out through `$D418` over the last 15 frames. Used for every human death (`PLAYER_DIE`: laser in `TRY_MOVE`, robot in `CHECK_SPRITE_HIT`) and when a driven robot burns out a laser (`ROBOT_LASER_DEATH`).
It sets `$D418 = $0F` on start, and `SNDOFF` gates off and restores `$0F` at the end.

## Screen Art

Non-game screens (intro, game over, win) use a PETSCII box design: a bordered panel (rows 3–13 on game over / win, rows 12–21 under the logo and author line on the intro) drawn at 50 Hz by the relevant setup routine. All three share the subroutine `DRAW_INTRO_SCREEN` for the intro layout (called from `SHOW_INTRO`, the `DO_GAMEOVER` restart path, and the `DO_WIN` restart path).

**Row lists.** `DRAW_ROWS` (`titanfall.asm`, A/Y = list address) draws a screen from a table of `(screen row, colour, string lo, string hi)` entries ended by `$FF` — the terminal (`TERM_ROWS`) and popup (`SBOX_ROWS`) use it instead of one unrolled copy loop per row. `DRAW_ROW` draws a single row (A = row, `PTR` = string, `TMP2` = colour), `PAINT_ROW` recolours the row at `PTR2`, `ROW_PTR` turns a row number into its screen address.

### Shared string labels (each exactly 40 bytes)
- `SCR_BORDER_TOP` — rounded top border (`G_RD_UL` + 38 × `G_HORIZ_BAR` + `G_RD_UR`)
- `SCR_BORDER_BOTTOM` — rounded bottom border (`G_RD_LL` + 38 × `G_HORIZ_BAR` + `G_RD_LR`)
- `SCR_BLANK` — `G_VERT_BAR` + 38 spaces + `G_VERT_BAR` empty interior row
- `ITR_SEP` — `G_VERT_BAR  ==...==  G_VERT_BAR` separator (reused by all three screens)

**All boxes use the PETSCII line glyphs** from `src/petscii.asm` — rounded corners `G_RD_UL/UR/LL/LR`, `G_HORIZ_BAR`, `G_VERT_BAR` — never ASCII `+`, `-`, `|` (those render as plain/odd glyphs). The terminal box reuses `SCR_BORDER_TOP`/`SCR_BORDER_BOTTOM`/`SCR_BLANK`; the popup's narrower box (`SBOX_*`, columns 4–35) builds its border rows with `!fill 30, G_HORIZ_BAR`; `genworld.py` frames the generated `ITEM_MSG_*` rows with `G_VERT_BAR`; the generated sector map uses the same glyphs (as screen codes, `SC_*` in `genworld.py`). After drawing a box, call `FRAME_EDGES` (full width) / `FRAME_EDGES_LR` (columns preset in `FR_L`/`FR_R`) with the frame colour so the `G_VERT_BAR` ends don't inherit each row's text colour.

All string-copy loops call `jsr PET2SCREEN` to convert PETSCII to screen codes before writing to screen RAM. `PET2SCREEN` is defined in `src/titanfall.asm` after `CLS`.
- `ITR_TAG`, `ITR_M1`–`ITR_M3` — intro panel content (the intro has no title row in the box any more — the logo above it replaces it)
- `GO_TITLE`, `GO_M1`–`GO_M3` — game over panel content
- `WIN_TITLE`, `WIN_M1`–`WIN_M3` — win panel content
- `TXT_PRESS`, `TXT_GOPRESS`, `TXT_WINPRESS` — blinking footer prompts

Star characters (`*`) in the game over / win titles are recoloured to YELLOW after the row loop by writing to individual CRAM addresses.

**Intro layout:** `DRAW_INTRO_SCREEN` copies the logo (`TITLE_SCR`/`TITLE_COL`, raw screen codes, no `PET2SCREEN`) into rows 1–8, the unframed author line (`ITR_AUTH`, "by johan berntsson", centred from its own length `ITR_AUTH_LEN`, MGRAY) on row 10, draws the mission box in rows 12–21 (top border, blank, tagline, separator, blank, 3 mission lines, blank, bottom border), and `BLINK_ON`/`BLINK_OFF` blink the prompt on row 23 (`SCRN+920`). The logo's solid block is screen code 224 (`$E0`), not the usual 160 (`$A0`) — `$80–$A2` in the custom charset are room-art tiles, and `$E0` is the other all-ones glyph in the ROM font. Any new full-screen PETSCII art must likewise avoid `$80–$A2` (check `src/charset.asm`).

## Current Status

The core puzzle loop is in place and playable end-to-end: explore, take over the splicer via the terminal, drive it into the laser (it slides into the beam, the beam vanishes from the art with a "bzzzt"), search for the access card, and reach the win screen through the now-unlockable room 2 door — with a real risk/reward death penalty (lose time + respawn) instead of an instant Game Over, and Game Over genuinely tied to the countdown clock hitting zero.

The world is **config-driven**: rooms (bounds, player start, vchar64 map), robots (type, start, patrol waypoints), items (position, label, found-text), doors (rect, destination, arrival position, key), lasers, the starting clock, the death penalty and the art codes (floor, laser, wall chars) all live in `titan.yaml` and are compiled into `src/world.asm` data tables at build time. Interior walls, terminals and the laser-erase patches are derived from the room art by `genworld.py` (and the sector map from the doors), which also rejects placements inside walls. Adding a room = a vchar64 map export + a `rooms:` entry + its doors; the sector map is generated from the doors. Adding an item, door, laser or robot is config-only.

Presentation (as of 2026-10-06): multicolour animated sprites with 4-way facing (walker player, walking robots in room 1, hovering drone in room 2), smooth gliding movement between tiles, a PETSCII block-letter title logo + author line on the intro, rounded PETSCII frames with uniform frame colours on every box (intro, game over, win, terminal, popups, sector map), and a working reactor thermometer tied to the countdown. The obvious visual glitches (robots over the terminal, wrong spawn in room 2, walking through walls, blank reactor HUD, terminal cursor on several rows) are fixed.

Controls and interface (as of 2026-10-06): the game is fully joystick-driven (keyboard still works as an alternative). Fire opens a terminal (any console in the art), selects in menus, ends a robot link, and — held — searches, Impossible Mission style (small "searching" / "nothing here" box by the player, the big popup on a find; time and robots keep running). The terminal menu lists the robots in the current room (generated, with `locked:`/destroyed states), then "view map" and "logoff"; there is no map key. HUD: mode left, reactor gauge centred, clock right. A robot catching the player and walking into a laser give the same single death (the player slides onto the beam first); the laser beams flicker via the charset. Everything about positions is on a 2×2-char (16×16 px) tile grid; walls, terminals, the laser-erase patches, the sector map and the charset are all generated at build time from the art and the doors.

## What's Not Yet Implemented

- Robot abilities: every linkable robot drives the same way (any of them would burn out a laser); the per-type capabilities from the design (loader immune to lasers, splicer through ducts, centurion armed) aren't implemented. The room-1 sentry is `locked: true` so the splicer stays the puzzle's key
- Item states `carried` vs `used` aren't distinguished yet — door keys accept either, nothing sets `used` (=2)
- `ai:` in `titan.yaml` only accepts `patrol` (two-waypoint shuttle); no other AI routines exist yet
- Max 2 robots per room (hardware sprites 1–2; enforced by `genworld.py`) — a sprite multiplexer is deliberately out of scope
- The reactor gauge is display-only — nothing happens when it's in the red (an idea: make it a real hazard)
- Weapons: the bolt and force-field sprites exist (see "Sprites") but nothing uses them yet. With 3 of the 8 hardware sprites in use (player + 2 robots), sprites 3–7 are free for projectiles/effects without a multiplexer
- Room 2's drone patrols only X 3–11, leaving the right third of the room unguarded
- Furniture is walk-through (not in `art.solid_tiles`); walls only check the sprite's feet, so the upper body overlaps wall art in the oblique view (intended)
- Every terminal shows the same menu (the current room's robots, map, logoff); there's no per-terminal behaviour yet (e.g. a terminal that only reaches certain robots or unlocks something)
- The code area has ~550 bytes left before `CHARSET` at `$2800` — keep new tables/strings in generated data above `$3000` where possible (see the TILE_COLORS gotcha)
