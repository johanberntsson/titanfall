/* The terminal (GAME_STATE = 3): a menu of the room's robots, view map,
 * robodex, logoff. (terminal.asm) */
#include "titan.h"

#define TERM_MAX    8
#define TM_DEX      0xFC
#define TM_MAP      0xFE
#define TM_LOGOFF   0xFF
#define TERM_RROW   8               /* first robot row */
#define TERM_MSGROW 18              /* message row under the box */
#define DEX_ROW     14

static uint8_t term_n;              /* menu entries */
static uint8_t tm_act[TERM_MAX];    /* per entry: actor, TM_MAP, TM_DEX, TM_LOGOFF */
static uint8_t tm_row[TERM_MAX];    /* per entry: screen row */

static const uint8_t TBOX_TTL[40]  = VB "  * sector drone network - terminal   " VB;
static const uint8_t TBOX_SUB[40]  = VB "  access verified. select unit:       " VB;
static const uint8_t TBOX_NONE[40] = VB "    no units in this sector           " VB;
static const uint8_t TBOX_MAP[40]  = VB "    view map                          " VB;
static const uint8_t TBOX_DEX[40]  = VB "    robodex - unit information        " VB;
static const uint8_t TBOX_OFF[40]  = VB "    logoff                            " VB;
static const uint8_t TBOX_HNT[40]  = VB "    fire=select    up/down=move       " VB;
static const uint8_t TMSG_LCK[40]  = "  access denied. unit locked by titan.  ";
static const uint8_t TMSG_DEAD[40] = "  unit destroyed. link unavailable.     ";

static const struct row TERM_ROWS[] = {
    { 4,  LTGREEN, SCR_BORDER_TOP },
    { 5,  LTGREEN, TBOX_TTL },
    { 6,  GREEN,   TBOX_SUB },
    { 7,  GREEN,   SCR_BLANK },
    { 8,  DGRAY,   TBOX_NONE },     /* the robot rows draw over it */
    { 9,  GREEN,   SCR_BLANK },
    { 10, GREEN,   SCR_BLANK },
    { 11, GREEN,   SCR_BLANK },
    { 12, GREEN,   SCR_BLANK },
    { 13, GREEN,   TBOX_MAP },
    { 14, GREEN,   TBOX_DEX },
    { 15, GREEN,   TBOX_OFF },
    { 16, LTRED,   TBOX_HNT },
    { 17, LTGREEN, SCR_BORDER_BOTTOM },
    { ROWS_END }
};

/* rows 2-23 blank (the HUD and the status line stay) */
void clear_room(void)
{
    fill(SCRN + 80, CH_SPC, 22 * 40);
    fill(CRAM + 80, DGRAY, 22 * 40);
}

/* the '>' on the selected entry: light green, destroyed robots dark grey,
 * the rest green */
static void term_draw_sel(void)
{
    for (uint8_t i = 0; i < term_n; i++) {
        uint8_t *p = row_ptr(tm_row[i]), a = tm_act[i], col = GREEN;
        if (i == term_sel) {
            p[3] = '>';
            col = LTGREEN;
        } else {
            p[3] = CH_SPC;
            if (a < NUM_ACTORS && !ACT_ALIVE[a])
                col = DGRAY;
        }
        paint_row(p, col);
    }
    frame_edges(LTGREEN, 4, 17);
}

static void add_entry(uint8_t act, uint8_t row)
{
    tm_act[term_n] = act;
    tm_row[term_n++] = row;
}

/* from read_keys (term_sel = $FF: the cursor starts on logoff, so a double
 * press of fire logs off instead of spending a code) and from the map and
 * the robodex on their way back (term_sel still on their entry) */
void setup_terminal(void)
{
    game_state = ST_TERMINAL;
    KBD_NDX = 0;
    VIC_SPEN = 0;
    clear_room();
    draw_rows(TERM_ROWS);
    term_n = 0;
    for (uint8_t a = 0; a < NUM_ACTORS; a++) {
        if (ACT_ROOM[a] != cur_room)
            continue;
        uint8_t row = TERM_RROW + term_n;
        add_entry(a, row);
        draw_row(row, ACT_TROW[a], GREEN);  /* (colour: term_draw_sel) */
        if (!ACT_ALIVE[a])
            put_text(row_ptr(row) + 28, "destroyed", GREEN);
    }
    add_entry(TM_MAP, 13);
    add_entry(TM_DEX, DEX_ROW);
    add_entry(TM_LOGOFF, 15);
    if (term_sel & 0x80)
        term_sel = term_n - 1;
    term_draw_sel();
}

/* back to the room (logoff; also the popup's and carrier lock's exit) */
void term_abort(void)
{
    game_state = ST_GAME;
    draw_room();
    draw_status();
    VIC_SPEN = 0x07;
    update_sprite0();
    update_robot_sprites();
}

/* link to actor a, unless it's destroyed, locked, or needs a security code
 * the player has none of: then the message (NULL = linked) */
static const uint8_t *term_link(uint8_t a)
{
    uint8_t c = ACT_CODE[a];
    if (!ACT_ALIVE[a])
        return TMSG_DEAD;
    if (ACT_LOCK[a])
        return TMSG_LCK;
    if (c--) {
        if (!CODE_CNT[c])
            return CODE_MSG[c];
        CODE_CNT[c]--;              /* spend one */
    }
    start_link(a);
    return 0;
}

static void term_fire(void)
{
    uint8_t a = tm_act[term_sel];
    const uint8_t *msg;

    switch (a) {
    case TM_LOGOFF: term_abort(); return;
    case TM_DEX:    setup_dex();  return;
    case TM_MAP:    setup_map();  return;
    }
    msg = term_link(a);
    if (msg) {
        draw_row(TERM_MSGROW, msg, LTRED);
        return;
    }
    /* back to the room, driving it, under the "now controlling" popup (the
     * link's time only runs once it's closed) */
    draw_room();
    draw_status();
    draw_hud_dynamic();             /* "robot 30" */
    setup_linked(a);
}

/* fire / Space / Return select, up/down or W/S move, F7 leaves; the
 * joystick first, so a key in the buffer can't swallow a fire press */
void do_terminal(void)
{
    uint8_t k;

    if (joy_new & 0x10) {
        term_fire();
        return;
    }
    if (joy_new & 0x01)
        k = 'W';
    else if (joy_new & 0x02)
        k = 'S';
    else
        k = getin();
    switch (k) {
    case 0x88:                      /* F7 */
        term_abort();
        break;
    case 0x0D:                      /* Return */
        term_fire();
        break;
    case 'W':                       /* PETSCII W */
        if (term_sel) {
            term_sel--;
            term_draw_sel();
        }
        break;
    case 'S':
        if (term_sel + 1 < term_n) {
            term_sel++;
            term_draw_sel();
        }
        break;
    }
}
