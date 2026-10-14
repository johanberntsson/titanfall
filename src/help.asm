; =============================================================================
; HELP / PAUSE STATE (GAME_STATE = 9)
; =============================================================================
; F1 (without shift — shift+F1 is F2, where am I) opens this screen from any
; state (MAIN_LOOP checks it before the dispatch). It pauses everything: no
; DO_* handler of the interrupted state runs (so the clock, robots, the death
; pause, the explosion and the missile all stop), the music and any sound
; effect are silenced. The screen, colour RAM (and with them the sprite
; pointers) and the VIC registers the states play with are saved, so resuming
; puts the interrupted state back exactly as it was, whatever it was.
;   space / fire     resume
;   f7               end a robot link, then resume
; and, listed under "from this screen you can also select:",
;   r                reset the room (like a death): spends a reset key, or
;                    without one costs CFG_RESET_M minutes
;   run/stop         restart the game (SETUP_GAME; in VICE, Esc is Run/Stop)
; R/F7 only work when a game is under way (R: not while the player is dying,
; or it would dodge the death penalty).
; =============================================================================
HLP_STATE !byte 0                       ; the interrupted state
HLP_MOFF  !byte 0                       ; its MUSIC_OFF, SND_TMR
HLP_SND   !byte 0
HLP_SPEN  !byte 0                       ; its VIC_SPEN, border, background,
HLP_BRD   !byte 0                       ;  $D011 (bit 7 clear) and $D016
HLP_BG    !byte 0
HLP_D011  !byte 0
HLP_D016  !byte 0
HLP_SCR   = $C600                       ; screen RAM (incl. the sprite pointers)
HLP_COL   = $CA00                       ; colour RAM -- both in the free RAM
                                        ;  after the music ($C000-$C5xx; its
                                        ;  file checks it ends below $C600)

; -----------------------------------------------------------------------------
; SETUP_HELP — jmp'd to from MAIN_LOOP on a fresh F1 press
; -----------------------------------------------------------------------------
SETUP_HELP
        lda GAME_STATE : sta HLP_STATE
        lda #9 : sta GAME_STATE
        lda MUSIC_OFF : sta HLP_MOFF
        lda #1 : sta MUSIC_OFF          ; (first: the IRQ plays music once
        lda SND_TMR : sta HLP_SND       ;  SND_TMR is 0)
        lda #0 : sta SND_TMR
        sta $D404 : sta $D40B : sta $D412   ; all three voices off
        lda VIC_SPEN : sta HLP_SPEN
        lda #0 : sta VIC_SPEN
        lda VIC_BRDCOL : sta HLP_BRD
        lda VIC_BGCOL : sta HLP_BG
        lda VIC_CR1 : and #$7F : sta HLP_D011
        lda $D016 : sta HLP_D016
        ; the help screen unshaken: the explosion shakes the fine scroll
        ; (EXP_D011/EXP_D016 hold the values from before the shake)
        ldx HLP_D011 : ldy HLP_D016
        lda HLP_STATE : cmp #7 : bne SHPSCRL
        ldx EXP_D011 : ldy EXP_D016
SHPSCRL txa : and #$7F : sta VIC_CR1
        sty $D016

        ldx #0
SHPSAVE lda SCRN,x       : sta HLP_SCR,x
        lda SCRN+$100,x  : sta HLP_SCR+$100,x
        lda SCRN+$200,x  : sta HLP_SCR+$200,x
        lda SCRN+$300,x  : sta HLP_SCR+$300,x
        lda CRAM,x       : sta HLP_COL,x
        lda CRAM+$100,x  : sta HLP_COL+$100,x
        lda CRAM+$200,x  : sta HLP_COL+$200,x
        lda CRAM+$300,x  : sta HLP_COL+$300,x
        inx : bne SHPSAVE

        lda #0 : sta $C6                ; drop buffered keys (F1 itself)
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        jsr CLS                         ; (the pointers come back on resume)
        lda #<HLP_ROWS : ldy #>HLP_ROWS : jsr DRAW_ROWS
        ; the r line says what a reset costs: a key, or minutes
        lda #<HLP_L4K : sta PTR : lda #>HLP_L4K : sta PTR+1
        lda RESET_KEYS : bne SHPRK
        lda #<HLP_L4T : sta PTR : lda #>HLP_L4T : sta PTR+1
        lda #CFG_RESET_M
SHPRK   pha
        lda #WHITE : sta TMP2
        lda #14 : jsr DRAW_ROW
        pla : jsr DEC2                   ; keys: col 31 / minutes: cols 25-26
        lda RESET_KEYS : bne SHPRK2
        lda TMP : sta SCRN+14*40+25 : lda TMP2 : sta SCRN+14*40+26
        jmp SHPRK3
SHPRK2  lda TMP2 : sta SCRN+14*40+31
SHPRK3  lda #DGRAY : ldx #5 : ldy #17 : jsr FRAME_EDGES
        jmp MAIN_LOOP

; -----------------------------------------------------------------------------
; DO_HELP — called each frame in state 9
; -----------------------------------------------------------------------------
DO_HELP
        lda JOY_NEW : and #$10 : beq DHNORES ; space / fire (fresh press)
        jmp HELP_RESUME
DHNORES lda #$7F : sta CIA1_PRA         ; Run/Stop: col 7 (PA=$7F), row 7
        lda CIA1_PRB : and #$80 : bne DHNORST
        jmp HELP_RESTART
DHNORST lda #$FB : sta CIA1_PRA         ; R: col 2 (PA=$FB), row 1
        lda CIA1_PRB : and #$02 : bne DHNOR
        jmp HELP_RESET
DHNOR   lda #$FE : sta CIA1_PRA         ; F7: col 0 (PA=$FE), row 3
        lda CIA1_PRB : and #$08 : bne DHOUT
        jmp HELP_UNLINK
DHOUT   lda #$FF : sta CIA1_PRA
        jmp MAIN_LOOP

; HLP_INGAME — C set if the interrupted state is part of a game under way
; (game, terminal, map, popup, robodex)
HLP_INGAME
        lda HLP_STATE
        cmp #1 : beq HIGYES
        cmp #3 : beq HIGYES
        cmp #5 : beq HIGYES
        cmp #6 : beq HIGYES
        cmp #11 : beq HIGYES
        clc : rts
HIGYES  sec : rts

; F7: the robot link ends (as F7 in the game; not while the robot is dying in
; a laser — ROBOT_LASER_DEATH ends it), then back to the game
HELP_UNLINK
        lda HLP_STATE : cmp #1 : bne DHOUT
        ldx PLAYER_MODE : beq DHOUT
        dex
        lda ACT_ALIVE,x : cmp #1 : bne DHOUT
        jsr HELP_RESUME_HW
        jsr END_LINK                    ; (sets the border: after the restore)
        jmp HELP_BACK

; space / fire: everything back as it was
HELP_RESUME
        jsr HELP_RESUME_HW
HELP_BACK
        lda HLP_STATE : sta GAME_STATE
        lda #1 : sta FIRE_PREV          ; the resuming press isn't a new one
        lda #0 : sta POPUP_ST           ;  (also for the popup's own detector)
        sta $C6
        lda #$FF : sta CIA1_PRA
        jmp MAIN_LOOP

; restore the screen, VIC and sound of the interrupted state
HELP_RESUME_HW
        ldx #0
HRSCR   lda HLP_SCR,x       : sta SCRN,x
        lda HLP_SCR+$100,x  : sta SCRN+$100,x
        lda HLP_SCR+$200,x  : sta SCRN+$200,x
        lda HLP_SCR+$300,x  : sta SCRN+$300,x
        lda HLP_COL,x       : sta CRAM,x
        lda HLP_COL+$100,x  : sta CRAM+$100,x
        lda HLP_COL+$200,x  : sta CRAM+$200,x
        lda HLP_COL+$300,x  : sta CRAM+$300,x
        inx : bne HRSCR
        lda HLP_BRD : sta VIC_BRDCOL
        lda HLP_BG : sta VIC_BGCOL
        lda HLP_D011 : sta VIC_CR1
        lda HLP_D016 : sta $D016
        lda VIC_SPCOLL                  ; (nothing latched from the restore)
        lda HLP_SPEN : sta VIC_SPEN
        lda HLP_SND : sta SND_TMR       ; an effect carries on, then the music
        lda HLP_MOFF : sta MUSIC_OFF
        rts

; R: the room back as it was entered — robots, lasers, crates, codes spent
; here, the player at the entry point — like a respawn, without the penalty
HRSOUT  jmp DHOUT
HELP_RESET
        jsr HLP_INGAME : bcc HRSOUT
        lda DEATH_TMR : ora PLR_DYING : bne HRSOUT  ; dying: no escape
        lda HLP_MOFF : sta MUSIC_OFF
        lda #0 : sta $C6
        lda #$FF : sta CIA1_PRA
        lda RESET_KEYS : beq HRSPAY     ; a reset key, else the time penalty
        dec RESET_KEYS
        jmp HRSGO
HRSPAY  lda #CFG_RESET_M : jsr SUB_MINUTES : bne HRSGO
        jsr SETUP_GAMEOVER              ; that was the last of the time
        jmp MAIN_LOOP
HRSGO   jsr RESTORE_CODES
        jsr RESET_ROUND                 ; (state 1, redraws everything)
        lda #GRACE_LEN : sta GRACE_TMR
        jmp MAIN_LOOP

; Run/Stop: a new game from the start (the briefing is skipped)
HELP_RESTART
        lda #0 : sta $D017 : sta $D01D  ; the cut scene's sprite setup
        sta VIC_SP_MSB                  ;  (as CS_END)
        lda #LTGRAY : sta $D026
        lda TYPE_COLOR+ATYPE_HUMAN : sta VIC_SPCOL0
        lda HLP_MOFF : beq HRSTMUS      ; game over had stopped the music:
        jsr MUSIC_INIT                  ;  from the top (MUSIC_OFF is still
HRSTMUS lda #0 : sta MUSIC_OFF          ;  set, so the IRQ doesn't play it)
        sta $C6
        lda #$FF : sta CIA1_PRA
        jsr LVL_RESET                   ; the first game's clock and silo
        jsr SETUP_GAME
        jmp MAIN_LOOP

; -----------------------------------------------------------------------------
; Help screen rows (40 bytes each)
; -----------------------------------------------------------------------------
HLP_ROWS
        !byte 5,  DGRAY,  <SCR_BORDER_TOP,    >SCR_BORDER_TOP
        !byte 6,  DGRAY,  <SCR_BLANK,         >SCR_BLANK
        !byte 7,  YELLOW, <HLP_TITLE,         >HLP_TITLE
        !byte 8,  BLUE,   <ITR_SEP,           >ITR_SEP
        !byte 9,  DGRAY,  <SCR_BLANK,         >SCR_BLANK
        !byte 10, WHITE,  <HLP_L1,            >HLP_L1
        !byte 11, WHITE,  <HLP_L2,            >HLP_L2
        !byte 12, DGRAY,  <SCR_BLANK,         >SCR_BLANK
        !byte 13, MGRAY,  <HLP_L3,            >HLP_L3
        !byte 14, WHITE,  <HLP_L4,            >HLP_L4
        !byte 15, WHITE,  <HLP_L5,            >HLP_L5
        !byte 16, DGRAY,  <SCR_BLANK,         >SCR_BLANK
        !byte 17, DGRAY,  <SCR_BORDER_BOTTOM, >SCR_BORDER_BOTTOM
        !byte $FF

HLP_TITLE !pet G_VERT_BAR, "          help - game paused          ", G_VERT_BAR
HLP_L1    !pet G_VERT_BAR, " space to return                      ", G_VERT_BAR
HLP_L2    !pet G_VERT_BAR, " f7 to leave robot mode               ", G_VERT_BAR
HLP_L3    !pet G_VERT_BAR, " from this screen you can also select ", G_VERT_BAR
HLP_L4    !pet G_VERT_BAR, " r to reset room                      ", G_VERT_BAR
HLP_L5    !pet G_VERT_BAR, " run/stop (or esc) to restart game    ", G_VERT_BAR
!if * - HLP_TITLE != 6*40 { !error "help rows must be 40 bytes each" }
HLP_L4K   !pet G_VERT_BAR, " r to reset room (reset keys: 0)      ", G_VERT_BAR
HLP_L4T   !pet G_VERT_BAR, " r to reset room (costs 00 minutes)   ", G_VERT_BAR
