; =============================================================================
; WIN STATE (GAME_STATE = 4)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_WIN — called each frame in state 4
; ---------------------------------------------------------------------------
DO_WIN
        jsr GETIN
        bne WIN_GO
        lda JOY_NEW : and #$10          ; or joystick fire
        beq WIN_NOBTN
WIN_GO
        lda #0     : sta GAME_STATE
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$00   : sta VIC_SPEN
        lda #0     : sta BLINK_TMR : sta BLINK_ST
        jsr CLS
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2
        jsr DRAW_INTRO_SCREEN
        jmp MAIN_LOOP

WIN_NOBTN
        inc BLINK_TMR
        lda BLINK_TMR : cmp #25 : bcc WIN_DONE
        lda #0 : sta BLINK_TMR
        lda BLINK_ST : bne WIN_SHOW
        jsr WIN_BLINK_OFF
        lda #1 : sta BLINK_ST : jmp WIN_DONE
WIN_SHOW
        jsr WIN_BLINK_ON
        lda #0 : sta BLINK_ST
WIN_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_WIN — draw win screen, set GAME_STATE=4. Called via jsr from MOVE_PLAYER.
; =============================================================================
SETUP_WIN
        lda #4     : sta GAME_STATE
        lda #0     : sta $C6
        lda #0     : sta SND_TMR
        lda #$00   : sta $D404
        lda #$00   : sta VIC_SPEN
        lda #GREEN : sta VIC_BRDCOL
        lda #BLACK : sta VIC_BGCOL
        lda #0     : sta BLINK_TMR : sta BLINK_ST

        jsr CLS
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2

        ldx #39    ; row 3: top border (GREEN)
WROW03  lda SCR_BORDER_TOP,x : jsr PET2SCREEN : sta SCRN+120,x
        lda #GREEN : sta CRAM+120,x
        dex : bpl WROW03

        ldx #39    ; row 4: blank (GREEN)
WROW04  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+160,x
        lda #GREEN : sta CRAM+160,x
        dex : bpl WROW04

        ldx #39    ; row 5: title (LTGREEN)
WROW05  lda WIN_TITLE,x : jsr PET2SCREEN : sta SCRN+200,x
        lda #LTGREEN : sta CRAM+200,x
        dex : bpl WROW05
        lda #YELLOW
        sta CRAM+203 : sta CRAM+205 : sta CRAM+207
        sta CRAM+228 : sta CRAM+230 : sta CRAM+232

        ldx #39    ; row 6: blank (GREEN)
WROW06  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+240,x
        lda #GREEN : sta CRAM+240,x
        dex : bpl WROW06

        ldx #39    ; row 7: separator (BLUE)
WROW07  lda ITR_SEP,x : jsr PET2SCREEN : sta SCRN+280,x
        lda #BLUE : sta CRAM+280,x
        dex : bpl WROW07

        ldx #39    ; row 8: launch aborted (YELLOW)
WROW08  lda WIN_M1,x : jsr PET2SCREEN : sta SCRN+320,x
        lda #YELLOW : sta CRAM+320,x
        dex : bpl WROW08

        ldx #39    ; row 9: secured (WHITE)
WROW09  lda WIN_M2,x : jsr PET2SCREEN : sta SCRN+360,x
        lda #WHITE : sta CRAM+360,x
        dex : bpl WROW09

        ldx #39    ; row 10: blank (GREEN)
WROW10  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+400,x
        lda #GREEN : sta CRAM+400,x
        dex : bpl WROW10

        ldx #39    ; row 11: well done (CYAN)
WROW11  lda WIN_M3,x : jsr PET2SCREEN : sta SCRN+440,x
        lda #CYAN : sta CRAM+440,x
        dex : bpl WROW11

        ldx #39    ; row 12: blank (GREEN)
WROW12  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+480,x
        lda #GREEN : sta CRAM+480,x
        dex : bpl WROW12

        ldx #39    ; row 13: bottom border (GREEN)
WROW13  lda SCR_BORDER_BOTTOM,x : jsr PET2SCREEN : sta SCRN+520,x
        lda #GREEN : sta CRAM+520,x
        dex : bpl WROW13

        lda #GREEN : ldx #3 : ldy #13 : jsr FRAME_EDGES
        jsr WIN_BLINK_ON
        rts

; =============================================================================
; Blink helpers — win prompt
; =============================================================================
WIN_BLINK_ON
        ldx #39
WINBLON lda TXT_WINPRESS,x : jsr PET2SCREEN : sta SCRN+600,x
        lda #WHITE : sta CRAM+600,x
        dex : bpl WINBLON
        rts

WIN_BLINK_OFF
        ldx #39
WINBLOFF lda #CH_SPC : sta SCRN+600,x
        dex : bpl WINBLOFF
        rts

; =============================================================================
; Win strings — all exactly 40 bytes
; =============================================================================
WIN_TITLE   !pet G_VERT_BAR,"  * * *  mission complete  * * *      ",G_VERT_BAR
WIN_M1      !pet G_VERT_BAR,"  launch sequence aborted!            ",G_VERT_BAR
WIN_M2      !pet G_VERT_BAR,"  titan complex secured               ",G_VERT_BAR
WIN_M3      !pet G_VERT_BAR,"  well done, operative                ",G_VERT_BAR

TXT_WINPRESS !pet "       press fire to continue           "

; =============================================================================
; EXPLOSION (GAME_STATE = 7) — the payoff before the win screen. SETUP_EXPLODE
; (jmp from BOLT_TICK when a player-fired bolt enters a win-target tile)
; turns every power-cell char on screen dark grey, starts the explosion sound
; and saves $D011/$D016; DO_EXPLODE then shakes the whole screen for
; EXPL_LEN frames with random fine-scroll values (bits 0-2 of $D011/$D016,
; the amplitude dying away with the timer) and flickers the border, then
; restores both registers and shows the win screen. Time and robots are
; paused (DO_GAME isn't called in state 7). Returns to GAME_ALIVE.
; =============================================================================
EXPL_LEN = BOOM_LEN                     ; 2 s

SETUP_EXPLODE
        lda #7 : sta GAME_STATE
        lda #0 : sta BOLT_ON
        lda VIC_SPEN : and #$F7 : sta VIC_SPEN   ; the bolt is gone
        ; the power cell burns out: its chars (art.win_tiles) go dark grey —
        ; rows 2-23 = SCRN+80.., 3 pages + 112 bytes
        ldx #0
EXSL    lda SCRN+80,x : jsr EXP_ISCELL : bne EXS1
        lda #DGRAY : sta CRAM+80,x
EXS1    lda SCRN+336,x : jsr EXP_ISCELL : bne EXS2
        lda #DGRAY : sta CRAM+336,x
EXS2    lda SCRN+592,x : jsr EXP_ISCELL : bne EXS3
        lda #DGRAY : sta CRAM+592,x
EXS3    cpx #112 : bcs EXS4
        lda SCRN+848,x : jsr EXP_ISCELL : bne EXS4
        lda #DGRAY : sta CRAM+848,x
EXS4    inx : bne EXSL
        lda VIC_CR1 : sta EXP_D011
        lda $D016 : sta EXP_D016
        lda #EXPL_LEN : sta EXPL_TMR
        jmp SOUND_BOOM_START

; EXP_ISCELL — A = screen code. Z set if it's a win-target char (WIN_CHARS,
; generated from art.win_tiles). Preserves X.
EXP_ISCELL
        ldy #0
EICL    cpy #NUM_WIN_CHARS : bcs EICNO
        cmp WIN_CHARS,y : beq EICOUT
        iny : bne EICL
EICNO   ldy #1                          ; Z clear
EICOUT  rts

; DO_EXPLODE — called each frame in state 7
DO_EXPLODE
        dec EXPL_TMR : beq EXDONE
        lda LFSR_ST : asl : bcc EXNFB : eor #$B8   ; step the LFSR
EXNFB   sta LFSR_ST
        lda EXPL_TMR : lsr : lsr : lsr : lsr       ; amplitude 6 .. 0
        ora #1 : sta TMP                           ; (never quite still)
        lda LFSR_ST : and TMP : sta TMP2
        lda VIC_CR1 : and #$78 : ora TMP2 : sta VIC_CR1   ; vertical shake (bit 7
                                          ;  reads the raster's bit 8: write 0, or the IRQ moves)
        lda LFSR_ST : lsr : lsr : lsr : and TMP : sta TMP2
        lda $D016 : and #$F8 : ora TMP2 : sta $D016       ; horizontal shake
        lda LFSR_ST : and #3 : tax
        lda EXP_COLS,x : sta VIC_BRDCOL                   ; fire in the border
        jmp MAIN_LOOP
EXDONE  lda EXP_D011 : and #$7F : sta VIC_CR1   ; (bit 7: see above)
        lda EXP_D016 : sta $D016
        jsr SETUP_WIN
        jmp MAIN_LOOP

EXP_COLS !byte RED, ORANGE, YELLOW, ORANGE
