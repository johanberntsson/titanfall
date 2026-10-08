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
