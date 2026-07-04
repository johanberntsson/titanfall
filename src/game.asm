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
        jsr UPDATE_SPRITE1
        jsr UPDATE_SPRITE2
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
        lda #5   : sta CLK_H
        lda #47  : sta CLK_M
        lda #33  : sta CLK_S
        lda #0   : sta CLK_TICK
        jmp RESET_ROUND

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

        lda #4   : sta PLR_X
        lda #4   : sta PLR_Y
        lda #23  : sta REACT_TEMP
        lda #0   : sta REACT_CNT
        lda #0   : sta REACT_JIT
        lda #$A3 : sta LFSR_ST
        lda #0   : sta MOVE_TMR
        lda #0   : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0   : sta DEATH_TMR
        lda #0   : sta CUR_ROOM
        lda #0   : sta BFLASH
        lda #0   : sta SND_TMR
        lda #0   : sta PLAYER_MODE
        lda #0   : sta LASER_OFF
        lda #1   : sta ROB2_ALIVE

        lda #2   : sta ROB0_X
        lda #7   : sta ROB0_Y
        lda #1   : sta ROB0_DIR
        lda #2   : sta ROB1_X
        lda #5   : sta ROB1_Y
        lda #1   : sta ROB1_DIR
        lda #7   : sta ROB2_X
        lda #3   : sta ROB2_Y
        lda #1   : sta ROB2_DIR
        lda #20  : sta ROB_TMR

        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1
        lda #$FE   : sta SPRPTR+2
        lda #ORANGE : sta VIC_SPCOL1
        lda #GREEN  : sta VIC_SPCOL2
        jsr DRAW_HUD_STATIC
        jsr DRAW_ROOM

        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_SPRITE1
        jsr UPDATE_SPRITE2
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
        lda CLK_M : cmp #30 : bcs ADPSUB30    ; M>=30: just subtract 30 from M
        lda CLK_H : bne ADPBORROW             ; M<30, H>0: borrow an hour
        lda #0 : sta CLK_H : sta CLK_M : sta CLK_S  ; not enough time left: clamp to 0
        jmp ADPCHECK
ADPBORROW
        dec CLK_H
        lda CLK_M : clc : adc #30 : sta CLK_M ; M was <30, so M+30 <60: no overflow
        jmp ADPCHECK
ADPSUB30
        lda CLK_M : sec : sbc #30 : sta CLK_M
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
        lda #0 : sta KEY_F1 : sta KEY_RET : sta KEY_ESC : sta KEY_MAP
        lda #0 : sta KEY_X

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

        ; T key: col 2 (PA=$FB), row 6 (PB bit 6, active low)
        lda #$FB : sta CIA1_PRA
        lda CIA1_PRB : and #$40 : bne RKF1N
        lda #1 : sta KEY_F1
RKF1N

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

        ; Check proximity to terminal: PLR_X 1-3, PLR_Y 3-5 (room 1 only)
        lda #0 : sta NEAR_TERM
        lda CUR_ROOM : bne RKMAPCHK
        lda PLR_X : cmp #1 : bcc RKMAPCHK
        cmp #4 : bcs RKMAPCHK
        lda PLR_Y : cmp #3 : bcc RKMAPCHK
        cmp #6 : bcs RKMAPCHK
        lda #1 : sta NEAR_TERM
        lda KEY_F1 : beq RKMAPCHK
        jsr SETUP_TERMINAL
        rts
RKMAPCHK
        lda KEY_MAP : beq RKXCHK
        jsr SETUP_MAP
        rts
RKXCHK
        lda PLAYER_MODE : beq RKDONE
        lda KEY_X : beq RKDONE
        lda #0 : sta PLAYER_MODE
RKDONE  rts

; =============================================================================
; MOVE_PLAYER
; Doorway: room1 left wall / room2 right wall open at PLR_Y 5-6.
; =============================================================================
MOVE_PLAYER
        lda MOVE_TMR : beq MOVEGO
        dec MOVE_TMR : rts
MOVEGO  lda #8 : sta MOVE_TMR

        lda PLAYER_MODE : beq MOVEHUM
        jmp MOVE_ROBOT2
MOVEHUM
        ; Up
        lda KEY_U : beq MOVTD
        lda PLR_Y : beq MOVTD
        dec PLR_Y : rts
        ; Down
MOVTD   lda KEY_D : beq MOVTL
        lda PLR_Y : cmp #9 : bcc MOVTD_WALK
        ; PLR_Y=9: check for bottom win doorway (room 2 only, PLR_X 4-6)
        lda CUR_ROOM : beq MOVTL
        lda PLR_X : cmp #4 : bcc MOVTL
        cmp #7 : bcs MOVTL
        jsr SETUP_WIN : rts
MOVTD_WALK
        inc PLR_Y : rts
        ; Left
MOVTL   lda KEY_L : beq MOVTR
        lda PLR_X : bne MOVLW
        ; PLR_X=0: doorway check (room 1 left wall, PLR_Y 5-6)
        lda CUR_ROOM : bne MOVTR
        lda PLR_Y : cmp #5 : bcc MOVTR
        cmp #7 : bcs MOVTR
        lda #1 : sta CUR_ROOM
        lda #9 : sta PLR_X
        jsr DRAW_ROOM : rts
MOVLW   dec PLR_X : rts
        ; Right
MOVTR   lda KEY_R : beq MOVDONE
        lda CUR_ROOM : bne MOVTR_R2
        ; Room 1: right wall is at tile 12, not 9 (see TILE_TO_PIXEL_X — the
        ; room is 320px wide, wider than tile 9's ~244px reach at the shared
        ; 24px/tile pitch).
        lda PLR_X : cmp #12 : bcs MOVDONE
        jmp MOVRW
MOVTR_R2
        ; Room 2: PLR_X=9 doorway check (right wall, PLR_Y 5-6, back to room 1)
        lda PLR_X : cmp #9 : bcc MOVRW
        lda PLR_Y : cmp #5 : bcc MOVDONE
        cmp #7 : bcs MOVDONE
        lda #0 : sta CUR_ROOM
        lda #0 : sta PLR_X
        jsr DRAW_ROOM : rts
        ; Inner right move: laser in room 1 only (unless already destroyed)
MOVRW   lda CUR_ROOM : bne MOVOK
        lda PLR_X : clc : adc #1 : cmp #6 : bne MOVOK
        lda LASER_OFF : bne MOVOK
        lda #RED  : sta VIC_BRDCOL
        lda #100  : sta DEATH_TMR
        jsr SOUND_DEATH_START : rts
MOVOK   inc PLR_X
MOVDONE rts

; =============================================================================
; MOVE_ROBOT2 — move the splicer robot (room 1 only) while PLAYER_MODE=1.
; No laser/doorway checks. Y is confined to the 0-9 tile grid, but X goes up
; to 12: the room is 320px (40 chars) wide while the shared PLR/ROB tile pitch
; (24px, see UPDATE_SPRITE2) only spans ~244px over 0-9, well short of the
; right wall. Tiles 10-12 push the sprite X pixel value past 255, which is
; why UPDATE_SPRITE2 already tracks the carry out of the pixel-X add and sets
; VIC_SP_MSB bit 2 (the 9th/extended X bit) for sprite 2 — that logic was
; simply never exercised while X topped out at 9.
; =============================================================================
MOVE_ROBOT2
        lda KEY_U : beq MR2D
        lda ROB2_Y : beq MR2D
        dec ROB2_Y : rts
MR2D    lda KEY_D : beq MR2L
        lda ROB2_Y : cmp #9 : bcs MR2L
        inc ROB2_Y : rts
MR2L    lda KEY_L : beq MR2R
        lda ROB2_X : beq MR2R
        dec ROB2_X
        lda ROB2_X : jsr LASER_HIT_CHECK : bcc MR2DONE
        jsr ROB2_LASER_DEATH : rts
MR2R    lda KEY_R : beq MR2DONE
        lda ROB2_X : cmp #12 : bcs MR2DONE
        inc ROB2_X
        lda ROB2_X : jsr LASER_HIT_CHECK : bcc MR2DONE
        jsr ROB2_LASER_DEATH
MR2DONE rts

; =============================================================================
; LASER_HIT_CHECK — A=robot tile X. Returns carry set if this is a live laser
; hit: room 1, tile X=6, and the laser hasn't already been destroyed.
; =============================================================================
LASER_HIT_CHECK
        cmp #6 : bne LHCNO
        lda CUR_ROOM : bne LHCNO
        lda LASER_OFF : bne LHCNO
        sec : rts
LHCNO   clc : rts

; =============================================================================
; ROB2_LASER_DEATH — the splicer walked into the laser: it disappears for
; good and the laser itself burns out (LASER_OFF=1), so it can no longer
; hurt the human either. If the player was piloting it, control snaps back
; to human immediately.
; =============================================================================
ROB2_LASER_DEATH
        lda #0   : sta ROB2_ALIVE
        lda #1   : sta LASER_OFF
        lda #YELLOW : sta VIC_BRDCOL
        lda #15  : sta BFLASH
        lda PLAYER_MODE : beq RB2LDONE
        lda #0   : sta PLAYER_MODE
RB2LDONE rts

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
; UPDATE_SPRITE1 — position robot sprite from current room's robot coords
; =============================================================================
UPDATE_SPRITE1
        lda CUR_ROOM : bne UPSP1R2
        lda ROB0_X : sta TMP : lda ROB0_Y : jmp UPSP1CALC
UPSP1R2 lda ROB1_X : sta TMP : lda ROB1_Y
UPSP1CALC
        asl : asl : asl : asl
        clc : adc #66 : sta VIC_SP1Y
        lda TMP : jsr TILE_TO_PIXEL_X
        sta VIC_SP1X
        bcs UPSP1MSB
        lda VIC_SP_MSB : and #$FD : sta VIC_SP_MSB : bcc UPSP1X
UPSP1MSB lda VIC_SP_MSB : ora #$02 : sta VIC_SP_MSB
UPSP1X  rts

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
; UPDATE_SPRITE2 — position splicer robot (room 1 only, right of the laser).
; Sprite is enabled only while CUR_ROOM=0 and ROB2_ALIVE=1; hidden (VIC_SPEN
; bit 2 cleared) otherwise — either because there's no room 2 counterpart, or
; because the splicer was destroyed by the laser (see ROB2_LASER_DEATH).
; =============================================================================
UPDATE_SPRITE2
        lda ROB2_ALIVE : beq UPSP2OFF
        lda CUR_ROOM : beq UPSP2ON
UPSP2OFF lda VIC_SPEN : and #$FB : sta VIC_SPEN
        rts
UPSP2ON lda VIC_SPEN : ora #$04 : sta VIC_SPEN

        lda ROB2_Y : asl : asl : asl : asl
        clc : adc #66 : sta VIC_SP2Y

        lda ROB2_X : jsr TILE_TO_PIXEL_X
        sta VIC_SP2X
        bcs UPSP2MSB
        lda VIC_SP_MSB : and #$FB : sta VIC_SP_MSB : rts
UPSP2MSB lda VIC_SP_MSB : ora #$04 : sta VIC_SP_MSB
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
; TICK_ROBOT — move both robots on their patrol paths
; =============================================================================
TICK_ROBOT
        lda ROB_TMR : beq TROBOK
        dec ROB_TMR : rts
TROBOK  lda #20 : sta ROB_TMR

        ; Robot 0 (room 1): patrols X=2..4 on Y=7
        lda ROB0_DIR : bne TR0RIGHT
        lda ROB0_X : cmp #3 : bcc TR0FLIP0
        dec ROB0_X : jmp TROBT1
TR0FLIP0 lda #1 : sta ROB0_DIR : jmp TROBT1
TR0RIGHT lda ROB0_X : cmp #4 : bcc TR0FWD
        lda #0 : sta ROB0_DIR : jmp TROBT1
TR0FWD  inc ROB0_X

TROBT1  ; Robot 1 (room 2): patrols X=2..7 on Y=5
        lda ROB1_DIR : bne TR1RIGHT
        lda ROB1_X : cmp #3 : bcc TR1FLIP1
        dec ROB1_X : jmp TROBT2
TR1FLIP1 lda #1 : sta ROB1_DIR : jmp TROBT2
TR1RIGHT lda ROB1_X : cmp #7 : bcc TR1FWD
        lda #0 : sta ROB1_DIR : jmp TROBT2
TR1FWD  inc ROB1_X

TROBT2  ; Robot 2 (room 1, splicer): patrols X=7..9 on Y=3, right of the laser.
        ; Suspended while PLAYER_MODE=1 (player is driving it via MOVE_ROBOT2)
        ; or ROB2_ALIVE=0 (destroyed by the laser — stays put forever).
        lda ROB2_ALIVE : beq TR2SKIP
        lda PLAYER_MODE : bne TR2SKIP
        lda ROB2_DIR : bne TR2RIGHT
        lda ROB2_X : cmp #8 : bcc TR2FLIP2
        dec ROB2_X : rts
TR2FLIP2 lda #1 : sta ROB2_DIR : rts
TR2RIGHT lda ROB2_X : cmp #9 : bcc TR2FWD
        lda #0 : sta ROB2_DIR : rts
TR2FWD  inc ROB2_X : rts
TR2SKIP rts

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
        rts

DRMSETPTR
        lda CUR_ROOM : beq DRMSP1
        lda #<ROOM2_DATA : sta PTR : lda #>ROOM2_DATA : sta PTR+1 : rts
DRMSP1  lda #<ROOM_DATA  : sta PTR : lda #>ROOM_DATA  : sta PTR+1 : rts

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
        lda PLAYER_MODE : bne DSTROBX
        lda PLR_X : jmp DSTXGO
DSTROBX lda ROB2_X
        ; X can reach 12 (see MOVTR/MOVE_ROBOT2), so it needs 2 digits, unlike
        ; the single-digit 0-9 room/Y fields.
DSTXGO  jsr DEC2
        lda TMP : sta SCRN+966 : lda TMP2 : sta SCRN+967
        lda PLAYER_MODE : bne DSTROBY
        lda PLR_Y : jmp DSTYGO
DSTROBY lda ROB2_Y
DSTYGO  clc : adc #CH_0 : sta SCRN+971
        lda #LTGREEN : sta CRAM+962 : sta CRAM+966 : sta CRAM+967 : sta CRAM+971
        rts

STAT_TMPL
        !pet "r:0 x=00 y=0 chips:l1x2 l2x1  joy/wasd  "

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
