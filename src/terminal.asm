; =============================================================================
; TERMINAL STATE (GAME_STATE = 3)
; =============================================================================
; Drone list screen row addresses (equates, not data)
TERM_ROW0 = SCRN + 8*40
TERM_ROW1 = SCRN + 9*40
TERM_ROW2 = SCRN + 10*40
TERM_ROW3 = SCRN + 12*40
TERM_COL0 = CRAM + 8*40
TERM_COL1 = CRAM + 9*40
TERM_COL2 = CRAM + 10*40
TERM_COL3 = CRAM + 12*40
TERM_MSGROW = SCRN + 16*40

; ---------------------------------------------------------------------------
; CLEAR_ROOM — blank rows 2-23 (SCRN+80..SCRN+959). Leaves HUD and footer.
; ---------------------------------------------------------------------------
CLEAR_ROOM
        lda #<(SCRN+80) : sta PTR  : lda #>(SCRN+80) : sta PTR+1
        ldx #3 : ldy #0
CRMSPG  lda #CH_SPC : sta (PTR),y
        iny : bne CRMSPG
        inc PTR+1 : dex : bne CRMSPG
        ldy #0
CRMSTAIL lda #CH_SPC : sta (PTR),y
        iny : cpy #112 : bcc CRMSTAIL
        lda #<(CRAM+80) : sta PTR  : lda #>(CRAM+80) : sta PTR+1
        ldx #3 : ldy #0
CRMCPG  lda #DGRAY : sta (PTR),y
        iny : bne CRMCPG
        inc PTR+1 : dex : bne CRMCPG
        ldy #0
CRMCTAIL lda #DGRAY : sta (PTR),y
        iny : cpy #112 : bcc CRMCTAIL
        rts

; ---------------------------------------------------------------------------
; SETUP_TERMINAL — draw terminal screen, switch to state 3
; Called via jsr from READ_KEYS when T pressed near terminal.
; ---------------------------------------------------------------------------
SETUP_TERMINAL
        lda #3 : sta GAME_STATE
        lda #0 : sta TERM_SEL
        lda #0 : sta TERM_TMR
        lda #$00 : sta VIC_SPEN

        jsr CLEAR_ROOM

        ; Row 4: top border
        ldx #39
TSETB1  lda TBOX_TOP,x : sta SCRN+160,x
        lda #LTGREEN : sta CRAM+160,x
        dex : bpl TSETB1

        ; Row 5: title
        ldx #39
TSETB2  lda TBOX_TTL,x : sta SCRN+200,x
        lda #LTGREEN : sta CRAM+200,x
        dex : bpl TSETB2

        ; Row 6: subtitle
        ldx #39
TSETB3  lda TBOX_SUB,x : sta SCRN+240,x
        lda #GREEN : sta CRAM+240,x
        dex : bpl TSETB3

        ; Row 7: blank interior
        ldx #39
TSETB4  lda TBOX_BLK,x : sta SCRN+280,x
        lda #GREEN : sta CRAM+280,x
        dex : bpl TSETB4

        ; Rows 8-10: drone entries
        ldx #39
TSETD0  lda TBOX_D0,x : sta TERM_ROW0,x
        lda #GREEN : sta TERM_COL0,x
        dex : bpl TSETD0
        ldx #39
TSETD1  lda TBOX_D1,x : sta TERM_ROW1,x
        lda #GREEN : sta TERM_COL1,x
        dex : bpl TSETD1
        ldx #39
TSETD2  lda TBOX_D2,x : sta TERM_ROW2,x
        lda #DGRAY : sta TERM_COL2,x
        dex : bpl TSETD2

        ; Row 11: blank
        ldx #39
TSETB5  lda TBOX_BLK,x : sta SCRN+440,x
        lda #GREEN : sta CRAM+440,x
        dex : bpl TSETB5

        ; Row 12: logoff entry
        ldx #39
TSETD3  lda TBOX_D3,x : sta TERM_ROW3,x
        lda #GREEN : sta TERM_COL3,x
        dex : bpl TSETD3

        ; Row 13: blank
        ldx #39
TSETB6  lda TBOX_BLK,x : sta SCRN+520,x
        lda #GREEN : sta CRAM+520,x
        dex : bpl TSETB6

        ; Row 14: key hint
        ldx #39
TSETB7  lda TBOX_HNT,x : sta SCRN+560,x
        lda #DGRAY : sta CRAM+560,x
        dex : bpl TSETB7

        ; Row 15: bottom border
        ldx #39
TSETB8  lda TBOX_BOT,x : sta SCRN+600,x
        lda #LTGREEN : sta CRAM+600,x
        dex : bpl TSETB8

        ; Clear message row (row 16)
        ldx #39
TSETM   lda #CH_SPC : sta TERM_MSGROW,x
        dex : bpl TSETM

        jsr TERM_DRAW_SEL
        rts

; ---------------------------------------------------------------------------
; DO_TERMINAL — called each frame in state 3
; ---------------------------------------------------------------------------
DO_TERMINAL
        ; GETIN returns PETSCII: F7=$88, Return=$0D, cursor up=$91, dn=$11
        jsr GETIN
        beq TERM_DONE
        cmp #$88 : beq TERM_ABORT
        cmp #$0D : beq TERM_LINK
        cmp #$85 : beq TERM_LINK
        cmp #$91 : beq TERM_UP
        cmp #$11 : beq TERM_DOWN
        bne TERM_DONE

TERM_UP
        lda TERM_SEL : beq TERM_DONE
        dec TERM_SEL
        jsr TERM_DRAW_SEL
        bne TERM_DONE

TERM_DOWN
        lda TERM_SEL : cmp #3 : bcs TERM_DONE
        inc TERM_SEL
        jsr TERM_DRAW_SEL
        bne TERM_DONE

TERM_LINK
        lda TERM_SEL : cmp #3 : beq TERM_LOGOFF
        cmp #2 : beq TERM_LOCKED
        ldx #39
TLINK1  lda TMSG_OK,x : sta TERM_MSGROW,x
        lda #LTGREEN : sta CRAM+(16*40),x
        dex : bpl TLINK1
        bne TERM_DONE

TERM_LOCKED
        ldx #39
TLOCK1  lda TMSG_LCK,x : sta TERM_MSGROW,x
        lda #LTRED : sta CRAM+(16*40),x
        dex : bpl TLOCK1
        bne TERM_DONE

TERM_LOGOFF
TERM_ABORT
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$03 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_SPRITE1

TERM_DONE
        jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; TERM_DRAW_SEL — redraw all 4 rows, highlight selected one
; ---------------------------------------------------------------------------
TERM_DRAW_SEL
        ldx #39
        lda TERM_SEL : bne TDSEL1
        lda #LTGREEN : !byte $2C
TDSEL1  lda #GREEN
        sta TERM_COL0,x : dex : bpl TDSEL1

        ldx #39
        lda TERM_SEL : cmp #1 : bne TDSEL2
        lda #LTGREEN : !byte $2C
TDSEL2  lda #GREEN
        sta TERM_COL1,x : dex : bpl TDSEL2

        ldx #39
TDSEL3  lda #DGRAY : sta TERM_COL2,x : dex : bpl TDSEL3

        ldx #39
        lda TERM_SEL : cmp #3 : bne TDSEL4
        lda #LTGREEN : !byte $2C
TDSEL4  lda #GREEN
        sta TERM_COL3,x : dex : bpl TDSEL4

        lda #CH_SPC
        sta TERM_ROW0+3
        sta TERM_ROW1+3
        sta TERM_ROW2+3
        sta TERM_ROW3+3
        lda #$3E                        ; PETSCII '>'
        ldx TERM_SEL
        beq TDSELA
        cpx #1 : beq TDSELB
        cpx #2 : beq TDSELC
        sta TERM_ROW3+3 : bne TDSELX
TDSELA  sta TERM_ROW0+3 : bne TDSELX
TDSELB  sta TERM_ROW1+3 : bne TDSELX
TDSELC  sta TERM_ROW2+3
TDSELX  rts

; =============================================================================
; Terminal strings — all exactly 40 bytes
; =============================================================================
TBOX_TOP  !pet "+--------------------------------------+"
TBOX_TTL  !pet "|  * sector drone network - terminal   |"
TBOX_SUB  !pet "|  access verified. select unit:       |"
TBOX_BLK  !pet "|                                      |"
TBOX_D0   !pet "|   [1] bot-7741  loader    available  |"
TBOX_D1   !pet "|   [2] bot-3312  splicer   available  |"
TBOX_D2   !pet "|   [3] bot-9901  centurion  locked    |"
TBOX_D3   !pet "|   [ ] logoff                         |"
TBOX_HNT  !pet "|   return=select   f7=exit            |"
TBOX_BOT  !pet "+--------------------------------------+"
TMSG_OK   !pet "  proxy link established. unit active   "
TMSG_LCK  !pet "  access denied. unit locked by titan.  "
