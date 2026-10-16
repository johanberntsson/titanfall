/* Laser traps (art.trap_tiles): while the human stands in a trap's tile
 * column its beam is on, from under it down to the first solid tile; a
 * step into it kills, and it fries robots. (traps.asm) */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"

/* the first tile row below trap t (from TRAP_Y0) that's solid and not a
 * pit, or past the bottom */
static uint8_t trap_reach(uint8_t t)
{
    uint8_t y = TRAP_Y0[t];
    while (y <= ROOM_MAXY[cur_room]) {
        uint8_t b = wall_at(cur_room, TRAP_X[t], y);
        if (W_BLOCKED(b) && !W_PIT(b))
            break;
        y++;
    }
    return y;
}

/* trap t's char column from under the trap to above tile row trap_len:
 * the beam (draw) or the room map's chars (ROOM_BUF) */
static void trap_rows(uint8_t t, bool draw)
{
    uint8_t end = trap_len * 2;
    for (uint8_t r = TRAP_ROW1[t]; r < end; r++) {
        uint16_t o = r * 40 + TRAP_COL[t];
        uint8_t ch = draw ? CFG_BEAM : ROOM_BUF[o];
        SCRN[80 + o] = ch;
        CRAM[80 + o] = TILE_COLORS[ch];
    }
}

static void trap_off(void)
{
    if (!trap_on)
        return;
    trap_rows(trap_on - 1, false);
    trap_on = 0;
    room_overlays();                /* crates, filled pits, gates on top again */
}

/* the beam on if the player is in a trap's column (redrawn if its reach
 * changed), off otherwise; true if the player is in the beam */
bool trap_show(void)
{
    for (uint8_t t = 0; t < NUM_TRAPS; t++) {
        uint8_t end;
        if (TRAP_ROOM[t] != cur_room || TRAP_X[t] != plr_x ||
            plr_y < TRAP_Y0[t])
            continue;
        end = trap_reach(t);
        if (trap_on != t + 1 || trap_len != end) {
            trap_off();             /* the old one, or this one changed */
            trap_on = t + 1;
            trap_len = end;
            trap_rows(t, true);
        }
        return plr_y < trap_len;
    }
    trap_off();
    return false;
}

/* the human just stepped onto plr_x/plr_y */
void trap_check(void)
{
    if (!plr_dying && trap_show())
        plr_dying = 1;              /* stepped into the beam */
}

/* every frame: a robot in the beam on screen is destroyed */
void trap_zap(void)
{
    uint8_t t = trap_on;
    if (!t--)
        return;
    for (uint8_t a = 0; a < NUM_ACTORS; a++)
        if (ACT_ALIVE[a] == 1 && ACT_ROOM[a] == cur_room &&
            ACT_X[a] == TRAP_X[t] && ACT_Y[a] >= TRAP_Y0[t] &&
            ACT_Y[a] < trap_len)
            zap_actor(a);
}
