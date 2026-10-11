; =============================================================================
; THE LAUNCH INTERLOCK — one room (ILK_ROOM, art.interlock in titan.yaml):
; NUM_SLOTS key slots (SLOT_X/Y, their art SLOT_ART_n), as many nested
; barrier layers (tiles LT_X/Y/N, art LAYER_ART_n; layer 0 is the outermost)
; and the release console (CONSOLE_X/Y) in the middle. All start solid.
; The human walks into a slot carrying a launch key (ITEM_LKEY): the key is
; used up, the slot lights (CFG_SLOT_LIT) and the next layer opens (ILK_N
; counts them) — any slot, any order. Once the innermost layer is open the
; console is in reach: walking into it opens the room's sealed: door to the
; silo (ILK_DOOR, DOOR_UNLOCK in game.asm). The state survives deaths and
; room resets (like an opened door); only a new game (ILK_RESET) closes it.
; =============================================================================

; ILK_TOUCH — TRY_MOVE (game.asm) jumps here when the human's move into
; NEWX/NEWY in CUR_ROOM is blocked by a solid tile. Carry clear = a plain
; wall (TRY_MOVE's old answer); carry set = handled (a key turned, the
; console released, or a popup). Clobbers A/X/Y/NEWX/NEWY/PTR/PTR2/TMP2.
ILK_TOUCH
        lda CUR_ROOM : cmp #ILK_ROOM : bne ITNO
        lda NEWX : cmp #CONSOLE_X : bne ITSLOT
        lda NEWY : cmp #CONSOLE_Y : bne ITSLOT
        ldx #ILK_DOOR                    ; the console
        lda DOOR_OPEN,x : bne ITNO       ; released already
        jsr DOOR_UNLOCK                  ; the silo door opens (green flash)
        jsr SETUP_RELEASED
        sec : rts
ITSLOT  ldx #0
ITSL    cpx #NUM_SLOTS : bcs ITNO
        lda SLOT_X,x : cmp NEWX : bne ITSN
        lda SLOT_Y,x : cmp NEWY : beq ITHIT
ITSN    inx : bne ITSL
ITNO    clc : rts
ITHIT   lda ILK_SLOT,x : bne ITNO        ; a key is turned in it already
        ldy #0                           ; carrying a launch key?
ITKL    cpy #NUM_ITEMS : bcs ITNOKEY
        lda ITEM_LKEY,y : beq ITKN
        lda ITEM_STATE,y : cmp #1 : beq ITKEY
ITKN    iny : bne ITKL
ITNOKEY jsr SETUP_NEED_KEY
        sec : rts
ITKEY   lda #2 : sta ITEM_STATE,y        ; the key stays in the slot
        lda #1 : sta ILK_SLOT,x
        ldx #0                           ; open layer ILK_N: its tiles walkable
ITLL    cpx #NUM_LTILES : bcs ITLD       ;  (and not searchable: plain floor)
        lda LT_N,x : cmp ILK_N : bne ITLN
        lda LT_X,x : sta NEWX
        lda LT_Y,x : sta NEWY
        lda #ILK_ROOM : jsr WALL_AT
        lda (PTR),y : and #$F0 : sta (PTR),y
ITLN    inx : bne ITLL
ITLD    inc ILK_N
        jsr ILK_PAINT                    ; the slot lit, the layer gone
        lda #GREEN : sta VIC_BRDCOL
        lda #15 : sta BFLASH
        sec : rts

; ILK_PAINT — over the room map's chars (ROOM_OVERLAYS, i.e. every redraw):
; in the interlock room, the slots with a key turned lit and the open
; layers floor. Clobbers A/X/Y/PTR/PTR2/TMP2.
ILK_PAINT
        lda CUR_ROOM : cmp #ILK_ROOM : bne IPOUT
        ldx #0
IPSL    cpx #NUM_SLOTS : bcs IPL
        lda ILK_SLOT,x : beq IPSN
        lda SLOT_ART_LO,x : sta PTR
        lda SLOT_ART_HI,x : sta PTR+1
        lda #CFG_SLOT_LIT : jsr ART_LIST ; (preserves X)
IPSN    inx : bne IPSL
IPL     ldx #0
IPLL    cpx ILK_N : bcs IPOUT
        lda LAYER_ART_LO,x : sta PTR
        lda LAYER_ART_HI,x : sta PTR+1
        lda #0 : jsr ART_LIST            ; floor
        inx : bne IPLL
IPOUT   rts

; ILK_RESET — SETUP_GAME: no keys turned, every layer tile solid again.
ILK_RESET
        lda #0 : sta ILK_N
        ldx #0
IRSL    cpx #NUM_SLOTS : bcs IRL
        sta ILK_SLOT,x
        inx : bne IRSL
IRL     ldx #0
IRLL    cpx #NUM_LTILES : bcs IRD
        lda LT_X,x : sta NEWX
        lda LT_Y,x : sta NEWY
        lda #ILK_ROOM : jsr WALL_AT
        lda (PTR),y : and #$F0 : ora #1 : sta (PTR),y
        inx : bne IRLL
IRD     rts
