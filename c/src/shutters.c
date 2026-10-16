/* Timed shutters: barriers that open and close on their own frame clocks
 * (SH_OPEN/SH_CLOSED; SH_FIRST frames closed at the start). Closed, their
 * tiles are walls for everyone; open, plain floor. All tick together, every
 * game frame. Also bolt_solid: a driven shooter's bolt trips the room's
 * laser target. (shutters.asm) */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"

/* shutter s's tiles: solid (1) or plain floor (0), keeping bits 4-7 */
static void sh_solid(uint8_t s, uint8_t set)
{
    uint8_t end = SH_T0[s] + SH_TN[s];
    for (uint8_t i = SH_T0[s]; i < end; i++) {
        uint8_t *w = wall_ptr(SH_ROOM[s], SHT_X[i], SHT_Y[i]);
        *w = (*w & 0xF0) | set;
    }
}

/* shutter s on screen (art_list mode 0 floor, 1 the map's chars) -- not
 * while the small search popup is up */
static void sh_paint(uint8_t s, uint8_t mode)
{
    if (SH_ROOM[s] == cur_room && !srch_st)
        art_list(SH_ART[s], mode);
}

void shut_reset(void)
{
    for (uint8_t s = 0; s < NUM_SHUT; s++) {
        SH_STATE[s] = 0;
        SH_TMR[s] = SH_FIRST[s];
        sh_solid(s, 1);
    }
}

void shut_tick(void)
{
    for (uint8_t s = 0; s < NUM_SHUT; s++) {
        if (--SH_TMR[s])
            continue;
        SH_STATE[s] ^= 1;
        if (SH_STATE[s]) {          /* opens: floor */
            SH_TMR[s] = SH_OPEN[s];
            sh_solid(s, 0);
            sh_paint(s, 0);
        } else {                    /* closes: the map's shutter chars */
            SH_TMR[s] = SH_CLOSED[s];
            sh_solid(s, 1);
            sh_paint(s, 1);
        }
    }
}

/* room_overlays: CUR_ROOM's open shutters over the map's closed ones */
void shut_paint(void)
{
    for (uint8_t s = 0; s < NUM_SHUT; s++)
        if (SH_STATE[s])
            sh_paint(s, 0);
}

/* the bolt's centre is in a solid tile x/y: a player's bolt destroys the
 * room's intact laser target; the bolt is gone either way */
void bolt_solid(uint8_t x, uint8_t y)
{
    if (bolt_plr && tgt_at(x, y))
        tgt_destroy();
    bolt_kill();
}
