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
        jsr SETUP_GAMEOVER
        jmp MAIN_LOOP

GAME_ALIVE
        jsr TICK_CLOCK
        jsr TICK_REACTOR
        jsr TICK_ROBOT
        jsr READ_KEYS
        jsr MOVE_PLAYER
        lda GAME_STATE : cmp #4 : bcs GAME_TICK_DONE  ; win/map triggered this frame
        jsr UPDATE_SPRITE0
        jsr UPDATE_SPRITE1
        jsr CHECK_SPRITE_HIT
        jsr DRAW_HUD_DYNAMIC
        jsr DRAW_STATUS
GAME_TICK_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_GAME — initialise vars and draw playfield. Called via jsr from DO_INTRO.
; =============================================================================
SETUP_GAME
        lda #1   : sta GAME_STATE
        lda #0   : sta $C6
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL

        lda #4   : sta PLR_X
        lda #4   : sta PLR_Y
        lda #5   : sta CLK_H
        lda #47  : sta CLK_M
        lda #33  : sta CLK_S
        lda #0   : sta CLK_TICK
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

        lda #2   : sta ROB0_X
        lda #7   : sta ROB0_Y
        lda #1   : sta ROB0_DIR
        lda #2   : sta ROB1_X
        lda #5   : sta ROB1_Y
        lda #1   : sta ROB1_DIR
        lda #20  : sta ROB_TMR

        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1
        lda #ORANGE : sta VIC_SPCOL1
        jsr DRAW_HUD_STATIC
        jsr DRAW_ROOM

        lda #$03 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_SPRITE1
        rts

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

        ldx #4
HUDML   lda LMODE_H,x : jsr PET2SCREEN : sta SCRN+9,x
        lda #CYAN : sta CRAM+9,x
        dex
        bpl HUDML

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

        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRB : sta TMP
        lda TMP : and #$01 : bne RKJ1 : lda #1 : sta KEY_U
RKJ1    lda TMP : and #$02 : bne RKJ2 : lda #1 : sta KEY_D
RKJ2    lda TMP : and #$04 : bne RKJ3 : lda #1 : sta KEY_L
RKJ3    lda TMP : and #$08 : bne RKJ4 : lda #1 : sta KEY_R
RKJ4
        lda #$FE : sta CIA1_PRA
        lda CIA1_PRB : sta TMP
        lda TMP : and #$80 : bne RKCUD
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : bne RKCDN
        lda #1 : sta KEY_U : !byte $2C
RKCDN   lda #1 : sta KEY_D
RKCUD
        lda #$FE : sta CIA1_PRA
        lda CIA1_PRB : and #$04 : bne RKCRT
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : bne RKCRIGHT
        lda #1 : sta KEY_L : !byte $2C
RKCRIGHT lda #1 : sta KEY_R
RKCRT

        ; T key: col 2 (PA=$FB), row 4 (PB bit 4, active low)
        lda #$FB : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKF1N
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
        lda KEY_MAP : beq RKDONE
        jsr SETUP_MAP
RKDONE  rts

; =============================================================================
; MOVE_PLAYER
; Doorway: room1 left wall / room2 right wall open at PLR_Y 5-6.
; =============================================================================
MOVE_PLAYER
        lda MOVE_TMR : beq MOVEGO
        dec MOVE_TMR : rts
MOVEGO  lda #8 : sta MOVE_TMR

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
        lda PLR_X : cmp #9 : bcc MOVRW
        ; PLR_X=9: doorway check (room 2 right wall, PLR_Y 5-6)
        lda CUR_ROOM : beq MOVDONE
        lda PLR_Y : cmp #5 : bcc MOVDONE
        cmp #7 : bcs MOVDONE
        lda #0 : sta CUR_ROOM
        lda #0 : sta PLR_X
        jsr DRAW_ROOM : rts
        ; Inner right move: laser in room 1 only
MOVRW   lda CUR_ROOM : bne MOVOK
        lda PLR_X : clc : adc #1 : cmp #6 : bne MOVOK
        lda #RED  : sta VIC_BRDCOL
        lda #100  : sta DEATH_TMR
        jsr SOUND_DEATH_START : rts
MOVOK   inc PLR_X
MOVDONE rts

; =============================================================================
; UPDATE_SPRITE0
; =============================================================================
UPDATE_SPRITE0
        lda PLR_X
        asl : asl : asl : asl : sta TMP
        lda PLR_X : asl : asl : asl
        clc : adc TMP : clc : adc #28
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
        lda TMP : asl : asl : asl : asl : sta TMP2   ; TMP * 16
        lda TMP : asl : asl : asl                    ; TMP * 8
        clc : adc TMP2 : clc : adc #28
        sta VIC_SP1X
        bcs UPSP1MSB
        lda VIC_SP_MSB : and #$FD : sta VIC_SP_MSB : bcc UPSP1X
UPSP1MSB lda VIC_SP_MSB : ora #$02 : sta VIC_SP_MSB
UPSP1X  rts

; =============================================================================
; CHECK_SPRITE_HIT — read $D01E once; bits 0-1 = sprites 0+1 collided
; =============================================================================
CHECK_SPRITE_HIT
        lda DEATH_TMR : bne SPRHITOK
        lda VIC_SPCOLL : and #$03 : beq SPRHITOK
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
        dec ROB1_X : rts
TR1FLIP1 lda #1 : sta ROB1_DIR : rts
TR1RIGHT lda ROB1_X : cmp #7 : bcc TR1FWD
        lda #0 : sta ROB1_DIR : rts
TR1FWD  inc ROB1_X : rts

; =============================================================================
; DRAW_ROOM — draws CUR_ROOM to screen rows 2-23
; =============================================================================
DRAW_ROOM
        jsr DRMSETPTR
        lda #<(SCRN+80) : sta PTR2 : lda #>(SCRN+80) : sta PTR2+1
        ldx #3 : ldy #0
DRMPG   lda (PTR),y : jsr PET2SCREEN : sta (PTR2),y
        iny : bne DRMPG
        inc PTR+1 : inc PTR2+1
        dex : bne DRMPG
        ldy #0
DRMTAIL lda (PTR),y : jsr PET2SCREEN : sta (PTR2),y
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

COL_BYTE
        lda (PTR),y
        cmp #CH_SPC  : beq COLFL
        cmp #CH_PLUS     : beq COLWA
        cmp #G_HORIZ_BAR : beq COLWA
        cmp #G_VERT_BAR  : beq COLWA
        cmp #CH_EQ   : beq COLRA
        cmp #CH_HASH : beq COLCR
        cmp #CH_BANG : beq COLLA
        cmp #$54     : beq COLTE
        cmp #$44     : beq COLDR
        cmp #CH_LBRK : beq COLDR
        cmp #CH_RBRK : beq COLDR
        cmp #$31     : beq COLDR
        cmp #$32     : beq COLDR
        lda #MGRAY   : !byte $2C
COLFL   lda #DGRAY   : !byte $2C
COLWA   lda #BLUE    : !byte $2C
COLRA   lda #YELLOW  : !byte $2C
COLCR   lda #ORANGE  : !byte $2C
COLLA   lda #LTRED   : !byte $2C
COLTE   lda #LTGREEN : !byte $2C
COLDR   lda #LTGREEN
COLST   sta (PTR2),y
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
        lda PLR_X : clc : adc #CH_0 : sta SCRN+966
        lda PLR_Y : clc : adc #CH_0 : sta SCRN+970
        lda #LTGREEN : sta CRAM+962 : sta CRAM+966 : sta CRAM+970
        rts

STAT_TMPL
        !pet "r:0 x=0 y=0  chips:l1x2 l2x1  joy/crsr  "

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
        lda #$00 : sta $D418
SNDOUT  rts
