; =============================================================================
; TITAN FALL  —  C64  (ACME assembler)
; =============================================================================
; Build : acme -f cbm -o titanfall.prg titanfall.asm
; Run   : x64sc titanfall.prg
;
; Built by adding one feature at a time onto the known-good base.
; This version adds: intro screen → game → game-over → intro loop.
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
; New variables for state machine
GAME_STATE = $1A   ; 0=intro  1=game  2=gameover
DEATH_TMR  = $1B   ; countdown after laser hit
BLINK_TMR  = $1C   ; blink counter
BLINK_ST   = $1D   ; 0=text visible  1=hidden
SND_TMR    = $1E   ; death sound frame counter (0=silent)
TERM_SEL   = $1F   ; terminal: selected drone row (0-2)
TERM_TMR   = $20   ; terminal: link confirmation countdown
NEAR_TERM  = $21   ; non-zero when player is adjacent to terminal
KEY_F1     = $22   ; T key flag (enter terminal)
KEY_RET    = $23   ; Return key flag
KEY_ESC    = $24   ; F7/Escape key flag (exit terminal)

; ---------------------------------------------------------------------------
; Hardware
; ---------------------------------------------------------------------------
SCRN       = $0400
CRAM       = $D800
SPRPTR     = $07F8
SPRDAT0    = $3F40   ; 64-byte aligned — $3F40/64=$FD, safely above all code

VIC_SP0X   = $D000
VIC_SP0Y   = $D001
VIC_SP_MSB = $D010
VIC_CR1    = $D011
VIC_RASTER = $D012
VIC_VMCSB  = $D018
VIC_IRQ    = $D019
VIC_IRQEN  = $D01A
VIC_SPEN   = $D015
VIC_SPCOL0 = $D027
VIC_BRDCOL = $D020
VIC_BGCOL  = $D021

CIA1_PRA   = $DC00
CIA1_PRB   = $DC01
CIA1_DDRA  = $DC02

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
; The ONLY things that happen here are hardware init.
; We then fall straight into the INTRO state — no jsr, no jmp, just fall.
; =============================================================================
        * = $0810

        sei

        ; Silence SID
        ldx #$18
SIDCLR  lda #0
        sta $D400,x
        dex
        bpl SIDCLR

        ; VIC init
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        ; Lowercase charset: D018=$16 (screen $0400, chars $1800)
        ; $0291 = KERNAL charset flag ($0E=lower) — stops EA31 resetting it
        lda #$16 : sta VIC_VMCSB
        lda #$0E : sta $0291

        ; Sprite pointer — data lives at $3F40 (placed there by assembler)
        lda #$FD   : sta SPRPTR     ; $3F40/64 = $FD
        lda #CYAN  : sta VIC_SPCOL0
        lda #$00   : sta $D01C
        lda #$00   : sta $D01D
        lda #$00   : sta $D017

        ; Raster IRQ
        lda #<RASTER_IRQ : sta $0314
        lda #>RASTER_IRQ : sta $0315
        lda VIC_CR1 : and #$7F : sta VIC_CR1
        lda #50     : sta VIC_RASTER
        lda #$01    : sta VIC_IRQEN
        lda #$FF    : sta VIC_IRQ

        cli

        ; ---- fall into INTRO state ----

; =============================================================================
; SHOW_INTRO
; Called by: fall-through from init, and by GAMEOVER when key pressed.
; Draws intro screen, sets GAME_STATE=0, then falls into MAIN_LOOP.
; Must NOT be entered via jsr — it falls into MAIN_LOOP.
; =============================================================================
SHOW_INTRO
        lda #0 : sta GAME_STATE
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$00   : sta VIC_SPEN       ; sprite off
        lda #0     : sta BLINK_TMR
        lda #0     : sta BLINK_ST

        jsr CLS
        lda #$FD   : sta SPRPTR     ; CLS wiped $07F8 — restore sprite pointer

        ; Row 5 — title
        ldx #39
IROW5   lda TXT_TITLE,x
        sta SCRN+200,x
        lda #PURPLE
        sta CRAM+200,x
        dex
        bpl IROW5
        lda #YELLOW : sta CRAM+213 : sta CRAM+226

        ; Row 7 — tagline
        ldx #39
IROW7   lda TXT_TAG,x
        sta SCRN+280,x
        lda #CYAN
        sta CRAM+280,x
        dex
        bpl IROW7

        ; Row 9 — divider
        ldx #39
IROW9   lda #CH_HBLK
        sta SCRN+360,x
        lda #BLUE
        sta CRAM+360,x
        dex
        bpl IROW9

        ; Row 20 — "press space" (starts visible)
        jsr BLINK_ON

        ; ---- fall into MAIN_LOOP ----

; =============================================================================
; MAIN_LOOP — ticked at 50 Hz by raster IRQ
; Dispatches to the right handler based on GAME_STATE.
; =============================================================================
MAIN_LOOP
        lda TICK_FLAG
        beq MAIN_LOOP
        lda #0 : sta TICK_FLAG

        lda GAME_STATE
        beq DO_INTRO
        cmp #1 : beq DO_GAME
        cmp #2 : beq DO_GAMEOVER
        jmp DO_TERMINAL         ; state 3

DO_INTRO
        ; Check for keypress → start game
        jsr GETIN
        beq INTRO_NOBTN
        ; Key pressed — set up game and jump into game state
        jsr SETUP_GAME
        jmp MAIN_LOOP

INTRO_NOBTN
        ; Blink the prompt
        inc BLINK_TMR
        lda BLINK_TMR
        cmp #25
        bcc INTRO_DONE
        lda #0 : sta BLINK_TMR
        lda BLINK_ST
        bne INTRO_SHOW
        jsr BLINK_OFF
        lda #1 : sta BLINK_ST
        jmp INTRO_DONE
INTRO_SHOW
        jsr BLINK_ON
        lda #0 : sta BLINK_ST
INTRO_DONE
        jmp MAIN_LOOP

; ---------------------------------------------------------------------------
DO_GAME
        jsr SOUND_TICK          ; always tick sound, even during death wait

        ; Death timer running?
        lda DEATH_TMR
        beq GAME_ALIVE
        dec DEATH_TMR
        bne GAME_TICK_DONE
        ; Timer expired — show gameover
        jsr SETUP_GAMEOVER
        jmp MAIN_LOOP

GAME_ALIVE
        jsr TICK_CLOCK
        jsr TICK_REACTOR
        jsr READ_KEYS
        jsr MOVE_PLAYER
        jsr UPDATE_SPRITE0
        jsr DRAW_HUD_DYNAMIC
        jsr DRAW_STATUS
GAME_TICK_DONE
        jmp MAIN_LOOP

; ---------------------------------------------------------------------------
DO_GAMEOVER
        ; Check for keypress → back to intro
        jsr GETIN
        beq GO_NOBTN
        ; Key pressed — go back to intro
        ; Can't jsr SHOW_INTRO (it falls into MAIN_LOOP).
        ; Instead: duplicate the intro setup inline, then jump to MAIN_LOOP.
        lda #0     : sta GAME_STATE
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL
        lda #$00   : sta VIC_SPEN
        lda #0     : sta BLINK_TMR
        lda #0     : sta BLINK_ST
        jsr CLS
        lda #$FD   : sta SPRPTR     ; CLS wiped $07F8 — restore sprite pointer
        ldx #39
GORESTART_T lda TXT_TITLE,x
        sta SCRN+200,x
        lda #PURPLE : sta CRAM+200,x
        dex
        bpl GORESTART_T
        lda #YELLOW : sta CRAM+213 : sta CRAM+226
        ldx #39
GORESTART_G lda TXT_TAG,x
        sta SCRN+280,x
        lda #CYAN : sta CRAM+280,x
        dex
        bpl GORESTART_G
        ldx #39
GORESTART_D lda #CH_HBLK
        sta SCRN+360,x
        lda #BLUE : sta CRAM+360,x
        dex
        bpl GORESTART_D
        jsr BLINK_ON
        jmp MAIN_LOOP

GO_NOBTN
        ; Blink prompt
        inc BLINK_TMR
        lda BLINK_TMR
        cmp #25
        bcc GO_DONE
        lda #0 : sta BLINK_TMR
        lda BLINK_ST
        bne GO_SHOW
        jsr GO_BLINK_OFF
        lda #1 : sta BLINK_ST
        jmp GO_DONE
GO_SHOW
        jsr GO_BLINK_ON
        lda #0 : sta BLINK_ST
GO_DONE
        jmp MAIN_LOOP

; =============================================================================
; SETUP_GAME — initialise vars and draw playfield. Called via jsr from DO_INTRO.
; =============================================================================
SETUP_GAME
        lda #1   : sta GAME_STATE
        lda #0   : sta $C6          ; flush kernal keyboard buffer
        lda #BLACK : sta VIC_BRDCOL : sta VIC_BGCOL

        lda #4   : sta PLR_X
        lda #4   : sta PLR_Y
        lda #5   : sta CLK_H
        lda #47  : sta CLK_M
        lda #33  : sta CLK_S
        lda #0   : sta CLK_TICK
        lda #23  : sta REACT_TEMP
        lda #0   : sta REACT_CNT
        lda #0   : sta REACT_JIT
        lda #$A3 : sta LFSR_ST
        lda #0   : sta MOVE_TMR
        lda #0   : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0   : sta DEATH_TMR
        lda #0   : sta BFLASH
        lda #0   : sta SND_TMR

        jsr CLS
        lda #$FD   : sta SPRPTR     ; CLS wiped $07F8 — restore sprite pointer
        jsr DRAW_HUD_STATIC
        jsr DRAW_ROOM

        lda #$01 : sta VIC_SPEN
        jsr UPDATE_SPRITE0
        rts

; =============================================================================
; SETUP_GAMEOVER — draw game over screen. Called via jsr from DO_GAME.
; =============================================================================
SETUP_GAMEOVER
        lda #2     : sta GAME_STATE
        lda #0     : sta $C6        ; flush kernal keyboard buffer (count = 0)
        lda #0     : sta SND_TMR    ; stop sound tick
        lda #$00   : sta $D404      ; SID gate off
        lda #$00   : sta $D418      ; SID volume off
        lda #$00   : sta VIC_SPEN
        lda #RED   : sta VIC_BRDCOL
        lda #BLACK : sta VIC_BGCOL
        lda #0     : sta BLINK_TMR
        lda #0     : sta BLINK_ST

        jsr CLS
        lda #$FD   : sta SPRPTR     ; CLS wiped $07F8 — restore sprite pointer

        ldx #39
GOROW8  lda TXT_GO1,x
        sta SCRN+320,x
        lda #LTRED : sta CRAM+320,x
        dex
        bpl GOROW8
        lda #YELLOW : sta CRAM+330 : sta CRAM+349

        ldx #39
GOROW10 lda TXT_GO2,x
        sta SCRN+400,x
        lda #WHITE : sta CRAM+400,x
        dex
        bpl GOROW10

        ldx #39
GOROW12 lda TXT_GO3,x
        sta SCRN+480,x
        lda #CYAN : sta CRAM+480,x
        dex
        bpl GOROW12

        ldx #39
GOROW14 lda #CH_HBLK
        sta SCRN+560,x
        lda #RED : sta CRAM+560,x
        dex
        bpl GOROW14

        jsr GO_BLINK_ON
        rts

; =============================================================================
; Blink helpers
; =============================================================================
BLINK_ON
        ldx #39
BLON    lda TXT_PRESS,x
        sta SCRN+800,x
        lda #WHITE : sta CRAM+800,x
        dex
        bpl BLON
        rts

BLINK_OFF
        ldx #39
BLOFF   lda #CH_SPC
        sta SCRN+800,x
        dex
        bpl BLOFF
        rts

GO_BLINK_ON
        ldx #39
GOBLON  lda TXT_GOPRESS,x
        sta SCRN+640,x
        lda #YELLOW : sta CRAM+640,x
        dex
        bpl GOBLON
        rts

GO_BLINK_OFF
        ldx #39
GOBLOFF lda #CH_SPC
        sta SCRN+640,x
        dex
        bpl GOBLOFF
        rts

; =============================================================================
; CLS
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
; DRAW_HUD_STATIC
; =============================================================================
DRAW_HUD_STATIC
        ldx #39
HUDST1  lda HUD_TMPL,x : sta SCRN,x
        lda #CYAN : sta CRAM,x
        dex
        bpl HUDST1
        ldx #39
HUDST2  lda #CH_HBLK : sta SCRN+40,x
        lda #BLUE : sta CRAM+40,x
        dex
        bpl HUDST2
        rts

HUD_TMPL
        !pet "00:00:00 human reactor:[        ]  0%   "

; =============================================================================
; DRAW_HUD_DYNAMIC
; =============================================================================
DRAW_HUD_DYNAMIC
        lda CLK_H : jsr DEC2
        lda TMP : sta SCRN+0 : lda TMP2 : sta SCRN+1
        lda #CH_COLN : sta SCRN+2
        lda CLK_M : jsr DEC2
        lda TMP : sta SCRN+3 : lda TMP2 : sta SCRN+4
        lda #CH_COLN : sta SCRN+5
        lda CLK_S : jsr DEC2
        lda TMP : sta SCRN+6 : lda TMP2 : sta SCRN+7

        lda #WHITE
        ldx CLK_H : bne HUDCC
        ldx CLK_M : cpx #10 : bcs HUDCC
        lda #LTRED
HUDCC   ldx #7
HUDCCL  sta CRAM,x : dex : bpl HUDCCL

        ldx #4
HUDML   lda LMODE_H,x : sta SCRN+9,x
        lda #CYAN : sta CRAM+9,x
        dex
        bpl HUDML

        lda REACT_TEMP
        cmp #40 : bcc HUDBG
        cmp #70 : bcc HUDBY
        lda #LTRED  : !byte $2C
HUDBG   lda #LTGREEN : !byte $2C
HUDBY   lda #YELLOW
        sta TMP2

        ldy #7
HUDBCLR lda #CH_SPC : sta SCRN+24,y
        lda #DGRAY  : sta CRAM+24,y
        dey
        bpl HUDBCLR

        lda REACT_TEMP : lsr : lsr : lsr : lsr
        tax
        beq HUDBD
        ldy #0
HUDBF   lda #CH_EQ : sta SCRN+24,y
        lda TMP2 : sta CRAM+24,y
        iny : dex : bne HUDBF
HUDBD
        lda REACT_TEMP : jsr DEC3
        lda DEC3BUF+0 : sta SCRN+33
        lda DEC3BUF+1 : sta SCRN+34
        lda DEC3BUF+2 : sta SCRN+35
        lda TMP2 : sta CRAM+33 : sta CRAM+34 : sta CRAM+35
        rts

LMODE_H !pet "human"

; =============================================================================
; DEC2 — A (0-99) → TMP=tens char  TMP2=units char
; =============================================================================
DEC2
        ldx #0
DEC2L   cmp #10 : bcc DEC2D
        sec : sbc #10 : inx : bne DEC2L
DEC2D   clc : adc #CH_0 : sta TMP2
        txa : clc : adc #CH_0 : sta TMP
        rts

; =============================================================================
; DEC3 — A (0-99) → 3 chars in DEC3BUF (space-padded left)
; =============================================================================
DEC3BUF !byte 0,0,0

DEC3
        jsr DEC2
        lda TMP : cmp #CH_0 : bne DEC3T
        lda #CH_SPC : sta DEC3BUF+0 : sta DEC3BUF+1
        lda TMP2 : sta DEC3BUF+2
        rts
DEC3T   lda #CH_SPC : sta DEC3BUF+0
        lda TMP : sta DEC3BUF+1
        lda TMP2 : sta DEC3BUF+2
        rts

; =============================================================================
; TICK_CLOCK
; =============================================================================
TICK_CLOCK
        inc CLK_TICK
        lda CLK_TICK : cmp #50 : bcc TCKOUT
        lda #0 : sta CLK_TICK
        lda CLK_S : bne TCKDS
        lda #59 : sta CLK_S
        lda CLK_M : bne TCKDM
        lda #59 : sta CLK_M
        lda CLK_H : beq TCKOUT
        dec CLK_H : bne TCKOUT
TCKDM   dec CLK_M : bne TCKOUT
TCKDS   dec CLK_S
TCKOUT  rts

; =============================================================================
; TICK_REACTOR
; =============================================================================
TICK_REACTOR
        lda LFSR_ST : asl : bcc RCTNFB : eor #$B8
RCTNFB  sta LFSR_ST
        inc REACT_JIT
        lda REACT_JIT : and #$07 : bne RCTDR
        lda LFSR_ST : and #$01 : beq RCTJDN
        lda REACT_TEMP : cmp #99 : bcs RCTDR
        inc REACT_TEMP : bne RCTDR
RCTJDN  lda REACT_TEMP : beq RCTDR : dec REACT_TEMP
RCTDR   inc REACT_CNT
        lda REACT_CNT : cmp #180 : bcc RCTOUT
        lda #0 : sta REACT_CNT
        lda REACT_TEMP : cmp #99 : bcs RCTOUT
        inc REACT_TEMP
RCTOUT  rts

; =============================================================================
; READ_KEYS
; Reads joystick port 2 + cursor keys → KEY_U/D/L/R
; Also reads F1 (enter terminal), Return (select), F7 (exit terminal)
;
; C64 keyboard matrix (relevant rows):
;   Row 0 ($FE): bit7=CRSR-DN, bit2=CRSR-RT
;   Row 1 ($FD): bit7=R-SHIFT
;   Row 4 ($EF): bit2=SPACE, bit3=F7
;   Row 5 ($DF): bit4=F1, bit5=F3, bit6=F5, bit7=F7 (actually: see below)
;
; Correct C64 matrix positions:
;   F1: row 0 ($FE), bit 0  (low = pressed)
;   F7: row 4 ($EF), bit 3
;   Return: row 0 ($FE), bit 1... actually:
;   Return: row 5 ($DF), bit 0 (col 0 = bit0, PA0→row5→PB0)
;   Wait — standard C64 matrix:
;     PA selects column (active low), PB reads row (active low)
;     F1: col 0 (PA=$FE), row 4 (PB bit4)
;     Return: col 1 (PA=$FD), row 5 (PB bit0)... 
;   Actually the standard matrix is:
;     F1: PA=$FE (col0), PB bit 4
;     Return: PA=$FD (col1), PB bit 1... let's use definitive values:
;     F1     col7/row4: PA=$7F, PB bit4
;     Return col1/row1: PA=$FD, PB bit1... 
;
; Definitive C64 key matrix (from C64 wiki):
;   F1: PA bit7=0 (col7), PB bit6=0  → PA=$7F, PRB and #$40
;   Return: PA bit1=0 (col1), PB bit1=0 → PA=$FD, PRB and #$02
;   F7: PA bit7=0 (col7), PB bit3=0 → PA=$7F, PRB and #$08
; =============================================================================
READ_KEYS
        lda #0 : sta KEY_U : sta KEY_D : sta KEY_L : sta KEY_R
        lda #0 : sta KEY_F1 : sta KEY_RET : sta KEY_ESC

        ; Joystick port 2 (CIA1 port B, active low)
        lda #$FF : sta CIA1_DDRA : sta CIA1_PRA
        lda CIA1_PRB : sta TMP
        lda TMP : and #$01 : bne RKJ1 : lda #1 : sta KEY_U
RKJ1    lda TMP : and #$02 : bne RKJ2 : lda #1 : sta KEY_D
RKJ2    lda TMP : and #$04 : bne RKJ3 : lda #1 : sta KEY_L
RKJ3    lda TMP : and #$08 : bne RKJ4 : lda #1 : sta KEY_R
RKJ4
        ; Cursor keys (row 0)
        lda #$FE : sta CIA1_PRA
        lda CIA1_PRB : sta TMP
        lda TMP : and #$80 : bne RKCUD
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : bne RKCDN
        lda #1 : sta KEY_U : !byte $2C
RKCDN   lda #1 : sta KEY_D
RKCUD
        lda #$FE : sta CIA1_PRA
        lda CIA1_PRB : and #$04 : bne RKCRT
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$80 : bne RKCRIGHT
        lda #1 : sta KEY_L : !byte $2C
RKCRIGHT lda #1 : sta KEY_R
RKCRT

        ; T key: col 2 (PA=$FB), row 4 (PB bit 4, active low)
        lda #$FB : sta CIA1_PRA
        lda CIA1_PRB : and #$10 : bne RKF1N
        lda #1 : sta KEY_F1
RKF1N

        ; Return: col 1 (PA=$FD), row 5 (PB bit 5... 
        ; Actually: Return is at col1/row1 on C64 — PA=$FD, PB bit1
        lda #$FD : sta CIA1_PRA
        lda CIA1_PRB : and #$02 : bne RKRETN
        lda #1 : sta KEY_RET
RKRETN

        ; F7: col 7 (PA=$7F), row 4 (PB bit 3, active low)
        lda #$7F : sta CIA1_PRA
        lda CIA1_PRB : and #$08 : bne RKESCN
        lda #1 : sta KEY_ESC
RKESCN

        ; Check proximity to terminal: PLR_X 1-3, PLR_Y 3-5
        lda #0 : sta NEAR_TERM
        lda PLR_X : cmp #1 : bcc RKDONE
        cmp #4 : bcs RKDONE
        lda PLR_Y : cmp #3 : bcc RKDONE
        cmp #6 : bcs RKDONE
        lda #1 : sta NEAR_TERM
        ; If F1 pressed near terminal → enter terminal state
        lda KEY_F1 : beq RKDONE
        jsr SETUP_TERMINAL
RKDONE  rts

; =============================================================================
; MOVE_PLAYER
; =============================================================================
MOVE_PLAYER
        lda MOVE_TMR : beq MOVEGO
        dec MOVE_TMR : rts
MOVEGO  lda #8 : sta MOVE_TMR
        lda KEY_U : beq MOVD
        lda PLR_Y : beq MOVD
        dec PLR_Y : rts
MOVD    lda KEY_D : beq MOVL
        lda PLR_Y : cmp #9 : bcs MOVL
        inc PLR_Y : rts
MOVL    lda KEY_L : beq MOVR
        lda PLR_X : beq MOVR
        dec PLR_X : rts
MOVR    lda KEY_R : beq MOVDONE
        lda PLR_X : cmp #9 : bcs MOVDONE
        clc : adc #1 : cmp #6 : bne MOVOK
        ; laser hit
        lda #RED  : sta VIC_BRDCOL
        lda #100  : sta DEATH_TMR
        jsr SOUND_DEATH_START
        rts
MOVOK   inc PLR_X
MOVDONE rts

; =============================================================================
; UPDATE_SPRITE0
; =============================================================================
UPDATE_SPRITE0
        lda PLR_X
        asl : asl : asl : asl : sta TMP
        lda PLR_X : asl : asl : asl
        clc : adc TMP : clc : adc #28
        sta VIC_SP0X
        bcs SPRMSB
        lda VIC_SP_MSB : and #$FE : sta VIC_SP_MSB : bcc SPRDX
SPRMSB  lda VIC_SP_MSB : ora #$01 : sta VIC_SP_MSB
SPRDX
        lda PLR_Y : asl : asl : asl : asl
        clc : adc #66 : sta VIC_SP0Y

        lda BFLASH : beq SPROUT
        dec BFLASH : bne SPROUT
        lda #BLACK : sta VIC_BRDCOL
SPROUT  rts

; =============================================================================
; DRAW_ROOM
; =============================================================================
DRAW_ROOM
        lda #<ROOM_DATA : sta PTR  : lda #>ROOM_DATA : sta PTR+1
        lda #<(SCRN+80) : sta PTR2 : lda #>(SCRN+80) : sta PTR2+1
        ldx #3 : ldy #0
DRMPG   lda (PTR),y : sta (PTR2),y
        iny : bne DRMPG
        inc PTR+1 : inc PTR2+1
        dex : bne DRMPG
        ldy #0
DRMTAIL lda (PTR),y : sta (PTR2),y
        iny : cpy #112 : bcc DRMTAIL

        lda #<ROOM_DATA : sta PTR  : lda #>ROOM_DATA : sta PTR+1
        lda #<(CRAM+80) : sta PTR2 : lda #>(CRAM+80) : sta PTR2+1
        ldx #3 : ldy #0
DRMCPG  jsr COL_BYTE : iny : bne DRMCPG
        inc PTR+1 : inc PTR2+1
        dex : bne DRMCPG
        ldy #0
DRMCTAIL jsr COL_BYTE : iny : cpy #112 : bcc DRMCTAIL
        rts

COL_BYTE
        lda (PTR),y
        cmp #CH_SPC  : beq COLFL
        cmp #CH_PLUS : beq COLWA
        cmp #CH_DASH : beq COLWA
        cmp #CH_BAR  : beq COLWA
        cmp #CH_EQ   : beq COLRA
        cmp #CH_HASH : beq COLCR
        cmp #CH_BANG : beq COLLA
        cmp #$54     : beq COLTE
        cmp #$44     : beq COLDR
        cmp #CH_LBRK : beq COLDR
        cmp #CH_RBRK : beq COLDR
        cmp #$31     : beq COLDR
        cmp #$32     : beq COLDR
        lda #MGRAY   : !byte $2C
COLFL   lda #DGRAY   : !byte $2C
COLWA   lda #BLUE    : !byte $2C
COLRA   lda #YELLOW  : !byte $2C
COLCR   lda #ORANGE  : !byte $2C
COLLA   lda #LTRED   : !byte $2C
COLTE   lda #LTGREEN : !byte $2C
COLDR   lda #LTGREEN
COLST   sta (PTR2),y
        rts

; =============================================================================
; DRAW_STATUS
; =============================================================================
DRAW_STATUS
        ldx #39
DSTL    lda STAT_TMPL,x : sta SCRN+960,x
        lda #DGRAY : sta CRAM+960,x
        dex : bpl DSTL
        lda PLR_X : clc : adc #CH_0 : sta SCRN+966
        lda PLR_Y : clc : adc #CH_0 : sta SCRN+970
        lda #LTGREEN : sta CRAM+966 : sta CRAM+970
        rts

STAT_TMPL
        !pet "pos:x=0 y=0  chips:l1x2 l2x1  joy/crsr  "

; =============================================================================
; RASTER IRQ
; =============================================================================
RASTER_IRQ
        lda #$01 : sta VIC_IRQ
        lda #$01 : sta TICK_FLAG
        jmp $EA31

; =============================================================================
; Screen text strings (all exactly 40 chars)
; =============================================================================
TXT_TITLE
        !pet "           * titan fall *            "
        !byte $20,$20,$20   ; pad to 40

TXT_TAG
        !pet "   infiltrate. subvert. stop launch. "
        !byte $20,$20,$20   ; pad to 40

TXT_PRESS
        !pet "        press any key to start       "
        !byte $20,$20,$20   ; pad to 40

TXT_GO1
        !pet "          * security breach *        "
        !byte $20,$20,$20,$20   ; pad to 40

TXT_GO2
        !pet "          operative terminated       "
        !byte $20,$20,$20,$20,$20   ; pad to 40

TXT_GO3
        !pet "  titan launch sequence continues... "
        !byte $20,$20,$20   ; pad to 40

TXT_GOPRESS
        !pet "        press any key to retry       "
        !byte $20,$20,$20   ; pad to 40

; =============================================================================
; Sprite data — placed directly at $3F40 (64-byte aligned, pointer $FD)
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
        !byte $00           ; byte 63: colour (unused in hires mode)

; =============================================================================
; Room data — 22 rows x 40 chars
; =============================================================================
ROOM_DATA
        !pet "+------+-----------!-----------+------+ "
        !pet "|=====||           !           |      | "
        !pet "|=====||           !           |      | "
        !pet "|=====||           !           |      | "
        !pet "|     |+-----------!-----------+      | "
        !pet "|     | T          !                  | "
        !pet "|     |            !                  | "
        !pet "|     |            !    [D1]          | "
        !pet "|     |            !                  | "
        !pet "+-----+            !                  | "
        !pet "|                  !                  | "
        !pet "|                  !     |=====|      | "
        !pet "|                  !     |=====|      | "
        !pet "|                  !                  | "
        !pet "|   [D2]           !                  | "
        !pet "|                  !                  | "
        !pet "|  ##              !                  | "
        !pet "|  ##              !                  | "
        !pet "|                  !                  | "
        !pet "|                  !                  | "
        !pet "|                  !                  | "
        !pet "+------------------!-------------------+"

; =============================================================================
; SID DEATH SOUND
; =============================================================================
; Voice 1 sawtooth wave, descending pitch sweep over ~50 frames (1 second PAL).
; SND_TMR counts down 50→0. Each frame we write a new frequency derived from
; the timer — higher timer = higher pitch. Simple linear sweep.
;
; Frequency register = SND_TMR * 8 + $0200  (rough descending sweep)
; At timer=50: freq~$0290 (~350Hz)  At timer=0: freq~$0200 (~260Hz, low thud)
;
; SID voice 1 registers used:
;   $D400/$D401  freq lo/hi
;   $D404        control (sawtooth=$20 + gate=$01)
;   $D405        attack/decay
;   $D406        sustain/release
;   $D418        master volume

SOUND_DEATH_START
        lda #50    : sta SND_TMR    ; ~1 second at 50Hz

        lda #$00   : sta $D405      ; attack=0, decay=0 (instant on)
        lda #$F0   : sta $D406      ; sustain=15, release=0

        lda #$0F   : sta $D418      ; master volume full

        ; Set initial (highest) frequency and gate on
        lda #$90   : sta $D400      ; freq lo  ($0290 ≈ 350Hz)
        lda #$02   : sta $D401      ; freq hi
        lda #$21   : sta $D404      ; sawtooth + gate on
        rts

SOUND_TICK
        lda SND_TMR
        beq SNDOUT              ; already done

        dec SND_TMR
        lda SND_TMR
        beq SNDOFF              ; just hit zero — gate off

        ; Compute frequency = SND_TMR * 8 + $0200
        ; lo byte = (SND_TMR << 3) & $FF, hi byte = (SND_TMR >> 5) + 2
        asl : asl : asl         ; SND_TMR * 8 (fits in 8 bits for values 0-31)
        sta $D400               ; freq lo
        lda SND_TMR
        lsr : lsr : lsr : lsr : lsr  ; SND_TMR >> 5
        clc : adc #2
        sta $D401               ; freq hi
        bne SNDOUT              ; always

SNDOFF  lda #$20 : sta $D404   ; gate off, sawtooth stays (triggers release)
        lda #$00 : sta $D418    ; volume off
SNDOUT  rts

; =============================================================================
; TERMINAL STATE (GAME_STATE = 3)
; =============================================================================
; Room area (rows 2-23) is blanked; HUD (rows 0-1) and footer (row 24) kept.
; Clock does not tick in this state (TICK_CLOCK only called from GAME_ALIVE).
; Sprite is hidden on entry and restored on exit.
;
; Screen layout (rows 4-13 within the cleared room area):
;   row  4: +--------------------------------------+
;   row  5: |  * sector drone network - terminal   |
;   row  6: |  access verified. select unit:       |
;   row  7: |                                      |
;   row  8: |  > [1] bot-7741  loader   available  |  ← selector
;   row  9: |    [2] bot-3312  splicer  available  |
;   row 10: |    [3] bot-9901  centurion locked    |
;   row 11: |                                      |
;   row 12: |   return=link   f7=abort    [t=open] |
;   row 13: +--------------------------------------+
;   row 14: (status message)
;
; TERM_SEL = 0,1,2
; TERM_TMR > 0 = showing "link established" confirmation

; Drone list rows on screen: SCRN + 8*40=320, 9*40=360, 10*40=400
TERM_ROW0 = SCRN + 8*40    ; row 8  = SCRN+320
TERM_ROW1 = SCRN + 9*40    ; row 9  = SCRN+360
TERM_ROW2 = SCRN + 10*40   ; row 10 = SCRN+400
TERM_COL0 = CRAM + 8*40
TERM_COL1 = CRAM + 9*40
TERM_COL2 = CRAM + 10*40
TERM_MSGROW = SCRN + 14*40 ; row 14 = SCRN+560 — status message

; ---------------------------------------------------------------------------
; CLEAR_ROOM — blank rows 2-23 (SCRN+80..SCRN+959) with spaces / DGRAY
; Leaves row 0 (HUD), row 1 (separator) and row 24 (footer) untouched.
; ---------------------------------------------------------------------------
CLEAR_ROOM
        lda #<(SCRN+80) : sta PTR  : lda #>(SCRN+80) : sta PTR+1
        ldx #3 : ldy #0
CRMSPG  lda #CH_SPC : sta (PTR),y
        iny : bne CRMSPG
        inc PTR+1 : dex : bne CRMSPG
        ldy #0
CRMSTAIL lda #CH_SPC : sta (PTR),y
        iny : cpy #112 : bcc CRMSTAIL
        lda #<(CRAM+80) : sta PTR  : lda #>(CRAM+80) : sta PTR+1
        ldx #3 : ldy #0
CRMCPG  lda #DGRAY : sta (PTR),y
        iny : bne CRMCPG
        inc PTR+1 : dex : bne CRMCPG
        ldy #0
CRMCTAIL lda #DGRAY : sta (PTR),y
        iny : cpy #112 : bcc CRMCTAIL
        rts

; ---------------------------------------------------------------------------
; SETUP_TERMINAL — draw terminal screen, switch to state 3
; Called via jsr from READ_KEYS when T pressed near terminal.
; ---------------------------------------------------------------------------
SETUP_TERMINAL
        lda #3 : sta GAME_STATE
        lda #0 : sta TERM_SEL
        lda #0 : sta TERM_TMR
        lda #$00 : sta VIC_SPEN      ; hide player sprite

        jsr CLEAR_ROOM               ; replace room area with blank canvas

        ; Draw box rows 4-13
        ; Row 4: top border
        ldx #39
TSETB1  lda TBOX_TOP,x : sta SCRN+160,x
        lda #LTGREEN : sta CRAM+160,x
        dex : bpl TSETB1

        ; Row 5: title
        ldx #39
TSETB2  lda TBOX_TTL,x : sta SCRN+200,x
        lda #LTGREEN : sta CRAM+200,x
        dex : bpl TSETB2

        ; Row 6: subtitle
        ldx #39
TSETB3  lda TBOX_SUB,x : sta SCRN+240,x
        lda #GREEN : sta CRAM+240,x
        dex : bpl TSETB3

        ; Row 7: blank interior
        ldx #39
TSETB4  lda TBOX_BLK,x : sta SCRN+280,x
        lda #GREEN : sta CRAM+280,x
        dex : bpl TSETB4

        ; Rows 8-10: drone entries
        ldx #39
TSETD0  lda TBOX_D0,x : sta TERM_ROW0,x
        lda #GREEN : sta TERM_COL0,x
        dex : bpl TSETD0
        ldx #39
TSETD1  lda TBOX_D1,x : sta TERM_ROW1,x
        lda #GREEN : sta TERM_COL1,x
        dex : bpl TSETD1
        ldx #39
TSETD2  lda TBOX_D2,x : sta TERM_ROW2,x
        lda #DGRAY : sta TERM_COL2,x
        dex : bpl TSETD2

        ; Row 11: blank
        ldx #39
TSETB5  lda TBOX_BLK,x : sta SCRN+440,x
        lda #GREEN : sta CRAM+440,x
        dex : bpl TSETB5

        ; Row 12: key hint
        ldx #39
TSETB6  lda TBOX_HNT,x : sta SCRN+480,x
        lda #DGRAY : sta CRAM+480,x
        dex : bpl TSETB6

        ; Row 13: bottom border
        ldx #39
TSETB7  lda TBOX_BOT,x : sta SCRN+520,x
        lda #LTGREEN : sta CRAM+520,x
        dex : bpl TSETB7

        ; Clear message row
        ldx #39
TSETM   lda #CH_SPC : sta TERM_MSGROW,x
        dex : bpl TSETM

        jsr TERM_DRAW_SEL       ; draw initial selector
        rts

; ---------------------------------------------------------------------------
; DO_TERMINAL — called each frame in state 3
; ---------------------------------------------------------------------------
DO_TERMINAL
        ; If link confirmation timer running, count down then return to game
        lda TERM_TMR : beq TERM_INPUT
        dec TERM_TMR
        beq TEXPIRE
        jmp MAIN_LOOP
TEXPIRE ; Timer expired — back to game
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$01 : sta VIC_SPEN      ; restore sprite
        jsr UPDATE_SPRITE0
        jmp MAIN_LOOP

TERM_INPUT
        ; Read keyboard directly each frame (not using KEY_* flags — those need
        ; READ_KEYS which is only called in game state)
        ; Use GETIN for simplicity — it reads from KERNAL buffer (EA31 populates it)
        jsr GETIN
        beq TERM_DONE

        ; F7 ($03 in KERNAL key table) or '-' used as escape — just check common values
        ; Actually GETIN returns PETSCII: F1=$85, F7=$88, Return=$0D, cursor up=$91, dn=$11
        cmp #$88 : beq TERM_ABORT      ; F7 = abort
        cmp #$1B : beq TERM_ABORT      ; ESC = abort (some setups)
        cmp #$0D : beq TERM_LINK       ; Return = link
        cmp #$85 : beq TERM_LINK       ; F1 = link
        cmp #$91 : beq TERM_UP         ; cursor up
        cmp #$11 : beq TERM_DOWN       ; cursor down
        bne TERM_DONE

TERM_UP
        lda TERM_SEL : beq TERM_DONE
        dec TERM_SEL
        jsr TERM_DRAW_SEL
        bne TERM_DONE

TERM_DOWN
        lda TERM_SEL : cmp #2 : bcs TERM_DONE
        inc TERM_SEL
        jsr TERM_DRAW_SEL
        bne TERM_DONE

TERM_LINK
        ; Can't link to bot-9901 (locked, row 2)
        lda TERM_SEL : cmp #2 : beq TERM_LOCKED
        ; Show confirmation message
        ldx #39
TLINK1  lda TMSG_OK,x : sta TERM_MSGROW,x
        lda #LTGREEN : sta CRAM+560,x
        dex : bpl TLINK1
        lda #75 : sta TERM_TMR   ; ~1.5 seconds then return
        bne TERM_DONE

TERM_LOCKED
        ldx #39
TLOCK1  lda TMSG_LCK,x : sta TERM_MSGROW,x
        lda #LTRED : sta CRAM+560,x
        dex : bpl TLOCK1
        bne TERM_DONE

TERM_ABORT
        lda #1 : sta GAME_STATE
        jsr DRAW_ROOM
        jsr DRAW_STATUS
        lda #$01 : sta VIC_SPEN      ; restore sprite
        jsr UPDATE_SPRITE0

TERM_DONE
        jmp MAIN_LOOP

; ---------------------------------------------------------------------------
; TERM_DRAW_SEL — redraw all 3 drone rows, highlight selected one
; ---------------------------------------------------------------------------
TERM_DRAW_SEL
        ; Row 0 colour
        ldx #39
        lda TERM_SEL : bne TDSEL1
        lda #LTGREEN : !byte $2C        ; selected
TDSEL1  lda #GREEN                      ; unselected
        sta TERM_COL0,x : dex : bpl TDSEL1

        ; Row 1 colour
        ldx #39
        lda TERM_SEL : cmp #1 : bne TDSEL2
        lda #LTGREEN : !byte $2C
TDSEL2  lda #GREEN
        sta TERM_COL1,x : dex : bpl TDSEL2

        ; Row 2 colour (always DGRAY — locked)
        ldx #39
TDSEL3  lda #DGRAY : sta TERM_COL2,x : dex : bpl TDSEL3

        ; Draw '>' selector character in col 3 of correct row
        ; Clear all three first
        lda #CH_SPC
        sta TERM_ROW0+3
        sta TERM_ROW1+3
        sta TERM_ROW2+3
        ; Draw '>' in selected row
        lda #$3E                        ; PETSCII '>'
        ldx TERM_SEL
        beq TDSELA
        cpx #1 : beq TDSELB
        sta TERM_ROW2+3 : bne TDSELX
TDSELA  sta TERM_ROW0+3 : bne TDSELX
TDSELB  sta TERM_ROW1+3
TDSELX  rts

; ---------------------------------------------------------------------------
; Terminal box strings — all 40 chars
; ---------------------------------------------------------------------------
TBOX_TOP  !pet "+--------------------------------------+"
TBOX_TTL  !pet "|  * sector drone network - terminal   |"
TBOX_SUB  !pet "|  access verified. select unit:       |"
TBOX_BLK  !pet "|                                      |"
TBOX_D0  !pet "|   [1] bot-7741  loader    available  |"
TBOX_D1  !pet "|   [2] bot-3312  splicer   available  |"
TBOX_D2  !pet "|   [3] bot-9901  centurion  locked    |"
TBOX_HNT  !pet "|   return=link   f7=abort    [t=open] |"
TBOX_BOT  !pet "+--------------------------------------+"
TMSG_OK  !pet "  proxy link established. unit active   "
TMSG_LCK  !pet "  access denied. unit locked by titan.  "

        !eof
