/* The room on screen, the sprites, the robots' AI, the bolt and the force
 * field. (game.asm, UPDATE_SPRITE0 .. DRAW_ROOM) */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"


uint8_t glt_l, glt_h, glt_y;        /* gl_target: the tile's sprite position */
uint16_t spr_x;                     /* upd_slot: where the sprite is drawn */
uint8_t spr_y;                      /*  (hop_arc lifts it off its path) */

/* robot slot 0-3 -> hardware sprite (3 is the bolt, 4 the force field) */
const uint8_t SLOT_HW[ROBOT_SLOTS] = { 1, 2, 5, 6 };

#define ROAM_MIN    2
#define FIELD_OFS   20              /* the field's px from the robot's sprite */
#define FIELD_OFS_V 18
#define BOLT_SPEED  3

/* ---- the room -------------------------------------------------------- */

/* a list of (map offset lo, hi, char) ended by a $FF hi byte: those cells
 * on screen and in ROOM_BUF (destroyed lasers, opened doors) */
static void erase_art(const uint8_t *p)
{
    for (; !(p[1] & 0x80); p += 3) {
        uint16_t o = p[0] | p[1] << 8;
        uint8_t ch = p[2];
        SCRN[80 + o] = ch;
        CRAM[80 + o] = TILE_COLORS[ch];
        ROOM_BUF[o] = ch;
    }
}

void erase_door(uint8_t d)  { erase_art(DOOR_ART[d]); }
void erase_laser(uint8_t l) { erase_art(LASER_ART[l]); }

/* map this room's actors onto the robot slots (hardware sprites 1, 2, 5, 6) */
static void assign_sprites(void)
{
    uint8_t s = 0;
    fill(SPR_SLOT_ACT, 0xFF, ROBOT_SLOTS);
    for (uint8_t a = 0; a < NUM_ACTORS && s < ROBOT_SLOTS; a++) {
        if (ACT_ROOM[a] != cur_room)
            continue;
        uint8_t t = ACT_TYPE[a], hw = SLOT_HW[s];
        SPR_SLOT_ACT[s++] = a;
        VIC_SPCOL(hw) = TYPE_COLOR[t];
        SPRPTR[hw] = TYPE_SPRPTR[t];
    }
}

/* CUR_ROOM on screen rows 2-23, with everything that's changed since the
 * map was drawn: burnt-out lasers and opened doors (patched into ROOM_BUF
 * before the blit, so they never flash on screen), crates, gates, beams. */
void draw_room(void)
{
    srch_tmr = srch_st = 0;         /* a redraw ends any search, bolt, field */
    bolt_on = 0;
    field_act = 0;
    fire_prev = 1;                  /* want a new press */
    room_unpack();
    for (uint8_t l = 0; l < NUM_LASERS; l++)
        if (LASER_STATE[l] && LASER_ROOM[l] == cur_room)
            erase_laser(l);
    for (uint8_t d = 0; d < NUM_DOORS; d++)
        if (DOOR_OPEN[d] && DOOR_ROOM[d] == cur_room)
            erase_door(d);
    /* the blit: four quarters of 220 bytes, so every address is a
     * constant plus an 8-bit index */
    for (uint8_t i = 0; i < 220; i++) {
        uint8_t c;
        c = ROOM_BUF[i];       (SCRN + 80)[i] = c;  (CRAM + 80)[i] = TILE_COLORS[c];
        c = (ROOM_BUF + 220)[i]; (SCRN + 300)[i] = c; (CRAM + 300)[i] = TILE_COLORS[c];
        c = (ROOM_BUF + 440)[i]; (SCRN + 520)[i] = c; (CRAM + 520)[i] = TILE_COLORS[c];
        c = (ROOM_BUF + 660)[i]; (SCRN + 740)[i] = c; (CRAM + 740)[i] = TILE_COLORS[c];
    }
    crate_draw_all();
    room_dynamic();                 /* gate, emitter beam, trap beam */
    win_flicker();
    snap_all();                     /* no gliding across a room change */
    assign_sprites();
}

/* The laser beams crawl: their dash rows are flipped in the charset itself,
 * so every beam on screen animates at once. Must match the art: $81 the
 * beam, $82/$83 the emitters' beam halves, CFG_BEAM_H's rows 3-4. */
void anim_laser(void)
{
    uint8_t *ch = CHARSET + 0x81 * 8;
    for (uint8_t i = 0; i < 8; i++)
        ch[i] ^= 0x18;
    for (uint8_t i = 0; i < 4; i++) {
        ch[8 + 4 + i] ^= 0x18;      /* $82 rows 4-7 */
        ch[16 + i] ^= 0x18;         /* $83 rows 0-3 */
    }
    CHARSET[CFG_BEAM_H * 8 + 3] ^= 0xFF;
    CHARSET[CFG_BEAM_H * 8 + 4] ^= 0xFF;
}

/* the intact power cell flickers cyan/purple (not over the search popup) */
void win_flicker(void)
{
    if (!srch_st)
        paint_win(anim_cnt & 16 ? PURPLE : CYAN);
}

void paint_win(uint8_t col)
{
    for (const uint8_t *p = ROOM_WINART[cur_room]; !(p[1] & 0x80); p += 2)
        CRAM[80 + (p[0] | p[1] << 8)] = col;
}

/* ---- smooth movement ----------------------------------------------------
 * Logic is on tiles; each sprite has a pixel position (GL_PXL/PXH/PY, slot
 * = actor, GL_PLAYER = the human) that glides gl_sx/gl_sy px a frame toward
 * its tile's, never overshooting. */

/* tile -> sprite position: X = x*16+20 (9 bits), Y = y*16+62 (feet on the
 * tile's bottom line) */
void gl_target(uint8_t x, uint8_t y)
{
    uint16_t px = x * 16 + 20;
    glt_l = px;
    glt_h = px >> 8;
    glt_y = y * 16 + 62;
}

static void gl_snap(uint8_t s, uint8_t x, uint8_t y)
{
    gl_target(x, y);
    GL_PXL[s] = glt_l;
    GL_PXH[s] = glt_h;
    GL_PY[s] = glt_y;
}

/* slot s, one frame toward glt_* */
static void glide(uint8_t s)
{
    uint16_t x = GL_PXL[s] | GL_PXH[s] << 8, tx = glt_l | glt_h << 8;
    uint8_t y = GL_PY[s];

    if (x < tx) {
        x += gl_sx;
        if (x > tx)
            x = tx;
    } else if (x > tx) {
        x -= gl_sx;
        if (x < tx)
            x = tx;
    }
    GL_PXL[s] = x;
    GL_PXH[s] = x >> 8;
    if (y < glt_y) {
        y += gl_sy;
        if (y > glt_y)
            y = glt_y;
    } else if (y > glt_y) {
        y -= gl_sy;
        if (y < glt_y)
            y = glt_y;
    }
    GL_PY[s] = y;
}

static bool at_target(uint8_t s)
{
    return GL_PXL[s] == glt_l && GL_PXH[s] == glt_h && GL_PY[s] == glt_y;
}

void snap_all(void)
{
    gl_snap(GL_PLAYER, plr_x, plr_y);
    for (uint8_t a = 0; a < NUM_ACTORS; a++)
        gl_snap(a, ACT_X[a], ACT_Y[a]);
}

static void set_msb(uint8_t bit, uint8_t on)
{
    if (on)
        VIC_SP_MSB |= bit;
    else
        VIC_SP_MSB &= ~bit;
}

/* The sprite frame of type t facing dir, walk frame f: TYPE_SPRPTR +
 * facing group * 3 + frame. A hover type loops hover/move1/hover/move2 off
 * anim_cnt; a hop type (4 frames a facing: rest, charged, move1, move2)
 * shows the charged pose (hop_show) or, mid-jump (hop_leap), move2. */
static uint8_t frame_ptr(uint8_t t, uint8_t dir, uint8_t f)
{
    uint8_t anim = TYPE_ANIM[t];

    if (anim) {
        if (hop_leap)
            f = 2;
        else if (anim_cnt & 8)
            f = ((anim_cnt >> 4) & 1) + 1;
        else
            f = 0;
    }
    dir -= TYPE_DIR0[t];
    if (anim == 2) {
        if (hop_show)
            f = 1;
        else if (f)
            f++;
        return TYPE_SPRPTR[t] + dir * 4 + f;
    }
    return TYPE_SPRPTR[t] + dir * 3 + f;
}

/* the human's sprite (0); a walk into a laser or pit kills on arrival */
void update_sprite0(void)
{
    SPRPTR[0] = frame_ptr(ATYPE_HUMAN, plr_dir, plr_anim);
    gl_sx = gl_sy = GL_FAST;
    gl_target(plr_x, plr_y);
    glide(GL_PLAYER);
    VIC_SP0X = GL_PXL[GL_PLAYER];
    set_msb(0x01, GL_PXH[GL_PLAYER]);
    VIC_SP0Y = GL_PY[GL_PLAYER];

    if (plr_dying && at_target(GL_PLAYER)) {
        uint8_t d = plr_dying;
        plr_dying = 0;
        if (d == 2)                 /* fell into a pit: the sprite vanishes */
            VIC_SPEN &= ~0x01;
        player_die();
    }
    if (bflash && !--bflash)
        VIC_BRDCOL = BLACK;
}

/* robot slot s: glide its actor toward its tile and show it (hidden if
 * the slot is empty, the actor dead or elsewhere) */
static void upd_slot(uint8_t s)
{
    uint8_t a = SPR_SLOT_ACT[s], hw = SLOT_HW[s], bit = 1 << hw;

    if (a == 0xFF || !ACT_ALIVE[a] || ACT_ROOM[a] != cur_room) {
        VIC_SPEN &= ~bit;
        return;
    }
    /* patrol pace, or the player's pace while driven or rushing */
    gl_sx = gl_sy = (ACT_FAST[a] || DRIVEN(a)) ? GL_FAST : GL_SLOW;
    if (ACT_HOP[a]) {               /* a 2-tile hop: twice as fast */
        gl_sx <<= 1;
        gl_sy <<= 1;
    }
    gl_target(ACT_X[a], ACT_Y[a]);
    /* dying in a laser, and drawn on its tile last frame: destroyed */
    if (ACT_ALIVE[a] == 2 && at_target(a)) {
        robot_laser_death(a);
        VIC_SPEN &= ~bit;
        return;
    }
    glide(a);
    spr_x = GL_PXL[a] | GL_PXH[a] << 8;
    spr_y = GL_PY[a];
    hop_arc(a);                     /* mid-jump: lift it along an arc */
    hop_color(a, s);                /* a jumper's charge colour */
    SPRPTR[hw] = frame_ptr(ACT_TYPE[a], ACT_DIR[a], ACT_ANIM[a]);
    VIC_SPEN |= bit;
    VIC_SPX(hw) = spr_x;
    set_msb(bit, spr_x >> 8);
    VIC_SPY(hw) = spr_y;
}

void update_robot_sprites(void)
{
    for (uint8_t s = 0; s < ROBOT_SLOTS; s++)
        upd_slot(s);
}

/* after a respawn: robots can't see or touch the player; it blinks */
void grace_tick(void)
{
    if (!grace_tmr)
        return;
    if (--grace_tmr && (grace_tmr & 4))
        VIC_SPEN &= ~0x01;
    else
        VIC_SPEN |= 0x01;
}

/* $D01E once a frame (reading clears it): the player touched a robot, the
 * force field or the bolt. Also the human left at a terminal. */
void check_sprite_hit(void)
{
    uint8_t c = VIC_SPCOLL;
    if (!grace_tmr && !death_tmr && (c & 1))
        player_die();
}

/* ---- the robots' AI -------------------------------------------------------
 * Every ROB_HALF frames: a normal-pace actor acts every other time, a
 * rushing one every time. Off-screen ones too. */

/* actor a, one tile in dir if it's free (bounds, walls, active lasers) */
bool roam_try(uint8_t a, uint8_t dir)
{
    uint8_t r = ACT_ROOM[a];
    uint8_t x = ACT_X[a] + DIR_DX[dir], y = ACT_Y[a] + DIR_DY[dir];

    if (x > ROOM_MAXX[r] || y > ROOM_MAXY[r] ||
        W_BLOCKED(wall_at(r, x, y)) || laser_at(r, x, y))
        return false;
    hop_dir = dir;
    act_face(a, dir);
    ACT_X[a] = x;
    ACT_Y[a] = y;
    act_step_anim(a);
    if (hop_ok && TYPE_JUMP[ACT_TYPE[a]])
        hop_ai(a);                  /* a jumper may hop one more tile */
    return true;
}

/* idle: patrol -- one step toward the waypoint (x first), turning round
 * on arrival; blocked both ways, it waits. No patrol: it stands. */
static void patrol_step(uint8_t a)
{
    uint8_t wx, wy, x = ACT_X[a], y = ACT_Y[a];

    if (ACT_WX0[a] == ACT_WX1[a] && ACT_WY0[a] == ACT_WY1[a]) {
        ACT_ANIM[a] = 0;
        return;
    }
    wx = ACT_TGT[a] ? ACT_WX1[a] : ACT_WX0[a];
    wy = ACT_TGT[a] ? ACT_WY1[a] : ACT_WY0[a];
    if (x != wx) {
        hop_pd(x - wx);             /* may hop if 2+ tiles to go */
        if (roam_try(a, x < wx ? DIR_RIGHT : DIR_LEFT))
            return;
    }
    if (y != wy) {
        hop_pd(y - wy);
        if (roam_try(a, y < wy ? DIR_DOWN : DIR_UP))
            return;
    } else if (x == wx) {
        ACT_TGT[a] ^= 1;            /* arrived: turn round */
    }
    ACT_ANIM[a] = 0;
}

/* idle: roam -- a random walk. ACT_TGT = steps left * 4 + direction; at a
 * leg's end, or blocked, a new one (the four directions from a random one;
 * boxed in, it waits). */
static void roam_step(uint8_t a)
{
    uint8_t t = ACT_TGT[a], d;

    if (t >= 4) {
        hop_ok = t >= 8;            /* 2+ steps left: may hop */
        if (roam_try(a, t & 3)) {
            t -= 4;
            if (ACT_HOP[a])
                t -= 4;             /* hopped: one more step of the leg */
            ACT_TGT[a] = t;
            return;
        }
    }
    hop_ok = 0;                     /* a new leg's first step: no hop */
    d = (rand8() >> 3) & 3;
    for (uint8_t n = 0; n < 4; n++, d = (d + 1) & 3)
        if (roam_try(a, d)) {
            ACT_TGT[a] = ((rand8() >> 5) + ROAM_MIN - 1) << 2 | d;
            return;
        }
    ACT_TGT[a] = d;
    ACT_ANIM[a] = 0;
}

static void actor_idle(uint8_t a)
{
    if (ACT_IDLE[a] == IDLE_ROAM)
        roam_step(a);
    else
        patrol_step(a);
}

/* Can actor a see the human along its row (or column)? Human mode, not
 * dying, no grace, same room, no wall between them. Lasers don't block. */
static bool sees(uint8_t a, bool col)
{
    uint8_t x = ACT_X[a], y = ACT_Y[a];

    if (player_mode | plr_dying | grace_tmr || ACT_ROOM[a] != cur_room)
        return false;
    if (col ? x != plr_x : y != plr_y)
        return false;
    while (x != plr_x || y != plr_y) {
        if (col)
            y += y < plr_y ? 1 : 0xFF;
        else
            x += x < plr_x ? 1 : 0xFF;
        if (W_BLOCKED(wall_at(cur_room, x, y)))
            return false;
    }
    return true;
}

/* one step toward the player, along its row (or its column if it's in the
 * player's); never into a beam */
static void advance(uint8_t a)
{
    uint8_t x = ACT_X[a], y = ACT_Y[a], d;

    if (x != plr_x) {
        d = x < plr_x ? DIR_RIGHT : DIR_LEFT;
    } else if (y != plr_y) {
        d = y < plr_y ? DIR_DOWN : DIR_UP;
    } else {
        ACT_ANIM[a] = 0;
        return;
    }
    x += DIR_DX[d];
    y += DIR_DY[d];
    act_face(a, d);                 /* face the player even if blocked */
    if (laser_at(cur_room, x, y)) {
        ACT_ANIM[a] = 0;
        return;
    }
    ACT_X[a] = x;
    ACT_Y[a] = y;
    act_step_anim(a);
}

/* attack: rush -- on sight, double pace toward the player; losing sight,
 * back to normal pace on the normal beat */
static void rush_think(uint8_t a)
{
    if (sees(a, false)) {
        ACT_FAST[a] = 1;
        advance(a);
        return;
    }
    if (ACT_FAST[a]) {
        ACT_FAST[a] = 0;
        if (rob_phase)
            return;
    }
    actor_idle(a);
}

/* attack: forcefield -- it looks along the axis it moves on; on sight the
 * field goes up (field_act) and it advances at normal pace */
static void field_think(uint8_t a)
{
    if (sees(a, ACT_DIR[a] < DIR_LEFT)) {
        field_act = a + 1;
        advance(a);
        return;
    }
    if (field_act == a + 1)
        field_act = 0;              /* lost sight: field down */
    actor_idle(a);
}

/* attack: shoot -- on sight it stops, faces the player and fires */
static void shooter_think(uint8_t a)
{
    uint8_t d;
    if (!sees(a, false)) {
        actor_idle(a);
        return;
    }
    ACT_ANIM[a] = 0;
    if (ACT_X[a] == plr_x)
        return;
    d = ACT_X[a] > plr_x ? DIR_LEFT : DIR_RIGHT;
    act_face(a, d);
    fire_bolt(a, d, 0);
}

/* Each actor thinks every ROB_HALF frames, a normal-pace one only on its
 * phase 0 (every ROB_PERIOD), a rushing one on both -- as in the asm. But
 * the asm runs every actor on the same frame, which in C (~22,000 cycles
 * for the 23 robots) overran the frame: here actor a takes its turn on
 * frame (rob_tmr + a) & 7 = 0 of a 16-frame cycle, so about three robots
 * think per frame. (Robots in a room no longer step in unison.) */
void tick_robot(void)
{
    rob_tmr = (rob_tmr + 1) & 15;   /* the 16-frame cycle */
    /* this frame's actors: (rob_tmr + a) & 7 == 0 */
    for (uint8_t a = -rob_tmr & 7; a < NUM_ACTORS; a += 8) {
        if (ACT_ALIVE[a] != 1 || DRIVEN(a))
            continue;
        rob_phase = ((rob_tmr + a) >> 3) & 1;   /* this actor's phase */
        if (!ACT_FAST[a] && rob_phase)
            continue;
        switch (ACT_ATTACK[a]) {
        case ATK_NONE:       actor_idle(a);    break;
        case ATK_RUSH:       rush_think(a);    break;
        case ATK_FORCEFIELD: field_think(a);   break;
        default:             shooter_think(a); break;
        }
    }
}

/* ---- the force field (hardware sprite 4) ------------------------------- */

void field_tick(void)
{
    uint8_t a = field_act, y, p = SPRP_FIELD;
    uint16_t x;

    if (!a || ACT_ALIVE[--a] != 1 || ACT_ROOM[a] != cur_room ||
        DRIVEN(a)) {
        VIC_SPEN &= ~0x10;
        return;
    }
    x = GL_PXL[a] | GL_PXH[a] << 8;
    y = GL_PY[a];
    switch (ACT_DIR[a]) {
    case DIR_LEFT:  x -= FIELD_OFS; break;
    case DIR_RIGHT: x += FIELD_OFS; break;
    case DIR_UP:    y -= FIELD_OFS_V; p = SPRP_FIELD_V; break;
    default:        y += FIELD_OFS_V; p = SPRP_FIELD_V; break;
    }
    VIC_SPX(4) = x;
    set_msb(0x10, x >> 8);
    VIC_SPY(4) = y;
    VIC_SPCOL(4) = TYPE_COLOR[ACT_TYPE[a]];
    SPRPTR[4] = p + ((anim_cnt >> 1) & 1);
    VIC_SPEN |= 0x10;
}

/* ---- the bolt (hardware sprite 3) -------------------------------------
 * One for everyone. bolt_x/bolt_y: its centre in room pixels. */

void fire_bolt(uint8_t a, uint8_t dir, uint8_t plr)
{
    if (bolt_on)
        return;
    bolt_dir = dir;
    bolt_plr = plr;
    bolt_on = 1;
    bolt_y = ACT_Y[a] * 16 + 8;
    bolt_x = ACT_X[a] * 16 + 8;
}

void bolt_kill(void)
{
    bolt_on = 0;
    VIC_SPEN &= ~0x08;
}

/* BOLT_SPEED px a frame; it dies in a wall or off the room, flies over pits
 * and through robots and lasers; a player's bolt in a win target (the power
 * cell) wins. Hitting the player is the sprite collision. */
void bolt_tick(void)
{
    uint8_t tx, ty, b;

    if (!bolt_on) {
        VIC_SPEN &= ~0x08;
        return;
    }
    switch (bolt_dir) {
    case DIR_RIGHT:
        bolt_x += BOLT_SPEED;
        break;
    case DIR_LEFT:
        if (bolt_x < BOLT_SPEED) {
            bolt_kill();
            return;
        }
        bolt_x -= BOLT_SPEED;
        break;
    case DIR_DOWN:
        bolt_y += BOLT_SPEED;
        break;
    default:
        if (bolt_y < BOLT_SPEED) {
            bolt_kill();
            return;
        }
        bolt_y -= BOLT_SPEED;
        break;
    }
    tx = bolt_x >> 4;
    ty = bolt_y >> 4;
    if (tx >= TILE_COLS || ty >= TILE_ROWS) {
        bolt_kill();
        return;
    }
    b = wall_at(cur_room, tx, ty);
    if (!W_PIT(b)) {
        if ((b & W_TARGET) && bolt_plr) {   /* (before the solid test) */
            bolt_kill();
            setup_explode();        /* the power cell is hit (win.c) */
            return;
        }
        if (b & W_SOLID) {
            bolt_solid(tx, ty);     /* a laser target? (shutters.c) */
            return;
        }
    }
    VIC_SPX(3) = bolt_x + 12;
    set_msb(0x08, (bolt_x + 12) >> 8);
    VIC_SPY(3) = bolt_y + 54;
    SPRPTR[3] = SPRP_BOLT + ((anim_cnt >> 1) & 1);
    VIC_SPEN |= 0x08;
}
