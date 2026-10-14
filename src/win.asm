; =============================================================================
; WIN STATE (GAME_STATE = 4)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_WIN — called each frame in state 4
; ---------------------------------------------------------------------------
DO_WIN
        jsr GETIN                       ; any key but Space (Space is fire,
        beq WINNK                       ;  merged into JOY_NEW by MAIN_LOOP;
        cmp #$20 : bne WIN_GO           ;  as a key it could be a repeat)
WINNK   lda JOY_NEW : and #$10          ; or joystick fire / Space
        beq WIN_DONE
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
WIN_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_WIN — the "you win / press fire" popup over the room (the missile
; room after the explosion), set GAME_STATE=4. Called via jsr from
; DO_EXPLODE (and from DOOR_ENTER for a leads_to: exit door).
; =============================================================================
SETUP_WIN
        jsr LVL_NEXT                    ; the next game is harder
        lda #4     : sta GAME_STATE
        lda #0     : sta $C6
        lda #0     : sta SND_TMR
        lda #$00   : sta $D404
        lda #$00   : sta VIC_SPEN
        lda #GREEN : sta VIC_BRDCOL
        lda #<SBOX_MSG_WIN : sta PTR
        lda #>SBOX_MSG_WIN : sta PTR+1
        jmp DRAW_POPUP_BOX

; =============================================================================
; EXPLOSION (GAME_STATE = 7) — the payoff before the win screen. SETUP_EXPLODE
; (jmp from BOLT_TICK when a player-fired bolt enters a win-target tile)
; turns the room's power-cell chars dark grey (PAINT_WIN), starts the explosion sound
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
        lda #DGRAY : jsr PAINT_WIN       ; the power cell burns out
        lda VIC_CR1 : sta EXP_D011
        lda $D016 : sta EXP_D016
        lda #EXPL_LEN : sta EXPL_TMR
        jmp SOUND_BOOM_START

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

; =============================================================================
; Replays after a win: every win (LVL_NEXT, from SETUP_WIN) takes an hour off
; the starting clock (START_H, read by SETUP_GAME; never below one hour) and
; moves the briefing to the next silo (17, 18, ...). The texts that say so
; are patched in place: the silo number and the hours in the cut scene
; (CS_SILO, CS_HRS) and the intro's "t-minus n hours" (ITR_HRS).
; The help screen's restart (Run/Stop) goes back to the first game's
; settings (LVL_RESET).
; =============================================================================
WINS    !byte 0                         ; games won since loading (max 82: silo 99)
START_H !byte CFG_CLK_H                 ; the starting clock's hours

LVL_NEXT
        lda WINS : cmp #82 : bcs LVLNH
        inc WINS
LVLNH   lda START_H : cmp #2 : bcc LVL_APPLY
        dec START_H
        jmp LVL_APPLY

; LVL_RESET — back to the first game's settings (help screen's restart)
LVL_RESET
        lda #0 : sta WINS
        lda #CFG_CLK_H : sta START_H
        ; fall through

; LVL_APPLY — patch the texts from WINS and START_H
LVL_APPLY
        lda WINS : clc : adc #17 : jsr DEC2  ; TMP = tens, TMP2 = ones
        lda TMP : sta CS_SILO
        lda TMP2 : sta CS_SILO+1
        lda START_H : cmp #10 : bcs LVLX
        ora #CH_0 : sta ITR_HRS          ; "t-minus n hours"
        ldx #$53                         ; PETSCII "s"
        cmp #CH_0+1 : bne LVLHRS
        ldx #" "                         ; "1 hour"
LVLHRS  stx ITR_HRS+6
        ; CS_HRS = the word for START_H+1 + " hours." + spaces
        ldx #0 : ldy START_H             ; skip START_H words ("one" is 0th)
LVLW1   cpy #0 : beq LVLW3
LVLW2   lda HR_WORDS,x : inx : cmp #0 : bne LVLW2
        dey : jmp LVLW1
LVLW3   ldy #0
LVLW4   lda HR_WORDS,x : beq LVLW5
        sta CS_HRS,y : inx : iny : bne LVLW4
LVLW5   ldx #0
LVLW6   lda HR_TAIL,x : sta CS_HRS,y
        iny : inx : cpx #7 : bcc LVLW6
        lda #" "
LVLW7   cpy #12 : bcs LVLX               ; pad to CS_HRS's 12 chars
        sta CS_HRS,y : iny : bne LVLW7
LVLX    rts

HR_WORDS !pet "one",0,"two",0,"three",0,"four",0,"five",0,"six",0,"seven",0,"eight",0,"nine",0,"ten",0
HR_TAIL  !pet " hours."
!if CFG_CLK_H >= 10 { !error "LVL_NEXT's texts assume a start under 10 hours" }

; REACT_KTL/KTH[h] = 89*256/START for a start of h hours (and CFG_CLK_M
; minutes): the reactor gauge's scale (TICK_REACTOR), so every start shows 10%
REACT_KL !byte 0
REACT_KH !byte 0
!macro react_k .h, .hi {
        !if .h*60 + CFG_CLK_M = 0 { !byte 0 } else {
        !if .hi = 0 { !byte <((REACT_SPAN*256 + (.h*60 + CFG_CLK_M) DIV 2) DIV (.h*60 + CFG_CLK_M)) } else {
        !byte >((REACT_SPAN*256 + (.h*60 + CFG_CLK_M) DIV 2) DIV (.h*60 + CFG_CLK_M)) } }
}
REACT_KTL
!for REACT_H, 0, CFG_CLK_H { +react_k REACT_H, 0 }
REACT_KTH
!for REACT_H, 0, CFG_CLK_H { +react_k REACT_H, 1 }
