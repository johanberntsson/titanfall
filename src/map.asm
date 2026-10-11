; =============================================================================
; MAP STATE (GAME_STATE = 5)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_MAP — called each frame in state 5. Fire (or any key) goes back to the
; terminal the map was opened from, with "view map" still selected.
; ---------------------------------------------------------------------------
DO_MAP
        jsr GETIN                       ; any key but Space (Space is fire,
        beq MAPNK                       ;  merged into JOY_NEW by MAIN_LOOP;
        cmp #$20 : bne MAP_GO           ;  as a key it could be a repeat)
MAPNK   lda JOY_NEW : and #$10          ; or joystick fire / Space
        beq MAPDONE
MAP_GO
        lda #0 : sta $C6
        jsr SETUP_TERMINAL
MAPDONE jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; SETUP_MAP — draw the sector map, switch to state 5. Called via jsr from the
; terminal's "view map" entry. The whole map (rows 2-23: boxes, corridors,
; exits, title, prompt) is generated from the doors by tools/genworld.py as
; MAP_SCR (screen codes) / MAP_COL (colours) in world.asm; this copies it,
; blanks the rooms the player hasn't been in yet (ROOM_SEEN; their box,
; MAPHL_*) and the corridors between two of them (MAPCOR_* — a corridor
; from a visited room into an unknown one stays, as a hint), and lights up
; the current room's box.
; ---------------------------------------------------------------------------
SETUP_MAP
        lda #5 : sta GAME_STATE
        lda #0 : sta $C6                ; empty the keyboard buffer (198)
        lda #$00 : sta VIC_SPEN

        lda #<MAP_SCR : sta PTR : lda #>MAP_SCR : sta PTR+1
        lda #<(SCRN+80) : sta PTR2 : lda #>(SCRN+80) : sta PTR2+1
        jsr MAPCOPY
        lda #<MAP_COL : sta PTR : lda #>MAP_COL : sta PTR+1
        lda #<(CRAM+80) : sta PTR2 : lda #>(CRAM+80) : sta PTR2+1
        jsr MAPCOPY

        ldx #0                          ; unvisited rooms: box blanked
SMRL    cpx #NUM_ROOMS : bcs SMRD
        lda ROOM_SEEN,x : bne SMRN
        lda MAPHL_LO,x : sta PTR
        lda MAPHL_HI,x : sec : sbc #>(CRAM-SCRN) : sta PTR+1
        lda MAPHL_W,x : sta TMP2
        lda MAPHL_H,x : sta TMP
        jsr MAP_BLANK
SMRN    inx : bne SMRL
SMRD    ldx #0                          ; corridors between two unvisited rooms
SMCL    cpx #NUM_MAPCOR : bcs SMCD
        ldy MAPCOR_A,x : lda ROOM_SEEN,y
        ldy MAPCOR_B,x : ora ROOM_SEEN,y : bne SMCN
        lda MAPCOR_LO,x : sta PTR
        lda MAPCOR_HI,x : sta PTR+1
        lda MAPCOR_W,x : sta TMP2
        lda MAPCOR_H,x : sta TMP
        jsr MAP_BLANK
SMCN    inx : bne SMCL
SMCD
        ldx CUR_ROOM
        lda MAPHL_LO,x : sta PTR
        lda MAPHL_HI,x : sta PTR+1
        lda MAPHL_H,x : sta TMP
SMHLROW ldy MAPHL_W,x
        dey
SMHLCOL lda #LTGREEN : sta (PTR),y
        dey : bpl SMHLCOL
        lda PTR : clc : adc #40 : sta PTR
        lda PTR+1 : adc #0 : sta PTR+1
        dec TMP : bne SMHLROW
        rts

; MAP_BLANK — spaces over a TMP2 wide, TMP high block of the screen at PTR.
; Preserves X.
MAP_BLANK
MBROW   ldy TMP2 : dey
        lda #CH_SPC
MBCOL   sta (PTR),y
        dey : bpl MBCOL
        lda PTR : clc : adc #40 : sta PTR
        bcc MBNC : inc PTR+1
MBNC    dec TMP : bne MBROW
        rts

; MAPCOPY — copy 22 rows (880 = 3*256+112 bytes) from PTR to PTR2.
MAPCOPY
        ldx #3 : ldy #0
MCPG    lda (PTR),y : sta (PTR2),y
        iny : bne MCPG
        inc PTR+1 : inc PTR2+1
        dex : bne MCPG
MCPT    lda (PTR),y : sta (PTR2),y
        iny : cpy #112 : bcc MCPT
        rts
