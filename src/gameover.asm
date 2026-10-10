; =============================================================================
; GAMEOVER STATE (GAME_STATE = 2)
; =============================================================================
; The clock has run out: the missile room is shown (no sprites), after a
; moment the missile (art.missile_tiles, MSL_* from genworld.py) lifts off
; and flies up off the top of the screen, one char row per step and
; speeding up, leaving the room art behind it. Then the "game over / press
; fire" popup, and fire (or any key) goes back to the intro.

GO_T0    = MSL_Y+2               ; the missile's top screen row before launch
GO_ROWS  = GO_T0+MSL_H           ; its path: screen rows 0..GO_ROWS-1, cols
                                 ;  MSL_X..; gone after GO_ROWS steps
GO_PAUSE = 60                    ; frames before lift-off
GO_D0    = 12                    ; step k waits 2*(GO_D0-k) frames, at least 4 (~3.5 s flight)
!if MSL_W*MSL_H > 127 { !error "missile too big for GO_DRAW's 7-bit index" }

GO_PH    !byte 0                 ; 0 = launching, 1 = popup up
GO_TMR   !byte 0
GO_K     !byte 0                 ; rows the missile has risen
GO_R     !byte 0                 ; GO_DRAW: screen row
GO_MI    !byte 0                 ; GO_DRAW: index of the row in MSL_CHARS, $FF none
GO_BG    !fill GO_ROWS*MSL_W, 0  ; the missile's path without the missile

; ---------------------------------------------------------------------------
; DO_GAMEOVER — called each frame in state 2
; ---------------------------------------------------------------------------
DO_GAMEOVER
        lda GO_PH : bne GOWAIT
        lda GO_K : beq GONOSND          ; flying: keep the rumble going
        lda SND_TMR : bne GONOSND       ;  (one effect lasts 2 s, the
        jsr SOUND_BOOM_START            ;  launch about 3.5)
GONOSND dec GO_TMR : bne GODONE
        lda GO_K : bne GOSTEP
        jsr SOUND_BOOM_START            ; lift-off rumble
GOSTEP  inc GO_K
        jsr GO_DRAW
        lda GO_K : cmp #GO_ROWS : beq GOPOP
        lda #2                          ; next step sooner: it speeds up
        ldx GO_K : cpx #GO_D0-2 : bcs GOSTD
        lda #GO_D0 : sec : sbc GO_K
GOSTD   asl : sta GO_TMR            ; x2: the flight takes ~3.5 s
GODONE  jmp MAIN_LOOP

GOPOP   lda #1 : sta GO_PH              ; gone: the popup
        lda #<SBOX_MSG_GAMEOVER : sta PTR
        lda #>SBOX_MSG_GAMEOVER : sta PTR+1
        jsr DRAW_POPUP_BOX
        lda #0 : sta $C6                ; keys pressed during the launch
        jmp MAIN_LOOP

GOWAIT  jsr GETIN                       ; any key but Space (Space is fire,
        beq GONK                        ;  merged into JOY_NEW by MAIN_LOOP;
        cmp #$20 : bne GO_GO            ;  as a key it could be a repeat)
GONK    lda JOY_NEW : and #$10          ; or joystick fire / Space
        beq GODONE
GO_GO
        jsr MUSIC_INIT                  ; the theme from the top (MUSIC_OFF still
        lda #0     : sta MUSIC_OFF       ;  set, so the IRQ can't play half-way)
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

; =============================================================================
; SETUP_GAMEOVER — show the missile room. Called via jsr from DO_GAME.
; =============================================================================
SETUP_GAMEOVER
        lda #2     : sta GAME_STATE
        lda #0     : sta $C6
        lda #0     : sta SND_TMR
        lda #1     : sta MUSIC_OFF       ; no music until the intro
        lda #$00   : sta $D404           ; all three voices off (the launch
        sta $D40B : sta $D412            ;  rumble is an effect: it still plays)
        lda #$00   : sta VIC_SPEN
        lda #RED   : sta VIC_BRDCOL
        lda #BLACK : sta VIC_BGCOL
        lda #0     : sta GO_PH : sta GO_K
        lda #GO_PAUSE : sta GO_TMR

        jsr CLS
        lda #<GO_CLOCK : sta PTR        ; row 0: the clock, run out
        lda #>GO_CLOCK : sta PTR+1
        lda #LTRED : sta TMP2
        lda #0 : jsr DRAW_ROW
        lda #MSL_ROOM : sta CUR_ROOM    ; the room as the game draws it
        jsr DRAW_ROOM                   ;  (opened doors, burnt-out lasers)
        lda #$00 : sta VIC_SPEN         ; (sprites stay off)
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2

        lda #0 : sta GO_R               ; GO_BG = the missile's path ...
        lda #<GO_BG : sta PTR
        lda #>GO_BG : sta PTR+1
GOBGR   lda GO_R : ldx #MSL_X : jsr CS_ROWP
        ldy #MSL_W-1
GOBGC   lda (PTR2),y : sta (PTR),y
        dey : bpl GOBGC
        jsr GO_NEXTROW : bne GOBGR
        ldx #MSL_W*MSL_H-1              ; ... with spaces where the missile is
GOBGM   lda MSL_CHARS,x : beq GOBGMN
        lda #CH_SPC : sta GO_BG+GO_T0*MSL_W,x
GOBGMN  dex : bpl GOBGM
        rts

; PTR += MSL_W (next GO_BG row), next GO_R; Z set after the last row
GO_NEXTROW
        lda PTR : clc : adc #MSL_W : sta PTR
        bcc GONRNC : inc PTR+1
GONRNC  inc GO_R
        lda GO_R : cmp #GO_ROWS
        rts

; -----------------------------------------------------------------------------
; GO_DRAW — draw the missile's path with the missile GO_K rows up: missile
; chars where it is, GO_BG everywhere else, colours from TILE_COLORS.
; -----------------------------------------------------------------------------
GO_DRAW
        lda #0 : sta GO_R
        lda #<GO_BG : sta PTR
        lda #>GO_BG : sta PTR+1
GODRR   lda GO_R : ldx #MSL_X : jsr CS_ROWP
        lda #$FF : sta GO_MI            ; the missile row here: GO_R-GO_T0+GO_K
        lda GO_R : clc : adc GO_K
        sec : sbc #GO_T0 : bcc GODRNM   ; (above the missile)
        cmp #MSL_H : bcs GODRNM         ; (below it)
        tax : lda #0                    ; * MSL_W
GODRMUL dex : bmi GODRMD
        clc : adc #MSL_W : bne GODRMUL
GODRMD  sta GO_MI
GODRNM  ldy #0
GODRC   lda GO_MI : bmi GODRB
        sty TMP : clc : adc TMP : tax
        lda MSL_CHARS,x : bne GODRP
GODRB   lda (PTR),y
GODRP   sta (PTR2),y
        tax : lda TILE_COLORS,x : sta (PTR3),y
        iny : cpy #MSL_W : bne GODRC
        jsr GO_NEXTROW : bne GODRR
        rts

; row 0 while the missile flies: the countdown clock, at zero
GO_CLOCK !pet "                                00:00:00"
!if * - GO_CLOCK != 40 { !error "GO_CLOCK must be 40 bytes" }
