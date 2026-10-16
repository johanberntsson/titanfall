/* Input and movement: the keys, the human's and the driven robot's moves,
 * doors, the wall grid, lasers. (game.asm, READ_KEYS .. LASER_AT) */
#include "titan.h"

/* code below the sprite block (c/titan-c64.scm) */
#pragma clang section text="lowcode"

const uint8_t DIR_DX[4] = { 0, 0, 0xFF, 1 };    /* per DIR_DOWN/UP/LEFT/RIGHT */
const uint8_t DIR_DY[4] = { 1, 0xFF, 0, 0 };

uint8_t laser_hit;                  /* laser_at's laser */
uint8_t pend_lsr;                   /* the laser a dying robot slides into */

/* ---- the wall grid ----------------------------------------------------- */

static const uint8_t ROW20[TILE_ROWS] = { 0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200 };

/* Tile x/y (in bounds) of room's wall grid: genworld.py's ROOM_WALLS_n,
 * 20 bytes per tile row (W_* bits in titan.h) */
uint8_t *wall_ptr(uint8_t room, uint8_t x, uint8_t y)
{
    /* (in a variable: Calypsi 5.18 sign-extends `p + (uint8_t)(a + b)`,
     * so offsets of 128+ -- tile rows 6-10 -- went 256 bytes too low) */
    uint8_t i = ROW20[y] + x;
    return ROOM_WALL[room] + i;
}

uint8_t wall_at(uint8_t room, uint8_t x, uint8_t y)
{
    return *wall_ptr(room, x, y);
}

/* x/y inside an active laser of room? laser_hit = which */
bool laser_at(uint8_t room, uint8_t x, uint8_t y)
{
    for (uint8_t l = 0; l < NUM_LASERS; l++) {
        if (LASER_STATE[l] || LASER_ROOM[l] != room)
            continue;
        if (x >= LASER_X1[l] && x <= LASER_X2[l] &&
            y >= LASER_Y1[l] && y <= LASER_Y2[l]) {
            laser_hit = l;
            return true;
        }
    }
    return false;
}

/* a keyed door's tiles walkable (DOOR_KNUM: its number + 1 in bits 4-7) */
static void open_door_walls(uint8_t d)
{
    uint8_t *p = ROOM_WALL[DOOR_ROOM[d]];
    uint8_t k = DOOR_KNUM[d] << 4;
    for (uint8_t i = 0; i < TILE_ROWS * TILE_COLS; i++)
        if ((p[i] & 0xF0) == k)
            p[i] &= ~W_SOLID;
}

/* a new game: keyed doors solid again, no tile searched */
void reset_walls(void)
{
    for (uint8_t r = 0; r < NUM_ROOMS; r++) {
        uint8_t *p = ROOM_WALL[r];
        uint8_t i = TILE_ROWS * TILE_COLS;
        do {
            uint8_t b = p[--i];
            if (b & (0xF0 | W_SEARCHED))    /* (most bytes: nothing to do) */
                p[i] = (b & ~W_SEARCHED) | (b >= 0x10 ? W_SOLID : 0);
        } while (i);
    }
}

/* ---- the keys ---------------------------------------------------------- */

/* key matrix: write col to PRA, true if row bit is pressed (active low) */
static bool key(uint8_t col, uint8_t row)
{
    CIA1_PRA = col;
    return !(CIA1_PRB & row);
}

void read_keys(void)
{
    uint8_t j, a;

    key_u = key_d = key_l = key_r = key_spc = 0;
    CIA1_DDRA = 0xFF;
    CIA1_PRA = 0xFF;                /* joystick 2, no keyboard column */
    j = CIA1_PRA;
    if (!(j & 1) || key(0xFD, 0x02)) key_u = 1;     /* W */
    if (!(j & 2) || key(0xFD, 0x20)) key_d = 1;     /* S */
    if (!(j & 4) || key(0xFD, 0x04)) key_l = 1;     /* A */
    if (!(j & 8) || key(0xFB, 0x04)) key_r = 1;     /* D */

    /* F2 = shift + F1: the "where am I" popup, edge-detected */
    if (key(0xFE, 0x10) && (key(0xFD, 0x80) || key(0xBF, 0x10))) {
        if (!f2_prev) {
            f2_prev = 1;
            setup_where();
            return;
        }
    } else {
        f2_prev = 0;
    }

    /* fire = the joystick's or Space: fire_prev "held now" (the search),
     * key_spc "freshly pressed" (terminal, a search, the driven shooter) */
    if ((joy_prev & 0x10) || key(0x7F, 0x10)) {
        key_spc = fire_prev ^ 1;
        fire_prev = 1;
    } else {
        fire_prev = 0;
    }

    if (!player_mode) {
        /* a terminal zone: fire opens the terminal (cursor on logoff) */
        for (uint8_t t = 0; t < NUM_TERMZONES; t++) {
            if (TERMZ_ROOM[t] == cur_room &&
                plr_x >= TERMZ_X1[t] && plr_x <= TERMZ_X2[t] &&
                plr_y >= TERMZ_Y1[t] && plr_y <= TERMZ_Y2[t]) {
                if (key_spc) {
                    term_sel = 0xFF;
                    setup_terminal();
                    return;
                }
                search_tick();
                return;
            }
        }
        /* fire on a COMM desk tile: the carrier lock (carrier.c) */
        if (key_spc)
            for (uint8_t c = 0; c < NUM_COMMT; c++)
                if (COMM_ROOM[c] == cur_room && COMM_X[c] == plr_x &&
                    COMM_Y[c] == plr_y) {
                    setup_carrier();
                    return;
                }
        search_tick();              /* hold fire to search (popup.c) */
        return;
    }

    /* driving a robot: F7 ends the link -- not while it's dying in a laser */
    a = player_mode - 1;
    if (key(0xFE, 0x08) && ACT_ALIVE[a] == 1) {
        end_link();
        return;
    }
    hop_charge_tick();              /* a jumper: fire held charges it */
    if (key_spc && ACT_ATTACK[a] == ATK_SHOOT && ACT_ALIVE[a] == 1)
        fire_bolt(a, ACT_DIR[a], 1);    /* a shooter fires the way it faces */
}

/* ---- the human --------------------------------------------------------- */

static void plr_step_anim(void)
{
    plr_anim = plr_anim == 1 ? 2 : 1;
}

/* x/y is outside the walkable range: a door of this room, or a wall */
static bool try_door(uint8_t x, uint8_t y)
{
    for (uint8_t d = 0; d < NUM_DOORS; d++)
        if (DOOR_ROOM[d] == cur_room &&
            x >= DOOR_X1[d] && x <= DOOR_X2[d] &&
            y >= DOOR_Y1[d] && y <= DOOR_Y2[d])
            return door_enter(d);
    return false;
}

/* Move the human to x/y: true if that was handled (a step, a door, a popup),
 * false if a plain wall blocked it (move_player tries the next direction). */
static bool try_move(uint8_t x, uint8_t y)
{
    uint8_t b;

    if (x > ROOM_MAXX[cur_room] || y > ROOM_MAXY[cur_room])
        return try_door(x, y);      /* (-1 wraps to $FF: outside too) */
    b = wall_at(cur_room, x, y);
    if (W_PIT(b)) {
        plr_dying = 2;              /* step in, the sprite vanishes on arrival */
    } else if (W_BLOCKED(b)) {
        if (b >> 4)                 /* a closed keyed door's tile */
            return door_enter(KEYDOOR[(b >> 4) - 1]);
        return ilk_touch(x, y);         /* a wall -- or the interlock's slots */
    } else if (laser_at(cur_room, x, y) || beam_at(x, y)) {
        plr_dying = 1;              /* take the step, die on arrival */
    }
    plr_x = x;
    plr_y = y;
    sw_enter(cur_room, x, y);       /* onto a switch: flip (switches.c) */
    trap_check();                   /* under a laser trap? */
    plr_step_anim();
    return true;
}

static bool human_try(uint8_t dir)
{
    plr_dir = dir;
    return try_move(plr_x + DIR_DX[dir], plr_y + DIR_DY[dir]);
}

/* ---- the driven robot -------------------------------------------------- */

/* Actor a to x/y: true = handled, false = blocked. The step commits first;
 * a laser on the new tile marks it dying (ACT_ALIVE 2), and it glides onto
 * the beam before robot_laser_death (actors.c, upd_dying). */
static bool try_act(uint8_t a, uint8_t x, uint8_t y)
{
    uint8_t r = ACT_ROOM[a], b;

    if (hop_try(a, x, y))           /* a charged jumper: two tiles */
        return true;
    if (x > ROOM_MAXX[r] || y > ROOM_MAXY[r])
        return false;
    b = wall_at(r, x, y);
    if (W_BLOCKED(b) && !(W_PIT(b) && TYPE_FLY[ACT_TYPE[a]]) &&
        !crate_push(a, x, y))       /* a flyer crosses pits; a dozer pushes */
        return false;
    ACT_X[a] = x;
    ACT_Y[a] = y;
    act_step_anim(a);
    if (laser_at(cur_room, x, y)) {
        pend_lsr = laser_hit;
        ACT_ALIVE[a] = 2;
    }
    return true;
}

static bool actor_try(uint8_t a, uint8_t dir)
{
    act_face(a, dir);
    return try_act(a, ACT_X[a] + DIR_DX[dir], ACT_Y[a] + DIR_DY[dir]);
}

/* proxy mode: the keys drive actor player_mode-1 (no doors: robots stay) */
static void move_actor(void)
{
    uint8_t a = player_mode - 1;
    if (ACT_ALIVE[a] != 1)          /* sliding into a laser */
        return;
    if (key_u && actor_try(a, DIR_UP)) return;
    if (key_d && actor_try(a, DIR_DOWN)) return;
    if (key_l && actor_try(a, DIR_LEFT)) return;
    if (key_r && actor_try(a, DIR_RIGHT)) return;
    ACT_ANIM[a] = 0;                /* no step this tick: rest pose */
}

/* One step per MOVE_PERIOD frames. Directions in U, D, L, R order: a
 * walled-off one falls through to the next pressed one. Each attempt turns
 * the sprite; no step drops back to the rest pose. */
void move_player(void)
{
    if (srch_tmr | plr_dying)       /* searching, or sliding into death */
        return;
    if (move_tmr) {
        move_tmr--;
        return;
    }
    move_tmr = MOVE_PERIOD - 1;
    if (player_mode) {
        move_actor();
        return;
    }
    if (key_u && human_try(DIR_UP)) return;
    if (key_d && human_try(DIR_DOWN)) return;
    if (key_l && human_try(DIR_LEFT)) return;
    if (key_r && human_try(DIR_RIGHT)) return;
    plr_anim = 0;
}

/* ---- doors --------------------------------------------------------------- */

/* A keyed door not open yet: without its key the locked popup, with it
 * the door opens (the key is used up) and the player stays put, so the
 * opening is seen. Otherwise: the win exit, or into the next room. */
bool door_enter(uint8_t d)
{
    uint8_t k = DOOR_KEY[d], dest;

    if (k && !DOOR_OPEN[d]) {
        if (k == 0xFF)
            show_popup(SBOX_MSG_SEALED);    /* the interlock's console opens it */
        else if (ITEM_STATE[k - 1] != 1)
            show_popup(SBOX_MSG_LOCKED);
        else {
            ITEM_STATE[k - 1] = 2;
            door_unlock(d);
        }
        return true;
    }
    dest = DOOR_DEST[d];
    if (dest == 0xFF) {             /* leads_to: exit */
        setup_win();
        return true;
    }
    ROOM_SEEN[dest] = 1;            /* (a visited: goal for the room ahead) */
    leave_room();                   /* goal not done: roll the room back */
    cur_room = dest;
    if (DOOR_AX[d] != 0xFF)
        plr_x = DOOR_AX[d];
    if (DOOR_AY[d] != 0xFF)
        plr_y = DOOR_AY[d];
    save_entry();
    plr_step_anim();
    draw_room();
    return true;
}

/* open keyed door d (also the interlock console's release) */
void door_unlock(uint8_t d)
{
    DOOR_OPEN[d] = 1;
    erase_door(d);
    open_door_walls(d);
    flash(GREEN);
}

/* ---- actors -------------------------------------------------------------- */

/* turn actor a, unless its type has no frames that way (directions: 2) */
void act_face(uint8_t a, uint8_t dir)
{
    if (dir >= TYPE_DIR0[ACT_TYPE[a]])
        ACT_DIR[a] = dir;
}

/* actor a took a step: walk1/walk2 */
void act_step_anim(uint8_t a)
{
    sw_actor(a);                    /* onto a switch: flip (switches.c) */
    ACT_HOP[a] = 0;                 /* an ordinary step (hopper.c sets it) */
    ACT_ANIM[a] = ACT_ANIM[a] == 1 ? 2 : 1;
}

/* the dying robot's sprite reached the laser: both are destroyed, the beam
 * vanishes from the art, control snaps back to the human */
void robot_laser_death(uint8_t a)
{
    ACT_ALIVE[a] = 0;
    LASER_STATE[pend_lsr] = 1;
    erase_laser(pend_lsr);
    sound_zap_start();
    flash(YELLOW);
    player_mode = 0;
}
