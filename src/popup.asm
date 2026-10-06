; =============================================================================
; POPUP STATE (GAME_STATE = 6)
; =============================================================================
; Popup box shown over the room art (rows 8-13, columns 4-35; the
; room/HUD/status stay visible around it) — used both for "found item"
; messages (SETUP_SEARCH, at the end of a successful held-fire search, see
; SEARCH_TICK) and the locked room 2 exit door (SETUP_DOOR_LOCKED). Time and
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
; SEARCH_TICK — Impossible Mission style searching, from READ_KEYS every game
; frame. A fresh fire press (KEY_SPC) starts a search (human only, outside
; terminal zones — the terminal takes that press first); while fire stays
; held SRCH_TMR counts up and MOVE_PLAYER stands still. At SRCH_SHOW a small
; "searching" box appears by the player; at SRCH_DONE the tile is checked:
; an item there opens the big found-item popup (SETUP_SEARCH), otherwise the
; box turns into "nothing here" until fire is let go. Time and robots keep
; running throughout — searching is a risk.
; ---------------------------------------------------------------------------
SRCH_SHOW = 10                          ; frames held before "searching"
SRCH_DONE = SRCH_SHOW+50                ; ... and before the result

SEARCH_TICK
        lda PLAYER_MODE : bne SRCHEND    ; a driven robot can't search
        lda FIRE_PREV : beq SRCHEND      ; fire not held: stop
        lda SRCH_TMR : bne SRCHHOLD
        lda KEY_SPC : beq SRCHOUT        ; held over from before: no search
        lda #0 : sta PLR_ANIM            ; stand at rest while searching
SRCHHOLD
        lda SRCH_TMR : cmp #SRCH_DONE : bcs SRCHOUT   ; finished: just wait
        inc SRCH_TMR
        lda SRCH_TMR
        cmp #SRCH_SHOW : bne SRCHRES
        jsr SPOP_PLACE                   ; show "searching"
        lda #SP_SAVE : ldx #0 : jsr SPOP
        lda #SP_DRAW : ldx #SP_T_SEARCH-SP_TEXTS : jsr SPOP
        lda #1 : sta SRCH_ST
        rts
SRCHRES cmp #SRCH_DONE : bne SRCHOUT
        ldx #0                           ; a still-hidden item on this tile?
SRCHL   cpx #NUM_ITEMS : bcs SRCHNONE
        lda ITEM_STATE,x : bne SRCHN     ; already found/used
        lda ITEM_ROOM,x : cmp CUR_ROOM : bne SRCHN
        lda ITEM_X,x : cmp PLR_X : bne SRCHN
        lda ITEM_Y,x : cmp PLR_Y : bne SRCHN
        txa : pha
        jsr SPOP_HIDE
        pla : tax
        jmp SETUP_SEARCH                 ; X = item index
SRCHN   inx : bne SRCHL
SRCHNONE
        lda #SP_DRAW : ldx #SP_T_NOTHING-SP_TEXTS : jsr SPOP
        lda #2 : sta SRCH_ST
        rts
SRCHEND jsr SPOP_HIDE
        lda #0 : sta SRCH_TMR
SRCHOUT rts

; SPOP_HIDE — take the small search popup down (if shown), restoring the
; screen under it.
SPOP_HIDE
        lda SRCH_ST : beq SPHOUT
        lda #SP_REST : ldx #0 : jsr SPOP
        lda #0 : sta SRCH_ST
SPHOUT  rts

; SPOP_PLACE — put the small popup (SPOP_W x SPOP_H) centred over the
; player: above the sprite (bottom row = screen row 2y, the sprite covers
; rows 2y+1..2y+3), or below it (from row 2y+4) when there's no room above
; the playfield's top (row 2); columns clamped to the screen.
SPOP_PLACE
        lda PLR_Y : asl                  ; 2y
        cmp #5 : bcc SPPBELOW            ; 2y-3 < 2
        sbc #SPOP_H-1 : bcs SPPROW       ; (C set by the cmp)
SPPBELOW adc #SPOP_H                     ; (C clear)
SPPROW  sta SP_ROW
        lda PLR_X : asl : sec : sbc #(SPOP_W-1)/2-1   ; centre on col 2x+1
        bcs SPPC1 : lda #0
SPPC1   cmp #40-SPOP_W+1 : bcc SPPC2 : lda #40-SPOP_W
SPPC2   sta SP_COL
        rts

; SPOP — process the SPOP_W x SPOP_H cells at SP_ROW/SP_COL. A = mode:
; SP_SAVE copies screen+colour into SP_BUF, SP_REST copies them back (X=0
; for both), SP_DRAW draws the template at SP_TEXTS+X (border glyphs, codes
; >= $60, light green; text yellow). Preserves nothing but SP_ROW/SP_COL.
SP_SAVE = 0
SP_DRAW = 1
SP_REST = 2
SPOP_W  = 11
SPOP_H  = 4
SP_BUF  = $0340                         ; 2 x 44 bytes in the (unused) tape buffer

SPOP
        sta SP_MODE
        lda SP_ROW : sta SP_R
SPRL    lda SP_R : jsr ROW_PTR
        lda PTR2 : clc : adc SP_COL : sta PTR2 : sta PTR3
        lda PTR2+1 : adc #0 : sta PTR2+1
        clc : adc #>(CRAM-SCRN) : sta PTR3+1
        ldy #0
SPCL    lda SP_MODE : bne SPCL1
        lda (PTR2),y : sta SP_BUF,x                    ; save
        lda (PTR3),y : sta SP_BUF+SPOP_W*SPOP_H,x
        jmp SPCN
SPCL1   cmp #SP_DRAW : bne SPCL2
        lda SP_TEXTS,x : jsr PET2SCREEN : sta (PTR2),y ; draw
        lda SP_TEXTS,x : cmp #$60
        lda #YELLOW : bcc SPCC : lda #LTGREEN
SPCC    sta (PTR3),y
        jmp SPCN
SPCL2   lda SP_BUF,x : sta (PTR2),y                    ; restore
        lda SP_BUF+SPOP_W*SPOP_H,x : sta (PTR3),y
SPCN    inx : iny : cpy #SPOP_W : bne SPCL
        inc SP_R
        lda SP_R : sec : sbc SP_ROW : cmp #SPOP_H : bne SPRL
        rts

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

; Small search popup templates: SPOP_H rows of SPOP_W PETSCII bytes each
SP_TEXTS
SP_T_SEARCH
        !byte G_RD_UL : !fill SPOP_W-2, G_HORIZ_BAR : !byte G_RD_UR
        !pet G_VERT_BAR, "searching", G_VERT_BAR
        !pet G_VERT_BAR, "   ...   ", G_VERT_BAR
        !byte G_RD_LL : !fill SPOP_W-2, G_HORIZ_BAR : !byte G_RD_LR
SP_T_NOTHING
        !byte G_RD_UL : !fill SPOP_W-2, G_HORIZ_BAR : !byte G_RD_UR
        !pet G_VERT_BAR, " nothing ", G_VERT_BAR
        !pet G_VERT_BAR, "  here   ", G_VERT_BAR
        !byte G_RD_LL : !fill SPOP_W-2, G_HORIZ_BAR : !byte G_RD_LR

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
