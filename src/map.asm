; =============================================================================
; MAP STATE (GAME_STATE = 5)
; =============================================================================

; ---------------------------------------------------------------------------
; DO_MAP — called each frame in state 5. Fire (or any key) goes back to the
; terminal the map was opened from, with "view map" still selected.
; ---------------------------------------------------------------------------
DO_MAP
        jsr GETIN
        bne MAP_GO
        lda JOY_NEW : and #$10          ; or joystick fire
        beq MAPDONE
MAP_GO
        lda #0 : sta $C6
        jsr SETUP_TERMINAL
MAPDONE jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; SETUP_MAP — draw map screen, switch to state 5
; Called via jsr from the terminal's "view map" entry.
; ---------------------------------------------------------------------------
SETUP_MAP
        lda #5 : sta GAME_STATE
        lda #$00 : sta VIC_SPEN

        jsr CLEAR_ROOM
        lda #<MAP_ROWS : ldy #>MAP_ROWS : jsr DRAW_ROWS

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

; Rows of the map screen: (screen row, colour, string), for DRAW_ROWS
MAP_ROWS
        !byte 8,  YELLOW, <MAP_R8,  >MAP_R8        ; title
        !byte 9,  DGRAY,  <MAP_R9,  >MAP_R9        ; top border
        !byte 10, DGRAY,  <MAP_R10, >MAP_R10       ; room names
        !byte 11, DGRAY,  <MAP_R11, >MAP_R11       ; connection row 1
        !byte 12, DGRAY,  <MAP_R12, >MAP_R12       ; connection row 2
        !byte 13, DGRAY,  <MAP_R13, >MAP_R13       ; bottom border (exit gap)
        !byte 14, WHITE,  <MAP_R14, >MAP_R14       ; exit arrow
        !byte 15, WHITE,  <MAP_R15, >MAP_R15       ; "exit" label
        !byte 17, MGRAY,  <MAP_R17, >MAP_R17       ; prompt
        !byte $FF

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
MAP_R17  !pet "     press fire to return               "
