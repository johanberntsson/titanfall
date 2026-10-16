/* Toggle switches and red/green blocks. All switches of a room share one
 * state (SW_STATE): a red block is up (solid) while it's off, a green one
 * while it's on. A switch flips when the human, a walking robot or a
 * pushed crate enters it -- in any room. A rising block crushes; a crate
 * on a block jams it. A switch door is a block of colour 2 (closed like a
 * red one). (switches.asm) */
#include "titan.h"

/* a crate of room standing on x/y? */
static bool blk_crate(uint8_t room, uint8_t x, uint8_t y)
{
    for (uint8_t i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == room && CRATE_X[i] == x && CRATE_Y[i] == y)
            return true;
    return false;
}

/* does room have any crates? (blk_crate is called per block) */
static bool room_crates(uint8_t room)
{
    for (uint8_t i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == room)
            return true;
    return false;
}

/* the blocks of room just set: whoever stands on one that rose is crushed
 * -- the human dies, a robot is destroyed. (The asm checks every actor for
 * every rising block; here each of the room's robots is checked once, or
 * an off-screen metronome flip cost a whole frame.) */
static void blk_crush(uint8_t room)
{
    for (uint8_t b = 0; b < NUM_BLK; b++)
        if (BLK_ROOM[b] == room && room == cur_room &&
            plr_x == BLK_X[b] && plr_y == BLK_Y[b] &&
            *wall_ptr(room, plr_x, plr_y) == W_SOLID &&
            !(death_tmr | plr_dying))
            player_die();
    for (uint8_t a = 0; a < NUM_ACTORS; a++) {
        uint8_t x = ACT_X[a], y = ACT_Y[a];
        if (ACT_ALIVE[a] != 1 || ACT_ROOM[a] != room ||
            *wall_ptr(room, x, y) != W_SOLID)
            continue;               /* (a robot on a solid tile: a block rose) */
        for (uint8_t b = 0; b < NUM_BLK; b++) {
            if (BLK_ROOM[b] != room || BLK_X[b] != x || BLK_Y[b] != y)
                continue;
            if (room == cur_room) { /* seen: zap + yellow flash */
                zap_actor(a);
            } else {
                ACT_ALIVE[a] = 0;
                if (DRIVEN(a))
                    player_mode = 0;
            }
            break;
        }
    }
}

/* is block b up in its room's state? (a switch door goes with red) */
static bool blk_up(uint8_t b)
{
    return (BLK_COL[b] & 1) == SW_STATE[BLK_ROOM[b]];
}

/* flip room's switches: every block up or down to match */
static void sw_flip(uint8_t room)
{
    bool crates = room_crates(room);

    SW_STATE[room] ^= 1;
    for (uint8_t b = 0; b < NUM_BLK; b++) {
        uint8_t x = BLK_X[b], y = BLK_Y[b];
        if (BLK_ROOM[b] != room || (crates && blk_crate(room, x, y)))
            continue;               /* (jammed by a crate) */
        *wall_ptr(room, x, y) = blk_up(b) ? W_SOLID : 0;
    }
    blk_crush(room);
    if (room == cur_room)
        sw_paint();
}

/* the tile x/y of room was just entered: one of its switches? flip */
void sw_enter(uint8_t room, uint8_t x, uint8_t y)
{
    for (uint8_t s = 0; s < NUM_SW; s++)
        if (SW_ROOM[s] == room && SW_X[s] == x && SW_Y[s] == y) {
            sw_flip(room);
            return;
        }
}

/* actor a stepped onto its tile (flying types pass over). Every robot's
 * every step: the switch's coordinates are checked inline, sw_enter only
 * on a hit. */
void sw_actor(uint8_t a)
{
    uint8_t r = ACT_ROOM[a], x = ACT_X[a], y = ACT_Y[a];
    for (uint8_t s = 0; s < NUM_SW; s++)
        if (SW_X[s] == x && SW_Y[s] == y && SW_ROOM[s] == r &&
            !TYPE_FLY[ACT_TYPE[a]]) {
            sw_flip(r);
            return;
        }
}

/* tile x/y of CUR_ROOM painted with the 4 chars at SW_PAT + p */
static void sw_tile(uint8_t x, uint8_t y, uint8_t p)
{
    static const uint8_t CELL[4] = { 0, 1, 40, 41 };
    uint16_t o = (uint16_t)y * 80 + x * 2;
    for (uint8_t i = 0; i < 4; i++) {
        uint8_t ch = SW_PAT[p + i];
        SCRN[80 + o + CELL[i]] = ch;
        CRAM[80 + o + CELL[i]] = TILE_COLORS[ch];
    }
}

/* room_overlays and every flip: CUR_ROOM's switches in their state, its
 * blocks up or down as their wall bytes say (not under a crate), its
 * switch doors closed (the map's chars) or open (floor). Not while the
 * small search popup is up. */
void sw_paint(void)
{
    uint8_t i;
    bool crates;

    if (srch_st)
        return;
    crates = room_crates(cur_room);
    for (i = 0; i < NUM_SW; i++)    /* SW_PAT: off 0, on 4 */
        if (SW_ROOM[i] == cur_room &&
            !(crates && blk_crate(cur_room, SW_X[i], SW_Y[i])))
            sw_tile(SW_X[i], SW_Y[i], SW_STATE[cur_room] * 4);
    for (i = 0; i < NUM_BLK; i++) { /* up 8 + colour*4, down 16 + colour*4 */
        uint8_t x = BLK_X[i], y = BLK_Y[i];
        if (BLK_ROOM[i] != cur_room || BLK_COL[i] >= 2 ||
            (crates && blk_crate(cur_room, x, y)))
            continue;
        sw_tile(x, y, (W_BLOCKED(wall_at(cur_room, x, y)) ? 8 : 16) +
                      BLK_COL[i] * 4);
    }
    art_list(SWD_ART[cur_room], SW_STATE[cur_room] ^ 1);
}

/* reset_room: the switches back to their start state, the blocks to match
 * (no crushing: the room is being reset) */
void sw_roomreset(void)
{
    uint8_t i;
    for (i = 0; i < NUM_ROOMS; i++)
        if (rs_mine(i))
            SW_STATE[i] = SW_START[i];
    for (i = 0; i < NUM_BLK; i++)
        if (rs_mine(BLK_ROOM[i]))
            *wall_ptr(BLK_ROOM[i], BLK_X[i], BLK_Y[i]) = blk_up(i) ? W_SOLID : 0;
}
