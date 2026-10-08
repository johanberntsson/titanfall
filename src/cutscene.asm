; =============================================================================
; CUT SCENE (GAME_STATE = 8) — the briefing between the intro and the game
; =============================================================================
; The commander (left, green uniform) briefs the agent (right, the player's
; own colours) in speech bubbles that come and go by themselves; then the
; agent turns and walks off screen and the game starts. Fire, Space or
; Return skip the whole scene.
;
; Both figures are the walker sprite, double size. Only the %10 bits have a
; per-sprite colour, and in the walker those are the skin — so the scene
; uses copies of four walker frames with %10 and %11 swapped (CS_FRAMES, in
; the sprite block, filled by SETUP_CUTSCENE): skin comes from the shared
; MC1 ($D026 = light red during the scene) and the clothes from each
; sprite's own colour.

CS_BOT    = 13           ; bubble bottom border row (tail on the 2 rows below)
CS_TOP    = 3            ; first row CS_CLEAR wipes
CS_FLOOR  = 18           ; first floor row
CS_Y      = 178          ; sprite Y: double height, feet on screen row 21
CS_CX     = 72           ; commander sprite X (cols 6-11)
CS_AX     = 232          ; agent sprite X (cols 26-31)
CS_EXITX  = 344          ; agent's X once it's off the right edge
CS_SPRP   = CS_FRAMES/64 ; +0 left rest, +1 right rest, +2/+3 right walk1/2
CS_PAUSE  = 40           ; frames before the first line
CS_GAP    = 15           ; frames between bubbles
CS_COL_L  = 1            ; commander bubble's left column
CS_SC_BSL = $4D          ; screen codes: diagonal "\" and "/" (bubble tails)
CS_SC_SL  = $4E

; state
CS_PH   !byte 0          ; 0 = pause (CS_TMR), 1 = bubble up, 2 = walking out
CS_TMR  !byte 0
CS_LP   !byte 0, 0       ; next dialog entry
CS_SPK  !byte 0          ; speaker of the bubble: 0 commander, 1 agent
CS_NL   !byte 0          ; bubble: text lines
CS_W    !byte 0          ; bubble: width (widest line + 4)
CS_LEN  !byte 0          ; bubble: characters (sets how long it stays)
CS_CUR  !byte 0          ; scratch: length of the line being measured
CS_COL  !byte 0          ; bubble: left column
CS_RGT  !byte 0          ; bubble: right column
CS_ROW  !byte 0          ; row being drawn
CS_TOPR !byte 0          ; bubble: top border row
CS_SRC  !byte 0          ; index of the line's first char in the entry
CS_C    !byte 0          ; colour for CS_PUT
CS_CL   !byte 0          ; left / middle / right char of the row being drawn
CS_CM   !byte 0
CS_CR   !byte 0
CS_X    !byte 0, 0       ; agent sprite X (9 bits) while walking out
CS_AN   !byte 0          ; walk animation counter

; per speaker: commander, agent
CS_BCOL  !byte GREEN, LTBLUE     ; bubble frame (and tail)
CS_TCOL  !byte LTGREEN, CYAN     ; bubble text
CS_TAIL1 !byte 11, 28            ; tail column on row CS_BOT+1
CS_TAIL2 !byte 10, 29            ; ... and on row CS_BOT+2 (above the head)
CS_TAILC !byte CS_SC_SL, CS_SC_BSL
CS_WALKF !byte CS_SPRP+2, CS_SPRP+1, CS_SPRP+3, CS_SPRP+1

; -----------------------------------------------------------------------------
; SETUP_CUTSCENE — called via jsr from DO_INTRO
; -----------------------------------------------------------------------------
SETUP_CUTSCENE
        lda #8 : sta GAME_STATE
        lda #0 : sta VIC_SPEN
        jsr CLS

        ldx #63                          ; walker frames, %10 <-> %11 swapped
CSFRM   lda sprite_left_rest,x   : jsr CS_SWAP : sta CS_FRAMES,x
        lda sprite_right_rest,x  : jsr CS_SWAP : sta CS_FRAMES+64,x
        lda sprite_right_walk1,x : jsr CS_SWAP : sta CS_FRAMES+128,x
        lda sprite_right_walk2,x : jsr CS_SWAP : sta CS_FRAMES+192,x
        dex : bpl CSFRM

        lda #<CS_HEAD : sta PTR          ; row 1: where we are
        lda #>CS_HEAD : sta PTR+1
        lda #MGRAY : sta TMP2
        lda #1 : jsr DRAW_ROW

        lda #CS_FLOOR                    ; the floor the two stand on
CSFLR   pha
        jsr ROW_PTR
        ldy #39
        lda #CFG_FLOOR
CSFLR2  sta (PTR2),y
        dey : bpl CSFLR2
        lda TILE_COLORS+CFG_FLOOR : jsr PAINT_ROW
        pla : clc : adc #1 : cmp #25 : bcc CSFLR

        lda #CS_SPRP   : sta SPRPTR      ; agent, facing left
        lda #CS_SPRP+1 : sta SPRPTR+1    ; commander, facing right
        lda #CS_AX : sta VIC_SP0X : sta CS_X
        lda #CS_CX : sta VIC_SP1X
        lda #CS_Y  : sta VIC_SP0Y : sta VIC_SP1Y
        lda #0 : sta VIC_SP_MSB : sta CS_X+1
        lda #LTGRAY : sta VIC_SPCOL0     ; the agent's shirt, as in the game
        lda #GREEN  : sta VIC_SPCOL1     ; the commander's uniform
        lda #LTRED  : sta $D026          ; MC1: skin (both)
        lda #$03 : sta $D017 : sta $D01D ; double height and width
        sta VIC_SPEN

        lda #<CS_DIALOG : sta CS_LP
        lda #>CS_DIALOG : sta CS_LP+1
        lda #0 : sta CS_PH
        lda #CS_PAUSE : sta CS_TMR
        lda #0 : sta $C6                 ; drop buffered keys
        rts

; A -> A with the %10 and %11 pixel pairs swapped (%00/%01 unchanged)
CS_SWAP sta TMP
        and #$AA : lsr : eor TMP
        rts

; -----------------------------------------------------------------------------
; DO_CUTSCENE — called each frame in state 8
; -----------------------------------------------------------------------------
DO_CUTSCENE
        jsr GETIN : cmp #$0D : beq CS_END    ; Return skips the scene,
        lda JOY_NEW : and #$10 : bne CS_END  ;  and so does fire / Space
        lda CS_PH : cmp #2 : beq CS_WALK
        dec CS_TMR : bne CSDONE
        lda CS_PH : beq CSNEXT
        jsr CS_CLEAR                     ; bubble's time is up
        lda #0 : sta CS_PH
        lda #CS_GAP : sta CS_TMR
CSDONE  jmp MAIN_LOOP
CSNEXT  jsr CS_BUBBLE                    ; pause over: next line
        bcs CSGO
        lda #1 : sta CS_PH
        jmp MAIN_LOOP
CSGO    lda #2 : sta CS_PH               ; no lines left: walk out
        lda #0 : sta CS_AN
        jmp MAIN_LOOP

CS_WALK lda CS_X : clc : adc #2 : sta CS_X : sta VIC_SP0X
        lda CS_X+1 : adc #0 : sta CS_X+1 : sta VIC_SP_MSB   ; sprite 0's bit
        lda CS_X : cmp #<CS_EXITX
        lda CS_X+1 : sbc #>CS_EXITX
        bcs CS_END                       ; off screen
        inc CS_AN
        lda CS_AN : lsr : lsr : lsr : and #3 : tax
        lda CS_WALKF,x : sta SPRPTR
        jmp MAIN_LOOP

CS_END  lda #0 : sta VIC_SPEN
        sta $D017 : sta $D01D : sta VIC_SP_MSB
        lda #LTGRAY : sta $D026
        lda TYPE_COLOR+ATYPE_HUMAN : sta VIC_SPCOL0
        jsr SETUP_GAME
        jmp MAIN_LOOP

; -----------------------------------------------------------------------------
; CS_CLEAR — wipe the bubble area (rows CS_TOP..CS_BOT+2)
; -----------------------------------------------------------------------------
CS_CLR_N = (CS_BOT+3-CS_TOP)*40/4
CS_CLEAR
        lda #CH_SPC
        ldx #CS_CLR_N-1
CSCLR   sta SCRN+CS_TOP*40,x
        sta SCRN+CS_TOP*40+CS_CLR_N,x
        sta SCRN+CS_TOP*40+CS_CLR_N*2,x
        sta SCRN+CS_TOP*40+CS_CLR_N*3,x
        dex : cpx #$FF : bne CSCLR
        rts

; -----------------------------------------------------------------------------
; CS_BUBBLE — draw the next dialog entry (CS_LP) as a speech bubble above
; its speaker and set CS_TMR to how long it stays; carry set (nothing drawn)
; at the end of the dialog.
; -----------------------------------------------------------------------------
CS_BUBBLE
        lda CS_LP : sta PTR
        lda CS_LP+1 : sta PTR+1
        ldy #0 : lda (PTR),y : bpl CSB1
        sec : rts
CSB1    sta CS_SPK
        lda #0 : sta CS_NL : sta CS_W : sta CS_LEN : sta CS_CUR
CSBM    iny : lda (PTR),y : cmp #2 : bcc CSBEOL      ; 0 = end, 1 = new line
        inc CS_CUR : inc CS_LEN
        jmp CSBM
CSBEOL  tax
        inc CS_NL
        lda CS_CUR : cmp CS_W : bcc CSBNW
        sta CS_W
CSBNW   lda #0 : sta CS_CUR
        txa : bne CSBM
        iny : tya : clc : adc PTR : sta CS_LP        ; next entry
        lda PTR+1 : adc #0 : sta CS_LP+1

        lda CS_LEN : asl : bcs CSBCAP                ; 50 frames + 2 per char
        adc #50 : bcc CSBTM
CSBCAP  lda #255
CSBTM   sta CS_TMR

        lda CS_W : clc : adc #4 : sta CS_W           ; frame + a space each side
        ldx CS_SPK
        lda #CS_COL_L
        cpx #0 : beq CSBCOL
        lda #39 : sec : sbc CS_W                     ; agent: right edge col 38
CSBCOL  sta CS_COL
        clc : adc CS_W : sec : sbc #1 : sta CS_RGT
        lda #CS_BOT : clc : sbc CS_NL                ; CS_BOT - lines - 1
        sta CS_TOPR : sta CS_ROW
        lda CS_BCOL,x : sta CS_C

CSBROW  lda CS_ROW : ldx #0 : jsr CS_ROWP
        lda CS_ROW : cmp CS_TOPR : bne CSBR1
        lda #$55 : sta CS_CL                         ; top: rounded corners
        lda #$43 : sta CS_CM
        lda #$49 : sta CS_CR
        bne CSBRD
CSBR1   cmp #CS_BOT : bne CSBR2
        lda #$4A : sta CS_CL                         ; bottom
        lda #$43 : sta CS_CM
        lda #$4B : sta CS_CR
        bne CSBRD
CSBR2   lda #$5D : sta CS_CL : sta CS_CR             ; sides, blank inside
        lda #CH_SPC : sta CS_CM
CSBRD   ldy CS_COL : lda CS_CL : jsr CS_PUT
CSBMID  iny : cpy CS_RGT : beq CSBRE
        lda CS_CM : jsr CS_PUT
        jmp CSBMID
CSBRE   lda CS_CR : jsr CS_PUT
        lda CS_ROW : cmp #CS_BOT : beq CSBTAIL
        inc CS_ROW : bne CSBROW

CSBTAIL lda #CS_BOT+1 : ldx #0 : jsr CS_ROWP     ; the tail, down to the head
        ldx CS_SPK
        ldy CS_TAIL1,x : lda CS_TAILC,x : jsr CS_PUT
        lda #CS_BOT+2 : ldx #0 : jsr CS_ROWP
        ldx CS_SPK
        ldy CS_TAIL2,x : lda CS_TAILC,x : jsr CS_PUT

        lda CS_TCOL,x : sta CS_C                     ; the text, line by line
        lda CS_TOPR : sta CS_ROW
        lda #1 : sta CS_SRC
CSBTL   inc CS_ROW
        lda CS_COL : clc : adc #2 : tax              ; PTR2/PTR3 = text start
        lda CS_ROW : jsr CS_ROWP                     ;  minus CS_SRC, so the
        lda PTR2 : sec : sbc CS_SRC                  ;  entry index y works
        sta PTR2 : sta PTR3                          ;  for both
        bcs CSBTNB
        dec PTR2+1 : dec PTR3+1
CSBTNB  ldy CS_SRC
CSBTC   lda (PTR),y : cmp #2 : bcc CSBTE
        jsr PET2SCREEN : jsr CS_PUT
        iny : bne CSBTC
CSBTE   iny : sty CS_SRC
        cmp #0 : bne CSBTL
        clc
        rts

; A = screen row, X = column -> PTR2 = its screen address, PTR3 = colour RAM
; (also used by the game over screen, gameover.asm)
CS_ROWP jsr ROW_PTR
        txa : clc : adc PTR2 : sta PTR2 : sta PTR3
        lda PTR2+1 : adc #0 : sta PTR2+1
        clc : adc #>(CRAM-SCRN) : sta PTR3+1
        rts

; A = screen code -> (PTR2),y, colour CS_C -> (PTR3),y
CS_PUT  sta (PTR2),y
        lda CS_C : sta (PTR3),y
        rts

; -----------------------------------------------------------------------------
; Strings. Dialog entries: speaker (0 commander, 1 agent), the text with 1
; between lines (at most 28 chars per line, 3 lines), 0; $FF ends the list.
; -----------------------------------------------------------------------------
CS_HEAD !pet "    defense command hq  -  0400 hours   "
!if * - CS_HEAD != 40 { !error "CS_HEAD must be 40 bytes" }

CS_DIALOG
        !byte 1 : !pet "you wanted to see me, sir?", 0
        !byte 0 : !pet "yes, agent 9. we have an", 1, "emergency at titan silo 17.", 0
        !byte 1 : !pet "what happened?", 0
        !byte 0 : !pet "the robots have taken over", 1, "the silo. the whole crew", 1, "is dead.", 0
        !byte 1 : !pet "who is behind this?", 0
        !byte 0 : !pet "we don't know. but they are", 1, "preparing a missile launch.", 0
        !byte 0 : !pet "the missile will be ready", 1, "in less than six hours.", 0
        !byte 1 : !pet "what about a military", 1, "strike?", 0
        !byte 0 : !pet "too dangerous. the silo", 1, "is built to take a hit.", 0
        !byte 0 : !pet "only a single agent can", 1, "get inside undetected.", 1, "it has to be you, 9.", 0
        !byte 1 : !pet "i'm on my way, sir.", 0
        !byte $FF
