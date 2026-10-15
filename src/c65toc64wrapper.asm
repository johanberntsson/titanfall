; c65toc64wrapper.asm — a front end that makes one PRG run on both the
; MEGA65 (C65 mode) and a C64 (or a MEGA65 in C64 mode). Adapted from Ozmoo's.
;
; Assembled on its own with `--setpc 0x2001 --cpu m65 -f cbm` and the packed
; game (a C64 PRG, load address $0801, SYS 2061) appended to it — see the
; Makefile's `universal` target. The BASIC line reads
;     IF PEEK(44)=8 THEN SYS 2081 : ELSE BANK 0 : SYS 8225
; C65 mode loads it at $2001 (PEEK(44)=$20): SYS 8225 = program_start, which
; switches the machine to C64 memory mode, DMAs the game down to $0801, resets
; the C64 KERNAL and runs it. C64 mode loads it at $0801 (PEEK(44)=8): SYS 2081
; = program_start - $1800, which copies the game down with plain 6502 code
; (no MEGA65 opcodes on that path — it must run on a real 6510) and runs it.

GAME_ENTRY = 2061           ; the exomizer sfx stub's SYS address
C64_SHIFT  = $1800          ; $2001 (assembled) - $0801 (C64 mode load address)

basic_header
	;; Auto-detect C64/C65 mode and either way jump into the assembly
	!byte 0x1f,0x20,0xe4,0x07,0x8b,0xc2,0x28,0x34,0x34,0x29,0xb2
	!byte 0x38,0xa7,0x9e
	!pet "2081"
	!byte 0x3a,0xd5,0xfe,0x02,0x30,0x3a,0x9e
	!pet "8225"
	!byte 0x00,0x00,0x00

program_start
!if program_start != 8225 { !error "program_start must be at 8225 (the SYS in the BASIC line)" }
	sei
	;; Both paths enter here: only position-independent 6502 code until
	;; the mode is known
	lda 44
	cmp #$08
	bne in_c65_mode

	;; C64 mode (C64, or MEGA65 in C64 mode): copy the C64 copier to the
	;; tape buffer, out of the way of the copy
	ldx #c64_transfer_end-c64_transfer-1
c64cp	lda c64_transfer-C64_SHIFT,x
	sta $0380,x
	dex
	bpl c64cp
	jmp $0380

in_c65_mode
	;; Set the memory mode to that of the C64
	lda #$37
	sta $01
	lda #0
	tax
	tay
	taz
	map
	eom

	;; Enable fast CPU for quick depack
	lda #65
	sta 0
	;; Enable IO for DMA
	lda #$47
	sta $d02f
	lda #$53
	sta $d02f

	;; Copy a helper routine to $0380 that DMAs the memory down.
	ldx #$7f
c65cp	lda transfer_routine,x
	sta $0380,x
	dex
	bpl c65cp
	jmp $0380

transfer_routine
	!pseudopc $0380 {

	;; Source MSB of the DMA job: $20 in C65 mode
	lda 44
	asl
	asl
	sec
	sbc 44
	sta $fd
	lda #$20
	sec
	sbc $fd
	sta dmalist_dst_msb

	;; Set 45/46 for C64 mode from C65 mode end of BASIC marker
	lda 44
	bne t_skip
	lda $82
	sta 45
	lda $83
	sta 46
	lda #$01
	sta 43
	lda #$08
	sta 44
t_skip
	;; Do transfer
	lda #0
	sta $0800 		; and clear $0800 if coming from C65 mode
	sta $d702
	lda #>dmalist
	sta $d701
	lda #<dmalist
	sta $d705

	;; Back to 1 MHz: the game is timed by the raster IRQ, but not all of it
	lda #64
	sta 0
	;; Leave the C65's video modes (80 columns, V400, fast, VIC-IV extras)
	;; and lock the VIC back to VIC-II mode before the KERNAL screen init
	lda #0
	sta $d031
	sta $d054
	sta $d02f

	;; Reset C64 mode KERNAL stuff
	jsr $fda3 ; init I/O
	jsr $fd15 ; set I/O vectors
	lda #>$0400 		; Make sure screen memory set to sensible location
	sta $0288		; before we call screen init $FF5B
	jsr $ff5b ; more init
	jsr $f7a9 ; C65 DOS reinit

	;; Enter programme
	jmp GAME_ENTRY

dmalist
	;; F011A job, source and dest in 1st MB
	!byte $0A,$80,$00,$81,$00,$00
	;; Single copy of $DFFF bytes
	!byte $00,$FF,$DF
	;; From 2 bytes past end of the wrapper, to skip wrapper and load address
	;; of the relocated programme
	!byte 2+<end_of_wrapper
dmalist_dst_msb
	!byte $20,$00
	;; To $0801
	!byte $01,$08,$00
	;; No modulo
	!byte 0,0

	}
transfer_routine_end
!if transfer_routine_end - transfer_routine > $80 { !error "transfer_routine is longer than the $80 bytes copied" }

c64_transfer
	!pseudopc $0380 {
	;; Plain 6502: copy from just past the appended PRG's load address up to
	;; the end of the load ($2D/$2E) down to $0801. The destination is below
	;; the source, so a forward copy is safe.
	lda #<(end_of_wrapper+2-C64_SHIFT)
	sta $fb
	lda #>(end_of_wrapper+2-C64_SHIFT)
	sta $fc
	lda #$01
	sta $fd
	lda #$08
	sta $fe
	ldy #0
c64_loop
	lda ($fb),y
	sta ($fd),y
	inc $fb
	bne c64_l1
	inc $fc
c64_l1	inc $fd
	bne c64_l2
	inc $fe
c64_l2	lda $fb
	cmp 45
	bne c64_loop
	lda $fc
	cmp 46
	bne c64_loop
	cli
	jmp GAME_ENTRY
	}
c64_transfer_end

end_of_wrapper
!if end_of_wrapper + 2 >= $2100 { !error "the DMA source low byte assumes the wrapper ends below $20FE" }
