; =============================================================================
; POPUP STATE (GAME_STATE = 6)
; =============================================================================
; Small popup box shown over the room art (rows 8-13; room/HUD/status stay
; visible around it) — used both for "found item" messages (SETUP_SEARCH,
; space key) and the locked room 2 exit door (SETUP_DOOR_LOCKED). Time and
; robots are paused for free: DO_GAME (and hence TICK_CLOCK/TICK_ROBOT)
; simply isn't called while GAME_STATE=6.
; =============================================================================

; ---------------------------------------------------------------------------
; DO_POPUP — called each frame in state 6
; ---------------------------------------------------------------------------
DO_POPUP
        jsr GETIN
        beq POPUPDONE
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$07 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        jsr UPDATE_SPRITE1
        jsr UPDATE_SPRITE2
POPUPDONE jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; SETUP_SEARCH — "found item" popup. Called via jsr from READ_KEYS when
; searching at a spot with something to find. Caller has already checked
; position/CARD_RED; this just marks the card found and shows the popup.
; ---------------------------------------------------------------------------
SETUP_SEARCH
        lda #1 : sta CARD_RED
        lda #<SBOX_MSG_FOUND : sta PTR
        lda #>SBOX_MSG_FOUND : sta PTR+1
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
; PTR/PTR+1 (must be exactly 40 PETSCII bytes), switch to state 6.
; ---------------------------------------------------------------------------
SHOW_POPUP
        lda #6 : sta GAME_STATE
        lda #$00 : sta VIC_SPEN

        ldx #39
SPROW8  lda SBOX_TOP,x : jsr PET2SCREEN : sta SCRN+8*40,x
        lda #LTGREEN : sta CRAM+8*40,x
        dex : bpl SPROW8

        ldx #39
SPROW9  lda SBOX_BLK,x : jsr PET2SCREEN : sta SCRN+9*40,x
        lda #LTGREEN : sta CRAM+9*40,x
        dex : bpl SPROW9

        ldy #39
SPROW10 lda (PTR),y : jsr PET2SCREEN : sta SCRN+10*40,y
        lda #YELLOW : sta CRAM+10*40,y
        dey : bpl SPROW10

        ldx #39
SPROW11 lda SBOX_BLK,x : jsr PET2SCREEN : sta SCRN+11*40,x
        lda #LTGREEN : sta CRAM+11*40,x
        dex : bpl SPROW11

        ldx #39
SPROW12 lda SBOX_HNT,x : jsr PET2SCREEN : sta SCRN+12*40,x
        lda #DGRAY : sta CRAM+12*40,x
        dex : bpl SPROW12

        ldx #39
SPROW13 lda SBOX_BOT,x : jsr PET2SCREEN : sta SCRN+13*40,x
        lda #LTGREEN : sta CRAM+13*40,x
        dex : bpl SPROW13
        rts

; =============================================================================
; Popup strings — all exactly 40 bytes
; =============================================================================
SBOX_TOP        !pet "    +------------------------------+    "
SBOX_BLK        !pet "    |                              |    "
SBOX_MSG_FOUND  !pet "    |    red access card found!    |    "
SBOX_MSG_LOCKED !pet "    |         door locked!          |    "
SBOX_HNT        !pet "    |        press any key         |    "
SBOX_BOT        !pet "    +------------------------------+    "
