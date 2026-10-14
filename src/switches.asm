; =============================================================================
; TOGGLE SWITCHES AND RED/GREEN BLOCKS
; =============================================================================
; genworld.py finds every tile drawn exactly like art.switch's off/on
; pattern (SW_ROOM/X/Y) or one of art.blocks' patterns (BLK_ROOM/X/Y,
; BLK_COL 0 red / 1 green), and each room's start state from its switch art
; (SW_START). All switches of a room share one state, SW_STATE (0 off,
; 1 on): a red block is up (solid) while it's off, a green one while it's
; on. A switch flips when the human, a non-flying robot or a pushed crate
; enters its tile (SW_ENTER, from TMCOMMIT, ACT_STEP_ANIM via SW_ACTOR,
; HOP_AI and CRATE_PUSH) -- in any room, so a patrolling robot keeps time
; off-screen too. A block that rises crushes: the human dies (PLAYER_DIE),
; a robot is destroyed (like TRAP_ZAP); a crate standing on it jams it down
; until the next flip. A switch: door (titan.yaml) is a block of colour 2:
; closed like a red one while the switches are off, its door chars painted
; back from the map (SWD_ART_n, per room); open, they're floor.
; Blocks are plain wall bytes (1 up, 0 down), so
; walkers, robots, sight and bolts all see them through WALL_AT. The state
; resets with the room (SW_ROOMRESET, from RESET_ROOM). Room 16 uses it.
; =============================================================================

SWF_ROOM !byte 0                    ; SW_FLIP: the room
SWT_P    !byte 0                    ; SW_TILE: pattern offset into SW_PAT
SWT_C    !byte 0                    ; SW_TILE: cell; SW_ROOMRESET: wall index
SWT_BASE !byte 0                    ; SW_PAINT: up / down pattern base

; SW_ACTOR — X = actor that just stepped onto ACT_X/ACT_Y (ACT_STEP_ANIM,
; HOP_AI). Flying types pass over switches. Preserves X, Y and NEWX/NEWY.
SW_ACTOR
        lda #NUM_SW : beq SWAOUT         ; (world.asm comes later: no !if)
        tya : pha
        ldy ACT_TYPE,x
        lda TYPE_FLY,y : bne SWAD
        lda NEWX : pha
        lda NEWY : pha
        lda ACT_X,x : sta NEWX
        lda ACT_Y,x : sta NEWY
        lda ACT_ROOM,x : jsr SW_ENTER
        pla : sta NEWY
        pla : sta NEWX
SWAD    pla : tay
SWAOUT  rts

; SW_ENTER — A = room, NEWX/NEWY = the tile just entered: if it's one of
; the room's switches, flip the room. Preserves X, NEWX/NEWY, TMP/TMP2 and
; PTR/PTR2 (it's called from the middle of movement code).
SW_ENTER
        sta SWF_ROOM
        txa : pha
        ldx #0
SWEL    cpx #NUM_SW : bcs SWENO
        lda SW_ROOM,x : cmp SWF_ROOM : bne SWEN
        lda SW_X,x : cmp NEWX : bne SWEN
        lda SW_Y,x : cmp NEWY : beq SWEHIT
SWEN    inx : bne SWEL
SWENO   pla : tax
        rts
SWEHIT  lda NEWX : pha
        lda NEWY : pha
        lda TMP : pha
        lda TMP2 : pha
        lda PTR : pha
        lda PTR+1 : pha
        lda PTR2 : pha
        lda PTR2+1 : pha
        jsr SW_FLIP
        pla : sta PTR2+1
        pla : sta PTR2
        pla : sta PTR+1
        pla : sta PTR
        pla : sta TMP2
        pla : sta TMP
        pla : sta NEWY
        pla : sta NEWX
        pla : tax
        rts

; SW_FLIP — flip SWF_ROOM's switches: every block of the room up or down
; to match, then repaint if it's on screen.
SW_FLIP
        ldx SWF_ROOM
        lda SW_STATE,x : eor #1 : sta SW_STATE,x
        ldx #0
SWFL    cpx #NUM_BLK : bcs SWFD
        lda BLK_ROOM,x : cmp SWF_ROOM : bne SWFN
        jsr BLK_SET
SWFN    inx : bne SWFL
SWFD    lda SWF_ROOM : cmp CUR_ROOM : bne SWFOUT
        jmp SW_PAINT
SWFOUT  rts

; BLK_SET — X = a block of SWF_ROOM: down = plain floor; up = solid,
; crushing whoever stands there. A crate on it jams it (the crate's wall
; bits stay as they are). Preserves X.
BLK_SET
        lda BLK_X,x : sta NEWX
        lda BLK_Y,x : sta NEWY
        jsr BLK_CRATE : bcs BLKOUT       ; jammed by a crate
        lda BLK_COL,x : and #1           ; (a switch door, 2, goes with red)
        ldy SWF_ROOM : cmp SW_STATE,y
        beq BLKUP                        ; up iff its colour matches the state
        lda SWF_ROOM : jsr WALL_AT
        lda #0 : sta (PTR),y
        rts
BLKUP   lda SWF_ROOM : jsr WALL_AT
        lda #1 : sta (PTR),y
        jmp BLK_CRUSH
BLKOUT  rts

; BLK_CRATE — carry set if a crate of SWF_ROOM stands on NEWX/NEWY (one that
; filled a pit has CRATE_X = $ff and never matches). Preserves X.
BLK_CRATE
        ldy #0
BCRL    cpy #NUM_CRATES : bcs BCRNO
        lda CRATE_ROOM,y : cmp SWF_ROOM : bne BCRN
        lda CRATE_X,y : cmp NEWX : bne BCRN
        lda CRATE_Y,y : cmp NEWY : beq BCRYES
BCRN    iny : bne BCRL
BCRNO   clc : rts
BCRYES  sec : rts

; BLK_CRUSH — a block of SWF_ROOM just rose at NEWX/NEWY: the human on it
; dies (unless already dying), a living robot on it is destroyed (a driven
; one hands control back). Preserves X.
BLK_CRUSH
        lda SWF_ROOM : cmp CUR_ROOM : bne BCRA
        lda PLR_X : cmp NEWX : bne BCRA
        lda PLR_Y : cmp NEWY : bne BCRA
        lda DEATH_TMR : ora PLR_DYING : bne BCRA
        jsr PLAYER_DIE                   ; (A only)
BCRA    ldy #0
BCRAL   cpy #NUM_ACTORS : bcs BCRAD
        lda ACT_ALIVE,y : cmp #1 : bne BCRAN     ; dead, or dying in a laser
        lda ACT_ROOM,y : cmp SWF_ROOM : bne BCRAN
        lda ACT_X,y : cmp NEWX : bne BCRAN
        lda ACT_Y,y : cmp NEWY : bne BCRAN
        lda #0 : sta ACT_ALIVE,y                 ; crushed
        tya : clc : adc #1 : cmp PLAYER_MODE : bne BCRAF
        lda #0 : sta PLAYER_MODE                 ; it was the driven one
BCRAF   lda SWF_ROOM : cmp CUR_ROOM : bne BCRAN  ; seen: zap + yellow flash
        jsr SOUND_ZAP_START
        lda #YELLOW : sta VIC_BRDCOL
        lda #15 : sta BFLASH
BCRAN   iny : bne BCRAL
BCRAD   rts

; SW_PAINT — from ROOM_OVERLAYS (every redraw) and SW_FLIP: CUR_ROOM's
; switches in their state, its blocks up or down as their wall bytes say.
; Its switch doors: the map's door chars while off, floor while on. Not
; while the small search popup is up (it would draw over the box), and not
; under a crate. Clobbers A/X/Y/NEWX/NEWY/PTR/PTR2/TMP/TMP2.
SW_PAINT
        lda SRCH_ST : beq SWPGO
        rts
SWPGO
        lda CUR_ROOM : sta SWF_ROOM      ; (BLK_CRATE)
        ldx #0
SWPSL   cpx #NUM_SW : bcs SWPB
        lda SW_ROOM,x : cmp CUR_ROOM : bne SWPSN
        lda SW_X,x : sta NEWX
        lda SW_Y,x : sta NEWY
        jsr BLK_CRATE : bcs SWPSN
        ldy CUR_ROOM : lda SW_STATE,y : asl : asl   ; SW_PAT: off 0, on 4
        jsr SW_TILE
SWPSN   inx : bne SWPSL
SWPB    ldx #0
SWPBL   cpx #NUM_BLK : bcs SWPDOOR
        lda BLK_ROOM,x : cmp CUR_ROOM : bne SWPBN
        lda BLK_COL,x : cmp #2 : bcs SWPBN       ; switch doors: below
        lda BLK_X,x : sta NEWX
        lda BLK_Y,x : sta NEWY
        jsr BLK_CRATE : bcs SWPBN
        lda CUR_ROOM : jsr WALL_AT       ; C = up
        lda #16 : bcc SWPBD              ; SW_PAT: up 8 + colour*4,
        lda #8                           ;  down 16 + colour*4
SWPBD   sta SWT_BASE
        lda BLK_COL,x : asl : asl : clc : adc SWT_BASE
        jsr SW_TILE
SWPBN   inx : bne SWPBL
SWPDOOR ldx CUR_ROOM
        lda SWD_ART_LO,x : sta PTR
        lda SWD_ART_HI,x : sta PTR+1
        lda SW_STATE,x : eor #1          ; ART_LIST: off 1 (map chars), on 0 (floor)
        jmp ART_LIST

; SW_TILE — paint tile NEWX/NEWY of CUR_ROOM with the 4 chars at SW_PAT+A
; (TL, TR, BL, BR) and their TILE_COLORS colours. Preserves X.
SW_TILE
        sta SWT_P
        txa : pha
        lda NEWY : asl : clc : adc #2    ; screen row of the tile's top half
        jsr ROW_PTR
        lda NEWX : asl : clc : adc PTR2 : sta PTR2
        bcc SWTNC : inc PTR2+1
SWTNC   ldx #0
SWTL    ldy CR_CELL,x                    ; 0, 1, 40, 41 (crates.asm)
        stx SWT_C
        txa : clc : adc SWT_P : tax
        lda SW_PAT,x : sta (PTR2),y
        tax : lda TILE_COLORS,x : pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : sta (PTR2),y
        lda PTR2+1 : sec : sbc #>(CRAM-SCRN) : sta PTR2+1
        ldx SWT_C : inx : cpx #4 : bcc SWTL
        pla : tax
        rts

; SW_ROOMRESET — from RESET_ROOM (after CRATE_RESET): CUR_ROOM's switches
; (every room's with RS_ALL, a new game) back to their start state, its
; blocks' wall bytes to match. No crushing: the room is being reset.
SW_ROOMRESET
        ldx #0
SWRRL   cpx #NUM_ROOMS : bcs SWRB
        lda RS_ALL : bne SWRRGO
        cpx CUR_ROOM : bne SWRRN
SWRRGO  lda SW_START,x : sta SW_STATE,x
SWRRN   inx : bne SWRRL
SWRB    ldx #0
SWRBL   cpx #NUM_BLK : bcs SWRBD
        lda RS_ALL : bne SWRBGO
        lda BLK_ROOM,x : cmp CUR_ROOM : bne SWRBN
SWRBGO  lda BLK_X,x : sta NEWX
        lda BLK_Y,x : sta NEWY
        lda BLK_ROOM,x : jsr WALL_AT     ; Y = its index in the wall grid
        sty SWT_C
        lda BLK_COL,x : and #1 : sta SWT_BASE    ; (a switch door goes with red)
        ldy BLK_ROOM,x : lda SW_STATE,y
        ldy SWT_C
        cmp SWT_BASE : beq SWRUP
        lda #0 : beq SWRPUT
SWRUP   lda #1
SWRPUT  sta (PTR),y
SWRBN   inx : bne SWRBL
SWRBD   rts
