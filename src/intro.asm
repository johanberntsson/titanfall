; =============================================================================
; INTRO STATE (GAME_STATE = 0)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_INTRO — called each frame in state 0
; ---------------------------------------------------------------------------
DO_INTRO
        jsr GETIN                       ; any key but Space (Space is fire,
        beq INTNK                       ;  merged into JOY_NEW by MAIN_LOOP;
        cmp #$20 : bne INTRO_GO           ;  as a key it could be a repeat)
INTNK   lda JOY_NEW : and #$10          ; or joystick fire / Space
        beq INTRO_NOBTN
INTRO_GO
        jsr SETUP_CUTSCENE              ; the briefing, then the game
        jmp MAIN_LOOP

INTRO_NOBTN
        inc BLINK_TMR
        lda BLINK_TMR
        cmp #25
        bcc INTRO_DONE
        lda #0 : sta BLINK_TMR
        lda BLINK_ST
        bne INTRO_SHOW
        jsr BLINK_OFF
        lda #1 : sta BLINK_ST
        jmp INTRO_DONE
INTRO_SHOW
        jsr BLINK_ON
        lda #0 : sta BLINK_ST
INTRO_DONE
        jmp MAIN_LOOP

; =============================================================================
; DRAW_INTRO_SCREEN — title logo (rows 1-8, src/titanfall_title.asm), the
; author line (row 10), the mission box (rows 12-20); the blinking prompt is
; row 22 (BLINK_ON), the help hint row 24.
; CLS + sprite pointers must be done by caller.
; =============================================================================
DRAW_INTRO_SCREEN
        ldx #0     ; rows 1-8: logo, raw screen codes + colours, two halves
DILOGO  lda TITLE_SCR,x     : sta SCRN+40,x
        lda TITLE_SCR+160,x : sta SCRN+40+160,x
        lda TITLE_COL,x     : sta CRAM+40,x
        lda TITLE_COL+160,x : sta CRAM+40+160,x
        inx : cpx #TITLE_ROWS*40/2 : bne DILOGO

        ldx #ITR_AUTH_LEN-1   ; row 10: author line, centred, no frame
DIAUTH  lda ITR_AUTH,x : jsr PET2SCREEN : sta SCRN+10*40+(40-ITR_AUTH_LEN)/2,x
        lda #MGRAY : sta CRAM+10*40+(40-ITR_AUTH_LEN)/2,x
        dex : bpl DIAUTH

        ldx #39    ; row 12: top border (DGRAY)
DIRS12  lda SCR_BORDER_TOP,x : jsr PET2SCREEN : sta SCRN+480,x
        lda #DGRAY : sta CRAM+480,x
        dex : bpl DIRS12

        ldx #39    ; row 13: tagline (CYAN)
DIRS13  lda ITR_TAG,x : jsr PET2SCREEN : sta SCRN+520,x
        lda #CYAN : sta CRAM+520,x
        dex : bpl DIRS13

        ldx #39    ; row 14: separator (BLUE)
DIRS14  lda ITR_SEP,x : jsr PET2SCREEN : sta SCRN+560,x
        lda #BLUE : sta CRAM+560,x
        dex : bpl DIRS14

        ldx #39    ; row 15: blank (DGRAY)
DIRS15  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+600,x
        lda #DGRAY : sta CRAM+600,x
        dex : bpl DIRS15

        ldx #39    ; row 16: mission line 1 (MGRAY)
DIRS16  lda ITR_M1,x : jsr PET2SCREEN : sta SCRN+640,x
        lda #MGRAY : sta CRAM+640,x
        dex : bpl DIRS16

        ldx #39    ; row 17: mission line 2 (MGRAY)
DIRS17  lda ITR_M2,x : jsr PET2SCREEN : sta SCRN+680,x
        lda #MGRAY : sta CRAM+680,x
        dex : bpl DIRS17

        ldx #39    ; row 18: warning (LTRED)
DIRS18  lda ITR_M3,x : jsr PET2SCREEN : sta SCRN+720,x
        lda #LTRED : sta CRAM+720,x
        dex : bpl DIRS18

        ldx #39    ; row 19: blank (DGRAY)
DIRS19  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+760,x
        lda #DGRAY : sta CRAM+760,x
        dex : bpl DIRS19

        ldx #39    ; row 20: bottom border (DGRAY)
DIRS20  lda SCR_BORDER_BOTTOM,x : jsr PET2SCREEN : sta SCRN+800,x
        lda #DGRAY : sta CRAM+800,x
        dex : bpl DIRS20

        lda #DGRAY : ldx #12 : ldy #20 : jsr FRAME_EDGES

        ldx #39    ; row 24: the help hint
DIF1    lda TXT_F1HELP,x : jsr PET2SCREEN : sta SCRN+960,x
        lda #MGRAY : sta CRAM+960,x
        dex : bpl DIF1
        jsr BLINK_ON
        rts

; =============================================================================
; Blink helpers — intro prompt
; =============================================================================
BLINK_ON
        ldx #39
BLON    lda TXT_PRESS,x
        jsr PET2SCREEN
        sta SCRN+880,x
        lda #WHITE : sta CRAM+880,x
        dex
        bpl BLON
        rts

BLINK_OFF
        ldx #39
BLOFF   lda #CH_SPC
        sta SCRN+880,x
        dex
        bpl BLOFF
        rts

; =============================================================================
; Intro strings — all exactly 40 bytes
; =============================================================================
ITR_AUTH    !pet "release 1, 2026 by johan berntsson"
ITR_AUTH_LEN = * - ITR_AUTH
ITR_TAG     !pet G_VERT_BAR, "  infiltrate. subvert. stop launch.   ", G_VERT_BAR
ITR_M1      !pet G_VERT_BAR, "  mission: abort launch sequence      ", G_VERT_BAR
ITR_M2      !pet G_VERT_BAR, "  location: titan missile complex     ", G_VERT_BAR
ITR_M3      !pet G_VERT_BAR, "  warning: launch in t-minus "
ITR_HRS     !pet "5 hours  ", G_VERT_BAR    ; (LVL_NEXT patches the digit)

TXT_PRESS   !pet "         press fire to start            "
TXT_F1HELP  !pet "              f1 for help               "
