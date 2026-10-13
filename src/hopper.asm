; =============================================================================
; hopper.asm — the hopper's jump (actor types with jump: true, TYPE_JUMP).
;
; Driven: standing still with fire held charges it — HOP_CHG counts the
; frames, the sprite flashes between its own colour and HOP_COL — and after
; HOP_CHARGE frames it is charged (HOP_JMP = HOP_JUMPS, the sprite stays
; HOP_COL). Each move then jumps two tiles (HOP_TRY, from TRY_ACT) over
; floor, a pit or a laser, until the jumps are used up. A jump that can't be
; made (wall in between, no landing) is an ordinary 1-tile step and keeps
; the charge. Only one robot is driven at a time, so the charge is global
; (START_LINK clears it).
; By itself: a step of the AI walk (ROAM_TRY, when the caller allowed it in
; HOP_OK) now and then hops one more tile the same way — over floor only, so
; pits still fence it in (HOP_AI).
; A 2-tile step sets ACT_HOP, which doubles the glide speed (UPD_SLOT);
; ACT_STEP_ANIM clears it on the next step.
; =============================================================================

HOP_CHARGE = 100                         ; frames of fire held to charge (2 s)
HOP_JUMPS  = 2                           ; jumps per charge
HOP_COL    = WHITE                       ; colour while charged

; step deltas per DIR_* (down, up, left, right)
HOP_DX  !byte 0, 0, $FF, 1
HOP_DY  !byte 1, $FF, 0, 0

; -----------------------------------------------------------------------------
; HOP_CHARGE_TICK — every game frame while a robot is driven (RKPROXY, after
; READ_KEYS has set FIRE_PREV and KEY_U/D/L/R). Clobbers A/X/Y.
; -----------------------------------------------------------------------------
HOP_CHARGE_TICK
        ldx PLAYER_MODE : dex
        ldy ACT_TYPE,x : lda TYPE_JUMP,y : beq HCOUT
        lda ACT_ALIVE,x : cmp #1 : bne HCRST
        lda HOP_JMP : bne HCRST          ; already charged
        lda FIRE_PREV : beq HCRST        ; fire let go: start again
        lda KEY_U : ora KEY_D : ora KEY_L : ora KEY_R : bne HCRST
        inc HOP_CHG
        lda HOP_CHG : cmp #HOP_CHARGE : bcc HCOUT
        lda #HOP_JUMPS : sta HOP_JMP     ; charged
HCRST   lda #0 : sta HOP_CHG
HCOUT   rts

; -----------------------------------------------------------------------------
; HOP_TRY — from TRY_ACT: X = the driven actor, NEWX/NEWY = the tile one step
; on. If it's a charged jumper and the jump is possible — the middle tile in
; bounds, floor or a pit, not the human's; the landing tile in bounds, not
; solid (walls, crates, pits, closed gates), not the human's — it moves two
; tiles (a laser on the landing tile kills it as usual) and returns carry
; set. Otherwise carry clear and NEWX/NEWY unchanged: an ordinary step.
; Preserves X; clobbers A/Y/PTR/TMP.
; -----------------------------------------------------------------------------
HOP_TRY
        ldy ACT_TYPE,x : lda TYPE_JUMP,y : beq HTNO
        lda HOP_JMP : beq HTNO
        lda NEWX : sta HOP_MX
        lda NEWY : sta HOP_MY
        jsr HOP_INROOM : bcs HTFAIL      ; the middle tile
        jsr HOP_ONHUMAN : bcs HTFAIL
        lda ACT_ROOM,x : jsr WALL_AT : bcc HTMOK
        bpl HTFAIL                       ; solid, not a pit
HTMOK   lda HOP_MX : asl : sec : sbc ACT_X,x : sta NEWX   ; landing =
        lda HOP_MY : asl : sec : sbc ACT_Y,x : sta NEWY   ;  2 * middle - start
        jsr HOP_INROOM : bcs HTFAIL
        jsr HOP_ONHUMAN : bcs HTFAIL
        lda ACT_ROOM,x : jsr WALL_AT : bcs HTFAIL
        lda NEWX : sta ACT_X,x
        lda NEWY : sta ACT_Y,x
        jsr ACT_STEP_ANIM
        lda #1 : sta ACT_HOP,x
        dec HOP_JMP
        jsr LASER_AT : bcc HTDONE
        sty PEND_LSR                     ; landed in a laser: slide in, die
        lda #2 : sta ACT_ALIVE,x         ;  (UPD_DYING)
HTDONE  sec : rts
HTFAIL  lda HOP_MX : sta NEWX
        lda HOP_MY : sta NEWY
HTNO    clc : rts

; HOP_INROOM — X = actor: carry clear if NEWX/NEWY is inside its room's
; bounds (a negative coordinate wraps to $FF: outside). Clobbers A/Y.
HOP_INROOM
        ldy ACT_ROOM,x
        lda ROOM_MAXX,y : cmp NEWX : bcc HIOUT
        lda ROOM_MAXY,y : cmp NEWY : bcc HIOUT
        clc : rts
HIOUT   sec : rts

; HOP_ONHUMAN — carry set if NEWX/NEWY is the (frozen) human's tile.
HOP_ONHUMAN
        lda NEWX : cmp PLR_X : bne HOHNO
        lda NEWY : cmp PLR_Y : bne HOHNO
        sec : rts
HOHNO   clc : rts

; -----------------------------------------------------------------------------
; HOP_AI — from ROAM_TRY after an AI step (X = actor, HOP_DIR = its
; direction, HOP_OK set by the caller: there's room for two steps). A jumper
; hops one more tile the same way about one time in four, if that tile is
; in bounds, floor (no pit) and free of active lasers; ACT_HOP = 1 then.
; Preserves X and TMP2; clobbers A/Y/PTR/TMP/NEWX/NEWY.
; -----------------------------------------------------------------------------
HOP_AI
        ldy ACT_TYPE,x : lda TYPE_JUMP,y : beq HAOUT
        jsr RAND : and #$18 : bne HAOUT  ; bits 3-4 (RAND's good ones)
        ldy HOP_DIR
        lda ACT_X,x : clc : adc HOP_DX,y : sta NEWX
        lda ACT_Y,x : clc : adc HOP_DY,y : sta NEWY
        jsr HOP_INROOM : bcs HAOUT
        lda ACT_ROOM,x : jsr WALL_AT : bcs HAOUT
        lda ACT_ROOM,x : jsr LASER_AT_A : bcs HAOUT
        lda NEWX : sta ACT_X,x
        lda NEWY : sta ACT_Y,x
        lda #1 : sta ACT_HOP,x
HAOUT   rts

; HOP_PDX / HOP_PDY — ACTOR_PATROL_STEP: HOP_OK = 1 if the waypoint
; (PS_WX/PS_WY) is at least two tiles away on that axis, so a patrol never
; hops past it. X = actor. Clobbers A.
HOP_PDX lda ACT_X,x : sec : sbc PS_WX : jmp HOPD
HOP_PDY lda ACT_Y,x : sec : sbc PS_WY
HOPD    bcs HOPD1
        eor #$FF : adc #1                ; (C clear) negate
HOPD1   cmp #2 : lda #0 : rol : sta HOP_OK
        rts

; -----------------------------------------------------------------------------
; HOP_COLOR — from UPD_SLOT, every frame: X = actor, Y = robot slot. A
; jumper's sprite colour: HOP_COL while charged, flashing between its own
; colour and HOP_COL while charging, else its own (TYPE_COLOR) — which also
; puts it back once a link ends. Preserves X/Y.
; -----------------------------------------------------------------------------
HOP_COLOR
        tya : pha
        ldy ACT_TYPE,x : lda TYPE_JUMP,y : beq HCLDONE
        lda TYPE_COLOR,y : sta HOP_C
        txa : clc : adc #1 : cmp PLAYER_MODE : bne HCLSET   ; not driven
        lda HOP_JMP : bne HCLW
        lda HOP_CHG : and #4 : beq HCLSET
HCLW    lda #HOP_COL : sta HOP_C
HCLSET  pla : tay : pha
        txa : pha
        ldx SLOT_HW,y
        lda HOP_C : sta VIC_SPCOL0,x
        pla : tax
HCLDONE pla : tay
        rts
