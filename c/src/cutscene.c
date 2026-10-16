/* The briefing (GAME_STATE = 8) between the intro and the game: the
 * commander and the agent as double-size walker sprites, the dialog in
 * speech bubbles that close by themselves; then the agent walks off.
 * Fire, Space or Return skip it. (cutscene.asm)
 *
 * Only the %10 pixels have a per-sprite colour, and in the walker they're
 * the skin, so the scene uses copies of four walker frames with %10 and %11
 * swapped (CS_FRAMES): the skin from MC1 (light red here), the clothes from
 * each sprite's own colour. */
#include "titan.h"

#define CS_BOT    13                /* the bubble's bottom border row */
#define CS_TOP    3                 /* first row cs_clear wipes */
#define CS_FLOOR  18
#define CS_Y      178               /* feet on screen row 21 */
#define CS_CX     72                /* commander's sprite X */
#define CS_AX     232               /* agent's */
#define CS_EXITX  344               /* the agent's X off the right edge */
#define CS_SPRP   SPRP_CS_FRAMES    /* +0 left rest, +1 right rest, +2/3 walk */
#define CS_PAUSE  40                /* frames before the first line */
#define CS_GAP    15                /* between bubbles */

static uint8_t cs_ph;               /* 0 pause, 1 a bubble up, 2 walking out */
static uint8_t cs_tmr, cs_an;
static const uint8_t *cs_lp;        /* the next dialog entry */
static uint16_t cs_x;               /* the agent's X while walking out */

/* per speaker: commander, agent */
static const uint8_t CS_BCOL[2]  = { GREEN, LTBLUE };    /* frame, tail */
static const uint8_t CS_TCOL[2]  = { LTGREEN, CYAN };    /* text */
static const uint8_t CS_TAIL1[2] = { 13, 24 };           /* tail columns */
static const uint8_t CS_TAIL2[2] = { 12, 25 };
static const uint8_t CS_TAILC[2] = { 0x4E, 0x4D };       /* "/" and "\" */
static const uint8_t CS_WALKF[4] = { CS_SPRP + 2, CS_SPRP + 1, CS_SPRP + 3, CS_SPRP + 1 };

static const uint8_t CS_HEAD[40] = "    defense command hq  -  0400 hours   ";

/* The dialog: speaker (0 commander, 1 agent), the text with 1 between
 * lines (28 chars, 3 lines at most), 0; $FF ends it. The silo number and
 * the hours are patched by win.c (cs_silo, cs_hrs). */
#define CS_D1 \
    "\1you wanted to see me, sir?\0" \
    "\0yes, agent 9. we have an\1emergency at titan silo "
#define CS_D2 \
    "17.\0" \
    "\1what happened?\0" \
    "\0the robots have taken over\1the silo. the whole crew\1is dead.\0" \
    "\1who is behind this?\0" \
    "\0we don't know. but they are\1preparing a missile launch.\0" \
    "\0the missile will be ready\1in less than "
#define CS_D3 \
    "six hours.  \0" \
    "\1what about a military\1strike?\0" \
    "\0too dangerous. the silo\1is built to take a hit.\0" \
    "\0only a single agent can\1get inside undetected.\1it has to be you, 9.\0" \
    "\1i'm on my way, sir.\0" \
    "\xff"
static uint8_t CS_DIALOG[] = CS_D1 CS_D2 CS_D3;
uint8_t *const cs_silo = CS_DIALOG + sizeof CS_D1 - 1;
uint8_t *const cs_hrs = CS_DIALOG + sizeof CS_D1 + sizeof CS_D2 - 2;

/* %10 <-> %11 pixel pairs (%00/%01 unchanged) */
static uint8_t cs_swap(uint8_t b)
{
    return ((b & 0xAA) >> 1) ^ b;
}

void setup_cutscene(void)
{
    static const uint8_t SRC[4] = {
        SPRP_sprite_left_rest, SPRP_sprite_right_rest,
        SPRP_sprite_right_walk1, SPRP_sprite_right_walk2
    };

    game_state = ST_CUTSCENE;
    VIC_SPEN = 0;
    cls();
    for (uint8_t f = 0; f < 4; f++) {
        const uint8_t *s = SPRITES + (SRC[f] - SPRITES_START / 64) * 64;
        for (uint8_t i = 0; i < 64; i++)
            CS_FRAMES[f * 64 + i] = cs_swap(s[i]);
    }
    draw_row(1, CS_HEAD, MGRAY);
    for (uint8_t r = CS_FLOOR; r < 25; r++) {   /* the floor */
        fill(row_ptr(r), CFG_FLOOR, 40);
        paint_row(row_ptr(r), TILE_COLORS[CFG_FLOOR]);
    }
    SPRPTR[0] = CS_SPRP;            /* the agent, facing left */
    SPRPTR[1] = CS_SPRP + 1;        /* the commander, facing right */
    VIC_SP0X = cs_x = CS_AX;
    VIC_SPX(1) = CS_CX;
    VIC_SP0Y = VIC_SPY(1) = CS_Y;
    VIC_SP_MSB = 0;
    VIC_SPCOL(0) = LTGRAY;          /* the agent's shirt, as in the game */
    VIC_SPCOL(1) = GREEN;           /* the commander's uniform */
    VIC_SPMC1 = LTRED;              /* skin (both) */
    VIC_SPYEXP = VIC_SPXEXP = 0x03; /* double size */
    VIC_SPEN = 0x03;
    cs_lp = CS_DIALOG;
    cs_ph = 0;
    cs_tmr = CS_PAUSE;
    KBD_NDX = 0;
}

/* back to the game's sprite setup (also the help screen's restart) */
void cs_end_sprites(void)
{
    VIC_SPYEXP = VIC_SPXEXP = 0;
    VIC_SP_MSB = 0;
    VIC_SPMC1 = LTGRAY;
    VIC_SPCOL(0) = TYPE_COLOR[ATYPE_HUMAN];
}

static void cs_end(void)
{
    VIC_SPEN = 0;
    cs_end_sprites();
    setup_game();
}

/* wipe the bubble area */
static void cs_clear(void)
{
    fill(SCRN + CS_TOP * 40, CH_SPC, (CS_BOT + 3 - CS_TOP) * 40);
}

static void cs_put(uint8_t row, uint8_t col, uint8_t ch, uint8_t c)
{
    uint8_t *p = row_ptr(row) + col;
    *p = ch;
    p[CRAM_OFS] = c;
}

/* the next entry as a speech bubble above its speaker; how long it stays
 * in cs_tmr; false at the end of the dialog */
static bool cs_bubble(void)
{
    const uint8_t *s = cs_lp;
    uint8_t spk = *s++, nl = 0, w = 0, len = 0, cur = 0, c;
    uint8_t col, rgt, top, row, x;

    if (spk == 0xFF)
        return false;
    do {                            /* measure: lines, the widest, chars */
        c = *s++;
        if (c >= 2) {
            cur++;
            len++;
        } else {
            nl++;
            if (cur > w)
                w = cur;
            cur = 0;
        }
    } while (c);
    cs_tmr = len < 103 ? 50 + 2 * len : 255;    /* 50 frames + 2 per char */
    w += 4;                         /* frame + a space each side */
    col = spk ? 39 - w : 1;         /* the agent's: right edge col 38 */
    rgt = col + w - 1;
    top = CS_BOT - nl - 1;
    for (row = top; row <= CS_BOT; row++) {
        uint8_t l, m, r;
        if (row == top) {           /* rounded corners */
            l = SC_RD_UL; m = SC_HBAR; r = SC_RD_UR;
        } else if (row == CS_BOT) {
            l = SC_RD_LL; m = SC_HBAR; r = SC_RD_LR;
        } else {
            l = r = SC_VBAR; m = CH_SPC;
        }
        cs_put(row, col, l, CS_BCOL[spk]);
        for (x = col + 1; x < rgt; x++)
            cs_put(row, x, m, CS_BCOL[spk]);
        cs_put(row, rgt, r, CS_BCOL[spk]);
    }
    /* the tail, down to the head */
    cs_put(CS_BOT + 1, CS_TAIL1[spk], CS_TAILC[spk], CS_BCOL[spk]);
    cs_put(CS_BOT + 2, CS_TAIL2[spk], CS_TAILC[spk], CS_BCOL[spk]);
    /* the text, line by line */
    s = cs_lp + 1;
    row = top + 1;
    x = col + 2;
    while ((c = *s++)) {
        if (c == 1) {
            row++;
            x = col + 2;
        } else {
            cs_put(row, x++, scr(c), CS_TCOL[spk]);
        }
    }
    cs_lp = s;
    return true;
}

void do_cutscene(void)
{
    if (getin() == 0x0D || (joy_new & 0x10)) {   /* Return, fire / Space */
        cs_end();
        return;
    }
    if (cs_ph == 2) {               /* walking out */
        cs_x += 2;
        VIC_SP0X = cs_x;
        VIC_SP_MSB = cs_x >> 8;     /* sprite 0's bit */
        if (cs_x >= CS_EXITX) {
            cs_end();
            return;
        }
        cs_an++;
        SPRPTR[0] = CS_WALKF[(cs_an >> 3) & 3];
        return;
    }
    if (--cs_tmr)
        return;
    if (cs_ph) {                    /* the bubble's time is up */
        cs_clear();
        cs_ph = 0;
        cs_tmr = CS_GAP;
    } else if (cs_bubble()) {       /* the pause is over: the next line */
        cs_ph = 1;
    } else {                        /* no lines left: walk out */
        cs_ph = 2;
        cs_an = 0;
    }
}
