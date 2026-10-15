; =============================================================================
; CARRIER LOCK (GAME_STATE = 10) — the COMM desk mini-game that wins reset keys
; =============================================================================
; Fire on a COMM desk tile (art.comm_tiles, room 3; READ_KEYS) starts it, as
; often as the player likes — every key won makes the next one harder. Voice 1 plays the hidden target tone as a buzzy pulse —
; alone for the first second (CL_LISTEN), so the player hears what to match —
; then voice 2 joins with the dial as a soft triangle (different timbres, or
; the two blend into one sound), starting 25-55% off. Left/right (joystick or
; A/D) turn the dial: fast and steady in coarse range mode, slow in detailed
; (CL_DIALIN). The tones beat at their frequency difference — 1 SID unit is
; about 0.06 Hz — and the scope shows the target and tuner waves on top of
; each other (the tuner's wavelength off by the difference, and sliding at
; the beat rate). The dial is fast in coarse range, slow within CL_DETAIL
; of the target (CL_MODE). Inside the lock window (WIN units) the tuner wave turns green
; and the lock bar fills; outside it drains at twice that rate. A full bar
; wins. The clock keeps running; an attempt times out after ~30 s (CL_TSTEP:
; "signal lost", try again); fire aborts or, once it's over, returns to the
; room. A win: one more reset key (RESET_KEYS; F1 -> R spends one instead of the time
; penalty) and CL_WON + 1, which selects the next, harder level — one column
; per key in the tables below:
;   WIN   the lock window (units of difference)
;   HSTEP frames per lock bar cell (24 cells: the hold time)
;   DRIFT / DRT  the target moves DRIFT units every DRT frames (0 = still),
;         reversing now and then
;   JIT   from the 5th key: the target jumps to base +-JIT every 4 frames
;   HINT  the scope's tuner wave: 2 = wavelength and slide, 1 = the slide
;         only, 0 = noise (ear only)
; Once JIT > 2*WIN (the 7th key on) the dial is in the window at most about
; half the time, and with the bar draining twice as fast as it fills, a full
; lock is out of reach: ten keys can't be won.
; =============================================================================

RESET_KEYS !byte 0                      ; reset keys held (F1 -> R)
CL_WON     !byte 0                      ; keys won this game (the level)

CL_LVL   !byte 0                        ; level index, min(CL_WON, 9)
CL_ST    !byte 0                        ; 0 tuning, 1 won, 2 lost
CL_MOFF  !byte 0                        ; MUSIC_OFF to restore
CL_DIAL  !word 0                        ; the player's frequency (voice 2)
CL_BASE  !word 0                        ; the target before jitter
CL_TGT   !word 0                        ; the target (voice 1)
CL_JOFS  !byte 0                        ; jitter offset (signed)
CL_DDIR  !byte 0                        ; drift direction: 0 up, 1 down
CL_DT    !byte 0                        ; drift timer
CL_RATE  !byte 0                        ; dial speed, units per frame
CL_RMIN  = 1                            ; detailed: its start (a tap: ~5 units)
CL_FMAX  = 6                            ;  and top speed
CL_CSPD  = 48                           ; coarse: the speed (worst start ~3 s)
CL_HELD  !byte 0                        ; frames into the current speed step
CL_SLOW  !byte 0                        ; 1 = this hold reached detailed range
CL_DET   !byte 0                        ; range mode: 0 coarse, 8 detailed (dial speed)
CL_DETAIL = 48                          ; |diff| below it: detailed
!if CL_CSPD >= 2*CL_DETAIL { !error "CL_CSPD would jump across the detailed zone" }
CL_PH    !word 0                        ; beat phase (scope)
CL_DIFF  !word 0                        ; |dial - target|
CL_SD    !word 0                        ; dial - target (signed)
CL_HC    !byte 0                        ; lock bar cells, CL_HT frames into it
CL_IN    !byte 0                        ; 1 = the dial is in the lock window
CL_HT    !byte 0
CL_TC    !byte 0                        ; time bar cells left, CL_TT frames into it
CL_TT    !byte 0
CL_T     !byte 0                        ; frame counter (scope scroll)
CL_LSN   !byte 0                        ; frames the target plays alone first
CL_LISTEN = 50                          ; (1 s: "this is the tone to match")

CL_MIN   = $1000                        ; dial range (~240-960 Hz)
CL_MAXHI = $3F
CL_CELLS = 24                           ; bar width
CL_TSTEP = 62                           ; frames per time cell (24*62: ~30 s)
CL_BAR   = 10                           ; first bar column

;               key:  1   2   3   4   5   6   7   8   9  10+
CL_WIN   !byte       80, 56, 34, 20, 12,  8,  4,  3,  2,  2
CL_HSTEP !byte        3,  4,  4,  5,  6,  6,  7,  7,  8,  8
CL_DRIFT !byte        0,  0,  1,  1,  1,  1,  2,  2,  2,  3
CL_DRT   !byte        0,  0,  8,  4,  2,  1,  1,  1,  1,  1
CL_JIT   !byte        0,  0,  0,  0,  3,  6,  9,  8,  6,  6
CL_HINT  !byte        2,  2,  2,  1,  0,  0,  0,  0,  0,  0

; -----------------------------------------------------------------------------
; CL_RESET — SETUP_GAME: the starting reset keys, back to the first level
; -----------------------------------------------------------------------------
CL_RESET
        lda #CFG_RESET_START : sta RESET_KEYS
        lda #0 : sta CL_WON
        rts

; -----------------------------------------------------------------------------
; ANIM_COMM — every game frame (GAME_ALIVE): every COMM_RATE frames swap the
; bitmaps of the two sine waves' chars ($D6 <-> $D7, $D8 <-> $D9) and the radio antenna's
; ($CB <-> $CC) in the charset, so every one on screen pulses at once with
; no screen writes (like ANIM_LASER). Each pair shares its TILE_COLORS colour.
; -----------------------------------------------------------------------------
COMM_RATE = 25                          ; 2 swaps a second
COMM_TMR  !byte COMM_RATE
CH_SINE   = CHARSET+$D6*8               ; $D6, $D7
CH_SINE2  = CHARSET+$D8*8               ; $D8, $D9 (the second wave)
CH_ANT    = CHARSET+$CB*8               ; $CB, $CC
ANIM_COMM
        dec COMM_TMR : bne ACDONE
        lda #COMM_RATE : sta COMM_TMR
        ldx #7
ACSWAP  lda CH_SINE,x : ldy CH_SINE+8,x
        sta CH_SINE+8,x : tya : sta CH_SINE,x
        lda CH_SINE2,x : ldy CH_SINE2+8,x
        sta CH_SINE2+8,x : tya : sta CH_SINE2,x
        lda CH_ANT,x : ldy CH_ANT+8,x
        sta CH_ANT+8,x : tya : sta CH_ANT,x
        dex : bpl ACSWAP
ACDONE  rts

; -----------------------------------------------------------------------------
; SUB_MINUTES — A = minutes (1-59): take them off the clock, clamped at
; 0:00:00. Returns Z set (A = 0) if the clock is now at zero. Death penalty
; (APPLY_DEATH_PENALTY) and the F1 -> R reset without a key (help.asm).
; -----------------------------------------------------------------------------
SUB_MINUTES
        sta TMP
        lda CLK_M : cmp TMP : bcs SMSUB  ; enough minutes
        lda CLK_H : bne SMBOR
        lda #0 : sta CLK_H : sta CLK_M : sta CLK_S   ; not enough time: zero
        beq SMCHK
SMBOR   dec CLK_H                        ; borrow an hour
        lda CLK_M : clc : adc #60 : sec : sbc TMP : sta CLK_M
        jmp SMCHK
SMSUB   sbc TMP : sta CLK_M              ; (C set)
SMCHK   lda CLK_H : ora CLK_M : ora CLK_S
        rts

; -----------------------------------------------------------------------------
; SETUP_CARRIER — from READ_KEYS (fire on a COMM desk; a tail call, so it
; returns to DO_GAME, which sees state 10): draw the screen, start the tones
; -----------------------------------------------------------------------------
SETUP_CARRIER
        lda #10 : sta GAME_STATE
        lda #0 : sta $C6
        lda MUSIC_OFF : sta CL_MOFF
        lda #1 : sta MUSIC_OFF           ; (first: then no music frame sneaks in)
        lda #$08 : sta $D404 : sta $D40B ; TEST: both oscillators restart
                                         ;  from a known state (CL_SOUND
                                         ;  rewrites the waveform next frame)
        lda #0 : sta SND_TMR             ; (A = 0 for the stores below)
        sta CL_ST : sta CL_HELD : sta CL_DET : sta CL_SLOW : sta CL_DT : sta CL_JOFS : sta CL_T
        sta CL_HC : sta CL_HT : sta CL_TT : sta CL_IN
        lda #CL_LISTEN : sta CL_LSN
        lda #0
        sta CL_PH : sta CL_PH+1
        lda #CL_CELLS : sta CL_TC
        lda #CL_RMIN : sta CL_RATE
        lda CL_WON : cmp #9 : bcc CLSL
        lda #9
CLSL    sta CL_LVL

        ; the target: $1800-$37FF; the dial 25-55% off it, either way
        jsr RAND : and #$1F : clc : adc #$18 : sta CL_BASE+1
        jsr RAND : sta CL_BASE
        jsr RAND : and #$08 : lsr : lsr : lsr : sta CL_DDIR
        lda CL_BASE : sta CL_TGT : lda CL_BASE+1 : sta CL_TGT+1
        jsr RAND : lsr : lsr : lsr : and #7   ; 0-7 pages, plus a quarter
        sta TMP2                         ;  of the target: 25-55% off it,
        lda CL_BASE+1 : lsr : lsr        ;  about 4-8 semitones -- two
        clc : adc TMP2 : sta TMP2        ;  clearly different notes ...
        jsr RAND : and #$40 : beq CLSUP  ; ... below or above
        lda CL_BASE+1 : sec : sbc TMP2 : jmp CLSDST
CLSUP   lda CL_BASE+1 : clc : adc TMP2
CLSDST  sta CL_DIAL+1
        jsr RAND : sta CL_DIAL
        jsr CL_CLAMP

        jsr CLEAR_ROOM
        lda #$00 : sta VIC_SPEN
        lda #<CL_ROWS : ldy #>CL_ROWS : jsr DRAW_ROWS
        lda CL_WON : clc : adc #1 : jsr DEC2   ; "key nn"
        lda TMP : sta SCRN+5*40+24 : lda TMP2 : sta SCRN+5*40+25
        lda #LTGREEN : ldx #4 : ldy #17 : jsr FRAME_EDGES

        lda #$00 : sta $D402             ; the target's pulse: 50%
        lda #$08 : sta $D403
        lda #$00 : sta $D405 : sta $D40C ; attack/decay 0
        lda #$F0 : sta $D406 : sta $D40D ; sustain full, release 0
        lda #$0F : sta $D418
        rts

; CL_CLAMP — keep the dial in CL_MIN .. CL_MAXHI*256+255
CL_CLAMP
        lda CL_DIAL+1 : cmp #>CL_MIN : bcs CLCLO
        lda #0 : sta CL_DIAL : lda #>CL_MIN : sta CL_DIAL+1
        rts
CLCLO   cmp #CL_MAXHI+1 : bcc CLCOK
        lda #$FF : sta CL_DIAL : lda #CL_MAXHI : sta CL_DIAL+1
CLCOK   rts

; -----------------------------------------------------------------------------
; DO_CARRIER — every frame in state 10
; -----------------------------------------------------------------------------
DO_CARRIER
        jsr TICK_CLOCK                   ; the clock keeps running
        lda CLK_H : ora CLK_M : ora CLK_S : bne CLCLK
        jsr SETUP_GAMEOVER               ; (silences the voices)
        jmp MAIN_LOOP
CLCLK   jsr DRAW_HUD_DYNAMIC
        lda CL_ST : beq CLPLAY
        lda JOY_NEW : and #$10 : beq CLOUT   ; won / lost: fire = back
        jmp CL_EXIT
CLPLAY  lda JOY_NEW : and #$10 : beq CLNOAB  ; fire: give up
        jmp CL_EXIT
CLNOAB  inc CL_T
        jsr CL_DIALIN
        jsr CL_DRIFTS
        jsr CL_SOUND
        jsr CL_LOCK
        jsr CL_MODE
        jsr CL_SCOPE
        jsr CL_BARS
        lda CL_TC : bne CLOUT            ; time's up: "signal lost"
        lda #2 : sta CL_ST
        lda #<CLS_LOST : sta PTR : lda #>CLS_LOST : sta PTR+1
        lda #LTRED : jmp CL_END
CLOUT   jmp MAIN_LOOP

; CL_END — A = colour, PTR = message: show it on row 15, the tones off
CL_END  sta TMP2
        lda #15 : jsr DRAW_ROW
        lda #LTGREEN : ldx #4 : ldy #17 : jsr FRAME_EDGES
        lda #$40 : sta $D404             ; gates off
        lda #$10 : sta $D40B
        jmp MAIN_LOOP

; CL_EXIT — back to the room (as the terminal's logoff)
CL_EXIT
        lda #0 : sta $D404 : sta $D40B
        lda CL_MOFF : sta MUSIC_OFF
        lda #0 : sta $C6
        jmp TERM_ABORT                   ; (terminal.asm)

; CL_DIALIN — left/right: turn the dial. The speed follows the range mode
; (CL_DET, last frame's): coarse, a steady CL_CSPD units a frame; detailed,
; CL_RMIN, one more every 8 frames held, up to CL_FMAX — entering detailed
; mode drops it to CL_RMIN at once, and it stays slow until let go
; (CL_SLOW: holding on through the zone mustn't speed up on the far side).
; CL_CSPD < 2*CL_DETAIL, so the dial can't jump across the detailed zone. (Speeding up with hold time —
; doubling, then +25% steps — felt like "nothing, then it flies away".)
CL_DIALIN
        lda #0 : sta TMP2                ; bit 0 left, bit 1 right
        lda JOY_PREV : and #$04 : beq CLDA
        inc TMP2
CLDA    lda #$FD : sta CIA1_PRA          ; A: col 1, row 2
        lda CIA1_PRB : and #$04 : bne CLDJR
        lda #1 : ora TMP2 : sta TMP2
CLDJR   lda JOY_PREV : and #$08 : beq CLDD
        lda #2 : ora TMP2 : sta TMP2
CLDD    lda #$FB : sta CIA1_PRA          ; D: col 2, row 2
        lda CIA1_PRB : and #$04 : bne CLDK
        lda #2 : ora TMP2 : sta TMP2
CLDK    lda #$FF : sta CIA1_PRA
        lda TMP2 : beq CLDREL
        cmp #3 : beq CLDREL              ; both: nothing
        inc CL_HELD
        lda CL_DET : bne CLDDET
        lda CL_SLOW : beq CLDCO          ; slowed on this hold: stay slow
        bne CLDF
CLDDET  lda #1 : sta CL_SLOW
        lda CL_RATE : cmp #CL_FMAX+1 : bcc CLDF
        lda #CL_RMIN : sta CL_RATE       ; just came in from coarse: slow
        lda #0 : sta CL_HELD
CLDF    lda CL_HELD : and #7 : bne CLDMOV
        lda CL_RATE : cmp #CL_FMAX : bcs CLDMOV
        inc CL_RATE : bne CLDMOV         ; detailed: +1 every 8 frames
CLDCO   lda #CL_CSPD : sta CL_RATE       ; coarse: one steady speed
CLDMOV  lda TMP2 : cmp #1 : bne CLDUP
        lda CL_DIAL : sec : sbc CL_RATE : sta CL_DIAL
        bcs CLDCL
        dec CL_DIAL+1
        jmp CLDCL
CLDUP   lda CL_DIAL : clc : adc CL_RATE : sta CL_DIAL
        bcc CLDCL
        inc CL_DIAL+1
CLDCL   jmp CL_CLAMP
CLDREL  lda #0 : sta CL_HELD : sta CL_SLOW
        lda #CL_RMIN : sta CL_RATE
        rts

; CL_DRIFTS — the target drifts (DRIFT units every DRT frames, sometimes
; turning round, and at the range's ends) and jitters (+-JIT every 4 frames)
CL_DRIFTS
        ldx CL_LVL
        lda CL_DRT,x : beq CLJIT
        inc CL_DT
        lda CL_DT : cmp CL_DRT,x : bcc CLJIT
        lda #0 : sta CL_DT
        jsr RAND : and #$78 : bne CLDNR  ; ~1 in 16: turn round
        lda CL_DDIR : eor #1 : sta CL_DDIR
CLDNR   ldx CL_LVL
        lda CL_DDIR : bne CLDDN
        lda CL_BASE : clc : adc CL_DRIFT,x : sta CL_BASE
        bcc CLDUC
        inc CL_BASE+1
CLDUC   lda CL_BASE+1 : cmp #$38 : bcc CLJIT
        lda #1 : sta CL_DDIR             ; top of the range: down again
        bne CLJIT
CLDDN   lda CL_BASE : sec : sbc CL_DRIFT,x : sta CL_BASE
        bcs CLDDC
        dec CL_BASE+1
CLDDC   lda CL_BASE+1 : cmp #$18 : bcs CLJIT
        lda #0 : sta CL_DDIR             ; bottom: up again
CLJIT   ldx CL_LVL
        lda CL_JIT,x : beq CLJSET
        lda CL_T : and #3 : bne CLJSET
        lda CL_JIT,x : asl : sta TMP     ; 2*JIT (+1 below)
        jsr RAND : lsr : lsr : lsr       ; 0-31
CLJMOD  cmp TMP : bcc CLJOK : beq CLJOK  ; reduce to 0 .. 2*JIT
        clc : sbc TMP                    ; (C clear: - (2*JIT+1))
        jmp CLJMOD
CLJOK   ldx CL_LVL
        sec : sbc CL_JIT,x : sta CL_JOFS ; -JIT .. +JIT
CLJSET  lda CL_JOFS : bmi CLJNEG
        clc : adc CL_BASE : sta CL_TGT
        lda CL_BASE+1 : adc #0 : sta CL_TGT+1
        rts
CLJNEG  clc : adc CL_BASE : sta CL_TGT
        lda CL_BASE+1 : adc #$FF : sta CL_TGT+1
        rts

; CL_SOUND — both tones, every frame (the help screen may have stopped
; them): the target a buzzy 50% pulse on voice 1, the tuner a soft triangle
; on voice 2 — different timbres, so they're heard as two tones (and still
; beat against each other). The target plays alone for the first second.
CL_SOUND
        lda CL_TGT : sta $D400 : lda CL_TGT+1 : sta $D401
        lda CL_DIAL : sta $D407 : lda CL_DIAL+1 : sta $D408
        lda #$41 : sta $D404             ; pulse, gate on
        lda CL_LSN : beq CLSNTUN
        dec CL_LSN
        lda #$10 : bne CLSNV2            ; listening: the tuner's gate off
CLSNTUN lda #$11                         ; triangle, gate on
CLSNV2  sta $D40B
        lda #$0F : sta $D418
        rts

; CL_LOCK — CL_DIFF = |dial - target|; inside the window the lock bar fills
; (a full bar wins; CL_IN = 1), outside it drains at twice that rate. Also
; advances the scope's
; beat phase: CL_PH += diff*80 (one beat is 65536 at 0.0587 Hz per unit and
; 50 frames per second: ~77 per unit and frame).
CL_LOCK
        lda CL_DIAL : sec : sbc CL_TGT : sta CL_SD
        lda CL_DIAL+1 : sbc CL_TGT+1 : sta CL_SD+1
        lda CL_SD : sta TMP : lda CL_SD+1 : sta TMP2
        ldx #4                           ; diff*16 (signed, mod 65536)
CLLS4   asl TMP : rol TMP2 : dex : bne CLLS4
        lda CL_PH : clc : adc TMP : sta CL_PH
        lda CL_PH+1 : adc TMP2 : sta CL_PH+1
        asl TMP : rol TMP2 : asl TMP : rol TMP2   ; diff*64
        lda CL_PH : clc : adc TMP : sta CL_PH
        lda CL_PH+1 : adc TMP2 : sta CL_PH+1
        lda CL_SD : sta CL_DIFF : lda CL_SD+1 : sta CL_DIFF+1
        bpl CLLPOS                       ; |diff|
        lda #0 : sec : sbc CL_DIFF : sta CL_DIFF
        lda #0 : sbc CL_DIFF+1 : sta CL_DIFF+1
CLLPOS
        ldx CL_LVL
        lda CL_DIFF+1 : bne CLLOUT
        lda CL_WIN,x : cmp CL_DIFF : bcc CLLOUT
        lda #1 : sta CL_IN               ; (the tuner wave turns green)
        inc CL_HT                        ; in the window: hold on
        lda CL_HT : cmp CL_HSTEP,x : bcc CLLDONE
        lda #0 : sta CL_HT
        inc CL_HC
        lda CL_HC : cmp #CL_CELLS : bcc CLLDONE
        pla : pla                        ; locked! (out of DO_CARRIER's jsr)
        jmp CL_WIN_IT
CLLOUT  lda #0 : sta CL_IN               ; out of it: the bar drains at
        inc CL_HT                        ;  twice the fill rate, so a slip
        lda CL_HT : cmp CL_HSTEP,x : bcc CLLDONE   ;  costs a little, not
        lda #0 : sta CL_HT               ;  everything (and a target that's
        lda CL_HC : beq CLLDONE          ;  in the window only half the
        dec CL_HC : beq CLLDONE          ;  time, keys 7+, can't fill it)
        dec CL_HC
CLLDONE rts

; CL_WIN_IT — a key: the next level is harder
CL_WIN_IT
        lda #1 : sta CL_ST
        jsr CL_BARS                      ; the full lock bar (no time tick)
        lda RESET_KEYS : cmp #9 : bcs CLWMAX
        inc RESET_KEYS
CLWMAX  inc CL_WON
        lda #<CLS_WON : sta PTR : lda #>CLS_WON : sta PTR+1
        lda #LTGREEN : jmp CL_END

; CL_SCOPE — two waves on top of each other: the target (row 8) and the
; tuner (row 9). Both scroll along; the tuner's is drawn with
;   - a wavelength off by (dial - target)/32 (clamped): far off it's visibly
;     shorter (too high) or longer (too low) than the target's,
;   - an offset of the beat phase (CL_PH): near the target it slides against
;     the target wave at the beat rate — one way too high, the other too low —
;     slowing down as it closes in, standing still in lock.
; HINT 1 leaves out the wavelength (the slide only, dimmer), HINT 0 shows
; noise on the tuner row (ear only).
CL_SCOPE
        lda CL_T : asl : asl : sta PTR   ; scroll: phase at column 0
        lda #32 : sta TMP2               ; target: 1/8 cycle per column
        lda #CYAN : sta PTR+1
        lda #8 : jsr CL_WAVEROW
        ldx CL_LVL
        lda CL_HINT,x : bne CLSCW
        ldx #0                           ; ear only: noise
CLSCN   jsr RAND : lsr : lsr : lsr : lsr : lsr   ; 0-7
        tay : lda CL_WAVE+48,y
        sta SCRN+9*40+CL_BAR,x
        lda #DGRAY : sta CRAM+9*40+CL_BAR,x
        inx : cpx #CL_CELLS : bcc CLSCN
        rts
CLSCW   pha
        lda #32 : sta TMP2               ; tuner: the same wavelength ...
        pla : cmp #2 : bne CLSCDIM
        jsr CL_STEP                      ; ... or off by the difference
        lda #YELLOW : bne CLSCC
CLSCDIM lda #MGRAY
CLSCC   ldy CL_IN : beq CLSCC2
        lda #LTGREEN                     ; in the lock window
CLSCC2  sta PTR+1
        lda CL_T : asl : asl : clc : adc CL_PH+1 : sta PTR   ; + beat phase
        lda #9                           ; (falls into CL_WAVEROW)

; CL_WAVEROW — A = screen row: 24 cells of the big sine wave, phase PTR at
; the first cell, TMP2 per cell (256 = one cycle), colour PTR+1
CL_WAVEROW
        jsr ROW_PTR                      ; PTR2 = the row
        ldy #CL_BAR
CLWRL   lda PTR : lsr : lsr : lsr : lsr  ; 16 steps per cycle
        tax : lda CL_WAVE+48,x : sta (PTR2),y
        lda PTR : clc : adc TMP2 : sta PTR
        iny : cpy #CL_BAR+CL_CELLS : bcc CLWRL
        lda PTR2+1 : clc : adc #>(CRAM-SCRN) : sta PTR2+1
        lda PTR+1
        ldy #CL_BAR
CLWRC   sta (PTR2),y
        iny : cpy #CL_BAR+CL_CELLS : bcc CLWRC
        rts

; CL_STEP — TMP2 = 32 + (dial - target)/32, clamped to 8..56
CL_STEP
        lda CL_SD+1 : bmi CLSTN
        cmp #3 : bcs CLSTMAX             ; >= 768: the most
        lda CL_SD : sta PTR : lda CL_SD+1
        ldx #5
CLSTP   lsr : ror PTR : dex : bne CLSTP
        lda PTR : clc : adc #32 : sta TMP2
        rts
CLSTMAX lda #56 : sta TMP2
        rts
CLSTN   cmp #$FD : bcc CLSTMIN           ; <= -768: the least
        lda CL_SD : sta PTR : lda CL_SD+1
        ldx #5
CLSTNL  sec : ror : ror PTR : dex : bne CLSTNL   ; arithmetic shift (negative)
        lda PTR : clc : adc #32 : sta TMP2
        rts
CLSTMIN lda #8 : sta TMP2
        rts

; CL_MODE — the range mode (CL_DET) for the dial's speed (CL_DIALIN):
; coarse (fast) while |diff| >= CL_DETAIL, detailed (slow) closer in
CL_MODE
        ldy #0                           ; coarse
        lda CL_DIFF+1 : bne CLMOD
        lda CL_DIFF : cmp #CL_DETAIL : bcs CLMOD
        ldy #8                           ; detailed
CLMOD   sty CL_DET
        rts

; CL_BARS — dial position, lock bar, time bar (and the time count-down)
CL_BARS
        lda CL_DIAL+1 : sec : sbc #>CL_MIN : lsr : sta TMP   ; dial cell 0-23
        ldx #0
CLBL    lda #$2E : ldy #DGRAY            ; '.'
        cpx TMP : bne CLBD
        lda #CH_SOLID : ldy #WHITE
CLBD    sta SCRN+10*40+CL_BAR,x
        tya : sta CRAM+10*40+CL_BAR,x
        lda #$2E : ldy #DGRAY            ; lock bar
        cpx CL_HC : bcs CLBH
        lda #CH_SOLID : ldy #LTGREEN
CLBH    sta SCRN+12*40+CL_BAR,x
        tya : sta CRAM+12*40+CL_BAR,x
        lda #$2E : ldy #DGRAY            ; time bar
        cpx CL_TC : bcs CLBT
        lda #CH_SOLID : ldy #YELLOW
        cpx #6 : bcs CLBT
        ldy #LTRED
CLBT    sta SCRN+13*40+CL_BAR,x
        tya : sta CRAM+13*40+CL_BAR,x
        inx : cpx #CL_CELLS : bcc CLBL
        lda CL_ST : bne CLBOUT           ; (the win's last draw: no tick)
        inc CL_TT
        lda CL_TT : cmp #CL_TSTEP : bcc CLBOUT
        lda #0 : sta CL_TT
        dec CL_TC
CLBOUT  rts

; scope glyphs: 4 amplitudes x 16 columns of one sine period, drawn with the
; ROM's horizontal line glyphs at 7 heights ($77 top .. $6F bottom)
CL_WAVE
        !byte $43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43,$43   ; amplitude 0
        !byte $43,$43,$44,$44,$44,$44,$44,$43,$43,$43,$46,$46,$46,$46,$46,$43   ; amplitude 1
        !byte $43,$44,$44,$45,$45,$45,$44,$44,$43,$46,$46,$52,$52,$52,$46,$46   ; amplitude 2
        !byte $43,$44,$45,$77,$77,$77,$45,$44,$43,$46,$52,$6f,$6f,$6f,$52,$46   ; amplitude 3

; screen rows (DRAW_ROWS)
CL_ROWS
        !byte 4,  LTGREEN, <SCR_BORDER_TOP, >SCR_BORDER_TOP
        !byte 5,  LTGREEN, <CLS_TTL, >CLS_TTL
        !byte 6,  GREEN,   <CLS_SUB, >CLS_SUB
        !byte 7,  GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 8,  GREEN,   <CLS_SCP, >CLS_SCP
        !byte 9,  GREEN,   <CLS_TUN, >CLS_TUN
        !byte 10, GREEN,   <CLS_DIA, >CLS_DIA
        !byte 11, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 12, GREEN,   <CLS_LCK, >CLS_LCK
        !byte 13, GREEN,   <CLS_TIM, >CLS_TIM
        !byte 14, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 15, GREEN,   <SCR_BLANK, >SCR_BLANK
        !byte 16, LTRED,   <CLS_HNT, >CLS_HNT
        !byte 17, LTGREEN, <SCR_BORDER_BOTTOM, >SCR_BORDER_BOTTOM
        !byte $FF

CLS_TTL  !pet G_VERT_BAR, "  * carrier lock - key 01             ", G_VERT_BAR
CLS_SUB  !pet G_VERT_BAR, "  tune in the carrier. stop the beat. ", G_VERT_BAR
CLS_SCP  !pet G_VERT_BAR, " target [                        ]    ", G_VERT_BAR
CLS_TUN  !pet G_VERT_BAR, " tuner  [                        ]    ", G_VERT_BAR
CLS_DIA  !pet G_VERT_BAR, " dial   [                        ]    ", G_VERT_BAR
CLS_LCK  !pet G_VERT_BAR, " lock   [                        ]    ", G_VERT_BAR
CLS_TIM  !pet G_VERT_BAR, " time   [                        ]    ", G_VERT_BAR
CLS_HNT  !pet G_VERT_BAR, "    left/right=tune     fire=abort    ", G_VERT_BAR
CLS_WON  !pet G_VERT_BAR, "    reset key decoded! fire=return    ", G_VERT_BAR
CLS_LOST !pet G_VERT_BAR, "    signal lost.  fire=return         ", G_VERT_BAR
!if * - CLS_TTL != 10*40 { !error "carrier rows must be 40 bytes each" }
