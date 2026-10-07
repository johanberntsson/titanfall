; =============================================================================
; GAME STATE (GAME_STATE = 1)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_GAME — called each frame in state 1
; ---------------------------------------------------------------------------
DO_GAME
        lda DEATH_TMR
        beq GAME_ALIVE
        dec DEATH_TMR
        bne GAME_TICK_DONE
        jsr APPLY_DEATH_PENALTY
        jmp MAIN_LOOP

GAME_ALIVE
        jsr TICK_CLOCK
        ; Countdown hit 0:00:00 (either just now, or from APPLY_DEATH_PENALTY
        ; clamping it there) — mission's out of time, game over.
        lda CLK_H : ora CLK_M : ora CLK_S : bne GA_CLOCKOK
        jsr SETUP_GAMEOVER
        jmp MAIN_LOOP
GA_CLOCKOK
        jsr TICK_LINK
        jsr TICK_REACTOR
        inc ANIM_CNT            ; drives the always-on hover animation
        lda ANIM_CNT : and #7 : bne GA_NOLASER
        jsr ANIM_LASER          ; flicker the beams ~6 times a second
GA_NOLASER
        jsr TICK_ROBOT
        jsr READ_KEYS
        lda GAME_STATE : cmp #1 : bne GAME_TICK_DONE  ; terminal/popup opened by a key
        jsr MOVE_PLAYER
        lda GAME_STATE : cmp #1 : bne GAME_TICK_DONE  ; terminal/win/map/popup entered this frame
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
        jsr BOLT_TICK                    ; before the collision read
        lda GAME_STATE : cmp #1 : bne GAME_TICK_DONE  ; the bolt won the game
        jsr CHECK_SPRITE_HIT
        jsr DRAW_HUD_DYNAMIC
        jsr DRAW_STATUS
GAME_TICK_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_GAME — initialise a fresh game (clock included) and draw the
; playfield. Called via jsr from DO_INTRO. Sets the starting clock, then
; tail-jumps into RESET_ROUND for everything else.
; =============================================================================
SETUP_GAME
        lda #CFG_CLK_H : sta CLK_H
        lda #CFG_CLK_M : sta CLK_M
        lda #CFG_CLK_S : sta CLK_S
        lda #0   : sta CLK_TICK
        ; all items back to hidden — inventory only resets on a fresh game,
        ; not on death/respawn (RESET_ROUND leaves ITEM_STATE alone)
        ldx #0
SGITEM  cpx #NUM_ITEMS : bcs SGITEMD
        lda #0 : sta ITEM_STATE,x
        inx : bne SGITEM
SGITEMD ldx #0                           ; keyed doors closed again (an opened
SGDOOR  cpx #NUM_DOORS : bcs SGDOORD     ;  door stays open across respawns)
        lda #0 : sta DOOR_OPEN,x
        inx : bne SGDOOR
SGDOORD ldx #0                           ; security codes back to the start counts
SGCODE  cpx #NUM_CODES : bcs SGCODED
        lda CODE_START,x : sta CODE_CNT,x
        inx : bne SGCODE
SGCODED jmp RESET_ROUND

; =============================================================================
; RESET_ROUND — reset all per-round world state (player, reactor, robots,
; room, sprites) to their starting values and redraw the playfield. Does
; NOT touch the countdown clock (CLK_H/M/S/CLK_TICK) — shared by SETUP_GAME
; (fresh game, clock set separately above) and APPLY_DEATH_PENALTY (respawn
; after death, which keeps the already-penalized clock).
; =============================================================================
RESET_ROUND
        lda #1   : sta GAME_STATE
        lda #0   : sta $C6
        lda #0   : sta VIC_SPEN            ; no sprites (or collisions) while redrawing
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL

        lda #START_ROOM : sta CUR_ROOM
        lda ROOM_PSX+START_ROOM : sta PLR_X
        lda ROOM_PSY+START_ROOM : sta PLR_Y
        lda #0   : sta REACT_TEMP          ; set from the clock each frame
        lda #0   : sta REACT_CNT
        lda #0   : sta REACT_JIT
        lda #$A3 : sta LFSR_ST
        lda #0   : sta MOVE_TMR
        lda #0   : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0   : sta DEATH_TMR
        lda #0   : sta PLR_DYING
        lda #0   : sta BFLASH
        lda #0   : sta SND_TMR
        lda #0   : sta PLAYER_MODE
        lda #DIR_DOWN : sta PLR_DIR
        lda #0   : sta PLR_ANIM

        ; all actors back at their start positions, alive, heading for
        ; patrol waypoint 1, standing still facing their type's first
        ; direction; all lasers back on
        ldx #0
RSRACT  cpx #NUM_ACTORS : bcs RSRACTD
        lda ACT_SX,x : sta ACT_X,x
        lda ACT_SY,x : sta ACT_Y,x
        lda #1 : sta ACT_TGT,x
        lda #1 : sta ACT_ALIVE,x
        lda #0 : sta ACT_ANIM,x
        lda #0 : sta ACT_FAST,x
        ldy ACT_TYPE,x
        lda TYPE_DIR0,y : sta ACT_DIR,x
        inx : bne RSRACT
RSRACTD
        ldx #0
RSRLSR  cpx #NUM_LASERS : bcs RSRLSRD
        lda #0 : sta LASER_STATE,x
        inx : bne RSRLSR
RSRLSRD
        lda #ROB_HALF-1 : sta ROB_TMR
        lda #0 : sta ROB_PHASE

        jsr CLS
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2
        jsr DRAW_HUD_STATIC
        jsr DRAW_ROOM

        ; Robots first (UPDATE_ROBOT_SPRITES enables their slots), then drop
        ; any collision still latched in $D01E from the death pause — DO_GAME
        ; doesn't read it while DEATH_TMR runs, so a robot kill would
        ; otherwise kill the respawned player again — and only then show
        ; the player.
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
        lda VIC_SPCOLL
        lda VIC_SPEN : ora #$01 : sta VIC_SPEN
        rts

; =============================================================================
; ANIM_LASER — make every laser beam crawl by flipping its dash pattern in
; the charset itself (so all beams on screen animate at once, no screen RAM
; writes): the beam glyph's rows alternate LASER_DASH / 0, and XOR-ing every
; row with LASER_DASH swaps the two phases. The emitters carry the same
; pattern in their beam half (top emitter rows 4-7, bottom emitter rows
; 0-3), flipped along so the beam stays continuous into them. Must match
; the art: chars $81-$83 in src/charset.asm (art.laser_tiles in titan.yaml).
; =============================================================================
LASER_DASH = $18                        ; the beam's lit pixels (00011000)
CH_BEAM    = CHARSET+$81*8              ; beam, top emitter, bottom emitter
CH_EMIT_T  = CHARSET+$82*8
CH_EMIT_B  = CHARSET+$83*8

ANIM_LASER
        ldx #7
ALBEAM  lda CH_BEAM,x : eor #LASER_DASH : sta CH_BEAM,x
        dex : bpl ALBEAM
        ldx #3
ALEMIT  lda CH_EMIT_T+4,x : eor #LASER_DASH : sta CH_EMIT_T+4,x
        lda CH_EMIT_B,x : eor #LASER_DASH : sta CH_EMIT_B,x
        dex : bpl ALEMIT
        rts

; =============================================================================
; PLAYER_DIE — the human is killed (laser or robot): red border, the laser
; zap, and a ZAP_LEN pause (DEATH_TMR, as long as the zap) before DO_GAME
; calls APPLY_DEATH_PENALTY to respawn.
; =============================================================================
PLAYER_DIE
        lda #RED : sta VIC_BRDCOL
        lda #ZAP_LEN : sta DEATH_TMR
        jmp SOUND_ZAP_START

; =============================================================================
; APPLY_DEATH_PENALTY — Impossible Mission style: laser/robot death no longer
; ends the game outright. Subtract 30 minutes from the countdown clock
; (clamped at 0:00:00, never negative), then either respawn (RESET_ROUND,
; keeping the penalized clock) or, if that exhausts the remaining time, go
; straight to the Game Over screen — the game now only reaches Game Over
; when the clock hits zero (here, or via GAME_ALIVE's own check if time
; simply runs out without a death in between).
; =============================================================================
APPLY_DEATH_PENALTY
        lda CLK_M : cmp #CFG_PENALTY_M : bcs ADPSUB30 ; M>=penalty: subtract from M
        lda CLK_H : bne ADPBORROW             ; M<penalty, H>0: borrow an hour
        lda #0 : sta CLK_H : sta CLK_M : sta CLK_S  ; not enough time left: clamp to 0
        jmp ADPCHECK
ADPBORROW
        dec CLK_H
        lda CLK_M : clc : adc #60-CFG_PENALTY_M : sta CLK_M ; M<penalty, so no overflow
        jmp ADPCHECK
ADPSUB30
        lda CLK_M : sec : sbc #CFG_PENALTY_M : sta CLK_M
ADPCHECK
        lda CLK_H : ora CLK_M : ora CLK_S : bne ADPRESPAWN
        jsr SETUP_GAMEOVER
        rts
ADPRESPAWN
        jmp RESET_ROUND

; =============================================================================
; DRAW_HUD_STATIC
; =============================================================================
DRAW_HUD_STATIC
        ldx #39
HUDST1  lda HUD_TMPL,x : jsr PET2SCREEN : sta SCRN,x
        lda #CYAN : sta CRAM,x
        dex
        bpl HUDST1
        ldx #39
HUDST2  lda #CH_HBLK : sta SCRN+40,x
        lda #BLUE : sta CRAM+40,x
        dex
        bpl HUDST2
        rts

HUD_TMPL
        !pet "human     reactor: [        ]   00:00:00"

; =============================================================================
; DRAW_HUD_DYNAMIC
; =============================================================================
DRAW_HUD_DYNAMIC
        ; layout: mode at cols 0-4, gauge centred at 10-28, clock at 32-39
        lda CLK_H : jsr DEC2
        lda TMP : sta SCRN+HUD_CLK+0 : lda TMP2 : sta SCRN+HUD_CLK+1
        lda #CH_COLN : sta SCRN+HUD_CLK+2
        lda CLK_M : jsr DEC2
        lda TMP : sta SCRN+HUD_CLK+3 : lda TMP2 : sta SCRN+HUD_CLK+4
        lda #CH_COLN : sta SCRN+HUD_CLK+5
        lda CLK_S : jsr DEC2
        lda TMP : sta SCRN+HUD_CLK+6 : lda TMP2 : sta SCRN+HUD_CLK+7

        lda #WHITE
        ldx CLK_H : bne HUDCC
        ldx CLK_M : cpx #10 : bcs HUDCC
        lda #LTRED
HUDCC   ldx #7
HUDCCL  sta CRAM+HUD_CLK,x : dex : bpl HUDCCL

        lda PLAYER_MODE : bne HUDMLR
        ldx #4
HUDML   lda LMODE_H,x : jsr PET2SCREEN : sta SCRN,x
        lda #CYAN : sta CRAM,x
        dex
        bpl HUDML
        jmp HUDMLH
HUDMLR  ldx #4
HUDML2  lda LMODE_R,x : jsr PET2SCREEN : sta SCRN,x
        lda #GREEN : sta CRAM,x
        dex
        bpl HUDML2
        lda LINK_S : jsr DEC2            ; "robot 30": seconds of link left
        lda TMP : sta SCRN+6 : lda TMP2 : sta SCRN+7
        lda #GREEN : sta CRAM+6 : sta CRAM+7
        bne HUDMLDONE                    ; (always)
HUDMLH  lda #CH_SPC : sta SCRN+6 : sta SCRN+7   ; human: clear the count
HUDMLDONE

        ; reactor thermometer: 8 solid segments (cols 20-27), lit ones in
        ; their zone colour (4 green, 2 yellow, 2 red), unlit ones dark grey
        lda REACT_TEMP : clc : adc REACT_JIT     ; shown = base + flicker
        cmp #100 : bcc HUDRV : lda #99
HUDRV   ldx #0                                   ; lit = (shown+6)/12, 0-8
        clc : adc #6
HUDRDV  cmp #12 : bcc HUDRDD
        sbc #12 : inx : bne HUDRDV
HUDRDD  stx TMP2
        ldy #0
HUDBAR  lda #CH_SOLID : sta SCRN+HUD_BAR,y
        lda #DGRAY
        cpy TMP2 : bcs HUDBUL
        lda REACT_ZONES,y
HUDBUL  sta CRAM+HUD_BAR,y
        iny : cpy #8 : bne HUDBAR
        rts

HUD_CLK = 32                    ; HUD row columns: clock, first gauge segment
HUD_BAR = 20

REACT_ZONES !byte LTGREEN,LTGREEN,LTGREEN,LTGREEN,YELLOW,YELLOW,LTRED,LTRED

LMODE_H !pet "human"
LMODE_R !pet "robot"

; =============================================================================
; DEC2 — A (0-99) → TMP=tens char  TMP2=units char
; =============================================================================
DEC2
        ldx #0
DEC2L   cmp #10 : bcc DEC2D
        sec : sbc #10 : inx : bne DEC2L
DEC2D   clc : adc #CH_0 : sta TMP2
        txa : clc : adc #CH_0 : sta TMP
        rts

; =============================================================================
; TICK_LINK — a robot link (PLAYER_MODE != 0) lasts CFG_LINK_S seconds
; (robot_link_seconds in titan.yaml), counted in game frames, so it pauses
; with the clock in terminal/map/popup. On expiry control reverts to the
; human, with a cyan border flash; there's no other way to end a link (robots can't use terminals).
; START_LINK (from TERM_ROBOT, X = actor) starts a link.
; =============================================================================
START_LINK
        inx : stx PLAYER_MODE
        lda #CFG_LINK_S : sta LINK_S
        lda #0 : sta LINK_JIF
        rts

TICK_LINK
        lda PLAYER_MODE : beq TLOUT
        inc LINK_JIF
        lda LINK_JIF : cmp #50 : bcc TLOUT
        lda #0 : sta LINK_JIF
        dec LINK_S : bne TLOUT
        sta PLAYER_MODE                  ; A = 0: back to human control
        lda #CYAN : sta VIC_BRDCOL       ; flash the border in the "human"
        lda #15 : sta BFLASH             ;  HUD colour (UPDATE_SPRITE0 ends it)
TLOUT   rts

; =============================================================================
; TICK_CLOCK
; =============================================================================
TICK_CLOCK
        lda CLK_H : ora CLK_M : ora CLK_S : beq TCKOUT   ; already 0:00:00 — clamp, never go negative
        inc CLK_TICK
        lda CLK_TICK : cmp #50 : bcc TCKOUT
        lda #0 : sta CLK_TICK
        lda CLK_S : bne TCKDS
        lda #59 : sta CLK_S
        lda CLK_M : bne TCKDM
        lda #59 : sta CLK_M
        lda CLK_H : beq TCKOUT
        dec CLK_H : bne TCKOUT
TCKDM   dec CLK_M : bne TCKOUT
TCKDS   dec CLK_S
TCKOUT  rts

; =============================================================================
; TICK_REACTOR
; =============================================================================
TICK_REACTOR
        ; The reactor tracks the countdown: REACT_TEMP = 99 - M*89/START,
        ; with M = minutes left (CLK_H*60+CLK_M) and START = the starting
        ; countdown in minutes — 10 at mission start (one green segment:
        ; visibly safe), 99 as the clock runs out (so a death penalty
        ; visibly heats it up). M*89/START is done as M * REACT_K,
        ; REACT_K = 89*256/START precomputed at assembly time, taking the
        ; high byte. REACT_JIT is a 0-3 flicker shown on top,
        ; re-rolled from the LFSR every 8 frames (display only).
        lda LFSR_ST : asl : bcc RCTNFB : eor #$B8
RCTNFB  sta LFSR_ST
        inc REACT_CNT
        lda REACT_CNT : and #$07 : bne RCTCALC
        lda LFSR_ST : and #$03 : sta REACT_JIT
RCTCALC lda CLK_M : sta TMP              ; TMP/TMP2 = M (16-bit)
        lda #0 : sta TMP2
        ldx CLK_H : beq RCTMUL
RCTHR   lda TMP : clc : adc #60 : sta TMP
        bcc RCTHN : inc TMP2
RCTHN   dex : bne RCTHR
RCTMUL  lda #0 : sta PTR : sta PTR+1     ; PTR = M * REACT_K (16-bit;
        ldx #16                          ;  M <= START keeps it <= 89*256)
RCTML   asl PTR : rol PTR+1
        asl TMP : rol TMP2 : bcc RCTMN
        lda PTR : clc : adc #<REACT_K : sta PTR
        lda PTR+1 : adc #>REACT_K : sta PTR+1
RCTMN   dex : bne RCTML
        lda #99 : sec : sbc PTR+1
        bcs RCTSET : lda #0
RCTSET  sta REACT_TEMP
        rts

REACT_START_M = CFG_CLK_H*60 + CFG_CLK_M
REACT_SPAN = 89                         ; 99 - starting temperature (10)
REACT_K = (REACT_SPAN*256 + REACT_START_M DIV 2) DIV REACT_START_M

; =============================================================================
; READ_KEYS
; =============================================================================
READ_KEYS
        lda #0 : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0 : sta KEY_SPC

        ; Joystick port 2 = CIA1 PRA ($DC00), read with no keyboard column
        ; selected (PRA=$FF). Bits active low: 0 up, 1 down, 2 left,
        ; 3 right, 4 fire. Fire (held: JOY_PREV) is merged with space
        ; below, at RKSPCN.
        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRA : sta TMP
        lda TMP : and #$01 : bne RKJ1 : lda #1 : sta KEY_U
RKJ1    lda TMP : and #$02 : bne RKJ2 : lda #1 : sta KEY_D
RKJ2    lda TMP : and #$04 : bne RKJ3 : lda #1 : sta KEY_L
RKJ3    lda TMP : and #$08 : bne RKJ4 : lda #1 : sta KEY_R
RKJ4
        ; W (up): col 1 (PA=$FD), row 1 (PB bit 1, active low)
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$02 : bne RKWN
        lda #1 : sta KEY_U
RKWN
        ; S (down): col 1 (PA=$FD), row 5 (PB bit 5, active low)
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$20 : bne RKSN
        lda #1 : sta KEY_D
RKSN
        ; A (left): col 1 (PA=$FD), row 2 (PB bit 2, active low)
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$04 : bne RKAN
        lda #1 : sta KEY_L
RKAN
        ; D (right): col 2 (PA=$FB), row 2 (PB bit 2, active low)
        lda #$FB : sta CIA1_PRA
        lda CIA1_PRB : and #$04 : bne RKDN
        lda #1 : sta KEY_R
RKDN


        ; F2 = shift + F1 (hard to hit by mistake): the "where am I" popup
        ; with room and position (SETUP_WHERE). F1: col 0 (PA=$FE), row 4;
        ; left shift: col 1 (PA=$FD), row 7; right shift: col 6 (PA=$BF),
        ; row 4. Edge-detected via F2_PREV so holding it doesn't reopen the
        ; popup straight after it closes.
        lda #$FE : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKF2UP
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : beq RKF2DN
        lda #$BF : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKF2UP
RKF2DN  lda F2_PREV : bne RKF2N          ; still held from the last popup
        lda #1 : sta F2_PREV
        jmp SETUP_WHERE                  ; tail call: back to GAME_ALIVE
RKF2UP  lda #0 : sta F2_PREV
RKF2N

        ; Space (search): col 7 (PA=$7F), row 4 (PB bit 4, active low)
        lda #$7F : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKSPCN
        lda #1 : sta KEY_SPC
RKSPCN
        ; Fire = joystick fire or space. FIRE_PREV becomes "held now" (the
        ; search holds it), KEY_SPC "freshly pressed" (terminal, starting a
        ; search, ending a robot link). DRAW_ROOM sets FIRE_PREV=1, so after
        ; any screen change fire must be let go and pressed again.
        lda JOY_PREV : and #$10 : ora KEY_SPC : beq RKFUP
        lda FIRE_PREV : eor #1 : sta KEY_SPC
        lda #1 : sta FIRE_PREV
        bne RKFDONE
RKFUP   sta KEY_SPC : sta FIRE_PREV      ; A = 0
RKFDONE

        ; Check proximity to a terminal zone (TERMZ_* tables) in this room.
        ; Human mode only: robots can't use terminals (the human sprite
        ; still stands in the zone while a robot is driven; the link only
        ; ends when it expires, TICK_LINK).
        lda #0 : sta NEAR_TERM
        lda PLAYER_MODE : bne RKSEARCHCHK
        ldx #0
RKTL    cpx #NUM_TERMZONES : bcs RKSEARCHCHK
        lda TERMZ_ROOM,x : cmp CUR_ROOM : bne RKTN
        lda PLR_X : cmp TERMZ_X1,x : bcc RKTN
        lda TERMZ_X2,x : cmp PLR_X : bcc RKTN
        lda PLR_Y : cmp TERMZ_Y1,x : bcc RKTN
        lda TERMZ_Y2,x : cmp PLR_Y : bcc RKTN
        lda #1 : sta NEAR_TERM
        lda KEY_SPC : beq RKSEARCHCHK
        lda #0 : sta TERM_SEL
        jsr SETUP_TERMINAL
        rts
RKTN    inx : bne RKTL
RKSEARCHCHK
        lda PLAYER_MODE : bne RKPROXY
        jmp SEARCH_TICK                  ; hold fire to search (popup.asm)
RKPROXY ; driving a robot: fire shoots, if it's a shooter (ai: shooter) —
        ; in the direction it faces
        lda KEY_SPC : beq RKPOUT
        ldx PLAYER_MODE : dex
        lda ACT_AI,x : cmp #AI_SHOOTER : bne RKPOUT
        lda ACT_ALIVE,x : cmp #1 : bne RKPOUT
        lda ACT_DIR,x : ldy #1
        jmp FIRE_BOLT
RKPOUT  rts

; =============================================================================
; MOVE_PLAYER — fully table-driven (world.asm): room bounds from ROOM_MAXX/Y,
; doorways from the DOOR_* tables, lasers from the LASER_* tables. A door is
; a rectangle just outside the walkable range; attempting to move into it
; triggers the transition (or the locked popup / win screen).
; Directions are tried in U,D,L,R order; a wall-blocked direction falls
; through to the next pressed one, anything else ends the move.
; Each attempt turns the sprite to face that way (even into a wall); a
; committed step advances the walk frame, and a tick with no step (nothing
; pressed, or every pressed direction walled off) drops back to the rest pose.
; =============================================================================
MOVE_PLAYER
        lda SRCH_TMR : ora PLR_DYING : beq MPNOSRCH   ; searching or sliding
        rts                                           ;  into a laser: no input
MPNOSRCH
        lda MOVE_TMR : beq MOVEGO
        dec MOVE_TMR : rts
MOVEGO  lda #MOVE_PERIOD-1 : sta MOVE_TMR

        lda PLAYER_MODE : beq MOVEHUM
        jmp MOVE_ACTOR
MOVEHUM
        lda KEY_U : beq MPD
        lda #DIR_UP : jsr MPSET : dec NEWY
        jsr TRY_MOVE : bcs MPDONE
MPD     lda KEY_D : beq MPL
        lda #DIR_DOWN : jsr MPSET : inc NEWY
        jsr TRY_MOVE : bcs MPDONE
MPL     lda KEY_L : beq MPR
        lda #DIR_LEFT : jsr MPSET : dec NEWX
        jsr TRY_MOVE : bcs MPDONE
MPR     lda KEY_R : beq MPIDLE
        lda #DIR_RIGHT : jsr MPSET : inc NEWX
        jsr TRY_MOVE : bcs MPDONE
MPIDLE  lda #0 : sta PLR_ANIM        ; no step this tick: rest pose
MPDONE  rts

; MPSET — A = facing for this attempt; NEWX/NEWY = current position
MPSET   sta PLR_DIR
        lda PLR_X : sta NEWX
        lda PLR_Y : sta NEWY
        rts

; ---------------------------------------------------------------------------
; TRY_MOVE — attempt to move the human to NEWX/NEWY. Returns carry set if the
; move was handled (committed, laser death, door taken, popup or win shown);
; carry clear if a plain wall blocked it (caller tries the next direction).
; ---------------------------------------------------------------------------
TRY_MOVE
        ldx CUR_ROOM
        lda NEWX : cmp ROOM_MAXX,x : bcc TMXOK : beq TMXOK
        jmp TRY_DOOR                 ; outside walkable range: door or wall
TMXOK   lda NEWY : cmp ROOM_MAXY,x : bcc TMYOK : beq TMYOK
        jmp TRY_DOOR
TMYOK   lda CUR_ROOM : jsr WALL_AT : bcc TMNOWALL
        clc : rts                    ; wall: blocked (try the next direction)
TMNOWALL
        jsr LASER_AT : bcc TMCOMMIT
        ; stepped into an active laser: take the step, but already dying —
        ; no more input, and UPDATE_SPRITE0 kills the player once the sprite has
        ; glided onto the laser tile (like a driven robot, UPD_DYING)
        lda #1 : sta PLR_DYING
TMCOMMIT
        lda NEWX : sta PLR_X
        lda NEWY : sta PLR_Y
        jsr PLR_STEP_ANIM
        sec : rts

; PLR_STEP_ANIM — a step was taken: alternate walk1/walk2 (rest -> walk1)
PLR_STEP_ANIM
        lda PLR_ANIM : cmp #1 : beq PSA2
        lda #1 : sta PLR_ANIM : rts
PSA2    lda #2 : sta PLR_ANIM : rts

; ---------------------------------------------------------------------------
; TRY_DOOR — NEWX/NEWY is outside the walkable range: scan this room's doors.
; Carry set if a door handled it, clear if it's just a wall.
; ---------------------------------------------------------------------------
TRY_DOOR
        ldx #0
TDL     cpx #NUM_DOORS : bcs TDNONE
        lda DOOR_ROOM,x : cmp CUR_ROOM : bne TDN
        lda NEWX : cmp DOOR_X1,x : bcc TDN
        lda DOOR_X2,x : cmp NEWX : bcc TDN
        lda NEWY : cmp DOOR_Y1,x : bcc TDN
        lda DOOR_Y2,x : cmp NEWY : bcc TDN
        jmp DOOR_ENTER
TDN     inx : bne TDL
TDNONE  clc : rts

; ---------------------------------------------------------------------------
; DOOR_ENTER — X = door index. A keyed door that isn't open yet: without
; the key the locked popup; with it the door opens — its art turns to floor
; (ERASE_DOOR), a green border flash, the key is used up (ITEM_STATE=2) —
; and the player stays put, so the
; opening is seen; the next push goes through. Then win exit or room change.
; ---------------------------------------------------------------------------
DOOR_ENTER
        lda DOOR_KEY,x : beq DENOPEN
        lda DOOR_OPEN,x : bne DENOPEN
        ldy DOOR_KEY,x : dey         ; key is item index + 1
        lda ITEM_STATE,y : cmp #1 : beq DENUNLK   ; carried: open it
        jsr SETUP_DOOR_LOCKED
        sec : rts
DENUNLK lda #2 : sta ITEM_STATE,y    ; the key is used up (leaves the card slot)
        lda #1 : sta DOOR_OPEN,x
        txa : tay : jsr ERASE_DOOR   ; (preserves X)
        lda #GREEN : sta VIC_BRDCOL
        lda #15 : sta BFLASH
        sec : rts
DENOPEN lda DOOR_DEST,x : cmp #$FF : bne DENGO
        jsr SETUP_WIN                ; $FF = mission exit
        sec : rts
DENGO   sta CUR_ROOM
        lda DOOR_AX,x : cmp #$FF : beq DENAY   ; $FF = keep current coord
        sta PLR_X
DENAY   lda DOOR_AY,x : cmp #$FF : beq DENDRW
        sta PLR_Y
DENDRW  jsr PLR_STEP_ANIM            ; walking through the doorway is a step
        jsr DRAW_ROOM
        sec : rts

; =============================================================================
; MOVE_ACTOR — proxy mode: WASD/joystick drive actor PLAYER_MODE-1 instead of
; the human (who stays frozen at the terminal). Bounds come from the actor's
; own room; no doorway checks (robots can't leave their room). Driving into
; an active laser destroys both the laser and the robot (ROBOT_LASER_DEATH).
; =============================================================================
MOVE_ACTOR
        ldx PLAYER_MODE : dex
        lda ACT_ALIVE,x : cmp #1 : beq MAGO
        rts                          ; sliding into a laser: no more input
MAGO    lda KEY_U : beq MAD
        lda #DIR_UP : jsr MASET : dec NEWY
        jsr TRY_ACT : bcs MADONE
MAD     lda KEY_D : beq MAL
        lda #DIR_DOWN : jsr MASET : inc NEWY
        jsr TRY_ACT : bcs MADONE
MAL     lda KEY_L : beq MAR
        lda #DIR_LEFT : jsr MASET : dec NEWX
        jsr TRY_ACT : bcs MADONE
MAR     lda KEY_R : beq MAIDLE
        lda #DIR_RIGHT : jsr MASET : inc NEWX
        jsr TRY_ACT : bcs MADONE
MAIDLE  lda #0 : sta ACT_ANIM,x      ; no step this tick: rest pose
MADONE  rts

; MASET — X = actor, A = facing for this attempt; NEWX/NEWY = its position
MASET   jsr ACT_FACE
        lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        rts

; TRY_ACT — X = actor index. Carry set = handled, clear = blocked by wall.
; The move commits first, then the laser check runs on the new position: a
; hit marks the robot dying (ACT_ALIVE=2) and it glides onto the laser tile
; before ROBOT_LASER_DEATH runs (see UPD_DYING).
TRY_ACT
        ldy ACT_ROOM,x
        lda NEWX : cmp ROOM_MAXX,y : bcc TAXOK : beq TAXOK
        clc : rts
TAXOK   lda NEWY : cmp ROOM_MAXY,y : bcc TAYOK : beq TAYOK
        clc : rts
TAYOK   lda ACT_ROOM,x : jsr WALL_AT : bcc TANOWALL
        clc : rts                    ; wall: blocked
TANOWALL
        lda NEWX : sta ACT_X,x
        lda NEWY : sta ACT_Y,x
        jsr ACT_STEP_ANIM
        jsr LASER_AT : bcc TAOK
        sty PEND_LSR                 ; hit a laser: finish the slide into the
        lda #2 : sta ACT_ALIVE,x     ;  beam first, then die (UPD_DYING)
TAOK    sec : rts

; =============================================================================
; WALL_AT — A = room, NEWX/NEWY = tile (in bounds). Carry set if the tile is
; solid; A != 0 if it's a win target (BOLT_TICK). genworld.py derives
; ROOM_WALLS_n (20 bytes per tile row; bit 0 = solid, bit 1 = target) from
; each tile's 2x2 chars of room art. Preserves X; clobbers A/Y/PTR/TMP.
; =============================================================================
WALL_AT
        tay
        lda ROOM_WALL_LO,y : sta PTR
        lda ROOM_WALL_HI,y : sta PTR+1
        lda NEWY : asl : asl : sta TMP   ; y*4
        asl : asl : adc TMP              ; + y*16 = y*20 (C clear: y <= 10)
        adc NEWX : tay                   ; + x (max 10*20+19 = 219)
        lda (PTR),y : lsr                ; C = solid, A = target
        rts

; =============================================================================
; LASER_AT — carry set if NEWX/NEWY is inside an active laser rectangle of
; the current room; Y = that laser's index. Preserves X.
; =============================================================================
LASER_AT
        ldy #0
LAL     cpy #NUM_LASERS : bcs LANONE
        lda LASER_STATE,y : bne LAN
        lda LASER_ROOM,y : cmp CUR_ROOM : bne LAN
        lda NEWX : cmp LASER_X1,y : bcc LAN
        lda LASER_X2,y : cmp NEWX : bcc LAN
        lda NEWY : cmp LASER_Y1,y : bcc LAN
        lda LASER_Y2,y : cmp NEWY : bcc LAN
        sec : rts
LAN     iny : bne LAL
LANONE  clc : rts

; =============================================================================
; ROBOT_LASER_DEATH — X = actor; the laser index is PEND_LSR. A driven robot
; that steps into an active laser first gets ACT_ALIVE=2 ("dying": no more
; input, no patrol) and keeps gliding; UPD_DYING calls this once its sprite
; has reached the laser tile. The robot is destroyed for good and the laser
; burns out with it, so it no longer hurts the human either, and its chars
; are repainted as floor (ERASE_LASER). Control snaps back to human.
; =============================================================================
PEND_LSR !byte 0                     ; laser a dying robot is sliding into

ROBOT_LASER_DEATH
        ldy PEND_LSR
        lda #0   : sta ACT_ALIVE,x
        lda #1   : sta LASER_STATE,y
        jsr ERASE_LASER              ; beam/emitters vanish from the room art
        jsr SOUND_ZAP_START
        lda #YELLOW : sta VIC_BRDCOL
        lda #15  : sta BFLASH
        lda #0   : sta PLAYER_MODE
        rts

; =============================================================================
; UPDATE_SPRITE0
; =============================================================================
UPDATE_SPRITE0
        lda PLR_DIR : sta TMP
        lda PLR_ANIM : sta TMP2
        ldx #ATYPE_HUMAN : jsr FRAME_PTR
        sta SPRPTR
        lda PLR_X : sta NEWX
        lda PLR_Y : sta NEWY
        lda #GL_FAST_X : sta GL_SX
        lda #GL_FAST_Y : sta GL_SY
        ldx #GL_PLAYER : jsr GLIDE
        lda GL_PXL+GL_PLAYER : sta VIC_SP0X
        lda GL_PXH+GL_PLAYER : bne SPRMSB
        lda VIC_SP_MSB : and #$FE : sta VIC_SP_MSB : jmp SPRDX
SPRMSB  lda VIC_SP_MSB : ora #$01 : sta VIC_SP_MSB
SPRDX
        lda GL_PY+GL_PLAYER : sta VIC_SP0Y

        lda PLR_DYING : beq SPRALIVE     ; walked into a laser: die once the
        lda GL_PXL+GL_PLAYER : cmp GLT_L : bne SPRALIVE   ;  sprite is on it
        lda GL_PXH+GL_PLAYER : cmp GLT_H : bne SPRALIVE   ;  (GLT_* = target
        lda GL_PY+GL_PLAYER  : cmp GLT_Y : bne SPRALIVE   ;  from GLIDE)
        lda #0 : sta PLR_DYING
        jsr PLAYER_DIE
SPRALIVE

        lda BFLASH : beq SPROUT
        dec BFLASH : bne SPROUT
        lda #BLACK : sta VIC_BRDCOL
SPROUT  rts

; =============================================================================
; ASSIGN_SPRITES — map this room's actors onto hardware sprites 1-2. Called
; from DRAW_ROOM, so every room change / room redraw refreshes the mapping.
; Fills SPR_SLOT_ACT (2 bytes: actor index or $FF) and sets each used slot's
; sprite pointer and colour from the actor's type (TYPE_SPRPTR/TYPE_COLOR).
; Dead actors still claim a slot (UPDATE_ROBOT_SPRITES keeps them hidden);
; genworld.py enforces max 2 robots per room, so nothing gets crowded out.
; =============================================================================
ASSIGN_SPRITES
        lda #$FF : sta SPR_SLOT_ACT : sta SPR_SLOT_ACT+1
        ldy #0                       ; next free slot
        ldx #0                       ; actor index
ASGL    cpx #NUM_ACTORS : bcs ASGDONE
        lda ACT_ROOM,x : cmp CUR_ROOM : bne ASGN
        txa : sta SPR_SLOT_ACT,y
        stx TMP
        lda ACT_TYPE,x : tax
        lda TYPE_SPRPTR,x : sta SPRPTR+1,y
        lda TYPE_COLOR,x  : sta VIC_SPCOL1,y
        ldx TMP
        iny : cpy #2 : bcs ASGDONE
ASGN    inx : bne ASGL
ASGDONE rts

; =============================================================================
; UPDATE_ROBOT_SPRITES — position/enable hardware sprites 1-2 from their
; assigned actors (SPR_SLOT_ACT). A slot with no actor, a dead actor, or an
; actor outside the current room is disabled (VIC_SPEN bit cleared) — callers
; that re-enter game state can just set VIC_SPEN=$07 and let this fix it up.
; =============================================================================
SLOT_ORBIT  !byte $02,$04           ; VIC bit for hw sprite 1/2
SLOT_ANDBIT !byte $FD,$FB
SLOT_REGOFF !byte 0,2               ; VIC_SP1X/VIC_SP2X register offset

UPDATE_ROBOT_SPRITES
        ldy #0
        jsr UPD_SLOT
        ldy #1
        ; fall through for slot 1
; UPD_SLOT — Y = slot (0/1). Y survives; X/A/TMP/TMP2/NEWX/NEWY are scratch.
UPD_SLOT
        ldx SPR_SLOT_ACT,y
        cpx #$FF : beq UPDSOFF
        lda ACT_ALIVE,x : beq UPDSOFF
        lda ACT_ROOM,x : cmp CUR_ROOM : beq UPDON
UPDSOFF lda VIC_SPEN : and SLOT_ANDBIT,y : sta VIC_SPEN
        rts
UPDON   ; glide toward its tile: patrol pace, or the player's pace while
        ; driven or rushing (a hunter that has seen the player)
        lda #GL_SLOW_X : sta GL_SX
        lda #GL_SLOW_Y : sta GL_SY
        lda ACT_FAST,x : bne UPDFAST
        txa : clc : adc #1 : cmp PLAYER_MODE : bne UPDSPD
UPDFAST lda #GL_FAST_X : sta GL_SX
        lda #GL_FAST_Y : sta GL_SY
UPDSPD  lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        jsr GL_TARGET
        jsr UPD_DYING : bcs UPDSOFF      ; drawn on the laser tile: destroyed
        jsr GLIDE                        ; (preserves X/Y)
        lda GL_PXL,x : sta NEWX          ; NEWX/NEWY/GLT_H now hold the
        lda GL_PY,x  : sta NEWY          ;  sprite's pixel position
        lda GL_PXH,x : sta GLT_H
        lda ACT_DIR,x : sta TMP
        lda ACT_ANIM,x : sta TMP2
        lda ACT_TYPE,x : tax
        jsr FRAME_PTR                    ; (preserves Y)
        sta SPRPTR+1,y
        lda VIC_SPEN : ora SLOT_ORBIT,y : sta VIC_SPEN
        ldx SLOT_REGOFF,y
        lda NEWX : sta VIC_SP1X,x
        lda GLT_H : bne UPDSMSB
        lda VIC_SP_MSB : and SLOT_ANDBIT,y : sta VIC_SP_MSB
        jmp UPDSY
UPDSMSB lda VIC_SP_MSB : ora SLOT_ORBIT,y : sta VIC_SP_MSB
UPDSY   lda NEWY : sta VIC_SP1Y,x
        rts

; UPD_DYING — X = actor, GLT_* = its tile's pixel position (GL_TARGET),
; checked *before* this frame's GLIDE: if it is dying (ACT_ALIVE=2) and the
; sprite was already drawn on the laser tile last frame, run
; ROBOT_LASER_DEATH and return carry set (hide the sprite).
; Preserves X/Y.
UPD_DYING
        lda ACT_ALIVE,x : cmp #2 : bne UDNO
        lda GL_PXL,x : cmp GLT_L : bne UDNO
        lda GL_PXH,x : cmp GLT_H : bne UDNO
        lda GL_PY,x  : cmp GLT_Y : bne UDNO
        tya : pha
        jsr ROBOT_LASER_DEATH
        pla : tay
        sec : rts
UDNO    clc : rts

; =============================================================================
; Smooth movement. Game logic stays on tiles (PLR_X/Y, ACT_X/Y); each sprite
; has its own pixel position (GL_PXL/GL_PXH/GL_PY, slot = actor index, or
; GL_PLAYER for the human) that GLIDE moves toward its tile's pixel position
; by GL_SX/GL_SY pixels per frame, so a one-tile step (16 x 16 px) is drawn
; as a slide instead of a jump. Speeds are matched to the step periods so a
; glide just finishes as the next step starts: the player (and a driven
; robot) steps every MOVE_PERIOD=8 frames at 2 px per frame; patrolling
; robots step every ROB_PERIOD=16 frames at 1 px per frame. GL_SNAP jumps
; straight to the tile (DRAW_ROOM -> SNAP_ALL: room change, respawn,
; redraw after terminal/map/popup).
; =============================================================================
MOVE_PERIOD = 8                 ; frames per player step
ROB_PERIOD  = 16                ; frames per patrol step
ROB_HALF    = ROB_PERIOD/2      ; frames per rushing step (ACT_FAST)
GL_FAST_X   = 2                 ; 16 px / 8 frames
GL_FAST_Y   = 2                 ; 16 px / 8 frames
GL_SLOW_X   = 1                 ; 16 px / 16 frames
GL_SLOW_Y   = 1                 ; 16 px / 16 frames
GL_PLAYER   = NUM_ACTORS        ; glide slot of the human

GLT_L   !byte 0                 ; GL_TARGET result: pixel X lo/hi, pixel Y
GLT_H   !byte 0
GLT_Y   !byte 0

; GL_TARGET — NEWX/NEWY tile -> GLT_L/GLT_H/GLT_Y. Preserves X/Y.
; Y pixel = tile*16+62: room row 0 is at sprite Y 66, and the sprite is
; lifted 4 px so its feet (sprite line 19) sit on the tile's bottom line.
GL_TARGET
        lda NEWX : jsr TILE_TO_PIXEL_X
        sta GLT_L
        lda #0 : rol : sta GLT_H
        lda NEWY : asl : asl : asl : asl
        clc : adc #62 : sta GLT_Y
        rts

; GL_SNAP — X = glide slot, NEWX/NEWY = tile: jump straight there.
GL_SNAP
        jsr GL_TARGET
        lda GLT_L : sta GL_PXL,x
        lda GLT_H : sta GL_PXH,x
        lda GLT_Y : sta GL_PY,x
        rts

; GLIDE — X = glide slot, NEWX/NEWY = tile, GL_SX/GL_SY = speed: one
; frame's step toward that tile, never overshooting. Preserves X/Y.
GLIDE
        jsr GL_TARGET
        lda GL_PXH,x : cmp GLT_H : bne GLXNE
        lda GL_PXL,x : cmp GLT_L : beq GLY
GLXNE   bcs GLXDEC                       ; C from the deciding compare
        lda GL_PXL,x : clc : adc GL_SX : sta GL_PXL,x   ; moving right
        lda GL_PXH,x : adc #0 : sta GL_PXH,x
        cmp GLT_H : bne GLXC1
        lda GL_PXL,x : cmp GLT_L
GLXC1   bcc GLY : beq GLY                ; not past the target yet
        jmp GLXSET
GLXDEC  lda GL_PXL,x : sec : sbc GL_SX : sta GL_PXL,x   ; moving left
        lda GL_PXH,x : sbc #0 : sta GL_PXH,x
        cmp GLT_H : bne GLXC2
        lda GL_PXL,x : cmp GLT_L
GLXC2   bcs GLY                          ; not past the target yet
GLXSET  lda GLT_L : sta GL_PXL,x         ; overshot: clamp
        lda GLT_H : sta GL_PXH,x
GLY     lda GL_PY,x : cmp GLT_Y : beq GLDONE
        bcs GLYDEC
        adc GL_SY                        ; moving down (C clear)
        cmp GLT_Y : bcc GLYST
        lda GLT_Y : jmp GLYST
GLYDEC  sbc GL_SY                        ; moving up (C set)
        cmp GLT_Y : bcs GLYST
        lda GLT_Y
GLYST   sta GL_PY,x
GLDONE  rts

; SNAP_ALL — every sprite straight to its tile (from DRAW_ROOM).
SNAP_ALL
        lda PLR_X : sta NEWX
        lda PLR_Y : sta NEWY
        ldx #GL_PLAYER : jsr GL_SNAP
        ldx #0
SNAPL   cpx #NUM_ACTORS : bcs SNAPD
        lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        jsr GL_SNAP
        inx : bne SNAPL
SNAPD   rts

; =============================================================================
; TILE_TO_PIXEL_X — A = tile number (0-19). Returns the sprite pixel X low
; byte in A (store to VIC_SPnX) and carry set if the 9-bit value tile*16+20
; exceeds 255, i.e. the sprite's VIC_SP_MSB bit must be set (tiles 15-19).
; The 24 px sprite is centred on the 16 px tile: room column 0 is at sprite
; X 24, minus 4 px overhang on each side. Computed as (tile*8+10)*2 so the
; only overflow is the final shift, which lands straight in carry.
; =============================================================================
TILE_TO_PIXEL_X
        asl : asl : asl                  ; tile*8 (< 256 for tile < 32)
        clc : adc #10                    ; tile*8+10
        asl                              ; *2 = tile*16+20, C = bit 8
        rts

; =============================================================================
; CHECK_SPRITE_HIT — read $D01E once (every frame, to keep the latch clear);
; bit 0 = player (sprite 0) collided with any other enabled sprite. Ignored
; while PLAYER_MODE=1: the human sprite is frozen at the terminal and cannot
; be hurt by patrol robots while the player is instead piloting the splicer.
; =============================================================================
CHECK_SPRITE_HIT
        lda VIC_SPCOLL : sta TMP
        lda PLAYER_MODE : bne SPRHITOK
        lda DEATH_TMR : bne SPRHITOK
        lda TMP : and #$01 : beq SPRHITOK
        jmp PLAYER_DIE                  ; same death as a laser
SPRHITOK rts

; =============================================================================
; TICK_ROBOT — run every actor's patrol AI (shared 20-frame timer). An actor
; is skipped while dead (ACT_ALIVE=0), dying (2: sliding into a laser) or
; player-driven (PLAYER_MODE=index+1).
; Actors in other rooms keep patrolling off-screen, as before.
; =============================================================================
TICK_ROBOT
        lda ROB_TMR : beq TROBOK
        dec ROB_TMR : rts
TROBOK  lda #ROB_HALF-1 : sta ROB_TMR
        lda ROB_PHASE : eor #1 : sta ROB_PHASE
        ldx #0
TROBL   cpx #NUM_ACTORS : bcs TROBD
        lda ACT_ALIVE,x : cmp #1 : bne TROBN   ; dead, or dying in a laser
        txa : clc : adc #1 : cmp PLAYER_MODE : beq TROBN
        lda ACT_FAST,x : bne TROBGO      ; rushing: every half period
        lda ROB_PHASE : bne TROBN        ; normal pace: every other one
TROBGO  jsr ACTOR_THINK
TROBN   inx : bne TROBL
TROBD   rts

; ---------------------------------------------------------------------------
; ACTOR_THINK — X = actor; one step of its AI (ACT_AI, ai: in titan.yaml).
; AI_PATROL just patrols. AI_HUNTER patrols too, but while it can see the
; human (SEES_PLAYER) it rushes at the player at double pace (ACT_FAST=1: steps every
; ROB_HALF frames, glides 2 px/frame). Losing sight drops it back to normal
; pace and it walks back onto its patrol. Speed only changes when a glide
; has finished: a normal-pace robot is only asked on even half periods
; (TICK_ROBOT), and one that loses sight on an odd one waits for the next.
; ---------------------------------------------------------------------------
; AI_SHOOTER: see SHOOTER_THINK.
ACTOR_THINK
        lda ACT_AI,x : cmp #AI_HUNTER : beq ATHUNT
        cmp #AI_SHOOTER : bne ACTOR_PATROL_STEP
        jmp SHOOTER_THINK
ATHUNT  jsr SEES_PLAYER : bcc ATNOSEE
        jmp HUNT_RUSH
ATNOSEE lda ACT_FAST,x : beq ACTOR_PATROL_STEP
        lda #0 : sta ACT_FAST,x          ; lost sight: normal pace again,
        lda ROB_PHASE : beq ACTOR_PATROL_STEP   ;  on the normal beat
        rts

; ---------------------------------------------------------------------------
; ACTOR_PATROL_STEP — X = actor. One step toward the current target waypoint
; (ACT_TGT selects ACT_WX0/WY0 or ACT_WX1/WY1), X axis first, then Y; on
; arrival the target flips, so the actor shuttles between the two waypoints.
; No laser/collision checks — patrol paths are authored not to cross hazards.
; ---------------------------------------------------------------------------
ACTOR_PATROL_STEP
        lda ACT_TGT,x : beq APSW0
        lda ACT_WX1,x : sta NEWX
        lda ACT_WY1,x : sta NEWY
        jmp APSGO
APSW0   lda ACT_WX0,x : sta NEWX
        lda ACT_WY0,x : sta NEWY
APSGO   lda ACT_X,x : cmp NEWX : beq APSY
        bcs APSXL
        inc ACT_X,x : lda #DIR_RIGHT : jmp APSSTEP
APSXL   dec ACT_X,x : lda #DIR_LEFT : jmp APSSTEP
APSY    lda ACT_Y,x : cmp NEWY : beq APSFLIP
        bcs APSYU
        inc ACT_Y,x : lda #DIR_DOWN : jmp APSSTEP
APSYU   dec ACT_Y,x : lda #DIR_UP
APSSTEP jsr ACT_FACE
        jmp ACT_STEP_ANIM
APSFLIP lda ACT_TGT,x : eor #1 : sta ACT_TGT,x
        lda #0 : sta ACT_ANIM,x      ; pause at the waypoint in the rest pose
        rts

; ---------------------------------------------------------------------------
; SEES_PLAYER — X = actor (hunter, shooter). Carry set if it can see the human: human mode (a
; robot link leaves the human standing at the terminal, not hunted), not
; already dying, same room, same tile row, and no wall tile between them on
; that row. Lasers don't block sight (but HUNT_RUSH won't step into one).
; Preserves X; clobbers A/Y/NEWX/NEWY/PTR/TMP.
; ---------------------------------------------------------------------------
SEES_PLAYER
        lda PLAYER_MODE : ora PLR_DYING : bne HSNO
        lda ACT_ROOM,x : cmp CUR_ROOM : bne HSNO
        lda ACT_Y,x : cmp PLR_Y : bne HSNO
        sta NEWY
        lda ACT_X,x : sta NEWX
HSL     lda NEWX : cmp PLR_X : beq HSYES ; reached the player: clear view
        bcc HSR
        dec NEWX : jmp HSW
HSR     inc NEWX
HSW     lda CUR_ROOM : jsr WALL_AT : bcc HSL
HSNO    clc : rts
HSYES   sec : rts

; HUNT_RUSH — X = actor that sees the human (same row): one fast step along
; the row toward the player; the sprite collision does the rest. Stands still (on
; the player already, or the next tile is an active laser).
HUNT_RUSH
        lda #1 : sta ACT_FAST,x
        lda ACT_Y,x : sta NEWY
        lda ACT_X,x : sta NEWX
        cmp PLR_X : beq HRSTOP
        bcc HRR
        dec NEWX : lda #DIR_LEFT : bne HRGO
HRR     inc NEWX : lda #DIR_RIGHT
HRGO    jsr ACT_FACE                     ; turn to face the player even if blocked
        jsr LASER_AT : bcs HRSTOP        ; never charge into a beam
        lda NEWX : sta ACT_X,x
        jmp ACT_STEP_ANIM
HRSTOP  lda #0 : sta ACT_ANIM,x
        rts

; ---------------------------------------------------------------------------
; SHOOTER_THINK — X = actor with AI_SHOOTER, at normal pace. Patrols; while it
; sees the player (SEES_PLAYER: same row, no wall between) it stops, turns to
; face them and fires a bolt along the row, unless one is already in flight
; (there is only one bolt, BOLT_*; BOLT_TICK flies it).
; ---------------------------------------------------------------------------
SHOOTER_THINK
        jsr SEES_PLAYER : bcs STSEE
        jmp ACTOR_PATROL_STEP
STSEE   lda #0 : sta ACT_ANIM,x          ; stand and aim
        lda ACT_X,x : cmp PLR_X : beq STOUT   ; same tile: no direction
        lda #0 : rol : sta TMP           ; C = player to the left -> 1
        lda #DIR_RIGHT
        ldy TMP : beq STFACE
        lda #DIR_LEFT
STFACE  jsr ACT_FACE
        ldy #0                           ; the AI's bolt (can't win the game)
        jmp FIRE_BOLT
STOUT   rts

; FIRE_BOLT — X = actor, A = direction (DIR_*), Y = 1 if a player-driven
; robot fires (BOLT_PLR). Launches the bolt from the actor's tile centre,
; unless one is already in flight. Preserves X.
FIRE_BOLT
        pha
        lda BOLT_ON : bne FBBUSY
        pla : sta BOLT_DIR
        sty BOLT_PLR
        lda #1 : sta BOLT_ON
        lda ACT_Y,x : asl : asl : asl : asl : ora #8 : sta BOLT_Y
        lda #0 : sta BOLT_XH
        lda ACT_X,x : asl : asl : asl : asl   ; only the last asl can carry
        rol BOLT_XH : ora #8 : sta BOLT_XL
        rts
FBBUSY  pla
        rts

; ---------------------------------------------------------------------------
; BOLT_TICK — every game frame: fly the bolt BOLT_SPEED px in BOLT_DIR (any
; of the 4 directions; BOLT_XL/XH, BOLT_Y = its centre in room pixels) and
; show it on hw sprite 3 (bolt_1/bolt_2 alternating every 2 frames). It
; vanishes when its centre's tile is a wall or off the room. It passes robots
; and lasers; hitting the player is the ordinary sprite collision
; (CHECK_SPRITE_HIT, bit 0). A bolt fired by a player-driven robot
; (BOLT_PLR) that enters a win-target tile (art.win_tiles — the missile
; room's power cell) wins the game. DRAW_ROOM clears BOLT_ON (room change,
; respawn, redraw after terminal/map/popup).
; ---------------------------------------------------------------------------
BOLT_SPEED = 3                          ; px per frame (player: 2)

BOLT_TICK
        lda BOLT_ON : bne BTGO
        jmp BTOFF
BTGO    ldx BOLT_DIR
        cpx #DIR_RIGHT : bne BTNR
        lda BOLT_XL : clc : adc #BOLT_SPEED : sta BOLT_XL
        bcc BTMOVED : inc BOLT_XH : bne BTMOVED
BTNR    cpx #DIR_LEFT : bne BTNL
        lda BOLT_XL : sec : sbc #BOLT_SPEED : sta BOLT_XL
        bcs BTMOVED : dec BOLT_XH : bpl BTMOVED
        jmp BTKILL                       ; past the left edge
BTNL    cpx #DIR_DOWN : bne BTUP
        lda BOLT_Y : clc : adc #BOLT_SPEED : sta BOLT_Y
        jmp BTMOVED                      ; (bottom edge: the tile test)
BTUP    lda BOLT_Y : sec : sbc #BOLT_SPEED : sta BOLT_Y
        bcc BTKILL                       ; past the top edge
BTMOVED lda BOLT_XH : lsr                ; tile = X/16 (C = bit 8)
        lda BOLT_XL : ror : lsr : lsr : lsr
        cmp #20 : bcs BTKILL             ; past the right edge (tile 20)
        sta NEWX
        lda BOLT_Y : lsr : lsr : lsr : lsr
        cmp #11 : bcs BTKILL             ; past the bottom edge (tile 11)
        sta NEWY
        lda CUR_ROOM : jsr WALL_AT : bcs BTKILL
        and BOLT_PLR : beq BTSHOW        ; a win target, hit by the player?
        lda #0 : sta BOLT_ON
        lda VIC_SPEN : and #$F7 : sta VIC_SPEN
        jsr SOUND_ZAP_START
        jmp SETUP_WIN                    ; the power cell is hit: mission won
BTSHOW  lda BOLT_XL : clc : adc #12 : sta VIC_SP3X   ; sprite X = centre+12
        lda BOLT_XH : adc #0 : beq BTMSB0
        lda VIC_SP_MSB : ora #$08 : bne BTMSB
BTMSB0  lda VIC_SP_MSB : and #$F7
BTMSB   sta VIC_SP_MSB
        lda BOLT_Y : clc : adc #54 : sta VIC_SP3Y    ; = a robot's sprite Y on that row
        lda ANIM_CNT : lsr : and #1 : clc : adc #SPRP_BOLT : sta SPRPTR+3
        lda VIC_SPEN : ora #$08 : sta VIC_SPEN
        rts
BTKILL  lda #0 : sta BOLT_ON
BTOFF   lda VIC_SPEN : and #$F7 : sta VIC_SPEN
        rts

; ---------------------------------------------------------------------------
; ACT_FACE — X = actor, A = DIR_*. Turns the actor to face that way, unless
; its type has no frames for it (DIR < TYPE_DIR0: a left/right-only type
; keeps its last horizontal facing while moving up/down). Preserves X/A;
; clobbers Y.
; ---------------------------------------------------------------------------
ACT_FACE
        ldy ACT_TYPE,x
        cmp TYPE_DIR0,y : bcc AFNO
        sta ACT_DIR,x
AFNO    rts

; ACT_STEP_ANIM — X = actor took a step: alternate walk1/walk2 (rest -> walk1)
ACT_STEP_ANIM
        lda ACT_ANIM,x : cmp #1 : beq ASA2
        lda #1 : sta ACT_ANIM,x : rts
ASA2    lda #2 : sta ACT_ANIM,x : rts

; ---------------------------------------------------------------------------
; FRAME_PTR — X = actor type, TMP = facing (DIR_*), TMP2 = walk frame (0-2).
; Returns A = sprite pointer for that frame:
;   TYPE_SPRPTR + (facing - TYPE_DIR0)*3 + frame
; A "hover" type (TYPE_ANIM=1) ignores TMP2 and loops hover/move1/hover/
; move2 off ANIM_CNT instead (8 frames per pose), so it is always moving.
; Preserves Y; clobbers TMP/TMP2.
; ---------------------------------------------------------------------------
FRAME_PTR
        lda TYPE_ANIM,x : beq FPWALK
        lda ANIM_CNT
        lsr : lsr : lsr : lsr        ; C = bit 3 (odd pose), A = cnt>>4
        bcc FPHREST
        and #1 : adc #0              ; C=1: A = bit 4 + 1 -> move1 / move2
        sta TMP2 : jmp FPWALK
FPHREST lda #0 : sta TMP2            ; even pose: hover
FPWALK  lda TMP : sec : sbc TYPE_DIR0,x : sta TMP   ; facing group 0-3
        asl : adc TMP                ; *3 (C clear: group <= 3)
        adc TMP2
        clc : adc TYPE_SPRPTR,x
        rts

; =============================================================================
; DRAW_ROOM — draws CUR_ROOM to screen rows 2-23
; =============================================================================
DRAW_ROOM
        lda #0 : sta SRCH_TMR : sta SRCH_ST ; the redraw ends any search (and
        sta BOLT_ON                      ;  any bolt in flight)
        lda #1 : sta FIRE_PREV           ;  its small popup); want a new press
        jsr DRMSETPTR
        lda #<(SCRN+80) : sta PTR2 : lda #>(SCRN+80) : sta PTR2+1
        ldx #3 : ldy #0
DRMPG   lda (PTR),y : sta (PTR2),y
        iny : bne DRMPG
        inc PTR+1 : inc PTR2+1
        dex : bne DRMPG
        ldy #0
DRMTAIL lda (PTR),y : sta (PTR2),y
        iny : cpy #112 : bcc DRMTAIL

        jsr DRMSETPTR
        lda #<(CRAM+80) : sta PTR2 : lda #>(CRAM+80) : sta PTR2+1
        ldx #3 : ldy #0
DRMCPG  jsr COL_BYTE : iny : bne DRMCPG
        inc PTR+1 : inc PTR2+1
        dex : bne DRMCPG
        ldy #0
DRMCTAIL jsr COL_BYTE : iny : cpy #112 : bcc DRMCTAIL

        ; the map data always has every laser drawn in: erase the ones in
        ; this room that are already destroyed
        ldy #0
DRMLSR  cpy #NUM_LASERS : bcs DRMLSRD
        lda LASER_STATE,y : beq DRMLSRN
        lda LASER_ROOM,y : cmp CUR_ROOM : bne DRMLSRN
        tya : pha
        jsr ERASE_LASER
        pla : tay
DRMLSRN iny : bne DRMLSR
DRMLSRD
        ldy #0                       ; ... and the doors already opened
DRMDOOR cpy #NUM_DOORS : bcs DRMDOORD
        lda DOOR_OPEN,y : beq DRMDOORN
        lda DOOR_ROOM,y : cmp CUR_ROOM : bne DRMDOORN
        tya : pha
        jsr ERASE_DOOR
        pla : tay
DRMDOORN iny : bne DRMDOOR
DRMDOORD
        jsr SNAP_ALL                 ; no gliding across a room change
        jmp ASSIGN_SPRITES           ; room changed: remap actors -> sprites

; ---------------------------------------------------------------------------
; ERASE_LASER — Y = laser index. Repaints the laser's beam/emitter chars on
; screen (+ their colour RAM from TILE_COLORS) using the patch list
; genworld.py computed from the room art (LASER_ART_n: map offset lo/hi +
; new screen code per entry, $ff hi byte ends it). ERASE_DOOR (Y = door
; index, DOOR_ART_n) does the same for an opened door's art. Only call them
; while that room is on screen. Preserve X; clobber A/Y/PTR/PTR2/TMP.
; ---------------------------------------------------------------------------
ERASE_DOOR
        lda DOOR_ART_LO,y : sta PTR
        lda DOOR_ART_HI,y : jmp ERASE_ART
ERASE_LASER
        lda LASER_ART_LO,y : sta PTR
        lda LASER_ART_HI,y
ERASE_ART
        sta PTR+1
        txa : pha
        ldy #0
ELSL    lda (PTR),y : clc : adc #<(SCRN+80) : sta PTR2   ; map offset -> screen
        iny : lda (PTR),y : bmi ELSDONE                  ; ($ff = end)
        adc #>(SCRN+80) : sta PTR2+1                     ; (C from the low add)
        iny : lda (PTR),y                                ; new screen code
        iny : sty TMP
        ldy #0 : sta (PTR2),y
        tax : lda TILE_COLORS,x : tax
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1 ; same cell in colour RAM
        txa : sta (PTR2),y
        ldy TMP : jmp ELSL
ELSDONE pla : tax
        rts

DRMSETPTR
        ldx CUR_ROOM
        lda ROOM_MAP_LO,x : sta PTR
        lda ROOM_MAP_HI,x : sta PTR+1
        rts

; COL_BYTE — colour RAM byte is looked up from TILE_COLORS, indexed by the
; screen code of the tile being drawn (see src/charset.asm).
; X is the caller's page counter (DRMCPG) and must survive this call.
COL_BYTE
        txa : pha
        lda (PTR),y
        tax
        lda TILE_COLORS,x
        sta (PTR2),y
        pla : tax
        rts

; =============================================================================
; DRAW_STATUS
; =============================================================================
DRAW_STATUS
        ldx #39                          ; template generated from titan.yaml
DSTL    lda STAT_TMPL,x : jsr PET2SCREEN : sta SCRN+960,x
        lda #DGRAY : sta CRAM+960,x
        dex : bpl DSTL

        ; security code counts: one digit each, 4 columns apart
        ldx #0 : ldy #STAT_CNT_COL
DSTCL   cpx #NUM_CODES : bcs DSTCD
        lda CODE_CNT,x : clc : adc #CH_0 : sta SCRN+960,y
        lda #YELLOW : sta CRAM+960,y
        iny : iny : iny : iny
        inx : bne DSTCL
DSTCD
        ; card: label of the first carried item (not used up, ITEM_STATE=1)
        ; that isn't a security code
        ldx #0
DSTIL   cpx #NUM_ITEMS : bcs DSTOUT
        lda ITEM_STATE,x : cmp #1 : bne DSTIN
        lda ITEM_CODE,x : beq DSTIF
DSTIN   inx : bne DSTIL
DSTIF   lda ITEM_LABEL_LO,x : sta PTR
        lda ITEM_LABEL_HI,x : sta PTR+1
        ldy #11
DSTLL   lda (PTR),y : jsr PET2SCREEN : sta SCRN+960+STAT_LBL_COL,y
        lda #LTRED : sta CRAM+960+STAT_LBL_COL,y
        dey : bpl DSTLL
DSTOUT  rts

; =============================================================================
; SID SOUND EFFECTS — voice 1, one effect at a time. While SND_TMR > 0,
; RASTER_IRQ calls SOUND_TICK instead of the music player (in every game
; state, so an effect can't freeze if the state changes mid-sound — e.g.
; Space straight into the terminal right after the splicer burns out).
; SOUND_TICK runs inside the IRQ: it may only touch A (the KERNAL IRQ
; entry/exit saves and restores A/X/Y) and SND_* — never TMP/PTR etc.
;   The laser "bzzzt" (the only effect; used for every death and when a
;   driven robot burns out a laser): a low raspy pulse buzz alternating
;   every frame with a noise crackle, a one-frame gate drop every 8 frames
;   for the stutter, fading out over the last 15 frames
; =============================================================================
ZAP_LEN   = 40                  ; frames; also the laser-death pause

SOUND_ZAP_START
        lda #ZAP_LEN : sta SND_TMR

        lda #$00   : sta $D405      ; attack=0, decay=0
        lda #$F0   : sta $D406      ; sustain=15, release=0
        lda #$0F   : sta $D418      ; master volume full
        lda #$00   : sta $D402      ; pulse width $0200 (12.5%): thin and
        lda #$02   : sta $D403      ;  harmonic-rich, i.e. raspy

        lda #$00   : sta $D400      ; $0480 ≈ 68Hz — mains-hum territory
        lda #$04   : sta $D401
        lda #$41   : sta $D404      ; pulse + gate on
        rts

SOUND_TICK
        lda SND_TMR
        beq SNDOUT

        dec SND_TMR
        bne ZAP_TICK

SNDOFF  lda #$20 : sta $D404
        lda #$0F : sta $D418
SNDOUT  rts

ZAP_TICK
        lda SND_TMR : cmp #16 : bcs ZTWAVE
        sta $D418               ; fade: volume = frames left (15..1)
ZTWAVE  lda SND_TMR : and #7 : cmp #3 : beq ZTGAP
        lda SND_TMR : lsr : bcc ZTBUZZ
        ; odd frame: noise crackle, pitch jittered ($20xx-$2Fxx)
        lda LFSR_ST : eor SND_TMR : and #$0F : ora #$20 : sta $D401
        lda #$81 : sta $D404    ; noise + gate
        rts
ZTBUZZ  ; even frame: the buzz, ~60-90Hz with random fine jitter
        lda LFSR_ST : eor SND_TMR : sta $D400
        and #$01 : ora #$04 : sta $D401
        lda #$41 : sta $D404    ; pulse + gate
        rts
ZTGAP   lda #$40 : sta $D404    ; gate off for one frame: the stutter
        rts
