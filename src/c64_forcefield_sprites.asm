; C64 multicolor force field beam - 2 frames x 64 bytes, alternate every 2-3 frames
; $D025 (MC0, %01) = black (0), $D026 (MC1, %11) = light grey (15)  [shared with all characters]
; $D027+n (sprite colour, %10) = front strand: white (1) by default, or the robot's own colour
; enable multicolor in $D01C
; horizontal, tiles seamlessly: place sprites side by side every 24 px, or set X-expand ($D01D) for 48 px each
; beam centre line is sprite row 10 (rows 4..16 used); symmetric, so it works pointing left or right

forcefield_1:
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$cc,$00,$00,$30
    !byte $00,$30,$00,$00,$0c,$0f,$80,$f8,$30,$83,$02,$30,$23,$02,$80,$08
    !byte $00,$20,$32,$03,$20,$c2,$03,$0a,$c0,$ac,$00,$00,$00,$00,$c3,$00
    !byte $00,$30,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

forcefield_2:
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$03,$30,$0c
    !byte $00,$c0,$00,$00,$00,$e0,$3e,$03,$20,$c0,$8c,$08,$c0,$b0,$02,$00
    !byte $20,$0c,$80,$e0,$30,$80,$c8,$b0,$2b,$02,$c0,$00,$00,$00,$c0,$03
    !byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

