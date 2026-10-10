; =============================================================================
; GATES AND PRESSURE PLATES — genworld.py lists the gate tiles
; (art.gate_tiles: GATE_ROOM/X/Y, their art cells ROOM_GATEART_n), the
; pressure plates (art.plate_tiles: PLATE_ROOM/X/Y) and the laser targets
; (art.target_tiles: TGT_ROOM/X/Y, ROOM_TGTART_n). A room has at most one
; gate (all its gate tiles); gate and target tiles start solid.
; GATE_STATE (per room): 0 closed, 1 held open (by the plates), 2 latched open
; for good (a laser hit its target, or the player walked into the held-open
; gate) -- only a new game (GATE_RESET) closes a latched gate again;
; RESET_ROOM (death, leaving an unfinished room) closes a held one
; (GATE_ROOMRESET).
; Plates ("hold"): the gate is open while every plate of the room is loaded
; -- by the human, a robot or a crate/mirror standing on it (LOADED_AT).
; When one is unloaded it closes, unless something stands in it.
; =============================================================================

; PLATE_TICK — every game frame (GAME_ALIVE): the plates of CUR_ROOM.
; Clobbers A/X/Y/NEWX/NEWY/PTR/PTR2/TMP/TMP2.
PLATE_TICK
        ldx CUR_ROOM
        lda GATE_STATE,x : cmp #2 : beq PTOUT    ; latched: nothing to do
        sta PT_ST
        lda #0 : sta PT_ANY
        lda #1 : sta PT_ALL
        ldx #0
PTL     cpx #NUM_PLATES : bcs PTLD
        lda PLATE_ROOM,x : cmp CUR_ROOM : bne PTN
        lda #1 : sta PT_ANY              ; the room has plates
        lda PLATE_X,x : sta NEWX
        lda PLATE_Y,x : sta NEWY
        jsr LOADED_AT : bcs PTN
        lda #0 : sta PT_ALL              ; an empty plate
PTN     inx : bne PTL
PTLD    lda PT_ANY : beq PTOUT           ; no plates in this room
        lda PT_ST : bne PTHELD
        lda PT_ALL : beq PTOUT           ; closed, not all loaded
        lda #1 : jsr GATE_OPEN           ; all loaded: open (held)
        lda #GREEN : sta VIC_BRDCOL
        lda #15 : sta BFLASH
PTOUT   rts
PTHELD  lda PLR_X : sta NEWX             ; held open: the player in the gate
        lda PLR_Y : sta NEWY             ;  latches it (so the far side can't
        jsr GATE_TILE_AT : bcc PTNOLAT   ;  shut behind them)
        ldx CUR_ROOM : lda #2 : sta GATE_STATE,x
        rts
PTNOLAT lda PT_ALL : bne PTOUT           ; still loaded
        jsr GATE_OCCUPIED : bcs PTOUT    ; a robot/crate in the gate: wait
        jmp GATE_CLOSE

PT_ST   !byte 0                          ; GATE_STATE of CUR_ROOM this tick
PT_ANY  !byte 0
PT_ALL  !byte 0                          ; 1 = every plate loaded

; LOADED_AT — NEWX/NEWY in CUR_ROOM: carry set if the human, a robot (alive
; or dying) or a crate/mirror stands there. Preserves X; clobbers A/Y.
LOADED_AT
        lda PLR_X : cmp NEWX : bne LANH
        lda PLR_Y : cmp NEWY : beq LAYES
LANH    ldy #0
LAACT   cpy #NUM_ACTORS : bcs LACR
        lda ACT_ALIVE,y : beq LAACTN
        lda ACT_ROOM,y : cmp CUR_ROOM : bne LAACTN
        lda ACT_X,y : cmp NEWX : bne LAACTN
        lda ACT_Y,y : cmp NEWY : beq LAYES
LAACTN  iny : bne LAACT
LACR    ldy #0
LACRL   cpy #NUM_CRATES : bcs LANO
        lda CRATE_ROOM,y : cmp CUR_ROOM : bne LACRN
        lda CRATE_X,y : cmp NEWX : bne LACRN
        lda CRATE_Y,y : cmp NEWY : beq LAYES
LACRN   iny : bne LACRL
LANO    clc : rts
LAYES   sec : rts

; GATE_TILE_AT — NEWX/NEWY: carry set if it's a gate tile of CUR_ROOM.
; Preserves X; clobbers A/Y.
GATE_TILE_AT
        ldy #0
GTAL    cpy #NUM_GATES : bcs GTANO
        lda GATE_ROOM,y : cmp CUR_ROOM : bne GTAN
        lda GATE_X,y : cmp NEWX : bne GTAN
        lda GATE_Y,y : cmp NEWY : beq GTAYES
GTAN    iny : bne GTAL
GTANO   clc : rts
GTAYES  sec : rts

; GATE_OCCUPIED — carry set if anyone/anything stands on a gate tile of
; CUR_ROOM. Clobbers A/X/Y/NEWX/NEWY.
GATE_OCCUPIED
        ldx #0
GOCL    cpx #NUM_GATES : bcs GOCNO
        lda GATE_ROOM,x : cmp CUR_ROOM : bne GOCN
        lda GATE_X,x : sta NEWX
        lda GATE_Y,x : sta NEWY
        jsr LOADED_AT : bcs GOCYES
GOCN    inx : bne GOCL
GOCNO   clc
GOCYES  rts

; GATE_OPEN — A = new GATE_STATE (1 held, 2 latched): open CUR_ROOM's gate:
; its tiles walkable, its art floor. GATE_CLOSE: closed again, solid, the
; gate's chars back from the room map.
GATE_OPEN
        ldx CUR_ROOM : sta GATE_STATE,x
        lda #0 : jsr GATE_SOLID
        jmp GATE_PAINT
GATE_CLOSE
        ldx CUR_ROOM : lda #0 : sta GATE_STATE,x
        lda #1 : jsr GATE_SOLID
        ldx CUR_ROOM
        lda ROOM_GATEART_LO,x : sta PTR
        lda ROOM_GATEART_HI,x : sta PTR+1
        lda #1 : jmp ART_LIST

; GATE_SOLID — A = 1 make CUR_ROOM's gate tiles solid, 0 walkable (also
; clears their searched/searchable bits: an open gate is plain floor).
GATE_SOLID
        sta GS_SET
        lda CUR_ROOM : sta GS_ROOM
GATE_SOLID_R                             ; (GS_ROOM/GS_SET preset)
        ldx #0
GSL     cpx #NUM_GATES : bcs GSD
        lda GATE_ROOM,x : cmp GS_ROOM : bne GSN
        lda GATE_X,x : sta NEWX
        lda GATE_Y,x : sta NEWY
        lda GS_ROOM : jsr WALL_AT
        lda (PTR),y : and #$F0 : ora GS_SET : sta (PTR),y
GSN     inx : bne GSL
GSD     rts

; TGT_SOLID — the same for the laser target tiles of GS_ROOM (GS_SET).
TGT_SOLID
        ldx #0
TSOL    cpx #NUM_TGTS : bcs TSOD
        lda TGT_ROOM,x : cmp GS_ROOM : bne TSON
        lda TGT_X,x : sta NEWX
        lda TGT_Y,x : sta NEWY
        lda GS_ROOM : jsr WALL_AT
        lda (PTR),y : and #$F0 : ora GS_SET : sta (PTR),y
TSON    inx : bne TSOL
TSOD    rts

GS_ROOM !byte 0
GS_SET  !byte 0

; GATE_RESET — SETUP_GAME: every gate closed and every laser target intact
; (solid) again.
GATE_RESET
        ldx #0
GRL     cpx #NUM_ROOMS : bcs GRD
        lda #0 : sta GATE_STATE,x
        stx GS_ROOM
        lda #1 : sta GS_SET
        jsr GATE_SOLID_R
        jsr TGT_SOLID
        ldx GS_ROOM : inx : bne GRL
GRD     rts

; GATE_ROOMRESET — end of RESET_ROOM (CRATE_RESET): a gate held open by the
; plates in a room being reset closes (its plates are being emptied); a
; latched one stays open.
GATE_ROOMRESET
        ldx #0
GRRL    cpx #NUM_ROOMS : bcs GRRD
        txa : jsr RS_MINE : bne GRRN
        lda GATE_STATE,x : cmp #1 : bne GRRN
        lda #0 : sta GATE_STATE,x
        stx GS_ROOM
        lda #1 : sta GS_SET
        jsr GATE_SOLID_R
        ldx GS_ROOM
GRRN    inx : bne GRRL
GRRD    rts

; GATE_PAINT — CUR_ROOM's gate as it is: an open gate's cells painted floor,
; and (latched) the destroyed laser target's too. The room map has them
; drawn closed/intact.
GATE_PAINT
        ldx CUR_ROOM
        lda GATE_STATE,x : beq GPOUT
        pha
        lda ROOM_GATEART_LO,x : sta PTR
        lda ROOM_GATEART_HI,x : sta PTR+1
        lda #0 : jsr ART_LIST
        pla : cmp #2 : bne GPOUT
        ldx CUR_ROOM
        lda ROOM_TGTART_LO,x : sta PTR
        lda ROOM_TGTART_HI,x : sta PTR+1
        lda #0 : jmp ART_LIST
GPOUT   rts

; ROOM_OVERLAYS — after screen cells got the room map's chars back (a trap
; beam or the laser beam erased): repaint what lies on top of the map --
; crates/mirrors and filled pits, an open gate, a destroyed target.
ROOM_OVERLAYS
        jsr CRATE_DRAW_ALL
        jmp GATE_PAINT

; ART_LIST — PTR = a list of map offsets (lo, hi; a $ff hi byte ends it) in
; CUR_ROOM: A = 0 paint those cells floor (CFG_FLOOR), A = 1 put the room
; map's chars back; with their TILE_COLORS colours. Preserves X.
ART_LIST
        sta TMP2
        txa : pha
        ldy #0
ALL     lda (PTR),y : sta AL_LO
        iny : lda (PTR),y : bmi ALD
        sta AL_HI
        iny : sty AL_Y
        lda #CFG_FLOOR : sta AL_CH
        lda TMP2 : beq ALPUT
        ldx CUR_ROOM                     ; the map's char
        lda AL_LO : clc : adc ROOM_MAP_LO,x : sta PTR2
        lda AL_HI : adc ROOM_MAP_HI,x : sta PTR2+1
        ldy #0 : lda (PTR2),y : sta AL_CH
ALPUT   lda AL_LO : clc : adc #<(SCRN+80) : sta PTR2
        lda AL_HI : adc #>(SCRN+80) : sta PTR2+1
        ldy #0 : lda AL_CH : sta (PTR2),y
        tax : lda TILE_COLORS,x : pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : sta (PTR2),y
        ldy AL_Y : jmp ALL
ALD     pla : tax
        rts

AL_LO   !byte 0
AL_HI   !byte 0
AL_Y    !byte 0
AL_CH   !byte 0
