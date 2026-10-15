; =============================================================================
; ROBODEX (GAME_STATE = 11) — robot information, from the terminal's menu
; =============================================================================
; One page per robot type (the generated DEX_* tables: a robodex: entry per
; actor type in titan.yaml), but only types with a robot in a room the
; player has been in (ROOM_SEEN). The type's sprite, double size and
; animated, on the left (hardware sprite 7, unused in the game, so nothing
; else needs saving); name, type and notes on the right. Left/right (A/D)
; browse, fire / Space / Return go back to the terminal with "robodex"
; still selected. Time is paused, as in the terminal.

TM_DEX     = $FC                        ; terminal menu entry (terminal.asm)
DEX_ROW    = 14                         ; its menu row
DEX_TROW   = 7                          ; first text row (to row 14)
DEX_TCOL   = 12                         ; text column (26 wide, to col 37)
DEX_CNT    = SCRN+5*40+33               ; "n/m" in the title row
DEX_SPX    = 48                         ; sprite 7: cols 3-8 (double width)
DEX_SPY    = 117                        ;  centred on the text rows 7-14
VIC_SP7X   = $D00E
VIC_SP7Y   = $D00F
VIC_SPCOL7 = $D02E

DEX_N    !byte 0                        ; pages available this visit
DEX_SEL  !byte 0                        ; page shown (index into DEX_LIST)
DEX_AN   !byte 0                        ; animation counter
DEX_LIST !fill NUM_DEX+1                ; available pages (DEX_* indexes)
DEX_TC   !byte LTGREEN, GREEN           ; text colour: name, the rest
DEX_FRM  !byte 0, 1, 0, 2               ; animation: rest, walk1, rest, walk2

; -----------------------------------------------------------------------------
; SETUP_DEX — called via jsr from the terminal's "robodex" entry
; -----------------------------------------------------------------------------
SETUP_DEX
        lda #11 : sta GAME_STATE
        lda #0 : sta $C6                 ; empty the keyboard buffer
        sta VIC_SPEN
        jsr CLEAR_ROOM
        lda #<DEX_ROWS : ldy #>DEX_ROWS : jsr DRAW_ROWS
        lda #LTGREEN : ldx #4 : ldy #17 : jsr FRAME_EDGES

        ; the pages of types with a robot in a visited room
        lda #0 : sta DEX_N : sta DEX_SEL
        ldy #0
SDXP    cpy #NUM_DEX : bcs SDXPD
        ldx #0
SDXA    cpx #NUM_ACTORS : bcs SDXPN
        lda ACT_TYPE,x : cmp DEX_TYPE,y : bne SDXAN
        lda ACT_ROOM,x : sty TMP : tay
        lda ROOM_SEEN,y : ldy TMP
        cmp #0 : beq SDXAN
        ldx DEX_N                        ; seen: add it
        tya : sta DEX_LIST,x
        inc DEX_N
        jmp SDXPN
SDXAN   inx : bne SDXA
SDXPN   iny : bne SDXP
SDXPD
        ; start on the type of the first robot in this room, if it has a page
        ldx #0
SDXR    cpx #NUM_ACTORS : bcs SDXRD
        lda ACT_ROOM,x : cmp CUR_ROOM : beq SDXRF
        inx : bne SDXR
SDXRF   lda ACT_TYPE,x : sta TMP
        ldx #0
SDXRL   cpx DEX_N : bcs SDXRD
        ldy DEX_LIST,x
        lda DEX_TYPE,y : cmp TMP : beq SDXRS
        inx : bne SDXRL
SDXRS   stx DEX_SEL
SDXRD
        lda DEX_N : bne SDXSPR
        lda #<DEX_NONE : sta PTR : lda #>DEX_NONE : sta PTR+1
        lda #DGRAY : sta TMP2
        lda #DEX_TROW : jmp DRAW_ROW     ; nothing seen yet (no sprite)

SDXSPR  lda $D01C : ora #$80 : sta $D01C ; sprite 7: multicolour, double size
        lda $D017 : ora #$80 : sta $D017
        lda $D01D : ora #$80 : sta $D01D
        lda VIC_SP_MSB : and #$7F : sta VIC_SP_MSB
        lda #DEX_SPX : sta VIC_SP7X
        lda #DEX_SPY : sta VIC_SP7Y
        lda #0 : sta DEX_AN
        jsr DEX_DRAW
        lda #$80 : sta VIC_SPEN
        rts

; -----------------------------------------------------------------------------
; DO_DEX — called each frame in state 11
; -----------------------------------------------------------------------------
DO_DEX
        lda JOY_NEW : and #$10 : bne DEX_EXIT   ; fire / Space
        lda JOY_NEW : and #$04 : bne DEX_PREV
        lda JOY_NEW : and #$08 : bne DEX_NEXT
        jsr GETIN : beq DEX_ANIM
        cmp #$0D : beq DEX_EXIT                 ; Return
        cmp #$88 : beq DEX_EXIT                 ; F7
        cmp #$41 : beq DEX_PREV                 ; A
        cmp #$44 : beq DEX_NEXT                 ; D
        bne DEX_ANIM

DEX_PREV
        lda DEX_N : beq DEX_ANIM
        ldx DEX_SEL : bne DXPV
        ldx DEX_N                        ; wrap round to the last page
DXPV    dex : stx DEX_SEL
        jsr DEX_DRAW
        jmp MAIN_LOOP
DEX_NEXT
        lda DEX_N : beq DEX_ANIM
        ldx DEX_SEL : inx
        cpx DEX_N : bcc DXNX
        ldx #0                           ; wrap round to the first
DXNX    stx DEX_SEL
        jsr DEX_DRAW
        jmp MAIN_LOOP

DEX_ANIM
        lda DEX_N : beq DXDONE
        inc DEX_AN
        jsr DEX_FRAME
DXDONE  jmp MAIN_LOOP

DEX_EXIT
        lda #0 : sta VIC_SPEN : sta $C6
        lda $D01C : and #$7F : sta $D01C
        lda $D017 : and #$7F : sta $D017
        lda $D01D : and #$7F : sta $D01D
        jsr SETUP_TERMINAL               ; ("robodex" still selected)
        jmp MAIN_LOOP

; DEX_FRAME — sprite 7's pointer: the page's type, its first facing, the
; frame DEX_FRM picks from DEX_AN (a new one every 8 frames)
DEX_FRAME
        ldx DEX_SEL : ldy DEX_LIST,x
        ldx DEX_TYPE,y
        lda DEX_AN : lsr : lsr : lsr : and #3 : tay
        lda DEX_FRM,y : beq DXF0
        ldy TYPE_ANIM,x : cpy #2 : bne DXF0
        adc #0                           ; a hop type: skip the charged pose
DXF0    clc : adc TYPE_SPRPTR,x          ;  (C set: cpy #2)
        sta SPRPTR+7
        rts

; -----------------------------------------------------------------------------
; DEX_DRAW — show page DEX_SEL: counter, sprite colour, text
; -----------------------------------------------------------------------------
DEX_DRAW
        lda DEX_SEL : clc : adc #CH_0+1 : sta DEX_CNT
        lda DEX_N : clc : adc #CH_0 : sta DEX_CNT+2
        ldx DEX_SEL : ldy DEX_LIST,x
        ldx DEX_TYPE,y
        lda TYPE_COLOR,x : sta VIC_SPCOL7
        lda DEX_LO,y : sta PTR
        lda DEX_HI,y : sta PTR+1
        jsr DEX_FRAME

        lda #DEX_TROW : sta TMP2         ; clear the text rows 7-14
DXCLR   lda TMP2 : ldx #DEX_TCOL : jsr CS_ROWP
        ldy #39-1-DEX_TCOL
        lda #CH_SPC
DXCLRL  sta (PTR2),y
        dey : bpl DXCLRL
        inc TMP2 : lda TMP2 : cmp #DEX_TROW+8 : bcc DXCLR

        lda #DEX_TROW : sta TMP2         ; the lines: 1 = next line, 0 ends,
        lda #0 : sta DX_I                ;  2 toggles white (a label) and the
        tax                              ;  line's colour (DEX_TC)
DXLINE  lda DEX_TC,x : sta DX_LC : sta CS_C
        lda TMP2 : ldx #DEX_TCOL : jsr CS_ROWP
        lda #0 : sta DX_COL
DXCH    ldy DX_I : inc DX_I
        lda (PTR),y : cmp #3 : bcs DXPUT
        cmp #2 : bne DXEOL
        lda #WHITE : cmp CS_C : bne DXTGL
        lda DX_LC
DXTGL   sta CS_C
        jmp DXCH
DXPUT   jsr PET2SCREEN
        ldy DX_COL : inc DX_COL
        jsr CS_PUT
        jmp DXCH
DXEOL   cmp #0 : beq DXDRD
        inc TMP2
        ldx TMP2 : cpx #DEX_TROW+1       ; colour: name, then the rest
        bcc DXC0
        ldx #1 : bne DXLINE
DXC0    ldx #0 : beq DXLINE
DXDRD   rts

DX_I    !byte 0                          ; index into the page's text
DX_COL  !byte 0                          ; column in the line
DX_LC   !byte 0                          ; the line's colour

; -----------------------------------------------------------------------------
; Screen rows (40 bytes each)
; -----------------------------------------------------------------------------
DEX_ROWS
        !byte 4,  LTGREEN, <SCR_BORDER_TOP, >SCR_BORDER_TOP
        !byte 5,  LTGREEN, <DEX_TTL, >DEX_TTL
        !byte 6,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 7,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 8,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 9,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 10, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 11, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 12, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 13, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 14, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 15, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 16, LTRED,   <DEX_HNT, >DEX_HNT
        !byte 17, LTGREEN, <SCR_BORDER_BOTTOM, >SCR_BORDER_BOTTOM
        !byte $FF

DEX_TTL  !pet G_VERT_BAR, "  * robodex - unit information  0/0   ", G_VERT_BAR
DEX_HNT  !pet G_VERT_BAR, "    left/right=browse   fire=return   ", G_VERT_BAR
!if * - DEX_TTL != 2*40 { !error "robodex rows must be 40 bytes each" }
DEX_NONE !pet G_VERT_BAR, "    no units on record.               ", G_VERT_BAR
