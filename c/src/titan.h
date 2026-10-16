/* TITAN FALL in C (Calypsi) -- shared declarations.
 *
 * The C port of the asm build in src/. Each .c file ports the asm module of
 * the same name (game.asm is split into game.c, move.c and actors.c), so the
 * two can be read side by side; CLAUDE.md describes the behaviour of both.
 * The world data comes from the same titan.yaml through the asm build's
 * generated files (tools/acme2c.py -> data.h), with the asm names.
 */
#ifndef TITAN_H
#define TITAN_H

#include <stdint.h>
#include <stdbool.h>
#include "data.h"

#define ZP __attribute__((zpage))

/* ---- hardware ---------------------------------------------------------- */
#define REG(a)      (*(volatile uint8_t *)(a))
#define SCRN        ((uint8_t *)0x0400)
#define CRAM        ((uint8_t *)0xD800)
#define SPRPTR      ((uint8_t *)0x07F8)
#define CRAM_OFS    (0xD800 - 0x0400)

#define VIC_SP0X    REG(0xD000)
#define VIC_SP0Y    REG(0xD001)
#define VIC_SPX(n)  REG(0xD000 + 2 * (n))
#define VIC_SPY(n)  REG(0xD001 + 2 * (n))
#define VIC_SP_MSB  REG(0xD010)
#define VIC_CR1     REG(0xD011)
#define VIC_RASTER  REG(0xD012)
#define VIC_SPEN    REG(0xD015)
#define VIC_CR2     REG(0xD016)
#define VIC_SPYEXP  REG(0xD017)
#define VIC_VMCSB   REG(0xD018)
#define VIC_IRQ     REG(0xD019)
#define VIC_IRQEN   REG(0xD01A)
#define VIC_SPMC    REG(0xD01C)
#define VIC_SPXEXP  REG(0xD01D)
#define VIC_SPCOLL  REG(0xD01E)
#define VIC_BRDCOL  REG(0xD020)
#define VIC_BGCOL   REG(0xD021)
#define VIC_SPMC0   REG(0xD025)
#define VIC_SPMC1   REG(0xD026)
#define VIC_SPCOL(n) REG(0xD027 + (n))

#define SID(r)      REG(0xD400 + (r))

#define CIA1_PRA    REG(0xDC00)
#define CIA1_PRB    REG(0xDC01)
#define CIA1_DDRA   REG(0xDC02)
#define CIA1_TALO   REG(0xDC04)
#define CIA1_ICR    REG(0xDC0D)

#define KBD_NDX     REG(0xC6)       /* KERNAL keyboard buffer length */

/* The data in `kdata` (c/titan-c64.scm) lives in the RAM under the KERNAL
 * ROM: read it between kernal_out() and kernal_in() -- interrupts off, no
 * KERNAL calls. (BASIC stays out, I/O in.) */
#include <calypsi/intrinsics6502.h>
#define kernal_out() (__disable_interrupts(), REG(0x01) = 0x35)
#define kernal_in()  (REG(0x01) = 0x36, __enable_interrupts())

enum { BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW, ORANGE, BROWN,
       LTRED, DGRAY, MGRAY, LTGREEN, LTBLUE, LTGRAY };

/* facings -- also the frame-group order inside each sprite set */
enum { DIR_DOWN, DIR_UP, DIR_LEFT, DIR_RIGHT };

enum {
    ST_INTRO, ST_GAME, ST_GAMEOVER, ST_TERMINAL, ST_WIN, ST_MAP, ST_POPUP,
    ST_EXPLODE, ST_CUTSCENE, ST_HELP, ST_CARRIER, ST_DEX
};

#define CH_SPC   0x20
#define CH_0     0x30
#define CH_COLN  0x3A
#define CH_KEY   0xC0               /* the key glyph (status line) */
#define CH_CARD  0xC1               /* the key card glyph */
#define CH_SOLID 0xE0               /* solid block ($A0 is a room tile) */

/* screen codes of the ROM's line glyphs (petscii.asm: S_*), usable inside
 * the ASCII strings (scr() passes everything below 0x60 through) */
#define SC_HBAR  0x43
#define SC_VBAR  0x5D
#define VB       "\x5d"            /* SC_VBAR in a string literal */
#define LBR      "\x1b"            /* [ and ] in a string literal: ASCII's */
#define RBR      "\x1d"            /*  0x5B/0x5D are line glyphs here */
#define SC_RD_UL 0x55               /* rounded corners */
#define SC_RD_UR 0x49
#define SC_RD_LL 0x4A
#define SC_RD_LR 0x4B

/* wall grid bytes (ROOM_WALLS_n, genworld.py) */
#define W_SOLID    0x01
#define W_TARGET   0x02             /* without W_SOLID: a pit */
#define W_SEARCH   0x04
#define W_SEARCHED 0x08
#define W_BLOCKED(b) ((b) & 3)      /* a wall, a target or a pit */
#define W_PIT(b)   (((b) & 3) == 2)

#define SPRP_PLAYER  SPRP_sprite_down_rest
#define SPRP_ROBOT   SPRP_robot_down_rest
#define SPRP_DRONE   SPRP_drone_down_hover
#define SPRP_BOLT    SPRP_bolt_1
#define SPRP_FIELD   SPRP_forcefield_1
#define SPRP_FIELD_V SPRP_forcefield_v_1
/* is actor a the one being driven? (8-bit: `a + 1 == player_mode` is an int
 * compare in C) */
#define DRIVEN(a) ((uint8_t)((a) + 1) == player_mode)
#define CS_FRAMES    (SPRITES + (SPRP_CS_FRAMES - SPRITES_START / 64) * 64)

/* timing (frames) */
#define MOVE_PERIOD 8
#define ROB_PERIOD  16
#define ROB_HALF    (ROB_PERIOD / 2)
#define GL_FAST     2
#define GL_SLOW     1
#define GL_PLAYER   NUM_ACTORS      /* glide slot of the human */
#define GRACE_LEN   100
#define ZAP_LEN     40
#define BOOM_LEN    100
#define ROBOT_SLOTS 4
#define TILE_ROWS   11
#define TILE_COLS   20

/* ---- state shared between modules (titanfall.asm's zero page) ---------- */
extern ZP uint8_t plr_x, plr_y;
extern ZP uint8_t clk_h, clk_m, clk_s, clk_tick;
extern ZP uint8_t react_temp, react_cnt, react_jit;
extern ZP uint8_t move_tmr, bflash;
extern ZP uint8_t key_u, key_d, key_l, key_r, key_spc;
extern ZP uint8_t game_state, death_tmr;
extern ZP uint8_t term_sel, fire_prev;
extern ZP uint8_t plr_dying, cur_room;
extern ZP uint8_t srch_tmr, srch_st;
extern ZP uint8_t plr_dir, plr_anim, anim_cnt;
extern ZP uint8_t rob_tmr, rob_phase, gl_sx, gl_sy;  /* rob_tmr: tick_robot's
                                                         16-frame cycle */
extern ZP uint8_t player_mode, link_s, link_jif;
extern ZP uint8_t joy_prev, joy_new, popup_st, f2_prev, f1_prev;
extern ZP uint8_t bolt_on, bolt_dir, bolt_y, bolt_plr;
extern ZP uint16_t bolt_x;
extern ZP uint8_t field_act, ent_x, ent_y, rs_all, grace_tmr;
extern ZP uint8_t trap_on, trap_len;
extern ZP uint8_t hop_chg, hop_jmp, hop_ok, hop_dir, hop_leap, hop_show;
extern uint8_t expl_tmr, exp_d011, exp_d016;
extern uint8_t pend_lsr;
extern uint8_t glt_l, glt_h, glt_y;     /* gl_target's result */
extern uint16_t spr_x;                  /* upd_slot: where a robot is drawn */
extern uint8_t spr_y;

/* owned by the raster IRQ (irq.s) */
extern volatile uint8_t tick_flag, snd_tmr, snd_kind, music_off, lfsr_st;

/* ---- irq.s ------------------------------------------------------------- */
void irq_install(void);
uint8_t getin(void);                /* KERNAL GETIN, 0 = no key */
void music_init(void);
void sound_zap_start(void);
void sound_boom_start(void);

/* ---- screen.c (titanfall.asm's helpers) -------------------------------- */
/* All text in the C port is ASCII: a-z (0x61-0x7A) become screen codes
 * 1-26; digits and punctuation are the same in both. A PETSCII line glyph
 * is written as its screen code (SC_VBAR ...), always below 0x60, so it
 * passes through. (The asm build keeps PETSCII and uses PET2SCREEN.) */
static inline uint8_t scr(uint8_t c)
{
    return c >= 0x60 ? c - 0x60 : c;
}
uint8_t *row_ptr(uint8_t row);
extern uint8_t dr_l, dr_r, fr_l, fr_r;
void draw_row(uint8_t row, const uint8_t *s, uint8_t col);
void paint_row(uint8_t *row, uint8_t col);
/* a row of a text screen: draw_rows() draws a list ended by ROWS_END */
struct row {
    uint8_t row, col;
    const uint8_t *text;            /* 40 characters */
};
void draw_rows(const struct row *r);
void frame_edges(uint8_t col, uint8_t first, uint8_t last);
void frame_edges_lr(uint8_t col, uint8_t first, uint8_t last);
void put_text(uint8_t *at, const char *s, uint8_t col);
void fill(void *dst, uint8_t v, uint16_t n);     /* fast memset */
void copy(void *dst, const void *src, uint16_t n); /* fast memcpy */
void cls(void);
void sprptr_defaults(void);
void dec2(uint8_t v, uint8_t *out);
extern const uint8_t SCR_BORDER_TOP[40], SCR_BORDER_BOTTOM[40];
extern const uint8_t SCR_BLANK[40], ITR_SEP[40];
#define ROWS_END 0xFF

/* ---- game.c ------------------------------------------------------------ */
void do_game(void);
void setup_game(void);
void save_entry(void);
void reset_round(void);
void reset_room(void);
void restore_codes(void);
void player_die(void);
void apply_death_penalty(void);
void draw_hud_static(void);
void draw_hud_dynamic(void);
void draw_status(void);
void draw_status_static(void);
void start_link(uint8_t actor);
void end_link(void);
void tick_clock(void);
bool clock_zero(void);
bool sub_minutes(uint8_t m);
uint8_t rand8(void);
void flash(uint8_t col);
extern uint8_t react_kl, react_kh;
extern uint8_t start_h, wins;

/* ---- move.c ------------------------------------------------------------ */
void read_keys(void);
void move_player(void);
uint8_t *wall_ptr(uint8_t room, uint8_t x, uint8_t y);
uint8_t wall_at(uint8_t room, uint8_t x, uint8_t y);
bool laser_at(uint8_t room, uint8_t x, uint8_t y);
bool door_enter(uint8_t door);
void door_unlock(uint8_t door);
void reset_walls(void);
void act_face(uint8_t a, uint8_t dir);
void act_step_anim(uint8_t a);
void robot_laser_death(uint8_t a);
extern uint8_t laser_hit;           /* laser_at's laser */
extern const uint8_t DIR_DX[4], DIR_DY[4];

/* ---- actors.c ---------------------------------------------------------- */
void draw_room(void);
void erase_door(uint8_t d);
void erase_laser(uint8_t l);
void update_sprite0(void);
void update_robot_sprites(void);
void snap_all(void);
void tick_robot(void);
void field_tick(void);
void bolt_tick(void);
void bolt_kill(void);
void fire_bolt(uint8_t a, uint8_t dir, uint8_t plr);
void check_sprite_hit(void);
void win_flicker(void);
void paint_win(uint8_t col);
void anim_laser(void);
void grace_tick(void);
bool roam_try(uint8_t a, uint8_t dir);
void gl_target(uint8_t x, uint8_t y);
extern const uint8_t SLOT_HW[4];

/* ---- the other modules ------------------------------------------------- */
void setup_intro(void);             /* intro.c */
void do_intro(void);
void draw_intro_screen(void);
extern uint8_t *const itr_hrs;
void do_gameover(void);             /* gameover.c */
void setup_gameover(void);
void do_win(void);                  /* win.c */
void setup_win(void);
void setup_explode(void);
void do_explode(void);
void lvl_reset(void);
void setup_terminal(void);          /* terminal.c */
void do_terminal(void);
void term_abort(void);
void clear_room(void);
void do_map(void);                  /* map.c */
void setup_map(void);
void do_popup(void);                /* popup.c */
void search_tick(void);
void show_popup(const uint8_t *msg);
void draw_popup_box(const uint8_t *msg);
void setup_linked(uint8_t a);
void setup_where(void);
extern const uint8_t SBOX_MSG_LOCKED[40], SBOX_MSG_SEALED[40];
extern const uint8_t SBOX_MSG_NEEDKEY[40], SBOX_MSG_RELEASED[40];
extern const uint8_t SBOX_MSG_GAMEOVER[40], SBOX_MSG_WIN[40];
void setup_cutscene(void);          /* cutscene.c */
void do_cutscene(void);
void cs_end_sprites(void);
extern uint8_t *const cs_silo, *const cs_hrs;
void draw_orders(void);             /* orders.c */
extern uint8_t orders_shown;
uint8_t goal_done(uint8_t room);
void leave_room(void);
void crate_reset(void);             /* crates.c */
void crate_draw_all(void);
void crate_paint(uint8_t x, uint8_t y, uint8_t mode);
bool crate_push(uint8_t a, uint8_t x, uint8_t y);
bool rs_mine(uint8_t room);
void trap_check(void);              /* traps.c */
bool trap_show(void);
void trap_zap(void);
void plate_tick(void);              /* plates.c */
void gate_open(uint8_t st);
void gate_reset(void);
void gate_roomreset(void);
void gate_paint(void);
void room_overlays(void);
void art_list(const uint8_t *list, uint8_t mode);
void tgt_solid(uint8_t room, uint8_t set);
void room_dynamic(void);            /* beam.c */
void beam_update(void);
bool beam_at(uint8_t x, uint8_t y);
void beam_zap(void);
bool tgt_at(uint8_t x, uint8_t y);
void tgt_destroy(void);
void zap_actor(uint8_t a);
void setup_help(void);              /* help.c */
void do_help(void);
void room_unpack(void);             /* rle.c */
extern uint8_t ROOM_BUF[22 * 40];
void hop_charge_tick(void);         /* hopper.c */
bool hop_try(uint8_t a, uint8_t x, uint8_t y);
void hop_ai(uint8_t a);
void hop_pd(uint8_t d);
void hop_color(uint8_t a, uint8_t slot);
void hop_arc(uint8_t a);
extern uint8_t reset_keys;          /* carrier.c */
void cl_reset(void);
void anim_comm(void);
void setup_carrier(void);
void do_carrier(void);
void sw_enter(uint8_t room, uint8_t x, uint8_t y);  /* switches.c */
void sw_actor(uint8_t a);
void sw_paint(void);
void sw_roomreset(void);
void setup_dex(void);               /* robodex.c */
void do_dex(void);
bool ilk_touch(uint8_t x, uint8_t y);               /* interlock.c */
void ilk_paint(void);
void ilk_reset(void);
void shut_reset(void);              /* shutters.c */
void shut_tick(void);
void shut_paint(void);
void bolt_solid(uint8_t x, uint8_t y);

#endif
