; =============================================================================
; titan_theme.asm — "Countdown", the original TITAN Fall theme, and the small
; player that plays it. Assembled on its own into music/titan_theme.prg
; (load $C000) by the Makefile and packed next to the game by exomizer.
;
;   init  jsr $C000   (A ignored — one tune)
;   play  jsr $C003   once per frame (50 Hz PAL), from the game's raster IRQ
;
; Rules from the game (see CLAUDE.md "SID / Music"):
;   - play runs inside the IRQ while the main loop is anywhere, so it saves
;     and restores the one zero-page pointer it uses ($FB/$FC) and touches no
;     other game RAM
;   - the game's sound effects take over voice 1 (and $D418) while they play
;     and simply don't call play; every frame here rewrites frequency, pulse,
;     waveform and $D418, and every new note rewrites AD/SR, so the music
;     comes back cleanly afterwards
;
; Song data format
;   order list (one per voice): pattern numbers ($00-$7F); $80-$BF = set
;     transpose for the following patterns (value - $A0, i.e. T0 = $A0);
;     $FF, n = loop: continue at byte n of this order list
;   pattern: notes $00-$5F (C0 ... B7, transposed), REST ($60) = gate off;
;     L1-L42 ($80+rows-1) set the length of the following notes in rows
;     (one row = 6 frames = a 16th note at 125 BPM); instrument bytes ($C0+n)
;     select instrument n; $FF ends the pattern
;   instrument: AD, SR, wave-table start, initial pulse width (high nibble),
;     pulse sweep speed (0 = static; sweeps up and down between $200-$E00),
;     vibrato delay in frames (0 = no vibrato)
;   wave table: one (waveform, pitch) pair per frame; pitch $00-$7F = semitones
;     above the note, $80+n = absolute note n (drums); waveform $FF = jump to
;     the entry given as pitch
;   Every note gets a hard restart: two frames before it ends (unless a rest
;     follows) gate goes off and AD/SR drop to 0, so the next attack is clean.
; =============================================================================

        * = $C000

        jmp MUS_INIT
        jmp MUS_PLAY

ZP       = $FB          ; pattern/order pointer (saved and restored)
HR_FRAMES = 2           ; hard restart this many frames before a note ends

REST     = $60
L1 = $80 : L2 = $81 : L3 = $82 : L4 = $83 : L6 = $85 : L8 = $87 : L16 = $8F
T0  = $A0               ; transpose 0
TM2 = $9E : TM4 = $9C : TM5 = $9B : TM7 = $99

; =============================================================================
; init: silence the SID, rewind every voice
; =============================================================================
MUS_INIT
        lda ZP : pha : lda ZP+1 : pha
        ldx #$18
        lda #0
MI_SID  sta $D400,x
        dex
        bpl MI_SID
        lda #$0F : sta $D418
        ldx #2
MI_VOICE
        lda #0
        sta V_ORD,x
        sta V_TRANS,x
        sta V_INS,x
        sta V_WTI,x             ; wave-table entry 0 = silence
        sta V_NOTE,x
        sta V_PWL,x
        sta V_PDIR,x
        sta V_VDEL,x
        sta V_VPH,x
        lda #8 : sta V_PWH,x
        lda #6 : sta V_DURF,x
        lda #1 : sta V_DELAY,x  ; read the first event on the first play
        lda #$FE : sta V_GATE,x
        jsr NEXT_PATTERN
        dex
        bpl MI_VOICE
        pla : sta ZP+1 : pla : sta ZP
        rts

; =============================================================================
; play: one frame for all three voices
; =============================================================================
MUS_PLAY
        lda ZP : pha : lda ZP+1 : pha
        lda #$0F : sta $D418    ; an effect may have faded the volume
        ldx #2
MP_LOOP jsr VOICE
        dex
        bpl MP_LOOP
        pla : sta ZP+1 : pla : sta ZP
        rts

; ---------------------------------------------------------------------------
; VOICE — X = voice 0-2 (preserved)
; ---------------------------------------------------------------------------
VOICE
        dec V_DELAY,x
        bne VC_HR
        jsr READ_EVENT
        jmp VC_FX
VC_HR   lda V_DELAY,x
        cmp #HR_FRAMES
        bne VC_FX
        lda V_PLO,x : sta ZP    ; peek: no hard restart before a rest
        lda V_PHI,x : sta ZP+1
        ldy #0
        lda (ZP),y
        cmp #REST
        beq VC_FX
        lda #$FE : sta V_GATE,x
        ldy SIDOFS,x
        lda #0
        sta $D405,y
        sta $D406,y

VC_FX   ; ---- wave table: waveform and pitch for this frame
        ldy V_WTI,x
VF_WT   lda WT_WAVE,y
        cmp #$FF
        bne VF_WOK
        lda WT_NOTE,y
        tay
        jmp VF_WT
VF_WOK  and V_GATE,x
        sta M_WAVE
        lda WT_NOTE,y
        bmi VF_ABS
        clc
        adc V_NOTE,x
        jmp VF_NOTE
VF_ABS  and #$7F
VF_NOTE cmp #96
        bcc VF_NOK
        lda #95
VF_NOK  sta M_TMP
        iny
        tya
        sta V_WTI,x
        ldy M_TMP
        lda FREQ_LO,y : sta M_FL
        lda FREQ_HI,y : sta M_FH

        ; ---- vibrato: +-2 steps of freq/128 (~27 cents), 8 frames a cycle
        ldy V_INS,x
        lda INS_VIB,y
        beq VF_PULSE
        lda V_VDEL,x
        beq VF_VIB
        dec V_VDEL,x
        jmp VF_PULSE
VF_VIB  lda M_FH
        asl
        bcc VF_VD
        lda #$FF
VF_VD   sta M_TMP               ; the vibrato step
        lda V_VPH,x
        clc
        adc #1
        and #7
        sta V_VPH,x
        tay
        lda VIBTAB,y
        beq VF_PULSE
        bmi VF_VDN
        tay
VF_VUP  lda M_FL : clc : adc M_TMP : sta M_FL
        lda M_FH : adc #0 : sta M_FH
        dey
        bne VF_VUP
        jmp VF_PULSE
VF_VDN  eor #$FF
        clc
        adc #1
        tay
VF_VDL  lda M_FL : sec : sbc M_TMP : sta M_FL
        lda M_FH : sbc #0 : sta M_FH
        dey
        bne VF_VDL

VF_PULSE ; ---- pulse width sweep, up and down between $200 and $E00
        ldy V_INS,x
        lda INS_PSPD,y
        beq VF_WRITE
        sta M_TMP
        lda V_PDIR,x
        bne VF_PDN
        lda V_PWL,x : clc : adc M_TMP : sta V_PWL,x
        lda V_PWH,x : adc #0 : sta V_PWH,x
        cmp #$0E
        bcc VF_WRITE
        lda #1 : sta V_PDIR,x
        jmp VF_WRITE
VF_PDN  lda V_PWL,x : sec : sbc M_TMP : sta V_PWL,x
        lda V_PWH,x : sbc #0 : sta V_PWH,x
        cmp #$02
        bcs VF_WRITE
        lda #0 : sta V_PDIR,x

VF_WRITE
        ldy SIDOFS,x
        lda M_FL     : sta $D400,y
        lda M_FH     : sta $D401,y
        lda V_PWL,x  : sta $D402,y
        lda V_PWH,x  : sta $D403,y
        lda M_WAVE   : sta $D404,y
        rts

; ---------------------------------------------------------------------------
; READ_EVENT — read commands up to the next note or rest (X = voice)
; ---------------------------------------------------------------------------
READ_EVENT
RE_TOP  lda V_PLO,x : sta ZP
        lda V_PHI,x : sta ZP+1
        ldy #0
RE_NEXT lda (ZP),y
        iny
        cmp #$FF
        beq RE_END
        cmp #$C0
        bcs RE_INS
        cmp #$80
        bcs RE_DUR
        cmp #REST
        beq RE_REST
        ; ---- a note
        clc
        adc V_TRANS,x
        sta V_NOTE,x
        jsr RE_SAVE
        ldy V_INS,x
        lda INS_WT,y   : sta V_WTI,x
        lda INS_PW,y   : sta V_PWH,x
        lda INS_VIB,y  : sta V_VDEL,x
        lda INS_AD,y   : sta M_TMP
        lda INS_SR,y   : pha
        lda #0
        sta V_PWL,x
        sta V_PDIR,x
        sta V_VPH,x
        lda #$FF : sta V_GATE,x
        ldy SIDOFS,x
        lda M_TMP : sta $D405,y
        pla       : sta $D406,y
        rts
RE_REST jsr RE_SAVE
        lda #$FE : sta V_GATE,x
        rts
RE_INS  and #$1F
        sta V_INS,x
        jmp RE_NEXT
RE_DUR  and #$3F                ; rows-1 -> frames = rows*6
        clc
        adc #1
        sta M_TMP
        asl
        adc M_TMP
        asl
        sta V_DURF,x
        jmp RE_NEXT
RE_END  jsr NEXT_PATTERN
        jmp RE_TOP

; pattern pointer += Y, and the note/rest lasts V_DURF frames
RE_SAVE tya
        clc
        adc ZP
        sta V_PLO,x
        lda ZP+1
        adc #0
        sta V_PHI,x
        lda V_DURF,x
        sta V_DELAY,x
        rts

; ---------------------------------------------------------------------------
; NEXT_PATTERN — step voice X's order list to its next pattern
; ---------------------------------------------------------------------------
NEXT_PATTERN
        lda ORD_LO,x : sta ZP
        lda ORD_HI,x : sta ZP+1
NP_READ ldy V_ORD,x
        lda (ZP),y
        cmp #$FF
        bne NP_STEP
        iny
        lda (ZP),y
        sta V_ORD,x
        jmp NP_READ
NP_STEP inc V_ORD,x
        cmp #$80
        bcc NP_PAT
        sec
        sbc #$A0
        sta V_TRANS,x
        jmp NP_READ
NP_PAT  tay
        lda PAT_LO,y : sta V_PLO,x
        lda PAT_HI,y : sta V_PHI,x
        rts

SIDOFS  !byte 0, 7, 14
VIBTAB  !byte 1, 2, 1, 0, $FF, $FE, $FF, 0

; =============================================================================
; Instruments
; =============================================================================
SILENT = $C0 : BASS = $C1 : SNARE = $C2 : ARPMIN = $C3 : ARPMAJ = $C4
LEAD = $C5 : PING = $C6

;          silent bass  snare arpmin arpmaj lead  ping
INS_AD   !byte $00, $09, $09, $08, $08, $0A, $09
INS_SR   !byte $00, $A8, $00, $68, $68, $A9, $00
INS_WT   !byte WTS_SIL, WTS_BASS, WTS_SNARE, WTS_MIN, WTS_MAJ, WTS_LEAD, WTS_PING
INS_PW   !byte $08, $04, $08, $06, $06, $08, $08
INS_PSPD !byte $00, $20, $00, $30, $30, $18, $00
INS_VIB  !byte $00, $00, $00, $00, $00, $0A, $00

; =============================================================================
; Wave table (one entry per frame)
; =============================================================================
WTS_SIL = 0 : WTS_BASS = 2 : WTS_SNARE = 4 : WTS_MIN = 10 : WTS_MAJ = 14
WTS_LEAD = 18 : WTS_PING = 21

WT_WAVE !byte $00, $FF                      ;  0 silence
        !byte $41, $FF                      ;  2 bass: pulse
        !byte $81, $41, $81, $81, $81, $FF  ;  4 snare: noise, tone, noise falling
        !byte $41, $41, $41, $FF            ; 10 minor chord arpeggio
        !byte $41, $41, $41, $FF            ; 14 major chord arpeggio
        !byte $41, $41, $FF                 ; 18 lead: octave blip, then pulse
        !byte $41, $11, $FF                 ; 21 bell: pulse blip, then triangle
WT_NOTE !byte $00, 0
        !byte $00, 2
        !byte $80+82, $80+46, $80+76, $80+72, $80+68, 8
        !byte 0, 3, 7, 10
        !byte 0, 4, 7, 14
        !byte 12, 0, 19
        !byte 12, 0, 22

!if * - WT_NOTE != WT_NOTE - WT_WAVE {
        !error "WT_WAVE and WT_NOTE differ in length"
}

; note numbers (C0 = 0 ... B7 = 95); s = sharp
; octave 0
C0  = 0
Cs0 = 1
D0  = 2
Ds0 = 3
E0  = 4
F0  = 5
Fs0 = 6
G0  = 7
Gs0 = 8
A0  = 9
As0 = 10
B0  = 11
; octave 1
C1  = 12
Cs1 = 13
D1  = 14
Ds1 = 15
E1  = 16
F1  = 17
Fs1 = 18
G1  = 19
Gs1 = 20
A1  = 21
As1 = 22
B1  = 23
; octave 2
C2  = 24
Cs2 = 25
D2  = 26
Ds2 = 27
E2  = 28
F2  = 29
Fs2 = 30
G2  = 31
Gs2 = 32
A2  = 33
As2 = 34
B2  = 35
; octave 3
C3  = 36
Cs3 = 37
D3  = 38
Ds3 = 39
E3  = 40
F3  = 41
Fs3 = 42
G3  = 43
Gs3 = 44
A3  = 45
As3 = 46
B3  = 47
; octave 4
C4  = 48
Cs4 = 49
D4  = 50
Ds4 = 51
E4  = 52
F4  = 53
Fs4 = 54
G4  = 55
Gs4 = 56
A4  = 57
As4 = 58
B4  = 59
; octave 5
C5  = 60
Cs5 = 61
D5  = 62
Ds5 = 63
E5  = 64
F5  = 65
Fs5 = 66
G5  = 67
Gs5 = 68
A5  = 69
As5 = 70
B5  = 71
; octave 6
C6  = 72
Cs6 = 73
D6  = 74
Ds6 = 75
E6  = 76
F6  = 77
Fs6 = 78
G6  = 79
Gs6 = 80
A6  = 81
As6 = 82
B6  = 83
; octave 7
C7  = 84
Cs7 = 85
D7  = 86
Ds7 = 87
E7  = 88
F7  = 89
Fs7 = 90
G7  = 91
Gs7 = 92
A7  = 93
As7 = 94
B7  = 95

; PAL frequency table (985248 Hz clock, A4 = 440 Hz)
FREQ_LO
        !byte $16, $27, $39, $4B, $5F, $74, $8A, $A1, $BA, $D4, $F0, $0E
        !byte $2D, $4E, $71, $96, $BE, $E7, $14, $42, $74, $A9, $E0, $1B
        !byte $5A, $9C, $E2, $2D, $7B, $CF, $27, $85, $E8, $51, $C1, $37
        !byte $B4, $38, $C4, $59, $F7, $9D, $4E, $0A, $D0, $A2, $81, $6D
        !byte $67, $70, $89, $B2, $ED, $3B, $9C, $13, $A0, $45, $02, $DA
        !byte $CE, $E0, $11, $64, $DA, $76, $39, $26, $40, $89, $04, $B4
        !byte $9C, $C0, $23, $C8, $B4, $EB, $72, $4C, $80, $12, $08, $68
        !byte $39, $80, $45, $90, $68, $D6, $E3, $99, $00, $24, $10, $FF
FREQ_HI
        !byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02
        !byte $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $04
        !byte $04, $04, $04, $05, $05, $05, $06, $06, $06, $07, $07, $08
        !byte $08, $09, $09, $0A, $0A, $0B, $0C, $0D, $0D, $0E, $0F, $10
        !byte $11, $12, $13, $14, $15, $17, $18, $1A, $1B, $1D, $1F, $20
        !byte $22, $24, $27, $29, $2B, $2E, $31, $34, $37, $3A, $3E, $41
        !byte $45, $49, $4E, $52, $57, $5C, $62, $68, $6E, $75, $7C, $83
        !byte $8B, $93, $9C, $A5, $AF, $B9, $C4, $D0, $DD, $EA, $F8, $FF

; =============================================================================
; The song: 4 bars of bass and snare, then a 24-bar loop
;   B: arpeggios join, a bell motif on top   Dm Dm Bb A  Dm Dm Gm A
;   C: the theme on the lead                 Dm Dm Bb A  Dm Dm Gm A
;   D: bridge                                Gm Gm Dm Dm Bb C  A  A
; =============================================================================
ORD_LO  !byte <ORD1, <ORD2, <ORD3
ORD_HI  !byte >ORD1, >ORD2, >ORD3

; voice 1: bell / lead (also the sound effects' voice)
ORD1    !byte P_REST, P_REST, P_REST, P_REST
ORD1_L  !byte P_REST, P_REST, P_REST, P_REST
        !byte P_PING_DM, P_PING_DM, P_PING_GM, P_PING_A
        !byte P_LEAD1, P_LEAD2
        !byte P_BRIDGE1, P_BRIDGE2
        !byte $FF, ORD1_L - ORD1

; voice 2: bass + snare
ORD2    !byte T0, P_BASS, P_BASS, TM4, P_BASS, TM5, P_BFILL
ORD2_L  !byte T0, P_BASS, P_BASS, TM4, P_BASS, TM5, P_BASS
        !byte T0, P_BASS, P_BASS, TM7, P_BASS, TM5, P_BFILL
        !byte T0, P_BASS, P_BASS, TM4, P_BASS, TM5, P_BASS
        !byte T0, P_BASS, P_BASS, TM7, P_BASS, TM5, P_BFILL
        !byte TM7, P_BASS, P_BASS, T0, P_BASS, P_BASS
        !byte TM4, P_BASS, TM2, P_BASS, TM5, P_BASS, P_BFILL
        !byte $FF, ORD2_L - ORD2

; voice 3: chord arpeggios
ORD3    !byte P_REST, P_REST, P_REST, P_REST
ORD3_L  !byte T0, P_AMIN, P_AMIN, TM4, P_AMAJ, TM5, P_AMAJ
        !byte T0, P_AMIN, P_AMIN, TM7, P_AMIN, TM5, P_AMAJ
        !byte T0, P_AMIN, P_AMIN, TM4, P_AMAJ, TM5, P_AMAJ
        !byte T0, P_AMIN, P_AMIN, TM7, P_AMIN, TM5, P_AMAJ
        !byte TM7, P_AMIN, P_AMIN, T0, P_AMIN, P_AMIN
        !byte TM4, P_AMAJ, TM2, P_AMAJ, TM5, P_AMAJ, P_AMAJ
        !byte $FF, ORD3_L - ORD3

; ---- patterns (each one bar = 16 rows, except the 4-bar lead lines)
P_REST = 0 : P_BASS = 1 : P_BFILL = 2 : P_AMIN = 3 : P_AMAJ = 4
P_PING_DM = 5 : P_PING_GM = 6 : P_PING_A = 7
P_LEAD1 = 8 : P_LEAD2 = 9 : P_BRIDGE1 = 10 : P_BRIDGE2 = 11

PAT_LO  !byte <PT_REST, <PT_BASS, <PT_BFILL, <PT_AMIN, <PT_AMAJ
        !byte <PT_PING_DM, <PT_PING_GM, <PT_PING_A
        !byte <PT_LEAD1, <PT_LEAD2, <PT_BRIDGE1, <PT_BRIDGE2
PAT_HI  !byte >PT_REST, >PT_BASS, >PT_BFILL, >PT_AMIN, >PT_AMAJ
        !byte >PT_PING_DM, >PT_PING_GM, >PT_PING_A
        !byte >PT_LEAD1, >PT_LEAD2, >PT_BRIDGE1, >PT_BRIDGE2

PT_REST  !byte L16, REST, $FF

; octave-jumping bass with a snare on 2 and 4 (snare pitch is absolute)
PT_BASS  !byte BASS, L1, D2, D2, D3, D2, SNARE, L2, D3
         !byte BASS, L1, D2, D3, D2, D2, D3, D2, SNARE, L2, D3
         !byte BASS, L1, C3, D3, $FF
; the same into a snare roll, last bar of each section
PT_BFILL !byte BASS, L1, D2, D2, D3, D2, SNARE, D3, D3
         !byte BASS, D2, D3, SNARE, D3, BASS, D2, D3, D2
         !byte SNARE, D3, D3, D3, D3, $FF

; syncopated 3+3+2 chord stabs
PT_AMIN  !byte ARPMIN, L3, D4, D4, L2, D4, L3, D4, D4, L2, D4, $FF
PT_AMAJ  !byte ARPMAJ, L3, D4, D4, L2, D4, L3, D4, D4, L2, D4, $FF

; bell motif, in the stabs' rhythm
PT_PING_DM !byte PING, L3, D5, A4, L2, F5, L3, E5, A4, L2, D5, $FF
PT_PING_GM !byte PING, L3, D5, As4, L2, G5, L3, F5, D5, L2, As4, $FF
PT_PING_A  !byte PING, L3, Cs5, A4, L2, E5, L3, Cs5, A4, L2, E4, $FF

; the theme
PT_LEAD1 !byte LEAD, L4, A4, D5, L2, E5, L4, F5, L2, E5         ; Dm
         !byte L6, D5, L2, C5, L8, A4                           ; Dm
         !byte L4, As4, D5, F5, L2, E5, D5                      ; Bb
         !byte L8, Cs5, L4, E5, A4, $FF                         ; A
PT_LEAD2 !byte LEAD, L4, A4, D5, L2, E5, L4, F5, L2, G5         ; Dm
         !byte L6, A5, L2, G5, L4, F5, E5                       ; Dm
         !byte L4, D5, As4, L6, G5, L2, F5                      ; Gm
         !byte L6, E5, L2, Cs5, L8, A4, $FF                     ; A

; bridge
PT_BRIDGE1 !byte LEAD, L2, G4, As4, L4, D5, G5, F5              ; Gm
           !byte L4, D5, As4, L8, G4                            ; Gm
           !byte L2, F4, A4, L4, D5, F5, E5                     ; Dm
           !byte L4, D5, A4, L8, F4, $FF                        ; Dm
PT_BRIDGE2 !byte LEAD, L4, F5, D5, As4, D5                      ; Bb
           !byte E5, G5, C5, E5                                 ; C
           !byte Cs5, E5, L8, A5                                ; A
           !byte L2, G5, F5, E5, D5, L4, Cs5, REST, $FF         ; A

; =============================================================================
; Player state (per voice)
; =============================================================================
V_ORD   !fill 3         ; order list position
V_TRANS !fill 3         ; transpose for the current pattern
V_PLO   !fill 3         ; pattern pointer
V_PHI   !fill 3
V_DELAY !fill 3         ; frames left of the current note/rest
V_DURF  !fill 3         ; note length in frames
V_INS   !fill 3         ; instrument
V_NOTE  !fill 3         ; current note (transposed)
V_WTI   !fill 3         ; wave table position
V_GATE  !fill 3         ; $FF gate on, $FE off (ANDed into the waveform)
V_PWL   !fill 3         ; pulse width
V_PWH   !fill 3
V_PDIR  !fill 3         ; pulse sweep direction (0 up)
V_VDEL  !fill 3         ; frames until vibrato starts
V_VPH   !fill 3         ; vibrato phase 0-7
M_WAVE  !byte 0         ; scratch
M_TMP   !byte 0
M_FL    !byte 0
M_FH    !byte 0

!if * > $D000 {
        !error "titan_theme runs past $CFFF"
}
