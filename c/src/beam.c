/* Laser emitters and mirrors: an emitter fires a beam into its room all the
 * time; mirrors (movable, crates.c) turn it, the room's target is destroyed
 * by it (the gate latches open), anything else solid stops it. Anyone in
 * the beam dies. (beam.asm) */
#include "titan.h"


#define BEAM_MAX 64

static uint8_t beam_n;              /* tiles in the path on screen */
static uint8_t beam_x[BEAM_MAX], beam_y[BEAM_MAX];
static uint8_t beam_ax[BEAM_MAX];   /* 0 vertical, 1 horizontal */

/* a beam heading DIR_* hits a / or a \ mirror */
static const uint8_t TURN_SLASH[4] = { DIR_LEFT, DIR_RIGHT, DIR_DOWN, DIR_UP };
static const uint8_t TURN_BACK[4]  = { DIR_RIGHT, DIR_LEFT, DIR_UP, DIR_DOWN };

/* one cell of map row r, column c: ch, or the map's char (ch = 0) */
static void beam_cell(uint8_t r, uint8_t c, uint8_t ch)
{
    uint16_t o = r * 40 + c;
    if (!ch)
        ch = ROOM_BUF[o];
    SCRN[80 + o] = ch;
    CRAM[80 + o] = TILE_COLORS[ch];
}

/* draw the path (or the map back under it): a vertical tile is its left
 * char column, a horizontal one its top char row */
static void beam_cells(bool draw)
{
    for (uint8_t i = 0; i < beam_n; i++) {
        uint8_t r = beam_y[i] * 2, c = beam_x[i] * 2;
        if (beam_ax[i]) {
            beam_cell(r, c, draw ? CFG_BEAM_H : 0);
            beam_cell(r, c + 1, draw ? CFG_BEAM_H : 0);
        } else {
            beam_cell(r, c, draw ? CFG_BEAM : 0);
            beam_cell(r + 1, c, draw ? CFG_BEAM : 0);
        }
    }
}

/* the mirror kind standing on x/y of CUR_ROOM (1 /, 2 \), 0 = none */
static uint8_t mirror_at(uint8_t x, uint8_t y)
{
    for (uint8_t i = 0; i < NUM_CRATES; i++)
        if (CRATE_ROOM[i] == cur_room && CRATE_X[i] == x && CRATE_Y[i] == y)
            return CRATE_KIND[i];
    return 0;
}

/* x/y is CUR_ROOM's laser target, not destroyed yet? */
bool tgt_at(uint8_t x, uint8_t y)
{
    if (GATE_STATE[cur_room] == 2)
        return false;
    for (uint8_t i = 0; i < NUM_TGTS; i++)
        if (TGT_ROOM[i] == cur_room && TGT_X[i] == x && TGT_Y[i] == y)
            return true;
    return false;
}

/* the target is hit (by the beam, or a driven shooter's bolt): the gate
 * latches open, the target is walkable, both painted floor */
void tgt_destroy(void)
{
    gate_open(2);
    tgt_solid(cur_room, 0);
    gate_paint();
    sound_zap_start();
    flash(GREEN);
}

/* trace the beam from the emitter, tile by tile */
static void beam_trace(void)
{
    uint8_t e, x, y, dir, left, b, m;

    for (e = 0; e < NUM_EMITS; e++)
        if (EMIT_ROOM[e] == cur_room)
            break;
    if (e == NUM_EMITS)
        return;                     /* no emitter in this room */
restart:
    x = EMIT_X[e];
    y = EMIT_Y[e];
    dir = EMIT_DIR[e];
    beam_n = 0;
    for (left = 80; --left;) {      /* (a mirror loop can't hang) */
        x += DIR_DX[dir];
        y += DIR_DY[dir];
        if (x > ROOM_MAXX[cur_room] || y > ROOM_MAXY[cur_room])
            break;
        b = wall_at(cur_room, x, y);
        if (W_BLOCKED(b) && !W_PIT(b)) {    /* (pits: it passes over) */
            m = mirror_at(x, y);
            if (m) {
                dir = m == 1 ? TURN_SLASH[dir] : TURN_BACK[dir];
                continue;
            }
            if (!tgt_at(x, y))
                break;              /* solid: it stops here */
            tgt_destroy();
            goto restart;           /* the beam goes on through */
        }
        if (beam_n == BEAM_MAX)
            break;
        beam_x[beam_n] = x;
        beam_y[beam_n] = y;
        beam_ax[beam_n++] = dir >> 1;   /* left/right (2/3) -> 1 */
    }
    beam_cells(true);
}

/* erase the beam on screen, trace and draw it again (draw_room, and after
 * every crate/mirror push) */
void beam_update(void)
{
    beam_cells(false);
    beam_n = 0;
    room_overlays();
    beam_trace();
}

/* the end of draw_room: the gate, the emitter's beam, a trap's beam */
void room_dynamic(void)
{
    beam_n = 0;
    beam_update();
    trap_on = 0;
    trap_show();
}

bool beam_at(uint8_t x, uint8_t y)
{
    for (uint8_t i = 0; i < beam_n; i++)
        if (beam_x[i] == x && beam_y[i] == y)
            return true;
    return false;
}

/* a robot in a trap's or the emitter's beam, or crushed by a block: it's
 * destroyed (a driven one hands control back); zap, yellow flash */
void zap_actor(uint8_t a)
{
    ACT_ALIVE[a] = 0;
    if (DRIVEN(a))
        player_mode = 0;
    sound_zap_start();
    flash(YELLOW);
}

/* every frame: robots in the beam are fried, the human in it dies */
void beam_zap(void)
{
    if (!beam_n)
        return;
    for (uint8_t a = 0; a < NUM_ACTORS; a++)
        if (ACT_ALIVE[a] == 1 && ACT_ROOM[a] == cur_room &&
            beam_at(ACT_X[a], ACT_Y[a]))
            zap_actor(a);
    if (!(plr_dying | death_tmr) && beam_at(plr_x, plr_y))
        player_die();
}
