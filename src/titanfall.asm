
; TITAN FALL  —  C64  (ACME assembler)
; =============================================================================
; Build : make
; Run   : make run
; =============================================================================
        !cpu 6510

; ---------------------------------------------------------------------------
; Music: our own tune, music/titan_theme.asm, packed at $C000 by exomizer
; ---------------------------------------------------------------------------
MUSIC_INIT = $C000
MUSIC_PLAY = $C003

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
REACT_JIT  = $0A   ; reactor display flicker 0-3 (on top of REACT_TEMP)
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
                   ; 7=explosion  8=cut scene
DEATH_TMR  = $1B   ; death pause countdown (= length of the death sound)
BLINK_TMR  = $1C   ; blink counter
BLINK_ST   = $1D   ; 0=text visible  1=hidden
SND_TMR    = $1E   ; sound effect frame counter (0=silent, music plays)
TERM_SEL   = $1F   ; terminal: selected menu entry (0..TERM_N-1)
NEAR_TERM  = $21   ; non-zero when player is adjacent to terminal
ROWS_PTR   = $23   ; $23/$24: DRAW_ROWS row-list pointer
PLR_DYING  = $22   ; 1 = player is sliding into a laser, 2 = into a pit (dies on arrival)
FIRE_PREV  = $20   ; fire/space held (0/1), as of this frame's READ_KEYS
SRCH_TMR   = $26   ; search: frames fire held (0 = not searching)
SRCH_ST    = $2C   ; search popup: 0 none, 1 "searching", 2 "nothing here"
PTR3       = $37   ; $37/$38: third pointer (search popup colour RAM)
SP_ROW     = $39   ; search popup: top screen row, left column,
SP_COL     = $3A   ;  row being processed, mode (SPOP)
SP_R       = $3B
SP_MODE    = $3C
CUR_ROOM   = $25   ; current room index (into world.asm ROOM_* tables)
NEWX       = $27   ; candidate tile X for the move being attempted
NEWY       = $28   ; candidate tile Y (MOVE_PLAYER/MOVE_ACTOR/patrol scratch)
PLR_DIR    = $29   ; player facing (DIR_*)
PLR_ANIM   = $2A   ; player walk frame: 0=rest 1=walk1 2=walk2
ANIM_CNT   = $2B   ; free-running game-frame counter (hover animation)
ROB_TMR    = $2D   ; robot movement timer (shared by all actors)
ROB_PHASE  = $3D   ; toggles every ROB_HALF frames: normal-pace actors step on 0
BOLT_ON    = $3E   ; 1 = a shooter's bolt is in flight (hw sprite 3; one at a time)
BOLT_DIR   = $3F   ; 0 = flying right, 1 = left
BOLT_XL    = $40   ; bolt centre X in room pixels (tile*16+8), 9 bits
BOLT_XH    = $41
BOLT_Y     = $42   ; bolt centre Y in room pixels (tile*16+8)
BOLT_PLR   = $43   ; 1 = the bolt was fired by a player-driven robot (can win)
PLAYER_MODE = $31  ; 0=human (control PLR_X/Y)  else actor index+1 (proxy mode)
LINK_S     = $32   ; robot link: seconds left (HUD "robot NN"; 0 -> human)
SND_KIND   = $45   ; sound effect playing: 0 = laser zap, 1 = explosion
EXPL_TMR   = $46   ; explosion (state 7): frames left
EXP_D011   = $47   ; explosion: $D011/$D016 saved before the shake
EXP_D016   = $48
FIELD_ACT  = $49   ; forcefield robot showing its field (hw sprite 4): actor+1, 0 = none
LA_ROOM    = $4A   ; LASER_AT_A: room whose lasers are checked
ENT_X      = $4B   ; where the player entered the current room: the
ENT_Y      = $4C   ;  respawn point after a death (SAVE_ENTRY)
RS_ALL     = $4D   ; RESET_ROUND: 1 = reset every room (new game), 0 = only CUR_ROOM
CR_IDX     = $4E   ; CRATE_PUSH: the crate being pushed
CR_OX      = $4F   ; CRATE_PUSH: its tile
CR_OY      = $50
CR_NX      = $51   ; CRATE_PUSH: the tile it's pushed onto
CR_NY      = $52
PS_WX      = $53   ; ACTOR_PATROL_STEP: the waypoint it heads for
PS_WY      = $54
CR_PIT     = $55   ; CRATE_PUSH: 1 = the crate goes into a pit (fills it)
TR_END     = $56   ; laser trap: first tile row its beam doesn't reach
TR_ROW     = $57   ; laser trap: map row being drawn
TRAP_ON    = $58   ; laser trap whose beam is on screen: index+1, 0 = none
TRAP_LEN   = $59   ; its reach (TR_END when it was drawn)
TR_MODE    = $5A   ; TRAP_ROWS: 0 = draw the beam, 1 = map chars back
TR_TRAP    = $5B   ; TRAP_ROWS: the trap (X)
LINK_JIF   = $44   ; robot link: frames into the current second (0-49)
POPUP_ST   = $33   ; popup: 0=waiting for opening space to be released, 1=armed
F2_PREV    = $30   ; F2 held last game frame (edge detect for the where-am-I popup)
JOY_PREV   = $34   ; joystick 2 bits held last frame (1=pressed, bits 0-4)
KEY_SPC    = $35   ; fire/space freshly pressed this frame (READ_KEYS)
JOY_NEW    = $36   ; joystick 2 bits newly pressed this frame (U/D/L/R/fire)
GL_SX      = $2E   ; GLIDE speed X (px/frame)
GL_SY      = $2F   ; GLIDE speed Y (px/frame)
; free zero-page slots: $30
; Robot positions, laser/item state etc. live in RAM arrays declared at the
; end of src/world.asm (ACT_X/Y, ACT_ALIVE, ITEM_STATE, LASER_STATE, ...).

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
SCRN       = $0400
CRAM       = $D800
SPRPTR     = $07F8
SPRP_PLAYER = sprite_down_rest/64   ; default pointers written after CLS
SPRP_ROBOT  = robot_down_rest/64    ; (ASSIGN_SPRITES / FRAME_PTR set the
SPRP_DRONE  = drone_down_hover/64   ;  real per-frame values in game state)
SPRP_BOLT   = bolt_1/64             ; shooter's bolt (bolt_1/bolt_2), sprite 3
SPRP_FIELD  = forcefield_1/64       ; forcefield robot's field (forcefield_1/2), sprite 4

; facings — also the frame-group order inside each sprite set
DIR_DOWN   = 0
DIR_UP     = 1
DIR_LEFT   = 2
DIR_RIGHT  = 3

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
VIC_SP3X   = $D006
VIC_SP3Y   = $D007
VIC_SPCOL3 = $D02A
VIC_SP4X   = $D008
VIC_SP4Y   = $D009
VIC_SPCOL4 = $D02B
VIC_BRDCOL = $D020
VIC_BGCOL  = $D021

CIA1_PRA   = $DC00
CIA1_PRB   = $DC01
CIA1_DDRA  = $DC02
CIA1_TALO  = $DC04
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
CH_SOLID = $E0   ; solid block (ROM glyph; $A0 is a room tile in our charset)


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

        ; Init music (titan_theme ignores A)
        lda #0
        jsr MUSIC_INIT

        ; VIC init
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$1E : sta VIC_VMCSB        ; screen $0400, custom charset $3800
        lda #$0E : sta $0291            ; stop KERNAL IRQ resetting charset

        ; Sprite pointers and config
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2
        lda TYPE_COLOR+ATYPE_HUMAN : sta VIC_SPCOL0  ; slots 1-2 set by ASSIGN_SPRITES
        lda #WHITE : sta VIC_SPCOL3     ; the bolt's hot core
        lda #$1F   : sta $D01C          ; sprites 0-4 multicolour
        lda #DGRAY : sta $D025          ; MC0 (%01) — outlines
        lda #LTGRAY : sta $D026         ; MC1 (%11) — shared light grey
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
        lda #SPRP_PLAYER : sta SPRPTR
        lda #SPRP_ROBOT  : sta SPRPTR+1
        lda #SPRP_DRONE  : sta SPRPTR+2
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
        ; previous screen can't immediately trigger the next one. The Space
        ; key counts as fire (bit 4) everywhere — read from the matrix here,
        ; not via GETIN, so the KERNAL's Space key repeat can't fake a press.
        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRA : eor #$FF : and #$1F : tax
        lda #$7F : sta CIA1_PRA          ; Space: col 7 (PA=$7F), row 4
        lda CIA1_PRB : and #$10 : bne MLNOSPC
        txa : ora #$10 : tax             ; Space = fire
MLNOSPC lda #$FF : sta CIA1_PRA
        txa
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
MLNOT5  cmp #6 : bne MLNOT6
        jmp DO_POPUP
MLNOT6  cmp #7 : bne MLNOT7
        jmp DO_EXPLODE
MLNOT7  jmp DO_CUTSCENE

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
; FRAME_EDGES — box rows are drawn one colour per row, so the frame's "|"
; ends pick up each row's text colour. Call this after drawing a box to
; repaint its two side columns in the frame colour.
; A = frame colour, X = first screen row, Y = last screen row; FRAME_EDGES
; uses columns 0 and 39, FRAME_EDGES_LR the columns preset in FR_L/FR_R.
; Clobbers A/X/Y/TMP/TMP2/PTR2.
; =============================================================================
FR_L    !byte 0
FR_R    !byte 39
FR_LAST !byte 0

FRAME_EDGES
        pha
        lda #0  : sta FR_L
        lda #39 : sta FR_R
        pla
FRAME_EDGES_LR
        sta TMP                          ; colour
        stx TMP2                         ; first row
        sty FR_LAST
        lda #<CRAM : sta PTR2
        lda #>CRAM : sta PTR2+1
        ldx #0                           ; row of PTR2
FREL    cpx TMP2 : bcc FRENEXT
        lda TMP
        ldy FR_L : sta (PTR2),y
        ldy FR_R : sta (PTR2),y
FRENEXT cpx FR_LAST : beq FREDONE
        lda PTR2 : clc : adc #40 : sta PTR2
        bcc FRENC : inc PTR2+1
FRENC   inx : bne FREL
FREDONE rts

; =============================================================================
; Row drawing. ROW_PTR: A = screen row -> PTR2 = its screen address
; (preserves X/Y). DRAW_ROW: A = screen row, PTR = 40-byte PETSCII string,
; TMP2 = colour; leaves PTR2 = the row's screen address. PAINT_ROW: A =
; colour for the whole row at PTR2. DRAW_ROWS: A/Y = lo/hi of a row list
; of (screen row, colour, string lo, string hi) entries ended by $FF.
; DRAW_ROW/PAINT_ROW/DRAW_ROWS preserve X; clobber A/Y/TMP (+TMP2/PTR).
; DR_L/DR_R limit them to a column window (the string is still 40 bytes,
; only its cols DR_L..DR_R are drawn) — whoever narrows it restores 0/39.
; =============================================================================
DR_L    !byte 0
DR_R    !byte 39

ROW_PTR
        asl : asl : asl : sta TMP        ; row*8 (< 256 for rows 0-24)
        lda #0 : sta PTR2+1
        lda TMP : asl : rol PTR2+1
        asl : rol PTR2+1                 ; row*32, C clear
        adc TMP : sta PTR2               ; + row*8 = row*40
        lda PTR2+1 : adc #>SCRN : sta PTR2+1
        rts

DRAW_ROW
        jsr ROW_PTR
        ldy DR_R
DRWL    lda (PTR),y : jsr PET2SCREEN : sta (PTR2),y
        cpy DR_L : beq DRWE
        dey : bpl DRWL
DRWE    lda TMP2
PAINT_ROW
        pha
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        pla : ldy DR_R
PRWL    sta (PTR2),y
        cpy DR_L : beq PRWE
        dey : bpl PRWL
PRWE    lda PTR2+1 : sec : sbc #>(CRAM-SCRN) : sta PTR2+1
        rts

DRAW_ROWS
        sta ROWS_PTR : sty ROWS_PTR+1
DRSL    ldy #0 : lda (ROWS_PTR),y : bmi DRSDONE
        pha
        iny : lda (ROWS_PTR),y : sta TMP2
        iny : lda (ROWS_PTR),y : sta PTR
        iny : lda (ROWS_PTR),y : sta PTR+1
        lda ROWS_PTR : clc : adc #4 : sta ROWS_PTR
        bcc DRSNC : inc ROWS_PTR+1
DRSNC   pla : jsr DRAW_ROW
        jmp DRSL
DRSDONE rts

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
        lda SND_TMR : beq RIRQ_MUSIC   ; sound effect playing: it owns
        jsr SOUND_TICK                 ;  the SID, music waits (game.asm)
        jmp $EA31
RIRQ_MUSIC
        jsr MUSIC_PLAY                 ; music play
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
; State modules. Only game.asm (the per-frame gameplay code) stays down here
; in the code area below the sprite block; the other state modules are
; CPU-only code and live above $4000, after the world data (see the end of
; this file). The code area is bounded by SPRITES_START — check headroom
; (CLAUDE.md, TILE_COLORS gotcha).
; =============================================================================
        !source "src/game.asm"
        !source "src/charset.asm"

; =============================================================================
; Sprites — multicolour, 64-byte frames, packed to end right below CHARSET
; ($3800, the top 2K of VIC bank 0 — charset.asm). Sprite pointers are 8-bit
; (address/64), so every frame must sit below $4000; packing the block down
; from the charset leaves all the space from $0810 up to SPRITES_START for
; code. ACME can't set * from a forward reference, so SPRITE_FRAMES is kept
; by hand — the !error below fires if it doesn't match the sources. Every
; frame added here costs 64 bytes of code space.
; Shared colours: $D025 (MC0) = black, $D026 (MC1) = light grey; the
; per-sprite colour comes from TYPE_COLOR. Each actor type points at its
; first frame (sprite: in titan.yaml); frames follow as rest/walk1/walk2 (or
; hover/move1/move2) per facing, facings in down/up/left/right order —
; FRAME_PTR in game.asm picks the frame. Every actor set has all 4 facings
; (12 frames).
; =============================================================================
SPRITE_FRAMES = 12+12+12+12+12+2+2+4
        * = CHARSET - SPRITE_FRAMES*64
SPRITES_START
        !source "src/c64_walker_sprites.asm"    ; player:  12 frames
        !source "src/c64_robot_sprites.asm"     ; robot:   12 frames
        !source "src/c64_drone_sprites.asm"     ; drone:   12 frames
        !source "src/c64_dozer_sprites.asm"     ; dozer:   12 frames
        !source "src/c64_tripod_sprites.asm"    ; tripod:  12 frames
        !source "src/c64_bolt_sprites.asm"      ; bolt:     2 frames (shooter)
        !source "src/c64_forcefield_sprites.asm" ; field:   2 frames (forcefield)
CS_FRAMES                                       ; cut scene:  4 frames, filled
        !fill 4*64, 0                           ;  by SETUP_CUTSCENE (cutscene.asm)
SPRITES_END
!if SPRITES_END != CHARSET {
        !error "SPRITE_FRAMES doesn't match the sprite files - update it"
}

; Everything below is CPU-only data (no VIC access): above the charset,
; from $4000 up to the music at $C000.
        * = CHARSET + $800
        !source "src/titanfall_title.asm"     ; intro logo (data only)

; =============================================================================
; World data — generated from titan.yaml by tools/genworld.py (make target).
; Room maps, actor/item/door/laser/terminal tables and runtime state arrays.
; =============================================================================
        !source "src/world.asm"

; =============================================================================
; CPU-only state modules — code with no VIC constraint, so it lives up here
; (anywhere below the music at $C000) instead of eating the code area below
; the sprite block. Each module ends in rts/jmp or data, so the order
; doesn't matter (no fall-through between modules).
; =============================================================================
        !source "src/intro.asm"
        !source "src/gameover.asm"
        !source "src/win.asm"
        !source "src/terminal.asm"
        !source "src/map.asm"
        !source "src/popup.asm"
        !source "src/cutscene.asm"
        !source "src/orders.asm"
        !source "src/crates.asm"
        !source "src/traps.asm"
HIGH_END
!if HIGH_END > $C000 {
        !error "code/data above $4000 runs into the music at $C000"
}

        !eof
