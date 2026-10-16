/* The robodex (GAME_STATE = 11), from the terminal: a page per robot type
 * -- only types with a robot in a visited room -- with the type's sprite,
 * double size and animated, on hardware sprite 7 (unused in the game).
 * (robodex.asm) */
#include "titan.h"

#define DEX_TROW 7                  /* first text row (to row 14) */
#define DEX_TCOL 12                 /* text column (26 wide) */
#define DEX_CNT  (SCRN + 5 * 40 + 33)   /* "n/m" in the title row */
#define DEX_SPX  48                 /* sprite 7: cols 3-8 */
#define DEX_SPY  117

static uint8_t dex_n, dex_sel, dex_an;
static uint8_t dex_list[NUM_DEX];   /* the pages available this visit */

static const uint8_t DEX_TTL[40]  = VB "  * robodex - unit information  0/0   " VB;
static const uint8_t DEX_HNT[40]  = VB "    left/right=browse   fire=return   " VB;
static const uint8_t DEX_NONE[40] = VB "    no units on record.               " VB;

static const struct row DEX_ROWS[] = {
    { 4,  LTGREEN, SCR_BORDER_TOP },
    { 5,  LTGREEN, DEX_TTL },
    { 6,  GREEN,   SCR_BLANK },
    { 7,  GREEN,   SCR_BLANK },
    { 8,  GREEN,   SCR_BLANK },
    { 9,  GREEN,   SCR_BLANK },
    { 10, GREEN,   SCR_BLANK },
    { 11, GREEN,   SCR_BLANK },
    { 12, GREEN,   SCR_BLANK },
    { 13, GREEN,   SCR_BLANK },
    { 14, GREEN,   SCR_BLANK },
    { 15, GREEN,   SCR_BLANK },
    { 16, LTRED,   DEX_HNT },
    { 17, LTGREEN, SCR_BORDER_BOTTOM },
    { ROWS_END }
};

/* sprite 7: the page's type, its first facing, rest/walk1/rest/walk2 */
static void dex_frame(void)
{
    static const uint8_t FRM[4] = { 0, 1, 0, 2 };
    uint8_t t = DEX_TYPE[dex_list[dex_sel]], f = FRM[(dex_an >> 3) & 3];

    if (f && TYPE_ANIM[t] == 2)
        f++;                        /* a hop type: skip the charged pose */
    SPRPTR[7] = TYPE_SPRPTR[t] + f;
}

/* page dex_sel: the counter, the sprite's colour, the text -- 1 = next
 * line, 0 ends, 2 toggles white (a label) and the line's colour */
static void dex_draw(void)
{
    uint8_t p = dex_list[dex_sel], row = DEX_TROW, col, lc, x = 0, c;
    const uint8_t *s = DEX[p];

    DEX_CNT[0] = CH_0 + 1 + dex_sel;
    DEX_CNT[2] = CH_0 + dex_n;
    VIC_SPCOL(7) = TYPE_COLOR[DEX_TYPE[p]];
    dex_frame();
    for (uint8_t r = DEX_TROW; r < DEX_TROW + 8; r++) {
        uint8_t *q = row_ptr(r) + DEX_TCOL;
        for (uint8_t i = 0; i < 39 - DEX_TCOL; i++)
            q[i] = CH_SPC;
    }
    lc = col = LTGREEN;             /* the name line, then the rest green */
    kernal_out();                   /* the pages are under the KERNAL */
    for (;;) {
        c = *s++;
        if (c >= 3) {
            uint8_t *q = row_ptr(row) + DEX_TCOL + x++;
            *q = scr(c);
            q[CRAM_OFS] = col;
        } else if (c == 2) {
            col = col == WHITE ? lc : WHITE;
        } else if (c == 1) {
            row++;
            x = 0;
            lc = col = GREEN;
        } else {
            break;
        }
    }
    kernal_in();
}

static void sprite7(bool on)
{
    if (on) {
        VIC_SPMC |= 0x80;           /* multicolour, double size */
        VIC_SPYEXP |= 0x80;
        VIC_SPXEXP |= 0x80;
    } else {
        VIC_SPMC &= 0x7F;
        VIC_SPYEXP &= 0x7F;
        VIC_SPXEXP &= 0x7F;
    }
}

void setup_dex(void)
{
    uint8_t a;

    game_state = ST_DEX;
    KBD_NDX = 0;
    VIC_SPEN = 0;
    clear_room();
    draw_rows(DEX_ROWS);
    frame_edges(LTGREEN, 4, 17);
    /* the pages of types with a robot in a visited room */
    dex_n = dex_sel = 0;
    for (uint8_t p = 0; p < NUM_DEX; p++)
        for (a = 0; a < NUM_ACTORS; a++)
            if (ACT_TYPE[a] == DEX_TYPE[p] && ROOM_SEEN[ACT_ROOM[a]]) {
                dex_list[dex_n++] = p;
                break;
            }
    /* start on the type of the first robot in this room */
    for (a = 0; a < NUM_ACTORS; a++)
        if (ACT_ROOM[a] == cur_room) {
            for (uint8_t i = 0; i < dex_n; i++)
                if (DEX_TYPE[dex_list[i]] == ACT_TYPE[a])
                    dex_sel = i;
            break;
        }
    if (!dex_n) {                   /* nothing seen yet (no sprite) */
        draw_row(DEX_TROW, DEX_NONE, DGRAY);
        return;
    }
    sprite7(true);
    VIC_SP_MSB &= 0x7F;
    VIC_SPX(7) = DEX_SPX;
    VIC_SPY(7) = DEX_SPY;
    dex_an = 0;
    dex_draw();
    VIC_SPEN = 0x80;
}

/* left/right (A/D) browse, wrapping; fire/Space/Return/F7 go back */
void do_dex(void)
{
    uint8_t k = 0;

    if (!(joy_new & 0x1C))
        k = getin();
    if ((joy_new & 0x10) || k == 0x0D || k == 0x88) {
        VIC_SPEN = 0;
        KBD_NDX = 0;
        sprite7(false);
        setup_terminal();           /* "robodex" still selected */
        return;
    }
    if (!dex_n)
        return;
    if ((joy_new & 0x04) || k == 'A') {
        dex_sel = (dex_sel ? dex_sel : dex_n) - 1;
        dex_draw();
    } else if ((joy_new & 0x08) || k == 'D') {
        if (++dex_sel >= dex_n)
            dex_sel = 0;
        dex_draw();
    } else {
        dex_an++;
        dex_frame();
    }
}
