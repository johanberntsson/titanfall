/* Help / pause (GAME_STATE = 9): F1 from any state. Everything stops (no
 * do_* of the interrupted state runs; music and effects silenced); the
 * screen, colour RAM and VIC state are saved and put back on resume.
 *   space / fire  resume           f7        end a robot link, resume
 *   r             reset the room (a reset key, or CFG_RESET_M minutes)
 *   run/stop      restart the game (Esc in VICE)
 * (help.asm) */
#include "titan.h"

#define HLP_SCR ((uint8_t *)0xC600)  /* screen RAM (with the sprite pointers) */
#define HLP_COL ((uint8_t *)0xCA00)  /* colour RAM -- both after the music */

static uint8_t hlp_state, hlp_moff, hlp_snd, hlp_spen, hlp_brd, hlp_bg;
static uint8_t hlp_d011, hlp_d016;

static const uint8_t HLP_TITLE[40] = VB "          help - game paused          " VB;
static const uint8_t HLP_L1[40]    = VB " space to return                      " VB;
static const uint8_t HLP_L2[40]    = VB " f7 to leave robot mode               " VB;
static const uint8_t HLP_L3[40]    = VB " from this screen you can also select " VB;
static const uint8_t HLP_L4[40]    = VB " r to reset room                      " VB;
static const uint8_t HLP_L5[40]    = VB " run/stop (or esc) to restart game    " VB;
static const uint8_t HLP_L4K[40]   = VB " r to reset room (reset keys: 0)      " VB;
static const uint8_t HLP_L4T[40]   = VB " r to reset room (costs 00 minutes)   " VB;

static const struct row HLP_ROWS[] = {
    { 5,  DGRAY,  SCR_BORDER_TOP },
    { 6,  DGRAY,  SCR_BLANK },
    { 7,  YELLOW, HLP_TITLE },
    { 8,  BLUE,   ITR_SEP },
    { 9,  DGRAY,  SCR_BLANK },
    { 10, WHITE,  HLP_L1 },
    { 11, WHITE,  HLP_L2 },
    { 12, DGRAY,  SCR_BLANK },
    { 13, MGRAY,  HLP_L3 },
    { 14, WHITE,  HLP_L4 },
    { 15, WHITE,  HLP_L5 },
    { 16, DGRAY,  SCR_BLANK },
    { 17, DGRAY,  SCR_BORDER_BOTTOM },
    { ROWS_END }
};

void setup_help(void)
{
    uint8_t d011, d016;

    hlp_state = game_state;
    game_state = ST_HELP;
    hlp_moff = music_off;
    music_off = 1;                  /* (first: the IRQ plays music once
                                     *  snd_tmr is 0) */
    hlp_snd = snd_tmr;
    snd_tmr = 0;
    SID(0x04) = SID(0x0B) = SID(0x12) = 0;  /* all three voices off */
    hlp_spen = VIC_SPEN;
    VIC_SPEN = 0;
    hlp_brd = VIC_BRDCOL;
    hlp_bg = VIC_BGCOL;
    hlp_d011 = VIC_CR1 & 0x7F;      /* (bit 7 reads the raster: see win.c) */
    hlp_d016 = VIC_CR2;
    /* the help screen unshaken: the explosion shakes the fine scroll */
    d011 = hlp_d011;
    d016 = hlp_d016;
    if (hlp_state == ST_EXPLODE) {
        d011 = exp_d011;
        d016 = exp_d016;
    }
    VIC_CR1 = d011 & 0x7F;
    VIC_CR2 = d016;
    copy(HLP_SCR, SCRN, 1024);
    copy(HLP_COL, CRAM, 1024);
    KBD_NDX = 0;                    /* drop the F1 itself */
    VIC_BRDCOL = BLACK;
    VIC_BGCOL = BLACK;
    cls();                          /* (the pointers come back on resume) */
    draw_rows(HLP_ROWS);
    /* the r line says what a reset costs: a key, or minutes */
    if (reset_keys) {
        draw_row(14, HLP_L4K, WHITE);
        SCRN[14 * 40 + 31] = CH_0 + reset_keys;
    } else {
        draw_row(14, HLP_L4T, WHITE);
        dec2(CFG_RESET_M, SCRN + 14 * 40 + 25);
    }
    frame_edges(DGRAY, 5, 17);
}

/* the screen, VIC and sound of the interrupted state back */
static void resume_hw(void)
{
    copy(SCRN, HLP_SCR, 1024);
    copy(CRAM, HLP_COL, 1024);
    VIC_BRDCOL = hlp_brd;
    VIC_BGCOL = hlp_bg;
    VIC_CR1 = hlp_d011;
    VIC_CR2 = hlp_d016;
    (void)VIC_SPCOLL;               /* nothing latched from the restore */
    VIC_SPEN = hlp_spen;
    snd_tmr = hlp_snd;              /* an effect carries on, then the music */
    music_off = hlp_moff;
}

static void back(void)
{
    game_state = hlp_state;
    fire_prev = 1;                  /* the resuming press isn't a new one */
    popup_st = 0;                   /*  (the popup's own detector too) */
    KBD_NDX = 0;
    CIA1_PRA = 0xFF;
}

/* a game under way: game, terminal, map, popup, robodex */
static bool in_game(void)
{
    return hlp_state == ST_GAME || hlp_state == ST_TERMINAL ||
           hlp_state == ST_MAP || hlp_state == ST_POPUP ||
           hlp_state == ST_DEX;
}

/* R: the room back as it was entered -- a respawn without the death
 * penalty. Not while dying (that would dodge the penalty). */
static void help_reset(void)
{
    music_off = hlp_moff;
    KBD_NDX = 0;
    CIA1_PRA = 0xFF;
    if (reset_keys) {
        reset_keys--;
    } else if (!sub_minutes(CFG_RESET_M)) {
        setup_gameover();           /* that was the last of the time */
        return;
    }
    restore_codes();
    reset_round();
    grace_tmr = GRACE_LEN;
}

/* Run/Stop: a new game from the start (the briefing skipped) */
static void help_restart(void)
{
    cs_end_sprites();               /* the cut scene's sprite setup undone */
    if (hlp_moff)                   /* game over had stopped the music */
        music_init();
    music_off = 0;
    KBD_NDX = 0;
    CIA1_PRA = 0xFF;
    lvl_reset();                    /* the first game's clock and silo */
    setup_game();
}

static bool key(uint8_t col, uint8_t row)
{
    CIA1_PRA = col;
    return !(CIA1_PRB & row);
}

void do_help(void)
{
    uint8_t a = player_mode - 1;

    if (joy_new & 0x10) {           /* space / fire */
        resume_hw();
        back();
    } else if (key(0x7F, 0x80)) {   /* Run/Stop: col 7, row 7 */
        help_restart();
    } else if (key(0xFB, 0x02)) {   /* R: col 2, row 1 */
        if (in_game() && !(death_tmr | plr_dying))
            help_reset();
    } else if (key(0xFE, 0x08)) {   /* F7: col 0, row 3 */
        if (hlp_state == ST_GAME && player_mode && ACT_ALIVE[a] == 1) {
            resume_hw();
            end_link();             /* (sets the border: after the restore) */
            back();
        }
    }
    CIA1_PRA = 0xFF;
}
