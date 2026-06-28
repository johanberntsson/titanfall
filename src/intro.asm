; =============================================================================
; INTRO STATE (GAME_STATE = 0)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_INTRO — called each frame in state 0
; ---------------------------------------------------------------------------
DO_INTRO
        jsr GETIN
        beq INTRO_NOBTN
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
; DRAW_INTRO_SCREEN — draws intro box art. CLS + sprite pointers must be done
; by caller.
; =============================================================================
DRAW_INTRO_SCREEN
        ldx #39    ; row 3: top border (DGRAY)
DIRS03  lda SCR_BORDER,x : sta SCRN+120,x
        lda #DGRAY : sta CRAM+120,x
        dex : bpl DIRS03

        ldx #39    ; row 4: blank (DGRAY)
DIRS04  lda SCR_BLANK,x : sta SCRN+160,x
        lda #DGRAY : sta CRAM+160,x
        dex : bpl DIRS04

        ldx #39    ; row 5: title (PURPLE), * chars in YELLOW
DIRS05  lda ITR_TITLE,x : sta SCRN+200,x
        lda #PURPLE : sta CRAM+200,x
        dex : bpl DIRS05
        lda #YELLOW
        sta CRAM+205 : sta CRAM+207 : sta CRAM+209
        sta CRAM+224 : sta CRAM+226 : sta CRAM+228

        ldx #39    ; row 6: tagline (CYAN)
DIRS06  lda ITR_TAG,x : sta SCRN+240,x
        lda #CYAN : sta CRAM+240,x
        dex : bpl DIRS06

        ldx #39    ; row 7: separator (BLUE)
DIRS07  lda ITR_SEP,x : sta SCRN+280,x
        lda #BLUE : sta CRAM+280,x
        dex : bpl DIRS07

        ldx #39    ; row 8: blank (DGRAY)
DIRS08  lda SCR_BLANK,x : sta SCRN+320,x
        lda #DGRAY : sta CRAM+320,x
        dex : bpl DIRS08

        ldx #39    ; row 9: mission line 1 (MGRAY)
DIRS09  lda ITR_M1,x : sta SCRN+360,x
        lda #MGRAY : sta CRAM+360,x
        dex : bpl DIRS09

        ldx #39    ; row 10: mission line 2 (MGRAY)
DIRS10  lda ITR_M2,x : sta SCRN+400,x
        lda #MGRAY : sta CRAM+400,x
        dex : bpl DIRS10

        ldx #39    ; row 11: warning (LTRED)
DIRS11  lda ITR_M3,x : sta SCRN+440,x
        lda #LTRED : sta CRAM+440,x
        dex : bpl DIRS11

        ldx #39    ; row 12: blank (DGRAY)
DIRS12  lda SCR_BLANK,x : sta SCRN+480,x
        lda #DGRAY : sta CRAM+480,x
        dex : bpl DIRS12

        ldx #39    ; row 13: bottom border (DGRAY)
DIRS13  lda SCR_BORDER,x : sta SCRN+520,x
        lda #DGRAY : sta CRAM+520,x
        dex : bpl DIRS13

        jsr BLINK_ON
        rts

; =============================================================================
; Blink helpers — intro prompt
; =============================================================================
BLINK_ON
        ldx #39
BLON    lda TXT_PRESS,x
        sta SCRN+800,x
        lda #WHITE : sta CRAM+800,x
        dex
        bpl BLON
        rts

BLINK_OFF
        ldx #39
BLOFF   lda #CH_SPC
        sta SCRN+800,x
        dex
        bpl BLOFF
        rts

; =============================================================================
; Intro strings — all exactly 40 bytes
; =============================================================================
ITR_TITLE   !pet "|    * * *  titan fall  * * *          |"
ITR_TAG     !pet "|  infiltrate. subvert. stop launch.   |"
ITR_M1      !pet "|  mission: abort launch sequence      |"
ITR_M2      !pet "|  location: titan missile complex     |"
ITR_M3      !pet "|  warning: launch in t-minus 5 hours  |"

TXT_PRESS   !pet "        press any key to start          "
