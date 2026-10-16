/* The game state (GAME_STATE = 1): the frame, a new game, a new round, the
 * HUD, the clock and the reactor, the robot link. (game.asm, first part) */
#include "titan.h"

uint8_t react_kl, react_kh;         /* the reactor gauge's scale (REACT_KL/KH) */
uint8_t start_h = CFG_CLK_H;        /* the starting clock's hours (win.c) */
uint8_t wins;                       /* games won since loading */

#define HUD_CLK 32                  /* HUD row columns: clock, first gauge segment */
#define HUD_BAR 20
#define REACT_SPAN 89               /* 99 - the starting temperature (10) */

static const uint8_t REACT_ZONES[8] = {
    LTGREEN, LTGREEN, LTGREEN, LTGREEN, YELLOW, YELLOW, LTRED, LTRED
};

static void tick_link(void);

/* what the HUD shows now ($FF: redraw everything) -- the clock and the mode
 * are only drawn when they change (the asm draws them every frame) */
static uint8_t hud_s = 0xFF, hud_mode, hud_link;
static uint8_t react_m = 0xFF, react_h;
static uint8_t stat_sig = 0xFF;     /* what row 24 shows: a checksum */  /* the clock tick_reactor last used */
static void tick_reactor(void);

/* ---- the frame ------------------------------------------------------- */

void do_game(void)
{
    if (death_tmr) {                /* the death pause */
        if (--death_tmr == 0)
            apply_death_penalty();
        return;
    }
    tick_clock();
    if (clock_zero()) {             /* out of time: game over */
        setup_gameover();
        return;
    }
    tick_link();
    tick_reactor();
    anim_cnt++;
    if (!(anim_cnt & 7))
        anim_laser();               /* the beams crawl ~6 times a second */
    anim_comm();                    /* the COMM desk's waves (carrier.c) */
    if (!(anim_cnt & 15))
        win_flicker();              /* the power cell: cyan <-> purple */
    tick_robot();
    read_keys();
    if (game_state != ST_GAME)      /* terminal/popup opened by a key */
        return;
    move_player();
    if (game_state != ST_GAME)      /* terminal/win/map/popup entered */
        return;
    trap_zap();
    plate_tick();
    shut_tick();
    beam_zap();
    grace_tick();                   /* (before update_sprite0: a pit hides it) */
    update_sprite0();
    update_robot_sprites();
    field_tick();                   /* (both before the collision read) */
    bolt_tick();
    if (game_state != ST_GAME)      /* the bolt won the game */
        return;
    check_sprite_hit();
    draw_hud_dynamic();
    draw_status();
    draw_orders();
}

/* ---- a new game, a new round ---------------------------------------- */

/* a fresh game, clock included (the briefing, the help screen's restart) */
void setup_game(void)
{
    uint16_t start = start_h * 60 + CFG_CLK_M;
    uint16_t k = (REACT_SPAN * 256 + start / 2) / start;
    react_kl = k;                   /* the gauge shows 10% at every start */
    react_kh = k >> 8;
    clk_h = start_h;
    clk_m = CFG_CLK_M;
    clk_s = CFG_CLK_S;
    clk_tick = 0;
    /* inventory, opened doors, visited rooms only reset on a new game */
    fill(ITEM_STATE, 0, NUM_ITEMS);
    fill(DOOR_OPEN, 0, NUM_DOORS);
    reset_walls();
    gate_reset();
    ilk_reset();
    shut_reset();
    fill(ROOM_SEEN, 0, NUM_ROOMS);
    copy(CODE_CNT, CODE_START, NUM_CODES);
    cl_reset();
    cur_room = START_ROOM;
    plr_x = ROOM_PSX[START_ROOM];
    plr_y = ROOM_PSY[START_ROOM];
    save_entry();
    rs_all = 1;                     /* every room's robots and lasers */
    reset_round();
}

/* entering a room: the respawn point and the code counts (a death gives
 * back the codes spent in the room) */
void save_entry(void)
{
    ent_x = plr_x;
    ent_y = plr_y;
    copy(CODE_ENT, CODE_CNT, NUM_CODES);
}

void restore_codes(void)
{
    copy(CODE_CNT, CODE_ENT, NUM_CODES);
}

/* The per-round state: the player back where the room was entered, the
 * room reset (every room with rs_all), the playfield redrawn. The clock is
 * left alone (setup_game sets it, a respawn keeps the penalized one). */
void reset_round(void)
{
    game_state = ST_GAME;
    KBD_NDX = 0;
    VIC_SPEN = 0;                   /* no sprites (or collisions) while redrawing */
    VIC_BRDCOL = BLACK;
    VIC_BGCOL = BLACK;
    plr_x = ent_x;
    plr_y = ent_y;
    react_temp = react_cnt = react_jit = 0;
    react_m = 0xFF;                 /* tick_reactor: work it out again */
    lfsr_st = CIA1_TALO | 1;        /* seeded by the time of the fire press */
    move_tmr = 0;
    key_u = key_d = key_l = key_r = 0;
    death_tmr = plr_dying = grace_tmr = 0;
    bflash = 0;
    snd_tmr = 0;
    player_mode = 0;
    plr_dir = DIR_DOWN;
    plr_anim = 0;
    reset_room();
    rs_all = 0;                     /* the next one is a respawn */
    rob_tmr = 0;
    rob_phase = 0;

    cls();
    sprptr_defaults();
    draw_hud_static();
    draw_status_static();
    orders_shown = 0xFF;            /* row 1 is blank: draw it */
    draw_room();
    /* robots first, then drop a collision latched in $D01E during the death
     * pause (nothing reads it then) -- or a robot kill kills the respawned
     * player again -- and only then show the player */
    update_sprite0();
    update_robot_sprites();
    (void)VIC_SPCOLL;
    VIC_SPEN |= 0x01;
}

/* CUR_ROOM's actors, lasers, crates and switches back to the start (every
 * room's with rs_all) */
void reset_room(void)
{
    for (uint8_t a = 0; a < NUM_ACTORS; a++) {
        if (!rs_mine(ACT_ROOM[a]))
            continue;
        ACT_X[a] = ACT_SX[a];
        ACT_Y[a] = ACT_SY[a];
        ACT_TGT[a] = 1;
        ACT_ALIVE[a] = 1;
        ACT_ANIM[a] = 0;
        ACT_FAST[a] = 0;
        ACT_DIR[a] = TYPE_DIR0[ACT_TYPE[a]];
    }
    for (uint8_t l = 0; l < NUM_LASERS; l++)
        if (rs_mine(LASER_ROOM[l]))
            LASER_STATE[l] = 0;
    crate_reset();
    sw_roomreset();
}

/* ---- death ----------------------------------------------------------- */

void player_die(void)
{
    VIC_BRDCOL = RED;
    death_tmr = ZAP_LEN;
    sound_zap_start();
}

/* Impossible Mission style: a death costs CFG_PENALTY_M minutes and
 * respawns where the room was entered -- or ends the game if that was the
 * last of the time. */
void apply_death_penalty(void)
{
    if (!sub_minutes(CFG_PENALTY_M)) {
        setup_gameover();
        return;
    }
    restore_codes();
    reset_round();
    grace_tmr = GRACE_LEN;          /* a moment before the robots notice */
}

/* take m minutes (1-59) off the clock, clamped at 0:00:00; false if the
 * clock is at zero now */
bool sub_minutes(uint8_t m)
{
    if (clk_m >= m) {
        clk_m -= m;
    } else if (clk_h) {
        clk_h--;
        clk_m = clk_m + 60 - m;
    } else {
        clk_h = clk_m = clk_s = 0;
    }
    return !clock_zero();
}

/* ---- HUD (row 0) and the status line (row 24) ------------------------ */

static const char HUD_TMPL[] = "human     reactor: " LBR "        " RBR "   00:00:00";

void draw_hud_static(void)
{
    put_text(SCRN, HUD_TMPL, CYAN);
    hud_s = 0xFF;                   /* draw_hud_dynamic: everything */
    hud_mode = 0xFF;
}

void draw_hud_dynamic(void)
{
    uint8_t *p = SCRN + HUD_CLK;
    uint8_t c, lit, shown;

    if (clk_s == hud_s)
        goto mode;
    hud_s = clk_s;
    dec2(clk_h, p);
    p[2] = CH_COLN;
    dec2(clk_m, p + 3);
    p[5] = CH_COLN;
    dec2(clk_s, p + 6);
    c = (clk_h || clk_m >= 10) ? WHITE : LTRED;
    for (lit = 0; lit < 8; lit++)
        (CRAM + HUD_CLK)[lit] = c;

mode:
    if (player_mode == hud_mode && link_s == hud_link)
        goto gauge;
    hud_mode = player_mode;
    hud_link = link_s;
    if (player_mode) {              /* "robot 30": seconds of link left */
        put_text(SCRN, "robot", GREEN);
        dec2(link_s, SCRN + 6);
        CRAM[6] = CRAM[7] = GREEN;
    } else {
        put_text(SCRN, "human", CYAN);
        SCRN[6] = SCRN[7] = CH_SPC;
    }

gauge:
    /* the reactor thermometer: 8 segments, (shown+6)/12 lit in their zone
     * colours, the rest dark grey */
    shown = react_temp + react_jit;
    if (shown > 99)
        shown = 99;
    for (lit = 0, shown += 6; shown >= 12; shown -= 12)
        lit++;                      /* (shown + 6) / 12 */
    for (uint8_t i = 0; i < 8; i++) {
        (SCRN + HUD_BAR)[i] = CH_SOLID;
        (CRAM + HUD_BAR)[i] = i < lit ? REACT_ZONES[i] : DGRAY;
    }
}

#define STAT_SCR (SCRN + 960)       /* row 24 */
#define STAT_COL (CRAM + 960)

/* Row 24's template (generated from titan.yaml), after every full screen
 * clear (reset_round) */
void draw_status_static(void)
{
    for (uint8_t i = 0; i < 40; i++) {
        STAT_SCR[i] = scr(STAT_TMPL[i]);
        STAT_COL[i] = DGRAY;
    }
    stat_sig = 0xFF;                /* the fields too */
    draw_status();
}

/* Row 24's fields, every frame: each cell is written once, with its final
 * value. (The asm redraws the template every frame, through a buffer --
 * drawing the template and then the counts over it made the card flicker
 * under the raster beam. Writing only the fields avoids both, and saves
 * the C build ~4000 cycles a frame.) */
void draw_status(void)
{
    uint8_t i, found, sig = 0;

    /* only when a code count or an item changed (cheaper than drawing) */
    for (i = 0; i < NUM_CODES; i++)
        sig += CODE_CNT[i] << i;
    for (i = 0; i < NUM_ITEMS; i++)
        sig = (sig << 1 | sig >> 7) ^ ITEM_STATE[i];
    if (sig == stat_sig)
        return;
    stat_sig = sig;

    for (i = 0; i < NUM_CODES; i++) {   /* one digit each, 4 columns apart */
        STAT_SCR[STAT_CNT_COL + 4 * i] = CH_0 + CODE_CNT[i];
        STAT_COL[STAT_CNT_COL + 4 * i] = YELLOW;
    }
#if STAT_KEY_COL
    /* launch keys: the found ones (carried or turned in) yellow first */
    found = 0;
    for (i = 0; i < NUM_ITEMS; i++)
        if (ITEM_LKEY[i] && ITEM_STATE[i])
            found++;
    for (i = 0; i < NUM_LKEYS; i++) {
        (STAT_SCR + STAT_KEY_COL)[i] = CH_KEY;
        (STAT_COL + STAT_KEY_COL)[i] = i < found ? YELLOW : MGRAY;
    }
#endif
    /* cards: grey until found, then in the card's colour */
    for (i = 0; i < NUM_CARDS; i++) {
        (STAT_SCR + STAT_CARD_COL)[i] = CH_CARD;
        (STAT_COL + STAT_CARD_COL)[i] =
            ITEM_STATE[CARD_ITEM[i]] ? CARD_COLOR[i] : MGRAY;
    }
}

/* ---- the robot link ---------------------------------------------------- */

/* A link lasts CFG_LINK_S seconds of game time; F7 (move.c) or the timer
 * ends it through end_link(), with a cyan flash. */
void start_link(uint8_t actor)
{
    player_mode = actor + 1;
    link_s = CFG_LINK_S;
    link_jif = 0;
    hop_chg = hop_jmp = 0;          /* a new link starts uncharged */
}

static void tick_link(void)
{
    if (!player_mode)
        return;
    if (++link_jif < 50)
        return;
    link_jif = 0;
    if (--link_s == 0)
        end_link();
}

void end_link(void)
{
    player_mode = 0;                /* back to human control */
    flash(CYAN);
}

/* the border flashes; update_sprite0 counts bflash down and ends it */
void flash(uint8_t col)
{
    VIC_BRDCOL = col;
    bflash = 15;
}

/* ---- the clock and the reactor ------------------------------------- */

bool clock_zero(void)
{
    return !(clk_h | clk_m | clk_s);
}

/* clamped at 0:00:00 */
void tick_clock(void)
{
    if (clock_zero() || ++clk_tick < 50)
        return;
    clk_tick = 0;
    if (clk_s) {
        clk_s--;
    } else {
        clk_s = 59;
        if (clk_m) {
            clk_m--;
        } else {
            clk_m = 59;
            clk_h--;
        }
    }
}

static uint8_t lfsr_step(void)
{
    uint8_t v = lfsr_st << 1;
    if (lfsr_st & 0x80)
        v ^= 0xB8;
    lfsr_st = v;
    return v;
}

/* REACT_TEMP = 99 - M*89/START: 10 at the start, 99 as the clock runs out
 * (M = minutes left; the scale react_k = 89*256/START, from setup_game).
 * A 0-3 flicker on top, re-rolled every 8 frames (display only). */
static void tick_reactor(void)
{
    uint16_t m, t;
    lfsr_step();
    if (!(++react_cnt & 7))
        react_jit = lfsr_st & 3;
    if (clk_m == react_m && clk_h == react_h)
        return;                     /* (it only changes with the minutes) */
    react_m = clk_m;
    react_h = clk_h;
    m = clk_h * 60 + clk_m;
    t = (m * (uint16_t)(react_kl | react_kh << 8)) >> 8;
    react_temp = t > 99 ? 0 : 99 - t;
}

/* a random byte: the LFSR mixed with CIA1 timer A, which drifts against
 * the frame (the LFSR's low 3 bits are poor: use bits 3-7) */
uint8_t rand8(void)
{
    return lfsr_step() ^ CIA1_TALO;
}

/* ---- sound effects (voice 1; sound_tick in irq.s plays them) -------- */

void sound_zap_start(void)
{
    snd_tmr = ZAP_LEN;
    snd_kind = 0;
    SID(0x05) = 0x00;               /* attack 0, decay 0 */
    SID(0x06) = 0xF0;               /* sustain 15 */
    SID(0x18) = 0x0F;
    SID(0x02) = 0x00;               /* pulse $0200: thin, raspy */
    SID(0x03) = 0x02;
    SID(0x00) = 0x00;               /* ~68 Hz: mains hum */
    SID(0x01) = 0x04;
    SID(0x04) = 0x41;               /* pulse + gate */
}

void sound_boom_start(void)
{
    snd_tmr = BOOM_LEN;
    snd_kind = 1;
    SID(0x18) = 0x0F;
    SID(0x05) = 0x0B;               /* attack 0, decay ~1.5 s */
    SID(0x06) = 0x00;
    SID(0x00) = 0x00;
    SID(0x01) = 0x18;               /* noise, fairly low */
    SID(0x04) = 0x81;
}
