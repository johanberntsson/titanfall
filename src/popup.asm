; =============================================================================
; POPUP STATE (GAME_STATE = 6)
; =============================================================================
; Small popup box shown over the room art (rows 8-13, columns 4-35; the
; room/HUD/status stay visible around it) — used both for "found item" messages (SETUP_SEARCH,
; space key) and the locked room 2 exit door (SETUP_DOOR_LOCKED). Time and
; robots are paused for free: DO_GAME (and hence TICK_CLOCK/TICK_ROBOT)
; simply isn't called while GAME_STATE=6.
; =============================================================================

; ---------------------------------------------------------------------------
; DO_POPUP — called each frame in state 6. The popup stays up until a *fresh*
; space press: POPUP_ST tracks 0 = opening space still held, 1 = released
; (armed), 2 = new press seen; the popup closes when that press is released,
; so the closing space can't leak into READ_KEYS (terminal/search) either.
; Polls the CIA matrix directly — GETIN would see the opening keypress in
; the KERNAL buffer (filled by the raster IRQ's $EA31 tail) and close the
; popup on the very next frame.
; ---------------------------------------------------------------------------
DO_POPUP
        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRA : and #$10        ; joystick 2 fire (active low)
        beq DPDOWN
        lda #$7F : sta CIA1_PRA        ; space: col 7 (PA=$7F), row 4
        lda CIA1_PRB : and #$10        ; 0 = pressed (active low)
        beq DPDOWN
        ; space is up
        lda POPUP_ST : cmp #2 : beq DPCLOSE   ; full press+release done
        lda #1 : sta POPUP_ST          ; opening press released — armed
        jmp POPUPDONE
DPDOWN  ; space is down
        lda POPUP_ST : cmp #1 : bne POPUPDONE
        lda #2 : sta POPUP_ST          ; fresh press registered
        jmp POPUPDONE
DPCLOSE ; close the popup and resume the game
        lda #0 : sta $C6               ; drop buffered keypresses
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_ROBOT_SPRITES
POPUPDONE jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; SETUP_SEARCH — "found item" popup. Called via jsr from READ_KEYS with
; X = item index; the caller has already checked position and ITEM_STATE.
; Marks the item carried and shows its generated found-message (world.asm).
; ---------------------------------------------------------------------------
SETUP_SEARCH
        lda #1 : sta ITEM_STATE,x
        lda ITEM_MSG_LO,x : sta PTR
        lda ITEM_MSG_HI,x : sta PTR+1
        jmp SHOW_POPUP

; ---------------------------------------------------------------------------
; SETUP_DOOR_LOCKED — "door locked" popup. Called via jsr from MOVE_PLAYER
; when the room 2 exit is reached without the red access card.
; ---------------------------------------------------------------------------
SETUP_DOOR_LOCKED
        lda #<SBOX_MSG_LOCKED : sta PTR
        lda #>SBOX_MSG_LOCKED : sta PTR+1
        jmp SHOW_POPUP

; ---------------------------------------------------------------------------
; SHOW_POPUP — draw the popup box with the message row pointed to by
; PTR/PTR+1 (40 PETSCII bytes, of which columns 4-35 are drawn), switch to
; state 6.
; ---------------------------------------------------------------------------
SHOW_POPUP
        lda #6 : sta GAME_STATE
        lda #0 : sta POPUP_ST          ; opening space is still held down
        lda #$00 : sta VIC_SPEN

        lda #4  : sta DR_L : sta FR_L    ; draw only the box (columns
        lda #35 : sta DR_R : sta FR_R    ;  4-35): the room stays visible
        lda #YELLOW : sta TMP2           ; message row first (DRAW_ROWS
        lda #10 : jsr DRAW_ROW           ;  reuses PTR)
        lda #<SBOX_ROWS : ldy #>SBOX_ROWS : jsr DRAW_ROWS
        lda #0  : sta DR_L
        lda #39 : sta DR_R
        lda #LTGREEN : ldx #8 : ldy #13 : jmp FRAME_EDGES_LR

; Rows of the popup box around the message (row 10): for DRAW_ROWS
SBOX_ROWS
        !byte 8,  LTGREEN, <SBOX_TOP, >SBOX_TOP
        !byte 9,  LTGREEN, <SBOX_BLK, >SBOX_BLK
        !byte 11, LTGREEN, <SBOX_BLK, >SBOX_BLK
        !byte 12, DGRAY,   <SBOX_HNT, >SBOX_HNT
        !byte 13, LTGREEN, <SBOX_BOT, >SBOX_BOT
        !byte $FF

; =============================================================================
; Popup strings — all exactly 40 bytes
; =============================================================================
SBOX_TOP        !pet "    ", G_RD_UL
                !fill 30, G_HORIZ_BAR
                !pet G_RD_UR, "    "
SBOX_BLK        !pet "    ", G_VERT_BAR, "                              ", G_VERT_BAR, "    "
SBOX_MSG_LOCKED !pet "    ", G_VERT_BAR, "         door locked!         ", G_VERT_BAR, "    "
SBOX_HNT        !pet "    ", G_VERT_BAR, "          press fire          ", G_VERT_BAR, "    "
SBOX_BOT        !pet "    ", G_RD_LL
                !fill 30, G_HORIZ_BAR
                !pet G_RD_LR, "    "
