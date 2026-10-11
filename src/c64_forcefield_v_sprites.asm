; C64 multicolor force field beam, VERTICAL - 2 frames x 64 bytes, alternate every 2-3 frames
; companion to forcefield_1/2 (horizontal); same colours and same animation timing
; $D025 (MC0, %01) = black (0), $D026 (MC1, %11) = light grey (15)  [shared with all characters]
; $D027+n (sprite colour, %10) = front strand: white (1) by default, or the robot's own colour
; enable multicolor in $D01C
; vertical, tiles seamlessly: stack sprites every 21 px, or set Y-expand ($D017) for 42 px each
; beam is centred on sprite x = 12 (hires), strands use x = 6..19; works pointing up or down

forcefield_v_1:
    !byte $00,$08,$00,$00,$38,$00,$c0,$c2,$00,$30,$c2,$00,$c3,$00,$80,$03
    !byte $00,$80,$02,$00,$c0,$02,$00,$c0,$00,$83,$03,$00,$83,$0c,$00,$2c
    !byte $03,$00,$38,$00,$00,$c2,$00,$00,$c2,$00,$03,$00,$80,$0f,$00,$80
    !byte $32,$00,$c0,$02,$00,$c0,$00,$83,$30,$00,$83,$0c,$00,$2c,$00,$00

forcefield_v_2:
    !byte $03,$00,$80,$02,$00,$c0,$02,$00,$c3,$00,$83,$0c,$00,$2c,$03,$00
    !byte $2c,$00,$00,$38,$00,$00,$c2,$00,$c0,$c2,$00,$33,$00,$80,$c3,$00
    !byte $80,$02,$00,$c0,$02,$00,$c0,$00,$83,$00,$00,$83,$30,$00,$2c,$0c
    !byte $00,$38,$00,$00,$38,$00,$0c,$c2,$00,$33,$00,$80,$03,$00,$80,$00

