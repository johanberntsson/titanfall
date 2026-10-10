; =============================================================================
; LASER TRAPS — art.trap_tiles chars (genworld.py: TRAP_ROOM/X/Y0/ROW1/COL).
; A trap watches the tiles below it in its tile column. While the human
; stands on one of them, its beam is on: CFG_BEAM chars down the trap's char
; column from under the trap to the first solid tile (a wall or a crate — so
; a pushed crate changes it; a pit doesn't stop it), worked out again on
; every step. Stepping onto a tile the beam reaches kills (PLR_DYING=1: like
; walking into a laser, UPDATE_SPRITE0 kills on arrival); behind the
; blocker the beam still shows but can't hurt. Stepping out of the column
; switches it off: the cells get their map chars back (ROOM_MAP_n), and the
; crates / filled pits are repainted over them (CRATE_DRAW_ALL). TRAP_ON
; remembers which beam is on screen; DRAW_ROOM clears it and calls
; TRAP_SHOW, so a redraw (popup, terminal, respawn) shows it again if the
; player is still in the column. Robots aren't hit.
; =============================================================================

; TRAP_CHECK — the human has just stepped onto PLR_X/PLR_Y (TRY_MOVE).
; Clobbers A/X/Y/NEWX/NEWY/PTR/PTR2/TMP/TMP2.
TRAP_CHECK
        lda PLR_DYING : bne TCOUT        ; already falling/sliding into death
        jsr TRAP_SHOW : bcc TCOUT
        lda #1 : sta PLR_DYING           ; stepped into the beam
TCOUT   rts

; TRAP_SHOW — the beam on if the player is in a trap's column (redrawn if its
; reach changed), off otherwise. Carry set if the player is in the beam.
TRAP_SHOW
        ldx #0
TSL     cpx #NUM_TRAPS : bcs TSNONE
        lda TRAP_ROOM,x : cmp CUR_ROOM : bne TSN
        lda TRAP_X,x : cmp PLR_X : bne TSN
        lda PLR_Y : cmp TRAP_Y0,x : bcs TSHIT    ; at or below its first tile
TSN     inx : bne TSL
TSNONE  jsr TRAP_OFF
        clc : rts
TSHIT   jsr TRAP_REACH                   ; TR_END = first tile row it can't reach
        inx : cpx TRAP_ON : bne TSDRAW   ; another beam (or none) on screen
        lda TR_END : cmp TRAP_LEN : beq TSHAVE
TSDRAW  txa : pha
        jsr TRAP_OFF                     ; (the old one, or this one shorter/longer)
        pla : sta TRAP_ON : tax : dex
        lda TR_END : sta TRAP_LEN
        lda #0 : jsr TRAP_ROWS           ; draw it
TSHAVE  lda PLR_Y : cmp TRAP_LEN         ; in the beam: C clear -> set
        bcs TSSAFE
        sec : rts
TSSAFE  clc : rts

; TRAP_OFF — erase the beam on screen, if any (TRAP_ON = trap + 1).
TRAP_OFF
        ldx TRAP_ON : beq TOOUT
        dex
        lda #1 : jsr TRAP_ROWS           ; map chars back
        lda #0 : sta TRAP_ON
        jmp CRATE_DRAW_ALL               ; crates / filled pits on top again
TOOUT   rts

; TRAP_REACH — X = trap: TR_END = the first tile row below it (from TRAP_Y0)
; that is solid and not a pit, or ROOM_MAXY+1. Preserves X.
TRAP_REACH
        lda TRAP_X,x : sta NEWX
        lda TRAP_Y0,x : sta TR_END
TRRL    ldy CUR_ROOM
        lda ROOM_MAXY,y : cmp TR_END : bcc TRRD  ; past the bottom
        lda TR_END : sta NEWY
        lda CUR_ROOM : jsr WALL_AT
        bcc TRRN                         ; open
        bpl TRRD                         ; solid (N set = a pit: the beam passes)
TRRN    inc TR_END : bne TRRL
TRRD    rts

; TRAP_ROWS — X = trap (kept in TR_TRAP), TRAP_LEN = its reach: A = 0 draw the beam, A = 1 put
; the room map's chars back, in the map rows from under the trap down to the
; last row above tile TRAP_LEN, with their TILE_COLORS colours. Preserves X.
TRAP_ROWS
        sta TR_MODE
        stx TR_TRAP
        lda TRAP_LEN : asl : sta TMP2    ; map row of the blocking tile's top
        lda TRAP_ROW1,x : sta TR_ROW
TRWL    lda TR_ROW : cmp TMP2 : bcs TRWD
        jsr ROW_PTR                      ; PTR2 = SCRN + row*40
        ldy CUR_ROOM                     ; PTR = ROOM_MAP_n + row*40
        lda PTR2 : clc : adc ROOM_MAP_LO,y : sta PTR       ; (<SCRN = 0)
        lda PTR2+1 : sbc #>SCRN-1 : clc : adc ROOM_MAP_HI,y : sta PTR+1
        lda TR_ROW : clc : adc #2 : jsr ROW_PTR   ; the screen row
        ldy TRAP_COL,x
        lda #CFG_BEAM
        ldx TR_MODE : beq TRWSET
        lda (PTR),y                      ; the map's char
TRWSET  sta (PTR2),y
        tax : lda TILE_COLORS,x : pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : sta (PTR2),y
        ldx TR_TRAP
        inc TR_ROW : bne TRWL
TRWD    rts

!if <SCRN != 0 { !error "TRAP_ROWS assumes SCRN is page-aligned" }
