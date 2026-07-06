; =============================================================================
; GAME STATE (GAME_STATE = 1)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_GAME — called each frame in state 1
; ---------------------------------------------------------------------------
DO_GAME
        jsr SOUND_TICK          ; always tick sound, even during death wait

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
        jsr TICK_REACTOR
        jsr TICK_ROBOT
        jsr READ_KEYS
        jsr MOVE_PLAYER
        lda GAME_STATE : cmp #4 : bcs GAME_TICK_DONE  ; win/map triggered this frame
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
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
SGITEMD jmp RESET_ROUND

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
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL

        lda #START_ROOM : sta CUR_ROOM
        lda ROOM_PSX+START_ROOM : sta PLR_X
        lda ROOM_PSY+START_ROOM : sta PLR_Y
        lda #23  : sta REACT_TEMP
        lda #0   : sta REACT_CNT
        lda #0   : sta REACT_JIT
        lda #$A3 : sta LFSR_ST
        lda #0   : sta MOVE_TMR
        lda #0   : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0   : sta DEATH_TMR
        lda #0   : sta BFLASH
        lda #0   : sta SND_TMR
        lda #0   : sta PLAYER_MODE

        ; all actors back at their start positions, alive, heading for
        ; patrol waypoint 1; all lasers back on
        ldx #0
RSRACT  cpx #NUM_ACTORS : bcs RSRACTD
        lda ACT_SX,x : sta ACT_X,x
        lda ACT_SY,x : sta ACT_Y,x
        lda #1 : sta ACT_TGT,x
        lda #1 : sta ACT_ALIVE,x
        inx : bne RSRACT
RSRACTD
        ldx #0
RSRLSR  cpx #NUM_LASERS : bcs RSRLSRD
        lda #0 : sta LASER_STATE,x
        inx : bne RSRLSR
RSRLSRD
        lda #20  : sta ROB_TMR

        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1
        lda #$FE   : sta SPRPTR+2
        jsr DRAW_HUD_STATIC
        jsr DRAW_ROOM

        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
        rts

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
        !pet "00:00:00 human reactor:[        ]  0%   "

; =============================================================================
; DRAW_HUD_DYNAMIC
; =============================================================================
DRAW_HUD_DYNAMIC
        lda CLK_H : jsr DEC2
        lda TMP : sta SCRN+0 : lda TMP2 : sta SCRN+1
        lda #CH_COLN : sta SCRN+2
        lda CLK_M : jsr DEC2
        lda TMP : sta SCRN+3 : lda TMP2 : sta SCRN+4
        lda #CH_COLN : sta SCRN+5
        lda CLK_S : jsr DEC2
        lda TMP : sta SCRN+6 : lda TMP2 : sta SCRN+7

        lda #WHITE
        ldx CLK_H : bne HUDCC
        ldx CLK_M : cpx #10 : bcs HUDCC
        lda #LTRED
HUDCC   ldx #7
HUDCCL  sta CRAM,x : dex : bpl HUDCCL

        lda PLAYER_MODE : bne HUDMLR
        ldx #4
HUDML   lda LMODE_H,x : jsr PET2SCREEN : sta SCRN+9,x
        lda #CYAN : sta CRAM+9,x
        dex
        bpl HUDML
        jmp HUDMLDONE
HUDMLR  ldx #4
HUDML2  lda LMODE_R,x : jsr PET2SCREEN : sta SCRN+9,x
        lda #GREEN : sta CRAM+9,x
        dex
        bpl HUDML2
HUDMLDONE

        lda REACT_TEMP
        cmp #40 : bcc HUDBG
        cmp #70 : bcc HUDBY
        lda #LTRED  : !byte $2C
HUDBG   lda #LTGREEN : !byte $2C
HUDBY   lda #YELLOW
        sta TMP2

        ldy #7
HUDBCLR lda #CH_SPC : sta SCRN+24,y
        lda #DGRAY  : sta CRAM+24,y
        dey
        bpl HUDBCLR

        lda REACT_TEMP : lsr : lsr : lsr : lsr
        tax
        beq HUDBD
        ldy #0
HUDBF   lda #CH_EQ : sta SCRN+24,y
        lda TMP2 : sta CRAM+24,y
        iny : dex : bne HUDBF
HUDBD
        lda REACT_TEMP : jsr DEC3
        lda DEC3BUF+0 : sta SCRN+33
        lda DEC3BUF+1 : sta SCRN+34
        lda DEC3BUF+2 : sta SCRN+35
        lda TMP2 : sta CRAM+33 : sta CRAM+34 : sta CRAM+35
        rts

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
; DEC3 — A (0-99) → 3 chars in DEC3BUF (space-padded left)
; =============================================================================
DEC3BUF !byte 0,0,0

DEC3
        jsr DEC2
        lda TMP : cmp #CH_0 : bne DEC3T
        lda #CH_SPC : sta DEC3BUF+0 : sta DEC3BUF+1
        lda TMP2 : sta DEC3BUF+2
        rts
DEC3T   lda #CH_SPC : sta DEC3BUF+0
        lda TMP : sta DEC3BUF+1
        lda TMP2 : sta DEC3BUF+2
        rts

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
        lda LFSR_ST : asl : bcc RCTNFB : eor #$B8
RCTNFB  sta LFSR_ST
        inc REACT_JIT
        lda REACT_JIT : and #$07 : bne RCTDR
        lda LFSR_ST : and #$01 : beq RCTJDN
        lda REACT_TEMP : cmp #99 : bcs RCTDR
        inc REACT_TEMP : bne RCTDR
RCTJDN  lda REACT_TEMP : beq RCTDR : dec REACT_TEMP
RCTDR   inc REACT_CNT
        lda REACT_CNT : cmp #180 : bcc RCTOUT
        lda #0 : sta REACT_CNT
        lda REACT_TEMP : cmp #99 : bcs RCTOUT
        inc REACT_TEMP
RCTOUT  rts

; =============================================================================
; READ_KEYS
; =============================================================================
READ_KEYS
        lda #0 : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0 : sta KEY_RET : sta KEY_ESC : sta KEY_MAP
        lda #0 : sta KEY_X
        lda #0 : sta KEY_SPC

        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRB : sta TMP
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

        ; Return: col 1 (PA=$FD), row 1 (PB bit 1, active low)
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$02 : bne RKRETN
        lda #1 : sta KEY_RET
RKRETN

        ; F7: col 7 (PA=$7F), row 4 (PB bit 3, active low)
        lda #$7F : sta CIA1_PRA
        lda CIA1_PRB : and #$08 : bne RKESCN
        lda #1 : sta KEY_ESC
RKESCN

        ; M key (map): col 4 (PA=$EF), row 4 (PB bit 4, active low)
        lda #$EF : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKMN
        lda #1 : sta KEY_MAP
RKMN

        ; X key (exit robot proxy mode): col 2 (PA=$FB), row 7 (PB bit 7, active low)
        lda #$FB : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : bne RKXN
        lda #1 : sta KEY_X
RKXN

        ; Space (search): col 7 (PA=$7F), row 4 (PB bit 4, active low)
        lda #$7F : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKSPCN
        lda #1 : sta KEY_SPC
RKSPCN

        ; Check proximity to a terminal zone (TERMZ_* tables) in this room.
        ; Human mode only: while proxying a robot the human sprite still
        ; stands in the zone, and space must not bounce back into the
        ; terminal (the X key / logoff are the ways out of proxy mode).
        lda #0 : sta NEAR_TERM
        lda PLAYER_MODE : bne RKMAPCHK
        ldx #0
RKTL    cpx #NUM_TERMZONES : bcs RKMAPCHK
        lda TERMZ_ROOM,x : cmp CUR_ROOM : bne RKTN
        lda PLR_X : cmp TERMZ_X1,x : bcc RKTN
        lda TERMZ_X2,x : cmp PLR_X : bcc RKTN
        lda PLR_Y : cmp TERMZ_Y1,x : bcc RKTN
        lda TERMZ_Y2,x : cmp PLR_Y : bcc RKTN
        lda #1 : sta NEAR_TERM
        lda KEY_SPC : beq RKMAPCHK
        jsr SETUP_TERMINAL
        rts
RKTN    inx : bne RKTL
RKMAPCHK
        lda KEY_MAP : beq RKSEARCHCHK
        jsr SETUP_MAP
        rts
RKSEARCHCHK
        ; Search (space): human mode only — a player-driven robot can't use
        ; equipment or search. Looks for a still-hidden item at the player's
        ; exact tile in this room (ITEM_* tables).
        lda KEY_SPC : beq RKXCHK
        lda PLAYER_MODE : bne RKXCHK
        ldx #0
RKSL    cpx #NUM_ITEMS : bcs RKXCHK
        lda ITEM_STATE,x : bne RKSRN          ; already found/used
        lda ITEM_ROOM,x : cmp CUR_ROOM : bne RKSRN
        lda ITEM_X,x : cmp PLR_X : bne RKSRN
        lda ITEM_Y,x : cmp PLR_Y : bne RKSRN
        jsr SETUP_SEARCH                     ; X = item index
        rts
RKSRN   inx : bne RKSL
RKXCHK
        lda PLAYER_MODE : beq RKDONE
        lda KEY_X : beq RKDONE
        lda #0 : sta PLAYER_MODE
RKDONE  rts

; =============================================================================
; MOVE_PLAYER — fully table-driven (world.asm): room bounds from ROOM_MAXX/Y,
; doorways from the DOOR_* tables, lasers from the LASER_* tables. A door is
; a rectangle just outside the walkable range; attempting to move into it
; triggers the transition (or the locked popup / win screen).
; Directions are tried in U,D,L,R order; a wall-blocked direction falls
; through to the next pressed one, anything else ends the move.
; =============================================================================
MOVE_PLAYER
        lda MOVE_TMR : beq MOVEGO
        dec MOVE_TMR : rts
MOVEGO  lda #8 : sta MOVE_TMR

        lda PLAYER_MODE : beq MOVEHUM
        jmp MOVE_ACTOR
MOVEHUM
        lda KEY_U : beq MPD
        jsr MPSET : dec NEWY
        jsr TRY_MOVE : bcs MPDONE
MPD     lda KEY_D : beq MPL
        jsr MPSET : inc NEWY
        jsr TRY_MOVE : bcs MPDONE
MPL     lda KEY_L : beq MPR
        jsr MPSET : dec NEWX
        jsr TRY_MOVE : bcs MPDONE
MPR     lda KEY_R : beq MPDONE
        jsr MPSET : inc NEWX
        jsr TRY_MOVE
MPDONE  rts

MPSET   lda PLR_X : sta NEWX
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
TMYOK   jsr LASER_AT : bcc TMCOMMIT
        ; stepped into an active laser — death, move not committed
        lda #RED  : sta VIC_BRDCOL
        lda #100  : sta DEATH_TMR
        jsr SOUND_DEATH_START
        sec : rts
TMCOMMIT
        lda NEWX : sta PLR_X
        lda NEWY : sta PLR_Y
        sec : rts

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
; DOOR_ENTER — X = door index. Locked check, then win exit or room change.
; ---------------------------------------------------------------------------
DOOR_ENTER
        lda DOOR_KEY,x : beq DENOPEN
        tay : dey                    ; key is item index + 1
        lda ITEM_STATE,y : bne DENOPEN   ; carried or used: unlocked
        jsr SETUP_DOOR_LOCKED
        sec : rts
DENOPEN lda DOOR_DEST,x : cmp #$FF : bne DENGO
        jsr SETUP_WIN                ; $FF = mission exit
        sec : rts
DENGO   sta CUR_ROOM
        lda DOOR_AX,x : cmp #$FF : beq DENAY   ; $FF = keep current coord
        sta PLR_X
DENAY   lda DOOR_AY,x : cmp #$FF : beq DENDRW
        sta PLR_Y
DENDRW  jsr DRAW_ROOM
        sec : rts

; =============================================================================
; MOVE_ACTOR — proxy mode: WASD/joystick drive actor PLAYER_MODE-1 instead of
; the human (who stays frozen at the terminal). Bounds come from the actor's
; own room; no doorway checks (robots can't leave their room). Driving into
; an active laser destroys both the laser and the robot (ROBOT_LASER_DEATH).
; =============================================================================
MOVE_ACTOR
        ldx PLAYER_MODE : dex
        lda KEY_U : beq MAD
        jsr MASET : dec NEWY
        jsr TRY_ACT : bcs MADONE
MAD     lda KEY_D : beq MAL
        jsr MASET : inc NEWY
        jsr TRY_ACT : bcs MADONE
MAL     lda KEY_L : beq MAR
        jsr MASET : dec NEWX
        jsr TRY_ACT : bcs MADONE
MAR     lda KEY_R : beq MADONE
        jsr MASET : inc NEWX
        jsr TRY_ACT
MADONE  rts

MASET   lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        rts

; TRY_ACT — X = actor index. Carry set = handled, clear = blocked by wall.
; The move commits first, then the laser check runs on the new position (the
; robot lands on the laser tile as it dies), matching the old splicer code.
TRY_ACT
        ldy ACT_ROOM,x
        lda NEWX : cmp ROOM_MAXX,y : bcc TAXOK : beq TAXOK
        clc : rts
TAXOK   lda NEWY : cmp ROOM_MAXY,y : bcc TAYOK : beq TAYOK
        clc : rts
TAYOK   lda NEWX : sta ACT_X,x
        lda NEWY : sta ACT_Y,x
        jsr LASER_AT : bcc TAOK
        jsr ROBOT_LASER_DEATH
TAOK    sec : rts

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
; ROBOT_LASER_DEATH — X = actor, Y = laser (from LASER_AT). The robot is
; destroyed for good and the laser burns out with it, so it no longer hurts
; the human either. Control snaps back to human immediately.
; =============================================================================
ROBOT_LASER_DEATH
        lda #0   : sta ACT_ALIVE,x
        lda #1   : sta LASER_STATE,y
        lda #YELLOW : sta VIC_BRDCOL
        lda #15  : sta BFLASH
        lda #0   : sta PLAYER_MODE
        rts

; =============================================================================
; UPDATE_SPRITE0
; =============================================================================
UPDATE_SPRITE0
        lda PLR_X : jsr TILE_TO_PIXEL_X
        sta VIC_SP0X
        bcs SPRMSB
        lda VIC_SP_MSB : and #$FE : sta VIC_SP_MSB : bcc SPRDX
SPRMSB  lda VIC_SP_MSB : ora #$01 : sta VIC_SP_MSB
SPRDX
        lda PLR_Y : asl : asl : asl : asl
        clc : adc #66 : sta VIC_SP0Y

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
        lda ACT_ROOM,x : cmp CUR_ROOM : bne UPDSOFF
        lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        lda VIC_SPEN : ora SLOT_ORBIT,y : sta VIC_SPEN
        lda NEWX : jsr TILE_TO_PIXEL_X   ; (preserves Y, clobbers TMP/TMP2)
        ldx SLOT_REGOFF,y
        sta VIC_SP1X,x
        bcs UPDSMSB
        lda VIC_SP_MSB : and SLOT_ANDBIT,y : sta VIC_SP_MSB
        jmp UPDSY
UPDSMSB lda VIC_SP_MSB : ora SLOT_ORBIT,y : sta VIC_SP_MSB
UPDSY   lda NEWY : asl : asl : asl : asl
        clc : adc #66 : sta VIC_SP1Y,x
        rts
UPDSOFF lda VIC_SPEN : and SLOT_ANDBIT,y : sta VIC_SPEN
        rts

; =============================================================================
; TILE_TO_PIXEL_X — A=tile number. Returns pixel X low byte in A (store to
; VIC_SPnX) and carry set if the true 9-bit value (tile*24+28) exceeds 255,
; i.e. the sprite's extended/MSB X bit must be set. Shared by all three
; UPDATE_SPRITE0/1/2 so any sprite can reach tiles that push X past 255.
;
; Computed as two 8-bit adds (tile*16 + tile*8, then +28); a plain "bcs"
; after just the final add would miss overflow that happens on the *first*
; add instead (true for any tile >= 11, where tile*24 alone already exceeds
; 255) — see the "Extended (9-bit) sprite X" gotcha in CLAUDE.md. TMP/TMP2
; are scratch.
; =============================================================================
TILE_TO_PIXEL_X
        sta TMP                          ; TMP = tile
        asl : asl : asl : asl : sta TMP2 ; TMP2 = tile*16
        lda TMP : asl : asl : asl        ; A = tile*8
        clc : adc TMP2                   ; A = tile*24 (may overflow)
        sta TMP                          ; TMP = low byte so far
        lda #0 : adc #0 : sta TMP2       ; TMP2 = overflow bit from that add (0/1)
        lda TMP : clc : adc #28          ; add baseline offset (may overflow again)
        sta TMP                          ; TMP = final pixel-X low byte
        lda TMP2 : adc #0                ; fold in any 2nd-add overflow (0/1 — the
                                          ; two adds never both overflow for tile 0-12)
        cmp #1                           ; carry set iff total overflow occurred
        lda TMP                          ; A = final low byte (LDA doesn't touch carry)
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
        lda #RED : sta VIC_BRDCOL
        lda #100 : sta DEATH_TMR
        jsr SOUND_DEATH_START
SPRHITOK rts

; =============================================================================
; TICK_ROBOT — run every actor's patrol AI (shared 20-frame timer). An actor
; is skipped while dead (ACT_ALIVE=0) or player-driven (PLAYER_MODE=index+1).
; Actors in other rooms keep patrolling off-screen, as before.
; =============================================================================
TICK_ROBOT
        lda ROB_TMR : beq TROBOK
        dec ROB_TMR : rts
TROBOK  lda #20 : sta ROB_TMR
        ldx #0
TROBL   cpx #NUM_ACTORS : bcs TROBD
        lda ACT_ALIVE,x : beq TROBN
        txa : clc : adc #1 : cmp PLAYER_MODE : beq TROBN
        jsr ACTOR_PATROL_STEP
TROBN   inx : bne TROBL
TROBD   rts

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
        inc ACT_X,x : rts
APSXL   dec ACT_X,x : rts
APSY    lda ACT_Y,x : cmp NEWY : beq APSFLIP
        bcs APSYU
        inc ACT_Y,x : rts
APSYU   dec ACT_Y,x : rts
APSFLIP lda ACT_TGT,x : eor #1 : sta ACT_TGT,x
        rts

; =============================================================================
; DRAW_ROOM — draws CUR_ROOM to screen rows 2-23
; =============================================================================
DRAW_ROOM
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
        jmp ASSIGN_SPRITES           ; room changed: remap actors -> sprites

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
        ldx #39
DSTL    lda STAT_TMPL,x : jsr PET2SCREEN : sta SCRN+960,x
        lda #DGRAY : sta CRAM+960,x
        dex : bpl DSTL
        lda CUR_ROOM : clc : adc #(CH_0+1) : sta SCRN+962
        ; position of whoever the player is driving (human or proxy actor)
        ldx PLAYER_MODE : beq DSTHUM
        dex
        lda ACT_Y,x : sta NEWY       ; stash: DEC2 clobbers X and TMP/TMP2
        lda ACT_X,x : jsr DEC2       ; X can reach 12 — 2 digits
        lda TMP : sta SCRN+966 : lda TMP2 : sta SCRN+967
        lda NEWY
        jmp DSTYGO
DSTHUM  lda PLR_X : jsr DEC2
        lda TMP : sta SCRN+966 : lda TMP2 : sta SCRN+967
        lda PLR_Y
DSTYGO  clc : adc #CH_0 : sta SCRN+971
        lda #LTGREEN : sta CRAM+962 : sta CRAM+966 : sta CRAM+967 : sta CRAM+971

        ; item field: label of the first non-hidden item (12 chars, world.asm)
        ldx #0
DSTIL   cpx #NUM_ITEMS : bcs DSTOUT
        lda ITEM_STATE,x : bne DSTIF
        inx : bne DSTIL
DSTIF   lda ITEM_LABEL_LO,x : sta PTR
        lda ITEM_LABEL_HI,x : sta PTR+1
        ldy #11
DSTLL   lda (PTR),y : jsr PET2SCREEN : sta SCRN+978,y
        lda #LTRED : sta CRAM+978,y
        dey : bpl DSTLL
DSTOUT  rts

STAT_TMPL
        !pet "r:0 x=00 y=0 item:            joy/wasd  "

; =============================================================================
; SID DEATH SOUND
; Voice 1 sawtooth, descending pitch sweep over ~50 frames.
; =============================================================================
SOUND_DEATH_START
        lda #50    : sta SND_TMR

        lda #$00   : sta $D405      ; attack=0, decay=0
        lda #$F0   : sta $D406      ; sustain=15, release=0
        lda #$0F   : sta $D418      ; master volume full

        lda #$90   : sta $D400      ; freq lo  ($0290 ≈ 350Hz)
        lda #$02   : sta $D401      ; freq hi
        lda #$21   : sta $D404      ; sawtooth + gate on
        rts

SOUND_TICK
        lda SND_TMR
        beq SNDOUT

        dec SND_TMR
        lda SND_TMR
        beq SNDOFF

        ; Frequency = SND_TMR * 8 + $0200
        asl : asl : asl
        sta $D400               ; freq lo
        lda SND_TMR
        lsr : lsr : lsr : lsr : lsr
        clc : adc #2
        sta $D401               ; freq hi
        bne SNDOUT

SNDOFF  lda #$20 : sta $D404
        lda #$0F : sta $D418
SNDOUT  rts
