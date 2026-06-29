; =============================================================================
; GAMEOVER STATE (GAME_STATE = 2)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_GAMEOVER — called each frame in state 2
; ---------------------------------------------------------------------------
DO_GAMEOVER
        jsr GETIN
        beq GO_NOBTN
        lda #0     : sta GAME_STATE
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$00   : sta VIC_SPEN
        lda #0     : sta BLINK_TMR : sta BLINK_ST
        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1
        jsr DRAW_INTRO_SCREEN
        jmp MAIN_LOOP

GO_NOBTN
        inc BLINK_TMR
        lda BLINK_TMR
        cmp #25
        bcc GO_DONE
        lda #0 : sta BLINK_TMR
        lda BLINK_ST
        bne GO_SHOW
        jsr GO_BLINK_OFF
        lda #1 : sta BLINK_ST
        jmp GO_DONE
GO_SHOW
        jsr GO_BLINK_ON
        lda #0 : sta BLINK_ST
GO_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_GAMEOVER — draw game over screen. Called via jsr from DO_GAME.
; =============================================================================
SETUP_GAMEOVER
        lda #2     : sta GAME_STATE
        lda #0     : sta $C6
        lda #0     : sta SND_TMR
        lda #$00   : sta $D404
        lda #$00   : sta $D418
        lda #$00   : sta VIC_SPEN
        lda #RED   : sta VIC_BRDCOL
        lda #BLACK : sta VIC_BGCOL
        lda #0     : sta BLINK_TMR : sta BLINK_ST

        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1

        ldx #39    ; row 3: top border (RED)
GOROW03 lda SCR_BORDER_TOP,x : jsr PET2SCREEN : sta SCRN+120,x
        lda #RED : sta CRAM+120,x
        dex : bpl GOROW03

        ldx #39    ; row 4: blank (RED)
GOROW04 lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+160,x
        lda #RED : sta CRAM+160,x
        dex : bpl GOROW04

        ldx #39    ; row 5: title (LTRED)
GOROW05 lda GO_TITLE,x : jsr PET2SCREEN : sta SCRN+200,x
        lda #LTRED : sta CRAM+200,x
        dex : bpl GOROW05
        lda #YELLOW
        sta CRAM+203 : sta CRAM+205 : sta CRAM+207
        sta CRAM+227 : sta CRAM+229 : sta CRAM+231

        ldx #39    ; row 6: blank (RED)
GOROW06 lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+240,x
        lda #RED : sta CRAM+240,x
        dex : bpl GOROW06

        ldx #39    ; row 7: separator (DGRAY)
GOROW07 lda ITR_SEP,x : jsr PET2SCREEN : sta SCRN+280,x
        lda #DGRAY : sta CRAM+280,x
        dex : bpl GOROW07

        ldx #39    ; row 8: operative terminated (WHITE)
GOROW08 lda GO_M1,x : jsr PET2SCREEN : sta SCRN+320,x
        lda #WHITE : sta CRAM+320,x
        dex : bpl GOROW08

        ldx #39    ; row 9: launch continues (LTRED)
GOROW09 lda GO_M2,x : jsr PET2SCREEN : sta SCRN+360,x
        lda #LTRED : sta CRAM+360,x
        dex : bpl GOROW09

        ldx #39    ; row 10: blank (RED)
GOROW10 lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+400,x
        lda #RED : sta CRAM+400,x
        dex : bpl GOROW10

        ldx #39    ; row 11: mission failed (YELLOW)
GOROW11 lda GO_M3,x : jsr PET2SCREEN : sta SCRN+440,x
        lda #YELLOW : sta CRAM+440,x
        dex : bpl GOROW11

        ldx #39    ; row 12: blank (RED)
GOROW12 lda SCR_BLANK,x : jsr PET2SCREEN : sta SCRN+480,x
        lda #RED : sta CRAM+480,x
        dex : bpl GOROW12

        ldx #39    ; row 13: bottom border (RED)
GOROW13 lda SCR_BORDER_BOTTOM,x : jsr PET2SCREEN : sta SCRN+520,x
        lda #RED : sta CRAM+520,x
        dex : bpl GOROW13

        jsr GO_BLINK_ON
        rts

; =============================================================================
; Blink helpers — game over prompt
; =============================================================================
GO_BLINK_ON
        ldx #39
GOBLON  lda TXT_GOPRESS,x
        jsr PET2SCREEN
        sta SCRN+640,x
        lda #YELLOW : sta CRAM+640,x
        dex
        bpl GOBLON
        rts

GO_BLINK_OFF
        ldx #39
GOBLOFF lda #CH_SPC
        sta SCRN+640,x
        dex
        bpl GOBLOFF
        rts

; =============================================================================
; Game over strings — all exactly 40 bytes
; =============================================================================
GO_TITLE    !pet G_VERT_BAR,"  * * *  security breach  * * *       ",G_VERT_BAR
GO_M1       !pet G_VERT_BAR,"  operative terminated                ",G_VERT_BAR
GO_M2       !pet G_VERT_BAR,"  titan launch sequence continues...  ",G_VERT_BAR
GO_M3       !pet G_VERT_BAR,"  your mission has failed             ",G_VERT_BAR

TXT_GOPRESS !pet "        press any key to retry          "
