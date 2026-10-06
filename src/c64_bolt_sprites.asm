; C64 multicolor plasma bolt - 2 frames x 64 bytes, alternate them every 1-2 frames
; $D025 (MC0, %01) = black (0), $D026 (MC1, %11) = light grey (15)  [shared with all characters]
; $D027+n (sprite colour, %10) = hot core: white (1) by default, or tint per shooter
; enable multicolor in $D01C
; round shape works for all four directions; the core sits at sprite pixels x=8..15, y=8..13
; (centre of the bolt = sprite x+12, y+9.5) - offset from the shooter's gun position by that

bolt_1:
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$3c,$00,$00,$3c,$00,$00,$eb,$00,$0f,$aa,$f0,$0f,$aa
    !byte $f0,$00,$eb,$00,$00,$3c,$00,$00,$3c,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

bolt_2:
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$03,$00,$c0,$00,$c3,$00,$00,$eb,$00,$03,$aa,$c0,$03,$aa
    !byte $c0,$00,$eb,$00,$00,$c3,$00,$03,$00,$c0,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

