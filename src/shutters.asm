; =============================================================================
; TIMED SHUTTERS — barriers that close and open on their own clock
; =============================================================================
; genworld.py lists every shutter (a room's shutters: in titan.yaml, tile
; rectangles drawn with art.shutter_tiles chars): SH_ROOM, its open and
; closed times in frames (SH_OPEN/SH_CLOSED), how long it stays closed at
; the start of a game (SH_FIRST), its tiles (SH_T0/SH_TN into SHT_X/Y) and
; its art cells (SH_ART_n). Runtime SH_STATE (0 closed, 1 open) and SH_TMR
; (frames left). Closed, its tiles are solid (walls for everyone: walkers,
; robots, sight, bolts); open, they're plain floor drawn as floor. All
; shutters tick together, every game frame (they pause with the clock), so
; their rhythms keep the relation the config gives them. They don't wait
; for whatever stands in them (keep them off walking routes), and a laser
; emitter's beam isn't retraced when one moves.
; Also here: BOLT_SOLID — a bolt fired by a player-driven shooter that hits
; the room's laser target destroys it (TGT_DESTROY: the gate latches open).
; =============================================================================

SS_SET  !byte 0
SS_I    !byte 0
SS_END  !byte 0

; SHUT_RESET — SETUP_GAME: every shutter closed, solid, SH_FIRST frames to go
SHUT_RESET
        ldx #0
SHRL    cpx #NUM_SHUT : bcs SHRD
        lda #0 : sta SH_STATE,x
        lda SH_FIRST,x : sta SH_TMR,x
        lda #1 : jsr SH_SOLID
        inx : bne SHRL
SHRD    rts

; SHUT_TICK — every game frame (GAME_ALIVE). Clobbers A/Y/NEWX/NEWY/PTR/
; PTR2/TMP/TMP2.
SHUT_TICK
        ldx #0
SHTL    cpx #NUM_SHUT : bcs SHTD
        dec SH_TMR,x : bne SHTN
        lda SH_STATE,x : eor #1 : sta SH_STATE,x
        beq SHTCL
        lda SH_OPEN,x : sta SH_TMR,x     ; opens: floor
        lda #0 : jsr SH_SOLID
        lda #0 : jsr SH_PAINT
        jmp SHTN
SHTCL   lda SH_CLOSED,x : sta SH_TMR,x   ; closes: the map's shutter chars
        lda #1 : jsr SH_SOLID
        lda #1 : jsr SH_PAINT
SHTN    inx : bne SHTL
SHTD    rts

; SH_SOLID — X = shutter, A = 1 solid / 0 plain floor: its tiles' wall bytes
; (keeping bits 4-7). Preserves X.
SH_SOLID
        sta SS_SET
        lda SH_T0,x : sta SS_I
        clc : adc SH_TN,x : sta SS_END
SSOL    ldy SS_I : cpy SS_END : bcs SSOD
        lda SHT_X,y : sta NEWX
        lda SHT_Y,y : sta NEWY
        lda SH_ROOM,x : jsr WALL_AT      ; (Y = its index in the wall grid)
        lda (PTR),y : and #$F0 : ora SS_SET : sta (PTR),y
        inc SS_I : jmp SSOL
SSOD    rts

; SH_PAINT — X = shutter, A = ART_LIST mode (0 floor, 1 the map's chars):
; repaint it if it's on screen (not while the small search popup is up: it
; would draw over the box). Preserves X.
SH_PAINT
        tay
        lda SH_ROOM,x : cmp CUR_ROOM : bne SHPD
        lda SRCH_ST : bne SHPD
        lda SH_ART_LO,x : sta PTR
        lda SH_ART_HI,x : sta PTR+1
        tya : jmp ART_LIST
SHPD    rts

; SHUT_PAINT — from ROOM_OVERLAYS (every redraw): CUR_ROOM's open shutters
; painted floor over the map's closed ones
SHUT_PAINT
        ldx #0
SHPL    cpx #NUM_SHUT : bcs SHPLD
        lda SH_STATE,x : beq SHPN
        lda #0 : jsr SH_PAINT
SHPN    inx : bne SHPL
SHPLD   rts

; BOLT_SOLID — from BOLT_TICK, the bolt's centre (NEWX/NEWY) is in a solid
; tile: a player's bolt (BOLT_PLR) that hits the room's intact laser target
; destroys it (the gate latches open), then the bolt is gone either way.
BOLT_SOLID
        lda BOLT_PLR : beq BSKILL
        jsr TGT_AT : bcc BSKILL
        jsr TGT_DESTROY                  ; (beam.asm)
BSKILL  jmp BTKILL
