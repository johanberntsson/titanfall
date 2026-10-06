; =============================================================================
; TERMINAL STATE (GAME_STATE = 3)
; =============================================================================
; The menu is built on entry: one row per robot in the current room (rows
; 8-9, from the generated ACT_TROW_* strings — at most 2 robots per room),
; then "view map" (row 11) and "logoff" (row 12). TM_ACT says what each
; entry does: an actor index (link to it), TM_MAP or TM_LOGOFF.
TERM_MAX    = 4
TM_MAP      = $FE
TM_LOGOFF   = $FF
TERM_RROW   = 8                         ; first robot row
TERM_MSGROW = 16                        ; message row under the box

TERM_N  !byte 0                         ; menu entries
TM_ACT  !fill TERM_MAX                  ; per entry: actor, TM_MAP, TM_LOGOFF
TM_ROW  !fill TERM_MAX                  ; per entry: screen row

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
; SETUP_TERMINAL — draw the terminal screen, switch to state 3. Called via
; jsr from READ_KEYS (fire/space in a terminal zone; TERM_SEL=0 first) and
; from DO_MAP on its way back (TERM_SEL still on "view map").
; ---------------------------------------------------------------------------
SETUP_TERMINAL
        lda #3 : sta GAME_STATE
        lda #$00 : sta VIC_SPEN
        jsr CLEAR_ROOM
        lda #<TERM_ROWS : ldy #>TERM_ROWS : jsr DRAW_ROWS

        ; robots in this room: one entry each, drawn over the "no units" row
        lda #0 : sta TERM_N
        ldx #0
TSAL    cpx #NUM_ACTORS : bcs TSADONE
        lda ACT_ROOM,x : cmp CUR_ROOM : bne TSAN
        ldy TERM_N
        txa : sta TM_ACT,y
        tya : clc : adc #TERM_RROW : sta TM_ROW,y
        inc TERM_N
        pha
        lda ACT_TROW_LO,x : sta PTR
        lda ACT_TROW_HI,x : sta PTR+1
        pla : jsr DRAW_ROW               ; colour comes from TERM_DRAW_SEL
        lda ACT_ALIVE,x : bne TSAN
        ldy #36                          ; destroyed: status at cols 28-36
TSDL    lda TST_DEAD-28,y : jsr PET2SCREEN : sta (PTR2),y
        dey : cpy #28 : bcs TSDL
TSAN    inx : bne TSAL
TSADONE
        ldy TERM_N                       ; then view map, logoff
        lda #TM_MAP : sta TM_ACT,y
        lda #11 : sta TM_ROW,y
        iny
        lda #TM_LOGOFF : sta TM_ACT,y
        lda #12 : sta TM_ROW,y
        iny : sty TERM_N
        jmp TERM_DRAW_SEL

; ---------------------------------------------------------------------------
; DO_TERMINAL — called each frame in state 3
; ---------------------------------------------------------------------------
DO_TERMINAL
        ; Joystick 2 first (fresh presses only): fire = select, up/down =
        ; move. Checked before GETIN so a character sitting in the KERNAL
        ; buffer (e.g. an emulator fire key that also types a key) can't
        ; route the frame into the keyboard branch and swallow the fire.
        ; Keyboard: Return = select, cursor up/down, F7 = leave. (Not
        ; space: the space that opened the terminal is still buffered.)
        lda JOY_NEW : and #$10 : bne TERM_FIRE
        lda JOY_NEW : and #$01 : bne TERM_UP
        lda JOY_NEW : and #$02 : bne TERM_DOWN
        jsr GETIN
        beq TERM_DONE
        cmp #$88 : beq TERM_ABORT
        cmp #$0D : beq TERM_FIRE
        cmp #$91 : beq TERM_UP
        cmp #$11 : beq TERM_DOWN
        bne TERM_DONE

TERM_UP
        lda TERM_SEL : beq TERM_DONE
        dec TERM_SEL
        jsr TERM_DRAW_SEL
        jmp TERM_DONE

TERM_DOWN
        ldx TERM_SEL : inx : cpx TERM_N : bcs TERM_DONE
        stx TERM_SEL
        jsr TERM_DRAW_SEL
        jmp TERM_DONE

TERM_FIRE
        ldy TERM_SEL : ldx TM_ACT,y
        cpx #TM_LOGOFF : beq TERM_ABORT
        cpx #TM_MAP : bne TERM_ROBOT
        jsr SETUP_MAP
        jmp TERM_DONE

; Link to robot X: drop straight back into gameplay, now piloting it
; (PLAYER_MODE = actor+1) — unless it's destroyed or locked.
TERM_ROBOT
        lda #<TMSG_DEAD : ldy #>TMSG_DEAD
        sta PTR : sty PTR+1
        lda ACT_ALIVE,x : beq TERM_MSG
        lda #<TMSG_LCK : sta PTR
        lda #>TMSG_LCK : sta PTR+1
        lda ACT_LOCK,x : bne TERM_MSG
        inx : stx PLAYER_MODE
TERM_ABORT
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
        jmp TERM_DONE

TERM_MSG                                ; PTR = message: show it in light red
        lda #LTRED : sta TMP2
        lda #TERM_MSGROW : jsr DRAW_ROW

TERM_DONE
        jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; TERM_DRAW_SEL — recolour every entry and put the '>' on the selected one:
; selected light green, destroyed robots dark grey, the rest green.
; ---------------------------------------------------------------------------
TERM_DRAW_SEL
        ldx #0
TDSL    cpx TERM_N : bcs TDSDONE
        lda TM_ROW,x : jsr ROW_PTR
        ldy #3
        cpx TERM_SEL : bne TDSNS
        lda #$3E : sta (PTR2),y          ; '>' (same code in PETSCII/screen)
        lda #LTGREEN : bne TDSPAINT
TDSNS   lda #CH_SPC : sta (PTR2),y
        lda TM_ACT,x : bmi TDSGRN        ; view map / logoff
        tay : lda ACT_ALIVE,y : bne TDSGRN
        lda #DGRAY : bne TDSPAINT
TDSGRN  lda #GREEN
TDSPAINT jsr PAINT_ROW
        inx : bne TDSL
TDSDONE lda #LTGREEN : ldx #4 : ldy #15 : jmp FRAME_EDGES  ; box rows 4-15

; Static rows of the terminal box: (screen row, colour, string), for DRAW_ROWS
TERM_ROWS
        !byte 4,  LTGREEN, <SCR_BORDER_TOP, >SCR_BORDER_TOP
        !byte 5,  LTGREEN, <TBOX_TTL, >TBOX_TTL
        !byte 6,  GREEN,   <TBOX_SUB, >TBOX_SUB
        !byte 7,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 8,  DGRAY,   <TBOX_NONE, >TBOX_NONE      ; robot rows draw over it
        !byte 9,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 10, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 11, GREEN,   <TBOX_MAP, >TBOX_MAP
        !byte 12, GREEN,   <TBOX_OFF, >TBOX_OFF
        !byte 13, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 14, DGRAY,   <TBOX_HNT, >TBOX_HNT
        !byte 15, LTGREEN, <SCR_BORDER_BOTTOM, >SCR_BORDER_BOTTOM
        !byte $FF

; =============================================================================
; Terminal strings — box rows and messages exactly 40 bytes
; =============================================================================
TBOX_TTL  !pet G_VERT_BAR, "  * sector drone network - terminal   ", G_VERT_BAR
TBOX_SUB  !pet G_VERT_BAR, "  access verified. select unit:       ", G_VERT_BAR
TBOX_NONE !pet G_VERT_BAR, "    no units in this sector           ", G_VERT_BAR
TBOX_MAP  !pet G_VERT_BAR, "    view map                          ", G_VERT_BAR
TBOX_OFF  !pet G_VERT_BAR, "    logoff                            ", G_VERT_BAR
TBOX_HNT  !pet G_VERT_BAR, "    fire=select    up/down=move       ", G_VERT_BAR
TST_DEAD  !pet "destroyed"
TMSG_LCK  !pet "  access denied. unit locked by titan.  "
TMSG_DEAD !pet "  unit destroyed. link unavailable.     "
