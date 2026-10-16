/* Movable crates and mirrors: a driven push: true robot pushes one tile on;
 * onto a pit it fills it. A crate is solid + searchable in the wall grid
 * wherever it is, so everything that asks wall_at sees it. (crates.asm) */
#include "titan.h"

#define CR_SOLID (W_SOLID | W_SEARCH)

/* does reset_room reset room? (every room on a new game, else CUR_ROOM) */
bool rs_mine(uint8_t room)
{
    return rs_all || room == cur_room;
}

/* reset_room: the crates back to their start tiles and the pits they
 * filled open again. Two passes over the crates (one may stand on
 * another's start tile), the pits in between. */
void crate_reset(void)
{
    uint8_t i;

    for (i = 0; i < NUM_CRATES; i++)
        if (rs_mine(CRATE_ROOM[i]) && CRATE_X[i] != 0xFF)
            *wall_ptr(CRATE_ROOM[i], CRATE_X[i], CRATE_Y[i]) &= ~CR_SOLID;
    for (i = 0; i < NUM_PITS; i++)
        if (rs_mine(PIT_ROOM[i]) && PIT_FILLED[i]) {
            PIT_FILLED[i] = 0;
            *wall_ptr(PIT_ROOM[i], PIT_X[i], PIT_Y[i]) = PIT_WB[i];
        }
    for (i = 0; i < NUM_CRATES; i++)
        if (rs_mine(CRATE_ROOM[i])) {
            CRATE_X[i] = CRATE_SX[i];
            CRATE_Y[i] = CRATE_SY[i];
            *wall_ptr(CRATE_ROOM[i], CRATE_X[i], CRATE_Y[i]) |= CR_SOLID;
        }
    gate_roomreset();               /* a gate held open by plates closes */
}

/* Tile x/y of the screen with TILE_COLORS colours: mode 0 the room map's
 * chars (ROOM_BUF: where a crate left), 1 plain floor (a filled pit),
 * 4 + kind*4 a crate/mirror (CRATE_CH). */
void crate_paint(uint8_t x, uint8_t y, uint8_t mode)
{
    static const uint8_t CELL[4] = { 0, 1, 40, 41 };
    uint16_t o = (uint16_t)y * 80 + x * 2;

    for (uint8_t i = 0; i < 4; i++) {
        uint16_t c = o + CELL[i];
        uint8_t ch = mode == 0 ? ROOM_BUF[c]
                   : mode == 1 ? CFG_FLOOR : CRATE_CH[mode - 4 + i];
        SCRN[80 + c] = ch;
        CRAM[80 + c] = TILE_COLORS[ch];
    }
}

static uint8_t crate_look(uint8_t i)
{
    return 4 + CRATE_KIND[i] * 4;
}

/* draw_room: CUR_ROOM's crates where they are, its filled pits as floor */
void crate_draw_all(void)
{
    uint8_t i;
    for (i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == cur_room && CRATE_X[i] != 0xFF)
            crate_paint(CRATE_X[i], CRATE_Y[i], crate_look(i));
    for (i = 0; i < NUM_PITS; i++)
        if (PIT_ROOM[i] == cur_room && PIT_FILLED[i])
            crate_paint(PIT_X[i], PIT_Y[i], 1);
}

/* Can a crate go to x/y of room (pushed by actor a)? Plain floor (wall
 * byte 0 apart from the searched bit) or a pit (*pit set), no active
 * laser, nobody on it. */
static bool cr_free(uint8_t a, uint8_t room, uint8_t x, uint8_t y, bool *pit)
{
    uint8_t b = wall_at(room, x, y) & ~W_SEARCHED;

    *pit = (b & ~W_SEARCH) == W_TARGET;     /* bit 1 alone */
    if ((b && !*pit) || laser_at(room, x, y))
        return false;
    for (uint8_t i = 0; i < NUM_ACTORS; i++)
        if (ACT_ALIVE[i] && ACT_ROOM[i] == room &&
            ACT_X[i] == x && ACT_Y[i] == y)
            return false;
    /* the human, frozen at the terminal, if it's there */
    return !(room == cur_room && plr_x == x && plr_y == y);
}

/* crate i into the pit at x/y: the pit becomes floor, the crate leaves the
 * game until a room reset */
static void cr_fill(uint8_t i, uint8_t room, uint8_t x, uint8_t y)
{
    *wall_ptr(room, x, y) = 0;
    CRATE_X[i] = 0xFF;
    for (uint8_t p = 0; p < NUM_PITS; p++)
        if (PIT_ROOM[p] == room && PIT_X[p] == x && PIT_Y[p] == y)
            PIT_FILLED[p] = 1;
    if (room == cur_room)
        crate_paint(x, y, 1);
}

/* From try_act: driven actor a drives into the solid tile ox/oy. True if
 * it's a crate it can push and the push happened (the crate moved one
 * tile on; the actor steps onto ox/oy), false = blocked. */
bool crate_push(uint8_t a, uint8_t ox, uint8_t oy)
{
    uint8_t i, room = ACT_ROOM[a], nx, ny;
    bool pit;

    if (!TYPE_PUSH[ACT_TYPE[a]])
        return false;
    for (i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == room && CRATE_X[i] == ox && CRATE_Y[i] == oy)
            break;
    if (i == NUM_CRATES)
        return false;
    nx = ox * 2 - ACT_X[a];         /* the tile beyond: crate + (crate - robot) */
    ny = oy * 2 - ACT_Y[a];
    if (nx > ROOM_MAXX[room] || ny > ROOM_MAXY[room] ||
        !cr_free(a, room, nx, ny, &pit))
        return false;
    if (pit) {
        cr_fill(i, room, nx, ny);
    } else {
        *wall_ptr(room, nx, ny) |= CR_SOLID;
        CRATE_X[i] = nx;
        CRATE_Y[i] = ny;
        sw_enter(room, nx, ny);     /* onto a switch: flip (switches.c) */
        if (room == cur_room)
            crate_paint(nx, ny, crate_look(i));
    }
    *wall_ptr(room, ox, oy) &= ~CR_SOLID;   /* the old tile shows the map */
    if (room == cur_room) {
        crate_paint(ox, oy, 0);
        beam_update();              /* a mirror moved: retrace (beam.c) */
    }
    return true;
}
