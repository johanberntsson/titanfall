; TITAN Fall - Commodore 64 / 6510
; Boot stub: cycles border colors then returns to BASIC
;
; ACME assembler

VIC_BORDER = $D020

; ------------------------------------------------------------------
; BASIC stub: 10 SYS 2061
;
; $0801  0B 08       next-line pointer -> $080B
; $0803  0A 00       line number 10
; $0805  9E          SYS token
; $0806  "2061"      target address in ASCII (= $080D)
; $080A  00          end of line
; $080B  00 00       end of BASIC program
; $080D              machine code begins here
; ------------------------------------------------------------------
* = $0801
    !byte $0B, $08          ; next-line pointer ($080B)
    !byte $0A, $00          ; line number 10
    !byte $9E               ; SYS token
    !text "2061"            ; SYS target = $080D = 2061 decimal
    !byte $00               ; end of line
    !byte $00, $00          ; end of BASIC program

; ------------------------------------------------------------------
; Entry point ($080D)
; ------------------------------------------------------------------
start:
    lda VIC_BORDER          ; save original border color
    sta orig_border

    lda #4
    sta flash_cycles        ; 4 full color sweeps (0-15 each)

cycle_loop:
    lda #0
color_loop:
    sta VIC_BORDER          ; set border to current color
    pha                     ; preserve color across JSR (delay trashes X/Y)
    jsr delay
    pla
    clc
    adc #1
    cmp #16
    bne color_loop

    dec flash_cycles
    bne cycle_loop

    lda orig_border         ; restore border and hand back to BASIC
    sta VIC_BORDER
    rts

; ------------------------------------------------------------------
; delay - burns ~80 ms at 1 MHz PAL
; trashes X, Y; preserves A
; ------------------------------------------------------------------
delay:
    ldx #80
delay_x:
    ldy #200
delay_y:
    dey
    bne delay_y
    dex
    bne delay_x
    rts

; ------------------------------------------------------------------
; Variables
; ------------------------------------------------------------------
orig_border:    !byte 0
flash_cycles:   !byte 0
