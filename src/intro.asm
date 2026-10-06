; =============================================================================
; INTRO STATE (GAME_STATE = 0)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_INTRO — called each frame in state 0
; ---------------------------------------------------------------------------
DO_INTRO
        jsr GETIN
        bne INTRO_GO
        lda JOY_NEW : and #$10          ; or joystick fire
        beq INTRO_NOBTN
INTRO_GO
        jsr SETUP_GAME
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
; DRAW_INTRO_SCREEN — title logo (rows 1-8, src/titanfall_title.asm) above
; the mission box (rows 10-19); the blinking prompt is row 22 (BLINK_ON).
; CLS + sprite pointers must be done by caller.
; =============================================================================
DRAW_INTRO_SCREEN
        ldx #0     ; rows 1-8: logo, raw screen codes + colours, two halves
DILOGO  lda TITLE_SCR,x     : sta SCRN+40,x
        lda TITLE_SCR+160,x : sta SCRN+40+160,x
        lda TITLE_COL,x     : sta CRAM+40,x
        lda TITLE_COL+160,x : sta CRAM+40+160,x
        inx : cpx #TITLE_ROWS*40/2 : bne DILOGO

        ldx #39    ; row 10: top border (DGRAY)
DIRS10  lda SCR_BORDER_TOP,x : jsr PET2SCREEN : sta SCRN+400,x
        lda #DGRAY : sta CRAM+400,x
        dex : bpl DIRS10

        ldx #39    ; row 11: blank (DGRAY)
DIRS11  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+440,x
        lda #DGRAY : sta CRAM+440,x
        dex : bpl DIRS11

        ldx #39    ; row 12: tagline (CYAN)
DIRS12  lda ITR_TAG,x : jsr PET2SCREEN : sta SCRN+480,x
        lda #CYAN : sta CRAM+480,x
        dex : bpl DIRS12

        ldx #39    ; row 13: separator (BLUE)
DIRS13  lda ITR_SEP,x : jsr PET2SCREEN : sta SCRN+520,x
        lda #BLUE : sta CRAM+520,x
        dex : bpl DIRS13

        ldx #39    ; row 14: blank (DGRAY)
DIRS14  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+560,x
        lda #DGRAY : sta CRAM+560,x
        dex : bpl DIRS14

        ldx #39    ; row 15: mission line 1 (MGRAY)
DIRS15  lda ITR_M1,x : jsr PET2SCREEN : sta SCRN+600,x
        lda #MGRAY : sta CRAM+600,x
        dex : bpl DIRS15

        ldx #39    ; row 16: mission line 2 (MGRAY)
DIRS16  lda ITR_M2,x : jsr PET2SCREEN : sta SCRN+640,x
        lda #MGRAY : sta CRAM+640,x
        dex : bpl DIRS16

        ldx #39    ; row 17: warning (LTRED)
DIRS17  lda ITR_M3,x : jsr PET2SCREEN : sta SCRN+680,x
        lda #LTRED : sta CRAM+680,x
        dex : bpl DIRS17

        ldx #39    ; row 18: blank (DGRAY)
DIRS18  lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+720,x
        lda #DGRAY : sta CRAM+720,x
        dex : bpl DIRS18

        ldx #39    ; row 19: bottom border (DGRAY)
DIRS19  lda SCR_BORDER_BOTTOM,x : jsr PET2SCREEN : sta SCRN+760,x
        lda #DGRAY : sta CRAM+760,x
        dex : bpl DIRS19

        lda #DGRAY : ldx #10 : ldy #19 : jsr FRAME_EDGES
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
ITR_TAG     !pet G_VERT_BAR, "  infiltrate. subvert. stop launch.   ", G_VERT_BAR
ITR_M1      !pet G_VERT_BAR, "  mission: abort launch sequence      ", G_VERT_BAR
ITR_M2      !pet G_VERT_BAR, "  location: titan missile complex     ", G_VERT_BAR
ITR_M3      !pet G_VERT_BAR, "  warning: launch in t-minus 5 hours  ", G_VERT_BAR

TXT_PRESS   !pet "        press any key to start          "
