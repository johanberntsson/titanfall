/* Screen helpers and the shared box strings (titanfall.asm). */
#include "titan.h"

uint8_t *row_ptr(uint8_t row)
{
    return SCRN + (uint16_t)row * 40;
}

/* The column window of draw_row/paint_row; whoever narrows it puts 0/39
 * back. (DR_L/DR_R) */
uint8_t dr_l = 0, dr_r = 39;
uint8_t fr_l = 0, fr_r = 39;

void paint_row(uint8_t *row, uint8_t col)
{
    uint8_t *c = row + CRAM_OFS;
    for (uint8_t x = dr_l; x <= dr_r; x++)
        c[x] = col;
}

/* A = screen row, s = a 40-byte string (cols dr_l..dr_r are drawn) */
void draw_row(uint8_t row, const uint8_t *s, uint8_t col)
{
    uint8_t *p = row_ptr(row);
    for (uint8_t x = dr_l; x <= dr_r; x++)
        p[x] = scr(s[x]);
    paint_row(p, col);
}

void draw_rows(const struct row *r)
{
    for (; r->row != ROWS_END; r++)
        draw_row(r->row, r->text, r->col);
}

/* Box rows are drawn one colour per row, so the frame's side bars pick up
 * each row's text colour: repaint them in the frame colour. */
void frame_edges(uint8_t col, uint8_t first, uint8_t last)
{
    fr_l = 0;
    fr_r = 39;
    frame_edges_lr(col, first, last);
}

void frame_edges_lr(uint8_t col, uint8_t first, uint8_t last)
{
    uint8_t *c = CRAM + (uint16_t)first * 40;
    for (uint8_t r = first; r <= last; r++, c += 40) {
        c[fr_l] = col;
        c[fr_r] = col;
    }
}

/* a NUL-terminated string at a screen address, in one colour */
void put_text(uint8_t *at, const char *s, uint8_t col)
{
    for (; *s; s++, at++) {
        *at = scr(*s);
        at[CRAM_OFS] = col;
    }
}

/* Fill and copy: Calypsi's memset/memcpy take ~80 cycles a byte (generic,
 * 16-bit counts); these ~20, a page at a time with an 8-bit index. */
void fill(void *dst, uint8_t v, uint16_t n)
{
    uint8_t *p = dst;
    for (; n >= 256; n -= 256, p += 256) {
        uint8_t i = 0;
        do
            p[i] = v;
        while (++i);
    }
    for (uint8_t i = 0; i < (uint8_t)n; i++)
        p[i] = v;
}

void copy(void *dst, const void *src, uint16_t n)
{
    uint8_t *d = dst;
    const uint8_t *s = src;
    for (; n >= 256; n -= 256, d += 256, s += 256) {
        uint8_t i = 0;
        do
            d[i] = s[i];
        while (++i);
    }
    for (uint8_t i = 0; i < (uint8_t)n; i++)
        d[i] = s[i];
}

void cls(void)
{
    fill(SCRN, CH_SPC, 1024);
    fill(CRAM, LTGRAY, 1024);
}

/* after every cls(): the sprite pointers live at the end of screen RAM */
void sprptr_defaults(void)
{
    SPRPTR[0] = SPRP_PLAYER;
    SPRPTR[1] = SPRP_ROBOT;
    SPRPTR[2] = SPRP_DRONE;
}

/* v (0-99) -> two digit characters */
void dec2(uint8_t v, uint8_t *out)
{
    uint8_t t = 0;
    while (v >= 10) {
        v -= 10;
        t++;
    }
    out[0] = CH_0 + t;
    out[1] = CH_0 + v;
}

const uint8_t SCR_BORDER_TOP[40] = { SC_RD_UL, [1 ... 38] = SC_HBAR, SC_RD_UR };
const uint8_t SCR_BORDER_BOTTOM[40] = { SC_RD_LL, [1 ... 38] = SC_HBAR, SC_RD_LR };
const uint8_t SCR_BLANK[40] = VB "                                      " VB;
const uint8_t ITR_SEP[40]   = VB "  ==================================  " VB;
