; =============================================================================
; LASER EMITTERS AND MIRRORS — an emitter (art.emitter_tiles, in an outer
; wall; genworld.py: EMIT_ROOM/X/Y/DIR, at most one per room) fires a beam
; into the room all the time. BEAM_UPDATE traces it tile by tile from the
; emitter: over floor and pits; a mirror (CRATE_KIND 1 = /, 2 = \, a movable
; object the dozer pushes) turns it; the room's laser target (art.target_tiles)
; is destroyed by it -- which latches the room's gate open (GATE_STATE = 2,
; for good) -- and the beam goes on through; any other solid tile stops it.
; The path (BEAM_N tiles) is drawn with the vertical beam glyph CFG_BEAM or
; the horizontal CFG_BEAM_H, and erased again (the room map's chars back +
; ROOM_OVERLAYS) before every retrace: on DRAW_ROOM (ROOM_DYNAMIC) and after
; every crate/mirror push (CRATE_PUSH). Anyone in the beam dies: the human
; walking in (TRY_MOVE -> BEAM_AT: like a laser) or standing where a push
; sends it (BEAM_ZAP), robots too (BEAM_ZAP, like TRAP_ZAP).
; =============================================================================
BEAM_MAX = 64

BEAM_N  !byte 0                          ; tiles in the path on screen
BEAM_X  !fill BEAM_MAX
BEAM_Y  !fill BEAM_MAX
BEAM_AX !fill BEAM_MAX                   ; 0 = vertical, 1 = horizontal
BM_X    !byte 0                          ; trace: current tile, direction
BM_Y    !byte 0
BM_DIR  !byte 0
BM_LEFT !byte 0                          ; steps left (a mirror loop can't hang)
BM_I    !byte 0
BC_ROW  !byte 0                          ; BEAM_CELL: map row, column, char
BC_COL  !byte 0
BC_CH   !byte 0
BC_MODE !byte 0                          ; 0 = draw BC_CH, 1 = map char back

; ROOM_DYNAMIC — end of DRAW_ROOM, after the crates are drawn: the gate,
; the emitter's beam and a laser trap's beam (the screen is fresh, so
; nothing old needs erasing).
ROOM_DYNAMIC
        lda #0 : sta BEAM_N
        jsr BEAM_UPDATE                  ; (also paints the gate)
        lda #0 : sta TRAP_ON
        jmp TRAP_SHOW

; BEAM_UPDATE — erase the beam on screen and trace + draw it again in
; CUR_ROOM. Clobbers A/X/Y/NEWX/NEWY/PTR/PTR2/TMP/TMP2.
BEAM_UPDATE
        lda #1 : jsr BEAM_CELLS          ; the map's chars back
        lda #0 : sta BEAM_N
        jsr ROOM_OVERLAYS
BUTRACE ldx #0
BUE     cpx #NUM_EMITS : bcs BUOUT       ; no emitter in this room
        lda EMIT_ROOM,x : cmp CUR_ROOM : beq BUGO
        inx : bne BUE
BUOUT   rts
BUGO    lda EMIT_X,x : sta BM_X
        lda EMIT_Y,x : sta BM_Y
        lda EMIT_DIR,x : sta BM_DIR
        lda #0 : sta BEAM_N
        lda #80 : sta BM_LEFT
        jmp BTL
BTSTOP  jmp BTEND                        ; (branch trampoline)
BTL     dec BM_LEFT : beq BTSTOP
        ldx BM_DIR                       ; one tile on
        lda BM_X : clc : adc DIR_DX,x : sta BM_X
        lda BM_Y : clc : adc DIR_DY,x : sta BM_Y
        ldy CUR_ROOM                     ; off the room (-1 wraps to $ff)?
        lda ROOM_MAXX,y : cmp BM_X : bcc BTSTOP
        lda ROOM_MAXY,y : cmp BM_Y : bcc BTSTOP
        lda BM_X : sta NEWX
        lda BM_Y : sta NEWY
        lda CUR_ROOM : jsr WALL_AT
        bcc BTFREE                       ; open
        bmi BTFREE                       ; a pit: the beam passes over it
        jsr MIRROR_AT : beq BTTGT
        tay                              ; a mirror: turn
        ldx BM_DIR
        cpy #1 : bne BTBACK
        lda TURN_SLASH,x : sta BM_DIR : jmp BTL
BTBACK  lda TURN_BACK,x : sta BM_DIR : jmp BTL
BTTGT   jsr TGT_AT : bcc BTEND           ; solid: stops here
        lda #2 : jsr GATE_OPEN           ; the target is hit: gate latched open
        lda CUR_ROOM : sta GS_ROOM
        lda #0 : sta GS_SET
        jsr TGT_SOLID                    ; the target's tiles walkable,
        jsr GATE_PAINT                   ;  its art (and the gate's) floor
        jsr SOUND_ZAP_START
        lda #GREEN : sta VIC_BRDCOL
        lda #15 : sta BFLASH
        jmp BUTRACE                      ; the beam goes on through
BTFREE  ldx BEAM_N : cpx #BEAM_MAX : bcs BTEND
        lda BM_X : sta BEAM_X,x
        lda BM_Y : sta BEAM_Y,x
        lda BM_DIR : lsr : sta BEAM_AX,x ; DIR_LEFT/RIGHT (2/3) -> 1
        inc BEAM_N
        jmp BTL
BTEND   lda #0 : jmp BEAM_CELLS          ; draw it

DIR_DX     !byte 0, 0, $FF, 1            ; per DIR_DOWN/UP/LEFT/RIGHT
DIR_DY     !byte 1, $FF, 0, 0
TURN_SLASH !byte DIR_LEFT, DIR_RIGHT, DIR_DOWN, DIR_UP   ; / : down->left ...
TURN_BACK  !byte DIR_RIGHT, DIR_LEFT, DIR_UP, DIR_DOWN   ; \ : down->right ...

; MIRROR_AT — NEWX/NEWY in CUR_ROOM: A = the mirror kind standing there
; (1 /, 2 \), 0 = none (Z flag). Clobbers Y.
MIRROR_AT
        ldy #0
MRAL    cpy #NUM_CRATES : bcs MRANO
        lda CRATE_ROOM,y : cmp CUR_ROOM : bne MRAN
        lda CRATE_X,y : cmp NEWX : bne MRAN
        lda CRATE_Y,y : cmp NEWY : bne MRAN
        lda CRATE_KIND,y : rts
MRAN    iny : bne MRAL
MRANO   lda #0 : rts

; TGT_AT — NEWX/NEWY: carry set if it's a laser target tile of CUR_ROOM (and
; the target isn't destroyed yet). Clobbers A/Y.
TGT_AT
        ldy CUR_ROOM
        lda GATE_STATE,y : cmp #2 : beq TGANO
        ldy #0
TGAL    cpy #NUM_TGTS : bcs TGANO
        lda TGT_ROOM,y : cmp CUR_ROOM : bne TGAN
        lda TGT_X,y : cmp NEWX : bne TGAN
        lda TGT_Y,y : cmp NEWY : beq TGAYES
TGAN    iny : bne TGAL
TGANO   clc : rts
TGAYES  sec : rts

; BEAM_CELLS — A = 0 draw the path (BEAM_N tiles), A = 1 put the room map's
; chars back under it. A vertical tile is the tile's left char column (both
; rows, CFG_BEAM -- like the laser traps), a horizontal one its top char row
; (both columns, CFG_BEAM_H).
BEAM_CELLS
        sta BC_MODE
        lda #0 : sta BM_I
BCL     lda BM_I : cmp BEAM_N : bcs BCD
        tax
        lda BEAM_Y,x : asl : sta BC_ROW
        lda BEAM_X,x : asl : sta BC_COL
        lda BEAM_AX,x : bne BCH
        lda #CFG_BEAM : sta BC_CH        ; vertical: rows 2y, 2y+1
        jsr BEAM_CELL
        inc BC_ROW : jsr BEAM_CELL
        jmp BCN
BCH     lda #CFG_BEAM_H : sta BC_CH      ; horizontal: cols 2x, 2x+1
        jsr BEAM_CELL
        inc BC_COL : jsr BEAM_CELL
BCN     inc BM_I : bne BCL
BCD     rts

; BEAM_CELL — one cell (map row BC_ROW, column BC_COL): BC_CH, or the room
; map's char (BC_MODE = 1), with its TILE_COLORS colour.
BEAM_CELL
        lda BC_ROW : jsr ROW_PTR         ; PTR2 = SCRN + row*40
        ldy CUR_ROOM                     ; PTR = ROOM_MAP_n + row*40
        lda PTR2 : clc : adc ROOM_MAP_LO,y : sta PTR       ; (<SCRN = 0)
        lda PTR2+1 : sbc #>SCRN-1 : clc : adc ROOM_MAP_HI,y : sta PTR+1
        lda BC_ROW : clc : adc #2 : jsr ROW_PTR   ; the screen row
        ldy BC_COL
        lda BC_CH
        ldx BC_MODE : beq BCPUT
        lda (PTR),y
BCPUT   sta (PTR2),y
        tax : lda TILE_COLORS,x : pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : sta (PTR2),y
        rts

; BEAM_AT — NEWX/NEWY: carry set if the beam on screen covers that tile.
; Preserves X; clobbers A/Y.
BEAM_AT
        ldy #0
BAL     cpy BEAM_N : bcs BANO
        lda BEAM_X,y : cmp NEWX : bne BAN
        lda BEAM_Y,y : cmp NEWY : beq BAYES
BAN     iny : bne BAL
BANO    clc : rts
BAYES   sec : rts

; BEAM_ZAP — every game frame (GAME_ALIVE): a robot in the beam is destroyed
; (like TRAP_ZAP: zap, yellow flash; a driven one hands control back), the
; human standing in it dies (walking into it is TRY_MOVE's: PLR_DYING).
BEAM_ZAP
        lda BEAM_N : beq BZOUT
        ldx #0
BZL     cpx #NUM_ACTORS : bcs BZH
        lda ACT_ALIVE,x : cmp #1 : bne BZN
        lda ACT_ROOM,x : cmp CUR_ROOM : bne BZN
        lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        jsr BEAM_AT : bcc BZN
        lda #0 : sta ACT_ALIVE,x         ; fried
        txa : clc : adc #1 : cmp PLAYER_MODE : bne BZFX
        lda #0 : sta PLAYER_MODE
BZFX    jsr SOUND_ZAP_START
        lda #YELLOW : sta VIC_BRDCOL
        lda #15 : sta BFLASH
BZN     inx : bne BZL
BZH     lda PLR_DYING : ora DEATH_TMR : bne BZOUT
        lda PLR_X : sta NEWX
        lda PLR_Y : sta NEWY
        jsr BEAM_AT : bcc BZOUT
        jmp PLAYER_DIE
BZOUT   rts
