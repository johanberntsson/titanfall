/* Gates and pressure plates. A room has at most one gate (all its gate
 * tiles); GATE_STATE: 0 closed, 1 held open by the plates, 2 latched open
 * (a laser target was hit, or the player walked into the held-open gate)
 * -- only a new game closes a latched gate. (plates.asm) */
#include "titan.h"

/* the human, a robot (alive or dying) or a crate/mirror on x/y of CUR_ROOM? */
static bool loaded_at(uint8_t x, uint8_t y)
{
    uint8_t i;
    if (plr_x == x && plr_y == y)
        return true;
    for (i = 0; i < NUM_ACTORS; i++)
        if (ACT_ALIVE[i] && ACT_ROOM[i] == cur_room &&
            ACT_X[i] == x && ACT_Y[i] == y)
            return true;
    for (i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == cur_room && CRATE_X[i] == x && CRATE_Y[i] == y)
            return true;
    return false;
}

static bool gate_tile_at(uint8_t x, uint8_t y)
{
    for (uint8_t i = 0; i < NUM_GATES; i++)
        if (GATE_ROOM[i] == cur_room && GATE_X[i] == x && GATE_Y[i] == y)
            return true;
    return false;
}

static bool gate_occupied(void)
{
    for (uint8_t i = 0; i < NUM_GATES; i++)
        if (GATE_ROOM[i] == cur_room && loaded_at(GATE_X[i], GATE_Y[i]))
            return true;
    return false;
}

/* room's gate tiles solid (set = 1) or plain floor (0) */
static void gate_solid(uint8_t room, uint8_t set)
{
    for (uint8_t i = 0; i < NUM_GATES; i++)
        if (GATE_ROOM[i] == room) {
            uint8_t *w = wall_ptr(room, GATE_X[i], GATE_Y[i]);
            *w = (*w & 0xF0) | set;
        }
}

/* the same for room's laser target */
void tgt_solid(uint8_t room, uint8_t set)
{
    for (uint8_t i = 0; i < NUM_TGTS; i++)
        if (TGT_ROOM[i] == room) {
            uint8_t *w = wall_ptr(room, TGT_X[i], TGT_Y[i]);
            *w = (*w & 0xF0) | set;
        }
}

/* CUR_ROOM's gate open: st = 1 held, 2 latched */
void gate_open(uint8_t st)
{
    GATE_STATE[cur_room] = st;
    gate_solid(cur_room, 0);
    gate_paint();
}

static void gate_close(void)
{
    GATE_STATE[cur_room] = 0;
    gate_solid(cur_room, 1);
    art_list(ROOM_GATEART[cur_room], 1);    /* the gate's chars back */
}

/* every frame: the gate is open while every plate of CUR_ROOM is loaded */
void plate_tick(void)
{
    uint8_t st = GATE_STATE[cur_room];
    bool any = false, all = true;

    if (st == 2)                    /* latched: nothing to do */
        return;
    for (uint8_t i = 0; i < NUM_PLATES; i++)
        if (PLATE_ROOM[i] == cur_room) {
            any = true;
            if (!loaded_at(PLATE_X[i], PLATE_Y[i]))
                all = false;
        }
    if (!any)
        return;
    if (!st) {
        if (all) {                  /* all loaded: open (held) */
            gate_open(1);
            flash(GREEN);
        }
    } else if (gate_tile_at(plr_x, plr_y)) {
        GATE_STATE[cur_room] = 2;   /* the player in the gate latches it */
    } else if (!all && !gate_occupied()) {
        gate_close();
    }
}

/* a new game: every gate closed, every laser target intact */
void gate_reset(void)
{
    for (uint8_t r = 0; r < NUM_ROOMS; r++) {
        GATE_STATE[r] = 0;
        gate_solid(r, 1);
        tgt_solid(r, 1);
    }
}

/* reset_room: a gate held open by the plates closes (a latched one stays) */
void gate_roomreset(void)
{
    for (uint8_t r = 0; r < NUM_ROOMS; r++)
        if (rs_mine(r) && GATE_STATE[r] == 1) {
            GATE_STATE[r] = 0;
            gate_solid(r, 1);
        }
}

/* CUR_ROOM's gate as it is: an open one painted floor and, latched, the
 * destroyed target too (the map has them closed/intact) */
void gate_paint(void)
{
    uint8_t st = GATE_STATE[cur_room];
    if (!st)
        return;
    art_list(ROOM_GATEART[cur_room], 0);
    if (st == 2)
        art_list(ROOM_TGTART[cur_room], 0);
}

/* after cells got the map's chars back (a beam erased): repaint what's on
 * top of the map */
void room_overlays(void)
{
    crate_draw_all();
    gate_paint();
    shut_paint();
    sw_paint();
    ilk_paint();
}

/* list = map offsets (lo, hi; a $FF hi byte ends it) in CUR_ROOM: mode 0
 * floor, 1 the room map's chars, >= 2 that char; with TILE_COLORS colours */
void art_list(const uint8_t *list, uint8_t mode)
{
    for (; !(list[1] & 0x80); list += 2) {
        uint16_t o = list[0] | list[1] << 8;
        uint8_t ch = mode == 0 ? CFG_FLOOR : mode == 1 ? ROOM_BUF[o] : mode;
        SCRN[80 + o] = ch;
        CRAM[80 + o] = TILE_COLORS[ch];
    }
}
