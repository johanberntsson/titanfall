/* The sector map (GAME_STATE = 5), from the terminal. (map.asm) */
#include "titan.h"

/* spaces over a w x h block of the screen at p */
static void map_blank(uint8_t *p, uint8_t w, uint8_t h)
{
    for (; h; h--, p += 40)
        fill(p, CH_SPC, w);
}

/* The whole map (generated from the doors by genworld.py: MAP_SCR/COL),
 * without the rooms not visited yet and the corridors between two of them
 * (a corridor from a visited room into an unknown one stays, as a hint);
 * the current room lit. */
void setup_map(void)
{
    uint8_t *p;

    game_state = ST_MAP;
    KBD_NDX = 0;
    VIC_SPEN = 0;
    kernal_out();                   /* the map is under the KERNAL */
    copy(SCRN + 80, MAP_SCR, 22 * 40);
    copy(CRAM + 80, MAP_COL, 22 * 40);
    kernal_in();
    for (uint8_t r = 0; r < NUM_ROOMS; r++)
        if (!ROOM_SEEN[r])          /* (MAPHL points into colour RAM) */
            map_blank(MAPHL[r] - CRAM_OFS, MAPHL_W[r], MAPHL_H[r]);
    for (uint8_t c = 0; c < NUM_MAPCOR; c++)
        if (!(ROOM_SEEN[MAPCOR_A[c]] | ROOM_SEEN[MAPCOR_B[c]]))
            map_blank(MAPCOR[c], MAPCOR_W[c], MAPCOR_H[c]);
    p = MAPHL[cur_room];
    for (uint8_t h = MAPHL_H[cur_room]; h; h--, p += 40)
        fill(p, LTGREEN, MAPHL_W[cur_room]);
}

/* fire (or any key but Space) goes back to the terminal, "view map" still
 * selected */
void do_map(void)
{
    uint8_t k = getin();
    if ((k && k != ' ') || (joy_new & 0x10)) {
        KBD_NDX = 0;
        setup_terminal();
    }
}
