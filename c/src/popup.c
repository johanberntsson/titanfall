/* The popup (GAME_STATE = 6) over the room -- a found item, a locked door,
 * the interlock's messages, the robot link, F2 -- and the held-fire search
 * with its small "searching" box. (popup.asm) */
#include "titan.h"

#define SRCH_SHOW 10                /* frames held before "searching" */
#define SRCH_DONE (SRCH_SHOW + 50)  /* ... and before the result */
#define SPOP_W 11
#define SPOP_H 4
#define SP_BUF ((uint8_t *)0x0340)  /* 2 x 44 bytes in the (unused) tape buffer */

enum { SP_SAVE, SP_DRAW, SP_REST };

static uint8_t sp_row, sp_col;

#define SBOX_EDGE(l, m, r) \
    { [0 ... 3] = ' ', [4] = l, [5 ... 34] = m, [35] = r, [36 ... 39] = ' ' }
#define SBOX(text) "    " VB text VB "    "

static const uint8_t SBOX_TOP[40] = SBOX_EDGE(SC_RD_UL, SC_HBAR, SC_RD_UR);
static const uint8_t SBOX_BOT[40] = SBOX_EDGE(SC_RD_LL, SC_HBAR, SC_RD_LR);
static const uint8_t SBOX_BLK[40] = SBOX("                              ");
static const uint8_t SBOX_HNT[40] = SBOX("          press fire          ");
const uint8_t SBOX_MSG_GAMEOVER[40] = SBOX("          game over           ");
const uint8_t SBOX_MSG_WIN[40]      = SBOX("  launch aborted. you win!    ");
const uint8_t SBOX_MSG_LOCKED[40]   = SBOX("         door locked!         ");
const uint8_t SBOX_MSG_SEALED[40]   = SBOX(" door sealed. use the release ");
const uint8_t SBOX_MSG_NEEDKEY[40]  = SBOX("    a launch key is needed    ");
const uint8_t SBOX_MSG_RELEASED[40] = SBOX("     silo door released!      ");
static const uint8_t SBOX_MSG_CTRL[40] = SBOX("   you are now controlling    ");
static uint8_t SBOX_MSG_LINK[40]    = SBOX("  for 30 seconds. f7 aborts.  ");
static uint8_t SBOX_MSG_WHERE[40]   = SBOX("     room 1   x=00   y=00     ");

/* the rows around the message (row 10) */
static const struct row SBOX_ROWS[] = {
    { 8,  LTGREEN, SBOX_TOP },
    { 9,  LTGREEN, SBOX_BLK },
    { 11, LTGREEN, SBOX_BLK },
    { 12, LTRED,   SBOX_HNT },
    { 13, LTGREEN, SBOX_BOT },
    { ROWS_END }
};

/* the small search box: SPOP_H rows of SPOP_W */
#define SP_EDGE(l, r) l, SC_HBAR, SC_HBAR, SC_HBAR, SC_HBAR, SC_HBAR, \
                      SC_HBAR, SC_HBAR, SC_HBAR, SC_HBAR, r
static const uint8_t SP_T_SEARCH[SPOP_W * SPOP_H] = {
    SP_EDGE(SC_RD_UL, SC_RD_UR),
    SC_VBAR, 's', 'e', 'a', 'r', 'c', 'h', 'i', 'n', 'g', SC_VBAR,
    SC_VBAR, ' ', ' ', ' ', '.', '.', '.', ' ', ' ', ' ', SC_VBAR,
    SP_EDGE(SC_RD_LL, SC_RD_LR)
};
static const uint8_t SP_T_NOTHING[SPOP_W * SPOP_H] = {
    SP_EDGE(SC_RD_UL, SC_RD_UR),
    SC_VBAR, ' ', 'n', 'o', 't', 'h', 'i', 'n', 'g', ' ', SC_VBAR,
    SC_VBAR, ' ', ' ', 'h', 'e', 'r', 'e', ' ', ' ', ' ', SC_VBAR,
    SP_EDGE(SC_RD_LL, SC_RD_LR)
};

/* ---- the popup ------------------------------------------------------- */

/* the box (columns 4-35, rows 8-13) with msg on row 10; the room stays
 * visible around it. (The game over and win screens use it too.) */
void draw_popup_box(const uint8_t *msg)
{
    dr_l = fr_l = 4;
    dr_r = fr_r = 35;
    draw_row(10, msg, YELLOW);
    draw_rows(SBOX_ROWS);
    dr_l = 0;
    dr_r = 39;
    frame_edges_lr(LTGREEN, 8, 13);
}

void show_popup(const uint8_t *msg)
{
    game_state = ST_POPUP;
    popup_st = 0;                   /* the opening press is still held */
    VIC_SPEN = 0;
    draw_popup_box(msg);
}

/* Closes on a fresh fire/Space press, polled on the matrix: GETIN would
 * see the opening press in the KERNAL buffer and close it at once.
 * popup_st: 0 the opening press held, 1 released (armed), 2 pressed; it
 * closes on that press's release, so it can't leak into the game. */
void do_popup(void)
{
    bool down;

    CIA1_DDRA = 0xFF;
    CIA1_PRA = 0xFF;
    down = !(CIA1_PRA & 0x10);      /* joystick 2 fire */
    CIA1_PRA = 0x7F;                /* Space: col 7, row 4 */
    down |= !(CIA1_PRB & 0x10);
    if (down) {
        if (popup_st == 1)
            popup_st = 2;           /* a fresh press */
    } else if (popup_st == 2) {
        KBD_NDX = 0;                /* drop buffered keys */
        term_abort();               /* back to the game, as the terminal's logoff */
    } else {
        popup_st = 1;               /* the opening press released: armed */
    }
}

/* a found item: carried, a security code counted (one digit) */
static void setup_search(uint8_t i)
{
    uint8_t c = ITEM_CODE[i];

    ITEM_STATE[i] = 1;
    if (c-- && CODE_CNT[c] < 9) {
        CODE_CNT[c]++;
        if (CODE_ENT[c] < 9)        /* a death in this room keeps it too */
            CODE_ENT[c]++;
    }
    show_popup(ITEM_MSG[i]);
}

/* "you are now controlling <robot> for 30 seconds" */
void setup_linked(uint8_t a)
{
    show_popup(ACT_LNAME[a]);
    dr_l = 4;
    dr_r = 35;
    draw_row(9, SBOX_MSG_CTRL, LTGREEN);
    dec2(CFG_LINK_S, SBOX_MSG_LINK + 11);
    draw_row(11, SBOX_MSG_LINK, LTGREEN);
    dr_l = 0;
    dr_r = 39;
    frame_edges_lr(LTGREEN, 8, 13);
}

/* F2: the room number and the tile X/Y of whoever is driven */
void setup_where(void)
{
    uint8_t a = player_mode;
    SBOX_MSG_WHERE[15] = CH_0 + 1 + cur_room;
    dec2(a ? ACT_X[a - 1] : plr_x, SBOX_MSG_WHERE + 21);
    dec2(a ? ACT_Y[a - 1] : plr_y, SBOX_MSG_WHERE + 28);
    show_popup(SBOX_MSG_WHERE);
}

/* ---- the search ---------------------------------------------------------
 * A fresh fire press on a searchable tile (not plain floor) starts it;
 * while fire is held srch_tmr counts and move_player stands still. Time
 * and robots keep running: searching is a risk. */

static uint8_t *srch_tile(void)
{
    return wall_ptr(cur_room, plr_x, plr_y);
}

/* the small box SPOP_W x SPOP_H at sp_row/sp_col: save what's under it,
 * draw a template, or put it back */
static void spop(uint8_t mode, const uint8_t *t)
{
    uint8_t i = 0;
    for (uint8_t r = 0; r < SPOP_H; r++) {
        uint8_t *s = row_ptr(sp_row + r) + sp_col, *c = s + CRAM_OFS;
        for (uint8_t x = 0; x < SPOP_W; x++, i++) {
            if (mode == SP_SAVE) {
                SP_BUF[i] = s[x];
                SP_BUF[SPOP_W * SPOP_H + i] = c[x];
            } else if (mode == SP_DRAW) {
                uint8_t ch = t[i];
                s[x] = scr(ch);     /* the frame light green, text yellow */
                c[x] = ch >= 0x40 && ch < 0x60 ? LTGREEN : YELLOW;
            } else {
                s[x] = SP_BUF[i];
                c[x] = SP_BUF[SPOP_W * SPOP_H + i];
            }
        }
    }
}

/* centred over the player: above the sprite, or below it at the top */
static void spop_place(void)
{
    uint8_t r = plr_y * 2, c = plr_x * 2;
    sp_row = r < 5 ? r + SPOP_H : r - (SPOP_H - 1);
    c = c >= 4 ? c - 4 : 0;
    sp_col = c > 40 - SPOP_W ? 40 - SPOP_W : c;
}

static void spop_hide(void)
{
    if (srch_st) {
        spop(SP_REST, 0);
        srch_st = 0;
    }
}

static void srch_nothing(void)
{
    spop(SP_DRAW, SP_T_NOTHING);
    srch_st = 2;
}

void search_tick(void)
{
    if (player_mode || !fire_prev) {    /* a robot can't search; fire let go */
        spop_hide();
        srch_tmr = 0;
        return;
    }
    if (!srch_tmr) {
        if (!key_spc || !(*srch_tile() & W_SEARCH))
            return;                 /* held over, or plain floor */
        plr_anim = 0;               /* stand at rest while searching */
    }
    if (srch_tmr >= SRCH_DONE)      /* finished: wait for the release */
        return;
    if (++srch_tmr == SRCH_SHOW) {
        spop_place();
        spop(SP_SAVE, 0);
        if (*srch_tile() & W_SEARCHED) {    /* searched before */
            srch_tmr = SRCH_DONE;
            srch_nothing();
        } else {
            spop(SP_DRAW, SP_T_SEARCH);
            srch_st = 1;
        }
    } else if (srch_tmr == SRCH_DONE) {
        *srch_tile() |= W_SEARCHED;
        for (uint8_t i = 0; i < NUM_ITEMS; i++)
            if (!ITEM_STATE[i] && ITEM_ROOM[i] == cur_room &&
                ITEM_X[i] == plr_x && ITEM_Y[i] == plr_y) {
                spop_hide();
                setup_search(i);
                return;
            }
        srch_nothing();
    }
}
