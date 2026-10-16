/* Row 1, "orders: <goal>" for the current room, and rolling back a room
 * that's left unfinished. (orders.asm) */
#include "titan.h"

/* is room's goal achieved? (never, without a goal or a done:) */
uint8_t goal_done(uint8_t room)
{
    uint8_t arg = GOAL_ARG[room];

    switch (GOAL_KIND[room]) {
    case GOAL_FOUND:
        if (GOAL_ARG2[room] != 0xFF && !ITEM_STATE[GOAL_ARG2[room]])
            return 0;               /* found: [a, b] -- both */
        return ITEM_STATE[arg];
    case GOAL_OPENED:
        return DOOR_OPEN[arg];
    case GOAL_VISITED:
        return ROOM_SEEN[arg];
    case GOAL_GATE:
        return GATE_STATE[arg] & 2; /* latched open */
    }
    return 0;
}

/* the room and done-state on row 1 (room*2+done; $FF = redraw) */
uint8_t orders_shown = 0xFF;

/* every game frame: white while open, light green with " - done"; a room
 * without a goal shows no "orders:" label either. Marks the room visited.
 * (Drawn only when it changes -- the asm redraws it every frame.) */
void draw_orders(void)
{
    static const char LBL[] = "orders: ";
    const uint8_t *g;
    uint8_t col = WHITE, done, shown;

    ROOM_SEEN[cur_room] = 1;
    done = goal_done(cur_room) != 0;
    shown = cur_room * 2 + done;
    if (shown == orders_shown)
        return;
    orders_shown = shown;
    if (done) {
        g = GOALD[cur_room];
        col = LTGREEN;
    } else {
        g = GOAL[cur_room];
    }
    for (uint8_t i = 0; i < GOAL_WIDTH; i++) {
        (SCRN + 48)[i] = scr(g[i]);
        (CRAM + 48)[i] = col;
    }
    for (uint8_t i = 0; i < 8; i++) {
        (SCRN + 40)[i] = g[0] == ' ' ? CH_SPC : scr(LBL[i]);
        (CRAM + 40)[i] = YELLOW;
    }
}

/* Just before a door takes the player out of CUR_ROOM: unless its goal is
 * done, the room goes back to how it started and the codes spent in it
 * come back -- like a death there. */
void leave_room(void)
{
    if (!goal_done(cur_room)) {
        reset_room();
        restore_codes();
    }
}
