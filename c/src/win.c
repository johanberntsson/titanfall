/* Winning: the explosion (GAME_STATE = 7) when a driven shooter's bolt hits
 * the power cell, then the win popup (GAME_STATE = 4). Every win makes the
 * next game harder. (win.asm) */
#include "titan.h"

#define EXPL_LEN BOOM_LEN           /* 2 s */


static const uint8_t EXP_COLS[4] = { RED, ORANGE, YELLOW, ORANGE };
static const char *const HR_WORDS[10] = {
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"
};

/* the texts that name the silo and the hours: the briefing's (cs_silo,
 * cs_hrs) and the intro's "t-minus n hours" */
static void lvl_apply(void)
{
    const char *w;
    uint8_t i = 0;

    dec2(wins + 17, cs_silo);
    itr_hrs[0] = CH_0 + start_h;
    itr_hrs[6] = start_h == 1 ? ' ' : 's';  /* "1 hour" */
    for (w = HR_WORDS[start_h]; *w; w++)    /* the word for start_h + 1 */
        cs_hrs[i++] = *w;
    for (w = " hours."; *w; w++)
        cs_hrs[i++] = *w;
    while (i < 12)
        cs_hrs[i++] = ' ';
}

/* every win: an hour off the starting clock (never below one), the next
 * silo number */
static void lvl_next(void)
{
    if (wins < 82)
        wins++;
    if (start_h >= 2)
        start_h--;
    lvl_apply();
}

/* the help screen's restart: the first game's settings */
void lvl_reset(void)
{
    wins = 0;
    start_h = CFG_CLK_H;
    lvl_apply();
}

/* the "you win / press fire" popup over the room */
void setup_win(void)
{
    lvl_next();
    game_state = ST_WIN;
    KBD_NDX = 0;
    snd_tmr = 0;
    SID(0x04) = 0;
    VIC_SPEN = 0;
    VIC_BRDCOL = GREEN;
    draw_popup_box(SBOX_MSG_WIN);
}

void do_win(void)
{
    uint8_t k = getin();
    if ((k && k != ' ') || (joy_new & 0x10))
        setup_intro();
}

/* the power cell is hit: it burns out (dark grey), the explosion sound */
void setup_explode(void)
{
    game_state = ST_EXPLODE;
    bolt_kill();
    paint_win(DGRAY);
    exp_d011 = VIC_CR1;
    exp_d016 = VIC_CR2;
    expl_tmr = EXPL_LEN;
    sound_boom_start();
}

/* The whole screen shakes: random fine-scroll values, the amplitude dying
 * away, the border on fire. $D011 bit 7 reads the raster's bit 8 but is
 * the raster compare's on write: always write it 0, or the IRQ moves. */
void do_explode(void)
{
    uint8_t amp, r;

    if (!--expl_tmr) {
        VIC_CR1 = exp_d011 & 0x7F;
        VIC_CR2 = exp_d016;
        setup_win();
        return;
    }
    r = lfsr_st << 1;               /* step the LFSR */
    if (lfsr_st & 0x80)
        r ^= 0xB8;
    lfsr_st = r;
    amp = (expl_tmr >> 4) | 1;      /* (never quite still) */
    VIC_CR1 = (VIC_CR1 & 0x78) | (r & amp);
    VIC_CR2 = (VIC_CR2 & 0xF8) | ((r >> 3) & amp);
    VIC_BRDCOL = EXP_COLS[r & 3];
}
