; =============================================================================
; ROOM MAP UNPACKING — genworld.py stores every ROOM_MAP_n RLE-packed (a
; literal char, or RLE_ESC, count, char for a run; RLE_ESC, 0 ends it). The
; current room is unpacked into ROOM_BUF (22 rows x 40 screen codes), which
; DRAW_ROOM blits and every "put the map's chars back" path reads (ART_LIST,
; CRATE_PAINT, TRAP_ROWS, BEAM_CELL).
; =============================================================================

; ROOM_UNPACK — CUR_ROOM's map into ROOM_BUF, unless it's there already
; (RU_ROOM; the packed data never changes). Clobbers A/X/Y/PTR/PTR2.
ROOM_UNPACK
        lda CUR_ROOM : cmp RU_ROOM : beq RUOUT
        sta RU_ROOM
        tax
        lda ROOM_MAP_LO,x : sta PTR
        lda ROOM_MAP_HI,x : sta PTR+1
        lda #<ROOM_BUF : sta PTR2
        lda #>ROOM_BUF : sta PTR2+1
RUL     ldy #0
        lda (PTR),y : cmp #RLE_ESC : beq RURUN
        sta (PTR2),y                     ; a literal
        lda #1 : jsr RU_SRC
        lda #1 : jsr RU_DST
        jmp RUL
RURUN   iny : lda (PTR),y : beq RUOUT    ; ESC, 0: the end
        tax                              ; ESC, count, char: a run
        iny : lda (PTR),y
        ldy #0
RURL    sta (PTR2),y
        iny : dex : bne RURL
        tya : jsr RU_DST                 ; (count 1-255)
        lda #3 : jsr RU_SRC
        jmp RUL
RUOUT   rts

RU_SRC  clc : adc PTR : sta PTR          ; PTR += A
        bcc RUS1 : inc PTR+1
RUS1    rts
RU_DST  clc : adc PTR2 : sta PTR2        ; PTR2 += A
        bcc RUD1 : inc PTR2+1
RUD1    rts

RU_ROOM !byte $FF                        ; the room in ROOM_BUF ($ff = none)
ROOM_BUF !fill 22*40, 0                  ; the current room's map, unpacked
