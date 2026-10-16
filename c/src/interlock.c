/* The launch interlock (ILK_ROOM): a key slot per launch key, nested ring
 * layers and the release console, all solid. A launch key turned in any
 * slot opens the next layer; once the innermost is open, the console
 * releases the room's sealed door. Survives deaths and room resets.
 * (interlock.asm) */
#include "titan.h"

/* layer n's tiles (every layer: n = $FF) solid (1) or plain floor (0) */
static void ilk_layer(uint8_t n, uint8_t set)
{
    for (uint8_t i = 0; i < NUM_LTILES; i++)
        if (LT_N[i] == n || n == 0xFF) {
            uint8_t *w = wall_ptr(ILK_ROOM, LT_X[i], LT_Y[i]);
            *w = (*w & 0xF0) | set;
        }
}

/* try_move: the human pushes into the solid tile x/y of CUR_ROOM.
 * False = a plain wall; true = handled (a key turned, the console, a
 * popup). */
bool ilk_touch(uint8_t x, uint8_t y)
{
    uint8_t s, i;

    if (cur_room != ILK_ROOM)
        return false;
    if (x == CONSOLE_X && y == CONSOLE_Y) {
        if (DOOR_OPEN[ILK_DOOR])    /* released already */
            return false;
        door_unlock(ILK_DOOR);      /* the silo door opens */
        show_popup(SBOX_MSG_RELEASED);
        return true;
    }
    for (s = 0; s < NUM_SLOTS; s++)
        if (SLOT_X[s] == x && SLOT_Y[s] == y)
            break;
    if (s == NUM_SLOTS || ILK_SLOT[s])
        return false;               /* not a slot, or a key in it already */
    for (i = 0; i < NUM_ITEMS; i++)
        if (ITEM_LKEY[i] && ITEM_STATE[i] == 1)
            break;
    if (i == NUM_ITEMS) {
        show_popup(SBOX_MSG_NEEDKEY);
        return true;
    }
    ITEM_STATE[i] = 2;              /* the key stays in the slot */
    ILK_SLOT[s] = 1;
    ilk_layer(ILK_N++, 0);          /* plain floor: not searchable either */
    ilk_paint();
    flash(GREEN);
    return true;
}

/* room_overlays: the lit slots and the open layers over the map's chars */
void ilk_paint(void)
{
    if (cur_room != ILK_ROOM)
        return;
    for (uint8_t s = 0; s < NUM_SLOTS; s++)
        if (ILK_SLOT[s])
            art_list(SLOT_ART[s], CFG_SLOT_LIT);
    for (uint8_t n = 0; n < ILK_N; n++)
        art_list(LAYER_ART[n], 0);
}

/* a new game: no keys turned, every layer solid */
void ilk_reset(void)
{
    ILK_N = 0;
    for (uint8_t s = 0; s < NUM_SLOTS; s++)
        ILK_SLOT[s] = 0;
    ilk_layer(0xFF, 1);
}
