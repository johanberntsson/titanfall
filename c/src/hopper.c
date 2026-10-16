/* The hopper's jump (actor types with jump: true). Driven: fire held while
 * standing still for HOP_CHARGE frames charges it; then each move jumps
 * two tiles (over floor, a pit or a laser) until HOP_JUMPS are used. By
 * itself it now and then hops a tile further over floor. A 2-tile step
 * sets ACT_HOP: a faster glide, drawn along an arc. (hopper.asm) */
#include "titan.h"


#define HOP_CHARGE 100              /* frames of fire held (2 s) */
#define HOP_JUMPS  2                /* jumps per charge */
#define HOP_COL    WHITE            /* the colour while charged */

/* every frame while a robot is driven */
void hop_charge_tick(void)
{
    uint8_t a = player_mode - 1;

    if (!TYPE_JUMP[ACT_TYPE[a]])
        return;
    if (ACT_ALIVE[a] == 1 && !hop_jmp && fire_prev &&
        !(key_u | key_d | key_l | key_r)) {
        if (++hop_chg < HOP_CHARGE)
            return;
        hop_jmp = HOP_JUMPS;        /* charged */
    }
    hop_chg = 0;                    /* fire let go, moving: start again */
}

static bool in_room(uint8_t a, uint8_t x, uint8_t y)
{
    uint8_t r = ACT_ROOM[a];
    return x <= ROOM_MAXX[r] && y <= ROOM_MAXY[r];
}

/* From try_act: driven actor a, mx/my = one step on. A charged jumper
 * jumps if it can -- the middle tile floor or a pit, the landing (two
 * tiles on) not solid, neither the human's -- and returns true. Otherwise
 * false: an ordinary step, the charge kept. */
bool hop_try(uint8_t a, uint8_t mx, uint8_t my)
{
    uint8_t r = ACT_ROOM[a], x, y, b;

    if (!TYPE_JUMP[ACT_TYPE[a]] || !hop_jmp)
        return false;
    if (!in_room(a, mx, my) || (mx == plr_x && my == plr_y))
        return false;
    b = wall_at(r, mx, my);
    if (W_BLOCKED(b) && !W_PIT(b))
        return false;
    x = mx * 2 - ACT_X[a];          /* landing = 2 * middle - start */
    y = my * 2 - ACT_Y[a];
    if (!in_room(a, x, y) || (x == plr_x && y == plr_y) ||
        W_BLOCKED(wall_at(r, x, y)))
        return false;
    ACT_X[a] = x;
    ACT_Y[a] = y;
    act_step_anim(a);
    ACT_HOP[a] = 1;
    hop_jmp--;
    if (laser_at(cur_room, x, y)) { /* landed in a laser: slide in, die */
        pend_lsr = laser_hit;
        ACT_ALIVE[a] = 2;
    }
    return true;
}

/* After an AI step (roam_try, hop_dir its direction): about one time in
 * four a jumper hops one more tile, over plain floor (pits fence it in). */
void hop_ai(uint8_t a)
{
    uint8_t x, y;

    if (!TYPE_JUMP[ACT_TYPE[a]] || (rand8() & 0x18))
        return;
    x = ACT_X[a] + DIR_DX[hop_dir];
    y = ACT_Y[a] + DIR_DY[hop_dir];
    if (!in_room(a, x, y) || W_BLOCKED(wall_at(ACT_ROOM[a], x, y)) ||
        laser_at(ACT_ROOM[a], x, y))
        return;
    ACT_X[a] = x;
    ACT_Y[a] = y;
    sw_actor(a);                    /* onto a switch: flip */
    ACT_HOP[a] = 1;
}

/* a patrol may hop when the waypoint is d (signed) >= 2 tiles away */
void hop_pd(uint8_t d)
{
    if (d & 0x80)
        d = -d;
    hop_ok = d >= 2;
}

/* Every frame, actor a in robot slot s: a jumper's colour -- HOP_COL in
 * mid-jump or charged, flashing while charging, else its own. hop_show:
 * the driven one stands charged (frame_ptr's charged pose). */
void hop_color(uint8_t a, uint8_t s)
{
    uint8_t t = ACT_TYPE[a], c;

    hop_show = 0;
    if (!TYPE_JUMP[t])
        return;
    c = TYPE_COLOR[t];
    if (hop_leap) {
        c = HOP_COL;                /* in the air */
    } else if (DRIVEN(a)) {
        if (hop_jmp) {
            hop_show = 1;
            c = HOP_COL;
        } else if (hop_chg & 4) {
            c = HOP_COL;
        }
    }
    VIC_SPCOL(SLOT_HW[s]) = c;
}

/* height (px) by distance left: a parabola over the 32 px of a 2-tile jump */
static const uint8_t HOP_ARCTAB[33] = {
    0, 1, 2, 3, 4, 5, 6, 6, 7, 8, 8, 9, 9, 9, 9, 9, 10,
    9, 9, 9, 9, 9, 8, 8, 7, 6, 6, 5, 4, 3, 2, 1, 0
};

/* While a 2-tile step of actor a glides, draw it off its path (spr_x/
 * spr_y): up for a jump left/right, out to the left for one up/down; and
 * hop_leap for the leap pose. Display only. */
void hop_arc(uint8_t a)
{
    int8_t d;

    hop_leap = 0;
    if (!ACT_HOP[a])
        return;
    d = GL_PXL[a] - glt_l;          /* (|distance| <= 32) */
    if (d) {
        if (d < 0)
            d = -d;
        if (d > 32)
            return;
        spr_y -= HOP_ARCTAB[d];     /* left/right: up through the air */
    } else {
        d = GL_PY[a] - glt_y;
        if (!d)
            return;
        if (d < 0)
            d = -d;
        if (d > 32)
            return;
        spr_x -= HOP_ARCTAB[d];     /* up/down: out to the left */
    }
    hop_leap = 1;
}
