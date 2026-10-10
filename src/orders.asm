; =============================================================================
; ORDERS — row 1, under the HUD: "orders: <goal>" for the current room.
; The goals come from titan.yaml (goal: per room, generated GOAL_* tables in
; world.asm): white while open, green with " - done" once the goal's
; condition holds (an item found, a keyed door opened, a room visited).
; DRAW_ORDERS runs every game frame (like DRAW_STATUS), so a find, an opened
; door or a room change shows at once. It also marks CUR_ROOM as visited.
; =============================================================================
DRAW_ORDERS
        ldx CUR_ROOM
        lda #1 : sta ROOM_SEEN,x
        jsr GOAL_DONE : beq ORDTODO
        lda GOALD_LO,x : sta PTR         ; done: " - done", green
        lda GOALD_HI,x : sta PTR+1
        lda #LTGREEN : bne ORDSET
ORDTODO lda GOAL_LO,x : sta PTR
        lda GOAL_HI,x : sta PTR+1
        lda #WHITE
ORDSET  sta TMP2
        ldy #GOAL_WIDTH-1
ORDGL   lda (PTR),y : jsr PET2SCREEN : sta SCRN+48,y
        lda TMP2 : sta CRAM+48,y
        dey : bpl ORDGL
        ldy #7
ORDLL   lda ORD_LBL,y : jsr PET2SCREEN : sta SCRN+40,y
        lda #YELLOW : sta CRAM+40,y
        dey : bpl ORDLL
        rts

ORD_LBL !pet "orders: "

; GOAL_DONE — X = room: A <> 0 (Z clear) if its goal is achieved; a room
; without a goal or without done: is never done. Preserves X; clobbers Y.
GOAL_DONE
        ldy GOAL_ARG,x
        lda GOAL_KIND,x
        cmp #GOAL_FOUND : bne GDN1
        lda ITEM_STATE,y : rts
GDN1    cmp #GOAL_OPENED : bne GDN2
        lda DOOR_OPEN,y : rts
GDN2    cmp #GOAL_VISITED : bne GDNO
        lda ROOM_SEEN,y : rts
GDNO    lda #0 : rts

; =============================================================================
; LEAVE_ROOM — DOOR_ENTER, just before a door takes the player out of
; CUR_ROOM. Unless the room's goal is done, the room is rolled back to how
; it started — its robots, lasers and crates (RESET_ROOM) — and the
; security codes spent in it on this visit come back (RESTORE_CODES), just
; like a death there: a room left in an unsolvable state (crates pushed into
; a corner, the robot that was needed destroyed) can be tried again, and
; the try didn't use up a code. Found items, opened doors and codes found
; on the visit are kept. Preserves X (the door).
; =============================================================================
LEAVE_ROOM
        txa : pha
        ldx CUR_ROOM
        jsr GOAL_DONE : bne LRKEEP
        jsr RESET_ROOM
        jsr RESTORE_CODES
LRKEEP  pla : tax
        rts
