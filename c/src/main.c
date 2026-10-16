/* The entry point and the main loop (titanfall.asm). */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"

/* titanfall.asm's zero page */
ZP uint8_t plr_x, plr_y;
ZP uint8_t clk_h, clk_m, clk_s, clk_tick;
ZP uint8_t react_temp, react_cnt, react_jit;
ZP uint8_t move_tmr, bflash;
ZP uint8_t key_u, key_d, key_l, key_r, key_spc;
ZP uint8_t game_state, death_tmr;
ZP uint8_t term_sel, fire_prev;
ZP uint8_t plr_dying, cur_room;
ZP uint8_t srch_tmr, srch_st;
ZP uint8_t newx, newy;
ZP uint8_t plr_dir, plr_anim, anim_cnt;
ZP uint8_t rob_tmr, rob_phase, gl_sx, gl_sy;
ZP uint8_t player_mode, link_s, link_jif;
ZP uint8_t joy_prev, joy_new, popup_st, f2_prev, f1_prev;
ZP uint8_t bolt_on, bolt_dir, bolt_y, bolt_plr;
ZP uint16_t bolt_x;
ZP uint8_t field_act, ent_x, ent_y, rs_all, grace_tmr;
ZP uint8_t trap_on, trap_len;
ZP uint8_t hop_chg, hop_jmp, hop_ok, hop_dir, hop_leap, hop_show;
uint8_t expl_tmr, exp_d011, exp_d016;

/* shared with the raster IRQ (irq.s) */
volatile uint8_t tick_flag, snd_tmr, snd_kind, music_off, lfsr_st;

/* Frames counted by the IRQ and by the main loop: the difference is the
 * frames the game dropped (read them in the VICE monitor). */
volatile uint8_t irq_frames;
uint8_t loop_frames;

static void wait_frame(void)
{
    while (VIC_CR1 & 0x80)          /* raster line >= 256 ... */
        ;
    while (!(VIC_CR1 & 0x80))       /* ... and back to the top */
        ;
}

/* Hardware init (titanfall.asm's entry point). __low_level_init (irq.s)
 * has already banked BASIC out with interrupts off. */
static void init(void)
{
    /* CIA1's timer IRQ off: it shares the $0314 vector with the raster IRQ,
     * which would then run at ~110 Hz */
    CIA1_ICR = 0x7F;
    (void)CIA1_ICR;

    /* Reset the SID: the TEST bit held ~0.8 s refills the noise generator
     * (a reset doesn't clear the chip's state), then everything zeroed.
     * $D400-$D47F covers the MEGA65's four SIDs. */
    for (uint8_t v = 0x08;; v = 0) {
        for (uint8_t r = 0; r < 0x80; r++)
            SID(r) = v;
        if (!v)
            break;
        for (uint8_t f = 0; f < 40; f++)
            wait_frame();
    }
    music_init();

    VIC_BRDCOL = BLACK;
    VIC_BGCOL = BLACK;
    VIC_VMCSB = 0x1E;               /* screen $0400, charset $3800 */
    REG(0x0291) = 0x0E;             /* KERNAL: no charset switching */

    sprptr_defaults();
    VIC_SPCOL(0) = TYPE_COLOR[ATYPE_HUMAN];
    VIC_SPCOL(3) = WHITE;           /* the bolt's core */
    VIC_SPMC = 0x7F;                /* sprites 0-6 multicolour */
    VIC_SPMC0 = DGRAY;
    VIC_SPMC1 = LTGRAY;
    VIC_SPXEXP = 0;
    VIC_SPYEXP = 0;

    irq_install();
    VIC_CR1 &= 0x7F;
    VIC_RASTER = 50;
    VIC_IRQEN = 0x01;
    VIC_IRQ = 0xFF;

    snd_tmr = 0;                    /* the music plays from the first IRQ */
    music_off = 0;
    joy_prev = 0x1F;                /* a stick held at boot counts as old */
    joy_new = 0;
    f1_prev = 0;
    __asm(" cli\n");
}

/* Joystick 2 once per frame: joy_new = bits pressed now but not last
 * frame (1 = pressed; 0 up, 1 down, 2 left, 3 right, 4 fire). Space counts
 * as fire everywhere, read from the matrix, not GETIN (the KERNAL's key
 * repeat would fake presses). */
static void poll_joystick(void)
{
    uint8_t j;
    CIA1_DDRA = 0xFF;
    CIA1_PRA = 0xFF;
    j = ~CIA1_PRA & 0x1F;
    CIA1_PRA = 0x7F;                /* Space: col 7, row 4 */
    if (!(CIA1_PRB & 0x10))
        j |= 0x10;
    CIA1_PRA = 0xFF;
    joy_new = (j ^ joy_prev) & j;
    joy_prev = j;
}

/* F1 without shift (shift+F1 is F2): the help screen, from any state */
static bool f1_pressed(void)
{
    bool hit = false;
    CIA1_PRA = 0xFE;                /* F1: col 0, row 4 */
    if (CIA1_PRB & 0x10) {
        f1_prev = 0;
    } else {
        CIA1_PRA = 0xFD;            /* left shift: col 1, row 7 */
        if (CIA1_PRB & 0x80) {
            CIA1_PRA = 0xBF;        /* right shift: col 6, row 4 */
            if ((CIA1_PRB & 0x10) && !f1_prev) {
                f1_prev = 1;
                hit = game_state != ST_HELP;
            }
        }
    }
    CIA1_PRA = 0xFF;
    return hit;
}

int main(void)
{
    init();
    setup_intro();
    for (;;) {
        while (!tick_flag)
            ;
        tick_flag = 0;
        loop_frames++;
        poll_joystick();
        if (f1_pressed()) {
            setup_help();
            continue;
        }
        switch (game_state) {
        case ST_INTRO:    do_intro();    break;
        case ST_GAME:     do_game();     break;
        case ST_GAMEOVER: do_gameover(); break;
        case ST_TERMINAL: do_terminal(); break;
        case ST_WIN:      do_win();      break;
        case ST_MAP:      do_map();      break;
        case ST_POPUP:    do_popup();    break;
        case ST_EXPLODE:  do_explode();  break;
        case ST_HELP:     do_help();     break;
        case ST_CARRIER:  do_carrier();  break;
        case ST_DEX:      do_dex();      break;
        default:          do_cutscene(); break;
        }
    }
}
