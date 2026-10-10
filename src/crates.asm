; =============================================================================
; CRATES — movable crates (art.crate_tiles drawn on a whole tile). genworld.py
; lists them (CRATE_ROOM/SX/SY, the look in CRATE_CH), takes them out of the
; room map data (ROOM_MAP_n has floor there) and marks their start tiles
; solid + searchable in ROOM_WALLS_n. At runtime CRATE_X/Y say where each
; crate is: DRAW_ROOM draws them there (CRATE_DRAW_ALL), and a push moves the
; two wall bits along with the crate, so everything that asks WALL_AT —
; walking, robots, sight, bolts — sees a crate as a wall wherever it is.
;
; Pushing: a player-driven robot whose type has push: true (TYPE_PUSH) that
; drives into a crate pushes it one tile ahead (TRY_ACT -> CRATE_PUSH), if
; that tile is plain floor (wall byte 0 apart from the searched bit: no
; wall, pit, furniture, item or door), in the room's bounds, not an active
; laser and nobody stands on it. The robot follows into the crate's tile.
; Only one crate at a time (a crate behind a crate is a wall).
;
; Pits: a crate can also be pushed onto a pit (art.pit_tiles). It fills it:
; the crate is gone (CRATE_X = $ff), the pit tile becomes plain floor (wall
; byte 0, floor chars on screen) and PIT_FILLED records it. genworld.py
; lists every pit tile (PIT_ROOM/X/Y, PIT_WB = its wall byte), so a room
; reset (CRATE_RESET) brings the pit back with the crate.
; =============================================================================

; CRATE_RESET — from RESET_ROOM: every crate of CUR_ROOM (all rooms on a new
; game, RS_ALL) back to its start tile, and the pits they filled open again.
; Crates in two passes: first take every crate off the wall grid, then put
; them back where they start (one crate may have been pushed onto another's
; start tile); the pits in between (a filled pit is floor, so a crate may
; stand on it).
CRATE_RESET
        ldx #0
CRSL1   cpx #NUM_CRATES : bcs CRSD1
        lda CRATE_ROOM,x : jsr RS_MINE : bne CRSN1
        lda CRATE_X,x : bmi CRSN1        ; $ff: in a pit, not on the grid
        sta NEWX
        lda CRATE_Y,x : sta NEWY
        lda CRATE_ROOM,x : jsr WALL_AT
        lda (PTR),y : and #$FA : sta (PTR),y   ; not solid, not searchable
CRSN1   inx : bne CRSL1
CRSD1   ldx #0
CRSLP   cpx #NUM_PITS : bcs CRSDP
        lda PIT_ROOM,x : jsr RS_MINE : bne CRSNP
        lda PIT_FILLED,x : beq CRSNP
        lda #0 : sta PIT_FILLED,x
        lda PIT_X,x : sta NEWX
        lda PIT_Y,x : sta NEWY
        lda PIT_ROOM,x : jsr WALL_AT
        lda PIT_WB,x : sta (PTR),y       ; a pit again
CRSNP   inx : bne CRSLP
CRSDP   ldx #0
CRSL2   cpx #NUM_CRATES : bcs CRSD2
        lda CRATE_ROOM,x : jsr RS_MINE : bne CRSN2
        lda CRATE_SX,x : sta CRATE_X,x : sta NEWX
        lda CRATE_SY,x : sta CRATE_Y,x : sta NEWY
        lda CRATE_ROOM,x : jsr WALL_AT
        lda (PTR),y : ora #$05 : sta (PTR),y   ; solid + searchable
CRSN2   inx : bne CRSL2
CRSD2   jmp GATE_ROOMRESET               ; a gate held open by the plates closes

; RS_MINE — A = room: Z set if RESET_ROOM resets it (RS_ALL, or CUR_ROOM).
; Clobbers Y.
RS_MINE ldy RS_ALL : bne RSMALL
        cmp CUR_ROOM
        rts
RSMALL  lda #0 : rts

; CRATE_DRAW_ALL — from DRAW_ROOM: draw the crates of CUR_ROOM where they are.
; The pits filled in CUR_ROOM are painted over as floor (the map data has
; every pit).
CRATE_DRAW_ALL
        ldx #0
CRDL    cpx #NUM_CRATES : bcs CRDD
        lda CRATE_ROOM,x : cmp CUR_ROOM : bne CRDN
        lda CRATE_X,x : bmi CRDN         ; $ff: it filled a pit
        sta NEWX
        lda CRATE_Y,x : sta NEWY
        lda CRATE_KIND,x : asl : asl : clc : adc #4   ; its chars (CRATE_CH)
        jsr CRATE_PAINT
CRDN    inx : bne CRDL
CRDD    ldx #0
CRDPL   cpx #NUM_PITS : bcs CRDPD
        lda PIT_ROOM,x : cmp CUR_ROOM : bne CRDPN
        lda PIT_FILLED,x : beq CRDPN
        lda PIT_X,x : sta NEWX
        lda PIT_Y,x : sta NEWY
        lda #1 : jsr CRATE_PAINT         ; floor
CRDPN   inx : bne CRDPL
CRDPD   rts

; CRATE_PAINT — paint tile NEWX/NEWY of the screen (CUR_ROOM), with the
; TILE_COLORS colours: A = 0 the room map's own chars (ROOM_MAP_n: what's
; under a crate that moved away -- floor, or a plate), A = 1 plain floor
; (CFG_FLOOR, a filled pit), A = 4 + kind*4 a crate/mirror (CRATE_CH).
; Preserves X; clobbers A/Y/PTR/PTR2/TMP/TMP2.
CRATE_PAINT
        sta TMP2
        txa : pha
        lda NEWY : asl : clc : adc #2    ; screen row of the tile's top half
        jsr ROW_PTR
        lda NEWX : asl : clc : adc PTR2 : sta PTR2
        bcc CRPNC : inc PTR2+1
CRPNC   lda PTR2 : sec : sbc #<(SCRN+80) : sta PTR       ; the same cell in
        lda PTR2+1 : sbc #>(SCRN+80) : sta PTR+1         ;  the room's map
        ldy CUR_ROOM
        lda PTR : clc : adc ROOM_MAP_LO,y : sta PTR
        lda PTR+1 : adc ROOM_MAP_HI,y : sta PTR+1
        ldx #0
CRPL    ldy CR_CELL,x                    ; 0, 1, 40, 41
        lda TMP2 : beq CRPMAP
        cmp #1 : beq CRPFL
        stx TMP : clc : adc TMP : tax    ; CRATE_CH + kind*4 + cell
        lda CRATE_CH-4,x : ldx TMP
        jmp CRPPUT
CRPMAP  lda (PTR),y : jmp CRPPUT
CRPFL   lda #CFG_FLOOR
CRPPUT  sta (PTR2),y
        stx TMP : tax
        lda TILE_COLORS,x : pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : sta (PTR2),y
        lda PTR2+1 : sec : sbc #>(CRAM-SCRN) : sta PTR2+1
        ldx TMP : inx : cpx #4 : bcc CRPL
        pla : tax
        rts
CR_CELL !byte 0, 1, 40, 41

; CRATE_PUSH — from TRY_ACT: X = the driven actor, NEWX/NEWY = the solid tile
; it drives into. Carry set if that's a crate it can push and the push
; happened (the crate moved one tile on; NEWX/NEWY still the crate's old
; tile, for TRY_ACT to step onto); carry clear = blocked, nothing changed.
; Preserves X.
CRATE_PUSH
        ldy ACT_TYPE,x
        lda TYPE_PUSH,y : beq CPNO
        ldy #0                           ; a crate on that tile?
CPFIND  cpy #NUM_CRATES : bcs CPNO
        lda CRATE_ROOM,y : cmp ACT_ROOM,x : bne CPFN
        lda CRATE_X,y : cmp NEWX : bne CPFN
        lda CRATE_Y,y : cmp NEWY : beq CPFOUND
CPFN    iny : bne CPFIND
CPNO    clc : rts
CPFOUND sty CR_IDX
        lda NEWX : sta CR_OX             ; the tile beyond: crate + (crate - robot)
        asl : sec : sbc ACT_X,x : sta CR_NX
        lda NEWY : sta CR_OY
        asl : sec : sbc ACT_Y,x : sta CR_NY
        ldy ACT_ROOM,x                   ; in bounds? (-1 wraps to $FF: too big)
        lda ROOM_MAXX,y : cmp CR_NX : bcc CPNO
        lda ROOM_MAXY,y : cmp CR_NY : bcc CPNO
        jsr CR_FREE : bcc CPGO
CPBACK  lda CR_OX : sta NEWX             ; blocked: NEWX/NEWY as they were
        lda CR_OY : sta NEWY
        clc : rts
CPGO    lda CR_PIT : bne CPFILL
        lda ACT_ROOM,x : jsr WALL_AT     ; the new tile becomes the crate's
        lda (PTR),y : ora #$05 : sta (PTR),y
        ldy CR_IDX
        lda CR_NX : sta CRATE_X,y
        lda CR_NY : sta CRATE_Y,y
        lda ACT_ROOM,x : cmp CUR_ROOM : bne CPOLD
        lda CRATE_KIND,y : asl : asl : clc : adc #4
        jsr CRATE_PAINT
        jmp CPOLD
CPFILL  jsr CR_FILL                      ; into a pit: both are gone, floor
CPOLD   lda CR_OX : sta NEWX             ; the old one shows the map again
        lda CR_OY : sta NEWY
        lda ACT_ROOM,x : jsr WALL_AT
        lda (PTR),y : and #$FA : sta (PTR),y
        lda ACT_ROOM,x : cmp CUR_ROOM : bne CPDONE
        lda #0 : jsr CRATE_PAINT
        txa : pha
        jsr BEAM_UPDATE                  ; a mirror/crate moved: retrace (and
        pla : tax                        ;  repaint filled pits, gates)
        lda CR_OX : sta NEWX             ; (TRY_ACT steps onto it)
        lda CR_OY : sta NEWY
CPDONE  sec : rts

; CR_FREE — X = the pushing actor: carry clear if the crate can go to
; CR_NX/CR_NY (left in NEWX/NEWY): plain floor (wall byte 0 apart from the
; searched bit) or a pit (CR_PIT = 1), no active laser, no robot or human
; on it.
CR_FREE lda #0 : sta CR_PIT
        lda CR_NX : sta NEWX
        lda CR_NY : sta NEWY
        lda ACT_ROOM,x : jsr WALL_AT
        lda (PTR),y : and #$F7 : beq CFFLOOR  ; plain floor,
        and #$F3 : cmp #$02 : bne CFBLK       ;  or a pit (bit 1 alone)
        inc CR_PIT
CFFLOOR        lda ACT_ROOM,x : jsr LASER_AT_A : bcs CFBLK
        ldy #0                           ; nobody standing there
CFACT   cpy #NUM_ACTORS : bcs CFACTD
        lda ACT_ALIVE,y : beq CFACTN
        lda ACT_ROOM,y : cmp ACT_ROOM,x : bne CFACTN
        lda ACT_X,y : cmp NEWX : bne CFACTN
        lda ACT_Y,y : cmp NEWY : beq CFBLK
CFACTN  iny : bne CFACT
CFACTD  lda ACT_ROOM,x : cmp CUR_ROOM : bne CFOK   ; (the human, frozen at the
        lda PLR_X : cmp NEWX : bne CFOK          ;  terminal, if it's there)
        lda PLR_Y : cmp NEWY : beq CFBLK
CFOK    clc : rts
CFBLK   sec : rts

; CR_FILL — X = the pushing actor, crate CR_IDX goes into the pit at NEWX/NEWY
; (= CR_NX/CR_NY, PTR/Y from CR_FREE's WALL_AT are gone: look it up again):
; the pit tile becomes plain floor, the crate leaves the game until a room
; reset, PIT_FILLED marks the pit for DRAW_ROOM and the reset. Preserves X.
CR_FILL lda ACT_ROOM,x : jsr WALL_AT
        lda #0 : sta (PTR),y             ; plain floor
        ldy CR_IDX
        lda #$FF : sta CRATE_X,y
        ldy #0
CFLP    cpy #NUM_PITS : bcs CFLPD
        lda PIT_ROOM,y : cmp ACT_ROOM,x : bne CFLPN
        lda PIT_X,y : cmp NEWX : bne CFLPN
        lda PIT_Y,y : cmp NEWY : bne CFLPN
        lda #1 : sta PIT_FILLED,y
CFLPN   iny : bne CFLP
CFLPD   lda ACT_ROOM,x : cmp CUR_ROOM : bne CFLOUT
        lda #1 : jsr CRATE_PAINT         ; floor where the pit was
CFLOUT  rts
