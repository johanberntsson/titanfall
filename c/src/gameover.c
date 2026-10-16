/* Game over (GAME_STATE = 2): the clock has run out. The missile room, no
 * sprites; after a moment the missile (art.missile_tiles: MSL_*) lifts off
 * and flies up off the screen, speeding up, leaving the room behind it;
 * then the "game over" popup, and fire goes back to the intro.
 * (gameover.asm) */
#include "titan.h"

#define GO_T0    (MSL_Y + 2)        /* the missile's top screen row */
#define GO_ROWS  (GO_T0 + MSL_H)    /* its path: screen rows 0..GO_ROWS-1 */
#define GO_PAUSE 60                 /* frames before lift-off */
#define GO_D0    12                 /* step k waits 2*(GO_D0-k) frames, >= 4 */

static uint8_t go_ph;               /* 0 launching, 1 the popup */
static uint8_t go_tmr, go_k;        /* rows the missile has risen */
static uint8_t go_bg[GO_ROWS * MSL_W];  /* the path without the missile */

static const uint8_t GO_CLOCK[40] = "                                00:00:00";

/* the path with the missile go_k rows up: its chars where it is, go_bg
 * elsewhere, colours from TILE_COLORS */
static void go_draw(void)
{
    const uint8_t *bg = go_bg;
    for (uint8_t r = 0; r < GO_ROWS; r++, bg += MSL_W) {
        uint8_t *p = row_ptr(r) + MSL_X;
        uint8_t m = r + go_k - GO_T0;   /* the missile's row here */
        bool in = r + go_k >= GO_T0 && m < MSL_H;
        for (uint8_t c = 0; c < MSL_W; c++) {
            uint8_t ch = in ? MSL_CHARS[m * MSL_W + c] : 0;
            if (!ch)
                ch = bg[c];
            p[c] = ch;
            p[c + CRAM_OFS] = TILE_COLORS[ch];
        }
    }
}

void setup_gameover(void)
{
    uint8_t *bg = go_bg;

    game_state = ST_GAMEOVER;
    KBD_NDX = 0;
    snd_tmr = 0;
    music_off = 1;                  /* no music until the intro */
    SID(0x04) = SID(0x0B) = SID(0x12) = 0;  /* (the rumble still plays) */
    VIC_SPEN = 0;
    VIC_BRDCOL = RED;
    VIC_BGCOL = BLACK;
    go_ph = go_k = 0;
    go_tmr = GO_PAUSE;
    cls();
    draw_row(0, GO_CLOCK, LTRED);   /* the clock, run out */
    cur_room = MSL_ROOM;            /* the room as the game draws it */
    draw_room();
    VIC_SPEN = 0;
    sprptr_defaults();
    /* go_bg = the missile's path, with spaces where the missile is */
    for (uint8_t r = 0; r < GO_ROWS; r++, bg += MSL_W)
        for (uint8_t c = 0; c < MSL_W; c++)
            bg[c] = row_ptr(r)[MSL_X + c];
    for (uint8_t i = 0; i < MSL_W * MSL_H; i++)
        if (MSL_CHARS[i])
            go_bg[GO_T0 * MSL_W + i] = CH_SPC;
}

void do_gameover(void)
{
    uint8_t k;

    if (go_ph) {                    /* the popup: fire (any key but Space) */
        k = getin();
        if ((k && k != ' ') || (joy_new & 0x10)) {
            music_init();           /* the theme from the top (music_off
                                     *  still set: no half-way IRQ) */
            music_off = 0;
            setup_intro();
        }
        return;
    }
    if (go_k && !snd_tmr)           /* flying: keep the rumble going */
        sound_boom_start();
    if (--go_tmr)
        return;
    if (!go_k)
        sound_boom_start();         /* lift-off */
    go_k++;
    go_draw();
    if (go_k == GO_ROWS) {          /* gone: the popup */
        go_ph = 1;
        draw_popup_box(SBOX_MSG_GAMEOVER);
        KBD_NDX = 0;                /* keys pressed during the launch */
        return;
    }
    go_tmr = 2 * (go_k < GO_D0 - 2 ? GO_D0 - go_k : 2);  /* it speeds up */
}
