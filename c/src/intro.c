/* The intro (GAME_STATE = 0): the logo, the mission box, "press fire".
 * (intro.asm) */
#include "titan.h"

static uint8_t blink_tmr, blink_st;

static const char ITR_AUTH[] = "release 1, 2026 by johan berntsson";
static const uint8_t ITR_TAG[40] = VB "  infiltrate. subvert. stop launch.   " VB;
static const uint8_t ITR_M1[40]  = VB "  mission: abort launch sequence      " VB;
static const uint8_t ITR_M2[40]  = VB "  location: titan missile complex     " VB;
/* "5 hours": win.c patches the digit (ITR_HRS) */
static uint8_t ITR_M3[40]        = VB "  warning: launch in t-minus 5 hours  " VB;
static const uint8_t TXT_PRESS[40] = "         press fire to start            ";
static const uint8_t TXT_F1HELP[40] = "              f1 for help               ";

static const struct row INTRO_ROWS[] = {
    { 12, DGRAY,  SCR_BORDER_TOP },
    { 13, CYAN,   ITR_TAG },
    { 14, BLUE,   ITR_SEP },
    { 15, DGRAY,  SCR_BLANK },
    { 16, MGRAY,  ITR_M1 },
    { 17, MGRAY,  ITR_M2 },
    { 18, LTRED,  ITR_M3 },
    { 19, DGRAY,  SCR_BLANK },
    { 20, DGRAY,  SCR_BORDER_BOTTOM },
    { 24, MGRAY,  TXT_F1HELP },
    { ROWS_END }
};

uint8_t *const itr_hrs = ITR_M3 + 30;   /* "5 hours  " */

static void blink(bool on)
{
    if (on)
        draw_row(22, TXT_PRESS, WHITE);
    else
        fill(SCRN + 22 * 40, CH_SPC, 40);
}

/* the logo (rows 1-8, raw screen codes), the author line (row 10), the
 * mission box (rows 12-20), the prompt (row 22) and the help hint */
void draw_intro_screen(void)
{
    kernal_out();                   /* the logo is under the KERNAL */
    copy(SCRN + 40, TITLE_SCR, TITLE_ROWS * 40);
    copy(CRAM + 40, TITLE_COL, TITLE_ROWS * 40);
    kernal_in();
    put_text(SCRN + 10 * 40 + (40 - sizeof ITR_AUTH + 1) / 2, ITR_AUTH, MGRAY);
    draw_rows(INTRO_ROWS);
    frame_edges(DGRAY, 12, 20);
    blink(true);
}

/* from the start and from game over / win */
void setup_intro(void)
{
    game_state = ST_INTRO;
    VIC_BRDCOL = BLACK;
    VIC_BGCOL = BLACK;
    VIC_SPEN = 0;
    blink_tmr = blink_st = 0;
    cls();
    sprptr_defaults();
    draw_intro_screen();
}

void do_intro(void)
{
    uint8_t k = getin();
    /* any key but Space (Space is fire, in joy_new; as a key it could be
     * the KERNAL's repeat), or fire */
    if ((k && k != ' ') || (joy_new & 0x10)) {
        setup_cutscene();           /* the briefing, then the game */
        return;
    }
    if (++blink_tmr < 25)
        return;
    blink_tmr = 0;
    blink_st ^= 1;
    blink(!blink_st);
}
