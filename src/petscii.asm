; =============================================================================
; C64 PETSCII CONTROL AND GRAPHICS DEFINITIONS FOR ACME (WITH CORNERS)
; =============================================================================

; =============================================================================
; Screen codes (direct pokes to the screen, in upper case mode)
; =============================================================================

; --- Structural Graphics (screen codes) ---
S_HORIZ_BAR = 67    ; Horizontal line ─
S_VERT_BAR  = 93    ; Vertical line │

; --- Sharp / Square Corners (screen codes) ---
S_SQ_UL     = 112   ; Sharp Upper-Left  ┌
S_SQ_UR     = 110   ; Sharp Upper-Right ┐
S_SQ_LL     = 109   ; Sharp Lower-Left  └
S_SQ_LR     = 125   ; Sharp Lower-Right ┘

; --- Rounded Corners (screen codes) ---
S_RD_UL     = 85   ; Rounded Upper-Left  ╭
S_RD_UR     = 75   ; Rounded Upper-Right ╮
S_RD_LL     = 76   ; Rounded Lower-Left  ╰
S_RD_LR     = 77   ; Rounded Lower-Right ╯

; =============================================================================
; Petscii codes (can be used in calls to $ffd2 or chr$())
; =============================================================================

; --- Screen & Text Controls ---
CLR         = 147   ; Clear Screen and Home cursor
HOME        = 19    ; Home cursor without clearing
REV_ON      = 18    ; Reverse Video ON
REV_OFF     = 146   ; Reverse Video OFF
CR          = 13    ; Carriage Return (Enter)
NULL        = 0     ; Null terminator for print loops

; --- All 16 C64 Colors ---
;BLACK       = 144
;WHITE       = 5
;RED         = 28
;CYAN        = 159
;PURPLE      = 156
;GREEN       = 30
;BLUE        = 31
;YELLOW      = 158
;ORANGE      = 129
;BROWN       = 149
L_RED       = 150   ; Light Red / Pink
DARK_GRAY   = 151   ; Dark Grey
MED_GRAY    = 152   ; Medium Grey
L_GREEN     = 153   ; Light Green
L_BLUE      = 154   ; Light Blue
L_GRAY      = 155   ; Light Grey

; --- Structural Graphics (petscii) ---
G_HORIZ_BAR = 99    ; Horizontal line ─
G_VERT_BAR  = 125   ; Vertical line │

; --- Sharp / Square Corners (petscii) ---
G_SQ_UL     = 176   ; Sharp Upper-Left  ┌
G_SQ_UR     = 174   ; Sharp Upper-Right ┐
G_SQ_LL     = 173   ; Sharp Lower-Left  └
G_SQ_LR     = 189   ; Sharp Lower-Right ┘

; --- Rounded Corners (petscii) ---
G_RD_UL     = 213   ; Rounded Upper-Left  ╭
G_RD_UR     = 201   ; Rounded Upper-Right ╮
G_RD_LL     = 202   ; Rounded Lower-Left  ╰
G_RD_LR     = 203   ; Rounded Lower-Right ╯

; --- Card Suits & Misc Graphics ---
G_SPADE     = 161   ; ♠
G_CLUB      = 163   ; ♣
G_HEART     = 179   ; ♥
G_DIAMOND   = 186   ; ♦
G_CIRCLE    = 215   ; Solid/open circle
G_SLASH     = 110   ; Forward slash line
G_BACKSLASH = 112   ; Backward slash line
G_SQUARE    = 160   ; Solid block 


; =============================================================================
; MINI FRAME EXAMPLE:
; =============================================================================

; Draw the top of a rounded box: ╭─────╮
; !pet G_RD_UL, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_RD_UR, CR

; Draw the middle: │ ♠ │
; !pet G_VERT_BAR, " ", G_SPADE, " ", G_VERT_BAR, CR

; Draw the bottom: ╰─────╯
; !pet G_RD_LL, G_HORIZ_BAR, G_HORIZ_BAR, G_HORIZ_BAR, G_RD_LR, CR, NULL

