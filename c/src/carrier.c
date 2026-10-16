/* The carrier lock (GAME_STATE = 10), the COMM desk's mini-game that wins
 * reset keys. Voice 1 plays a hidden target tone (a buzzy pulse, alone for
 * the first second), voice 2 the dial (a soft triangle); left/right tune
 * the dial until the beat stops, and holding the lock fills the bar. Every
 * key won makes the next harder (one column per key in the tables). The
 * game clock keeps running. (carrier.asm) */
#include "titan.h"

uint8_t reset_keys;                 /* held (F1 -> R spends one) */
static uint8_t cl_won;              /* won this game: the level */

#define CL_RMIN   1                 /* detailed dial speed: start and top */
#define CL_FMAX   6
#define CL_CSPD   48                /* coarse: one steady speed */
#define CL_DETAIL 48                /* |diff| below it: detailed */
#define CL_LISTEN 50                /* frames the target plays alone */
#define CL_MIN    0x1000            /* dial range */
#define CL_MAX    0x3FFF
#define CL_CELLS  24                /* bar width */
#define CL_TSTEP  62                /* frames per time cell (~30 s) */
#define CL_BAR    10                /* first bar column */
#define COMM_RATE 25                /* the desk's art swaps 2 a second */

/*                          key:  1   2   3   4   5   6   7   8   9  10+ */
static const uint8_t CL_WIN[10]   = { 80, 56, 34, 20, 12,  8,  4,  3,  2,  2 };
static const uint8_t CL_HSTEP[10] = {  3,  4,  4,  5,  6,  6,  7,  7,  8,  8 };
static const uint8_t CL_DRIFT[10] = {  0,  0,  1,  1,  1,  1,  2,  2,  2,  3 };
static const uint8_t CL_DRT[10]   = {  0,  0,  8,  4,  2,  1,  1,  1,  1,  1 };
static const uint8_t CL_JIT[10]   = {  0,  0,  0,  0,  3,  6,  9,  8,  6,  6 };
static const uint8_t CL_HINT[10]  = {  2,  2,  2,  1,  0,  0,  0,  0,  0,  0 };

/* one sine period in 16 columns, the ROM's line glyphs at 7 heights */
static const uint8_t CL_WAVE[16] = {
    0x43, 0x44, 0x45, 0x77, 0x77, 0x77, 0x45, 0x44,
    0x43, 0x46, 0x52, 0x6f, 0x6f, 0x6f, 0x52, 0x46
};

static uint8_t cl_lvl, cl_st;       /* level index; 0 tuning, 1 won, 2 lost */
static uint8_t cl_moff;             /* music_off to restore */
static uint16_t cl_dial, cl_base, cl_tgt;
static int16_t cl_sd;               /* dial - target */
static uint16_t cl_diff, cl_ph;     /* |dial - target|; the scope's beat phase */
static int8_t cl_jofs;
static uint8_t cl_ddir, cl_dt, cl_rate, cl_held, cl_slow, cl_det;
static uint8_t cl_hc, cl_ht, cl_in, cl_tc, cl_tt, cl_t, cl_lsn;
static uint8_t comm_tmr = COMM_RATE;

static const uint8_t CLS_TTL[40]  = VB "  * carrier lock - key 01             " VB;
static const uint8_t CLS_SUB[40]  = VB "  tune in the carrier. stop the beat. " VB;
static const uint8_t CLS_SCP[40]  = VB " target " LBR "                        " RBR "    " VB;
static const uint8_t CLS_TUN[40]  = VB " tuner  " LBR "                        " RBR "    " VB;
static const uint8_t CLS_DIA[40]  = VB " dial   " LBR "                        " RBR "    " VB;
static const uint8_t CLS_LCK[40]  = VB " lock   " LBR "                        " RBR "    " VB;
static const uint8_t CLS_TIM[40]  = VB " time   " LBR "                        " RBR "    " VB;
static const uint8_t CLS_HNT[40]  = VB "    left/right=tune     fire=abort    " VB;
static const uint8_t CLS_WON[40]  = VB "    reset key decoded! fire=return    " VB;
static const uint8_t CLS_LOST[40] = VB "    signal lost.  fire=return         " VB;

static const struct row CL_ROWS[] = {
    { 4,  LTGREEN, SCR_BORDER_TOP },
    { 5,  LTGREEN, CLS_TTL },
    { 6,  GREEN,   CLS_SUB },
    { 7,  GREEN,   SCR_BLANK },
    { 8,  GREEN,   CLS_SCP },
    { 9,  GREEN,   CLS_TUN },
    { 10, GREEN,   CLS_DIA },
    { 11, GREEN,   SCR_BLANK },
    { 12, GREEN,   CLS_LCK },
    { 13, GREEN,   CLS_TIM },
    { 14, GREEN,   SCR_BLANK },
    { 15, GREEN,   SCR_BLANK },
    { 16, LTRED,   CLS_HNT },
    { 17, LTGREEN, SCR_BORDER_BOTTOM },
    { ROWS_END }
};

/* setup_game: the starting reset keys, the first level */
void cl_reset(void)
{
    reset_keys = CFG_RESET_START;
    cl_won = 0;
}

/* every game frame: swap the bitmaps of the desk's two sine waves ($D6/$D7,
 * $D8/$D9) and the antenna ($CB/$CC) in the charset -- every one on screen
 * pulses at once (like anim_laser) */
void anim_comm(void)
{
    static const uint8_t PAIRS[3] = { 0xD6, 0xD8, 0xCB };

    if (--comm_tmr)
        return;
    comm_tmr = COMM_RATE;
    for (uint8_t p = 0; p < 3; p++) {
        uint8_t *a = CHARSET + PAIRS[p] * 8;
        for (uint8_t i = 0; i < 8; i++) {
            uint8_t t = a[i];
            a[i] = a[8 + i];
            a[8 + i] = t;
        }
    }
}

static void cl_clamp(void)
{
    if (cl_dial < CL_MIN)
        cl_dial = CL_MIN;
    else if (cl_dial > CL_MAX)
        cl_dial = CL_MAX;
}

/* fire on a COMM desk (read_keys): the screen, the tones */
void setup_carrier(void)
{
    uint8_t off, hi;

    game_state = ST_CARRIER;
    KBD_NDX = 0;
    cl_moff = music_off;
    music_off = 1;                  /* first: no music frame sneaks in */
    SID(0x04) = SID(0x0B) = 0x08;   /* TEST: both oscillators restart */
    snd_tmr = 0;
    cl_st = cl_held = cl_det = cl_slow = cl_dt = cl_t = 0;
    cl_jofs = 0;
    cl_hc = cl_ht = cl_tt = cl_in = 0;
    cl_lsn = CL_LISTEN;
    cl_ph = 0;
    cl_tc = CL_CELLS;
    cl_rate = CL_RMIN;
    cl_lvl = cl_won < 9 ? cl_won : 9;

    /* the target in $1800-$37FF; the dial 25-55% off it, either way */
    cl_base = (uint16_t)((rand8() & 0x1F) + 0x18) << 8;
    cl_base |= rand8();
    cl_ddir = (rand8() >> 3) & 1;
    cl_tgt = cl_base;
    off = ((rand8() >> 3) & 7) + (cl_base >> 10);   /* pages: 0-7 + a quarter */
    hi = cl_base >> 8;
    hi = rand8() & 0x40 ? hi - off : hi + off;      /* below or above */
    cl_dial = hi << 8 | rand8();
    cl_clamp();

    clear_room();
    VIC_SPEN = 0;
    draw_rows(CL_ROWS);
    dec2(cl_won + 1, SCRN + 5 * 40 + 24);  /* "key nn" */
    frame_edges(LTGREEN, 4, 17);
    SID(0x02) = 0x00;               /* the target's pulse: 50% */
    SID(0x03) = 0x08;
    SID(0x05) = SID(0x0C) = 0x00;   /* attack/decay 0 */
    SID(0x06) = SID(0x0D) = 0xF0;   /* sustain full, release 0 */
    SID(0x18) = 0x0F;
}

/* back to the room (as the terminal's logoff) */
static void cl_exit(void)
{
    SID(0x04) = SID(0x0B) = 0;
    music_off = cl_moff;
    KBD_NDX = 0;
    term_abort();
}

/* won or lost: the message on row 15, the tones off */
static void cl_end(const uint8_t *msg, uint8_t col)
{
    draw_row(15, msg, col);
    frame_edges(LTGREEN, 4, 17);
    SID(0x04) = 0x40;               /* gates off */
    SID(0x0B) = 0x10;
}

/* left/right: turn the dial. Coarse range: a steady CL_CSPD units a frame;
 * detailed: CL_RMIN, +1 every 8 frames held, up to CL_FMAX -- and it stays
 * slow until let go (cl_slow), so holding on through the zone doesn't
 * speed up on the far side. */
static void cl_dialin(void)
{
    uint8_t lr = 0;                 /* bit 0 left, bit 1 right */

    if ((joy_prev & 0x04) || (CIA1_PRA = 0xFD, !(CIA1_PRB & 0x04)))
        lr |= 1;                    /* A: col 1, row 2 */
    if ((joy_prev & 0x08) || (CIA1_PRA = 0xFB, !(CIA1_PRB & 0x04)))
        lr |= 2;                    /* D: col 2, row 2 */
    CIA1_PRA = 0xFF;
    if (!lr || lr == 3) {           /* nothing, or both */
        cl_held = cl_slow = 0;
        cl_rate = CL_RMIN;
        return;
    }
    cl_held++;
    if (cl_det) {
        cl_slow = 1;
        if (cl_rate > CL_FMAX) {    /* just came in from coarse: slow */
            cl_rate = CL_RMIN;
            cl_held = 0;
        }
    }
    if (cl_det || cl_slow) {
        if (!(cl_held & 7) && cl_rate < CL_FMAX)
            cl_rate++;              /* detailed: +1 every 8 frames */
    } else {
        cl_rate = CL_CSPD;
    }
    if (lr == 1)
        cl_dial -= cl_rate;
    else
        cl_dial += cl_rate;
    cl_clamp();
}

/* the target drifts (DRIFT units every DRT frames, sometimes turning,
 * and at the range's ends) and jitters (+-JIT every 4 frames) */
static void cl_drifts(void)
{
    uint8_t drt = CL_DRT[cl_lvl], jit = CL_JIT[cl_lvl];

    if (drt && ++cl_dt >= drt) {
        cl_dt = 0;
        if (!(rand8() & 0x78))      /* ~1 in 16: turn round */
            cl_ddir ^= 1;
        if (!cl_ddir) {
            cl_base += CL_DRIFT[cl_lvl];
            if ((cl_base >> 8) >= 0x38)
                cl_ddir = 1;        /* top of the range: down again */
        } else {
            cl_base -= CL_DRIFT[cl_lvl];
            if ((cl_base >> 8) < 0x18)
                cl_ddir = 0;        /* bottom: up again */
        }
    }
    if (jit && !(cl_t & 3)) {
        uint8_t r = (rand8() >> 3) % (2 * jit + 1);
        cl_jofs = (int8_t)(r - jit);
    }
    cl_tgt = cl_base + cl_jofs;
}

/* both tones, every frame (the help screen may have stopped them) */
static void cl_sound(void)
{
    SID(0x00) = cl_tgt;
    SID(0x01) = cl_tgt >> 8;
    SID(0x07) = cl_dial;
    SID(0x08) = cl_dial >> 8;
    SID(0x04) = 0x41;               /* pulse, gate on */
    if (cl_lsn) {
        cl_lsn--;
        SID(0x0B) = 0x10;           /* listening: the tuner's gate off */
    } else {
        SID(0x0B) = 0x11;           /* triangle, gate on */
    }
    SID(0x18) = 0x0F;
}

static void cl_bars(void);

/* a key: the next level is harder */
static void cl_win_it(void)
{
    cl_st = 1;
    cl_bars();                      /* the full lock bar (no time tick) */
    if (reset_keys < 9)
        reset_keys++;
    cl_won++;
    cl_end(CLS_WON, LTGREEN);
}

/* cl_diff = |dial - target|. Inside the window the lock bar fills (full:
 * a key), outside it drains at twice that rate. Also the scope's beat
 * phase: cl_ph += diff * 80 (one beat = 65536). Returns true on a win. */
static bool cl_lock(void)
{
    cl_sd = (int16_t)(cl_dial - cl_tgt);
    cl_ph += (uint16_t)cl_sd * 80;
    cl_diff = cl_sd < 0 ? -cl_sd : cl_sd;
    if (++cl_ht < CL_HSTEP[cl_lvl]) {
        cl_in = cl_diff <= CL_WIN[cl_lvl];
        return false;
    }
    cl_ht = 0;
    if (cl_diff <= CL_WIN[cl_lvl]) {
        cl_in = 1;                  /* (the tuner wave turns green) */
        if (++cl_hc >= CL_CELLS) {
            cl_win_it();
            return true;
        }
    } else {
        cl_in = 0;                  /* a slip costs a little, not everything */
        if (cl_hc)
            cl_hc--;
        if (cl_hc)
            cl_hc--;
    }
    return false;
}

/* 24 cells of the sine on row `row`: phase at the first cell, step per
 * cell (256 = one cycle), colour */
static void cl_waverow(uint8_t row, uint8_t ph, uint8_t step, uint8_t col)
{
    uint8_t *p = row_ptr(row) + CL_BAR;
    for (uint8_t i = 0; i < CL_CELLS; i++, ph += step) {
        p[i] = CL_WAVE[ph >> 4];
        p[i + CRAM_OFS] = col;
    }
}

/* the tuner's wavelength: 32 + (dial - target)/32, clamped to 8..56 */
static uint8_t cl_step(void)
{
    if (cl_sd >= 768)
        return 56;
    if (cl_sd <= -768)
        return 8;
    return 32 + (cl_sd >> 5);
}

/* the target wave (row 8) and the tuner's (row 9), scrolling: the tuner's
 * wavelength is off by the difference and it slides at the beat rate.
 * HINT 1: the slide only (dimmer); HINT 0: noise (ear only). */
static void cl_scope(void)
{
    uint8_t hint = CL_HINT[cl_lvl], col;

    cl_waverow(8, cl_t << 2, 32, CYAN);
    if (!hint) {
        uint8_t *p = row_ptr(9) + CL_BAR;
        for (uint8_t i = 0; i < CL_CELLS; i++) {
            p[i] = CL_WAVE[rand8() >> 5];
            p[i + CRAM_OFS] = DGRAY;
        }
        return;
    }
    col = hint == 2 ? YELLOW : MGRAY;
    if (cl_in)
        col = LTGREEN;              /* in the lock window */
    cl_waverow(9, (cl_t << 2) + (cl_ph >> 8), hint == 2 ? cl_step() : 32, col);
}

/* the dial's position, the lock bar, the time bar (and its countdown) */
static void cl_bars(void)
{
    uint8_t dc = ((cl_dial >> 8) - (CL_MIN >> 8)) >> 1;   /* dial cell 0-23 */
    uint8_t *d = row_ptr(10) + CL_BAR, *l = row_ptr(12) + CL_BAR;
    uint8_t *t = row_ptr(13) + CL_BAR;

    for (uint8_t i = 0; i < CL_CELLS; i++) {
        bool on = i == dc;
        d[i] = on ? CH_SOLID : '.';
        d[i + CRAM_OFS] = on ? WHITE : DGRAY;
        on = i < cl_hc;
        l[i] = on ? CH_SOLID : '.';
        l[i + CRAM_OFS] = on ? LTGREEN : DGRAY;
        on = i < cl_tc;
        t[i] = on ? CH_SOLID : '.';
        t[i + CRAM_OFS] = !on ? DGRAY : i < 6 ? LTRED : YELLOW;
    }
    if (!cl_st && ++cl_tt >= CL_TSTEP) {
        cl_tt = 0;
        cl_tc--;
    }
}

void do_carrier(void)
{
    tick_clock();                   /* the clock keeps running */
    if (clock_zero()) {
        setup_gameover();
        return;
    }
    draw_hud_dynamic();
    if (joy_new & 0x10) {           /* fire: give up, or (over) back */
        cl_exit();
        return;
    }
    if (cl_st)
        return;
    cl_t++;
    cl_dialin();
    cl_drifts();
    cl_sound();
    if (cl_lock())
        return;
    cl_det = cl_diff < CL_DETAIL ? 8 : 0;   /* the range mode */
    cl_scope();
    cl_bars();
    if (!cl_tc) {                   /* time's up: "signal lost" */
        cl_st = 2;
        cl_end(CLS_LOST, LTRED);
    }
}
