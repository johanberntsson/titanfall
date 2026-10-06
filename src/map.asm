; =============================================================================
; MAP STATE (GAME_STATE = 5)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_MAP — called each frame in state 5
; ---------------------------------------------------------------------------
DO_MAP
        jsr GETIN
        bne MAP_GO
        lda JOY_NEW : and #$10          ; or joystick fire
        beq MAPDONE
MAP_GO
        lda #1 : sta GAME_STATE
        lda #0 : sta $C6
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
MAPDONE jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; SETUP_MAP — draw map screen, switch to state 5
; Called via jsr from READ_KEYS when M pressed.
; ---------------------------------------------------------------------------
SETUP_MAP
        lda #5 : sta GAME_STATE
        lda #$00 : sta VIC_SPEN

        jsr CLEAR_ROOM

        ; Row 8: title
        ldx #39
SMRT8   lda MAP_R8,x : jsr PET2SCREEN : sta SCRN+8*40,x
        lda #YELLOW : sta CRAM+8*40,x
        dex : bpl SMRT8

        ; Row 9: top border
        ldx #39
SMRT9   lda MAP_R9,x : jsr PET2SCREEN : sta SCRN+9*40,x
        lda #DGRAY : sta CRAM+9*40,x
        dex : bpl SMRT9

        ; Row 10: room name row
        ldx #39
SMRT10  lda MAP_R10,x : jsr PET2SCREEN : sta SCRN+10*40,x
        lda #DGRAY : sta CRAM+10*40,x
        dex : bpl SMRT10

        ; Row 11: connection row 1
        ldx #39
SMRT11  lda MAP_R11,x : jsr PET2SCREEN : sta SCRN+11*40,x
        lda #DGRAY : sta CRAM+11*40,x
        dex : bpl SMRT11

        ; Row 12: connection row 2
        ldx #39
SMRT12  lda MAP_R12,x : jsr PET2SCREEN : sta SCRN+12*40,x
        lda #DGRAY : sta CRAM+12*40,x
        dex : bpl SMRT12

        ; Row 13: bottom border (exit gap in room 2)
        ldx #39
SMRT13  lda MAP_R13,x : jsr PET2SCREEN : sta SCRN+13*40,x
        lda #DGRAY : sta CRAM+13*40,x
        dex : bpl SMRT13

        ; Row 14: exit arrow below room 2
        ldx #39
SMRT14  lda MAP_R14,x : jsr PET2SCREEN : sta SCRN+14*40,x
        lda #WHITE : sta CRAM+14*40,x
        dex : bpl SMRT14

        ; Row 15: "exit" label
        ldx #39
SMRT15  lda MAP_R15,x : jsr PET2SCREEN : sta SCRN+15*40,x
        lda #WHITE : sta CRAM+15*40,x
        dex : bpl SMRT15

        ; Row 17: key prompt
        ldx #39
SMRT17  lda MAP_R17,x : jsr PET2SCREEN : sta SCRN+17*40,x
        lda #MGRAY : sta CRAM+17*40,x
        dex : bpl SMRT17

        ; Colour connection passage (cols 13-20) on rows 11-12 in CYAN
        ldx #7
SMCN11  lda #CYAN : sta CRAM+11*40+13,x : dex : bpl SMCN11
        ldx #7
SMCN12  lda #CYAN : sta CRAM+12*40+13,x : dex : bpl SMCN12

        ; Highlight the current room's box in LTGREEN. The box position/size
        ; comes from the MAPHL_* tables (map_view in titan.yaml) — the map
        ; background art above is still hand-drawn, so a new room needs both
        ; a map_view entry and matching art in the MAP_R* strings.
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

; =============================================================================
; Map strings — all exactly 40 bytes
; =============================================================================
MAP_R8   !pet "      * sector map *                    "
MAP_R9
        !pet "  ", G_RD_UL
        !fill 10, G_HORIZ_BAR
        !pet G_RD_UR, "      ", G_RD_UL
        !fill 10, G_HORIZ_BAR
        !pet G_RD_UR, "        "
MAP_R10  !pet "  ", G_VERT_BAR, "  room 1  ", G_VERT_BAR, "      ", G_VERT_BAR, "  room 2  ", G_VERT_BAR, "        "
MAP_R11                                 ; corridor top: walls turn into it
        !pet "  ", G_VERT_BAR, "          ", G_RD_LL
        !fill 6, G_HORIZ_BAR
        !pet G_RD_LR, "          ", G_VERT_BAR, "        "
MAP_R12                                 ; corridor bottom
        !pet "  ", G_VERT_BAR, "          ", G_RD_UL
        !fill 6, G_HORIZ_BAR
        !pet G_RD_UR, "          ", G_VERT_BAR, "        "
MAP_R13
        !pet "  ", G_RD_LL
        !fill 10, G_HORIZ_BAR
        !pet G_RD_LR, "      ", G_RD_LL
        !fill 4, G_HORIZ_BAR
        !pet "  "
        !fill 4, G_HORIZ_BAR
        !pet G_RD_LR, "        "
MAP_R14  !pet "                         ", G_VERT_BAR, G_VERT_BAR, "             "
MAP_R15  !pet "                        exit            "
MAP_R17  !pet "     press any key to return            "
