
; TITAN FALL  —  C64  (ACME assembler)
; =============================================================================
; Build : make
; Run   : make run
; =============================================================================
        !cpu 6510

; ---------------------------------------------------------------------------
; Zero page
; ---------------------------------------------------------------------------
PLR_X      = $02
PLR_Y      = $03
CLK_H      = $04
CLK_M      = $05
CLK_S      = $06
CLK_TICK   = $07
REACT_TEMP = $08
REACT_CNT  = $09
REACT_JIT  = $0A
LFSR_ST    = $0B
MOVE_TMR   = $0C
TICK_FLAG  = $0D
BFLASH     = $0E
KEY_U      = $0F
KEY_D      = $10
KEY_L      = $11
KEY_R      = $12
PTR        = $14
PTR2       = $16
TMP        = $18
TMP2       = $19
GAME_STATE = $1A   ; 0=intro  1=game  2=gameover  3=terminal  4=win  5=map  6=popup
DEATH_TMR  = $1B   ; countdown after laser hit
BLINK_TMR  = $1C   ; blink counter
BLINK_ST   = $1D   ; 0=text visible  1=hidden
SND_TMR    = $1E   ; death sound frame counter (0=silent)
TERM_SEL   = $1F   ; terminal: selected drone row (0-3)
TERM_TMR   = $20   ; terminal: link confirmation countdown
NEAR_TERM  = $21   ; non-zero when player is adjacent to terminal
KEY_RET    = $23   ; Return key flag
KEY_ESC    = $24   ; F7/Escape key flag (exit terminal)
CUR_ROOM   = $25   ; current room index (into world.asm ROOM_* tables)
KEY_MAP    = $26   ; M key flag (open map)
NEWX       = $27   ; candidate tile X for the move being attempted
NEWY       = $28   ; candidate tile Y (MOVE_PLAYER/MOVE_ACTOR/patrol scratch)
ROB_TMR    = $2D   ; robot movement timer (shared by all actors)
PLAYER_MODE = $31  ; 0=human (control PLR_X/Y)  else actor index+1 (proxy mode)
KEY_X      = $32   ; X key flag (exit robot proxy mode)
POPUP_ST   = $33   ; popup: 0=waiting for opening space to be released, 1=armed
JOY_PREV   = $34   ; joystick 2 bits held last frame (1=pressed, bits 0-4)
KEY_SPC    = $35   ; space key flag (search / enter terminal)
JOY_NEW    = $36   ; joystick 2 bits newly pressed this frame (U/D/L/R/fire)
; free zero-page slots: $29-$2C, $2E-$30
; Robot positions, laser/item state etc. live in RAM arrays declared at the
; end of src/world.asm (ACT_X/Y, ACT_ALIVE, ITEM_STATE, LASER_STATE, ...).

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
SCRN       = $0400
CRAM       = $D800
SPRPTR     = $07F8
SPRDAT0    = $3F40   ; 64-byte aligned — $3F40/64=$FD
SPRDAT1    = $3F00   ; 64-byte aligned — $3F00/64=$FC
SPRDAT2    = $3F80   ; 64-byte aligned — $3F80/64=$FE

VIC_SP0X   = $D000
VIC_SP0Y   = $D001
VIC_SP_MSB = $D010
VIC_CR1    = $D011
VIC_RASTER = $D012
VIC_VMCSB  = $D018
VIC_IRQ    = $D019
VIC_IRQEN  = $D01A
VIC_SPEN   = $D015
VIC_SPCOLL = $D01E   ; sprite-sprite collision (read clears)
VIC_SPCOL0 = $D027
VIC_SPCOL2 = $D029
VIC_SP1X   = $D002
VIC_SP1Y   = $D003
VIC_SPCOL1 = $D028
VIC_SP2X   = $D004
VIC_SP2Y   = $D005
VIC_BRDCOL = $D020
VIC_BGCOL  = $D021

CIA1_PRA   = $DC00
CIA1_PRB   = $DC01
CIA1_DDRA  = $DC02
CIA1_ICR   = $DC0D

GETIN      = $FFE4

BLACK=0:WHITE=1:RED=2:CYAN=3:PURPLE=4:GREEN=5:BLUE=6:YELLOW=7
ORANGE=8:BROWN=9:LTRED=10:DGRAY=11:MGRAY=12:LTGREEN=13:LTBLUE=14:LTGRAY=15

CH_SPC  = $20
CH_HASH = $23
CH_PLUS = $2B
CH_DASH = $2D
CH_0    = $30
CH_COLN = $3A
CH_EQ   = $3D
CH_BANG = $21
CH_BAR  = $7C
CH_LBRK = $5B
CH_RBRK = $5D
CH_HBLK = $A0


; =============================================================================
; Include PETSCII constants
; =============================================================================
        !source "src/petscii.asm"

; =============================================================================
; BASIC stub
; =============================================================================
        * = $0801
        !word (+), 10
        !byte $9E
        !pet "2064"
        !byte 0
+       !word 0

; =============================================================================
; Entry point $0810
; Hardware init only — falls through into SHOW_INTRO.
; =============================================================================
        * = $0810

        sei

        ; Disable CIA1's Timer A IRQ (KERNAL jiffy clock). Left running, it
        ; keeps firing (~60Hz) through the same $0314 vector as our raster
        ; IRQ, so RASTER_IRQ runs on both sources combined (~110Hz) instead
        ; of just the raster's 50Hz — doubling music tempo and clock speed.
        lda #$7F   : sta CIA1_ICR        ; disable all CIA1 IRQ sources
        lda CIA1_ICR                     ; ack any pending CIA1 IRQ

        ; Silence SID
        ldx #$18
SIDCLR  lda #0
        sta $D400,x
        dex
        bpl SIDCLR

        ; Init music (song 1; A must be 0)
        lda #0
        jsr $C000

        ; VIC init
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$1A : sta VIC_VMCSB        ; screen $0400, custom charset $2800
        lda #$0E : sta $0291            ; stop KERNAL IRQ resetting charset

        ; Sprite pointers and config
        lda #$FD   : sta SPRPTR         ; spr0 → $3F40
        lda #$FC   : sta SPRPTR+1       ; spr1 → $3F00
        lda #$FE   : sta SPRPTR+2       ; spr2 → $3F80
        lda #CYAN  : sta VIC_SPCOL0     ; player; slots 1-2 set by ASSIGN_SPRITES
        lda #$00   : sta $D01C
        lda #$00   : sta $D01D
        lda #$00   : sta $D017

        ; Raster IRQ at line 50
        lda #<RASTER_IRQ : sta $0314
        lda #>RASTER_IRQ : sta $0315
        lda VIC_CR1 : and #$7F : sta VIC_CR1
        lda #50     : sta VIC_RASTER
        lda #$01    : sta VIC_IRQEN
        lda #$FF    : sta VIC_IRQ

        lda #0      : sta SND_TMR       ; ensure music plays from first IRQ
        lda #$1F    : sta JOY_PREV      ; treat a stick held at boot as old
        lda #0      : sta JOY_NEW

        cli

        ; ---- fall into INTRO state ----

; =============================================================================
; SHOW_INTRO
; Called by fall-through from init and by gameover/win when key pressed.
; Must NOT be entered via jsr — falls into MAIN_LOOP.
; =============================================================================
SHOW_INTRO
        lda #0 : sta GAME_STATE
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$00   : sta VIC_SPEN
        lda #0     : sta BLINK_TMR
        lda #0     : sta BLINK_ST

        jsr CLS
        lda #$FD   : sta SPRPTR
        lda #$FC   : sta SPRPTR+1
        lda #$FE   : sta SPRPTR+2
        jsr DRAW_INTRO_SCREEN

        ; ---- fall into MAIN_LOOP ----

; =============================================================================
; MAIN_LOOP — ticked at 50 Hz by raster IRQ
; =============================================================================
MAIN_LOOP
        lda TICK_FLAG
        beq MAIN_LOOP
        lda #0 : sta TICK_FLAG

        ; Poll joystick 2 once per frame: JOY_NEW = bits pressed now but not
        ; last frame (1=pressed; 0 up, 1 down, 2 left, 3 right, 4 fire).
        ; Menus and fire actions use JOY_NEW, so a press held over from the
        ; previous screen can't immediately trigger the next one.
        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRA : eor #$FF : and #$1F : tax
        eor JOY_PREV : sta JOY_NEW
        txa : and JOY_NEW : sta JOY_NEW
        stx JOY_PREV

        lda GAME_STATE
        bne MLNOT0
        jmp DO_INTRO
MLNOT0  cmp #1 : bne MLNOT1
        jmp DO_GAME
MLNOT1  cmp #2 : bne MLNOT2
        jmp DO_GAMEOVER
MLNOT2  cmp #3 : bne MLNOT3
        jmp DO_TERMINAL
MLNOT3  cmp #4 : bne MLNOT4
        jmp DO_WIN
MLNOT4  cmp #5 : bne MLNOT5
        jmp DO_MAP
MLNOT5  jmp DO_POPUP

; =============================================================================
; CLS — clears all 1024 bytes of screen + colour RAM
; After every call: restore sprite pointers at $07F8/$07F9.
; =============================================================================
CLS
        lda #<SCRN : sta PTR  : lda #>SCRN : sta PTR+1
        lda #<CRAM : sta PTR2 : lda #>CRAM : sta PTR2+1
        ldx #4
        ldy #0
CLSP    lda #CH_SPC : sta (PTR),y
        lda #LTGRAY : sta (PTR2),y
        iny
        bne CLSP
        inc PTR+1 : inc PTR2+1
        dex
        bne CLSP
        rts

; =============================================================================
; PET2SCREEN — convert PETSCII (A) to C64 screen code (A)
; $20-$3F → same  |  $40-$5F → -$40  |  $60-$7F → -$20
; $A0-$BF → -$40  |  $C0-$FF → -$80  |  others  → unchanged
; =============================================================================
PET2SCREEN
        cmp #$40 : bcc P2S_OUT      ; $00-$3F: identity
        cmp #$60 : bcc P2S_SUB40    ; $40-$5F: A-Z, brackets
        cmp #$80 : bcc P2S_SUB20    ; $60-$7F: a-z, |
        cmp #$A0 : bcc P2S_OUT      ; $80-$9F: control — pass through
        cmp #$C0 : bcc P2S_SUB40    ; $A0-$BF: graphics
        sec : sbc #$80 : rts        ; $C0-$FF: graphics
P2S_SUB40
        sec : sbc #$40 : rts
P2S_SUB20
        sec : sbc #$20 : rts
P2S_OUT rts

; =============================================================================
; RASTER IRQ — fires at line 50, ~50 Hz PAL
; =============================================================================
RASTER_IRQ
        lda #$01 : sta VIC_IRQ
        lda #$01 : sta TICK_FLAG
        lda SND_TMR : bne RIRQ_SKIP    ; skip music while death sound plays
        jsr $C127                      ; music play
RIRQ_SKIP
        jmp $EA31

; =============================================================================
; Shared box strings — used by intro, gameover, and win screens
; =============================================================================
;SCR_BORDER  !pet "+--------------------------------------+"
;SCR_BLANK   !pet "G_VERT_BAR                                      G_VERT_BAR
;ITR_SEP     !pet "G_VERT_BAR  ==================================  G_VERT_BAR
SCR_BORDER_TOP  !pet G_RD_UL, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_RD_UR
SCR_BLANK   !pet G_VERT_BAR, "                                      ", G_VERT_BAR
ITR_SEP    !pet G_VERT_BAR, "  ==================================  " , G_VERT_BAR
SCR_BORDER_BOTTOM  !pet G_RD_LL, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_RD_LR

; =============================================================================
; State modules
; =============================================================================
        !source "src/intro.asm"
        !source "src/game.asm"
        !source "src/gameover.asm"
        !source "src/win.asm"
        !source "src/terminal.asm"
        !source "src/map.asm"
        !source "src/popup.asm"
        !source "src/charset.asm"

; =============================================================================
; Sprite 1 — robot enemy, at $3F00 (pointer $FC)
; Top-down drone: square head, wide shoulders, split legs
; =============================================================================
        * = $3F00
SPR_ROBOT
        !byte $0F,$F0,$00   ; row  0  head top
        !byte $0F,$F0,$00   ; row  1
        !byte $0F,$F0,$00   ; row  2
        !byte $06,$60,$00   ; row  3  eye row
        !byte $0F,$F0,$00   ; row  4
        !byte $0F,$F0,$00   ; row  5  head bottom
        !byte $3F,$FC,$00   ; row  6  shoulder
        !byte $3F,$FC,$00   ; row  7
        !byte $3F,$FC,$00   ; row  8  body
        !byte $3F,$FC,$00   ; row  9
        !byte $3F,$FC,$00   ; row 10
        !byte $1F,$F8,$00   ; row 11  waist
        !byte $0F,$F0,$00   ; row 12
        !byte $0E,$E0,$00   ; row 13  legs
        !byte $0E,$E0,$00   ; row 14
        !byte $0E,$E0,$00   ; row 15
        !byte $0E,$E0,$00   ; row 16
        !byte $0E,$E0,$00   ; row 17
        !byte $0E,$E0,$00   ; row 18
        !byte $1E,$F0,$00   ; row 19  feet
        !byte $1E,$F0,$00   ; row 20
        !byte $00           ; byte 63

; =============================================================================
; Sprite 0 — player, at $3F40 (pointer $FD)
; Top-down person: oval head, shoulders+torso, two legs
; =============================================================================
        * = $3F40
SPR_PLAYER
        !byte $00,$FC,$00   ; row  0  head top
        !byte $03,$FF,$00   ; row  1
        !byte $07,$FF,$80   ; row  2
        !byte $0F,$FF,$C0   ; row  3
        !byte $0F,$FF,$C0   ; row  4
        !byte $0F,$FF,$C0   ; row  5
        !byte $0F,$FF,$C0   ; row  6
        !byte $07,$FF,$80   ; row  7
        !byte $03,$FF,$00   ; row  8
        !byte $00,$FC,$00   ; row  9  head bottom
        !byte $00,$00,$00   ; row 10  neck gap
        !byte $39,$F8,$E0   ; row 11  shoulders + torso
        !byte $7D,$F9,$F0   ; row 12
        !byte $7D,$F9,$F0   ; row 13
        !byte $7D,$F9,$F0   ; row 14
        !byte $39,$F8,$E0   ; row 15
        !byte $00,$00,$00   ; row 16  waist gap
        !byte $07,$9E,$00   ; row 17  legs
        !byte $07,$9E,$00   ; row 18
        !byte $07,$9E,$00   ; row 19
        !byte $07,$9E,$00   ; row 20  feet
        !byte $00           ; byte 63

; =============================================================================
; Sprite 2 — splicer robot, at $3F80 (pointer $FE)
; Maintenance Splicer drone: diamond sensor head, hex torso, single tapering
; tail/tread — visually distinct from the square-headed SPR_ROBOT.
; =============================================================================
        * = $3F80
SPR_ROBOT2
        !byte $00,$F0,$00   ; row  0  head tip
        !byte $03,$FC,$00   ; row  1
        !byte $0F,$FF,$00   ; row  2  widest
        !byte $0F,$FF,$00   ; row  3
        !byte $03,$FC,$00   ; row  4
        !byte $00,$84,$00   ; row  5  sensor slit
        !byte $00,$F0,$00   ; row  6  neck
        !byte $01,$FC,$00   ; row  7  torso shoulder
        !byte $03,$FE,$00   ; row  8  torso
        !byte $02,$64,$00   ; row  9  torso vents
        !byte $03,$FE,$00   ; row 10  torso
        !byte $03,$FE,$00   ; row 11  torso
        !byte $01,$FC,$00   ; row 12  torso taper
        !byte $00,$7C,$00   ; row 13  waist
        !byte $00,$38,$00   ; row 14  tail
        !byte $00,$38,$00   ; row 15
        !byte $00,$10,$00   ; row 16
        !byte $00,$38,$00   ; row 17
        !byte $00,$10,$00   ; row 18
        !byte $00,$38,$00   ; row 19
        !byte $00,$7C,$00   ; row 20  foot/tread
        !byte $00           ; byte 63

; =============================================================================
; World data — generated from titan.yaml by tools/genworld.py (make target).
; Room maps, actor/item/door/laser/terminal tables and runtime state arrays.
; =============================================================================
        !source "src/world.asm"

        !eof
