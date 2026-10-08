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
        ldy GOAL_ARG,x
        lda GOAL_KIND,x
        cmp #GOAL_FOUND : bne ORDN1
        lda ITEM_STATE,y : jmp ORDCHK
ORDN1   cmp #GOAL_OPENED : bne ORDN2
        lda DOOR_OPEN,y : jmp ORDCHK
ORDN2   cmp #GOAL_VISITED : bne ORDTODO
        lda ROOM_SEEN,y
ORDCHK  beq ORDTODO
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
